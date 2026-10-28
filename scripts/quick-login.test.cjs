const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME || 'C:/Program Files/Huawei/DevEco Studio', 'tools/ohpm/node_modules/typescript'));
const root = path.join(__dirname, '..');
const baseUrl = 'https://example.test/takeout';
const accounts = [0, 1, 2, 3].map(role => ({ role, phone: `1390000000${role}`, password: `private-test-password-${role}` }));
const configuration = { baseUrl, accounts };
const transpile = source => ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS } }).outputText;

function build(mode, localConfig) {
  let profile = { buildOption: { arkOptions: { buildProfileFields: { EXISTING: true } } } }, reads = 0;
  const result = {};
  vm.runInNewContext(transpile(fs.readFileSync(path.join(root, 'entry/hvigorfile.ts'), 'utf8')), {
    exports: result, process: { env: {} },
    require: name => {
      if (name === '@ohos/hvigor-ohos-plugin') return { OhosPluginId: { OHOS_HAP_PLUGIN: 'hap' } };
      if (name === 'node:fs') return { existsSync: () => localConfig !== undefined, readFileSync: () => { reads++; return JSON.stringify(localConfig); } };
      if (name === 'node:path') return path;
      throw new Error(`Unexpected import ${name}`);
    }
  });
  result.default.plugins[0].apply({ afterNodeEvaluate: callback => callback(), getContext: () => ({
    getModulePath: () => path.join(root, 'entry'), getBuildMode: () => mode,
    getBuildProfileOpt: () => profile, setBuildProfileOpt: value => { profile = value; }
  }) });
  const fields = profile.buildOption.arkOptions.buildProfileFields;
  assert.equal(fields.EXISTING, true);
  return { config: vm.runInNewContext(`'${fields.QUICK_LOGIN_CONFIG}'`), reads };
}

function resolver(debug, config) {
  const result = {};
  vm.runInNewContext(transpile(fs.readFileSync(path.join(root, 'entry/src/main/ets/common/QuickLoginConfig.ets'), 'utf8')), {
    exports: result, require: () => ({ default: { DEBUG: debug, QUICK_LOGIN_CONFIG: config } })
  });
  return result.getQuickLoginAccount;
}

test('private configuration reaches debug only; release never reads credentials', () => {
  const debug = build('debug', configuration);
  assert.deepEqual(JSON.parse(debug.config), configuration);
  assert.equal(debug.reads, 1);
  assert.deepEqual(build('release', configuration), { config: '', reads: 0 });
  assert.equal(build('debug', undefined).config, '');
  const escaped = { ...configuration, accounts: [{ ...accounts[0], password: "quotes'\\and\nnewlines\u2028are-safe" }] };
  assert.deepEqual(JSON.parse(build('debug', escaped).config), escaped);
});

test('four roles resolve their own credentials only on the configured backend', () => {
  const get = resolver(true, build('debug', configuration).config);
  for (const account of accounts) assert.deepEqual(JSON.parse(JSON.stringify(get(account.role, baseUrl))), account);
  assert.equal(get(0, 'http://10.0.2.2:8087'), undefined);
  assert.equal(get(4, baseUrl), undefined);
  assert.equal(resolver(false, JSON.stringify(configuration))(2, baseUrl), undefined);
});

test('missing, malformed and invalid credentials cannot trigger a login', () => {
  for (const raw of ['', '{', 'null', '{}', JSON.stringify({ baseUrl, accounts: null }),
    JSON.stringify({ baseUrl, accounts: [null] }),
    JSON.stringify({ baseUrl, accounts: [{ ...accounts[0], phone: 'bad' }] }),
    JSON.stringify({ baseUrl, accounts: [{ ...accounts[0], password: '123456' }] })]) {
    assert.equal(resolver(true, raw)(0, baseUrl), undefined);
  }
});

const pageSource = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/LoginPage.ets'), 'utf8');
const methodStart = pageSource.indexOf('  private async quickLogin(');
const methodEnd = pageSource.indexOf('\n  private loginTypeName(', methodStart);
const method = pageSource.slice(methodStart, methodEnd);
function page(getAccount, remote) {
  const result = {}, calls = [], state = { success: 0, logout: 0 };
  vm.runInNewContext(transpile(`export class Page { ${method} }`), {
    exports: result, UserRole: { CUSTOMER: 0, MERCHANT: 1, ADMIN: 2, RIDER: 3 },
    getQuickLoginAccount: getAccount, getApiBaseUrl: () => baseUrl,
    loginRemote: async (...args) => { calls.push(args); return remote(...args); },
    promptAction: { showToast: () => {} }, logout: () => { state.logout++; }, getLastRemoteErrorMessage: () => ''
  });
  const instance = new result.Page();
  Object.assign(instance, { submitting: false, password: '', loginTypeName: () => ['USER', 'MERCHANT', 'ADMIN', 'RIDER'][instance.selectedRole], onLoginSuccess: () => { state.success++; } });
  return { instance, calls, state };
}

test('quick login uses configured credentials and preserves role checks', async () => {
  const get = resolver(true, JSON.stringify(configuration));
  for (const account of accounts) {
    const p = page(get, async () => ({ role: account.role }));
    await p.instance.quickLogin(account.role);
    assert.equal(p.calls[0][0], account.phone);
    assert.equal(p.calls[0][1], account.password);
    assert.equal(p.calls[0][2], ['USER', 'MERCHANT', 'ADMIN', 'RIDER'][account.role]);
    assert.equal(p.state.success, 1);
    assert.equal(p.instance.password, '');
    assert.equal(p.instance.submitting, false);
  }
  const wrongRole = page(get, async () => ({ role: 2 }));
  await wrongRole.instance.quickLogin(0);
  assert.equal(wrongRole.state.success, 0);
  assert.equal(wrongRole.state.logout, 1);
});

test('unconfigured and repeated clicks send no request; errors release the submit guard', async () => {
  const unconfigured = page(() => undefined, async () => assert.fail('must not request'));
  await unconfigured.instance.quickLogin(0);
  assert.equal(unconfigured.calls.length, 0);
  const failed = page(() => accounts[0], async () => { throw new Error('offline'); });
  await failed.instance.quickLogin(0);
  assert.equal(failed.instance.submitting, false);
  assert.ok(failed.instance.errorMsg);
  failed.instance.submitting = true;
  await failed.instance.quickLogin(0);
  assert.equal(failed.calls.length, 1);
});
