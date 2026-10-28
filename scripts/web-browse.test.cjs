const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');

function browser(sidebarCollapsed='0',options={}){
  const nodes=new Map(),requests=[],calls=[],dialogs=[],observers=[],confirmMessages=[],promptMessages=[],storage=new Map([['takeout.demo.sidebarCollapsed',sidebarCollapsed]]);
  const element=id=>{
    if(!nodes.has(id)){
      const classes=new Set();
      nodes.set(id,{innerHTML:'',textContent:'',hidden:id==='authModal',dataset:{},value:'',isConnected:true,disabled:false,attributes:{},classes,
        setAttribute(name,value){this.attributes[name]=value;},
        addEventListener(){},insertAdjacentHTML(position,html){this.innerHTML+=html;},querySelector(){return {focus(){}};},querySelectorAll(){return [];},focus(){},
        classList:{toggle(name,enabled){if(enabled)classes.add(name);else classes.delete(name);}}});
    }
    return nodes.get(id);
  };
  const stores=options.stores||Array.from({length:55},(_,i)=>({id:i+1,name:`店铺${i+1}`,image:'/uploads/test.jpg',deliveryFee:3.5,categoryId:i%2+1,categoryIds:[i%2+1],tags:[]}));
  const cart=options.cart||[
    {storeId:1,storeName:'店铺A',goodsId:11,specId:0,specName:'',price:10,quantity:1,goods:{name:'商品A'}},
    {storeId:2,storeName:'店铺B',goodsId:22,specId:0,specName:'',price:20,quantity:1,goods:{name:'商品B'}}
  ];
  const coupons=options.coupons||[
    {id:1,storeId:2,name:'当前店可用券',threshold:10,amount:5,status:0,expireTime:'2099-12-31 23:59:59'},
    {id:2,storeId:2,name:'门槛未达券',threshold:30,amount:6,status:0,expireTime:'2099-12-31 23:59:59'},
    {id:3,storeId:1,name:'其他店券',threshold:10,amount:3,status:0,expireTime:'2099-12-31 23:59:59'},
    {id:4,storeId:2,name:'已使用券',threshold:10,amount:3,status:1,expireTime:'2099-12-31 23:59:59'},
    {id:5,storeId:2,name:'已过期券',threshold:10,amount:3,status:0,expireTime:'2000-01-01 00:00:00'}
  ];
  class TestFormData{
    constructor(form){this.data=form?.formData||{};}
    append(name,value){this.data[name]=value;}
    get(name){const value=this.data[name];return Array.isArray(value)?value[0]:(value??null);}
    getAll(name){const value=this.data[name];return value===undefined?[]:(Array.isArray(value)?value:[value]);}
    entries(){return Object.entries(this.data).flatMap(([key,value])=>(Array.isArray(value)?value:[value]).map(item=>[key,item]))[Symbol.iterator]();}
  }
  const createDialog=()=>{
    const listeners={},controls=new Map();
    const control=selector=>{
      if(!controls.has(selector))controls.set(selector,{value:'',checked:false,disabled:false,hidden:false,textContent:'',innerHTML:'',isConnected:true,listeners:{},focus(){},addEventListener(name,listener){this.listeners[name]=listener;},async fire(name,event={}){return this.listeners[name]?.({preventDefault(){},...event});}});
      return controls.get(selector);
    };
    const form=control('form');
    form.formData=options.reviewForm||{};
    form.elements=Object.fromEntries(['reasonType','reason','acknowledged','rejectReason'].map(name=>[name,control(name)]));
    form.querySelector=control;
    const dialog={innerHTML:'',returnValue:'',removed:false,attributes:{},open:false,isConnected:true,controls,form,
      setAttribute(name,value){this.attributes[name]=value;},
      addEventListener(name,listener){listeners[name]=listener;},
      querySelector:control,
      close(value){this.returnValue=value;this.open=false;listeners.close?.();},
      remove(){this.removed=true;this.isConnected=false;},
      showModal(){this.open=true;if(this.innerHTML.includes('data-refund-dialog')){if(options.refundDialogResult==='cancel')Promise.resolve().then(()=>this.close('cancel'));return;}this.returnValue=options.dialogResult||'cancel';Promise.resolve().then(()=>listeners.close?.());}
    };
    dialogs.push(dialog);return dialog;
  };
  class Observer{
    constructor(callback){this.callback=callback;observers.push(this);}
    observe(target){this.target=target;}
    disconnect(){this.disconnected=true;}
  }
  const context=vm.createContext({URL,console,setTimeout:(callback,delay)=>{const timer=setTimeout(callback,delay);timer.unref?.();return timer;},clearTimeout,IntersectionObserver:Observer,FormData:TestFormData,
    localStorage:{getItem:key=>storage.get(key),setItem:(key,value)=>storage.set(key,value),removeItem:key=>storage.delete(key)},
    window:{isSecureContext:true,navigator:options.navigator||{},IntersectionObserver:Observer,scrollTo(){},prompt(message,value){promptMessages.push({message,value});return options.promptResult??null;},confirm(message){confirmMessages.push(message);return options.confirmResult??false;}},
    document:{baseURI:'https://hqyx.website/takeout/',body:{append(){}},createElement(tag){return tag==='dialog'?createDialog():element(`created-${tag}`);},getElementById:element,querySelector(selector){return selector==='input[name="addressId"]:checked'?{value:element('selectedAddress').value||'1'}:null;},querySelectorAll(){return [];},addEventListener(){}},
    TakeoutUrls:{localPath:path=>path},
    TakeoutLocation:{coordinates(longitude,latitude){const lng=Number(longitude),lat=Number(latitude);return Number.isFinite(lng)&&Number.isFinite(lat)&&longitude!==''&&latitude!==''?{longitude:lng,latitude:lat}:null;}},
    fetch:async (path,init={})=>{
      requests.push(path);
      calls.push({path,init});
      if(options.onRequest){const override=await options.onRequest(path,init);if(override?.json)return override;}
      let data=[];
      if(path==='/api/stores')data=stores;
      else if(/^\/api\/stores\/\d+$/.test(path))data=stores.find(store=>store.id===Number(path.split('/').at(-1)));
      else if(path==='/api/cart')data=typeof cart==='function'?cart():cart;
      else if(path==='/api/addresses')data=options.addresses||[{id:1,name:'测试用户',phone:'13800138000',detail:'测试地址',isDefault:true}];
      else if(path==='/api/coupons')data=coupons;
      else if(path==='/api/orders')data=init.method==='POST'?(options.orderResponse||{id:51,orderNo:'WEB-51'}):[];
      else if(/^\/api\/orders\/\d+\/refunds$/.test(path))data=typeof options.refundHistory==='function'?await options.refundHistory(path):options.refundHistory||[];
      else if(/^\/api\/orders\/\d+\/refund$/.test(path))data=options.refundResponse||{id:71,orderId:Number(path.split('/')[3]),status:'PENDING'};
      else if(path==='/api/auth/login'){
        const payload=JSON.parse(init.body||'{}');
        data=typeof options.loginResponse==='function'?options.loginResponse(payload):options.loginResponse||{token:'login-token',refreshToken:'refresh-token',user:{id:2,role:0,username:'账号B'}};
      }
      else if(path==='/api/merchant/stores')data=options.merchantStores||[];
      else if(path==='/api/merchant/orders')data=options.merchantOrders||[];
      else if(path.startsWith('/api/merchant/stats'))data=options.merchantStats||{};
      else if(path==='/api/rider/profile')data=options.riderProfile||{online:1,status:1};
      else if(path==='/api/rider/orders/pool')data=options.riderPool||[];
      else if(path==='/api/rider/orders')data=typeof options.riderOrders==='function'?options.riderOrders():options.riderOrders||[];
      else if(path.startsWith('/api/admin/orders/page'))data=typeof options.adminOrdersPage==='function'?await options.adminOrdersPage(path):options.adminOrdersPage||{list:[],total:0,page:Number(new URL(path,'https://hqyx.website').searchParams.get('page')),pageSize:20,hasMore:false};
      else if(path.startsWith('/api/admin/refunds/page'))data=typeof options.adminRefundsPage==='function'?await options.adminRefundsPage(path):options.adminRefundsPage||{list:[],total:0,page:Number(new URL(path,'https://hqyx.website').searchParams.get('page')),pageSize:20,hasMore:false};
      else if(/^\/api\/admin\/refunds\/\d+$/.test(path))data=typeof options.refundDetail==='function'?await options.refundDetail(path):options.refundDetail||{id:Number(path.split('/').at(-1)),orderId:61,status:'PENDING',amount:25,reasonType:'QUALITY_ISSUE',reason:'餐盒破损漏汤'};
      else if(/^\/api\/admin\/refunds\/\d+\/approve$/.test(path))data={id:Number(path.split('/').at(-2)),orderId:61,status:'REFUNDED'};
      else if(/^\/api\/admin\/refunds\/\d+\/reject$/.test(path))data={id:Number(path.split('/').at(-2)),orderId:61,status:'REJECTED',rejectReason:JSON.parse(init.body).rejectReason};
      else if(path==='/api/stores?categoryId=2')data=stores.filter(s=>s.categoryId===2);
      else if(path.startsWith('/api/search?keyword='))data='searchResults' in options?options.searchResults:(new URL(path,'https://hqyx.website').searchParams.get('keyword').trim()?stores.filter(s=>s.id===2):[]);
      else if(path.startsWith('/api/rankings/stores'))data=[...stores].reverse();
      return {ok:true,status:200,json:async()=>({code:200,data})};
    }
  });
  const source=fs.readFileSync('server/takeout-gateway/src/main/resources/static/app.js','utf8');
  vm.runInContext(source.replace('  boot();','  globalThis.browseTest = {state,renderBrowse,renderCheckout,renderPage,renderShell,orderCard,handleAction,couponEligible,couponUnavailableReason,checkoutAmounts,checkoutDraft,merchantRejectPayload,addressForm,addressPayload,addressText,resetAccountState,loginWith,openAuth,closeAuth};'),context);
  Object.assign(context.browseTest.state,{user:{role:0},token:'test',location:{latitude:22.74967,longitude:108.452009},page:'discover'});
  return {...context.browseTest,element,requests,calls,dialogs,observers,confirmMessages,promptMessages,stores,coupons,storage,context};
}
const cardCount=html=>(html.match(/class="store-card"/g)||[]).length;

