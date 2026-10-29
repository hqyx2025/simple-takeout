const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const fixture=fs.readFileSync('scripts/web-browse.test.cjs','utf8');
const browser=new Function('require',fixture.slice(0,fixture.indexOf('const cardCount='))+';return browser;')(require);

test('guests stay light and theme choices are restored only for the logged-in account',async()=>{
  const b=browser('0',{darkSystem:true,storage:{'takeout.theme.0.2':'dark'}});
  b.resetAccountState();b.renderShell();
  assert.equal(b.element('documentElement').dataset.theme,'light');
  assert.equal(b.element('themeControl').hidden,true);
  await b.loginWith({phone:'test',password:'test',loginType:'CUSTOMER'});
  assert.equal(b.element('documentElement').dataset.theme,'dark');
  assert.equal(b.element('themeControl').hidden,false);
  assert.equal(b.element('themeSelect').value,'dark');
  b.element('themeSelect').value='system';await b.element('themeSelect').fire('change');
  assert.equal(b.storage.get('takeout.theme.0.2'),'system');
  b.media.matches=false;b.media.listener();
  assert.equal(b.element('documentElement').dataset.theme,'light');
  b.state.user={id:3,role:0};b.renderShell();
  assert.equal(b.element('themeSelect').value,'light');
  b.state.user={id:2,role:1};b.state.role=1;b.renderShell();
  assert.equal(b.element('themeSelect').value,'light');
  b.resetAccountState();b.renderShell();b.media.matches=true;b.media.listener();
  assert.equal(b.element('documentElement').dataset.theme,'light');
  assert.equal(b.storage.get('takeout.theme.0.2'),'system');
});

test('registration blocks mismatched passwords and submits only the validated password',async()=>{
  const b=browser('0',{onRequest(path,init){if(path==='/api/auth/register')return {ok:true,status:200,json:async()=>({code:200,data:{phone:JSON.parse(init.body).phone}})};}});
  b.openAuth('register');
  assert.match(b.element('authForm').innerHTML,/name="confirmPassword"[^>]*required/);
  assert.match(b.element('authForm').innerHTML,/密码需为 6 至 64 位/);
  const form=b.element('authForm');
  form.formData={username:'测试',phone:'13800138000',email:'test@example.com',code:'123456',password:'abcdef',confirmPassword:'abcdeg'};
  await form.fire('submit');
  assert.equal(b.calls.some(call=>call.path==='/api/auth/register'),false);
  assert.match(b.element('authError').textContent,/两次输入的密码不一致/);
  assert.equal(b.element('authError').hidden,false);
  assert.equal(b.element('authConfirmPassword').focused,true);
  b.element('authPassword').value='abcdef';b.element('authConfirmPassword').value='abcdef';
  await form.fire('input');
  assert.equal(b.element('authError').hidden,true);
  assert.equal(b.element('authConfirmPassword').attributes['aria-invalid'],'false');
  form.formData.confirmPassword='abcdef';await form.fire('submit');
  const payload=JSON.parse(b.calls.find(call=>call.path==='/api/auth/register').init.body);
  assert.equal(payload.password,'abcdef');assert.equal('confirmPassword' in payload,false);
  assert.equal(form.dataset.mode,'login');
});

test('registration length checks and server failures remain visible inside the auth dialog',async()=>{
  const b=browser('0',{onRequest(path){if(path==='/api/auth/register')return {ok:false,status:400,json:async()=>({code:400,message:'邮箱验证码不正确，请重新输入'})};}});
  b.openAuth('register');const form=b.element('authForm');
  for(const password of ['abc','a'.repeat(65)]){
    form.formData={password,confirmPassword:password};await form.fire('submit');
    assert.match(b.element('authError').textContent,/6 至 64 位/);
  }
  assert.equal(b.calls.some(call=>call.path==='/api/auth/register'),false);
  form.formData={password:'abcdef',confirmPassword:'abcdef'};await form.fire('submit');
  assert.match(b.element('authError').textContent,/邮箱验证码不正确/);
  assert.equal(b.element('authError').hidden,false);
  assert.equal(form.querySelector('button.primary').disabled,false);
});
