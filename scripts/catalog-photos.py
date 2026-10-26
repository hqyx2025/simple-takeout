"""Download attributed catalog photos and replace only known demo placeholders.

Run download, then apply on each database host (--cloud uses Docker MySQL).
Copy server/catalog-photos/catalog-photos-v1 to the server's uploads directory
before applying there. No application restart is needed.
"""
import argparse
import concurrent.futures
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import urllib.request
from datetime import datetime

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / 'server/catalog-photos/catalog-photos-v1'
PREFIX = '/uploads/catalog-photos-v1/'
LEGACY_CUISINES = [1,3,5,2,3,5,7,6,4,2,7,1,1,1,1,5,3,3,3,3,2,2,2,2,2,1,7,7,7,7,1,2,6,7,4,2,2,8,6,2]
spec = importlib.util.spec_from_file_location('seed_catalog', ROOT / 'scripts/seed-demo-catalog.py')
seed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(seed)


def manifest():
    result = json.loads((ASSETS / 'manifest.json').read_text(encoding='utf-8'))
    assert result['version'] == 1
    for photo in result['photos']:
        assert Path(photo['file']).name == photo['file'] and photo['file'].endswith('.jpg')
        assert photo['source'].startswith('https://') and photo['licenseUrl'].startswith('https://')
    return result


def download_photo(photo):
    target = ASSETS / photo['file']
    if target.exists() and hashlib.sha256(target.read_bytes()).hexdigest() == photo['sha256']:
        return
    request = urllib.request.Request(photo['download'], headers={'User-Agent': 'SimpleTakeoutCatalog/1.0 (https://hqyx.website)'})
    with urllib.request.urlopen(request, timeout=60) as response:
        assert response.headers.get_content_type().startswith('image/')
        data = response.read(12 * 1024 * 1024 + 1)
    assert len(data) <= 12 * 1024 * 1024 and data.startswith(b'\xff\xd8')
    assert hashlib.sha256(data).hexdigest() == photo['sha256'], 'Source changed; review photo before replacing it'
    target.write_bytes(data)


def validate_assets(data):
    files = {p['file'] for p in data['photos']}
    assert len(files) == len(data['photos'])
    for photo in data['photos']:
        raw = (ASSETS / photo['file']).read_bytes()
        assert raw.startswith(b'\xff\xd8') and hashlib.sha256(raw).hexdigest() == photo['sha256']
    assert len(data['storeImages']) == 8
    assert all(name in files for name in data['goodsImages'].values())
    assert all(name in files for name in data['storeImages'].values())


def rows(database, table, columns):
    fields = ','.join(f"'{c}',`{c}`" for c in columns)
    return [json.loads(line) for line in database.run(f'SELECT JSON_OBJECT({fields}) FROM `{table}` ORDER BY id;').splitlines() if line]


def updates(database, data):
    stores = rows(database, 'stores', ['id','name','category_id','image','notice'])
    goods = rows(database, 'goods', ['id','store_id','name','image','description'])
    meals = rows(database, 'setmeals', ['id','store_id','image'])
    cuisines = {}
    changes = []
    def change(table, row, values):
        if all(row[key] == value for key,value in values.items()):
            return
        changes.append(dict(table=table,id=row['id'],before={k:row[k] for k in values},after=values))
    def placeholder(row):
        return not row['image'] or row['image'].startswith('/uploads/demo-catalog-500-v1/cuisine-')
    for row in stores:
        sid = row['id']
        if 1 <= sid <= 40:
            cuisine = LEGACY_CUISINES[sid-1]
        elif 670000001 <= sid <= 670000500 and 'demo-catalog-500-v1' in (row['notice'] or ''):
            cuisine = row['category_id']
        else:
            continue
        cuisines[sid] = cuisine
        if placeholder(row):
            notice = (row['notice'] or '') + ' 配图为同类门店环境参考，非本店实景。'
            change('stores',row,dict(image=PREFIX+data['storeImages'][str(cuisine)],notice=notice.strip()))
    for row in goods:
        sid = row['store_id']
        if sid not in cuisines or not placeholder(row):
            continue
        if not (1 <= row['id'] <= 1200 or 671000000 <= row['id'] < 671011000):
            continue
        cuisine = cuisines[sid]
        file = data['goodsImages'].get(row['name'])
        if file is None and sid <= 40:
            # Legacy seeds have generic names; keep their photos within the store's cuisine.
            item = 10 if row['name']=='时令饮品' else (8 if row['name']=='人气小吃' else 0)
            file = data['goodsImages'][seed.MENUS[cuisine-1][item][0]]
        if file:
            description = (row['description'] or '').replace('配图为品类插画。','').strip()
            description += ' 配图为同类菜品参考实拍，实际出品以商户为准。'
            change('goods',row,dict(image=PREFIX+file,description=description.strip()))
    for row in meals:
        if row['store_id'] in cuisines and placeholder(row) and (row['id']==1 or 677000001<=row['id']<=677000500):
            cuisine = cuisines[row['store_id']]
            title = seed.MENUS[cuisine-1][4][0]
            file = data['goodsImages'].get(title) or data['goodsImages'][seed.MENUS[cuisine-1][0][0]]
            change('setmeals',row,dict(image=PREFIX+file))
    return changes


