const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME || 'C:/Program Files/Huawei/DevEco Studio', 'tools/ohpm/node_modules/typescript'));
const root = path.join(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
function compile(source, globals = {}) {
  const exports = {};
  const code = ts.transpileModule(source.replace(/^import .*?from '[^']+'\s*$/gm, ''), {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
  }).outputText;
  vm.runInNewContext(code, { exports, ...globals });
  return exports;
}
function method(source, name) {
  const start = source.search(new RegExp('^  (?:private )?(?:async )?' + name + '\\(', 'm'));
  assert.ok(start >= 0, name);
  const lineEnd = source.indexOf('\n', start);
  if (source.slice(start, lineEnd).trim().endsWith('}')) return source.slice(start, lineEnd);
  return source.slice(start, source.indexOf('\n  }', start) + 4);
}
function identity() {
  const state = { epoch: 1, user: { id: 7, role: 1 }, loggedIn: true, consent: true };
  const globals = { UserRole: { CUSTOMER: 0, MERCHANT: 1, ADMIN: 2, RIDER: 3 },
    getAuthSessionEpoch: () => state.epoch,
    AppStorage: { get: key => ({ user: state.user, isLoggedIn: state.loggedIn, privacyConsent: state.consent, appContext: {} })[key] }
  };
  return { state, globals };
}

test('display mapping separates delivered confirmation, settlement and refunds without granting actions', () => {
  const r = identity(), api = compile(read('service/OrderStatus.ets'), r.globals);
  assert.equal(api.orderDisplayState(4, 0).code, 'CONFIRMING');
  assert.equal(api.orderDisplayState(4, 1).code, 'COMPLETED');
  assert.equal(api.orderDisplayState(6, 2).code, 'REFUNDED');
  assert.equal(api.orderDisplayState(4, 2).label, '已退款');
  assert.equal(api.orderDisplayState(2, 0, 3).label, '待取餐');
  assert.equal(api.refundDisplayText('REJECTED'), '已驳回');
  for (const capabilities of [null, {}, [], { allowedActions: [] }, { allowedActions: ['PAY', 5] }]) {
    assert.equal(api.canOrderAction({ capabilities }, 'PAY', true), false);
  }
  assert.equal(api.canOrderAction({ capabilities: { allowedActions: ['PAY'] } }, 'PAY', false), true);
});

test('page session rejects old generations, hidden pages, revoked roles and replaced accounts', () => {
  for (const changed of ['generation', 'hidden', 'epoch', 'account', 'role', 'logout']) {
    const r = identity(), { PageSession } = compile(read('service/PageSession.ets'), r.globals);
    const session = new PageSession(); assert.equal(session.start(1), true);
    const version = session.request(); assert.equal(session.current(version), true);
    if (changed === 'generation') session.request();
    if (changed === 'hidden') session.pause();
    if (changed === 'epoch') r.state.epoch++;
    if (changed === 'account') r.state.user.id++;
    if (changed === 'role') r.state.user.role = 0;
    if (changed === 'logout') r.state.loggedIn = false;
    assert.equal(session.current(version), false, changed);
  }
});

function drafts() {
  const r = identity(), disk = new Map();
  let fail = false;
  const prefs = { get: async (key, fallback) => disk.get(key) ?? fallback,
    put: async (key, value) => { if (fail) throw Error('storage unavailable'); disk.set(key, value); },
    delete: async key => { disk.delete(key); }, flush: async () => {} };
  const api = compile(read('service/FormDraftStore.ets'), { ...r.globals, preferences: { getPreferences: async () => prefs } });
  return { ...r, disk, ...api, fail: () => { fail = true; } };
}

test('drafts survive a new store instance, keep an allowlist and isolate accounts and store scopes', async () => {
  const r = drafts(), draft = new r.FormDraftStore();
  assert.equal(await draft.open('store:2:edit', { name: 'server' }), null);
  assert.equal(await draft.save({ name: 'draft', password: 'NEVER-PERSIST', stock: '999' }), true);
  const saved = JSON.parse([...r.disk.values()][0]);
  assert.deepEqual(saved.fields, { name: 'draft' });
  const reopened = new r.FormDraftStore();
  assert.equal((await reopened.open('store:2:edit', { name: 'new server' })).fields.name, 'draft');
  assert.equal(await new r.FormDraftStore().open('store:3:edit', { name: '' }), null);
  r.state.user.id = 8;
  assert.equal(await new r.FormDraftStore().open('store:2:edit', { name: '' }), null);
  assert.equal(await draft.save({ name: 'stale response' }), true);
  assert.equal(JSON.parse([...r.disk.values()][0]).fields.name, 'draft');
});

