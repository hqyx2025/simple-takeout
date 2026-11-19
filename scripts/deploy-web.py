"""Package web/ or publish it over the existing SSH connection, without a Java build.

Run from any directory: python scripts/deploy-web.py [--package-only] [--host hqyx-cloud]
The server must first have server/docker/takeout-web.conf installed in Nginx.
"""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
from datetime import datetime, timezone
import urllib.error
import urllib.request


def sha(data):
    return hashlib.sha256(data).hexdigest()


def activate(bundle, expected):
    import fcntl
    with open('/run/lock/takeout-deploy.lock', 'a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        archive = Path(bundle)
        assert sha(archive.read_bytes()) == expected, 'Upload hash mismatch'
        base = Path('/var/www/takeout')
        releases = base / 'releases'
        releases.mkdir(mode=0o755, exist_ok=True)
        release = Path(tempfile.mkdtemp(prefix='web-', dir=releases))
        release.chmod(0o755)
        with tarfile.open(archive) as tar:
            for item in tar.getmembers():
                assert item.isfile() and not Path(item.name).is_absolute()
                assert '..' not in Path(item.name).parts
            tar.extractall(release, filter='data')
        manifest = json.loads((release / 'manifest.json').read_text())
        files = release / 'files'
        files.chmod(0o755)
        actual = {p.relative_to(files).as_posix(): sha(p.read_bytes()) for p in files.rglob('*') if p.is_file()}
        assert actual == manifest['files'] and 'index.html' in actual, 'Release contents mismatch'
        for item in files.rglob('*'):
            item.chmod(0o755 if item.is_dir() else 0o644)
        link = base / 'web-current'
        previous = link.resolve() if link.is_symlink() else None
        assert not link.exists() or link.is_symlink(), 'web-current must be a symlink'

        def point(target):
            temporary = base / '.web-current-next'
            temporary.unlink(missing_ok=True)
            temporary.symlink_to(target)
            os.replace(temporary, link)

        def containers():
            names = ['simple-takeout-demo-app-1', 'simple-takeout-demo-erp-1', 'takeout-gateway', 'personal-blog']
            details = json.loads(subprocess.check_output(['docker', 'inspect', *names], text=True))
            return {item['Name']: {'id': item['Id'], 'startedAt': item['State']['StartedAt']} for item in details}

        before = containers()
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        checks = []
        try:
            point(files)
            for name, digest in actual.items():
                path = '/takeout/' + ('' if name == 'index.html' else name)
                with opener.open(urllib.request.Request('https://hqyx.website' + path,
                                  headers={'Cache-Control': 'no-cache'}), timeout=30) as response:
                    assert response.status == 200 and sha(response.read()) == digest, 'Public content mismatch: ' + name
                    assert response.headers.get('X-Takeout-Web') == 'independent', 'Static request still reaches gateway'
                    assert response.headers.get('Cache-Control') == 'no-cache', 'Stale browser cache policy'
                checks.append({'path': path, 'status': 200, 'sha256': digest})
            for path, status in [('/takeout/health', 200), ('/takeout/api/stores', 200),
                                 ('/takeout/api/erp/stores/1/materials', 401),
                                 ('/takeout/actuator/prometheus', 404),
                                 ('/takeout/api/internal/erp/context?storeId=1', 404)]:
                try:
                    response = opener.open('https://hqyx.website' + path, timeout=30)
                except urllib.error.HTTPError as error:
                    response = error
                with response:
                    assert response.status == status, 'Route failed: ' + path
                    body = response.read()
                    if path == '/takeout/api/stores':
                        payload = json.loads(body)
                        assert payload.get('code') == 200 and isinstance(payload.get('data'), list), 'Store directory body is incomplete'
                checks.append({'path': path, 'status': status})
            assert containers() == before, 'Business container changed during web publication'
        except Exception:
            if previous:
                point(previous)
            else:
                link.unlink(missing_ok=True)
            raise
        finally:
            archive.unlink(missing_ok=True)
        result = {'release': release.name, 'source': manifest, 'checks': checks,
                  'containersUnchanged': True, 'containers': before,
                  'previous': str(previous) if previous else None,
                  'publishedAt': datetime.now(timezone.utc).isoformat()}
        (release / 'deployment.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
        print(json.dumps(result, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package-only', action='store_true')
    parser.add_argument('--host', default='hqyx-cloud')
    parser.add_argument('--activate', help=argparse.SUPPRESS)
    parser.add_argument('--sha256', help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.activate:
        activate(args.activate, args.sha256)
        return
    root = Path(__file__).resolve().parent.parent
    files = {p.relative_to(root / 'web').as_posix(): p.read_bytes()
             for p in sorted((root / 'web').rglob('*')) if p.is_file()}
    assert 'index.html' in files and not any(part.startswith('.') for name in files for part in Path(name).parts)
    manifest = {'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
                'files': {name: sha(data) for name, data in files.items()}}
    output = root / 'TemporaryCacheStorage' / datetime.now(timezone.utc).strftime('web-%Y%m%dT%H%M%S%fZ')
    output.mkdir(parents=True)
    bundle = output / 'web.tar.gz'
    with tarfile.open(bundle, 'w:gz') as tar:
        for name, data in {'manifest.json': json.dumps(manifest, indent=2).encode(),
                           **{'files/' + name: data for name, data in files.items()}}.items():
            item = tarfile.TarInfo(name)
            item.size = len(data)
            item.mode = 0o644
            tar.addfile(item, io.BytesIO(data))
    (output / 'source.diff').write_bytes(subprocess.check_output(['git', 'diff', 'HEAD', '--', 'web', 'scripts', 'server/docker'], cwd=root))
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    if args.package_only:
        print(json.dumps({'bundle': str(bundle), 'sha256': sha(bundle.read_bytes()), 'files': len(files)}))
        return
    remote = '/tmp/takeout-' + output.name + '.tar.gz'
    subprocess.run(['scp', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', str(bundle), args.host + ':' + remote], check=True)
    result = subprocess.run(['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', args.host,
                             'python3', '-', '--activate', remote, '--sha256', sha(bundle.read_bytes())],
                            input=Path(__file__).read_bytes(), capture_output=True)
    (output / 'deploy.log').write_bytes(result.stdout + result.stderr)
    if result.returncode:
        sys.stderr.buffer.write(result.stderr)
        raise SystemExit(result.returncode)
    (output / 'deployment.json').write_bytes(result.stdout)
    print(json.dumps({'evidence': str(output / 'deployment.json'), 'bundle': str(bundle),
                      'containersUnchanged': json.loads(result.stdout)['containersUnchanged']}))


if __name__ == '__main__':
    main()