test('guests browse all stores and details without login or location but cart stays protected',async()=>{
  const b=browser('0',{stores:[{id:1,name:'远方店铺',distance:'2000km',deliverable:false,tags:[]}]});
  b.resetAccountState();
  await b.renderPage();
  assert.equal(b.state.stores.length,1);
  assert.match(b.element('storeGrid').innerHTML,/远方店铺/);
  assert.equal(b.element('authModal').hidden,true);
  assert.ok(b.requests.every(path=>!/[?&](latitude|longitude)=/.test(path)));
  await b.handleAction('open-store',1);
  assert.equal(b.state.page,'store');
  assert.match(b.element('app').innerHTML,/远方店铺/);
  assert.equal(b.element('authModal').hidden,true);
  await b.handleAction('add-cart',11);
  assert.equal(b.element('authModal').hidden,false);
  assert.equal(b.calls.some(call=>call.path==='/api/cart/items'),false);
});

test('guests may select a browsing location and still see distant stores',async()=>{
  const b=browser('0',{stores:[{id:1,name:'远方店铺',deliverable:false,tags:[]}]});
  b.resetAccountState();
  await b.handleAction('location-select','',{dataset:{longitude:'116.4',latitude:'39.9',address:'测试地点'}});
  assert.equal(b.state.locationLabel,'测试地点');
  assert.equal(b.state.stores.length,1);
  assert.equal(b.element('authModal').hidden,true);
});

test('empty search displays all stores even after choosing a location',async()=>{
  const b=browser();await b.renderBrowse('discover');
  assert.equal(b.state.stores.length,55,'empty search must display stores instead of an empty result');
  assert.ok(b.requests.includes('/api/stores'));
  assert.ok(b.requests.every(p=>!/[?&](latitude|longitude)=/.test(p)));
});

test('home appends stores in batches and disconnects its observer on navigation',async()=>{
  const b=browser();b.state.page='home';await b.renderPage();
  assert.equal(b.state.stores.length,55);
  assert.equal(cardCount(b.element('storeGrid').innerHTML),24);
  assert.match(b.element('storeGrid').innerHTML,/loading="lazy"/);
  const observer=b.observers.at(-1);
  observer.callback([{isIntersecting:true}]);
  assert.equal(cardCount(b.element('storeGrid').innerHTML),48);
  observer.callback([{isIntersecting:true}]);
  assert.equal(cardCount(b.element('storeGrid').innerHTML),55);
  assert.equal(b.element('storeLoadMore').hidden,true);
  assert.equal(new Set([...b.element('storeGrid').innerHTML.matchAll(/data-id="(\d+)"/g)].map(m=>m[1])).size,55);
  await b.renderPage();assert.equal(observer.disconnected,true);
  assert.equal(cardCount(b.element('storeGrid').innerHTML),24);
});

test('category filtering and keyword search combine without distance filtering',async()=>{
  const b=browser();b.state.categoryId=2;await b.renderBrowse('discover');
  assert.equal(b.state.stores.length,27);
  b.state.search='盖饭';await b.renderBrowse('discover');
  assert.equal(b.state.stores.length,1);
  assert.ok(b.requests.includes('/api/search?keyword='+encodeURIComponent('盖饭')));
  assert.ok(b.requests.every(p=>!/[?&](latitude|longitude)=/.test(p)));
});

