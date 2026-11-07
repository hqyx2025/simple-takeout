"""Validate this run's Surefire reports and retain a machine-readable summary (no credentials)."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET


def collect(root, since=None):
    modules = []
    for name in ("takeout-common", "takeout-app", "takeout-gateway", "takeout-erp"):
        files = sorted((root / "server" / name / "target" / "surefire-reports").glob("TEST-*.xml"))
        if since is not None:
            files = [path for path in files if path.stat().st_mtime >= since]
        counts = dict(tests=0, failures=0, errors=0, skipped=0)
        for path in files:
            suite = ET.parse(path).getroot()
            for key in counts:
                counts[key] += int(suite.get(key, 0))
        modules.append(dict(module=name, reports=len(files), **counts))
    return modules


def evaluate(modules, allow_skipped=False):
    totals = {key: sum(module[key] for module in modules) for key in ("tests", "failures", "errors", "skipped")}
    totals["passed"] = totals["tests"] - totals["failures"] - totals["errors"] - totals["skipped"]
    valid = all(module["reports"] for module in modules) and totals["tests"] > 0 and not totals["failures"] and not totals["errors"]
    return bool(valid and (allow_skipped or not totals["skipped"])), totals


def read_coverage(root, since=None):
    report = root / "server/takeout-coverage/target/site/jacoco-aggregate/jacoco.xml"
    if not report.exists() or (since is not None and report.stat().st_mtime < since):
        return None
    counter = next((item for item in ET.parse(report).getroot().findall("counter") if item.get("type") == "LINE"), None)
    if counter is None:
        return None
    covered, missed = int(counter.get("covered")), int(counter.get("missed"))
    return dict(covered=covered, missed=missed, ratio=covered / (covered + missed) if covered + missed else 0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    parser.add_argument("--since", type=float, help="Unix seconds captured immediately before Maven starts; excludes stale reports")
    parser.add_argument("--allow-skipped", action="store_true", help="Report environment skips explicitly; CI never uses this")
    parser.add_argument("--minimum-line-coverage", type=float, help="Require the aggregate JaCoCo line ratio, e.g. 0.70")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    modules = collect(root, args.since)
    valid, totals = evaluate(modules, args.allow_skipped)
    coverage = read_coverage(root, args.since)
    if args.minimum_line_coverage is not None:
        if not 0 <= args.minimum_line_coverage <= 1:
            parser.error("minimum line coverage must be between zero and one")
        valid = valid and coverage is not None and coverage["ratio"] >= args.minimum_line_coverage
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    # Hash the source tree, including new source files, without reading ignored private configuration.
    tracked = subprocess.check_output(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=root)
    paths = sorted(set(item.decode("utf-8") for item in tracked.split(b"\0") if item))
    hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in paths
              if (root / name).is_file() and name.startswith(("server/", "entry/", "scripts/", ".github/", "AppScope/",
                                                            "hvigor/", "docker-compose", "build-profile", "oh-package", ".env.example"))}
    evidence = dict(recorded_at=datetime.now(timezone.utc).isoformat(), revision=revision, since=args.since,
                    valid=bool(valid), totals=totals, modules=modules, coverage=coverage, source_sha256=hashes)
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(dict(valid=bool(valid), **totals), ensure_ascii=False))
    return 0 if valid else 1


if __name__ == "__main__":
    raise SystemExit(main())
