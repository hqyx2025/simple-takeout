const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME || 'C:/Program Files/Huawei/DevEco Studio', 'tools/ohpm/node_modules/typescript'));
const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const deferred = () => { let resolve, reject; const promise = new Promise((yes, no) => { resolve = yes; reject = no; }); return { promise, resolve, reject }; };
const tick = () => new Promise(resolve => setImmediate(resolve));
const logger = { logInfo() {}, logWarn() {}, logError() {} };
const mutation = process.env.AUTH_SESSION_MUTATION || '';
function selected(file, names) {
  const source = read(file), parsed = ts.createSourceFile(file, source, ts.ScriptTarget.Latest, true);
  return parsed.statements.filter(statement => names.includes(statement.name?.text)
    || (ts.isVariableStatement(statement) && statement.declarationList.declarations.some(item => names.includes(item.name.text))))
    .map(statement => statement.getText(parsed)).join('\n');
}
function evaluate(source, dependencies = {}, globals = {}) {
  const exports = {};
  const code = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS } }).outputText;
  vm.runInNewContext(code, { exports, console, ...globals, require(name) {
    assert.ok(name in dependencies, `Missing dependency ${name}`); return dependencies[name];
  } });
  return exports;
}
function tokens(options = {}) {
  let source = selected('entry/src/main/ets/service/TokenStorage.ets', [
    'StoredAuthTokens', 'TOKEN_KEY', 'tokenStorageVersion', 'tokenOperations', 'queueTokenOperation',
    'saveAuthTokens', 'loadAuthTokens', 'clearAuthTokens'
  ]);
  if (mutation === 'token-generation') source = source.replaceAll('if (version !== tokenStorageVersion) { return }', '');
  if (mutation === 'token-queue') source = source.replace('tokenOperations.then(operation)', 'operation()');
  if (mutation === 'token-read') source = source.replace('return version === tokenStorageVersion ? tokens : null', 'return tokens');
  const disk = new Map(), writes = [], pendingEncryption = [], pendingDecryption = [];
  const putStarted = deferred(), releasePut = deferred();
  const prefs = {
    get: async (key, fallback) => disk.get(key) ?? fallback,
    put: async (key, value) => {
      if (options.blockPut) { putStarted.resolve(); await releasePut.promise; }
      writes.push(value); disk.set(key, value);
    },
    delete: async key => disk.delete(key), flush: async () => {}
  };
  const api = evaluate(source, {}, {
    getPrefs: async () => prefs,
    encrypt: value => options.slowEncrypt ? new Promise(resolve => pendingEncryption.push(() => resolve(value))) : Promise.resolve(value),
    decrypt: value => options.slowDecrypt ? new Promise(resolve => pendingDecryption.push(() => resolve(value))) : Promise.resolve(value)
  });
  return { api, disk, writes, pendingEncryption, pendingDecryption, putStarted, releasePut };
}

test('logout invalidates encryption already running; a newer login is the only persisted identity', async () => {
  const r = tokens({ slowEncrypt: true });
  const first = r.api.saveAuthTokens('access-A', 'refresh-A'); await tick();
  assert.equal(r.pendingEncryption.length, 1);
  const clearing = r.api.clearAuthTokens();
  const second = r.api.saveAuthTokens('access-B', 'refresh-B');
  r.pendingEncryption.shift()(); await tick();
  assert.equal(r.writes.some(value => value.includes('access-A')), false, 'invalidated encryption must never be written');
  assert.equal(r.pendingEncryption.length, 1);
  r.pendingEncryption.shift()(); await Promise.all([first, clearing, second]);
  assert.equal(JSON.parse(r.disk.get('encrypted_tokens_v1')).accessToken, 'access-B');
});

test('logout waits for an already-started device write and remains the final disk state', async () => {
  const r = tokens({ blockPut: true });
  const saving = r.api.saveAuthTokens('access-A', 'refresh-A');
  await r.putStarted.promise;
  const clearing = r.api.clearAuthTokens(); await tick();
  r.releasePut.resolve(); await Promise.all([saving, clearing]);
  assert.equal(r.disk.has('encrypted_tokens_v1'), false, 'an older put must not finish after the clear');
});

test('logout invalidates a credential read paused in device decryption', async () => {
  const r = tokens({ slowDecrypt: true });
  r.disk.set('encrypted_tokens_v1', JSON.stringify({ accessToken: 'A', refreshToken: 'RA' }));
  const reading = r.api.loadAuthTokens(); await tick();
  const clearing = r.api.clearAuthTokens();
  r.pendingDecryption.shift()();
  assert.equal(await reading, null);
  await clearing; assert.equal(r.disk.size, 0);
});

