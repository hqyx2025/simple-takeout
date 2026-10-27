"""Bounded local-only staircase benchmark. Output excludes tokens and request bodies.

Workload JSON: {storeId, goodsId, specId, users:[{token,addressId}]}.
Reads are 80% of operations; --write-local adds 10% cart and 10% create+balance-pay.
Set TAKEOUT_LOAD_ISOLATED=1 and provision disposable accounts before enabling writes.
"""
import argparse, concurrent.futures, datetime, json, math, os, platform, re, threading, time
import urllib.error, urllib.parse, urllib.request, uuid
from pathlib import Path

def request(base,path,token='',method='GET',body=None,headers=None):
    h={'Content-Type':'application/json',**(headers or {})}
    if token:h['Authorization']='Bearer '+token
    started=time.perf_counter()
    req=urllib.request.Request(base+path,headers=h,method=method,data=None if body is None else json.dumps(body).encode())
    try:
        with urllib.request.urlopen(req,timeout=10) as r:status=r.status;raw=r.read()
    except urllib.error.HTTPError as e:status=e.code;raw=e.read()
    except Exception:return {'status':0,'code':0,'ms':(time.perf_counter()-started)*1000,'path':path.split('?')[0]},None
    try:data=json.loads(raw)
    except ValueError:data={}
    return {'status':status,'code':data.get('code',0),'admissionRejection':status==503 and data.get('message')=='服务繁忙，请稍后重试',
            'ms':(time.perf_counter()-started)*1000,'path':path.split('?')[0]},data.get('data')

def percentile(values,p):return sorted(values)[max(0,math.ceil(len(values)*p)-1)] if values else 0
def summarize(samples,elapsed):
    times=[s['ms'] for s in samples];success=sum(s['status']==s['code']==200 for s in samples)
    rate=sum(s['status']==429 for s in samples);busy=sum(s.get('admissionRejection',False) for s in samples)
    return {'requests':len(samples),'success':success,'throughputRps':round(len(samples)/elapsed,2),'successfulRps':round(success/elapsed,2),
            'p95Ms':round(percentile(times,.95),2),'p99Ms':round(percentile(times,.99),2),'rateLimited429':rate,'overload503':busy,
            'rateLimitRatio':round(rate/len(samples),5) if samples else 0,'overloadRatio':round(busy/len(samples),5) if samples else 0,
            'errors':len(samples)-success-rate-busy,'errorRatio':round((len(samples)-success-rate-busy)/len(samples),5) if samples else 0,
            'elapsedSeconds':round(elapsed,2)}