test('draft writes reject missing consent, logout and an epoch change queued before persistence', async () => {
  for (const changed of ['consent', 'logout', 'epoch']) {
    const r = drafts(), draft = new r.FormDraftStore(); await draft.open('goods:2:create', { name: '' });
    const pending = draft.save({ name: 'pending' });
    if (changed === 'consent') r.state.consent = false;
    if (changed === 'logout') r.state.loggedIn = false;
    if (changed === 'epoch') r.state.epoch++;
    assert.equal(await pending, false);
    assert.equal(r.disk.size, 0);
  }
});

test('corrupt drafts are retained until explicit discard and write failure is reported', async () => {
  const r = drafts(), draft = new r.FormDraftStore();
  r.disk.set('7:1:store:2:edit', '{bad json');
  await assert.rejects(draft.open('store:2:edit', { name: '' }), /草稿/);
  await draft.save({ name: 'must not overwrite corruption' });
  assert.equal(r.disk.get('7:1:store:2:edit'), '{bad json');
  assert.equal(await draft.clear(), true); assert.equal(r.disk.size, 0);
  draft.resume({ name: '' }); r.fail();
  assert.equal(await draft.save({ name: 'not saved' }), false);
});

test('successful submission clears queued drafts and prevents later callbacks from recreating them', async () => {
  const r = drafts(), draft = new r.FormDraftStore(); await draft.open('goods:2:edit:5', { name: '' });
  const save = draft.save({ name: 'pending' }); const clear = draft.clear();
  await save; await clear; await draft.save({ name: 'late callback' });
  assert.equal(r.disk.size, 0);
});

function inventory() {
  const r = identity(), pending = [], calls = [], pageSource = read('pages/MerchantInventoryPage.ets');
  const { PageSession } = compile(read('service/PageSession.ets'), r.globals);
  const api = compile('export class Page { ' + ['applyGoods', 'updateStock', 'save', 'load'].map(name => method(pageSource, name)).join('\n') + '\n}', {
    ...r.globals, promptAction: { showToast() {} },
    changeMerchantStockApi: (...args) => { calls.push(args); return new Promise(resolve => pending.push(resolve)); },
    fetchMerchantGoodsResultApi: () => new Promise(resolve => pending.push(resolve))
  });
  const page = new api.Page();
  Object.assign(page, { session: new PageSession(), storeId: 2, goodsId: 5, amount: '2', replenish: true,
    busy: false, loading: false, failed: false, selection: 0, currentStock: 5,
    goods: { id: 5, stock: 5, version: 3, specs: [{ id: 20, stock: 5, version: 7, name: '大份' }] } });
  page.session.start(1);
  return { ...r, page, pending, calls };
}

test('inventory submits one selected SKU with its version and only applies confirmed server stock', async () => {
  const r = inventory(), work = r.page.save(); await r.page.save();
  assert.equal(r.calls.length, 1); assert.deepEqual(r.calls[0], [5, 20, 2, 7, true]);
  assert.equal(r.page.currentStock, 5);
  r.pending.shift()({ id: 5, stock: 7, specs: [{ id: 20, name: '大份', stock: 7, version: 8 }] }); await work;
  assert.equal(r.page.currentStock, 7); assert.equal(r.page.amount, '');
});

test('inventory ignores stale identity responses, blocks invalid quantities and requires refresh after conflict', async () => {
  for (const value of ['', '-1', '0', '1.2', '10000', 'abc']) {
    const r = inventory(); r.page.amount = value; await r.page.save(); assert.equal(r.calls.length, 0, value);
  }
  const old = inventory(), pending = old.page.save(); old.state.epoch++;
  old.pending.shift()({ id: 5, stock: 99, specs: [] }); await pending;
  assert.equal(old.page.currentStock, 5); assert.equal(old.page.amount, '2');
  const r = inventory(), failed = r.page.save(); r.pending.shift()(null); await failed;
  assert.equal(r.page.failed, true); assert.equal(r.page.currentStock, 5);
  await r.page.save(); assert.equal(r.calls.length, 1);
  const refresh = r.page.load(); r.pending.shift()([{ id: 5, stock: 8, version: 9, specs: [] }]); await refresh;
  assert.equal(r.page.failed, false); assert.equal(r.page.currentStock, 8);
});

