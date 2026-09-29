const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(path.join(process.env.DEVECO_HOME || 'C:/Program Files/Huawei/DevEco Studio',
  'tools/ohpm/node_modules/typescript'));
const read = file => fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/', file), 'utf8');
function run(source, context = {}) {
  const exports = {};
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: {
    target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS
  } }).outputText, { exports, ...context });
  return exports;
}
function method(source, name) {
  const start = source.indexOf(`  private ${name}(`);
  assert(start >= 0, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4);
}
const cart = read('pages/CartPage.ets');
const cardClass = cart.slice(cart.indexOf('class CartStoreCard'), cart.indexOf('/** 凑单提示：'));
const { Probe } = run(cardClass + '\nexport class Probe {' + [
  'recomputeTotals', 'rebuildCards', 'toggleStore', 'getStoreIds', 'getStoreItems',
  'getCurrentCartItems', 'getStoreTotal', 'rowKey'
].map(name => method(cart, name)).join('\n') + '}', { AppMotion: { duration: n => n }, Curve: { EaseOut: 0 } });
const page = new Probe();
const rows = [1, 2, 3, 4, 5, 6].map((n) => ({ storeId: n < 4 ? 10 : 20,
  goods: { id: n < 3 ? 1 : n, price: 10 }, specId: n, price: n, quantity: 2 }));
Object.assign(page, { cartItems: rows, expandedStoreIds: [],
  getUIContext: () => ({ animateTo: (_, update) => update() }) });
page.recomputeTotals();
assert.deepEqual(Array.from(page.storeCards, c => c.visibleItems.length), [2, 2]);
assert.equal(page.totalCount, 12);
assert.equal(page.totalPrice, 42);
page.toggleStore(10);
assert.deepEqual(Array.from(page.storeCards, c => c.visibleItems.length), [3, 2]);
assert.equal(page.getStoreTotal(10), 12);
assert.equal(page.totalPrice, 42, 'collapse must not change money');
page.toggleStore(20);
page.toggleStore(10);
assert.deepEqual(Array.from(page.storeCards, c => c.visibleItems.length), [2, 3]);
assert.notEqual(page.rowKey(rows[0]), page.rowKey(rows[1]), 'spec rows stay separate');
page.cartItems = rows.filter(row => row.storeId === 10);
page.recomputeTotals();
assert.equal(page.expandedStoreIds.length, 0, 'remove stale expansion state');
assert.equal(rows.length, 6, 'presentation must not mutate server rows');
// ArkUI ForEach retains the builder capture while its key stays unchanged.
assert(cart.includes('${card.storeId}-${card.expanded}'), 'expanded card must invalidate captured view model');

const nav = read('components/AdaptiveTabBar.ets');
let timers = new Map(), nextId = 0, subscriptions = 0;
let supported = true, recentHand = 1, recentFails = false, subscribeFails = false, registeredCallback;
const storage = new Map([['privacyConsent', true]]);
const motion = { OperatingHandStatus: { UNKNOWN_STATUS: 0, LEFT_HAND_OPERATED: 1, RIGHT_HAND_OPERATED: 2 },
  on: (event, callback) => {
    assert.equal(event, 'operatingHandChanged');
    if (subscribeFails) throw Error('unsupported');
    subscriptions++; registeredCallback = callback;
  },
  off: (event, callback) => {
    assert.equal(event, 'operatingHandChanged');
    assert.equal(callback, registeredCallback, 'unsubscribe the same callback');
    subscriptions--;
  },
  getRecentOperatingHandStatus: () => {
    if (recentFails) throw Error('no recent status');
    return recentHand;
  }
};
const { Nav } = run('export class Nav {' + nav.slice(nav.indexOf('  private beginSwipe'), nav.indexOf('  private icon')) + '}', {
  motion, AppStorage: { get: key => storage.get(key) },
  canIUse: capability => { assert.equal(capability, 'SystemCapability.MultimodalAwareness.Motion'); return supported; },
  clearTimeout: id => timers.delete(id), setTimeout: fn => { timers.set(++nextId, fn); return nextId; }
});
const bar = new Nav();
Object.assign(bar, { mode: 'auto', active: true, foreground: true, pressed: false, listening: false,
  side: 0, pendingSide: 0, settleTimer: -1 });
