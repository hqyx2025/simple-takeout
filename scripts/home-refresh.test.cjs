const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME || 'C:/Program Files/Huawei/DevEco Studio', 'tools/ohpm/node_modules/typescript'));
const read = file => fs.readFileSync(path.join(__dirname, '../entry/src/main/ets', file), 'utf8');
const tick = () => new Promise(resolve => setImmediate(resolve));
const ports = ['categories', 'stores', 'banners', 'announcements', 'special', 'seckills'];
const geo = ['stores', 'special', 'seckills'];
const location = (latitude, longitude = 114) => ({ latitude, longitude });
const deferred = () => { let release; const promise = new Promise(resolve => { release = resolve; }); return { promise, release }; };
const roles = { CUSTOMER: 0, MERCHANT: 1, ADMIN: 2, RIDER: 3 };

function createHome() {
  const state = { epoch: 1, now: 100000, address: location(30), user: { id: 1, role: roles.CUSTOMER } };
  const registry = new Map([['privacyConsent', true], ['categoryList', []]]), requests = [], replies = {};
  const source = read('components/home/HomePage.ets');
  const runtime = source.slice(source.indexOf('const HOME_REFRESH_WINDOW_MS'), source.indexOf('// 定义快捷入口'));
  let cls = source.slice(source.indexOf('export struct HomePage'), source.indexOf('  // ============ 限时秒杀'));
  cls = cls.replace('export struct', 'export class').replace(/^  (?:@[\w]+(?:\([^)]*\))? )+/gm, '  ');
  const coordinateCheck = source.slice(source.indexOf('  private hasCurrentLocation()'), source.indexOf('  private getCategoryRowsTemplate()'));
  const storage = read('service/AppStorageManager.ets').replaceAll('\r\n', '\n');
  const stores = storage.slice(storage.indexOf('export async function syncStoresFromServer'), storage.indexOf('/**\n * 从后端拉取指定店铺商品'));
  const categories = storage.slice(storage.indexOf('export async function syncCategoriesFromServer'), storage.indexOf('/**\n * 从后端拉取店铺列表'));
  const stateAccess = storage.slice(storage.indexOf('function getCurrentLatitude'), storage.indexOf('/**\n * 远程确认收货'));
  let code = read('model/SearchStoreDataSource.ets').replace(/^import.*\n/, '') +
    read('common/Constants.ets').match(/export const DELIVERY_RANGE: DeliveryRange = \{[^}]+\}/)[0] + '\n' +
    runtime + cls + coordinateCheck + '}\n' + categories + stores + stateAccess + '\nlet storesSyncVersion = 0;';
  if (process.env.HOME_REFRESH_MUTATION === 'dedupe') code = code.replace('section.pending !== null || (!force', '(!force');
  if (process.env.HOME_REFRESH_MUTATION === 'scope') code = code.replace('(!locationScoped || (place === this.locationVersion && key === this.coordinatesKey()))', 'true');
  if (process.env.HOME_REFRESH_MUTATION === 'radius') code = code.replace('distance <= DELIVERY_RANGE.NEARBY_KM', 'Math.round(distance * 10) / 10 <= DELIVERY_RANGE.NEARBY_KM');
  const fetch = async (port, args = []) => {
    requests.push({ port, args });
    return replies[port] ? replies[port](args) : [];
  };
  const globals = {
    exports: {}, Date: { now: () => state.now }, getAuthSessionEpoch: () => state.epoch,
    UserRole: roles, isLoggedIn: () => state.user !== null,
    AppStorage: {
      get: key => key === 'currentAddress' ? state.address : key === 'user' ? state.user : registry.get(key),
      setOrCreate: (key, value) => registry.set(key, value)
    },
    createDefaultCategories: () => [{ id: 9, name: 'default' }],
    fetchCategoriesResultApi: () => fetch('categories'), fetchStoresResultApi: (_, ...args) => fetch('stores', args),
    fetchBannersResultApi: () => fetch('banners'), fetchAnnouncementsResultApi: () => fetch('announcements'),
    fetchSpecialGoodsResultApi: (_, ...args) => fetch('special', args), fetchSeckillsResultApi: (_, ...args) => fetch('seckills', args),
    logError() {}, Scroller: class {}, BreakpointSystem: class { register() {} unregister() {} }
  };
  vm.runInNewContext(ts.transpileModule(code, { compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS } }).outputText, globals);
  const page = Object.assign(new globals.exports.HomePage(), { loggedIn: true, currentAddress: state.address,
    startSeckillTicker() {}, stopSeckillTicker() {}, getUIContext: () => ({ getHostContext() {} }) });
  return { state, page, replies, registry, requests,
    move(address) { state.address = address; page.currentAddress = address; page.onCurrentAddressChange(); },
    show(visible) { page.pageVisible = visible; page.onPageVisibilityChange(); },
    async expectCalls(label, expected) {
      await tick();
      const actual = requests.splice(0).map(r => r.port);
      if (process.env.HOME_REFRESH_REPORT) console.log(JSON.stringify({ name: label, ...Object.fromEntries(ports.map(port => [port, actual.filter(p => p === port).length])) }));
      assert.deepEqual(actual.sort(), [...expected].sort(), label);
    }
  };
}

test('homepage coalesces in-flight events, reuses recent results and refreshes only the necessary endpoints', async () => {
  const r = createHome();
  r.page.aboutToAppear(); r.page.onLoginStateChange(); r.show(true);
  await r.expectCalls('first', ports);
  r.show(false); r.state.now += 1000; r.show(true);
  await r.expectCalls('return <5s', []);
  r.move({ ...location(30), id: 200 });
  await r.expectCalls('same-coordinates', []);
  r.move(location(31));
  await r.expectCalls('new-coordinates', geo);
  r.page.refreshHomeData(true);
  await r.expectCalls('pull-to-refresh', ports);
  r.show(false); r.state.now += 5000; r.show(true);
  await r.expectCalls('return at 5s', ports);
});

