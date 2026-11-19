const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const ts = require(path.join(process.env.DEVECO_HOME || 'C:/Program Files/Huawei/DevEco Studio', 'tools/ohpm/node_modules/typescript'));
const read = file => fs.readFileSync(path.join(__dirname, '..', file), 'utf8');
function native(options = {}) {
  const source = read('entry/src/main/ets/pages/ProfileEditPage.ets');
  const methods = ['contactValue', 'contactAction', 'handleSave', 'loadContactStatus'].map(name => {
    const start = source.search(new RegExp('^  private (?:async )?' + name + '\\(', 'm'));
    assert.ok(start >= 0, name);
    return source.slice(start, source.indexOf('\n  }', start) + 4);
  }).join('\n');
  const exports = {}, state = { epoch: 1, saves: [], sends: [], verifies: [], feedback: [], loggedOut: 0, back: 0 };
  const code = ts.transpileModule('export class Page {' + methods + '}', { compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS } }).outputText;
  vm.runInNewContext(code, { exports, getAuthSessionEpoch: () => state.epoch,
    fetchContactVerificationApi: async () => ({ phoneAvailable: false, phoneVerified: false, emailVerified: true }),
    sendContactCodeApi: async (...args) => { state.sends.push(args); return options.send ? options.send(...args) : { code: 200 }; },
    verifyCurrentContactApi: async (...args) => { state.verifies.push(args); return { code: 200 }; },
    updateUserProfileRemote: async (...args) => { state.saves.push(args); return options.save ? options.save(...args) : { id: 1 }; },
    getLastApiErrorMessage: () => '验证码错误', logInfo() {}, logout: () => state.loggedOut++,
    promptAction: { showToast: item => state.feedback.push(item.message) }, router: { back: () => state.back++ },
    setInterval: () => 1, clearInterval() {}
  });
  const page = new exports.Page();
  Object.assign(page, { alive: true, loggedIn: true, saving: false, avatarUploading: false, contactBusy: false, contactCooldown: 0,
    contactsLoaded: true, phoneAvailable: false, phoneVerified: false, emailVerified: true,
    username: '新昵称', phone: '13800138000', originalPhone: '13800138000', email: 'a@example.test', originalEmail: 'a@example.test',
    currentPassword: '', phoneCode: '', emailCode: '', contactTimer: -1 });
  return { page, state };
}

test('native nickname edits remain available without SMS or an existing mailbox', async () => {
  const r = native(); r.page.email = ''; r.page.originalEmail = '';
  await r.page.handleSave();
  assert.equal(r.state.saves.length, 1); assert.equal(r.state.loggedOut, 0); assert.equal(r.state.back, 1);
});

test('native phone changes fail closed without SMS; email changes need a code and revoke the local session', async () => {
  const blocked = native(); blocked.page.phone = '13800138001';
  await blocked.page.handleSave(); assert.equal(blocked.state.saves.length, 0); assert.match(blocked.state.feedback[0], /短信验证暂不可用/);
  const r = native(); r.page.email = 'new@example.test'; r.page.currentPassword = 'current-password';
  await r.page.handleSave(); assert.equal(r.state.saves.length, 0);
  r.page.emailCode = '123456'; await r.page.handleSave();
  assert.deepEqual(r.state.saves[0], ['新昵称', '13800138000', 'new@example.test', 'current-password', '', '123456']);
  assert.equal(r.state.loggedOut, 1); assert.equal(r.page.currentPassword, ''); assert.equal(r.page.emailCode, '');
});

test('native verification binds the requested contact and suppresses duplicate sends', async () => {
  let finish; const r = native({ send: () => new Promise(resolve => { finish = resolve; }) });
  r.page.currentPassword = 'current-password'; r.page.email = 'NEW@EXAMPLE.TEST';
  const first = r.page.contactAction('EMAIL', false);
  await r.page.contactAction('EMAIL', false); assert.equal(r.state.sends.length, 1);
  assert.deepEqual(r.state.sends[0], ['EMAIL', 'new@example.test', 'current-password']);
  r.state.epoch++; finish({ code: 200 }); await first;
  assert.equal(r.state.feedback.length, 0); assert.equal(r.page.contactCooldown, 0);
});

test('native original-contact verification preserves the current login', async () => {
  const r = native(); r.page.currentPassword = 'current-password'; r.page.emailCode = '123456'; r.page.emailVerified = false;
  await r.page.contactAction('EMAIL', true);
  assert.equal(r.state.verifies.length, 1); assert.equal(r.page.emailVerified, true); assert.equal(r.state.loggedOut, 0);
});

