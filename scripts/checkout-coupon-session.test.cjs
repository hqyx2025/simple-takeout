const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require(path.join(process.env.DEVECO_HOME || 'C:/Program Files/Huawei/DevEco Studio', 'tools/ohpm/node_modules/typescript'));
const root = path.join(__dirname, '..');
const compile = source => ts.transpileModule(source, {
  compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS, experimentalDecorators: true }
}).outputText;
const rules = {};
vm.runInNewContext(compile(fs.readFileSync(path.join(root, 'entry/src/main/ets/service/CheckoutCouponRules.ets'), 'utf8')), { exports: rules });
const statusRules = {};
const constantsSource = fs.readFileSync(path.join(root, 'entry/src/main/ets/common/Constants.ets'), 'utf8');
vm.runInNewContext(compile(constantsSource.slice(constantsSource.indexOf('export function getOrderStatusText('), constantsSource.indexOf('// 订单状态颜色'))), { exports: statusRules });
const now = Date.parse('2026/10/26 12:00:00');
const base = { id: 1, amount: 10, minOrder: 10, storeId: 0, startTime: '2026-01-01 00:00:00', endTime: '2026-12-31 23:59:59', used: false };

test('coupon matrix: goods threshold, delivery-inclusive positive payment, store, status and expiry', () => {
  const matrix = [
    ['coupon covers goods while delivery remains payable', {}, 1, 10, 3, true],
    ['coupon equals total payment', {}, 1, 10, 0, false],
    ['coupon exceeds total payment', { amount: 14 }, 1, 10, 3, false],
    ['delivery does not count toward threshold', { minOrder: 11 }, 1, 10, 3, false],
    ['threshold is inclusive', { minOrder: 10 }, 1, 10, 3, true],
    ['specified store matches', { storeId: 1 }, 1, 10, 3, true],
    ['specified store differs', { storeId: 2 }, 1, 10, 3, false],
    ['used coupon is excluded', { used: true }, 1, 10, 3, false],
    ['expired coupon is excluded', { endTime: '2026-10-26 11:59:59' }, 1, 10, 3, false],
    ['expiry boundary follows server before comparison', { endTime: '2026-10-26 12:00:00' }, 1, 10, 3, true],
    ['missing expiry fails closed', { endTime: '' }, 1, 10, 3, false],
    ['invalid expiry fails closed', { endTime: 'invalid' }, 1, 10, 3, false],
    ['creation time is not a future-use policy', { startTime: '2099-01-01 00:00:00' }, 1, 10, 3, true],
    ['zero face amount is excluded', { amount: 0 }, 1, 10, 3, false],
    ['NaN face amount is excluded', { amount: NaN }, 1, 10, 3, false],
    ['decimal threshold avoids binary sum errors', { minOrder: 0.3, amount: 0.29 }, 1, 0.1 + 0.2, 0, true],
    ['one cent remains payable', { minOrder: 0, amount: 0.3 }, 1, 0.3, 0.01, true],
  ];
  for (const [label, changes, store, goods, fee, eligible] of matrix) {
    const reason = rules.checkoutCouponReason({ ...base, ...changes }, store, goods, fee, now);
    assert.equal(reason === '', eligible, `${label}: ${reason}`);
    if (!eligible) assert.ok(reason.length > 0, 'unavailable coupons explain recovery');
  }
  assert.match(rules.checkoutCouponReason(base, 1, 10, 3, now, 1), /刷新/);
  assert.equal(rules.checkoutCents(1.005), 101, 'HALF_UP at the cent boundary');
});

const storageSource = fs.readFileSync(path.join(root, 'entry/src/main/ets/service/AppStorageManager.ets'), 'utf8');
const createSource = storageSource.slice(storageSource.indexOf('export async function createOrderRemote('), storageSource.indexOf('async function updateStoredOrder('));
const couponSource = storageSource.slice(storageSource.indexOf('export async function syncCouponsRemote('), storageSource.indexOf('export async function claimCouponRemote('));
function runtime() {
  const result = {}, pending = [], writes = [];
  const storage = new Map([['user', { id: 1, orders: [] }], ['isLoggedIn', true], ['orderList', []], ['couponList', []]]);
  const state = { epoch: 1, saves: 0 };
  vm.runInNewContext(compile(createSource + '\n' + couponSource), {
    exports: result, getAuthSessionEpoch: () => state.epoch,
    createOrderApi: () => new Promise(resolve => pending.push(resolve)),
    fetchCouponsApi: () => new Promise(resolve => pending.push(resolve)),
    AppStorage: { get: key => storage.get(key), setOrCreate: (key, value) => { writes.push(key); storage.set(key, value); } },
    setStoredUser: user => { writes.push('user'); storage.set('user', user); },
    saveAllData: () => { state.saves++; }, logInfo: () => {}, logWarn: () => {}
  });
  return { result, pending, storage, state, writes };
}

