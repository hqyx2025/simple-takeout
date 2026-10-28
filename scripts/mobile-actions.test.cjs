const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME || 'C:/Program Files/Huawei/DevEco Studio', 'tools/ohpm/node_modules/typescript'));
const source = file => fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/', file), 'utf8');
const nl = String.fromCharCode(10);
function method(text, name) {
  const start = text.search(new RegExp('^  (?:private )?(?:async )?' + name + '[(]', 'm'));
  assert.ok(start >= 0, name);
  const lineEnd = text.indexOf(nl, start);
  return text.slice(start, text.slice(start, lineEnd).trim().endsWith('}') ? lineEnd : text.indexOf(nl + '  }', start) + 4);
}
function runtime(role, file, methods) {
  const exports = {}, calls = [], dialogs = [], buttons = [], user = { id: 1, role };
  const status = source('service/OrderStatus.ets'), start = status.indexOf('export function canOrderAction(');
  const helper = status.slice(start, status.indexOf(nl + '}', start) + 2);
  const code = helper + nl + 'export class Page {' + methods.map(name => method(source('pages/' + file + '.ets'), name)).join(nl) + '}';
  const button = label => { const current = { label, click: null }; buttons.push(current); const chain = new Proxy({}, { get: (_, key) => (...args) => { if (key === 'onClick') current.click = args[0]; return chain; } }); return chain; };
  const context = { exports, getAuthSessionEpoch: () => 1, AppStorage: { get: key => key === 'user' ? user : true }, getCurrentUser: () => user,
    UserRole: { CUSTOMER: 0, MERCHANT: 1, ADMIN: 2, RIDER: 3 }, promptAction: { showToast() {} }, logInfo() {},
    adminOrderActionApi: async (...args) => { calls.push(args); return false; }, merchantActionRemote: async (...args) => { calls.push(args); return false; }, rejectMerchantOrderApi: async (...args) => { calls.push(args); return false; },
    CustomDialogController: function (options) { dialogs.push(options.builder); return { open() {}, close() {} }; }, MerchantRejectOrderDialog: props => props,
    DialogAlignment: { Center: 0 }, AppButtonStyle: class {}, FONT_SIZE: {}, COLORS: {}, Button: button, Text: () => ({ fontSize() { return this; }, fontColor() { return this; } }) };
  const compiled = ts.transpileModule(code, { reportDiagnostics: true, compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS } });
  assert.equal(compiled.diagnostics.length, 0); vm.runInNewContext(compiled.outputText, context);
  const page = new exports.Page(); Object.assign(page, { pageActive: true, loggedIn: true, user, ordersOwner: user, ordersRequestVersion: 1, actioningOrderId: 0, allOrders: [], orders: [], loading: false });
  return { page, calls, dialogs, buttons, user };
}
const denied = [null, {}, { allowedActions: [] }, { allowedActions: 'MERCHANT_REJECT' }, { allowedActions: [null, 'MERCHANT_REJECT'] }];
const adminMethods = ['canApplyOrders', 'canRunOrderAction', 'runOrderAction', 'AdminOrderActions'];
test('admin rendering and dispatch deny every action for present empty/malformed capabilities', async () => {
  for (const capabilities of denied) for (const status of [0, 1, 2, 3]) {
    const r = runtime(2, 'AdminOrderPage', adminMethods), order = { id: 10, status, capabilities };
    r.page.orders = [order]; r.page.AdminOrderActions(order); assert.equal(r.buttons.length, 0);
    for (const action of ['accept', 'ready', 'deliver', 'complete', 'cancel', 'refund']) await r.page.runOrderAction(10, action, 'ok');
    assert.equal(r.calls.length, 0);
  }
});
test('admin RIDER order permits explicit CANCEL but never merchant complete; stale visible buttons recheck latest order', async () => {
  const r = runtime(2, 'AdminOrderPage', adminMethods), order = { id: 10, status: 3, capabilities: { allowedActions: ['CANCEL'], fulfillmentMode: 'RIDER' } };
  r.page.orders = [order]; r.page.AdminOrderActions(order);
  assert.deepEqual(r.buttons.map(item => item.label), ['取消并退款']);
  await r.page.runOrderAction(10, 'complete', 'ok'); assert.equal(r.calls.length, 0);
  r.page.orders = [{ ...order, capabilities: { allowedActions: [] } }]; r.buttons[0].click(); assert.equal(r.calls.length, 0);
  r.page.orders = [order]; await r.page.runOrderAction(10, 'cancel', 'ok'); assert.equal(r.calls.length, 1); assert.equal(r.calls[0][1], 'cancel');
});
test('admin actions follow exact server action names and only missing capabilities use legacy fallback', async () => {
  const mappings = [['accept', 'MERCHANT_ACCEPT', 1], ['ready', 'MERCHANT_READY', 2], ['deliver', 'MERCHANT_DELIVER', 2], ['complete', 'MERCHANT_COMPLETE', 3], ['cancel', 'CANCEL', 1]];
  for (const [action, capability, status] of mappings) {
    const r = runtime(2, 'AdminOrderPage', adminMethods), order = { id: 10, status, capabilities: { allowedActions: [capability] } };
    r.page.orders = [order]; assert.equal(r.page.canRunOrderAction(order, action), true); await r.page.runOrderAction(10, action, 'ok'); assert.equal(r.calls.length, 1);
    assert.equal(r.page.canRunOrderAction({ id: 10, status }, action), action !== 'deliver');
  }
});
const merchantMethods = ['canApplyOrders', 'canMerchantAction', 'activeMerchantOrder', 'openRejectDialog', 'submitMerchantRejection', 'handleAccept', 'handleReady', 'handleDeliver', 'handleComplete'];
test('merchant reject rendering decision, dialog open and submit all deny empty/malformed capabilities', async () => {
  for (const capabilities of denied) {
    const r = runtime(1, 'MerchantOrdersPage', merchantMethods), order = { id: 10, status: 1, capabilities };
    r.page.allOrders = [order]; assert.equal(r.page.canMerchantAction(order, 'MERCHANT_REJECT'), false);
    r.page.openRejectDialog(order); assert.equal(r.dialogs.length, 0);
    assert.equal(await r.page.submitMerchantRejection(10, { reasonCode: 'OTHER' }), false); assert.equal(r.calls.length, 0);
  }
});
test('merchant opened reject dialog rechecks capability before network submit and does not substitute ACCEPT permission', async () => {
  const r = runtime(1, 'MerchantOrdersPage', merchantMethods), order = { id: 10, status: 1, items: [], storeName: 'store', capabilities: { allowedActions: ['MERCHANT_REJECT'] } };
  r.page.allOrders = [order]; r.page.openRejectDialog(order); assert.equal(r.dialogs.length, 1);
  r.page.allOrders = [{ ...order, capabilities: { allowedActions: ['MERCHANT_ACCEPT'] } }];
  assert.equal(await r.dialogs[0].onSubmit({ reasonCode: 'OTHER' }), false); assert.equal(r.calls.length, 0);
  r.page.allOrders = [order]; assert.equal(await r.dialogs[0].onSubmit({ reasonCode: 'OTHER' }), false); assert.equal(r.calls.length, 1);
});
test('merchant sibling handlers recheck the latest order capability, while legacy reject remains compatible', async () => {
  for (const [method, status] of [['handleAccept', 1], ['handleReady', 2], ['handleDeliver', 2], ['handleComplete', 3]]) {
    const r = runtime(1, 'MerchantOrdersPage', merchantMethods), stale = { id: 10, status };
    r.page.allOrders = [{ ...stale, capabilities: { allowedActions: [] } }]; await r.page[method](stale); assert.equal(r.calls.length, 0);
  }
  const r = runtime(1, 'MerchantOrdersPage', merchantMethods); assert.equal(r.page.canMerchantAction({ status: 1 }, 'MERCHANT_REJECT'), true);
  assert.equal(r.page.canMerchantAction({ status: 2 }, 'MERCHANT_REJECT'), false);
});
test('customer list dispatch rechecks current capability for pay, cancel and confirmation', async () => {
  const names = ['activeCustomerOrder', 'payPendingOrder', 'cancelPendingOrder', 'confirmSelectedOrder'];
  for (const capabilities of denied) {
    const r = runtime(0, 'OrderListPage', names), stale = { id: 10, status: 0 };
    r.page.pageOrders = [{ ...stale, capabilities }]; r.page.confirmingOrderId = 10;
    r.page.payPendingOrder(stale); await r.page.cancelPendingOrder(stale); await r.page.confirmSelectedOrder();
    assert.equal(r.calls.length, 0);
  }
});
test('customer detail payment preparation and refund dispatch deny empty capabilities', async () => {
  const r = runtime(0, 'OrderDetailPage', ['canDispatchOrder', 'payNow', 'preparePayment', 'submitRefund']);
  Object.assign(r.page, { detailOwner: 1, detailRole: 0, sessionUser: r.user, order: { id: 10, status: 0, capabilities: { allowedActions: [] } }, refundAppealId: 0, refundSubmitting: false, refundUploading: false });
  await r.page.payNow(); assert.equal(await r.page.preparePayment('QR'), null);
  r.page.order.status = 4; await r.page.submitRefund(); assert.equal(r.calls.length, 0);
});
test('rider pickup, delivery and pool grab dispatch reject stale visible orders after capability removal', async () => {
  const r = runtime(3, 'RiderOrdersPage', ['pickup', 'deliver']), stale = { id: 10, status: 2 };
  const current = { ...stale, capabilities: { allowedActions: [] } };
  r.page.activeOrder = () => current; r.page.acting = false;
  await r.page.pickup(stale); current.status = 3; await r.page.deliver(stale); assert.equal(r.calls.length, 0);
  const pool = runtime(3, 'RiderOrderPoolPage', ['grab']); pool.page.orders = [current]; pool.page.grabbingOrderId = 0;
  await pool.page.grab(stale); assert.equal(pool.calls.length, 0);
});