function web() {
  const source = read('web/app.js'), parsed = ts.createSourceFile('app.js', source, ts.ScriptTarget.Latest, true, ts.ScriptKind.JS);
  const body = parsed.statements[0].expression.expression.expression.body;
  const names = ['updateProfileContacts', 'profileContactAction', 'renderSettings'];
  const selected = body.statements.filter(node => ts.isVariableStatement(node) && names.includes(node.declarationList.declarations[0]?.name?.text))
    .map(node => node.getText(parsed)).join('\n');
  const state = { calls: [], feedback: [], html: '', user: null, current: true }, outputs = {};
  vm.runInNewContext(selected + '\nObject.assign(outputs,{updateProfileContacts,profileContactAction,renderSettings});', {
    outputs, state, console, Date, get: async () => {}, pageHead: text => `<h1>${text}</h1>`, esc: text => String(text ?? ''),
    drawPage: html => { state.html = html; }, document: { querySelector: () => null }, staleRender: Error('stale'),
    asyncContext: () => ({}), isCurrentContext: () => state.current,
    guarded: async (promise, context, connected) => { const result = await promise; if (!state.current || !connected()) throw Error('stale'); return result; },
    send: async (...args) => { state.calls.push(args); }, toast: text => state.feedback.push(text), setTimeout: () => 1
  });
  const section = () => ({ hidden: false, verify: { hidden: false }, querySelector() { return this.verify; } });
  const sections = { phone: section(), email: section() };
  const form = { isConnected: true, dataset: { phone: '13800138000', email: 'a@example.test', phoneAvailable: 'false', phoneVerified: 'false', emailVerified: 'false' },
    elements: Object.fromEntries(Object.entries({ phone: '13800138000', email: 'a@example.test', currentPassword: 'current-password', phoneCode: '', emailCode: '123456' }).map(([key,value]) => [key, { value, focus() {} }])),
    querySelector: selector => sections[selector.includes('phone') ? 'phone' : 'email'] };
  return { ...outputs, state, form, sections, button: { disabled: false, dataset: {}, textContent: '获取验证码' } };
}

test('web contact controls respect SMS availability and distinguish verifying the current value from changing it', async () => {
  const r = web(); r.updateProfileContacts(r.form);
  assert.equal(r.sections.phone.hidden, true); assert.equal(r.sections.email.hidden, false);
  await assert.rejects(r.profileContactAction(r.form, 'PHONE', false, r.button), /短信验证暂不可用/);
  assert.equal(r.state.calls.length, 0);
  r.form.elements.email.value = 'new@example.test'; r.updateProfileContacts(r.form);
  assert.equal(r.sections.email.verify.hidden, true);
  await assert.rejects(r.profileContactAction(r.form, 'EMAIL', true, r.button), /当前联系方式/);
  await r.profileContactAction(r.form, 'EMAIL', false, r.button);
  assert.equal(r.state.calls[0][0], '/api/auth/me/contact-code');
  assert.equal(r.state.calls[0][2].value, 'new@example.test'); assert.equal(r.button.disabled, true);
});

test('web verification confirms the original contact and hides its verification fields', async () => {
  const r = web(); await r.profileContactAction(r.form, 'EMAIL', true, r.button);
  assert.equal(r.state.calls[0][0], '/api/auth/me/verify-contact'); assert.equal(r.state.calls[0][2].code, '123456');
  assert.equal(r.form.dataset.emailVerified, 'true'); assert.equal(r.sections.email.hidden, true);
});

test('web settings keeps nickname editable and explains unavailable SMS', async () => {
  const r = web();
  await r.renderSettings(async url => url.endsWith('/contacts')
    ? { phoneAvailable: false, emailVerified: true, phoneVerified: false }
    : { id: 1, role: 0, username: '昵称', phone: '13800138000', email: 'a@example.test' });
  assert.match(r.state.html, /name="phone"[^>]*readonly/);
  assert.match(r.state.html, /短信验证暂不可用/);
  assert.match(r.state.html, /type="submit">保存资料/);
  assert.doesNotMatch(r.state.html, /name="username"[^>]*readonly/);
  assert.match(r.state.html, /data-form="account-close"/);
});

test('native account closure requires explicit confirmation and never clears another or rejected session', async () => {
  const source = read('entry/src/main/ets/components/account/AccountSecurityTask.ets');
  const methods = ['hasSession', 'clearFields', 'closeAccount'].map(name => {
    const start = source.search(new RegExp('^  private (?:async )?' + name + '\\(', 'm'));
    return source.slice(start, source.indexOf('\n  }', start) + 4);
  }).join('\n');
  for (const scenario of ['unconfirmed', 'rejected', 'changed-session', 'success']) {
    const state = { epoch: 1, calls: 0, logout: 0, routes: 0 }, exports = {};
    const code = ts.transpileModule('export class Page {' + methods + '}', { compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS } }).outputText;
    vm.runInNewContext(code, { exports, getAuthToken: () => 'access', getAuthSessionEpoch: () => state.epoch,
      closeAccountApi: async () => { state.calls++; if (scenario === 'changed-session') state.epoch++; return { code: scenario === 'rejected' ? 409 : 200, message: '余额未结清' }; },
      logout: () => state.logout++, router: { replaceUrl: () => state.routes++ }, promptAction: { showToast() {} }
    });
    const page = new exports.Page(); Object.assign(page, { active: true, loggedIn: true, sessionEpoch: 1, user: { id: 1, role: 0 },
      closureConfirmed: scenario !== 'unconfirmed', closurePassword: 'current-password', closingAccount: false, savingPassword: false, savingPayment: false });
    await page.closeAccount();
    assert.equal(state.calls, scenario === 'unconfirmed' ? 0 : 1);
    assert.equal(state.logout, scenario === 'success' ? 1 : 0, scenario);
    assert.equal(state.routes, scenario === 'success' ? 1 : 0, scenario);
  }
});