function loginRuntime() {
  let source = selected('entry/src/main/ets/service/AppStorageManager.ets', [
    'loginRequestVersion', 'loginRemote', 'loginByEmailRemote', 'completeRemoteLogin'
  ]);
  if (mutation === 'login-generation') source = source.replace(
    'if (requestVersion !== loginRequestVersion || sessionEpoch !== getAuthSessionEpoch() || !isCurrent())', 'if (false)');
  const requests = [], saved = [], synced = [], memory = new Map();
  const state = { epoch: 0, token: '' };
  const request = () => { const pending = deferred(); requests.push(pending); return pending.promise; };
  const api = evaluate(source, {}, {
    apiLogin: request, apiLoginByEmail: request, getAuthSessionEpoch: () => state.epoch,
    setAuthTokens: token => { state.token = token; state.epoch++; },
    AppStorage: { setOrCreate: (key, value) => memory.set(key, value) },
    setStoredUser: user => memory.set('user', user), saveAuthTokens: async (access, refresh) => saved.push([access, refresh]),
    registerPushForCurrentSession() {}, syncAddressesRemote: async () => synced.push('addresses'),
    syncCartRemote: async () => synced.push('cart'), saveAllData: async () => synced.push('purge'),
    UserRole: { CUSTOMER: 0, MERCHANT: 1, ADMIN: 2, RIDER: 3 }, ...logger
  });
  return { api, requests, saved, synced, memory, state };
}
const session = id => ({ token: `access-${id}`, refreshToken: `refresh-${id}`, user: { id, role: 0 } });

test('a late login response cannot replace a newer account in memory or secure storage', async () => {
  const r = loginRuntime();
  const first = r.api.loginRemote('13800138000', 'secret', 'USER');
  const second = r.api.loginByEmailRemote('13800138001', 'b@example.test', '123456', 'USER');
  r.requests[1].resolve(session(2)); assert.equal((await second).id, 2);
  r.requests[0].resolve(session(1)); assert.equal(await first, undefined);
  assert.equal(r.memory.get('user').id, 2); assert.equal(r.state.token, 'access-2');
  assert.deepEqual(r.saved, [['access-2', 'refresh-2']]);
});

test('logout or a departed login page rejects successful in-flight authentication before committing it', async () => {
  for (const reason of ['logout', 'page']) {
    const r = loginRuntime(); let active = true;
    const running = r.api.loginRemote('13800138000', 'secret', 'USER', () => active);
    if (reason === 'logout') r.state.epoch++; else active = false;
    r.requests[0].resolve(session(1));
    assert.equal(await running, undefined, reason);
    assert.equal(r.memory.size, 0, reason); assert.equal(r.saved.length, 0, reason);
  }
});

function refreshRuntime() {
  const names = ['authToken', 'refreshToken', 'authSessionEpoch', 'refreshInFlight', 'refreshInFlightEpoch',
    'setAuthTokens', 'getAuthToken', 'getRefreshToken', 'getAuthSessionEpoch', 'refreshAfterUnauthorized'];
  const requests = [], saved = [];
  let source = selected('entry/src/main/ets/service/HttpClient.ets', names);
  if (mutation === 'refresh-generation') source = source.replace('refreshInFlight !== null && refreshInFlightEpoch === epoch', 'refreshInFlight !== null');
  source += '\nexport { refreshAfterUnauthorized };';
  const api = evaluate(source, {}, {
    rcp: { Request: class {} }, API_CONFIG: { CONNECT_TIMEOUT: 100, TIMEOUT: 100 }, activeBaseUrl: 'https://example.test',
    getClient: () => ({ fetch: () => { const pending = deferred(); requests.push(pending); return pending.promise; } }),
    buildHeaders: () => ({}), clearDeliveryForms() {}, AppStorage: { setOrCreate() {} },
    saveAuthTokens: async (access, refresh) => saved.push([access, refresh]), ...logger
  });
  return { api, requests, saved };
}
const refreshResponse = id => ({ statusCode: 200, toJSON: () => ({ code: 200, data: { token: `access-${id}`, refreshToken: `refresh-${id}` } }) });