test('order/coupon responses from an old account, login or token cannot write shared state', async () => {
  for (const action of ['order', 'coupon']) {
    for (const changed of ['account', 'logout', 'session']) {
      const r = runtime();
      const response = action === 'order' ? { id: 8 } : [{ ...base }];
      const pending = action === 'order'
        ? r.result.createOrderRemote(1, [], 1, 0, '', [], '', 'stable-key') : r.result.syncCouponsRemote(false);
      if (changed === 'account') r.storage.set('user', { id: 2, orders: [] });
      if (changed === 'logout') r.storage.set('isLoggedIn', false);
      if (changed === 'session') r.state.epoch++;
      r.pending.shift()(response);
      assert.equal(await pending, action === 'order' ? null : false, `${action}/${changed}`);
      assert.equal(r.writes.length, 0, `${action}/${changed} must not write`);
      assert.equal(r.state.saves, 0);
    }
  }
});

test('current-session order and coupon responses remain authoritative', async () => {
  const r = runtime();
  const order = { id: 8 };
  let pending = r.result.createOrderRemote(1, [], 1, 0, '', [], '', 'stable-key');
  r.pending.shift()(order);
  assert.equal(await pending, order);
  assert.equal(r.storage.get('orderList')[0], order);
  assert.equal(r.state.saves, 1);
  pending = r.result.createOrderRemote(1, [], 1, 0, '', [], '', 'stable-key');
  const replayed = { id: 8, status: 1 };
  r.pending.shift()(replayed);
  assert.equal(await pending, replayed);
  assert.equal(r.storage.get('orderList').length, 1, 'replayed order replaces its cached row');
  assert.equal(r.storage.get('orderList')[0], replayed);
  const coupons = [{ ...base }];
  pending = r.result.syncCouponsRemote(false);
  r.pending.shift()(coupons);
  assert.equal(await pending, true);
  assert.equal(r.storage.get('couponList'), coupons);
});

test('create-order feedback distinguishes confirmed rejection, pending server work and invalid success bodies', async () => {
  const source = fs.readFileSync(path.join(root, 'entry/src/main/ets/service/api/OrdersApi.ets'), 'utf8');
  const functionSource = source.slice(source.indexOf('export async function createOrderApi('), source.indexOf('export async function fetchUserOrdersApi('));
  const result = {};
  let response;
  vm.runInNewContext(compile(functionSource), {
    exports: result, post: async () => response, toOrder: order => order,
    API_CONFIG: { ENDPOINTS: { orders: '/api/orders' } }, logWarn: () => {}
  });
  const cases = [
    [400, '库存不足', null, true], [403, '没有权限', null, true],
    [500, '网络请求失败', null, false], [502, '响应异常', null, false], [429, '请求过多', null, false],
    [400, '订单正在提交中，请稍后重试', null, false],
    [400, '订单可能已提交，请在订单列表核对，不要重复下单', null, false],
    [200, '', null, false], [200, '', {}, false], [200, '', { id: 0 }, false],
    [200, '', { id: 5, storeId: 2, status: 0, payAmount: 13, items: [{}] }, false],
  ];
  for (const [code, message, data, confirmed] of cases) {
    response = { code, message, data };
    const feedback = { failureConfirmed: false, message: '' };
    const order = await result.createOrderApi(1, [], 10, 0, '', [], '', 'stable-key', 'DELIVERY', [], feedback);
    assert.equal(order, null, `${code}/${message}: malformed or rejected response cannot become an order`);
    assert.equal(feedback.failureConfirmed, confirmed, `${code}/${message}`);
  }
  const order = { id: 5, storeId: 1, status: 0, payAmount: 13, items: [{}] };
  response = { code: 200, message: '', data: order };
  assert.equal(await result.createOrderApi(1, [], 10, 0, '', [], '', 'stable-key'), order);
});

