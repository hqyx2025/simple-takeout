const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('C:/Program Files/Huawei/DevEco Studio/tools/ohpm/node_modules/typescript');

// Run the real recharge and balance-write functions with controlled API completion.
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/service/AppStorageManager.ets'), 'utf8');
const setUser = source.slice(source.indexOf('function setStoredUser('), source.indexOf('// 初始化全局数据'));
const recharge = source.slice(source.indexOf('export async function rechargeBalanceRemote('),
  source.indexOf('export async function syncCurrentUserFromServer('));
const compiled = ts.transpileModule('let currentUserSyncVersion = 0;\n' + setUser + recharge, {
  compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
}).outputText;
const result = {}, responses = [], writes = [];
const storage = new Map([['user', { id: 1, role: 0, balance: 10 }], ['userBalance', 10]]);
let token = 'account-a', saves = 0;
vm.runInNewContext(compiled, {
  exports: result, getAuthToken: () => token, clearDeliveryForms: () => {},
  AppStorage: { get: key => storage.get(key), setOrCreate: (key, value) => { storage.set(key, value); writes.push(key); } },
  rechargeBalanceApi: () => new Promise(resolve => responses.push(resolve)),
  saveAllData: async () => { saves++; }
});

(async () => {
  let pending = result.rechargeBalanceRemote(5);
  const updated = { id: 1, role: 0, balance: 15 };
  responses.shift()(updated);
  assert.equal(await pending, updated);
  assert.equal(storage.get('userBalance'), 15, 'normal response writes the server balance');
  assert.equal(saves, 1, 'normal response persists once');
  const writeCount = writes.length;
  for (const change of ['account', 'token', 'user']) {
    token = 'account-a'; storage.set('user', updated);
    pending = result.rechargeBalanceRemote(5);
    if (change !== 'user') token = 'account-b';
    if (change !== 'token') storage.set('user', { id: 2, role: 0, balance: 90 });
    const current = storage.get('user');
    responses.shift()({ id: 1, role: 0, balance: 20 });
    assert.equal(await pending, undefined, 'late response is discarded after ' + change + ' changes');
    assert.equal(storage.get('user'), current, 'late response preserves the current account');
    assert.equal(storage.get('userBalance'), 15, 'late response cannot write any balance');
    assert.equal(writes.length, writeCount); assert.equal(saves, 1);
  }
  console.log('PASS: recharge persists server balance and ignores late responses after token/user/account changes');
})().catch(error => { console.error(error); process.exitCode = 1; });
