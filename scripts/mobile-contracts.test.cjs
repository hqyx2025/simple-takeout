const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME || 'C:/Program Files/Huawei/DevEco Studio', 'tools/ohpm/node_modules/typescript'));
const source = file => fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/', file), 'utf8');
const newline = String.fromCharCode(10);
function fn(text, name, exported = true, async = true) {
  const start = text.indexOf((exported ? 'export ' : '') + (async ? 'async ' : '') + 'function ' + name + '(');
  assert.ok(start >= 0, name); return text.slice(start, text.indexOf(newline + '}', start) + 2);
}
function method(text, name) {
  const start = text.search(new RegExp('^  (?:private )?(?:async )?' + name + '[(]', 'm'));
  assert.ok(start >= 0, name);
  const lineEnd = text.indexOf(newline, start);
  return text.slice(start, text.slice(start, lineEnd).trim().endsWith('}') ? lineEnd : text.indexOf(newline + '  }', start) + 4);
}
function run(text, context) {
  const transpiled = ts.transpileModule(text, { reportDiagnostics: true, compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS } });
  assert.equal(transpiled.diagnostics.length, 0, 'production functions must parse');
  vm.runInNewContext(transpiled.outputText, context);
}
test('refund forwards partial amount, relative image evidence and unchanged idempotency key without duplicate toast', async () => {
  const exports = {}, calls = [];
  run(fn(source('service/api/OrdersApi.ets'), 'applyRefundApi'), { exports, post: async (...args) => { calls.push(args); return { code: 200, data: { id: 7 } }; } });
  assert.equal((await exports.applyRefundApi(10, 'QUALITY_ISSUE', '损坏', 'same-request', 12.50, ['/uploads/a.jpg'])).id, 7);
  assert.equal(calls[0][0], '/api/orders/10/refund');
  assert.equal(calls[0][1].amount, 12.50); assert.equal(calls[0][1].idempotencyKey, 'same-request');
  assert.equal(calls[0][1].evidenceImages[0], '/uploads/a.jpg'); assert.equal(calls[0][2], false);
});
test('delivery and after-sales API roles, payloads and failure states follow the agreed contract', async () => {
  const text = source('service/api/AfterSalesApi.ets'), calls = [], exports = {};
  const names = ['fetchDeliveryIssuesApi', 'reportDeliveryIssueApi', 'fetchAdminDeliveryIssuesApi', 'resolveDeliveryIssueApi', 'fetchFulfillmentApi', 'saveFulfillmentApi', 'fetchMerchantOrderRefundsApi', 'submitMerchantEvidenceApi', 'appealRefundApi'];
  const code = fn(text, 'issuePath', false, false) + newline + names.map(name => fn(text, name)).join(newline);
  const request = async (...args) => { calls.push(args); return { code: 500, data: null }; };
  run(code, { exports, UserRole: { CUSTOMER: 0, MERCHANT: 1, RIDER: 3, ADMIN: 2 }, get: request, post: request, put: request });
  for (const [role, prefix] of [[0, '/api/orders/'], [1, '/api/merchant/orders/'], [3, '/api/rider/orders/']]) {
    assert.equal(await exports.fetchDeliveryIssuesApi(10, role), null);
    assert.equal(calls.at(-1)[0], prefix + '10/issues');
    assert.equal(calls.at(-1)[1], false);
  }
  assert.equal(await exports.appealRefundApi(10, 7, { reason: '申诉说明', evidenceImages: ['/uploads/a.jpg'] }), null);
  assert.equal(calls.at(-1)[0], '/api/orders/10/refunds/7/appeal'); assert.equal(calls.at(-1)[2], false);
  assert.equal(await exports.submitMerchantEvidenceApi(7, { response: '商家说明', evidenceImages: [] }), false);
  assert.equal(calls.at(-1)[0], '/api/after-sales/7/merchant-evidence');
  assert.equal(await exports.fetchMerchantOrderRefundsApi(10), null); assert.equal(calls.at(-1)[0], '/api/merchant/orders/10/refunds');
  assert.equal(await exports.saveFulfillmentApi(4, 'MERCHANT'), false); assert.equal(calls.at(-1)[0], '/api/merchant/stores/4/fulfillment'); assert.equal(calls.at(-1)[1].mode, 'MERCHANT');
  assert.equal(await exports.resolveDeliveryIssueApi(7, { action: 'REASSIGN', note: '重新调度' }), false); assert.equal(calls.at(-1)[0], '/api/admin/delivery-issues/7/resolve');
});
function support() {
  const text = source('pages/OrderSupportPage.ets'), exports = {}, pending = [], state = { epoch: 1 };
  const request = () => new Promise(resolve => pending.push(resolve));
  const code = 'export class Page {' + ['current', 'load', 'report', 'onPageHide'].map(name => method(text, name)).join(newline) + '}';
  run(code, { exports, UserRole: { CUSTOMER: 0, MERCHANT: 1, RIDER: 3, ADMIN: 2 }, getAuthSessionEpoch: () => state.epoch, getLastApiErrorMessage: () => '', fetchDeliveryIssuesApi: request, fetchAdminDeliveryIssuesApi: request, fetchMerchantOrderRefundsApi: request, reportDeliveryIssueApi: request });
  const page = new exports.Page();
  Object.assign(page, { active: true, loggedIn: true, owner: 1, role: 3, user: { id: 1, role: 3 }, epoch: 1, pageVersion: 0, requestVersion: 0, orderId: 10, storeId: 0, canReport: true, issues: [{ id: 9 }], refunds: [], page: 1, hasMore: true, loading: false, busy: false, issueType: 'OTHER', note: '无法联系用户', pendingIssue: null });
  return { page, pending, state };
}
test('support history preserves data on failure and rejects epoch, owner and hide/show late responses', async () => {
  for (const change of ['failure', 'owner', 'epoch', 'hide-show', 'newer']) {
    const r = support(), running = r.page.load();
    if (change === 'owner') r.page.user = { id: 2, role: 3 };
    if (change === 'epoch') r.state.epoch++;
    if (change === 'hide-show') { r.page.onPageHide(); r.page.active = true; }
    if (change === 'newer') { const newer = r.page.load(); r.pending[1]([{ id: 22 }]); await newer; }
    r.pending[0](change === 'failure' ? null : [{ id: 11 }]); await running;
    assert.equal(r.page.issues[0].id, change === 'newer' ? 22 : 9, change);
    if (change === 'failure') { assert.ok(r.page.errorText); assert.equal(r.page.loading, false); }
  }
});
test('support report retries the same idempotency key and payload after an unconfirmed result', async () => {
  const r = support(), first = r.page.report(); const original = r.page.pendingIssue;
  r.pending[0](false); await first; assert.equal(r.page.issueLocked, true);
  r.page.note = 'changed'; r.page.issueType = 'FOOD_DAMAGED';
  const retry = r.page.report(); assert.equal(r.page.pendingIssue, original);
  r.pending[1](false); await retry; assert.equal(r.page.pendingIssue.note, '无法联系用户'); assert.equal(r.page.busy, false);
});
test('image evidence rejects completions belonging to an earlier page version', () => {
  const text = source('components/EvidenceImages.ets'), exports = {}, state = { epoch: 1, version: 4 };
  run('export class Evidence {' + method(text, 'current') + '}', { exports, getAuthSessionEpoch: () => state.epoch, AppStorage: { get: key => key === 'user' ? { id: 1 } : true } });
  const evidence = new exports.Evidence(); Object.assign(evidence, { alive: true, version: 1, contextVersion: () => state.version });
  assert.equal(evidence.current(1, 1, 1, 4), true); state.version++;
  assert.equal(evidence.current(1, 1, 1, 4), false); assert.equal(evidence.current(1, 2, 1, 5), false);
});