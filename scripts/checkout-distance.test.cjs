const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME || 'C:/Program Files/Huawei/DevEco Studio', 'tools/ohpm/node_modules/typescript'));
const page = fs.readFileSync('entry/src/main/ets/pages/CheckoutPage.ets', 'utf8');
const method = page.slice(page.indexOf('  private async submitStoreOrder('), page.indexOf('  // 调后端创建订单并跳转'));
const code = ts.transpileModule('class Page {' + method + '}; exports.Page=Page;', {
  compilerOptions: { target: ts.ScriptTarget.ES2020 }
}).outputText;

for (const choice of ['confirm', 'cancel', 'account-change', 'dismiss']) {
  test('mobile distance confirmation: ' + choice, async () => {
    const exports = {}, calls = [], dialogs = [];
    let active = true;
    vm.runInNewContext(code, { exports, COLORS: {}, createOrderRemote: async (...args) => {
      calls.push(args);
      args[10].distanceConfirmationRequired = calls.length === 1;
      args[10].message = '距离过远，请确认是否在此位置下单';
      return calls.length === 1 ? null : { id: 51, status: 0 };
    } });
    const p = new exports.Page();
    p.isCheckoutCurrent = () => active;
    p.getUIContext = () => ({ getPromptAction: () => ({ showDialog: async value => {
      dialogs.push(value);
      if (choice === 'account-change') active = false;
      if (choice === 'dismiss') throw new Error('dialog cancelled');
      return { index: choice === 'cancel' ? 0 : 1 };
    } }) });
    const snapshot = { storeId: 1, items: [], addressId: 10, couponId: 0, remark: '少辣', checkoutGoodsIds: [], key: 'same-order' };
    const result = await p.submitStoreOrder(snapshot, 1, {});
    assert.equal(dialogs.length, 1);
    assert.equal(calls[0][11], false);
    assert.equal(calls.length, choice === 'confirm' ? 2 : 1);
    if (choice === 'confirm') {
      assert.equal(result.id, 51);
      assert.equal(calls[1][11], true);
      assert.deepEqual(calls[1].slice(0, 10), calls[0].slice(0, 10), 'confirmation preserves the address, items and idempotency key');
    } else assert.equal(result, null);
  });
}

const fixture = fs.readFileSync('scripts/web-browse.test.cjs', 'utf8');
const browser = new Function('require', fixture.slice(0, fixture.indexOf('const cardCount=')) + ';return browser;')(require);
for (const confirmResult of [false, true]) {
  test('web distance confirmation: ' + confirmResult, async () => {
    const payloads = [];
    const b = browser('0', { confirmResult, onRequest(route, init) {
      if (route !== '/api/orders' || init.method !== 'POST') return;
      const payload = JSON.parse(init.body); payloads.push(payload);
      return { ok: true, status: 200, json: async () => payload.distanceConfirmed
        ? { code: 200, data: { id: 51, status: 0 } }
        : { code: 428, message: '距离过远，请确认是否在此位置下单' } };
    } });
    await b.handleAction('checkout', 2);
    await b.handleAction('place-order', '', { dataset: { store: '2' }, isConnected: true });
    assert.equal(payloads.length, confirmResult ? 2 : 1);
    if (confirmResult) {
      assert.equal(payloads[1].distanceConfirmed, true);
      assert.equal(payloads[1].idempotencyKey, payloads[0].idempotencyKey);
      assert.equal(payloads[1].addressId, payloads[0].addressId);
    } else {
      assert.equal(b.checkoutDraft(2).submittedPayload, null);
      assert.equal(b.state.checkoutSubmitting, false);
    }
  });
}
