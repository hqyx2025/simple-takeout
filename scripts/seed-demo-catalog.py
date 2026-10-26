"""Build and import the same additive demonstration catalog on local/cloud MySQL."""
import argparse
import gzip
import hashlib
import json
import math
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from xml.sax.saxutils import escape

BATCH = 'demo-catalog-500-v1'
ROOT = Path(__file__).resolve().parent.parent
CATEGORY_NAMES = ['美食','快餐','饮品','甜品','火锅','烧烤','面食','寿司']
BRANDS = [
    ['桂味小厨','老街粉铺','邕城家常菜','青禾食堂','阿婆米粉','巷口饭香'],
    ['一碗好饭','米粒便当','暖心小炒','麦香炸鸡','好味盖饭','饭点厨房'],
    ['青柠茶事','一杯春天','山野果茶','午后咖啡','鲜果小站','巷尾茶铺'],
    ['甜心烘焙','糖间小屋','云朵甜品','麦田蛋糕','一口香甜','果香布丁'],
    ['鲜煮小锅','蜀香冒菜','番茄小火锅','暖锅食记','山城麻辣烫','菌香小锅'],
    ['炭火小串','夜市烤场','巷口烧烤','小院烤肉','炙味厨房','晚风串铺'],
    ['面香小馆','手作面坊','汤面研究所','一碗鲜面','北街饺子','麦香馄饨'],
    ['禾风寿司','卷卷食堂','一口饭团','海苔小屋','日和轻食','山海寿司']
]
# Name, price, description. The last two items are suitable drink accompaniments.
MENUS = [
    [('南宁老友粉',14,'酸笋、豆豉与鲜肉现煮，米粉爽滑'),('经典螺蛳粉',16,'酸笋木耳配腐竹，汤底酸辣鲜香'),('桂林卤菜米粉',13,'卤汁拌粉配花生和酸豆角'),('生榨米粉',12,'传统生榨粉配肉末与时蔬'),('柠檬鸭饭',23,'柠檬鸭配米饭和应季蔬菜'),('酸笋牛肉饭',22,'酸笋与牛肉现炒，搭配米饭'),('香菇滑鸡饭',20,'香菇鸡肉配时蔬与米饭'),('招牌叉烧饭',21,'蜜汁叉烧配米饭和清爽蔬菜'),('香酥春卷',9,'蔬菜馅春卷，酥脆小食'),('凉拌青瓜',7,'青瓜拌蒜香汁，清爽配菜'),('手打柠檬茶',9,'鲜切柠檬与茶汤调配'),('冰镇酸梅汤',6,'乌梅山楂风味饮品')],
    [('招牌黄焖鸡饭',22,'鸡肉与土豆炖煮，配一份米饭'),('黑椒牛柳饭',24,'牛柳搭配黑椒酱和时蔬'),('香煎鸡腿饭',21,'鸡腿配米饭，搭配双拼蔬菜'),('照烧鸡排饭',23,'照烧鸡排配海苔和米饭'),('番茄炒蛋饭',15,'番茄鸡蛋现炒，家常口味'),('鱼香肉丝饭',19,'肉丝配木耳胡萝卜，鲜香下饭'),('宫保鸡丁饭',20,'鸡丁花生与时蔬现炒'),('咖喱土豆鸡饭',21,'咖喱鸡肉配土豆和米饭'),('原味薯条',10,'现炸薯条，搭配番茄酱'),('蔬菜沙拉',12,'生菜黄瓜与玉米，独立酱料'),('蜂蜜柚子茶',8,'柚子风味清爽饮品'),('冰红茶',5,'清爽茶饮，独立包装')],
    [('招牌茉莉奶茶',14,'茉莉茶香配醇香鲜奶'),('杨枝甘露',20,'芒果与西米搭配椰奶'),('芝士葡萄',22,'葡萄果肉搭配芝士奶盖'),('多肉草莓',21,'草莓果肉与清新茶底'),('黑糖珍珠鲜奶',18,'黑糖珍珠搭配鲜奶'),('生椰拿铁',20,'椰乳与咖啡调配'),('冰美式',14,'咖啡萃取，口感清爽'),('燕麦拿铁',21,'燕麦饮与咖啡调配'),('百香果双响',16,'百香果与椰果珍珠组合'),('乌龙纯茶',10,'乌龙茶汤，原叶茶香'),('鲜柠檬水',7,'鲜切柠檬清爽饮品'),('青提绿茶',16,'青提风味与绿茶调配')],
    [('芒果千层',24,'芒果与奶油夹层，独立包装'),('草莓盒子蛋糕',26,'草莓果肉与轻盈奶油'),('经典提拉米苏',28,'咖啡与可可风味甜品'),('巴斯克芝士蛋糕',25,'芝士烘烤，绵密口感'),('芋泥麻薯杯',19,'芋泥与麻薯搭配'),('双皮奶',14,'奶香甜品，细腻口感'),('红豆椰汁西米露',15,'红豆、西米与椰汁组合'),('原味蛋挞双只',12,'酥皮蛋挞，两只装'),('黄油可颂',13,'黄油起酥烘焙点心'),('海盐小饼干',10,'海盐黄油风味烘焙小食'),('桂花乌龙茶',9,'桂花香与乌龙茶调配'),('鲜牛奶',8,'独立包装奶饮')],
    [('招牌麻辣烫',26,'肉丸豆制品与时蔬组合'),('番茄肥牛小锅',32,'番茄汤底配肥牛和时蔬'),('菌汤鸡肉小锅',29,'菌菇汤底配鸡肉与蔬菜'),('藤椒鱼片锅',31,'藤椒风味鱼片与配菜'),('经典冒菜双拼',28,'荤素双拼，麻辣鲜香'),('骨汤关东煮',23,'骨汤丸子豆制品组合'),('虾滑拼盘',19,'虾滑小份，适合加菜'),('牛肉丸拼盘',16,'牛肉丸配时蔬'),('手工宽粉',8,'火锅宽粉加菜'),('香软米饭',3,'独立一份米饭'),('酸梅汤',7,'乌梅风味饮品'),('凉茶',6,'清爽凉茶饮品')],
    [('孜然牛肉串',24,'牛肉炭烤，六串装'),('香辣鸡肉串',18,'鸡肉串烤，六串装'),('秘制五花肉串',22,'五花肉烤制，六串装'),('蒜香鸡翅',23,'蒜香烤鸡翅，两只装'),('烤鸡腿',16,'秘制风味鸡腿，一只装'),('香烤鱿鱼',20,'鱿鱼烤制，配孜然香料'),('烤玉米',9,'玉米现烤，一份装'),('蒜蓉烤茄子',13,'茄子配蒜蓉酱烤制'),('烤土豆片',8,'土豆片现烤，微辣口味'),('烤香菇',10,'香菇烤制，一份装'),('冰柠檬茶',8,'柠檬风味解腻茶饮'),('乌梅汁',7,'乌梅风味清爽饮品')],
    [('红烧牛肉面',23,'红烧牛肉与汤面组合'),('番茄鸡蛋面',16,'番茄鸡蛋汤底配面条'),('香菇鸡汤面',20,'鸡汤配香菇与面条'),('重庆小面',15,'麻辣小面，配花生和时蔬'),('葱油拌面',13,'葱油拌面，咸香爽口'),('武汉热干面',12,'芝麻酱拌面，配萝卜丁'),('鲜肉小馄饨',18,'鲜肉馅馄饨，清汤口味'),('韭菜猪肉水饺',22,'手工水饺，十二只装'),('白菜猪肉水饺',21,'白菜猪肉馅，十二只装'),('香卤鸡蛋',4,'卤汁鸡蛋，一只装'),('豆浆',5,'原味豆浆饮品'),('酸梅汤',6,'乌梅风味解腻饮品')],
    [('招牌加州卷',26,'蟹柳黄瓜与米饭组合'),('香烤鳗鱼卷',32,'鳗鱼配海苔与米饭'),('金枪鱼沙拉卷',28,'金枪鱼沙拉与米饭组合'),('蟹柳玉子卷',24,'蟹柳玉子配海苔米饭'),('三色蔬菜卷',18,'黄瓜胡萝卜与蔬菜组合'),('照烧鸡肉饭团',16,'照烧鸡肉馅饭团，两只装'),('玉子烧',14,'鸡蛋煎制，独立一份'),('海苔肉松饭团',15,'海苔肉松饭团，两只装'),('日式土豆沙拉',12,'土豆配胡萝卜沙拉'),('味噌汤',8,'味噌汤与豆腐海带组合'),('玄米茶',7,'玄米风味茶饮'),('蜜桃乌龙茶',9,'蜜桃风味与乌龙茶调配')]
]
TABLES = ['users','categories','stores','goods','goods_specs','marketing_activities','seckills','setmeals','setmeal_items']
IDENTITY = {'users':['username','phone','role'], 'categories':['name','type','merchant_id'], 'stores':['name','owner_id','notice'], 'goods':['name','store_id'], 'goods_specs':['goods_id','name'], 'marketing_activities':['store_id','title'], 'seckills':['store_id','goods_id'], 'setmeals':['store_id','name'], 'setmeal_items':['setmeal_id','goods_id']}