def update_sql(changes, rollback=False):
    statements = ['SET NAMES utf8mb4;','START TRANSACTION;']
    for row in changes:
        old,new = (row['after'],row['before']) if rollback else (row['before'],row['after'])
        assignments = ','.join(f'`{key}`={seed.literal(value)}' for key,value in new.items())
        conditions = ' AND '.join(f'`{key}` <=> {seed.literal(value)}' for key,value in old.items())
        statements.append(f"UPDATE `{row['table']}` SET {assignments} WHERE id={row['id']} AND {conditions};")
    return '\n'.join(statements+['COMMIT;'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['download','apply','verify','self-test'])
    parser.add_argument('--cloud',action='store_true')
    parser.add_argument('--local-config')
    parser.add_argument('--upload-dir',type=Path,default=ROOT/'server/uploads')
    parser.add_argument('--backup-dir',type=Path,default=ROOT/'TemporaryCacheStorage/catalog-photos-backups')
    args = parser.parse_args()
    data = manifest()
    if args.action=='download':
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
            list(executor.map(download_photo,data['photos']))
    validate_assets(data)
    if args.action in ['download','self-test']:
        sample=[dict(table='stores',id=1,before={'image':None},after={'image':PREFIX+'store-1.jpg'})]
        sql=update_sql(sample)
        assert '<=> NULL' in sql and sql.endswith('COMMIT;') and 'DELETE' not in sql
        assert 'SET `image`=NULL' in update_sql(sample,True)
        assert set(data['goodsImages']) | set(data['unmatchedGoods']) == {item[0] for menu in seed.MENUS for item in menu}
        class Fixture:
            def run(self,sql):
                if 'FROM `stores`' in sql:
                    values=[dict(id=670000001,name='演示店',category_id=1,image='/uploads/demo-catalog-500-v1/cuisine-1.svg',notice='demo-catalog-500-v1'),dict(id=9001,name='真实店',category_id=1,image='',notice='')]
                elif 'FROM `goods`' in sql:
                    values=[dict(id=671000020,store_id=670000001,name='南宁老友粉',image='',description='演示菜单；配图为品类插画。'),dict(id=671000021,store_id=670000001,name='经典螺蛳粉',image='/uploads/merchant-photo.jpg',description='商户上传'),dict(id=671000022,store_id=670000001,name='虾滑拼盘',image='',description='')]
                else:
                    values=[]
                return '\n'.join(json.dumps(row,ensure_ascii=False) for row in values)
        planned=updates(Fixture(),data)
        assert [(r['table'],r['id']) for r in planned]==[('stores',670000001),('goods',671000020)]
        assert '品类插画' not in planned[1]['after']['description']
        print(f"PASS: {len(data['photos'])} attributed JPEGs, complete menu mapping, checksums and conditional transaction SQL")
        return
    database = seed.Database(args)
    if args.action=='verify':
        assert not updates(database,data), 'Placeholder images remain'
        print('PASS: all eligible catalog images are assigned')
        return
    args.upload_dir.mkdir(parents=True,exist_ok=True)
    target=args.upload_dir/ASSETS.name
    shutil.copytree(ASSETS,target,dirs_exist_ok=True)
    for photo in data['photos']:
        assert hashlib.sha256((target/photo['file']).read_bytes()).hexdigest()==photo['sha256']
    changes=updates(database,data)
    if not changes:
        print('Already applied; no database changes')
        return
    args.backup_dir.mkdir(parents=True,exist_ok=True)
    backup=args.backup_dir/f"images-before-{datetime.now():%Y%m%d-%H%M%S}"
    backup.with_suffix('.json').write_text(json.dumps(changes,ensure_ascii=False,indent=2),encoding='utf-8')
    backup.with_suffix('.sql').write_text(update_sql(changes,True),encoding='utf-8')
    os.chmod(backup.with_suffix('.json'),0o600)
    os.chmod(backup.with_suffix('.sql'),0o600)
    database.run(update_sql(changes))
    for table in ['stores','goods','setmeals']:
        expected={r['id']:r['after'] for r in changes if r['table']==table}
        if expected:
            actual={r['id']:r for r in rows(database,table,['id']+list(next(iter(expected.values()))))}
            assert all(all(actual[i][k]==v for k,v in values.items()) for i,values in expected.items()), 'Concurrent change detected; review backup'
    assert not updates(database,data)
    print(json.dumps({'updated':{t:sum(r['table']==t for r in changes) for t in ['stores','goods','setmeals']},'backup':str(backup)},ensure_ascii=False))


if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')
    main()
