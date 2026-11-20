const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME || 'C:/Program Files/Huawei/DevEco Studio', 'tools/ohpm/node_modules/typescript'));
const source = name => fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/', name), 'utf8');
function method(text, name) {
  const match = new RegExp('^  (?:private )?(?:async )?' + name + '[(]', 'm');
  // Match method boundaries using the production file's two-space indentation.
  const start = text.search(match);
  assert.ok(start >= 0, name);
  const lineEnd = text.indexOf('\n', start);
  if (text.slice(start, lineEnd).trim().endsWith('}')) return text.slice(start, lineEnd);
  return text.slice(start, text.indexOf('\n  }', start) + 4);
}
function pageRuntime(name, role) {
  const text = source('pages/' + name + '.ets');
  const load = name === 'OrderListPage' ? 'refreshOrders' : 'loadOrders';
  const names = ['canApplyOrders', load, 'onPageHide', 'onPageShow'];
  const methods = names.map(n => method(text, n)).join('\n');
  const pending = [], storage = new Map([['user', { id: 1, role }]]), state = { epoch: 1 };
  const exports = {};
  const network = () => new Promise(resolve => pending.push(resolve));
  const code = ts.transpileModule('export class Page { ' + methods + '\n}', { compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS } }).outputText;
  vm.runInNewContext(code, { exports, AppStorage: { get: k => storage.get(k) }, UserRole: { CUSTOMER: 0, MERCHANT: 1, ADMIN: 2 }, getAuthSessionEpoch: () => state.epoch, fetchUserOrdersPageApi: network, fetchMerchantOrdersPageApi: network, get: network });
  const page = new exports.Page();
  Object.assign(page, { pageActive: true, loggedIn: true, ordersRequestVersion: 0, ordersLoading: false, loading: false, currentStatus: -1, pageOrders: [{ id: 9 }], allOrders: [{ id: 9 }], orders: [{ id: 9 }], currentPage: 2, page: 2, totalOrders: 5, total: 5, hasMoreOrders: true, hasMore: true, refreshDataSource() {}, applyFilter() {} });
  return { page, pending, storage, state, load, data: name === 'OrderListPage' ? 'pageOrders' : name === 'MerchantOrdersPage' ? 'allOrders' : 'orders', admin: name === 'AdminOrderPage' };
}
const configs = [['OrderListPage', 0], ['MerchantOrdersPage', 1], ['AdminOrderPage', 2]];
const result = id => ({ list: [{ id }], total: 10, page: 3, hasMore: true });
for (const [name, role] of configs) {
  test(name + ': failed refresh/append preserve data, pagination and allow retry', async () => {
    for (const append of [false, true]) {
      const r = pageRuntime(name, role), running = r.page[r.load](3, append);
      r.pending.shift()(r.admin ? { code: 500 } : null); await running;
      assert.equal(r.page[r.data][0].id, 9);
      assert.equal(r.page.currentPage, 2); assert.equal(r.page.page, 2);
      assert.equal(r.page.ordersError, true); assert.equal(r.page.loading, false); assert.equal(r.page.ordersLoading, false);
      const retry = r.page[r.load](3, append); r.pending.shift()(r.admin ? { code: 200, data: result(10) } : result(10)); await retry;
      assert.equal(r.page.ordersError, false); assert.equal(r.page[r.data].at(-1).id, 10);
    }
  });
  test(name + ': epoch, owner, page lifecycle and request version reject late results', async () => {
    for (const change of ['epoch', 'owner', 'hide', 'newer']) {
      const r = pageRuntime(name, role), old = r.page[r.load]();
      if (change === 'epoch') r.state.epoch++;
      if (change === 'owner') r.storage.set('user', { id: 2, role });
      if (change === 'hide') r.page.onPageHide();
      if (change === 'newer') { const newer = r.page[r.load](); r.pending[1](r.admin ? { code: 200, data: result(22) } : result(22)); await newer; }
      r.pending[0](r.admin ? { code: 200, data: result(11) } : result(11)); await old;
      assert.equal(r.page[r.data][0].id, change === 'newer' ? 22 : 9, change);
    }
  });
}
for (const [name, role] of configs.slice(0,2)) {
  test(name + ': quick return retains data and pagination; expired return refreshes once', async () => {
    const r=pageRuntime(name,role);
    r.page.lastOrdersLoadedAt=Date.now();r.page.onPageHide();r.page.onPageShow();
    assert.equal(r.pending.length,0);assert.equal(r.page.currentPage,2);assert.equal(r.page[r.data][0].id,9);
    r.page.lastOrdersLoadedAt=Date.now()-16000;r.page.onPageShow();r.page.onPageShow();
    assert.equal(r.pending.length,1,'lifecycle callbacks must not duplicate an in-flight refresh');
    if(name==='OrderListPage')assert.equal(r.page.isRefreshing,false,'existing list refresh is silent');
    r.pending[0](result(22));await new Promise(setImmediate);
    assert.equal(r.page[r.data][0].id,22);
    const forced=r.page[r.load]();assert.equal(r.pending.length,2,'explicit business refresh bypasses the return window');
    r.pending[1](result(23));await forced;
  });
}
function searchRuntime() {
  let text=source('pages/SearchPage.ets');
  let dataSource=source('model/SearchStoreDataSource.ets').split('\n').slice(1).join('\n');
  if(process.env.SEARCH_MUTATION==='key') dataSource=dataSource.replace(" + ':' + this.revision.toString()",'');
  if(process.env.SEARCH_MUTATION==='request') text=text.replace('request !== this.searchRequest || !this.loggedIn || ownerId !== this.searchOwner.id ||','!this.loggedIn || ownerId !== this.searchOwner.id ||');
  const exports={},pending=[],state={epoch:1,tops:0}, history=[];
  const names=['doSearch','resetSearch','updateResults','onAddressChange','onSearchOwnerChange','onPageHide','aboutToDisappear','retrySearch'];
  let presentation=source('common/StorePresentation.ets').replace(/^import.*\r?\n/gm,'');
  if(process.env.SEARCH_MUTATION==='delivery-filter') presentation=presentation.replace('distance <= meters / 1000 + 1e-9', 'true');
  const code=presentation+'\n'+dataSource+'\nexport class Page {'+names.map(name=>method(text,name)).join('\n')+'}';
  vm.runInNewContext(ts.transpileModule(code,{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText,{
    exports,clearTimeout,Edge:{Top:0},DELIVERY_RANGE:{ORDER_CONFIRM_KM:5},getAuthSessionEpoch:()=>state.epoch,
    searchStoresResultApi:(keyword)=>new Promise(resolve=>pending.push({keyword,resolve})),
    AppStorage:{get:()=>null},addSearchHistory:async keyword=>history.push(keyword),logInfo(){},promptAction:{showToast(){}}
  });
  const page=Object.assign(new exports.Page(),{loggedIn:true,ownerId:1,searchOwner:{id:1},searchText:'first',searchRequest:0,
    suggestTimer:-1,results:new exports.SearchStoreDataSource(),resultCount:0,loadHistory:async()=>{},
    currentAddress:null,deliverableOnly:false,matchedStores:[],
    resultScroller:{scrollEdge:()=>{state.tops++;}}});
  return {page,pending,state,history,presentation:exports};
}
const searchReply=(stores)=>({success:true,stores});

test('search delivery filter uses the current delivery address and preserves the original order and match set',async()=>{
  const {page,pending,presentation}=searchRuntime();
  const first={id:1,latitude:22,longitude:108,deliveryRadius:8000,deliverable:false};
  const second={id:2,latitude:22.1,longitude:108,deliveryRadius:2000,deliverable:true};
  const unknown={id:3,latitude:22,longitude:108,deliveryRadius:0,deliverable:true};
  page.currentAddress={latitude:22.05,longitude:108};
  const request=page.doSearch();
  page.deliverableOnly=true;
  pending[0].resolve(searchReply([second,unknown,first])); await request;
  assert.deepEqual(Array.from({length:page.resultCount},(_,i)=>page.results.getData(i).id),[1]);
  assert.match(presentation.storeDeliveryText(first,page.currentAddress),/可配送，下单需确认/);
  assert.match(presentation.storeDeliveryText(second,page.currentAddress),/超出配送范围/);
  page.currentAddress={latitude:22.1,longitude:108};page.onAddressChange();
  assert.equal(page.resultCount,1);assert.equal(page.results.getData(0).id,2);
  page.currentAddress={latitude:0,longitude:0};page.onAddressChange();
  assert.equal(page.deliverableOnly,false);
  assert.deepEqual(Array.from({length:page.resultCount},(_,i)=>page.results.getData(i).id),[2,3,1]);
  assert.match(presentation.storeDeliveryText(unknown,page.currentAddress,true),/收货地址未定位/);
  assert.equal(pending.length,1);
  assert.match(presentation.storeRatingText(5,4),/4 人评分 · 评价较少/);
  assert.doesNotMatch(presentation.storeRatingText(4,5),/评价较少/);
  assert.equal(presentation.storeRatingText(5,0),'暂无评分');
});

test('search replaces same-store rows with a new key, notifies the list and starts new results at the top',async()=>{
  const {page,pending,state}=searchRuntime();let reloads=0;
  const listener={onDataReloaded(){reloads++;}};
  page.results.registerDataChangeListener(listener);page.results.registerDataChangeListener(listener);
  const a=page.doSearch();pending[0].resolve(searchReply([{id:4,distance:'2km',monthlySales:1}]));await a;
  const key=page.results.keyFor(page.results.getData(0));
  const b=page.doSearch();pending[1].resolve(searchReply([{id:4,distance:'8km',monthlySales:8}]));await b;
  assert.notEqual(page.results.keyFor(page.results.getData(0)),key,'same store must get a fresh row identity');
  assert.equal(page.results.getData(0).distance,'8km');assert.equal(page.results.getData(0).monthlySales,8);
  assert.equal(page.resultCount,1);assert.equal(reloads,2);assert.equal(state.tops,2);
  page.results.unregisterDataChangeListener(listener);page.resetSearch();assert.equal(reloads,2);
});

test('late search response cannot overwrite newer results',async()=>{
  const {page,pending,history}=searchRuntime();
  const a=page.doSearch();page.searchText='second';const b=page.doSearch();
  pending[1].resolve(searchReply([{id:2}]));await b;
  pending[0].resolve(searchReply([{id:1}]));await a;
  assert.equal(page.results.getData(0).id,2,'latest request must own the list');assert.deepEqual(history,['second']);
});

test('search cancels on hide and preserves rows and row identities; clearing or replacing the account clears them',async()=>{
  const {page,pending,state}=searchRuntime();
  const a=page.doSearch();pending[0].resolve(searchReply([{id:8}]));await a;
  const key=page.results.keyFor(page.results.getData(0));
  const b=page.doSearch();page.onPageHide();const tops=state.tops;
  pending[1].resolve(searchReply([{id:1}]));await b;
  assert.equal(page.searching,false);assert.equal(page.results.getData(0).id,8);
  assert.equal(page.results.keyFor(page.results.getData(0)),key);assert.equal(state.tops,tops);
  for(const end of ['clear','logout','account','epoch']) {
    page.loggedIn=true; const next=page.doSearch();
    if(end==='logout') { page.loggedIn=false;page.resetSearch(); }
    else if(end==='account') { page.searchOwner={id:2};page.onSearchOwnerChange(); }
    else if(end==='epoch') { state.epoch++; }
    else { page.resetSearch(); }
    pending.at(-1).resolve(searchReply([{id:99}]));await next;
    assert.equal(page.resultCount,0,end);assert.equal(page.results.totalCount(),0,end);
  }
});

test('search retry keeps the failed keyword and distinguishes an empty successful response',async()=>{
  const {page,pending}=searchRuntime();
  const a=page.doSearch();pending[0].resolve({success:false,stores:[]});await a;
  assert.equal(page.searchFailed,true);page.retrySearch();assert.equal(pending[1].keyword,'first');
  pending[1].resolve(searchReply([]));await new Promise(resolve=>setImmediate(resolve));
  assert.equal(page.searchFailed,false);assert.equal(page.hasSearched,true);assert.equal(page.resultCount,0);
});
test('retained home pauses its ticker offscreen and includes elapsed hidden time on return',()=>{
  const text=source('components/home/HomePage.ets'),exports={};let now=1000,callback,stopped=0;
  const code=['startSeckillTicker','stopSeckillTicker','seckillRemainSeconds'].map(name=>method(text,name)).join('\n');
  vm.runInNewContext(ts.transpileModule('export class Page {'+code+'}',{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText,
    {exports,Date:{now:()=>now},Math,setInterval:fn=>{callback=fn;return 1;},clearInterval:()=>stopped++});
  const page=new exports.Page();Object.assign(page,{seckillTimer:-1,seckillPausedAt:0,seckillTick:0});
  page.startSeckillTicker();for(let i=0;i<5;i++)callback();
  page.stopSeckillTicker();assert.equal(stopped,1);now+=60000;
  page.startSeckillTicker();assert.equal(page.seckillRemainSeconds({remainSeconds:120}),55);
});
function exportedFunction(text, name) {
  const start = text.indexOf('export async function ' + name + '(');
  assert.ok(start >= 0, name);
  return text.slice(start, text.indexOf(String.fromCharCode(10) + '}', start) + 2);
}
function uploadRuntime(responses, refreshResult = 1) {
  let progressCallback;
  const exports = {}, tokens = [], pending = [], counters = { refresh: 0, expire: 0, open: 0, close: 0, destroy: 0, toast: 0 };
  const context = {
    exports, authToken: 'old', refreshToken: 'refresh-old', authSessionEpoch: 1, lastApiErrorMessage: '',
    fileIo: { openSync: () => { counters.open++; return { fd: 3 }; }, statSync: () => ({ size: 4 }), readSync() {}, closeSync() { counters.close++; }, OpenMode: { READ_ONLY: 0 } },
    http: { createHttp: () => ({ on(type, callback) { progressCallback = callback; }, request: async (_, options) => { progressCallback?.({sendSize:2,totalSize:4}); tokens.push(options.header.Authorization); const next = responses.shift(); if (typeof next === 'function') return await next(context); return next; }, destroy() { counters.destroy++; } }), RequestMethod: { POST: 1 }, HttpDataType: { STRING: 1 } },
    API_CONFIG: { CONNECT_TIMEOUT: 1000, TIMEOUT: 2000 }, buildFileName: () => 'a.jpg', buildContentType: () => 'image/jpeg', logError() {},
    refreshAfterUnauthorized: async () => { counters.refresh++; context.authToken = 'new'; return refreshResult; },
    expireLocalSession: async () => { counters.expire++; context.authSessionEpoch++; context.authToken = ''; },
    notifyApiError: () => counters.toast++
  };
  const code = ts.transpileModule(exportedFunction(source('service/HttpClient.ets'), 'uploadFile'), { compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS } }).outputText;
  vm.runInNewContext(code, context);
  return { context, counters, tokens, upload: (show, progress) => exports.uploadFile('/upload', '/a.jpg', show, progress) };
}
const unauthorized = { responseCode: 401, result: '' };
const uploaded = { responseCode: 200, result: JSON.stringify({ code: 200, data: { url: '/uploads/a.jpg' } }) };

test('upload reports sent bytes then success and rejects oversize before allocating or sending', async () => {
  const r=uploadRuntime([uploaded]),progress=[];
  await r.upload(false,percent=>progress.push(percent));assert.deepEqual(progress,[50,100]);
  const large=uploadRuntime([uploaded]);large.context.fileIo.statSync=()=>({size:5*1024*1024+1});
  assert.equal(await large.upload(false),null);assert.equal(large.tokens.length,0);assert.equal(large.counters.close,1);
});
test('upload retries HTTP and business 401 once after refresh, reusing file and rotating token', async () => {
  for (const first of [unauthorized, { responseCode: 200, result: JSON.stringify({ code: 401 }) }]) {
    const r = uploadRuntime([first, uploaded]);
    assert.equal((await r.upload(true)).url, '/uploads/a.jpg');
    assert.deepEqual(r.tokens, ['Bearer old', 'Bearer new']);
    assert.deepEqual(r.counters, { refresh: 1, expire: 0, open: 1, close: 1, destroy: 2, toast: 0 });
  }
});
test('upload second 401 expires once without a third attempt or duplicate toast', async () => {
  const r = uploadRuntime([unauthorized, unauthorized, uploaded]);
  assert.equal(await r.upload(true), null);
  assert.equal(r.tokens.length, 2); assert.equal(r.counters.refresh, 1); assert.equal(r.counters.expire, 1); assert.equal(r.counters.toast, 1);
});
test('upload transient refresh failure preserves login and does not retry non-401 failures', async () => {
  for (const [response, refresh] of [[unauthorized, 0], [{ responseCode: 500, result: '' }, 1]]) {
    const r = uploadRuntime([response], refresh);
    assert.equal(await r.upload(false), null); assert.equal(r.tokens.length, 1); assert.equal(r.counters.expire, 0); assert.equal(r.counters.toast, 0);
  }
});
test('late upload success from a replaced session is ignored', async () => {
  const r = uploadRuntime([async context => { context.authSessionEpoch++; return uploaded; }]);
  assert.equal(await r.upload(true), null); assert.equal(r.counters.toast, 0); assert.equal(r.counters.close, 1); assert.equal(r.counters.destroy, 1);
});