def canonical(value):
    if isinstance(value,dict): return {k:canonical(v) for k,v in sorted(value.items())}
    if isinstance(value,list): return [canonical(v) for v in value]
    if isinstance(value,(int,float,Decimal)): return format(Decimal(str(value)).normalize(),'f')
    if isinstance(value,str) and re.fullmatch(r'\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.0{1,6}',value): return value.split('.')[0]
    return value

def fingerprint(value):
    return hashlib.sha256(json.dumps(canonical(value),ensure_ascii=False,separators=(',',':')).encode()).hexdigest()

def build(anchors):
    assert sum(a['count'] for a in anchors)==500 and len(anchors)==14
    now=datetime.now(timezone(timedelta(hours=8))).replace(tzinfo=None,microsecond=0)
    start=now.strftime('%Y-%m-%d %H:%M:%S'); end=(now+timedelta(days=365)).strftime('%Y-%m-%d %H:%M:%S')
    tables={table:[] for table in TABLES}; number=0
    for region,a in enumerate(anchors,1):
        owner=674000000+region
        tables['users'].append(dict(id=owner,username='演示店主-'+a['label'],avatar='',phone=f'demo500-{region:02}',password='!'+BATCH,role=1,status=0,balance=0,create_time=start,password_changed_at=''))
        category_ids=[]
        for sort,name in enumerate(['招牌热销','人气主食','特色小吃','解腻饮品']):
            cid=673000000+(region-1)*4+sort+1;category_ids.append(cid)
            tables['categories'].append(dict(id=cid,name=name,icon='',color='#E65D2F',type='MERCHANT',merchant_id=owner,sort=sort,status=1,deleted=0))
        for index in range(a['count']):
            number+=1; cuisine=(index+region-1)%8; menu=MENUS[cuisine]
            angle=index*2.399963229728653; distance=100+1100*math.sqrt((index+0.5)/a['count'])
            latitude=round(a['latitude']+distance*math.cos(angle)/111320,7)
            longitude=round(a['longitude']+distance*math.sin(angle)/(111320*math.cos(math.radians(a['latitude']))),7)
            store=670000000+number; cover=f'/uploads/{BATCH}/cuisine-{cuisine+1}.svg'
            name=BRANDS[cuisine][(index//8)%6]+f'（演示·{a["label"]}{index+1:03}店）'
            tables['stores'].append(dict(id=store,name=name,image=cover,rating=4.5,monthly_sales=0,delivery_fee=round(1.5+(index%4)*0.5,2),min_order=10,delivery_time=f'{20+index%5*5}分钟',distance='未知距离',tags=json.dumps(['演示店铺',CATEGORY_NAMES[cuisine],'可选规格'],ensure_ascii=False,separators=(',',':')),notice=f'【演示数据】用于点餐与配送流程体验，店名、菜单及商圈点位为示例。批次：{BATCH}',address=a['address']+f'周边（演示点位{region:02}-{index+1:03}）',latitude=latitude,longitude=longitude,delivery_radius=5000,category_id=cuisine+1,category_ids=json.dumps([1] if cuisine==0 else [1,cuisine+1],separators=(',',':')),owner_id=owner,status=1,recommended=1,create_time=start))
            goods=[]
            for item,(title,price,description) in enumerate(menu):
                gid=671000000+number*20+item;goods.append(gid)
                price=round(price+(index%3)*0.5,2);stock=120 if item<4 else 80+index%5*20
                tables['goods'].append(dict(id=gid,store_id=store,name=title,description=f'{description}。演示菜单；配图为品类插画。',price=price,original_price=price+3 if item<2 else price,image=cover,category_id=cuisine+1,merchant_category_id=category_ids[0 if item<4 else 1 if item<8 else 2 if item<10 else 3],stock=stock,version=0,sales=0,rating=4.5,tag='招牌' if item<2 else '',is_special=int(item<2),status=1,deleted=0,create_time=start))
                if item<4:
                    for variant,(label,extra,qty) in enumerate([('中杯',0,50),('大杯',3,70)] if cuisine==2 else [('标准份',0,50),('加量份',5,70)]):
                        tables['goods_specs'].append(dict(id=672000000+number*10+item*2+variant,goods_id=gid,name=label,price=price+extra,stock=qty,version=0,sort=variant,status=1,create_time=start))
            tables['marketing_activities'].append(dict(id=675000000+number,store_id=store,type='NEW_USER',title='演示新客满25减3',discount_rate=0,reduce_amount=3,threshold=25,gift_goods_id=0,start_time=start,end_time=end,status=1,create_time=start,start_time_dt=start,end_time_dt=end,create_time_dt=start))
            if number%5==0:
                tables['seckills'].append(dict(id=676000000+number,goods_id=goods[4],store_id=store,price=max(1,menu[4][1]-4),quota=20,sold=0,start_time=start,end_time=end,status=1,create_time=start,start_time_dt=start,end_time_dt=end,create_time_dt=start))
            meal=677000000+number;original=round(menu[4][1]+menu[10][1]+2*(index%3)*0.5,2)
            tables['setmeals'].append(dict(id=meal,store_id=store,name='双品搭配套餐',description=f'{menu[4][0]} + {menu[10][0]}，演示组合套餐',price=max(1,original-3),original_price=original,image=cover,status=1,create_time=start))
            for part,item in enumerate([4,10]):
                tables['setmeal_items'].append(dict(id=678000000+number*2+part,setmeal_id=meal,goods_id=goods[item],goods_name=menu[item][0],quantity=1))
    result=dict(batch=BATCH,coordinate_system='GCJ02',created_at=start,anchors=anchors,tables=tables)
    result['sha256']=fingerprint(tables)
    validate(result)
    return result

def validate(catalog):
    tables=catalog['tables']
    expected={'users':14,'categories':56,'stores':500,'goods':6000,'goods_specs':4000,'marketing_activities':500,'seckills':100,'setmeals':500,'setmeal_items':1000}
    assert {t:len(rows) for t,rows in tables.items()}==expected
    for rows in tables.values(): assert len({r['id'] for r in rows})==len(rows)
    stores={r['id']:r for r in tables['stores']};goods={r['id']:r for r in tables['goods']};users={r['id']:r for r in tables['users']}
    categories={r['id']:r for r in tables['categories']};meals={r['id']:r for r in tables['setmeals']}
    assert all(s['owner_id'] in users and s['recommended']==1 and s['status']==1 for s in stores.values())
    assert all(users[g['owner_id']]['status']==0 for g in stores.values())
    for g in goods.values():
        assert g['store_id'] in stores and categories[g['merchant_category_id']]['merchant_id']==stores[g['store_id']]['owner_id']
        specs=[s for s in tables['goods_specs'] if s['goods_id']==g['id']]
        if specs: assert g['stock']==sum(s['stock'] for s in specs) and g['price']==min(s['price'] for s in specs)
        assert g['price']>0 and g['original_price']>=g['price']
    for row in tables['setmeal_items']: assert goods[row['goods_id']]['store_id']==meals[row['setmeal_id']]['store_id']
    for row in tables['seckills']: assert goods[row['goods_id']]['store_id']==row['store_id'] and row['price']<=goods[row['goods_id']]['price']
    assert fingerprint(tables)==catalog['sha256']

def covers(directory):
    directory.mkdir(parents=True,exist_ok=True)
    colors=['#B96D3C','#BD7639','#6D8C68','#BA8290','#B95D45','#9A633F','#AF8C54','#63877B']
    for index,(name,color) in enumerate(zip(CATEGORY_NAMES,colors),1):
        drawing='<path d="M210 113h92l-12 114h-68zM256 72l-9 48M227 153h58"/>' if index==3 else '<path d="M178 158h156c-9 47-35 68-78 68s-69-21-78-68zM196 242h120M224 126c-19-21 19-24 0-47M257 126c-19-21 19-24 0-47M290 126c-19-21 19-24 0-47"/>'
        svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="512" height="320" viewBox="0 0 512 320"><rect width="512" height="320" fill="#FFF7ED"/><circle cx="256" cy="156" r="113" fill="{color}" opacity=".1"/><g fill="none" stroke="{color}" stroke-width="5" stroke-linecap="round" stroke-linejoin="round">{drawing}</g><text x="256" y="282" text-anchor="middle" font-family="sans-serif" font-size="22" fill="{color}">{escape(name)} · 演示菜单</text></svg>'
        (directory/f'cuisine-{index}.svg').write_text(svg,encoding='utf-8')

def envfile(path):
    result={}
    for line in path.read_text(encoding='utf-8-sig').splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            key,value=line.split('=',1);result[key.strip()]=value.strip().strip('\"\'')
    return result

class Database:
    def __init__(self,args):
        self.cloud=args.cloud;self.env=os.environ.copy()
        if self.cloud:
            self.base=['docker','exec','-i','takeout-mysql','sh','-c']
            self.name='takeout';self.client=[]
        else:
            cfg=envfile(ROOT/'.env') if (ROOT/'.env').exists() else {}
            if args.local_config:cfg.update(envfile(Path(args.local_config)))
            cfg.update({k:v for k,v in os.environ.items() if k.startswith('TAKEOUT_DB_')})
            self.name=cfg.get('TAKEOUT_DB_NAME','takeout')
            self.client=['--protocol=TCP','--connect-timeout=5','-h',cfg.get('TAKEOUT_DB_HOST','127.0.0.1'),'-P',cfg.get('TAKEOUT_DB_PORT','3310'),'-u',cfg.get('TAKEOUT_DB_USERNAME','root')]
            self.env['MYSQL_PWD']=cfg.get('TAKEOUT_DB_PASSWORD','')
            self.mysql=shutil.which('mysql') or r'C:\Software\Application\mysql\mysql-8.4.0-winx64\bin\mysql.exe'
            self.dump=str(Path(self.mysql).with_name('mysqldump.exe' if os.name=='nt' else 'mysqldump'))

    def command(self,dump=False):
        options=['--default-character-set=utf8mb4']
        if dump:options+=['--single-transaction','--quick','--no-tablespaces','--set-gtid-purged=OFF','--column-statistics=0','--skip-add-drop-table',self.name]+TABLES
        else:options+=['--batch','--raw','--skip-column-names',self.name]
        if self.cloud:
            import shlex
            return self.base+['MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec '+('mysqldump' if dump else 'mysql')+' -uroot '+shlex.join(options)]
        return [self.dump if dump else self.mysql]+self.client+options

    def run(self,sql):
        result=subprocess.run(self.command(),input=sql,encoding='utf-8',capture_output=True,env=self.env)
        if result.returncode:raise RuntimeError(result.stderr.strip()[:600])
        return result.stdout

    def rows(self,table,expected):
        cols=list(expected[0]); output=[]
        for start in range(0,len(expected),300):
            ids=','.join(str(r['id']) for r in expected[start:start+300]); fields=','.join(f"'{c}',`{c}`" for c in cols)
            result=self.run(f'SELECT JSON_OBJECT({fields}) FROM `{table}` WHERE id IN ({ids}) ORDER BY id;')
            output.extend(json.loads(line) for line in result.splitlines() if line)
        return sorted(output,key=lambda r:r['id'])

    def preflight(self,catalog):
        platform=self.run("SELECT id,name FROM categories WHERE type='PLATFORM' AND deleted=0 ORDER BY id;")
        current={int(line.split('\t')[0]):line.split('\t')[1] for line in platform.splitlines()}
        assert all(current.get(i+1)==name for i,name in enumerate(CATEGORY_NAMES)), 'Platform category IDs differ; do not import without mapping.'
        engines=self.run('SELECT table_name,engine FROM information_schema.tables WHERE table_schema=DATABASE();')
        actual=dict(line.split('\t') for line in engines.splitlines())
        assert all(actual.get(t)=='InnoDB' for t in TABLES), 'All target tables must use InnoDB.'
        for table,expected in catalog['tables'].items():
            by_id={r['id']:r for r in expected}
            for row in self.rows(table,expected):
                assert all(row[key]==by_id[row['id']][key] for key in IDENTITY[table]), f'ID collision in {table}: {row["id"]}'
        phones=','.join(literal(r['phone']) for r in catalog['tables']['users']);names=','.join(literal(r['username']) for r in catalog['tables']['users'])
        existing=self.run(f'SELECT id FROM users WHERE phone IN ({phones}) OR username IN ({names});')
        assert all(int(value) in {r['id'] for r in catalog['tables']['users']} for value in existing.splitlines()), 'Demo merchant identity collision.'
        print('PREFLIGHT_OK',self.name,flush=True)

    def backup(self,directory):
        directory.mkdir(parents=True,exist_ok=True)
        target=directory/f'catalog-before-{datetime.now():%Y%m%d-%H%M%S}.sql.gz'
        process=subprocess.Popen(self.command(True),stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=self.env)
        with gzip.open(target,'wb') as out:
            shutil.copyfileobj(process.stdout,out)
        error=process.stderr.read().decode('utf-8',errors='replace');code=process.wait()
        if code:target.unlink(missing_ok=True);raise RuntimeError(error[:500])
        os.chmod(target,0o600)
        print('BACKUP',target,flush=True)

    def verify(self,catalog):
        actual={t:self.rows(t,rows) for t,rows in catalog['tables'].items()}
        assert {t:len(rows) for t,rows in actual.items()}=={t:len(rows) for t,rows in catalog['tables'].items()}, 'Incomplete import.'
        digest=fingerprint(actual)
        if digest!=catalog['sha256']:
            differences=[]
            for table,rows in catalog['tables'].items():
                for expected,stored in zip(rows,actual[table]):
                    for key,value in expected.items():
                        if canonical(value)!=canonical(stored[key]):
                            differences.append(dict(table=table,id=expected['id'],column=key,expected=value,stored=stored[key]))
                            if len(differences)>=5:break
                    if len(differences)>=5:break
                if len(differences)>=5:break
            raise RuntimeError('Stored catalog differs: '+json.dumps(differences,ensure_ascii=False))
        print(json.dumps({'database':self.name,'counts':{t:len(rows) for t,rows in actual.items()},'sha256':digest},ensure_ascii=False),flush=True)

def literal(value):
    if value is None:return 'NULL'
    if isinstance(value,(int,float)):
        assert math.isfinite(value);return str(value)
    return "CONVERT(X'"+str(value).encode('utf-8').hex()+"' USING utf8mb4)"

def sql_for(catalog):
    statements=['SET NAMES utf8mb4;','START TRANSACTION;']
    for table,rows in catalog['tables'].items():
        columns=list(rows[0]);names=','.join(f'`{column}`' for column in columns)
        for start in range(0,len(rows),200):
            values=','.join('('+','.join(literal(row[column]) for column in columns)+')' for row in rows[start:start+200])
            statements.append(f'INSERT INTO `{table}` ({names}) VALUES {values} ON DUPLICATE KEY UPDATE id=id;')
    return '\n'.join(statements+['COMMIT;'])

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['build','self-test','preflight','apply','verify'])
    parser.add_argument('--anchors',type=Path)
    parser.add_argument('--catalog',type=Path,default=ROOT/'TemporaryCacheStorage/demo-catalog-500/catalog.json')
    parser.add_argument('--cloud','--docker',dest='cloud',action='store_true',help='Use the takeout-mysql Docker container on the current host')
    parser.add_argument('--local-config')
    parser.add_argument('--backup-dir',type=Path,default=ROOT/'TemporaryCacheStorage/demo-catalog-500/backups')
    args=parser.parse_args()
    if args.action=='self-test':
        counts=[160,40,30,20,20,20,10,40,30,30,30,30,20,20]
        anchors=[dict(label=f'区域{i}',count=count,latitude=22.8,longitude=108.4,address='测试区域',city='南宁市') for i,count in enumerate(counts)]
        catalog=build(anchors);assert len(catalog['tables']['stores'])==500
        assert len({s['name'] for s in catalog['tables']['stores']})==500
        for store in catalog['tables']['stores']:
            distance=111320*math.hypot(store['latitude']-22.8,(store['longitude']-108.4)*math.cos(math.radians(22.8)))
            assert 95<=distance<=1201
        sql=sql_for(catalog);assert 'DROP ' not in sql and 'DELETE ' not in sql and sql.endswith('COMMIT;')
        assert literal("'\\危险") .startswith("CONVERT(X'")
        print('PASS: 500 stores, 6000 dishes, relational integrity, SKU totals, location radius and additive SQL')
        return
    if args.action=='build':
        if args.catalog.exists():raise RuntimeError('Catalog already exists. Reuse it to keep both imports identical.')
        anchors=json.loads(args.anchors.read_text(encoding='utf-8'));catalog=build(anchors)
        args.catalog.parent.mkdir(parents=True,exist_ok=True)
        args.catalog.write_text(json.dumps(catalog,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
        covers(args.catalog.parent/'assets'/BATCH)
        print(json.dumps({'counts':{t:len(rows) for t,rows in catalog['tables'].items()},'sha256':catalog['sha256']},ensure_ascii=False))
        return
    catalog=json.loads(args.catalog.read_text(encoding='utf-8'));validate(catalog);database=Database(args)
    if args.action in ['preflight','apply']:database.preflight(catalog)
    if args.action=='apply':database.backup(args.backup_dir);database.run(sql_for(catalog))
    if args.action in ['apply','verify']:database.verify(catalog)

if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')
    try:main()
    except (RuntimeError,AssertionError,OSError) as error:
        print('FAILED:',str(error),file=sys.stderr);sys.exit(1)