test('concurrent 401 refreshes share only their own session, and an old completion cannot clear the new refresh', async () => {
  const r = refreshRuntime(); r.api.setAuthTokens('A', 'RA');
  const first = r.api.refreshAfterUnauthorized('A', 'RA', r.api.getAuthSessionEpoch());
  r.api.setAuthTokens('B', 'RB');
  const epoch = r.api.getAuthSessionEpoch();
  const second = r.api.refreshAfterUnauthorized('B', 'RB', epoch);
  assert.equal(r.requests.length, 2, 'account B must not share the pending refresh of account A');
  r.requests[0].resolve(refreshResponse(1)); assert.equal(await first, 2);
  const third = r.api.refreshAfterUnauthorized('B', 'RB', epoch);
  assert.equal(r.requests.length, 2, 'account B should still share its own pending refresh');
  r.requests[1].resolve(refreshResponse(2));
  assert.deepEqual(await Promise.all([second, third]), [1, 1]);
  assert.equal(r.api.getAuthToken(), 'access-2'); assert.deepEqual(r.saved, [['access-2', 'refresh-2']]);
});

function persistenceRuntime(options = {}) {
  const memory = new Map([['appContext', {}]]), disk = new Map(), calls = [];
  const state = { epoch: 0, token: '', secure: { accessToken: 'A', refreshToken: 'RA' } };
  const prefs = { get: async (key, fallback) => disk.get(key) ?? fallback,
    put: async (key, value) => { calls.push('put:' + key); disk.set(key, value); }, delete: async key => disk.delete(key),
    flush: async () => { if (options.failFlush) throw Error('disk unavailable'); } };
  let source = read('entry/src/main/ets/service/DataPersistence.ets');
  if (mutation === 'privacy-gate') source = source.replace('if (!consented) {', 'if (false) {');
  const api = evaluate(source, {
    '@ohos.data.preferences': { default: { getPreferences: async () => prefs } },
    '../model/Models': { createEmptyUser: () => ({ id: 0, role: 0, balance: 0 }) }, './AppLogger': logger,
    './HttpClient': { initializeApiBaseUrl: persist => {
      calls.push('network');
      const pending = (options.probe ?? Promise.resolve('https://example.test')).then(async url => { await persist(url); return url; });
      pending.catch(() => {});
      state.backend = pending;
      return pending;
    },
      getAuthSessionEpoch: () => state.epoch, setAuthTokens: token => { state.token = token; state.epoch++; } },
    './TokenStorage': { loadAuthTokens: async () => {
      calls.push('tokens'); if (options.failRead) throw Error('credential store unavailable'); return state.secure;
    }, clearAuthTokens: async () => { calls.push('clear'); state.secure = null; } },
    './api/AuthApi': { fetchCurrentUserApi: async () => {
      calls.push('me'); return options.user === null ? undefined : options.user ?? { id: 2, role: 0, balance: 7 };
    } }
  }, { AppStorage: { get: key => memory.get(key), setOrCreate: (key, value) => memory.set(key, value) } });
  return { api, memory, disk, calls, state };
}

test('guest startup finishes before the delayed probe and does not rewrite a later session', async () => {
  const probe = deferred();
  const r = persistenceRuntime({ probe: probe.promise });
  r.disk.set('privacyConsent', 'true'); r.state.secure = null;
  let ready = false;
  const local = r.api.loadAllData().then(() => { ready = true; });
  await tick();
  assert.equal(ready, true, 'guest can render without the probe');
  assert.equal(r.memory.get('_persistenceReady'), true);
  assert.equal(r.memory.get('isLoggedIn'), false);
  assert.deepEqual(r.calls, ['tokens', 'network']);
  r.state.epoch++; r.memory.set('isLoggedIn', true);
  probe.resolve('https://local.test'); await Promise.all([local, r.state.backend]);
  assert.equal(r.disk.get('apiBaseUrl'), 'https://local.test');
  assert.equal(r.memory.get('isLoggedIn'), true);
  assert.equal(r.calls.includes('me'), false);
});

test('stored credentials and failed credential reads do not take the guest fast path', async () => {
  const admin = { id: 4, role: 2, balance: 0 };
  for (const failRead of [false, true]) {
    const probe = deferred();
    const r = persistenceRuntime({ probe: probe.promise, failRead, user: admin });
    r.disk.set('privacyConsent', 'true');
    const local = r.api.loadAllData();
    await tick();
    assert.equal(r.memory.has('_persistenceReady'), false);
    assert.equal(r.calls.includes('me'), false);
    probe.resolve('https://example.test'); await local;
    assert.equal(r.memory.get('isLoggedIn'), !failRead);
    if (!failRead) assert.equal(r.memory.get('user'), admin);
  }
});

test('server switch invalidates stored credentials before recording the new server', async () => {
  const r = persistenceRuntime();
  r.disk.set('privacyConsent', 'true'); r.disk.set('apiBaseUrl', 'https://old.test');
  await r.api.loadAllData();
  assert.deepEqual(r.calls, ['tokens', 'network', 'clear', 'put:apiBaseUrl']);
  assert.equal(r.memory.get('isLoggedIn'), false);
  assert.equal(r.state.secure, null);
});

