const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME || 'C:/Program Files/Huawei/DevEco Studio', 'tools/ohpm/node_modules/typescript'));
const source = name => fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/', name), 'utf8');
function method(text, name) {
  const match = new RegExp('^  (?:private )?(?:async )?' + name + '[(]', 'm');
  // Match method boundaries using the production file's two-space indentation.
  const start = text.search(match);
  assert.ok(start >= 0, name);
  const lineEnd = text.indexOf('\n', start);
  if (text.slice(start, lineEnd).trim().endsWith('}')) return text.slice(start, lineEnd);
  return text.slice(start, text.indexOf('\n  }', start) + 4);
}
function pageRuntime(name, role) {
  const text = source('pages/' + name + '.ets');
  const load = name === 'OrderListPage' ? 'refreshOrders' : 'loadOrders';
  const names = ['canApplyOrders', load, 'onPageHide'];
  const methods = names.map(n => method(text, n)).join('\n');
  const pending = [], storage = new Map([['user', { id: 1, role }]]), state = { epoch: 1 };
  const exports = {};
  const network = () => new Promise(resolve => pending.push(resolve));
  const code = ts.transpileModule('export class Page { ' + methods + '\n}', { compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS } }).outputText;
  vm.runInNewContext(code, { exports, AppStorage: { get: k => storage.get(k) }, UserRole: { CUSTOMER: 0, MERCHANT: 1, ADMIN: 2 }, getAuthSessionEpoch: () => state.epoch, fetchUserOrdersPageApi: network, fetchMerchantOrdersPageApi: network, get: network });
  const page = new exports.Page();
  Object.assign(page, { pageActive: true, loggedIn: true, ordersRequestVersion: 0, ordersLoading: false, loading: false, currentStatus: -1, pageOrders: [{ id: 9 }], allOrders: [{ id: 9 }], orders: [{ id: 9 }], currentPage: 2, page: 2, totalOrders: 5, total: 5, hasMoreOrders: true, hasMore: true, refreshDataSource() {}, applyFilter() {} });
  return { page, pending, storage, state, load, data: name === 'OrderListPage' ? 'pageOrders' : name === 'MerchantOrdersPage' ? 'allOrders' : 'orders', admin: name === 'AdminOrderPage' };
}
const configs = [['OrderListPage', 0], ['MerchantOrdersPage', 1], ['AdminOrderPage', 2]];
const result = id => ({ list: [{ id }], total: 10, page: 3, hasMore: true });
for (const [name, role] of configs) {
  test(name + ': failed refresh/append preserve data, pagination and allow retry', async () => {
    for (const append of [false, true]) {
      const r = pageRuntime(name, role), running = r.page[r.load](3, append);
      r.pending.shift()(r.admin ? { code: 500 } : null); await running;
      assert.equal(r.page[r.data][0].id, 9);
      assert.equal(r.page.currentPage, 2); assert.equal(r.page.page, 2);
      assert.equal(r.page.ordersError, true); assert.equal(r.page.loading, false); assert.equal(r.page.ordersLoading, false);
      const retry = r.page[r.load](3, append); r.pending.shift()(r.admin ? { code: 200, data: result(10) } : result(10)); await retry;
      assert.equal(r.page.ordersError, false); assert.equal(r.page[r.data].at(-1).id, 10);
    }
  });
  test(name + ': epoch, owner, page lifecycle and request version reject late results', async () => {
    for (const change of ['epoch', 'owner', 'hide', 'newer']) {
      const r = pageRuntime(name, role), old = r.page[r.load]();
      if (change === 'epoch') r.state.epoch++;
      if (change === 'owner') r.storage.set('user', { id: 2, role });
      if (change === 'hide') r.page.onPageHide();
      if (change === 'newer') { const newer = r.page[r.load](); r.pending[1](r.admin ? { code: 200, data: result(22) } : result(22)); await newer; }
      r.pending[0](r.admin ? { code: 200, data: result(11) } : result(11)); await old;
      assert.equal(r.page[r.data][0].id, change === 'newer' ? 22 : 9, change);
    }
  });
}
function exportedFunction(text, name) {
  const start = text.indexOf('export async function ' + name + '(');
  assert.ok(start >= 0, name);
  return text.slice(start, text.indexOf(String.fromCharCode(10) + '}', start) + 2);
}
function uploadRuntime(responses, refreshResult = 1) {
  const exports = {}, tokens = [], pending = [], counters = { refresh: 0, expire: 0, open: 0, close: 0, destroy: 0, toast: 0 };
  const context = {
    exports, authToken: 'old', refreshToken: 'refresh-old', authSessionEpoch: 1, lastApiErrorMessage: '',
    fileIo: { openSync: () => { counters.open++; return { fd: 3 }; }, statSync: () => ({ size: 4 }), readSync() {}, closeSync() { counters.close++; }, OpenMode: { READ_ONLY: 0 } },
    http: { createHttp: () => ({ request: async (_, options) => { tokens.push(options.header.Authorization); const next = responses.shift(); if (typeof next === 'function') return await next(context); return next; }, destroy() { counters.destroy++; } }), RequestMethod: { POST: 1 }, HttpDataType: { STRING: 1 } },
    API_CONFIG: { CONNECT_TIMEOUT: 1000, TIMEOUT: 2000 }, buildFileName: () => 'a.jpg', buildContentType: () => 'image/jpeg', logError() {},
    refreshAfterUnauthorized: async () => { counters.refresh++; context.authToken = 'new'; return refreshResult; },
    expireLocalSession: async () => { counters.expire++; context.authSessionEpoch++; context.authToken = ''; },
    notifyApiError: () => counters.toast++
  };
  const code = ts.transpileModule(exportedFunction(source('service/HttpClient.ets'), 'uploadFile'), { compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS } }).outputText;
  vm.runInNewContext(code, context);
  return { context, counters, tokens, upload: show => exports.uploadFile('/upload', '/a.jpg', show) };
}
const unauthorized = { responseCode: 401, result: '' };
const uploaded = { responseCode: 200, result: JSON.stringify({ code: 200, data: { url: '/uploads/a.jpg' } }) };
test('upload retries HTTP and business 401 once after refresh, reusing file and rotating token', async () => {
  for (const first of [unauthorized, { responseCode: 200, result: JSON.stringify({ code: 401 }) }]) {
    const r = uploadRuntime([first, uploaded]);
    assert.equal((await r.upload(true)).url, '/uploads/a.jpg');
    assert.deepEqual(r.tokens, ['Bearer old', 'Bearer new']);
    assert.deepEqual(r.counters, { refresh: 1, expire: 0, open: 1, close: 1, destroy: 2, toast: 0 });
  }
});
test('upload second 401 expires once without a third attempt or duplicate toast', async () => {
  const r = uploadRuntime([unauthorized, unauthorized, uploaded]);
  assert.equal(await r.upload(true), null);
  assert.equal(r.tokens.length, 2); assert.equal(r.counters.refresh, 1); assert.equal(r.counters.expire, 1); assert.equal(r.counters.toast, 1);
});
test('upload transient refresh failure preserves login and does not retry non-401 failures', async () => {
  for (const [response, refresh] of [[unauthorized, 0], [{ responseCode: 500, result: '' }, 1]]) {
    const r = uploadRuntime([response], refresh);
    assert.equal(await r.upload(false), null); assert.equal(r.tokens.length, 1); assert.equal(r.counters.expire, 0); assert.equal(r.counters.toast, 0);
  }
});
test('late upload success from a replaced session is ignored', async () => {
  const r = uploadRuntime([async context => { context.authSessionEpoch++; return uploaded; }]);
  assert.equal(await r.upload(true), null); assert.equal(r.counters.toast, 0); assert.equal(r.counters.close, 1); assert.equal(r.counters.destroy, 1);
});