test('management paging failure preserves data and page; late responses cannot replace a newer identity', async () => {
  for (const [pageName, api, field] of [['AdminAuditPage', 'fetchAdminOperationLogsResultApi', 'logs'],
    ['AdminUserPage', 'fetchAdminUsersPageResultApi', 'users'], ['AdminProductPage', 'fetchAdminProductsResultApi', 'products']]) {
    for (const scenario of ['refresh failure', 'append failure', 'logout']) {
      const r = identity(); r.state.user.role = 2;
      const { PageSession } = compile(read('service/PageSession.ets'), r.globals);
      const pending = [], cls = compile('export class Page { ' + ['refresh', 'loadMore'].map(name => method(read('pages/' + pageName + '.ets'), name)).join('\n') + '\n}', {
        ...r.globals, promptAction: { showToast() {} }, [api]: () => new Promise(resolve => pending.push(resolve))
      });
      const page = new cls.Page(); Object.assign(page, { remoteSession: new PageSession(), remoteVisible: true,
        loading: false, remoteLoading: false, hasMore: true, page: 3, total: 4, keyword: 'keep', roleFilter: -1, statusFilter: -1,
        [field]: [{ id: 9 }] });
      const work = scenario === 'append failure' ? page.loadMore() : page.refresh();
      if (scenario === 'logout') r.state.loggedIn = false;
      pending.shift()(scenario === 'logout' ? { list: [{ id: 99 }], total: 9, page: 1, hasMore: true } : null); await work;
      assert.equal(page[field][0].id, 9); assert.equal(page.page, 3); assert.equal(page.keyword, 'keep');
      if (scenario !== 'logout') { assert.equal(page.remoteFailed, true); assert.equal(page.loading, false); }
    }
  }
});

test('order and store routes carry identifiers and the route manifest resolves every new task', () => {
  for (const name of ['StoreDetailPage', 'OrderDetailPage', 'ReviewPage', 'MerchantAddGoodsPage', 'MerchantEditGoodsPage', 'PasswordResetPage']) {
    assert.doesNotMatch(read('pages/' + name + '.ets'), /AppStorage\.get<[^>]+>\('(?:selectedStoreId|currentOrderId|merchantGoodsStoreId|merchantEditGoodsId|passwordResetMode)'/);
  }
  const manifest = JSON.parse(fs.readFileSync(path.join(root, '../resources/base/profile/main_pages.json'), 'utf8'));
  for (const route of ['MerchantStoreDetailPage', 'MerchantStoreEditPage', 'MerchantGoodsPage', 'MerchantCategoryPage',
    'MerchantInventoryPage', 'MerchantFulfillmentPage', 'OrderIssuePage', 'AdminDeliveryIssuesPage', 'ChangeLoginPasswordPage', 'PaymentPasswordPage', 'CloseAccountPage']) {
    assert.ok(manifest.src.includes('pages/' + route), route);
    assert.ok(fs.existsSync(path.join(root, 'pages', route + '.ets')));
  }
});

test('HTTP read adapters distinguish a failed request from an empty successful page', async () => {
  let response = { code: 503, data: null };
  const api = compile(read('service/api/AdminApi.ets'), { get: async () => response });
  for (const [name, args] of [['fetchAdminOperationLogsResultApi', [3]], ['fetchAdminUsersPageResultApi', [undefined, undefined, 'keep', 3]],
    ['fetchAdminProductsResultApi', ['keep', undefined, 3]]]) {
    assert.equal(await api[name](...args), null);
    response = { code: 200, data: { list: [], total: 0, page: 3, pageSize: 50, hasMore: false } };
    const empty = await api[name](...args);
    assert.equal(empty.list.length, 0); assert.equal(empty.page, 3);
    response = { code: 503, data: null };
  }
});
