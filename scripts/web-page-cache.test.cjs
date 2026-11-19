const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const fixture=fs.readFileSync('scripts/web-browse.test.cjs','utf8');
const browser=new Function('require',fixture.slice(0,fixture.indexOf('const cardCount='))+';return browser;')(require);
const reply=data=>({ok:true,status:200,json:async()=>({code:200,data})});
const tick=()=>new Promise(setImmediate);
function advance(b,ms){const NativeDate=Date;const now=Date.now()+ms;b.context.Date=class extends NativeDate{static now(){return now;}};}

test('returning to a warm page keeps content visible and reuses session data',async()=>{
 const b=browser();await b.renderPage();
 const requests=b.requests.length;
 await b.handleAction('go','home');
 const pending=b.handleAction('go','discover');
 assert.doesNotMatch(b.element('app').innerHTML,/正在读取服务端数据/);
 await pending;
 assert.equal(b.requests.length,requests,'fresh page visits must not refetch the same data');
 assert.match(b.element('app').innerHTML,/发现好味道/);
});

test('expired pages show cached data while refreshing and keep it after a network failure',async()=>{
 let refresh=false,finish;
 const b=browser('0',{onRequest(path){if(refresh&&path==='/api/stores')return new Promise(resolve=>finish=resolve);}});
 await b.renderPage();advance(b,120000);refresh=true;
 await b.renderPage();await tick();
 assert.match(b.element('storeGrid').innerHTML,/店铺1/);
 assert.doesNotMatch(b.element('app').innerHTML,/正在读取服务端数据/);
 assert.equal(typeof finish,'function');
 finish({ok:false,status:503,json:async()=>({code:503,message:'暂时不可用'})});await tick();
 assert.match(b.element('storeGrid').innerHTML,/店铺1/);
 assert.doesNotMatch(b.element('app').innerHTML,/暂时不可用/);
});

test('manual refresh bypasses cache and successful writes invalidate cached reads',async()=>{
 let name='原店铺';const b=browser('0',{onRequest(path){if(path==='/api/stores')return reply([{id:1,name}]);}});
 await b.renderPage();name='刷新后的店铺';
 await b.handleAction('refresh');assert.match(b.element('storeGrid').innerHTML,/刷新后的店铺/);
 name='收藏后更新';await b.handleAction('favorite',1);
 await b.renderPage();assert.match(b.element('storeGrid').innerHTML,/收藏后更新/);
});

test('old account requests cannot populate the next account cache',async()=>{
 let finish,delayed=false;
 const b=browser('0',{onRequest(path){if(delayed&&path==='/api/orders')return new Promise(resolve=>finish=resolve);return undefined;}});
 Object.assign(b.state,{user:{id:2,role:0},page:'orders'});await b.renderPage();
 advance(b,120000);delayed=true;await b.renderPage();await tick();
 b.resetAccountState();Object.assign(b.state,{token:'other',user:{id:3,role:0},role:0,page:'home'});
 finish(reply([{id:777,storeName:'旧账号私有订单',status:0}]));await tick();
 delayed=false;b.state.page='orders';await b.renderPage();
 assert.doesNotMatch(b.element('app').innerHTML,/旧账号私有订单/);
 assert.equal(b.state.orders.length,0);
});

test('background changes arrive without a loading screen and preserve the selected browse section',async()=>{
 let version='原榜单';
 const b=browser('0',{onRequest(path){if(path.startsWith('/api/rankings/stores'))return reply([{id:9,name:version}]);}});
 await b.renderPage();await b.handleAction('rank-stores');
 await b.handleAction('go','home');await b.handleAction('go','discover');
 assert.match(b.element('browseResult').innerHTML,/热销榜/);
 assert.match(b.element('storeGrid').innerHTML,/原榜单/);
 version='新榜单';advance(b,120000);await b.renderPage();await tick();await tick();
 assert.match(b.element('storeGrid').innerHTML,/新榜单/);
 assert.doesNotMatch(b.element('app').innerHTML,/正在读取服务端数据/);
});

test('a late response from before a write cannot refill the same account cache',async()=>{
 let first=true,finish;
 const b=browser('0',{onRequest(path){if(path==='/api/orders'&&first){first=false;return new Promise(resolve=>finish=resolve);}}});
 Object.assign(b.state,{page:'orders',user:{id:2,role:0}});
 const pending=b.renderPage();await tick();
 await b.handleAction('favorite',1);
 finish(reply([{id:3,storeName:'写入前的旧订单',status:0}]));await pending;
 await b.renderPage();
 assert.doesNotMatch(b.element('app').innerHTML,/写入前的旧订单/);
 assert.equal(b.requests.filter(path=>path==='/api/orders').length,2);
});

test('background refresh never replaces a focused input',async()=>{
 let refresh=false,finish;
 const b=browser('0',{onRequest(path){if(refresh&&path==='/api/stores')return new Promise(resolve=>finish=resolve);}});
 await b.renderPage();refresh=true;advance(b,120000);await b.renderPage();
 b.context.document.activeElement={matches:()=>true};b.element('app').contains=()=>true;
 finish(reply([{id:8,name:'后台最新店铺'}]));await tick();await tick();
 assert.match(b.element('storeGrid').innerHTML,/店铺1/);
 b.context.document.activeElement=null;await b.renderPage();
 assert.match(b.element('storeGrid').innerHTML,/后台最新店铺/);
});

test('checkout always verifies fresh cart and prices even within the cache lifetime',async()=>{
 const b=browser();Object.assign(b.state,{page:'checkout',checkoutStoreId:2});
 await b.renderPage();const count=b.requests.filter(path=>path==='/api/cart').length;
 await b.renderPage();
 assert.equal(b.requests.filter(path=>path==='/api/cart').length,count+1);
});

test('unsubmitted search text stays on its page without changing the server search',async()=>{
 const b=browser();await b.renderPage();
 b.element('storeSearch').value='尚未提交的关键词';b.element('storeSearch').oninput();
 await b.handleAction('go','home');await b.handleAction('go','discover');
 assert.match(b.element('app').innerHTML,/value="尚未提交的关键词"/);
 assert.equal(b.state.search,'');
 assert.ok(b.requests.every(path=>!path.startsWith('/api/search?keyword=')));
 b.resetAccountState();assert.equal(Object.keys(b.state.browseDrafts).length,0);
});
