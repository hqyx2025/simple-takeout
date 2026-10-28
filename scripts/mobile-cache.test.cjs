const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME || 'C:/Program Files/Huawei/DevEco Studio', 'tools/ohpm/node_modules/typescript'));
const source = name => fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/', name), 'utf8');
const newline = String.fromCharCode(10);
function productionFunction(text, name, async = true) {
  const start = text.indexOf('export ' + (async ? 'async ' : '') + 'function ' + name + '(');
  assert.ok(start >= 0, name);
  return text.slice(start, text.indexOf(newline + '}', start) + 2);
}
function run(code, context) {
  vm.runInNewContext(ts.transpileModule(code, { compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS } }).outputText, context);
}
function runtime(role = 1) {
  const names = ['syncMerchantOrdersFromServer', 'syncMerchantStoresRemote', 'syncStoresFromServer', 'syncGoodsFromServer', 'fetchOrderDetailRemote'];
  const functions = names.map(name => productionFunction(source('service/AppStorageManager.ets'), name)).join(newline);
  const prefix = 'let orderSyncVersion = 0, storesSyncVersion = 0, merchantStoresSyncVersion = 0; let goodsSyncVersions = {}, orderDetailSyncVersions = {};';
  const exports = {}, pending = [], writes = [], state = { epoch: 1, latitude: 20, longitude: 30 };
  const storage = new Map([['user', { id: 1, role }], ['isLoggedIn', true], ['orderList', [{ id: 9 }]], ['allStores', [{ id: 9 }]], ['allGoodsMap', { 10: [{ id: 9 }] }]]);
  const request = () => new Promise(resolve => pending.push(resolve));
  run(prefix + functions, { exports, AppStorage: { get: k => storage.get(k), setOrCreate: (k, v) => { storage.set(k, v); writes.push(k); } }, UserRole: { CUSTOMER: 0, MERCHANT: 1, ADMIN: 2 }, isLoggedIn: () => storage.get('isLoggedIn') === true, getAuthSessionEpoch: () => state.epoch, getCurrentLatitude: () => state.latitude, getCurrentLongitude: () => state.longitude, fetchMerchantOrdersApi: request, fetchMerchantStoresResultApi: request, fetchStoresResultApi: request, fetchStoreGoodsResultApi: request, fetchOrderDetailApi: request, logInfo() {} });
  return { exports, pending, writes, state, storage };
}
const cases = [['syncMerchantOrdersFromServer', 'orderList', 1], ['syncMerchantStoresRemote', 'allStores', 1], ['syncStoresFromServer', 'allStores', 0], ['syncGoodsFromServer', 'allGoodsMap', 1], ['fetchOrderDetailRemote', 'orderList', 1]];
for (const [name, key, role] of cases) {
  test(name + ': cache rejects replaced account, logout, epoch and old request', async () => {
    for (const change of ['owner', 'logout', 'epoch', 'newer']) {
      const r = runtime(role), old = r.exports[name](10);
      if (change === 'owner') r.storage.set('user', { id: 2, role });
      if (change === 'logout') r.storage.set('isLoggedIn', false);
      if (change === 'epoch') r.state.epoch++;
      if (change === 'newer') {
        const newer = r.exports[name](10); r.pending[1](name === 'fetchOrderDetailRemote' ? { id: 10, status: 3 } : [{ id: 22 }]); await newer;
      }
      const before = r.writes.length;
      r.pending[0](name === 'fetchOrderDetailRemote' ? { id: 10, status: 1 } : [{ id: 11 }]); await old;
      assert.equal(r.writes.length, before, change);
    }
  });
  test(name + ': failed sync retains cached data', async () => {
    const r = runtime(role), old = r.exports[name](10);
    r.pending[0](null); await old; assert.equal(r.writes.length, 0);
  });
}
test('full merchant store sync replaces removed stores and accepts a successful empty result', async () => {
  const r = runtime(); let running = r.exports.syncMerchantStoresRemote(); r.pending[0]([{ id: 22 }]); await running;
  assert.equal(r.storage.get('allStores').length, 1); assert.equal(r.storage.get('allStores')[0].id, 22);
  running = r.exports.syncMerchantStoresRemote(); r.pending[1]([]); await running; assert.equal(r.storage.get('allStores').length, 0);
});
test('location-dependent store cache rejects the previous address response', async () => {
  const r = runtime(0), running = r.exports.syncStoresFromServer(); r.state.latitude++; r.pending[0]([{ id: 11 }]); await running;
  assert.equal(r.writes.length, 0);
});
test('present empty capabilities deny all actions; only absent capabilities use legacy rules', () => {
  const exports = {}; run(productionFunction(source('service/OrderStatus.ets'), 'canOrderAction', false), { exports });
  assert.equal(exports.canOrderAction({}, 'REFUND', true), true);
  assert.equal(exports.canOrderAction({ capabilities: { allowedActions: [] } }, 'REFUND', true), false);
  assert.equal(exports.canOrderAction({ capabilities: { allowedActions: ['REFUND'] } }, 'REFUND', false), true);
  for (const capabilities of [null, {}, [], 'REFUND', 1, { allowedActions: null }, { allowedActions: 'REFUND' }, { allowedActions: {} }, { allowedActions: [1, 'REFUND'] }]) {
    assert.equal(exports.canOrderAction({ capabilities }, 'REFUND', true), false);
  }
});
test('user and merchant page APIs distinguish failure from empty success', async () => {
  for (const [file, name] of [['OrdersApi', 'fetchUserOrdersPageApi'], ['MerchantApi', 'fetchMerchantOrdersPageApi']]) {
    const exports = {}, state = { response: null, mapped: 0 };
    run(productionFunction(source('service/api/' + file + '.ets'), name), { exports, get: async () => state.response, toOrderPageData: resp => { state.mapped++; return resp.data; } });
    for (const response of [{ code: 500 }, { code: 200, data: null }, { code: 200, data: { list: 'bad' } }]) {
      state.response = response; assert.equal(await exports[name](), null);
    }
    assert.equal(state.mapped, 0); state.response = { code: 200, data: { list: [], total: 0 } };
    assert.equal((await exports[name]()).total, 0); assert.equal(state.mapped, 1);
  }
});
test('capability conversion preserves absence but normalizes malformed present values to a safe denied capability', () => {
  const exports = {}; run(productionFunction(source('model/server/Converters.ets'), 'normalizeOrderCapabilities', false), { exports });
  assert.equal(exports.normalizeOrderCapabilities(undefined), undefined);
  for (const value of [null, {}, [], 'PAY', 1, { allowedActions: 'PAY' }, { allowedActions: [null, 'PAY'] }]) {
    const result = exports.normalizeOrderCapabilities(value);
    assert.equal(result.allowedActions.length, 0); assert.equal(result.refundRemaining, 0); assert.equal(result.afterSalesDeadline, '');
  }
  const valid = { allowedActions: ['REFUND'], refundRemaining: 12.50, afterSalesDeadline: 'deadline', fulfillmentMode: 'RIDER' };
  assert.equal(exports.normalizeOrderCapabilities(valid).refundRemaining, 12.50);
  assert.notEqual(exports.normalizeOrderCapabilities(valid).allowedActions, valid.allowedActions);
  const malformedMetadata = exports.normalizeOrderCapabilities({ allowedActions: [], refundRemaining: '12', afterSalesDeadline: {}, fulfillmentMode: 'bad' });
  assert.equal(malformedMetadata.refundRemaining.toFixed(2), '0.00'); assert.equal(malformedMetadata.afterSalesDeadline, ''); assert.equal(malformedMetadata.fulfillmentMode, '');
});