// Run the real page's non-rendering methods; requests can complete after navigation or logout.
const pageSource = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/CheckoutPage.ets'), 'utf8');
const pageLogic = pageSource.slice(0, pageSource.indexOf('\n  build() {')).replace('export struct CheckoutPage', 'export class CheckoutPage') + '\n}';
function checkoutPage() {
  const result = {}, requests = [], toasts = [], navigations = [];
  const storage = new Map([['user', { id: 1 }], ['isLoggedIn', true], ['currentAddress', { id: 10 }]]);
  const stores = [{ id: 1, name: 'A', deliveryFee: 3 }, { id: 2, name: 'B', deliveryFee: 3 }];
  const state = { epoch: 1 };
  const services = {
    getAllStoresList: () => stores,
    createOrderRemote: (...args) => new Promise(resolve => requests.push({ args, resolve })),
    syncCartRemote: async () => true, syncCouponsRemote: async () => true,
    getLastRemoteErrorMessage: () => '该商品已下架'
  };
  const navigation = { promptCompat: { showToast: value => toasts.push(value) },
    routerCompat: { pushUrl: value => navigations.push(value), replaceUrl: value => navigations.push(value), back: () => navigations.push('back') } };
  vm.runInNewContext(compile(pageLogic), {
    exports: result,
    Entry: value => value, Component: value => value, State: () => {},
    StorageLink: () => () => {}, Watch: () => () => {},
    AppStorage: { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) },
    require: name => name.endsWith('CheckoutCouponRules') ? rules
      : name.endsWith('HttpClient') ? { getAuthSessionEpoch: () => state.epoch, getServerNowEpochMs: () => now }
      : name.endsWith('AppStorageManager') ? services
      : name.endsWith('UiNavigation') ? navigation
      : name.endsWith('AppLogger') ? { logInfo: () => {} }
      : name.endsWith('Models') ? { createEmptyUser: () => ({ id: 0 }) }
      : name.endsWith('Constants') ? statusRules
      : name.endsWith('OrderCalculations') ? { calculatePayAmount: (goods, fee, discount) => goods + fee - discount }
      : {},
  });
  const page = new result.CheckoutPage();
  Object.assign(page, {
    loggedIn: true, sessionUser: { id: 1 }, pageActive: true, pageOwnerId: 1, pageSessionEpoch: 1,
    couponOptionsReady: true, currentAddress: { id: 10 }, remark: '少辣，不要香菜', checkoutStoreIds: [1, 2],
    storeItems: [1, 2].map(id => ({ goods: { id, name: '餐品' + id, price: 10 }, storeId: id, storeName: '店' + id, quantity: 1, price: 10 })),
  });
  return { page, requests, state, storage, toasts, navigations };
}
const tick = () => new Promise(resolve => setImmediate(resolve));

test('address return preserves remark and explicit no-coupon choice', () => {
  const r = checkoutPage();
  r.page.couponList = [base];
  r.page.selectCoupon(null);
  r.page.onPageHide();
  r.storage.set('currentAddress', { id: 11 });
  r.page.onPageShow();
  assert.equal(r.page.currentAddress.id, 11);
  assert.equal(r.page.remark, '少辣，不要香菜');
  assert.equal(r.page.couponChoiceMode, 'NONE');
  assert.equal(r.page.selectedCoupon, null);
});

test('submission freezes address, remark and coupon while partial retry keeps the same store key', async () => {
  const r = checkoutPage();
  r.page.submitOrder();
  assert.equal(r.page.submitting, true);
  r.page.selectCoupon(null);
  r.page.openAddressSelector();
  assert.equal(r.navigations.length, 0);
  assert.equal(r.page.onBackPress(), true);
  const first = r.requests.shift();
  first.resolve({ id: 101, status: 0, payAmount: 13 }); await tick();
  const second = r.requests.shift();
  assert.equal(second.args[2], 10);
  assert.equal(second.args[4], '少辣，不要香菜');
  const key = second.args[7];
  second.args[10].failureConfirmed = true;
  second.resolve(null); await tick();
  assert.equal(r.page.createdOrderCount, 1);
  assert.equal(r.page.checkoutStoreIds.join(','), '2');
  assert.equal(r.page.remark, '少辣，不要香菜');
  r.page.submitOrder();
  const retry = r.requests.shift();
  assert.equal(retry.args[0], 2, 'only the failed store is retried');
  assert.equal(retry.args[7], key, 'response-loss retries use the original idempotency key');
  retry.resolve({ id: 102, status: 0, payAmount: 13 }); await tick();
  assert.equal(r.page.createdOrderCount, 2);
  assert.equal(r.navigations.at(-1).url, 'pages/OrderListPage');
});