def run(args):
    parsed=urllib.parse.urlsplit(args.base_url)
    if parsed.scheme!='http' or parsed.hostname not in ('127.0.0.1','localhost','::1') or parsed.username or parsed.password or parsed.query or parsed.fragment or parsed.path not in ('','/'):
        raise ValueError('Only a plain local HTTP origin is permitted')
    if args.write_local and os.environ.get('TAKEOUT_LOAD_ISOLATED')!='1':raise ValueError('Confirm disposable infrastructure with TAKEOUT_LOAD_ISOLATED=1')
    if args.write_local and not re.fullmatch(r'[0-9]{6}',os.environ.get('TAKEOUT_LOAD_PAYMENT_PIN','')):raise ValueError('Set the isolated account payment PIN before creating any orders')
    cases=json.loads(Path(args.workload).read_text(encoding='utf-8'))
    users=cases['users'];assert users and all(u.get('token') for u in users)
    stop=threading.Event();metrics=[]
    def observe():
        while not stop.is_set():
            for origin in args.metrics:
                sample,_=None,None
                try:
                    req=urllib.request.Request(origin+'/internal/metrics',headers={'X-Integration-Key':os.environ['TAKEOUT_INTEGRATION_SECRET']})
                    with urllib.request.urlopen(req,timeout=2) as r:sample=json.load(r)
                except Exception:sample={'unavailable':True}
                metrics.append({'time':time.time(),'origin':origin,'metrics':sample})
            stop.wait(.5)
    thread=threading.Thread(target=observe,daemon=True);thread.start();stages=[];created=[];lock=threading.Lock()
    try:
        for concurrency in args.steps:
            start=time.perf_counter();deadline=start+args.seconds;results=[];cursor=0;counter=threading.Lock()
            def worker(index):
                nonlocal cursor
                own=[]
                while time.perf_counter()<deadline:
                    with counter:
                        if cursor>=args.max_operations:break
                        n=cursor;cursor+=1
                    if args.operations_per_second:
                        scheduled=start+n/args.operations_per_second
                        if scheduled>=deadline:break
                        delay=scheduled-time.perf_counter()
                        if delay>0:time.sleep(delay)
                    user=users[(n+index)%len(users)];kind=n%10
                    if args.write_local and kind==8:
                        sample,_=request(args.base_url,'/api/cart/items',user['token'],'POST',{'goodsId':cases['goodsId'],'specId':cases['specId'],'quantity':1});own.append(sample)
                    elif args.write_local and kind==9:
                        sample,order=request(args.base_url,'/api/orders',user['token'],'POST',{'storeId':cases['storeId'],
                            'items':[{'goodsId':cases['goodsId'],'specId':cases['specId'],'quantity':1}], 'addressId':user['addressId'],
                            'idempotencyKey':str(uuid.uuid4()),'deliveryType':'DELIVERY','remark':'local isolated capacity check'})
                        own.append(sample)
                        if sample['status']==sample['code']==200:
                            with lock:created.append(order['id'])
                            pay,_=request(args.base_url,f'/api/orders/{order["id"]}/pay?channel=BALANCE',user['token'],'POST',{'paymentPassword':os.environ['TAKEOUT_LOAD_PAYMENT_PIN']});own.append(pay)
                    else:
                        paths=['/api/categories','/api/stores',f'/api/stores/{cases["storeId"]}/goods',f'/api/stores/{cases["storeId"]}']
                        sample,_=request(args.base_url,paths[n%len(paths)],user['token']);own.append(sample)
                return own
            before=len(metrics)
            with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as pool:
                for group in pool.map(worker,range(concurrency)):results.extend(group)
            elapsed=time.perf_counter()-start
            stage={'concurrency':concurrency,**summarize(results,elapsed),'metrics':metrics[before:]}
            stages.append(stage);print(json.dumps({k:v for k,v in stage.items() if k!='metrics'}),flush=True)
    finally:stop.set();thread.join(3)
    report={'measuredAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'machine':{'platform':platform.platform(),'logicalCpus':os.cpu_count()},
            'conditions':{'baseUrl':args.base_url,'secondsPerStage':args.seconds,'maxOperationsPerStage':args.max_operations,'dataScale':args.data_scale,
                          'operationsPerSecond':args.operations_per_second,
                          'connectionReuse':False,'automaticRetries':0,'workload':'80% browse / 10% cart / 10% create+balance-pay' if args.write_local else 'browse only',
                          'latencyIncludes':'failed/rejected requests and connection establishment','clientOnServerHost':True},
            'stages':stages,'createdOrderIds':created}
    target=Path(args.output);target.parent.mkdir(parents=True,exist_ok=True);target.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    return 0 if all(s['errors']==0 for s in stages) else 1

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--base-url',default='http://127.0.0.1:8087');p.add_argument('--workload',required=True);p.add_argument('--write-local',action='store_true')
    p.add_argument('--steps',default='1,4,8,16,32');p.add_argument('--seconds',type=int,default=8);p.add_argument('--max-operations',type=int,default=1000)
    p.add_argument('--operations-per-second',type=float,default=0)
    p.add_argument('--metrics',action='append',default=[]);p.add_argument('--data-scale',required=True)
    p.add_argument('--output',default='TemporaryCacheStorage/governance/load.json');a=p.parse_args();a.steps=[int(x) for x in a.steps.split(',')]
    if not 1<=a.seconds<=60 or not 1<=a.max_operations<=100000 or not 0<=a.operations_per_second<=10000 or not a.steps or any(not 1<=n<=128 for n in a.steps):p.error('Invalid bounded load parameters')
    for origin in a.metrics:
        m=urllib.parse.urlsplit(origin)
        if m.scheme!='http' or m.hostname not in ('localhost','127.0.0.1','::1') or m.username or m.password or m.query or m.fragment or m.path not in ('','/'):p.error('Metrics origins must be plain local HTTP origins')
    raise SystemExit(run(a))
