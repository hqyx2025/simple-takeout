const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME || 'C:/Program Files/Huawei/DevEco Studio', 'tools/ohpm/node_modules/typescript'));
const source = name => fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/', name), 'utf8');
function method(text, name) {
  const start = text.search(new RegExp('^  (?:private )?(?:async )?' + name + '[(]', 'm'));
  assert.ok(start >= 0, name);
  return text.slice(start, text.indexOf('\n  }', start) + 4);
}
function load(code, context = {}) {
  const exports = {};
  vm.runInNewContext(ts.transpileModule(code, { compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS } }).outputText, { exports, ...context });
  return exports;
}
const constants = source('common/Constants.ets');
const { getOrderStatusText } = load(constants.slice(constants.indexOf('export function getOrderStatusText('), constants.indexOf('// 订单状态颜色')));

test('merchant progress distinguishes preparation, dispatch modes and assigned riders without hiding refund state', () => {
  const { Page } = load('export class Page {' + method(source('pages/MerchantOrdersPage.ets'), 'orderStatusText') + '}', { getOrderStatusText });
  const page = new Page();
  const order = { status: 2, escrowStatus: 0 };
  assert.equal(page.orderStatusText(order), '制作中');
  assert.equal(page.orderStatusText({ ...order, readyTime: '2026-11-03 12:00:00' }), '待骑手接单');
  assert.equal(page.orderStatusText({ ...order, readyTime: 'now', capabilities: { fulfillmentMode: 'MERCHANT' } }), '待商家配送');
  assert.equal(page.orderStatusText({ ...order, readyTime: 'now', riderName: '测试骑手' }), '待骑手取餐');
  assert.equal(page.orderStatusText({ ...order, readyTime: 'now', escrowStatus: 2 }), '已退款');
  assert.equal(page.orderStatusText({ status: 4, escrowStatus: 1 }), '已完成');
});

function refunds(response) {
  const toasts = [];
  const { Page } = load('export class Page {' + method(source('pages/AdminRefundPage.ets'), 'doRejectRefund') + '}', {
    UserRole: { ADMIN: 2 }, getAuthSessionEpoch: () => 1, getOrderStatusText,
    rejectRefundApi: async () => response, fetchAdminRefundDetailApi: async () => null,
    promptAction: { showToast: x => toasts.push(x.message) }
  });
  const page = Object.assign(new Page(), { pageActive: true, loggedIn: true, user: { role: 2 }, submitting: false,
    rejectingRefundId: 8, rejectReason: '已核对配送记录', canApplyResponse: () => true, refresh: async () => {} });
  return { page, toasts };
}
test('refund rejection feedback uses returned escrow snapshot and handles unknown results', async () => {
  for (const [response, expected] of [
    [{ status: 'REJECTED', originalEscrow: 0 }, '已送达，待确认收货'],
    [{ status: 'REJECTED', originalEscrow: 1 }, '已完成'],
    [{ status: 'REJECTED', settledBefore: 1 }, '已完成'],
    [{ status: 'REJECTED' }, '请刷新查看订单状态']
  ]) {
    const r = refunds(response); await r.page.doRejectRefund();
    assert.ok(r.toasts[0].includes(expected)); assert.equal(r.page.rejectReason, '');
  }
  const unknown = refunds(null); await unknown.page.doRejectRefund();
  assert.equal(unknown.toasts.length, 0); assert.equal(unknown.page.rejectReason, '已核对配送记录');
  assert.ok(unknown.page.actionError.includes('未能确认处理结果'));
});
test('refund result from an old account cannot update the current account UI', async () => {
  const r = refunds({ status: 'REJECTED', originalEscrow: 1 });
  r.page.canApplyResponse = () => false;
  await r.page.doRejectRefund();
  assert.equal(r.toasts.length, 0); assert.equal(r.page.rejectReason, '已核对配送记录');
});