test('store search uses one native form path for Enter and button submission',async()=>{
  const b=browser();await b.renderBrowse('discover');
  assert.match(b.element('app').innerHTML,/<form class="toolbar section" id="storeSearchForm" role="search">/);
  assert.match(b.element('app').innerHTML,/<button class="btn primary" type="submit">搜索<\/button>/);
  b.element('storeSearch').value='  盖饭  ';
  let prevented=false;
  await b.element('storeSearchForm').onsubmit({preventDefault(){prevented=true;}});
  assert.equal(prevented,true);
  assert.equal(b.state.search,'盖饭');
  assert.equal(b.state.page,'discover');
  assert.match(b.element('nav').innerHTML,/nav-item active" data-page="discover"/);
  assert.ok(b.requests.includes('/api/search?keyword='+encodeURIComponent('盖饭')));
  assert.match(b.element('app').innerHTML,/value="盖饭"/);
});

test('address form keeps map position door detail and tag as separate fields',async()=>{
  const address={id:7,name:'张女士',phone:'13800138000',detail:'南宁学院东门 3 栋 1206',mapAddress:'南宁学院东门',doorDetail:'3 栋 1206',tag:'学校',isDefault:1,latitude:22.8167,longitude:108.32};
  const b=browser('0',{addresses:[address]});
  Object.assign(b.state,{page:'account',editAddress:address});
  await b.renderPage();
  const html=b.element('app').innerHTML;
  assert.match(html,/name="mapAddress"[^>]*value="南宁学院东门"/);
  assert.match(html,/name="doorDetail"[^>]*value="3 栋 1206"/);
  assert.match(html,/<option value="学校" selected>学校<\/option>/);
  assert.match(html,/南宁学院东门 3 栋 1206/);

  const payload=JSON.parse(JSON.stringify(b.addressPayload({name:' 张女士 ',phone:' 13800138000 ',mapAddress:' 南宁学院东门 ',doorDetail:' 3 栋 1206 ',tag:'学校',latitude:'22.8167',longitude:'108.32'},true)));
  assert.deepEqual(payload,{name:'张女士',phone:'13800138000',detail:'南宁学院东门 3 栋 1206',mapAddress:'南宁学院东门',doorDetail:'3 栋 1206',tag:'学校',isDefault:1,longitude:108.32,latitude:22.8167});
});

test('store search distinguishes a real empty result from a failed request and keeps the keyword',async()=>{
  const emptyResult=browser('0',{searchResults:[]});
  Object.assign(emptyResult.state,{search:'不存在的店',page:'discover'});
  await emptyResult.renderPage();
  assert.match(emptyResult.element('storeGrid').innerHTML,/暂时没有符合条件的店铺/);

  const failed=browser('0',{onRequest(path){
    if(path.startsWith('/api/search?keyword='))throw new Error('搜索服务暂不可用');
  }});
  await failed.renderBrowse('discover');
  failed.element('storeSearch').value='保留这个关键词';
  await failed.element('storeSearchForm').onsubmit({preventDefault(){}});
  assert.equal(failed.state.search,'保留这个关键词');
  assert.match(failed.element('app').innerHTML,/搜索服务暂不可用/);
  assert.match(failed.element('app').innerHTML,/data-action="refresh"/);
});

test('store ranking retains its results instead of overwriting them with an empty search',async()=>{
  const b=browser();await b.renderBrowse('discover');await b.handleAction('rank-stores');
  assert.equal(b.state.stores[0].id,55);
  assert.equal(cardCount(b.element('storeGrid').innerHTML),24);
});

test('browse shortcuts replace the store list with visible results and allow returning to all stores',async()=>{
  const b=browser();b.resetAccountState();await b.renderPage();
  assert.ok(b.element('app').innerHTML.indexOf('id="browseResult"')<b.element('app').innerHTML.indexOf('id="storeGrid"'));
  for(const [action,title] of [['rank-goods','热销菜品'],['specials','特价专区'],['seckills','限时秒杀']]){
    await b.handleAction(action);
    assert.equal(b.element('storeGrid').hidden,true);
    assert.equal(b.element('storeLoadMore').hidden,true);
    assert.equal(b.observers.at(-1).disconnected,true);
    assert.match(b.element('browseResult').innerHTML,new RegExp(title));
    assert.match(b.element('browseResult').innerHTML,/暂无/);
    assert.equal(b.element('authModal').hidden,true);
  }
  await b.handleAction('rank-stores');
  assert.equal(b.element('storeGrid').hidden,false);
  assert.match(b.element('browseResult').innerHTML,/热销榜/);
  await b.handleAction('browse-all');
  assert.equal(b.state.stores.length,55);
  assert.equal(b.state.stores[0].id,1);
  assert.match(b.element('app').innerHTML,/data-action="browse-all"[^>]*aria-pressed="true"/);
});

test('rapid shortcut switches keep the latest selection even when an earlier request finishes last',async()=>{
  let release;
  const b=browser('0',{onRequest(path){
    if(path.startsWith('/api/rankings/goods'))return new Promise(resolve=>{release=resolve;});
  }});
  await b.renderBrowse('discover');
  const first=b.handleAction('rank-goods');
  await Promise.resolve();
  await b.handleAction('specials');
  release({ok:true,status:200,json:async()=>({code:200,data:[{goods:{id:1,name:'过期榜单',price:2}}]})});
  await first;
  assert.match(b.element('browseResult').innerHTML,/特价专区/);
  assert.doesNotMatch(b.element('browseResult').innerHTML,/过期榜单/);
});

test('promotional and hot goods use the server product photos for both response shapes',async()=>{
  const goods={id:11,storeId:1,name:'招牌饭 <大份>',price:12,image:'/uploads/food-original.jpg'};
  const b=browser('0',{onRequest(path){
    if(['/api/rankings/goods?limit=20','/api/goods/special?limit=20','/api/seckills?limit=20'].includes(path)){
      const data=path.startsWith('/api/seckills')
        ? [{goodsId:goods.id,storeId:1,goodsName:goods.name,image:goods.image,price:9,quota:20,sold:3},{goodsName:'无图餐品',price:6}]
        : [{goods,storeName:'测试店铺'},{goods:{name:'无图餐品',price:6}}];
      return {ok:true,status:200,json:async()=>({code:200,data})};
    }
  }});
  await b.renderBrowse('home');
  for(const action of ['rank-goods','specials','seckills']){
    await b.handleAction(action);
    const html=b.element('browseResult').innerHTML;
    assert.match(html,/<img[^>]*loading="lazy"[^>]*src="\/uploads\/food-original.jpg"[^>]*alt="招牌饭 &lt;大份&gt;"/);
    assert.match(html,/暂无图片/);
    assert.match(html,/data-action="open-store" data-id="1"/);
    assert.doesNotMatch(html,/src="(?:undefined|null|)"/);
  }
});

test('failed shortcuts display a retryable error in the result area',async()=>{
  const b=browser('0',{onRequest(path){if(path.startsWith('/api/goods/special'))throw new Error('活动服务暂不可用');}});
  await b.renderBrowse('discover');await b.handleAction('specials');
  assert.equal(b.element('storeGrid').hidden,true);
  assert.match(b.element('browseResult').innerHTML,/活动服务暂不可用/);
  assert.match(b.element('browseResult').innerHTML,/data-action="specials"/);
});

test('a delayed ranking response cannot write into a different route',async()=>{
  let releaseRank;
  const pendingRank=new Promise(resolve=>{releaseRank=resolve;});
  const b=browser('0',{onRequest(path){if(path.startsWith('/api/rankings/goods'))return pendingRank;}});
  await b.renderBrowse('discover');
  const ranking=b.handleAction('rank-goods','',{isConnected:true});
  await Promise.resolve();
  const beforeNavigation=b.element('browseResult').innerHTML;
  b.state.page='orders';await b.renderPage();
  releaseRank();await ranking;
  assert.match(b.element('app').innerHTML,/我的订单/);
  assert.equal(b.element('browseResult').innerHTML,beforeNavigation);
});

test('sidebar collapse preserves the loaded list and exposes accessible icon navigation',async()=>{
  const b=browser();await b.renderBrowse('discover');
  const cards=b.element('storeGrid').innerHTML,requests=b.requests.length;
  await b.handleAction('sidebar-toggle');
  assert.equal(b.element('appLayout').classes.has('sidebar-collapsed'),true);
  assert.equal(b.element('sidebarToggle').attributes['aria-expanded'],'false');
  assert.equal(b.element('sidebarToggle').attributes['aria-label'],'展开侧边栏');
  assert.equal(b.storage.get('takeout.demo.sidebarCollapsed'),'1');
  assert.match(b.element('nav').innerHTML,/aria-label="首页"/);
  assert.equal(b.element('storeGrid').innerHTML,cards);
  assert.equal(b.requests.length,requests);
  await b.handleAction('sidebar-toggle');
  assert.equal(b.element('appLayout').classes.has('sidebar-collapsed'),false);
  assert.equal(b.element('sidebarToggle').attributes['aria-expanded'],'true');
  assert.equal(b.storage.get('takeout.demo.sidebarCollapsed'),'0');
});

test('a saved sidebar preference is restored for each role without mixing navigation permissions',()=>{
  const b=browser('1');
  for(const [role,label] of [[0,'首页'],[1,'经营概况'],[2,'平台总览'],[3,'待抢订单']]){
    b.state.role=role;b.state.user.role=role;b.renderShell();
    assert.equal(b.element('appLayout').classes.has('sidebar-collapsed'),true);
    assert.ok(b.element('nav').innerHTML.includes(`aria-label="${label}"`));
    if(role!==0)assert.ok(!b.element('nav').innerHTML.includes('aria-label="首页"'));
  }
});

test('switching accounts clears every account-scoped cache and merchant selection',async()=>{
  const b=browser('0',{loginResponse:{token:'token-b',refreshToken:'refresh-b',user:{id:202,role:0,username:'账号B'}}});
  Object.assign(b.state,{
    user:{id:101,role:1,username:'账号A'},role:1,token:'token-a',refreshToken:'refresh-a',page:'catalog',
    cart:[{goodsId:1}],addresses:[{id:1}],orders:[{id:1}],favorites:[{id:1}],coupons:[{id:1}],
    assistantHistory:[{role:'user',content:'账号A的私密问题'}],merchantStores:[{id:7}],activeStoreId:7,
    merchantGoods:[{id:8}],merchantReviews:[{id:9}],rider:{id:4},riderOrders:[{id:5}],
    checkoutStoreId:7,checkoutIntentStoreId:7,checkoutIntentKey:'account-a-intent',checkoutSubmitting:true
  });
  await b.loginWith({phone:'13900000000',password:'secret',loginType:'CUSTOMER'});
  assert.equal(b.state.user.id,202);
  assert.equal(b.state.token,'token-b');
  for(const key of ['cart','addresses','orders','favorites','coupons','assistantHistory','merchantStores','merchantGoods','merchantReviews','riderOrders'])assert.equal(b.state[key].length,0,`${key} must not cross accounts`);
  assert.equal(b.state.rider,null);
  assert.equal(b.state.activeStoreId,0);
  assert.equal(b.state.checkoutIntentKey,'');
  assert.equal(b.state.checkoutSubmitting,false);
});

test('merchant active store is reset when it is not owned by the current account',async()=>{
  const b=browser('0',{merchantStores:[{id:22,name:'账号B门店'}]});
  Object.assign(b.state,{user:{id:202,role:1},role:1,token:'merchant-b',page:'overview',activeStoreId:7});
  await b.renderPage();
  assert.equal(b.state.activeStoreId,22);
  assert.match(b.element('app').innerHTML,/账号B门店/);
});

test('auth mode switches keep the original opener for focus restoration',()=>{
  const b=browser();
  const opener={restored:false,focus(){this.restored=true;}};
  b.context.document.activeElement=opener;
  b.openAuth('login');
  b.context.document.activeElement={focus(){}};
  b.openAuth('register');
  b.closeAuth();
  assert.equal(opener.restored,true);
});

test('checkout keeps the selected store and only offers delivery',async()=>{
  const b=browser();b.state.page='cart';await b.handleAction('checkout',2);
  assert.equal(b.state.checkoutStoreId,2);
  assert.match(b.element('app').innerHTML,/店铺：店铺B/);
  assert.match(b.element('app').innerHTML,/商品B/);
  assert.doesNotMatch(b.element('app').innerHTML,/商品A|PICKUP|到店自取/);
  assert.match(b.element('app').innerHTML,/商品小计<\/span><span>¥20\.00/);
  assert.match(b.element('app').innerHTML,/配送费<\/span><span>¥3\.50/);
  assert.match(b.element('app').innerHTML,/当前店可用券/);
  const choices=b.element('app').innerHTML.match(/<select class="select" id="checkoutCoupon"[^>]*>([\s\S]*?)<\/select>/)[1];
  assert.doesNotMatch(choices,/门槛未达券|其他店券|已使用券|已过期券/);
  assert.match(b.element('app').innerHTML,/门槛未达券：商品还差 ¥10.00 达到门槛/);
  assert.match(b.element('app').innerHTML,/其他店券：不适用于本店/);
  const coupon=b.element('checkoutCoupon');
  coupon.value='1';coupon.onchange();
  assert.equal(b.element('checkoutDiscount').textContent,'5.00');
  assert.equal(b.element('checkoutPayable').textContent,'18.50');
  assert.ok(b.state.checkoutIntentKey);
  await b.handleAction('go','cart');
  assert.equal(b.state.checkoutStoreId,0);
  assert.equal(b.state.checkoutIntentKey,'');
});

test('checkout locks duplicate submits and keeps one idempotency key for retries',async()=>{
  let releaseOrder;
  const pendingOrder=new Promise(resolve=>{releaseOrder=resolve;});
  const b=browser('0',{onRequest(path,init){if(path==='/api/orders'&&init.method==='POST')return pendingOrder;}});
  Object.assign(b.state,{page:'checkout',checkoutStoreId:2,cart:[{storeId:2,goodsId:22,specId:0,specName:'',price:20,quantity:1,goods:{name:'商品B',image:''}}]});
  await b.renderCheckout();
  const button={dataset:{store:'2'},isConnected:true,disabled:false,textContent:''};
  const first=b.handleAction('place-order','',button);
  await new Promise(resolve=>setImmediate(resolve));
  const second=b.handleAction('place-order','',button);
  assert.equal(b.calls.filter(call=>call.path==='/api/orders'&&call.init.method==='POST').length,1);
  assert.equal(button.disabled,true);
  assert.equal(button.textContent,'提交中…');
  await second;releaseOrder();await first;
  const body=JSON.parse(b.calls.find(call=>call.path==='/api/orders'&&call.init.method==='POST').init.body);
  assert.match(body.idempotencyKey,/^web-/);
  assert.equal(b.state.checkoutIntentKey,'');
  assert.equal(b.state.checkoutSubmitting,false);

  let attempts=0;
  const retry=browser('0',{onRequest(path,init){if(path==='/api/orders'&&init.method==='POST'&&++attempts===1)throw new Error('网络暂不可用');}});
  Object.assign(retry.state,{page:'checkout',checkoutStoreId:2,cart:b.state.cart});
  await retry.renderCheckout();
  const retryButton={dataset:{store:'2'},isConnected:true,disabled:false,textContent:''};
  await retry.handleAction('place-order','',retryButton);
  const intent=retry.state.checkoutIntentKey;
  assert.ok(intent);
  assert.equal(retry.state.checkoutSubmitting,false);
  assert.equal(retryButton.disabled,false);
  await retry.handleAction('place-order','',retryButton);
  const posts=retry.calls.filter(call=>call.path==='/api/orders'&&call.init.method==='POST').map(call=>JSON.parse(call.init.body));
  assert.equal(posts.length,2);
  assert.equal(posts[0].idempotencyKey,intent);
  assert.equal(posts[1].idempotencyKey,intent);
});

test('clearing one store uses one transactional batch request and refreshes after failure',async()=>{
  const cart=[
    {storeId:7,storeName:'晚餐铺',goodsId:71,specId:1,quantity:2,price:12,goods:{name:'商品A'}},
    {storeId:7,storeName:'晚餐铺',goodsId:71,specId:2,quantity:3,price:8,goods:{name:'商品A 大份'}},
    {storeId:7,storeName:'晚餐铺',goodsId:72,specId:0,quantity:1,price:9,goods:{name:'商品B'}}
  ];
  const cancelled=browser('0',{cart});Object.assign(cancelled.state,{cart,page:'cart'});
  await cancelled.handleAction('cart-clear',7);
  assert.deepEqual(cancelled.confirmMessages,['确认清空“晚餐铺”的 3 项、共 6 件商品？此操作无法撤销。']);
  assert.equal(cancelled.calls.length,0);

  const confirmed=browser('0',{cart,confirmResult:true});Object.assign(confirmed.state,{cart,page:'cart'});
  await confirmed.handleAction('cart-clear',7);
  const deletes=confirmed.calls.filter(call=>call.init.method==='DELETE');
  assert.equal(deletes.length,1);
  assert.equal(deletes[0].path,'/api/cart/items?goodsIds=71%2C72');

  const failed=browser('0',{cart,confirmResult:true,onRequest(path,init){
    if(path.startsWith('/api/cart/items?goodsIds=')&&init.method==='DELETE')throw new Error('批量删除失败');
  }});Object.assign(failed.state,{cart,page:'cart'});
  await failed.handleAction('cart-clear',7);
  assert.ok(failed.requests.filter(path=>path==='/api/cart').length>=1,'failure must refresh the authoritative cart');
  assert.match(failed.element('notice').textContent,/清空失败：批量删除失败，已刷新购物车/);
});

test('an assigned rider can confirm pickup without a riderId field',()=>{
  const b=browser();
  const html=b.orderCard({id:42,status:2,items:[],payAmount:0},'rider');
  assert.match(html,/data-action="rider-pickup"/);
  assert.match(html,/确认取餐/);
});

test('merchant rejection uses structured reasons and an exact order SKU',()=>{
  const b=browser();
  assert.deepEqual(JSON.parse(JSON.stringify(b.merchantRejectPayload({
    reasonCode:'ITEM_UNAVAILABLE',goodsKey:'22:7',note:'  原料售罄  '
  }))),{reasonCode:'ITEM_UNAVAILABLE',note:'原料售罄',goodsId:22,specId:7});
  assert.deepEqual(JSON.parse(JSON.stringify(b.merchantRejectPayload({
    reasonCode:'STORE_OVER_CAPACITY',goodsKey:'22:7',note:''
  }))),{reasonCode:'STORE_OVER_CAPACITY'});
  assert.throws(()=>b.merchantRejectPayload({reasonCode:'ITEM_UNAVAILABLE',goodsKey:''}),/请选择缺货餐品/);
  assert.throws(()=>b.merchantRejectPayload({reasonCode:'STORE_BUSY'}),/请选择无法接单原因/);
});

test('merchant can reject only before acceptance and sees the production support boundary',()=>{
  const b=browser();
  const pending=b.orderCard({id:8,status:1,items:[],payAmount:20},'merchant');
  assert.match(pending,/data-action="merchant-reject" data-id="8"/);
  assert.match(pending,/data-action="merchant-flow" data-id="8:accept"/);
  const production=b.orderCard({id:8,status:2,items:[],payAmount:20},'merchant');
  assert.doesNotMatch(production,/merchant-reject/);
  assert.match(production,/出餐完成/);
  assert.match(production,/制作中如有异常，请联系平台处理/);
});

test('customer sees merchant rejection source and server reason without relabeling other cancellations',()=>{
  const b=browser();
  const rejected=b.orderCard({id:9,status:5,escrowStatus:2,cancelSource:'MERCHANT',cancelReason:'餐品缺货：招牌饭',rejectNote:'不应公开的自由备注',items:[],payAmount:20});
  assert.match(rejected,/商家未能接单/);
  assert.match(rejected,/餐品缺货：招牌饭/);
  assert.doesNotMatch(rejected,/不应公开的自由备注|商家说明/);
  const userCancelled=b.orderCard({id:10,status:5,cancelSource:'USER',cancelReason:'用户取消订单',items:[],payAmount:20});
  assert.match(userCancelled,/已取消/);
  assert.doesNotMatch(userCancelled,/商家未能接单/);
});

test('assistant identifies itself accurately and defers售后结果 to order state',async()=>{
  const b=browser();Object.assign(b.state,{page:'assistant',assistantHistory:[{role:'assistant',content:'请查看订单'}]});
  await b.renderPage();
  assert.match(b.element('app').innerHTML,/智能助手/);
  assert.match(b.element('app').innerHTML,/自动回答，退款与售后结果以订单状态为准/);
  assert.doesNotMatch(b.element('app').innerHTML,/<strong>客服<\/strong>/);
});

test('rider pool hides recipient data while assigned orders expose a dialable contact',async()=>{
  const order={id:42,orderNo:'RIDER-42',storeName:'真实店铺',status:2,deliveryFee:5,payAmount:30,createTime:'2026-10-26 12:00:00',
    address:{name:'王女士',phone:'13800138000',detail:'朝阳路 8 号 3 栋 1201'},items:[{goodsName:'私密商品',quantity:2}]};
  const b=browser('0',{riderProfile:{online:1,status:1},riderPool:[order],riderOrders:[order]});
  Object.assign(b.state,{role:3,user:{role:3},page:'rider-pool'});
  await b.renderPage();
  assert.match(b.element('app').innerHTML,/抢单后可查看收货地址/);
  assert.doesNotMatch(b.element('app').innerHTML,/王女士|13800138000|1201|私密商品/);

  b.state.page='rider-orders';await b.renderPage();
  assert.match(b.element('app').innerHTML,/收货人：王女士/);
  assert.match(b.element('app').innerHTML,/朝阳路 8 号 3 栋 1201/);
  assert.match(b.element('app').innerHTML,/href="tel:13800138000"/);
  assert.match(b.element('app').innerHTML,/拨打 13800138000/);
});

test('rider terminal orders remove recipient name phone and address from the DOM',()=>{
  const html=browser().orderCard({id:42,status:4,payAmount:30,items:[],address:{name:'王女士',phone:'13800138000',detail:'朝阳路 8 号 1201'}},'rider');
  assert.match(html,/收货信息已隐藏/);
  assert.doesNotMatch(html,/王女士|13800138000|朝阳路|1201|tel:/);
});

test('review dialog submits the chosen product, rating, tags and content',async()=>{
  const b=browser('0',{dialogResult:'submit',reviewForm:{goodsId:'22',rating:'2',tags:['需要改进'],content:'偏咸'}});
  b.state.page='orders';b.state.orders=[{id:7,status:4,items:[{goodsId:11,goodsName:'商品A'},{goodsId:22,goodsName:'商品B'}]}];
  await b.handleAction('review',7);
  const call=b.calls.find(item=>item.path==='/api/orders/7/review');
  assert.ok(call);
  assert.deepEqual(JSON.parse(call.init.body),{goodsId:22,rating:2,content:'偏咸',tags:['需要改进'],images:[],anonymous:0});
  assert.match(b.dialogs[0].innerHTML,/商品A/);
  assert.match(b.dialogs[0].innerHTML,/请选择 1–5 星/);
});

test('cancelling review or refund sends nothing and reports no success',async()=>{
  {
    const b=browser('0',{refundDialogResult:'cancel'});
    b.state.orders=[{id:7,status:4,items:[{goodsId:22,goodsName:'商品B'}]}];
    await b.handleAction('refund',7);
    assert.equal(b.calls.some(item=>item.path==='/api/orders/7/refund'),false);
    assert.notEqual(b.element('notice').textContent,'退款申请已提交');
  }
  const b=browser();b.state.orders=[{id:7,status:4,items:[{goodsId:22,goodsName:'商品B'}]}];
  await b.handleAction('review',7);
  assert.equal(b.calls.some(item=>item.path==='/api/orders/7/review'),false);
  assert.notEqual(b.element('notice').textContent,'评价已提交');
});

test('admin direct refund is only offered and sent before delivery',async()=>{
  const b=browser();
  for(const status of [1,2,3])assert.match(b.orderCard({id:status,status,items:[],payAmount:0},'admin'),/data-action="admin-refund-order"/);
  for(const status of [0,4,5,6])assert.doesNotMatch(b.orderCard({id:status,status,items:[],payAmount:0},'admin'),/data-action="admin-refund-order"/);
  b.state.adminOrders=[{id:4,status:4}];
  await b.handleAction('admin-refund-order',4);
  assert.equal(b.calls.some(item=>item.path==='/api/admin/orders/4/refund'),false);
  const allowed=browser();allowed.state.adminOrders=[{id:2,status:2}];
  await allowed.handleAction('admin-refund-order',2);
  assert.equal(allowed.calls.some(item=>item.path==='/api/admin/orders/2/refund'&&item.init.method==='PUT'),true);
});

test('admin order pagination action retains the current-page query and honors boundaries',async()=>{
  const pageData=path=>{
    const page=Number(new URL(path,'https://hqyx.website').searchParams.get('page'));
    return page===2
      ?{list:[{id:21,orderNo:'ORDER-21',status:1,items:[],payAmount:0}],total:21,page:2,pageSize:20,hasMore:false}
      :{list:[{id:1,orderNo:'ORDER-1',status:1,items:[],payAmount:0}],total:21,page:1,pageSize:20,hasMore:true};
  };
  const b=browser('0',{adminOrdersPage:pageData});
  Object.assign(b.state,{role:2,user:{role:2},page:'admin-orders'});
  await b.renderPage();
  b.element('adminOrderFilter').oninput({target:{value:'ORDER-21'}});
  assert.match(b.element('adminOrderList').innerHTML,/当前页没有匹配订单/);
  await b.handleAction('admin-orders-page','2');
  assert.ok(b.requests.includes('/api/admin/orders/page?page=2&pageSize=20'));
  assert.equal(b.state.adminOrderQuery,'ORDER-21');
  assert.match(b.element('app').innerHTML,/value="ORDER-21"/);
  assert.match(b.element('app').innerHTML,/ORDER-21/);
  assert.match(b.element('app').innerHTML,/第2页 \/ 共21条/);
  assert.match(b.element('app').innerHTML,/data-action="admin-orders-page" data-id="1" >上一页/);
  assert.match(b.element('app').innerHTML,/data-action="admin-orders-page" data-id="3" disabled>下一页/);
});

test('a stale admin page response cannot overwrite the active route',async()=>{
  let resolveOrders;
  const pendingOrders=new Promise(resolve=>{resolveOrders=resolve;});
  const b=browser('0',{adminOrdersPage:()=>pendingOrders});
  Object.assign(b.state,{role:2,user:{role:2},page:'admin-orders'});
  const staleRender=b.renderPage();
  await Promise.resolve();
  b.state.page='overview';
  await b.renderPage();
  resolveOrders({list:[{id:21,orderNo:'STALE-ORDER',status:1,items:[],payAmount:0}],total:1,page:1,pageSize:20,hasMore:false});
  await staleRender;
  assert.match(b.element('app').innerHTML,/平台总览/);
  assert.doesNotMatch(b.element('app').innerHTML,/STALE-ORDER/);
});

test('customer merchant and rider responses are discarded after a cross-route change',async()=>{
  let releaseOrders;
  const customer=browser('0',{onRequest(path,init){if(path==='/api/orders'&&!init.method)return new Promise(resolve=>{releaseOrders=resolve;});}});
  Object.assign(customer.state,{page:'orders',orders:[{id:99}]});
  const oldOrders=customer.renderPage();await Promise.resolve();
  customer.state.page='home';await customer.renderPage();releaseOrders();await oldOrders;
  assert.deepEqual(customer.state.orders,[{id:99}]);
  assert.match(customer.element('app').innerHTML,/全部店铺/);

  let releaseStores;
  const merchant=browser('0',{merchantStores:[{id:22,name:'延迟门店'}],onRequest(path){if(path==='/api/merchant/stores')return new Promise(resolve=>{releaseStores=resolve;});}});
  Object.assign(merchant.state,{user:{id:8,role:1},role:1,token:'merchant',page:'overview',merchantStores:[{id:7,name:'当前门店'}],activeStoreId:7});
  const oldMerchant=merchant.renderPage();await Promise.resolve();
  Object.assign(merchant.state,{user:{id:8,role:0},role:0,page:'home'});await merchant.renderPage();releaseStores();await oldMerchant;
  assert.deepEqual(merchant.state.merchantStores,[{id:7,name:'当前门店'}]);
  assert.match(merchant.element('app').innerHTML,/全部店铺/);

  let releaseProfile;
  const rider=browser('0',{riderProfile:{id:33,online:1},onRequest(path){if(path==='/api/rider/profile')return new Promise(resolve=>{releaseProfile=resolve;});}});
  Object.assign(rider.state,{user:{id:9,role:3},role:3,token:'rider',page:'rider-profile',rider:{id:9,online:0}});
  const oldProfile=rider.renderPage();await Promise.resolve();
  Object.assign(rider.state,{user:{id:9,role:0},role:0,page:'home'});await rider.renderPage();releaseProfile();await oldProfile;
  assert.deepEqual(rider.state.rider,{id:9,online:0});
  assert.match(rider.element('app').innerHTML,/全部店铺/);
});

test('a stale rider submit response cannot change the next page state or feedback',async()=>{
  let releaseStatus;
  const b=browser('0',{onRequest(path){if(path==='/api/rider/status')return new Promise(resolve=>{releaseStatus=resolve;});}});
  Object.assign(b.state,{user:{id:9,role:3},role:3,token:'rider',page:'rider-profile',rider:{id:9,online:0}});
  const submit=b.handleAction('rider-online','1',{isConnected:true});await Promise.resolve();
  b.state.page='rider-orders';await b.renderPage();releaseStatus();await submit;
  assert.deepEqual(b.state.rider,{id:9,online:0});
  assert.match(b.element('app').innerHTML,/配送订单/);
  assert.notEqual(b.element('notice').textContent,'已上线');
});

test('refunds default to pending and switching filters resets to the first page',async()=>{
  const b=browser('0',{adminRefundsPage:{list:[],total:21,page:1,pageSize:20,hasMore:true}});
  Object.assign(b.state,{role:2,user:{role:2},page:'refunds'});
  await b.renderPage();
  assert.ok(b.requests.includes('/api/admin/refunds/page?status=PENDING&page=1&pageSize=20'));
  assert.match(b.element('app').innerHTML,/tab active" data-action="admin-refund-filter" data-id="PENDING">待审批/);
  assert.match(b.element('app').innerHTML,/data-action="admin-refunds-page" data-id="0" disabled>上一页/);
  assert.match(b.element('app').innerHTML,/data-action="admin-refunds-page" data-id="2" >下一页/);
  b.state.adminRefundsPage=2;
  await b.handleAction('admin-refund-filter','ALL');
  assert.equal(b.state.adminRefundFilter,'');
  assert.equal(b.state.adminRefundsPage,1);
  assert.ok(b.requests.includes('/api/admin/refunds/page?page=1&pageSize=20'));
});

test('refund approval retains its filter and returns from an emptied last page',async()=>{
  let approved=false;
  const pageData=path=>{
    const page=Number(new URL(path,'https://hqyx.website').searchParams.get('page'));
    if(!approved)return page===2
      ?{list:[{id:41,orderId:61,status:'PENDING'}],total:21,page:2,pageSize:20,hasMore:false}
      :{list:[{id:1,orderId:1,status:'PENDING'}],total:21,page:1,pageSize:20,hasMore:true};
    return page===2
      ?{list:[],total:20,page:2,pageSize:20,hasMore:false}
      :{list:[{id:1,orderId:1,status:'PENDING'}],total:20,page:1,pageSize:20,hasMore:false};
  };
  const b=browser('0',{adminRefundsPage:pageData,onRequest(path,init){
    if(path==='/api/admin/refunds/41/approve'&&init.method==='POST')approved=true;
  }});
  Object.assign(b.state,{role:2,user:{role:2},page:'refunds',adminRefundsPage:2,adminRefundFilter:'PENDING'});
  await b.renderPage();
  assert.match(b.element('app').innerHTML,/data-action="refund-approve" data-id="41"/);
  const decision=b.handleAction('refund-approve',41);
  await new Promise(setImmediate);
  const dialog=b.dialogs.at(-1);
  dialog.form.elements.acknowledged.checked=true;
  await dialog.form.fire('submit');await decision;
  assert.equal(b.calls.filter(item=>item.path==='/api/admin/refunds/41/approve'&&item.init.method==='POST').length,1);
  assert.equal(approved,true);
  assert.equal(b.state.adminRefundFilter,'PENDING');
  assert.equal(b.state.adminRefundsPage,1);
  assert.ok(b.requests.includes('/api/admin/refunds/page?status=PENDING&page=2&pageSize=20'));
  assert.ok(b.requests.includes('/api/admin/refunds/page?status=PENDING&page=1&pageSize=20'));
});

test('refund history is on demand for every order state and exposes outcomes with escaped reasons',async()=>{
  const b=browser('0',{refundHistory:[
    {id:71,orderId:7,reasonType:'QUALITY_ISSUE',reason:'餐盒破损 <script>',amount:25,status:'PENDING',applyTime:'2026-10-26 12:00'},
    {id:72,orderId:7,reasonType:'OTHER',reason:'漏餐',amount:25,status:'REJECTED',applyTime:'2026-10-25 12:00',processTime:'2026-10-25 13:00',rejectReason:'核实说明'},
    {id:73,orderId:7,reasonType:'WRONG_ITEM',amount:25,status:'REFUNDED'}
  ]});
  Object.assign(b.state,{page:'orders'});await b.renderPage();
  assert.equal(b.requests.some(path=>path.endsWith('/refunds')),false,'listing orders must not trigger per-order history requests');
  for(const status of [0,1,2,3,4,5,6])assert.match(b.orderCard({id:7,status,items:[]}),/data-action="refund-history"/);
  await b.handleAction('refund-history',7);
  const content=b.dialogs.at(-1).querySelector('[data-refund-history]').innerHTML;
  assert.match(content,/退款申请编号/);assert.match(content,/餐品质量问题/);assert.match(content,/¥25\.00/);
  assert.match(content,/待审批/);assert.match(content,/已拒绝/);assert.match(content,/已退款/);
  assert.match(content,/2026-10-25 13:00/);assert.match(content,/核实说明/);
  assert.match(content,/&lt;script&gt;/);assert.doesNotMatch(content,/<script>/);
});

test('refund history offers retry after a failure and discards a response after leaving the page',async()=>{
  let fail=true;
  const b=browser('0',{refundHistory:[{id:71,status:'PENDING'}],onRequest(path){if(path==='/api/orders/7/refunds'&&fail){fail=false;throw new Error('网络断开');}}});
  await b.handleAction('refund-history',7);
  const dialog=b.dialogs.at(-1),content=dialog.querySelector('[data-refund-history]');
  assert.match(content.innerHTML,/退款记录读取失败：网络断开/);assert.match(content.innerHTML,/data-refund-retry/);
  await content.fire('click',{target:{closest:()=>({})}});await new Promise(setImmediate);
  assert.match(content.innerHTML,/退款申请编号/);

  let release;
  const delayed=browser('0',{refundHistory:()=>new Promise(resolve=>{release=resolve;})});
  const loading=delayed.handleAction('refund-history',7);await new Promise(setImmediate);
  const stale=delayed.dialogs.at(-1);
  delayed.resetAccountState();release([{id:911,reason:'旧账号私密说明',status:'REJECTED'}]);await loading;
  assert.equal(stale.removed,true);
  assert.doesNotMatch(stale.querySelector('[data-refund-history]').innerHTML,/旧账号私密说明/);
});

test('refund form validates other details, prevents duplicate submits and retries one stable request key',async()=>{
  let release,attempts=0;
  const b=browser('0',{onRequest(path){if(path==='/api/orders/7/refund'){attempts++;if(attempts===1)return new Promise((resolve,reject)=>{release=()=>reject(new Error('响应丢失'));});}}});
  b.state.orders=[{id:7,status:4,escrowStatus:0,payAmount:25}];b.state.page='orders';
  const applying=b.handleAction('refund',7);const dialog=b.dialogs.at(-1),form=dialog.form;
  form.elements.reasonType.value='OTHER';await form.elements.reasonType.fire('change');
  assert.equal(form.elements.reason.required,true);
  form.elements.reason.value='   ';await form.fire('submit');
  assert.equal(b.calls.some(call=>call.path==='/api/orders/7/refund'),false);
  assert.match(form.querySelector('[data-refund-error]').textContent,/请填写具体问题/);
  form.elements.reason.value='缺少一份米饭';
  const first=form.fire('submit');await form.fire('submit');
  assert.equal(b.calls.filter(call=>call.path==='/api/orders/7/refund').length,1);
  assert.equal(form.querySelector('[data-refund-submit]').disabled,true);
  release();await first;
  assert.equal(form.elements.reason.value,'缺少一份米饭');assert.equal(dialog.open,true);
  assert.match(form.querySelector('[data-refund-error]').textContent,/同一次申请不会重复创建/);
  await form.fire('submit');await applying;
  const payloads=b.calls.filter(call=>call.path==='/api/orders/7/refund').map(call=>JSON.parse(call.init.body));
  assert.equal(payloads.length,2);assert.equal(payloads[0].idempotencyKey,payloads[1].idempotencyKey);
  assert.equal(payloads[1].reasonType,'OTHER');assert.equal(payloads[1].reason,'缺少一份米饭');
  assert.match(b.element('notice').textContent,/等待平台审批/);
});

test('refund replay feedback follows terminal server state and a late response cannot leak across accounts',async()=>{
  const rejected=browser('0',{refundResponse:{id:71,status:'REJECTED',rejectReason:'已有处理结论'}});
  rejected.state.orders=[{id:7,status:4,escrowStatus:0}];
  const applying=rejected.handleAction('refund',7);const dialog=rejected.dialogs.at(-1);
  dialog.form.elements.reasonType.value='NOT_RECEIVED';await dialog.form.fire('submit');await applying;
  assert.match(rejected.element('notice').textContent,/该申请已被拒绝：已有处理结论/);
  assert.doesNotMatch(rejected.element('notice').textContent,/等待平台审批/);

  let release;
  const late=browser('0',{onRequest(path){if(path==='/api/orders/7/refund')return new Promise(resolve=>{release=resolve;});}});
  Object.assign(late.state,{page:'orders',orders:[{id:7,status:4,escrowStatus:0}]});
  const old=late.handleAction('refund',7);const stale=late.dialogs.at(-1);
  stale.form.elements.reasonType.value='NOT_RECEIVED';const sending=stale.form.fire('submit');
  await new Promise(setImmediate);
  late.resetAccountState();Object.assign(late.state,{user:{id:88,role:0},token:'new-account',page:'home'});await late.renderPage();
  release();await sending;await old;
  assert.equal(stale.removed,true);assert.equal(late.element('notice').textContent,'');
  assert.match(late.element('app').innerHTML,/全部店铺/);
});

test('admin refund decisions require loaded details, acknowledgement or valid rejection, and cancellation sends nothing',async()=>{
  const b=browser();Object.assign(b.state,{role:2,user:{id:2,role:2},page:'refunds',adminRefunds:[{id:41,status:'PENDING'}]});
  const deciding=b.handleAction('refund-approve',41);await new Promise(setImmediate);
  const dialog=b.dialogs.at(-1),form=dialog.form;
  assert.match(dialog.innerHTML,/按原支付渠道退款，餐品不恢复为库存/);
  assert.match(dialog.querySelector('[data-refund-decision-details]').innerHTML,/¥25\.00/);
  await form.fire('submit');assert.equal(b.calls.some(call=>call.path.endsWith('/approve')),false);
  assert.match(form.querySelector('[data-refund-error]').textContent,/请先核对/);
  await form.querySelector('[data-refund-cancel]').fire('click');await deciding;
  assert.equal(b.calls.some(call=>call.path.endsWith('/approve')),false);

  Object.assign(b.state,{adminRefunds:[{id:41,status:'PENDING'}]});
  const rejecting=b.handleAction('refund-reject',41);await new Promise(setImmediate);
  const rejection=b.dialogs.at(-1).form;
  rejection.elements.rejectReason.value='  ';await rejection.fire('submit');
  assert.equal(b.calls.some(call=>call.path.endsWith('/reject')),false);
  rejection.elements.rejectReason.value='配送照片与商品清单核实一致';await rejection.fire('submit');await rejecting;
  const call=b.calls.find(call=>call.path.endsWith('/reject'));
  assert.deepEqual(JSON.parse(call.init.body),{rejectReason:'配送照片与商品清单核实一致'});
  assert.match(b.element('notice').textContent,/处理原因已同步给用户/);
});

test('admin refund approval locks during submission and list preserves type notes and rejection result',async()=>{
  let release;
  const b=browser('0',{adminRefundsPage:{list:[{id:42,orderId:62,reasonType:'QUALITY_ISSUE',reason:'餐盒破损',status:'REJECTED',rejectReason:'已核对配送凭证',processTime:'2026-10-26 13:00'}],total:1,page:1,pageSize:20,hasMore:false},onRequest(path){if(path==='/api/admin/refunds/41/approve')return new Promise(resolve=>{release=resolve;});}});
  Object.assign(b.state,{role:2,user:{id:2,role:2},page:'refunds',adminRefundFilter:''});await b.renderPage();
  assert.match(b.element('app').innerHTML,/餐品质量问题/);assert.match(b.element('app').innerHTML,/餐盒破损/);
  assert.match(b.element('app').innerHTML,/已拒绝/);assert.match(b.element('app').innerHTML,/已核对配送凭证/);
  b.state.adminRefunds=[{id:41,status:'PENDING'}];
  const deciding=b.handleAction('refund-approve',41);await new Promise(setImmediate);
  const dialog=b.dialogs.at(-1),form=dialog.form;form.elements.acknowledged.checked=true;
  const sending=form.fire('submit');await form.fire('submit');
  assert.equal(b.calls.filter(call=>call.path.endsWith('/approve')).length,1);
  await form.querySelector('[data-refund-cancel]').fire('click');assert.equal(dialog.open,true);
  release();await sending;await deciding;
  assert.match(b.element('notice').textContent,/款项已按原支付渠道退回/);
});

test('admin reconciles an approval response lost after the server already refunded',async()=>{
  let detailReads=0;
  const b=browser('0',{refundDetail(){return {id:41,status:++detailReads===1?'PENDING':'REFUNDED',amount:25};},onRequest(path){if(path.endsWith('/41/approve'))throw new Error('响应丢失');}});
  Object.assign(b.state,{role:2,user:{id:2,role:2},page:'refunds',adminRefunds:[{id:41,status:'PENDING'}]});
  const deciding=b.handleAction('refund-approve',41);await new Promise(setImmediate);
  const form=b.dialogs.at(-1).form;form.elements.acknowledged.checked=true;
  await form.fire('submit');await deciding;
  assert.equal(detailReads,2);assert.equal(b.calls.filter(call=>call.path.endsWith('/41/approve')).length,1);
  assert.match(b.element('notice').textContent,/款项已按原支付渠道退回/);
});

test('admin refreshes pending list when latest detail was processed by another operator',async()=>{
  const b=browser('0',{refundDetail:{id:41,status:'REJECTED',rejectReason:'其他运营已核实处理'}});
  Object.assign(b.state,{role:2,user:{id:2,role:2},page:'refunds',adminRefunds:[{id:41,status:'PENDING'}]});
  const deciding=b.handleAction('refund-approve',41);await new Promise(setImmediate);
  const dialog=b.dialogs.at(-1);
  assert.equal(dialog.form.hidden,true);
  await dialog.querySelector('[data-refund-close]').fire('click');await deciding;
  assert.equal(b.calls.some(call=>call.path.endsWith('/approve')),false);
  assert.ok(b.requests.includes('/api/admin/refunds/page?status=PENDING&page=1&pageSize=20'));
  assert.match(b.element('notice').textContent,/其他运营已核实处理/);
});

test('successful order creation clears the selected checkout store',async()=>{
  const b=browser();Object.assign(b.state,{page:'checkout',checkoutStoreId:2,cart:[
    {storeId:2,goodsId:22,specId:0,specName:'',price:20,quantity:1,goods:{name:'商品B',image:''}}
  ]});
  await b.renderCheckout();
  b.element('checkoutCoupon').value='0';b.element('checkoutRemark').value='';
  b.element('checkoutCoupon').onchange();
  await b.handleAction('place-order','',{dataset:{store:'2'}});
  assert.equal(b.state.checkoutStoreId,0);
  const request=b.calls.find(item=>item.path==='/api/orders'&&item.init.method==='POST');
  assert.ok(request);
  assert.equal(JSON.parse(request.init.body).expectTime,'');
});

test('checkout replay of a terminal order reports its current state without asking for another payment',async()=>{
  const b=browser('0',{orderResponse:{id:51,orderNo:'WEB-51',status:6,escrowStatus:2}});
  await b.handleAction('checkout',2);
  await b.handleAction('place-order','',{dataset:{store:'2'},isConnected:true});
  assert.match(b.element('notice').textContent,/已核对到原订单 WEB-51，当前状态：已退款，请查看详情/);
  assert.doesNotMatch(b.element('notice').textContent,/付款|待支付|已创建/);
  assert.equal(b.state.page,'orders');
});

test('checkout exposes immediate delivery only',async()=>{
  const b=browser();Object.assign(b.state,{page:'checkout',checkoutStoreId:2});
  await b.renderCheckout();
  assert.match(b.element('app').innerHTML,/配送时间/);
  assert.match(b.element('app').innerHTML,/立即配送/);
  assert.match(b.element('app').innerHTML,/当前仅支持立即配送/);
  assert.doesNotMatch(b.element('app').innerHTML,/预约|自选时间/);
});

test('user order cancellation actions follow the fulfillment boundary',()=>{
  const b=browser();
  assert.match(b.orderCard({id:1,status:0,items:[],payAmount:20}),/data-action="cancel-order"/);
  assert.match(b.orderCard({id:2,status:1,items:[],payAmount:20}),/data-action="cancel-order"/);
  const production=b.orderCard({id:3,status:2,items:[],payAmount:20});
  assert.doesNotMatch(production,/data-action="cancel-order"/);
  assert.match(production,/订单已进入制作，如需处理请联系平台/);
  const delivery=b.orderCard({id:4,status:3,items:[],payAmount:20});
  assert.doesNotMatch(delivery,/data-action="cancel-order"/);
  assert.match(delivery,/订单已进入配送，如需处理请联系平台/);
});

test('web cancellation explains whether money was charged or refunded',async()=>{
  const pending=browser();pending.state.orders=[{id:61,status:0,payAmount:20}];
  await pending.handleAction('cancel-order',61);
  assert.equal(pending.calls.some(item=>item.path==='/api/orders/61/cancel'),false);
  assert.match(pending.confirmMessages[0],/平台尚未扣款/);

  const paid=browser('0',{confirmResult:true});paid.state.orders=[{id:62,status:1,payAmount:20}];
  await paid.handleAction('cancel-order',62);
  assert.equal(paid.calls.filter(item=>item.path==='/api/orders/62/cancel'&&item.init.method==='PUT').length,1);
  assert.match(paid.confirmMessages[0],/原支付渠道全额退回/);
  assert.match(paid.element('notice').textContent,/原支付渠道全额退回/);
});

test('confirming receipt explains settlement and cancellation sends nothing',async()=>{
  const cancelled=browser();
  await cancelled.handleAction('confirm-order',61);
  assert.equal(cancelled.calls.some(item=>item.path==='/api/orders/61/confirm'),false);
  const confirmed=browser('0',{confirmResult:true});
  await confirmed.handleAction('confirm-order',61);
  assert.equal(confirmed.calls.some(item=>item.path==='/api/orders/61/confirm'&&item.init.method==='PUT'),true);
  assert.equal(confirmed.element('notice').textContent,'已确认收到，订单已完成');
});

test('coupon eligibility includes delivery fee and explains every unavailable boundary',()=>{
  const b=browser();
  const coupon={id:9,storeId:2,name:'满10减10',threshold:10,amount:10,status:0,expireTime:'2099-12-31 23:59:59'};
  assert.equal(b.couponEligible(coupon,2,10,3),true);
  assert.equal(b.checkoutAmounts(10,3,10).payable,3);
  assert.match(b.couponUnavailableReason(coupon,2,10,0),/实付为 0/);
  assert.match(b.couponUnavailableReason({...coupon,amount:14},2,10,3),/超过/);
  assert.match(b.couponUnavailableReason(coupon,1,10,3),/不适用于本店/);
  assert.match(b.couponUnavailableReason({...coupon,status:1},2,10,3),/已使用/);
  assert.match(b.couponUnavailableReason({...coupon,expireTime:'2000-01-01 00:00:00'},2,10,3),/已过期/);
  assert.match(b.couponUnavailableReason({...coupon,threshold:12},2,10,3),/还差 ¥2.00/);
  for(const expireTime of ['',null,'2099','invalid'])assert.match(b.couponUnavailableReason({...coupon,expireTime},2,10,3),/有效期信息异常/);
  assert.equal(b.couponEligible({...coupon,storeId:0,createTime:'2098-01-01 00:00:00'},2,10,3),true,'creation time is not an effective date');
  assert.equal(b.checkoutAmounts(0.1,0.2,0.29).payable,0.01,'money compares in cents');
  assert.equal(b.checkoutAmounts(1.005,0,0).payable,1.01,'positive amounts use decimal half-up at the cent boundary');
});

test('checkout recommends the lowest estimated payable and retains an explicit no-coupon choice',async()=>{
  const coupons=[
    {id:8,storeId:2,name:'可用10元券',threshold:10,amount:10,status:0,expireTime:'2099-12-31 23:59:59'},
    {id:9,storeId:2,name:'过大券',threshold:10,amount:30,status:0,expireTime:'2099-12-31 23:59:59'}
  ];
  const b=browser('0',{coupons});await b.handleAction('checkout',2);
  assert.equal(b.element('checkoutCoupon').value,'8');
  assert.match(b.element('app').innerHTML,/checkoutPayable">13.50/);
  assert.match(b.element('app').innerHTML,/过大券：券额超过/);
  b.element('checkoutCoupon').value='0';b.element('checkoutCoupon').onchange();
  assert.equal(b.element('checkoutPayable').textContent,'23.50');
  await b.renderPage();
  assert.equal(b.element('checkoutCoupon').value,'0');
  await b.handleAction('go','cart');await b.handleAction('checkout',1);
  assert.equal(b.element('checkoutCoupon').value,'0','another store cannot borrow this store coupon');
  await b.handleAction('go','cart');await b.handleAction('checkout',2);
  assert.equal(b.element('checkoutCoupon').value,'0','a user rejection of coupons remains stable');
});

test('checkout restores address remark and coupon after managing addresses and rerendering',async()=>{
  const addresses=[{id:1,name:'家',phone:'13800138000',detail:'家地址',isDefault:true},{id:2,name:'公司',phone:'13800138000',detail:'公司地址'}];
  const b=browser('0',{addresses});await b.handleAction('checkout',2);
  b.element('selectedAddress').value='2';b.element('checkoutForm').onchange({target:{id:'address-2'}});
  b.element('checkoutRemark').value='少辣，不放香菜';b.element('checkoutRemark').oninput();
  b.element('checkoutCoupon').value='0';b.element('checkoutCoupon').onchange();
  const intent=b.state.checkoutIntentKey;
  await b.handleAction('go','account');
  assert.match(b.element('app').innerHTML,/继续确认订单/);
  await b.handleAction('checkout',2);
  assert.equal(b.element('checkoutRemark').value,'少辣，不放香菜');
  assert.equal(b.element('checkoutCoupon').value,'0');
  assert.match(b.element('app').innerHTML,/name="addressId" value="2" checked/);
  assert.equal(b.state.checkoutIntentKey,intent);
  assert.match(b.element('app').innerHTML,/maxlength="255"/);
  assert.match(b.element('app').innerHTML,/仅供商家备餐参考/);
  assert.doesNotMatch(b.element('app').innerHTML,/配送说明/);
});

test('checkout refreshes changed cart prices before a second explicit submit',async()=>{
  const cart=[{storeId:2,storeName:'店铺B',goodsId:22,specId:4,price:10,quantity:1,goods:{name:'商品B'}}];
  const b=browser('0',{cart});await b.handleAction('checkout',2);
  b.element('checkoutRemark').value='不要香菜';b.element('checkoutRemark').oninput();
  cart[0]={...cart[0],price:12,quantity:2};
  await b.handleAction('place-order','',{dataset:{store:'2'},isConnected:true});
  assert.equal(b.calls.some(call=>call.path==='/api/orders'&&call.init.method==='POST'),false);
  assert.match(b.element('app').innerHTML,/确认变更并提交待付款订单/);
  assert.match(b.element('app').innerHTML,/商品小计<\/span><span>¥24.00/);
  assert.equal(b.element('checkoutRemark').value,'不要香菜');
  await b.handleAction('place-order','',{dataset:{store:'2'},isConnected:true});
  const body=JSON.parse(b.calls.find(call=>call.path==='/api/orders'&&call.init.method==='POST').init.body);
  assert.equal(body.items[0].quantity,2);assert.equal(body.items[0].specId,4);assert.equal(body.remark,'不要香菜');
});

test('a selected coupon becoming unavailable is disclosed before submission',async()=>{
  const b=browser();await b.handleAction('checkout',2);
  b.element('checkoutCoupon').value='1';b.element('checkoutCoupon').onchange();
  b.coupons[0].status=1;
  await b.handleAction('place-order','',{dataset:{store:'2'},isConnected:true});
  assert.equal(b.calls.some(call=>call.path==='/api/orders'&&call.init.method==='POST'),false);
  assert.equal(b.element('checkoutCoupon').value,'0');
  assert.match(b.element('app').innerHTML,/原选优惠券已不可用：已使用/);
  assert.match(b.element('app').innerHTML,/checkoutPayable">23.50/);
});

test('unknown checkout results retain the original request across address navigation and an empty cart',async()=>{
  const cart=[{storeId:2,storeName:'店铺B',goodsId:22,specId:0,price:20,quantity:1,goods:{name:'商品B'}}];
  let attempts=0;
  const b=browser('0',{cart,onRequest(path,init){if(path==='/api/orders'&&init.method==='POST'&&++attempts===1){cart.length=0;throw new Error('响应连接中断');}}});
  await b.handleAction('checkout',2);
  b.element('checkoutRemark').value='少盐';b.element('checkoutRemark').oninput();
  await b.handleAction('place-order','',{dataset:{store:'2'},isConnected:true});
  assert.match(b.element('app').innerHTML,/上次提交结果尚未确认/);
  assert.match(b.element('app').innerHTML,/id="checkoutRemark"[^>]*disabled/);
  await b.handleAction('go','account');await b.handleAction('checkout',2);
  assert.equal(b.element('checkoutRemark').value,'少盐');
  assert.match(b.element('app').innerHTML,/核对上次提交结果/);
  b.element('checkoutRemark').value='程序改动不应覆盖原请求';
  await b.handleAction('place-order','',{dataset:{store:'2'},isConnected:true});
  const posts=b.calls.filter(call=>call.path==='/api/orders'&&call.init.method==='POST').map(call=>JSON.parse(call.init.body));
  assert.equal(posts.length,2);assert.deepEqual(posts[0],posts[1]);assert.equal(posts[1].remark,'少盐');
  assert.equal(b.state.checkoutStoreId,0);assert.equal(Object.keys(b.state.checkoutDrafts).length,0);
});

test('a truncated HTTP 200 body keeps checkout replayable after the server removed the cart',async()=>{
  const cart=[{storeId:2,storeName:'店铺B',goodsId:22,specId:0,price:20,quantity:1,goods:{name:'商品B'}}];
  let posts=0;
  const b=browser('0',{cart,onRequest(path,init){if(path==='/api/orders'&&init.method==='POST'&&++posts===1){cart.length=0;return{ok:true,status:200,json:async()=>{throw new SyntaxError('truncated JSON');}};}}});
  await b.handleAction('checkout',2);
  await b.handleAction('place-order','',{dataset:{store:'2'},isConnected:true});
  assert.ok(b.checkoutDraft(2).submittedPayload,'HTTP success alone does not prove the order result was read');
  assert.match(b.element('app').innerHTML,/上次提交结果尚未确认/);
  await b.handleAction('place-order','',{dataset:{store:'2'},isConnected:true});
  const bodies=b.calls.filter(call=>call.path==='/api/orders'&&call.init.method==='POST').map(call=>JSON.parse(call.init.body));
  assert.equal(bodies.length,2);assert.deepEqual(bodies[0],bodies[1]);assert.equal(b.state.page,'orders');
});

test('incomplete envelopes missing orders and in-progress business responses never discard checkout replay',async()=>{
  const replies=[
    {status:200,body:{}},
    {status:200,body:{code:0}},
    {status:200,body:{code:201}},
    {status:200,body:{code:200,data:null}},
    {status:200,body:{code:200,data:{}}},
    {status:200,body:{code:400,message:'订单正在提交中，请稍后重试'}},
    {status:200,body:{code:400,message:'订单可能已提交，请在订单列表核对，不要重复下单'}},
    {status:408,brokenBody:true},
    {status:409,brokenBody:true},
    {status:429,brokenBody:true},
    {status:429,body:{code:429,message:'请求频繁'}},
    {status:500,body:{code:500,message:'服务暂不可用'}}
  ];
  for(const reply of replies){
    const cart=[{storeId:2,storeName:'店铺B',goodsId:22,specId:0,price:20,quantity:1,goods:{name:'商品B'}}];
    let posts=0;
    const b=browser('0',{cart,onRequest(path,init){if(path==='/api/orders'&&init.method==='POST'&&++posts===1){cart.length=0;return{ok:reply.status===200,status:reply.status,json:async()=>{if(reply.brokenBody)throw new SyntaxError('truncated JSON');return reply.body;}};}}});
    await b.handleAction('checkout',2);await b.handleAction('place-order','',{dataset:{store:'2'},isConnected:true});
    assert.ok(b.checkoutDraft(2).submittedPayload,JSON.stringify(reply));
    assert.match(b.element('app').innerHTML,/上次提交结果尚未确认/);
    await b.handleAction('place-order','',{dataset:{store:'2'},isConnected:true});
    const bodies=b.calls.filter(call=>call.path==='/api/orders'&&call.init.method==='POST').map(call=>JSON.parse(call.init.body));
    assert.equal(bodies.length,2);assert.deepEqual(bodies[0],bodies[1]);assert.equal(b.state.page,'orders');
  }
});

test('a known checkout rejection keeps editable inputs and account switches remove all drafts',async()=>{
  const b=browser('0',{onRequest(path,init){if(path==='/api/orders'&&init.method==='POST')return{ok:true,status:200,json:async()=>({code:400,message:'库存不足'})};}});
  await b.handleAction('checkout',2);b.element('checkoutRemark').value='保留的备注';b.element('checkoutRemark').oninput();
  await b.handleAction('place-order','',{dataset:{store:'2'},isConnected:true});
  assert.equal(b.element('checkoutRemark').value,'保留的备注');
  assert.equal(b.checkoutDraft(2).submittedPayload,null);
  assert.match(b.element('notice').textContent,/库存不足/);
  await b.loginWith({phone:'13900000000',password:'secret',loginType:'CUSTOMER'});
  assert.equal(Object.keys(b.state.checkoutDrafts).length,0);assert.equal(b.state.checkoutReturnStoreId,0);
  await b.handleAction('checkout',2);assert.equal(b.element('checkoutRemark').value,'');
});

test('rider statuses describe pickup and delivery without changing customer or merchant semantics',()=>{
  const b=browser();const order={id:42,status:2,items:[],payAmount:20};
  assert.match(b.orderCard(order,'rider'),/待取餐/);assert.match(b.orderCard(order,'rider'),/确认拿到餐品后/);
  assert.doesNotMatch(b.orderCard(order,'rider'),/制作中/);
  assert.match(b.orderCard({...order,status:3},'rider'),/已取餐 · 配送中/);
  assert.match(b.orderCard(order,'merchant'),/制作中/);
});

test('rider delivery requires confirmation and holds one mutation while submitting',async()=>{
  const order={id:42,status:3,items:[],payAmount:20};
  const cancelled=browser('0',{riderOrders:[order]});Object.assign(cancelled.state,{role:3,user:{id:3,role:3},page:'rider-orders',riderOrders:[order]});
  await cancelled.handleAction('rider-deliver',42,{isConnected:true});
  assert.equal(cancelled.calls.length,0);assert.match(cancelled.confirmMessages[0],/交给用户.*约定的地点/);
  let release;const pending=new Promise(resolve=>{release=resolve;});
  const b=browser('0',{confirmResult:true,riderOrders:[order],onRequest(path){if(path.endsWith('/deliver'))return pending;}});
  Object.assign(b.state,{role:3,user:{id:3,role:3},page:'rider-orders',riderOrders:[order]});
  const button={isConnected:true,disabled:false,textContent:'送达'};
  const first=b.handleAction('rider-deliver',42,button);await Promise.resolve();
  await b.handleAction('rider-deliver',42,button);
  assert.equal(b.calls.filter(call=>call.path.endsWith('/deliver')).length,1);assert.equal(button.disabled,true);
  release();await first;assert.match(b.element('notice').textContent,/送达已确认/);
});

test('rider reconciles lost grab pickup and delivery responses using assigned orders',async()=>{
  for(const [flow,status,before]of [['grab',2,2],['pickup',3,2],['deliver',4,3]]){
    const b=browser('0',{confirmResult:true,riderOrders:[{id:42,status,items:[],payAmount:20}],onRequest(path){if(path.endsWith('/'+flow))throw new Error('响应丢失');}});
    Object.assign(b.state,{role:3,user:{id:3,role:3},page:'rider-orders',riderOrders:[{id:42,status:before}]});
    await b.handleAction('rider-'+flow,42,{isConnected:true});
    assert.ok(b.requests.includes('/api/rider/orders'));
    assert.match(b.element('notice').textContent,/已确认，已核对本人配送订单/);
    assert.equal(b.state.riderOrders[0].status,status);
  }
});

test('rider failed reconciliation reports an unknown result and invalid pickup sends no mutation',async()=>{
  const b=browser('0',{onRequest(path){if(path.includes('/api/rider/orders'))throw new Error('网络不可用');}});
  Object.assign(b.state,{role:3,user:{id:3,role:3},page:'rider-orders',riderOrders:[{id:42,status:2}]});
  await b.handleAction('rider-pickup',42,{isConnected:true});
  assert.match(b.element('notice').textContent,/取餐结果尚未确认/);
  assert.doesNotMatch(b.element('notice').textContent,/已确认，/);
  b.calls.length=0;b.state.riderOrders[0].status=4;
  await b.handleAction('rider-pickup',42,{isConnected:true});assert.equal(b.calls.length,0);
});

test('rider copies a full address with truthful manual fallback and terminal privacy',async()=>{
  const order={id:42,storeId:2,status:2,items:[],payAmount:20,address:{mapAddress:'朝阳大厦',doorDetail:'3 栋 1201',detail:'旧地址'}};
  const copied=[];
  const b=browser('0',{navigator:{clipboard:{async writeText(value){copied.push(value);}}}});
  Object.assign(b.state,{role:3,user:{id:3,role:3},page:'rider-orders',riderOrders:[order]});
  await b.handleAction('rider-copy-address',42,{isConnected:true});
  assert.deepEqual(copied,['朝阳大厦 3 栋 1201']);assert.match(b.element('notice').textContent,/已复制/);
  const fallback=browser('0',{navigator:{clipboard:{async writeText(){throw new Error('denied');}}}});
  Object.assign(fallback.state,{role:3,user:{id:3,role:3},page:'rider-orders',riderOrders:[order]});
  await fallback.handleAction('rider-copy-address',42,{isConnected:true});
  assert.equal(fallback.promptMessages[0].value,'朝阳大厦 3 栋 1201');
  assert.match(fallback.promptMessages[0].message,/手动复制/);assert.doesNotMatch(fallback.element('notice').textContent,/已复制/);
  await fallback.handleAction('rider-store-address',42,{isConnected:true});
  assert.match(fallback.element('notice').textContent,/门店暂未提供取餐地址/);
  fallback.state.riderOrders=[{...order,status:4}];
  await fallback.handleAction('rider-copy-address',42,{isConnected:true});assert.equal(fallback.promptMessages.length,1);
  assert.doesNotMatch(fallback.orderCard({...order,status:4},'rider'),/朝阳大厦|1201|复制收货地址|查看门店地址/);
});