test('unknown order result replays the frozen payload despite used coupons, changed address and an empty cart', async () => {
  const r = checkoutPage();
  r.page.checkoutStoreIds = [1]; r.page.storeItems = r.page.storeItems.slice(0, 1);
  r.page.couponList = [{ ...base }]; r.page.refreshCouponOptions();
  r.page.submitOrder();
  const first = r.requests.shift();
  const original = JSON.stringify(first.args.slice(0, 10));
  first.resolve(null); await tick();
  assert.equal(r.page.submissionUncertain, true);
  r.page.couponList = [{ ...base, used: true }]; r.page.onCouponListChanged();
  r.storage.set('cartItems', []); r.storage.set('currentAddress', { id: 11 });
  r.page.onPageHide(); r.page.onPageShow();
  assert.equal(r.page.currentAddress.id, 10, 'a pending request retains its original address');
  r.page.selectCoupon(null);
  assert.equal(r.page.selectedCoupon.id, 1, 'a pending request retains its original coupon');
  // Even a programmatic model change cannot alter the request used for reconciliation.
  r.page.currentAddress = { id: 99 }; r.page.remark = 'changed'; r.page.selectedCoupon = null;
  r.page.storeItems[0].quantity = 9;
  r.page.storeItems[0].goods.id = 99; r.page.storeItems[0].goods.name = 'changed goods';
  r.page.submitOrder();
  const replay = r.requests.shift();
  assert.equal(JSON.stringify(replay.args.slice(0, 10)), original);
  replay.resolve({ id: 101, status: 0, payAmount: 3 }); await tick();
  assert.equal(r.page.submissionUncertain, false);
  assert.equal(r.page.pendingSubmission, null);
  assert.equal(r.page.createdOrderCount, 1);
  assert.equal(r.navigations.at(-1).url, 'pages/OrderDetailPage');
});

test('hidden page and changed account discard late submission responses and stop the next store', async () => {
  for (const change of ['hide', 'account']) {
    const r = checkoutPage();
    r.page.submitOrder();
    const first = r.requests.shift();
    if (change === 'hide') r.page.onPageHide();
    else { r.page.sessionUser = { id: 2 }; r.page.onAccountChanged(); }
    first.resolve({ id: 101, status: 0, payAmount: 13 }); await tick();
    assert.equal(r.requests.length, 0, 'do not submit the next store after ' + change);
    assert.equal(r.navigations.length, 0, 'do not navigate from an obsolete page');
    assert.equal(r.page.createdOrderCount, 0);
    if (change === 'account') assert.equal(r.page.remark, '', 'do not retain the old account input');
  }
});

test('replaying a paid cancelled or refunded order reports its actual state without a payment deadline', async () => {
  for (const [status, escrowStatus, label] of [[1, 0, '待接单'], [4, 1, '已完成'], [5, 0, '已取消'], [6, 2, '已退款']]) {
    const r = checkoutPage();
    r.page.checkoutStoreIds = [1]; r.page.storeItems = r.page.storeItems.slice(0, 1);
    r.page.submitOrder(); r.requests.shift().resolve(null); await tick();
    r.page.submitOrder();
    r.requests.shift().resolve({ id: 101, status, escrowStatus, payAmount: 13 }); await tick();
    const message = r.toasts.at(-1).message;
    assert.match(message, new RegExp(`已核对到原订单，当前状态：${label}`));
    assert.doesNotMatch(message, /15 分钟|完成支付|待付款|分别.*支付/);
    assert.equal(r.navigations.at(-1).url, 'pages/OrderDetailPage');
  }
});
