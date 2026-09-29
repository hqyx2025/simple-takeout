// Run: node scripts/check-delivery-form.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require('C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync('entry/src/main/ets/service/DeliveryFormSync.ets', 'utf8');
const values = new Map([['privacyConsent', true], ['isLoggedIn', true], ['user', { id: 7, role: 0 }]]);
const writes = [];
let gate;
const provider = {
  getPublishedRunningFormInfos: async () => [{ abilityName: 'DeliveryFormAbility', formId: '1' }],
  updateForm: async (id, data) => { writes.push(data); if (gate) { const wait = gate; gate = null; await wait; } }
};
const output = { exports: {} };
vm.runInNewContext(ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText, {
  exports: output.exports, require: name => name === '@kit.FormKit' ? {
    formProvider: provider, formBindingData: { createFormBindingData: data => JSON.parse(JSON.stringify(data)) }
  } : { UserRole: { CUSTOMER: 0 } },
  AppStorage: { get: key => values.get(key) }, Date, Promise
});
const api = output.exports;
const tick = () => new Promise(resolve => setImmediate(resolve));
(async () => {
  assert.equal(api.deliveryStatus({ status: 4, escrowStatus: 0 }), '已送达 · 待确认');
  assert.equal(api.deliveryStatus({ status: 4, escrowStatus: 1 }), '已完成');
  assert.equal(api.deliveryStatus({ status: 3, escrowStatus: 2 }), '已退款');
  assert.equal(api.deliveryStatus({ status: 6, escrowStatus: 0 }), '退款中');
  assert.equal(api.deliveryStatus({ status: 6, escrowStatus: 2 }), '已退款');
  let release;
  gate = new Promise(resolve => { release = resolve; });
  api.syncDeliveryForms([{ status: 3, address: 'secret', riderPhone: 'secret' }], 7, api.deliveryRevision());
  await tick();
  assert.deepEqual(Object.keys(writes[0]).sort(), ['statusText', 'syncedText']);
  const old = api.deliveryRevision();
  api.clearDeliveryForms();
  values.set('user', { id: 8, role: 0 });
  api.syncDeliveryForms([{ status: 3 }], 7, old);
  release(); await tick(); await tick();
  assert.equal(writes.at(-1).statusText, '打开应用同步订单');
  const count = writes.length;
  values.set('user', { id: 8, role: 1 });
  api.syncDeliveryForms([{ status: 3 }], 8, api.deliveryRevision());
  await tick(); assert.equal(writes.length, count);
  values.set('user', { id: 8, role: 0 });
  api.syncDeliveryForms([{ status: 6, escrowStatus: 0 }], 8, api.deliveryRevision());
  await tick(); assert.equal(writes.at(-1).statusText, '退款中');
  api.syncDeliveryForms([], 8, api.deliveryRevision());
  await tick(); assert.equal(writes.at(-1).statusText, '暂无进行中订单');
  assert.match(writes.at(-1).syncedText, /^同步于 /);
  console.log('delivery-form checks passed (status, privacy, logout race, account, role, empty snapshot)');
})().catch(error => { console.error(error); process.exitCode = 1; });