test('slow or failed sections neither block other results nor discard their own usable content', async () => {
  const r = createHome(), slow = deferred();
  r.replies.banners = () => [{ id: 12 }];
  r.page.aboutToAppear(); await tick();
  assert.equal(r.page.banners[0].id, 12);
  r.requests.length = 0;
  r.replies.banners = () => slow.promise;
  r.replies.special = () => [{ id: 34 }];
  r.page.refreshHomeData(true); await tick();
  assert.equal(r.page.specialGoods[0].id, 34);
  assert.equal(r.page.specialLoading, false);
  assert.equal(r.page.isRefreshing, true);
  slow.release(null); await tick();
  assert.equal(r.page.banners[0].id, 12);
  assert.equal(r.page.homeFailed, true);
  assert.equal(r.page.isRefreshing, false);
  r.requests.length = 0;
  r.replies.banners = () => [{ id: 56 }];
  r.show(false); r.show(true);
  await r.expectCalls('return retries failed section', ['banners']);
  assert.equal(r.page.banners[0].id, 56);
  assert.equal(r.page.homeFailed, false);
});

test('cold homepage starts at most three requests and a free lane takes the next section', async () => {
  const r = createHome();
  const deferredByPort = Object.fromEntries(ports.map(port => [port, deferred()]));
  ports.forEach(port => { r.replies[port] = () => deferredByPort[port].promise; });
  r.page.aboutToAppear(); await tick();
  assert.equal(r.requests.length, 3);
  const first = r.requests[0].port;
  deferredByPort[first].release([]); await tick();
  assert.equal(r.requests.length, 4);
  ports.filter(port => port !== first).forEach(port => deferredByPort[port].release([]));
  await tick();
  assert.equal(r.requests.length, ports.length);
  assert.equal(r.page.isRefreshing, false);
});

test('old coordinate, account and destroyed or hidden page responses cannot overwrite current results', async () => {
  const r = createHome(), first = deferred(), oldStores = deferred();
  r.replies.special = () => first.promise;
  r.replies.stores = () => oldStores.promise;
  r.page.aboutToAppear(); await tick();
  r.replies.special = () => [{ id: 2 }]; r.replies.stores = () => [{ id: 2 }];
  r.move(location(31)); await tick();
  r.replies.special = () => [{ id: 3 }]; r.replies.stores = () => [{ id: 3 }];
  r.move(location(30)); await tick();
  first.release([{ id: 1 }]); oldStores.release([{ id: 1 }]); await tick();
  assert.equal(r.page.specialGoods[0].id, 3, 'A→B→A must reject the first A response');
  assert.equal(r.registry.get('allStores')[0].id, 3);

  for (const reason of ['hidden', 'destroyed', 'logout']) {
    const old = deferred();
    r.replies.banners = () => old.promise;
    r.page.refreshHomeData(true); await tick();
    if (reason === 'hidden') r.show(false);
    if (reason === 'destroyed') r.page.aboutToDisappear();
    if (reason === 'logout') { r.state.epoch++; r.page.loggedIn = false; r.page.onLoginStateChange(); }
    r.replies.banners = () => [{ id: 4 }];
    if (reason === 'destroyed') { r.page.aboutToAppear(); await tick(); }
    old.release([{ id: 99 }]); await tick();
    assert.notEqual(r.page.banners[0]?.id, 99, reason);
    if (reason === 'hidden') r.show(true);
  }
});

test('homepage honors privacy and login and loads the browse catalog without coordinates', async () => {
  const r = createHome();
  r.registry.set('privacyConsent', false); r.page.aboutToAppear();
  await r.expectCalls('without consent', []);
  r.registry.set('privacyConsent', true); r.page.loggedIn = false; r.page.refreshHomeData(true);
  await r.expectCalls('guest', []);
  r.replies.stores = () => [{ id: 1, rating: 4.1, ratingCount: 1 }];
  r.move(location(NaN)); r.page.loggedIn = true; r.page.onLoginStateChange();
  await r.expectCalls('missing location', ports);
  assert.equal(r.page.storeRows.totalCount(), 0);
  for (const mode of [1, 2]) {
    r.page.catalogMode = mode; r.page.updateCatalog();
    assert.equal(r.page.storeRows.getData(0).id, 1);
  }
});

test('catalog tabs share one request and distinguish exact distance, rating and server order', async () => {
  const r = createHome();
  r.replies.stores = () => [
    { id: 8, distanceKm: 5.001, rating: 4.8, ratingCount: 4 },
    { id: 7, distanceKm: 5, rating: 4.8, ratingCount: 12, deliverable: false },
    { id: 6, distanceKm: 2, rating: 4.0, ratingCount: 1 },
    { id: 5, distanceKm: 3, rating: 5, ratingCount: 0 },
    { id: 4, rating: 3.9, ratingCount: 100 }
  ];
  r.page.aboutToAppear(); await r.expectCalls('one catalog', ports);
  const ids = () => Array.from({ length: r.page.storeRows.totalCount() }, (_, i) => r.page.storeRows.getData(i).id);
  assert.deepEqual(ids(), [6, 5, 7]);
  r.page.catalogMode = 1; r.page.updateCatalog();
  assert.deepEqual(ids(), [7, 8, 6]);
  r.page.catalogMode = 2; r.page.updateCatalog();
  assert.deepEqual(ids(), [8, 7, 6, 5, 4]);
  await r.expectCalls('tab switches are local', []);
});