test('verified cold-start sessions enter their own role page without loading a login route', async () => {
  function method(sourcePath, name) {
    const source = read('entry/src/main/ets/' + sourcePath);
    const start = source.indexOf('  private ' + name + '(');
    assert.notEqual(start, -1, name);
    return source.slice(start, source.indexOf('\n  }', start) + 4);
  }
  const UserRole = { CUSTOMER: 0, MERCHANT: 1, ADMIN: 2, RIDER: 3 };
  for (const [role, expected] of [[0, 'Index'], [1, 'MerchantCenterPage'], [2, 'AdminCenterPage'], [3, 'RiderCenterPage']]) {
    const probe = deferred(), user = { id: 4, role, balance: 0 };
    const r = persistenceRuntime({ probe: probe.promise, user });
    r.disk.set('privacyConsent', 'true');
    const routes = [];
    const { Entry, Index } = evaluate([
      'export class Entry {' + method('entryability/EntryAbility.ets', 'loadMainContentIfReady') + '}',
      'export class Index {' + method('pages/Index.ets', 'guardAdminRole') + '}'
    ].join('\n'), {}, {
      UserRole, AppStorage: { get: key => r.memory.get(key) }, ...logger,
      router: { replaceUrl: ({ url }) => routes.push(url) }
    });
    const entry = new Entry();
    entry.mainWindowStage = { loadContent: route => routes.push(route) };
    const restoring = r.api.loadAllData();
    await tick();
    entry.loadMainContentIfReady();
    assert.deepEqual(routes, []);
    probe.resolve('https://example.test'); await restoring;
    entry.persistenceLoaded = r.memory.get('_persistenceReady');
    entry.loadMainContentIfReady();
    if (routes[0] === 'pages/Index') {
      const index = new Index(); index.loggedIn = r.memory.get('isLoggedIn');
      assert.equal(index.loggedIn, true);
      index.guardAdminRole();
    }
    assert.equal(routes.at(-1), 'pages/' + expected);
  }
});

function startupTransport() {
  const names = ['activeBaseUrl', 'apiBasePending', 'apiBaseReady', 'authSessionEpoch', 'authToken', 'refreshToken',
    'initializeApiBaseUrl', 'waitForStartupBackend', 'probeApiBaseUrl', 'selectBaseUrl', 'lastApiErrorMessage', 'request'];
  let source = selected('entry/src/main/ets/service/HttpClient.ets', names) + '\nexport { request };\nexport function expire() { authSessionEpoch++ }';
  if (mutation === 'startup-request-gate') source = source.replace('await apiBasePending\n      if (requestEpoch', 'if (requestEpoch');
  const probes = [], requests = [], cloud = 'https://online.test', local = 'http://local.test';
  const api = evaluate(source, {}, {
    API_CONFIG: { BASE_URLS: [cloud, local], CONNECT_TIMEOUT: 2000, TIMEOUT: 10000 }, ...logger,
    rcp: { Request: class { constructor(url) { this.url = url; } }, createSession: () => ({
      fetch: req => { const pending = deferred(); probes.push({ url: req.url, ...pending }); return pending.promise; }, close() {}
    }) }, setApiImageBaseUrl() {}, disposeHttpClient() {}, getOperationName: () => 'test',
    performRequest: async (method, url, _data, _timeout, _token, base) => { requests.push([method, base + url]); return { code: 200 }; }
  });
  return { api, probes, requests, cloud, local };
}

test('startup transport holds requests through selection and persistence and never probes twice', async () => {
  const r = startupTransport(), save = deferred();
  const ready = r.api.initializeApiBaseUrl(() => save.promise);
  assert.equal(ready, r.api.initializeApiBaseUrl(() => assert.fail('unexpected second initializer')));
  const paths = ['/api/auth/login', '/api/auth/register', '/api/auth/email/code', '/api/auth/password/reset'];
  const queued = paths.map(url => r.api.request('POST', url));
  await tick(); assert.deepEqual(r.requests, [], 'requests must wait before sending');
  r.probes[0].reject(Error('unreachable'));
  await tick(); assert.equal(r.probes[1].url, r.local + '/api/categories');
  r.probes[1].resolve({ statusCode: 200 });
  await tick(); assert.deepEqual(r.requests, [], 'requests must wait for durable backend selection');
  save.resolve(); await Promise.all([ready, ...queued]);
  assert.deepEqual(r.requests, paths.map(url => ['POST', r.local + url]));
  assert.equal(await r.api.initializeApiBaseUrl(() => assert.fail('startup already initialized')), r.local);
  assert.equal(r.probes.length, 2);
});

