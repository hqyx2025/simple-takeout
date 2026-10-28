const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME || 'C:/Program Files/Huawei/DevEco Studio', 'tools/ohpm/node_modules/typescript'));

// Execute the production functions with controllable network completion.
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/service/AppStorageManager.ets'), 'utf8');
const names = ['updateUserProfileRemote', 'syncCurrentUserFromServer', 'syncFavoritesRemote', 'syncAddressesRemote', 'updateStoredOrder'];
const functions = names.map(name => {
  const start = source.indexOf(`${name === 'updateStoredOrder' ? '' : 'export '}async function ${name}(`);
  assert.ok(start >= 0, name);
  return source.slice(start, source.indexOf('\n}', start) + 2).replace(/^async function/, 'export async function');
}).join('\n');
const code = ts.transpileModule('let currentUserSyncVersion = 0, addressSyncVersion = 0, favoriteSyncVersion = 0;\n' + functions, {
  compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
}).outputText;
function runtime() {
  const result = {}, pending = [], writes = [];
  const state = { epoch: 1, token: 'first-access-token', saves: 0 };
  const storage = new Map([['user', { id: 1, role: 0 }], ['isLoggedIn', true], ['favoriteList', []], ['addressList', []], ['orderList', []]]);
  const request = () => new Promise(resolve => pending.push(resolve));
  vm.runInNewContext(code, {
    exports: result, AppStorage: { get: key => storage.get(key), setOrCreate: (key, value) => { storage.set(key, value); writes.push(key); } },
    getAuthSessionEpoch: () => state.epoch, getAuthToken: () => state.token, isLoggedIn: () => storage.get('isLoggedIn') === true,
    updateUserProfileApi: request, fetchCurrentUserApi: request, fetchFavoritesApi: request, fetchAddressesApi: request, fetchOrderDetailApi: request,
    setStoredUser: user => { storage.set('user', user); writes.push('user'); }, saveAllData: async () => { state.saves++; },
    deduplicateAddresses: addresses => addresses, deliveryCustomerId: () => storage.get('user').id, deliveryRevision: () => state.epoch,
    syncDeliveryForms: () => {}, logInfo: () => {}, logWarn: () => {}
  });
  return { result, state, storage, pending, writes };
}
const response = name => name.includes('Favorites') ? [{ storeId: 99 }] : name.includes('Addresses')
  ? [{ id: 10, name: '收货人', isDefault: true }] : name === 'updateStoredOrder' ? { id: 20, status: 1 } : { id: 1, role: 0, username: '已更新' };
const invoke = (r, name) => name === 'updateUserProfileRemote' ? r.result[name]('姓名', '13800138000', 'a@example.com') : r.result[name](20);

test('account, logout and session changes discard late identity, favorites, address and order responses', async () => {
  for (const name of names) for (const change of ['account', 'logout', 'session']) {
    const r = runtime(), running = invoke(r, name), before = r.writes.length;
    if (change === 'account') r.storage.set('user', { id: 2, role: 0 });
    if (change === 'logout') r.storage.set('isLoggedIn', false);
    if (change === 'session') r.state.epoch++;
    r.pending.shift()(response(name));
    await running;
    assert.equal(r.writes.length, before, `${name}/${change} must not write`);
    assert.equal(r.state.saves, 0, `${name}/${change} must not persist`);
  }
});

test('access-token rotation within one session preserves successful responses', async () => {
  for (const name of names) {
    const r = runtime(), running = invoke(r, name);
    r.state.token = 'refreshed-access-token';
    r.pending.shift()(response(name));
    await running;
    assert.ok(r.writes.length > 0, name);
    if (name.includes('Addresses')) {
      assert.equal(r.storage.get('addressSyncState'), 'ready');
      assert.equal(r.storage.get('currentAddress').id, 10);
    }
    if (name.includes('Favorites')) assert.equal(r.storage.get('favoriteList')[0].userId, 1);
    if (name === 'updateStoredOrder') assert.equal(r.storage.get('orderList')[0].id, 20);
  }
});

test('a newer favorites response wins when network responses arrive backwards', async () => {
  const r = runtime(), first = r.result.syncFavoritesRemote(), second = r.result.syncFavoritesRemote();
  r.pending[1]([{ storeId: 22 }]); await second;
  r.pending[0]([{ storeId: 11 }]); await first;
  assert.equal(r.storage.get('favoriteList')[0].storeId, 22);
});

test('profile save invalidates an older current-user response', async () => {
  const r = runtime(), old = r.result.syncCurrentUserFromServer(), save = invoke(r, 'updateUserProfileRemote');
  r.pending[1]({ id: 1, role: 0, username: '新资料' }); await save;
  r.pending[0]({ id: 1, role: 0, username: '旧资料' }); await old;
  assert.equal(r.storage.get('user').username, '新资料');
});