const flush = () => { const callbacks = Array.from(timers.values()); timers.clear(); callbacks.forEach(fn => fn()); };
bar.updateListening();
assert.equal(subscriptions, 1);
flush(); assert.equal(bar.side, -1, 'restore the recent operating hand');
bar.onHandChanged(1); bar.onHandChanged(2); flush();
assert.equal(bar.side, 1, 'last stable hand wins');
bar.pressed = true; bar.onHandChanged(1); flush();
assert.equal(bar.side, 1, 'navigation cannot move during a press');
bar.pressed = false; bar.scheduleMove(); flush(); assert.equal(bar.side, -1);
bar.onHandChanged(0); flush(); assert.equal(bar.side, -1, 'unknown status must not move navigation');
bar.onHandChanged(3); flush(); assert.equal(bar.side, -1, 'holding-hand-only values are not operating hands');
bar.mode = 'right'; bar.updateListening(); assert.equal(subscriptions, 0); assert.equal(bar.side, 1);
bar.mode = 'auto'; bar.active = false; bar.updateListening(); assert.equal(subscriptions, 0);
bar.active = true; storage.set('privacyConsent', false); bar.updateListening(); assert.equal(subscriptions, 0);
storage.set('privacyConsent', true); supported = false;
bar.updateListening(); assert.equal(subscriptions, 0); assert.equal(bar.available, false); assert.equal(bar.side, 0);
supported = true; subscribeFails = true;
bar.updateListening(); assert.equal(subscriptions, 0); assert.equal(bar.available, false);
subscribeFails = false; recentFails = true;
bar.updateListening(); assert.equal(subscriptions, 1); assert.equal(bar.available, true);
bar.onHandChanged(2); flush(); assert.equal(bar.side, 1, 'recent-status failure must keep live subscription');
bar.onHandChanged(1); bar.foreground = false; bar.updateListening(); flush();
assert.equal(subscriptions, 0); assert.equal(bar.side, 1, 'background must cancel pending movement');
bar.foreground = true; recentFails = false; recentHand = 1; bar.updateListening(); flush();
assert.equal(subscriptions, 1); assert.equal(bar.side, -1, 'foreground restores latest operating hand');
bar.pressed = true; bar.aboutToDisappear();
assert.equal(bar.pressed, false); assert.equal(subscriptions, 0); assert.equal(timers.size, 0);
bar.pendingSide = 1; bar.scheduleMove(); flush(); assert.equal(bar.side, -1, 'stale touch cannot move unsubscribed navigation');
console.log('PASS: independent card collapse, full totals/specs, operating-hand restore/debounce, press/lifecycle/privacy/unsupported guards');

const selectedPages = [];
Object.assign(bar, { selected: 1, active: true, foreground: true, onSelect: index => selectedPages.push(index) });
bar.beginSwipe(); bar.finishSwipe(80, 2);
assert.deepEqual(selectedPages, [2], 'right swipe opens the next page');
bar.selected = 2; bar.beginSwipe(); bar.finishSwipe(-80, 2);
assert.deepEqual(selectedPages, [2, 1], 'left swipe opens the previous page');
bar.finishSwipe(-80, 0); // Duplicate completion must not switch again.
bar.beginSwipe(); bar.finishSwipe(20, 0);
bar.beginSwipe(); bar.finishSwipe(40, 90);
bar.selected = 0; bar.beginSwipe(); bar.finishSwipe(-80, 0);
bar.selected = 3; bar.beginSwipe(); bar.finishSwipe(80, 0);
bar.selected = 1; bar.beginSwipe(); bar.active = false; bar.finishSwipe(-80, 0);
bar.active = true; bar.beginSwipe(); bar.stopListening(); bar.finishSwipe(-80, 0);
assert.deepEqual(selectedPages, [2, 1], 'jitter, vertical motion, edges and canceled/hidden drags must not switch');
bar.selected = 0; bar.beginSwipe(); bar.finishSwipe(400, 0);
assert.deepEqual(selectedPages, [2, 1, 1], 'one swipe advances one adjacent page');
console.log('PASS: navigation swipe direction, threshold, boundaries, one-page limit and lifecycle cancellation');

(async () => {
  const requests = [], sessions = [], toasts = [];
  storage.set('privacyConsent', false);
  let payload = { code: 200, message: 'ok', data: [] }, statusCode = 200, failure = false;
  class Request { constructor(url, method = 'GET', headers, content) { Object.assign(this, { url, method, headers, content }); } }
  const session = { fetch: async req => {
    requests.push(req);
    if (failure) throw Error('offline');
    return { statusCode, toJSON: () => payload };
  }, close: () => { session.closed = true; } };
  const http = run(read('service/HttpClient.ets').replace(/^import .*$/gm, ''), {
    rcp: { Request, createSession: config => { sessions.push(config); return session; } },
    API_CONFIG: { BASE_URL: 'https://example.test', TIMEOUT: 10000 },
    AppStorage: { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) },
    logInfo() {}, logWarn() {}, logError() {}, promptAction: { showToast: toast => toasts.push(toast) }
  });
  http.warmColdStartConnection(); assert.equal(requests.length, 0);
  storage.set('privacyConsent', true); http.setAuthToken('private-token');
  http.warmColdStartConnection(); http.warmColdStartConnection();
  assert.equal(requests.length, 1); assert.equal(requests[0].connectOnly, true);
  assert.equal(requests[0].headers, undefined, 'preconnect carries no credentials');
  assert.equal(requests[0].configuration.transfer.timeout.connectMs, 1500);
  await http.get('/api/cart'); await http.post('/api/cart', { specId: 2, quantity: 1 });
  assert.equal(sessions.length, 1, 'normal traffic must reuse preconnect session');
  assert.equal(requests[1].headers.Authorization, 'Bearer private-token');
  assert.equal(requests[2].content, '{"specId":2,"quantity":1}');
  statusCode = 401; payload = null;
  const expired = await http.get('/api/cart');
  assert.equal(expired.code, 401); assert.equal(storage.get('isLoggedIn'), false); assert.equal(http.getAuthToken(), '');
  statusCode = 200; payload = { code: 401, message: 'expired', data: null };
  http.setAuthToken('new-token'); await http.get('/api/cart'); assert.equal(http.getAuthToken(), '');
  failure = true;
  assert.equal((await http.get('/api/cart')).code, 500);
  const before = toasts.length; await http.get('/api/cart'); assert.equal(toasts.length, before);
  http.disposeHttpClient(); assert.equal(session.closed, true);
  console.log('PASS: real connectOnly, consent gating, shared session, JSON body, HTTP/business 401, offline errors/disposal');
})().catch(error => { console.error(error); process.exitCode = 1; });