test('offline fallback keeps the original default and an invalidated queued request is not sent', async () => {
  const r = startupTransport();
  const ready = r.api.initializeApiBaseUrl(async url => { assert.equal(url, r.cloud); });
  const waiting = r.api.waitForStartupBackend();
  const queued = r.api.request('POST', '/api/auth/login');
  r.api.expire();
  r.probes[0].reject(Error('offline'));
  await tick(); r.probes[1].reject(Error('offline'));
  assert.equal(await ready, r.cloud);
  assert.equal(await waiting, false);
  assert.equal((await queued).code, 401);
  assert.deepEqual(r.requests, []);
});

test('failed backend persistence stays closed to queued and later requests', async () => {
  const r = startupTransport();
  const ready = r.api.initializeApiBaseUrl(async () => { throw Error('disk unavailable'); });
  const queued = r.api.request('POST', '/api/auth/login', undefined, false);
  r.probes[0].resolve({ statusCode: 200 });
  await assert.rejects(ready, /disk unavailable/);
  assert.equal((await queued).code, 500);
  assert.equal((await r.api.request('POST', '/api/auth/login', undefined, false)).code, 500);
  assert.deepEqual(r.requests, []);
});

test('startup deletes historical personal data and restores identity only from the authenticated server', async () => {
  const r = persistenceRuntime(); r.disk.set('privacyConsent', 'true'); r.disk.set('theme', 'dark');
  const privateKeys = ['authToken', 'isLoggedIn', 'user', 'orderList', 'favoriteList', 'addressList', 'couponList', 'currentAddress', 'lastLocationPosition', 'cartItems'];
  privateKeys.forEach(key => r.disk.set(key, JSON.stringify({ owner: 1, phone: '13800138000' })));
  await r.api.loadAllData();
  assert.equal(r.memory.get('user').id, 2); assert.equal(r.memory.get('userBalance'), 7);
  assert.equal(r.memory.get('isLoggedIn'), true); assert.equal(r.memory.get('currentAddress'), null);
  privateKeys.forEach(key => assert.equal(r.disk.has(key), false, key));
  r.memory.set('orderList', [{ id: 99, phone: '13800138000' }]); await r.api.saveAllData();
  privateKeys.forEach(key => assert.equal(r.disk.has(key), false, key));
  assert.equal(r.disk.get('privacyConsent'), 'true'); assert.equal(r.disk.get('theme'), 'dark');
});

test('offline restore keeps secure credentials but exposes no previous account data', async () => {
  const r = persistenceRuntime({ user: null }); r.disk.set('privacyConsent', 'true');
  r.disk.set('user', JSON.stringify({ id: 1, balance: 200 }));
  await r.api.loadAllData();
  assert.equal(r.memory.get('isLoggedIn'), false); assert.equal(r.memory.get('user').id, 0);
  assert.equal(r.memory.get('userBalance'), 0); assert.equal(r.state.secure.accessToken, 'A');
});

test('only persisted privacy consent permits credential reads or network access; disk failure is observable', async () => {
  const r = persistenceRuntime(); r.memory.set('privacyConsent', true);
  await r.api.loadAllData(); assert.deepEqual(r.calls, []);
  assert.equal(r.memory.get('privacyConsent'), false);
  const failed = persistenceRuntime({ failFlush: true });
  await assert.rejects(failed.api.savePrivacyConsent(true), /disk unavailable/);
});

test('privacy page does not enable memory consent or restore any session after failed persistence', async () => {
  const source = read('entry/src/main/ets/pages/ConsentPage.ets');
  const start = source.indexOf('  private async accept('), end = source.indexOf('\n  }', start) + 4;
  const calls = [], result = evaluate('export class Page { submitting = false;\n' + source.slice(start, end) + '\n}', {}, {
    savePrivacyConsent: async () => { calls.push('save'); throw Error('disk unavailable'); },
    setPrivacyConsent: () => calls.push('consent'), AppStorage: { setOrCreate: () => calls.push('memory') },
    initLogger: () => calls.push('logger'), loadAllData: async () => calls.push('restore'),
    warmColdStartConnection: () => calls.push('network'), saveAllData: async () => {}, ...logger,
    promptAction: { showToast: () => calls.push('feedback') }, router: { replaceUrl: () => calls.push('navigate') }
  });
  const page = new result.Page(); await page.accept();
  assert.deepEqual(calls, ['save', 'feedback']); assert.equal(page.submitting, false);
});
