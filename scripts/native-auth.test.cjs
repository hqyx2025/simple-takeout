const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const ts=require(path.join(process.env.DEVECO_HOME||'C:/Program Files/Huawei/DevEco Studio','tools/ohpm/node_modules/typescript'));
const source=fs.readFileSync('entry/src/main/ets/pages/LoginPage.ets','utf8');
const policy={};
vm.runInNewContext(ts.transpileModule(fs.readFileSync('entry/src/main/ets/common/PasswordPolicy.ets','utf8'),
  {compilerOptions:{target:ts.ScriptTarget.ES2020,module:ts.ModuleKind.CommonJS}}).outputText,{exports:policy});
function method(name,sourceText=source){
  const start=sourceText.search(new RegExp('^  (?:private )?(?:async )?'+name+'\\(','m'));
  assert.ok(start>=0,name+' must exist');
  return sourceText.slice(start,sourceText.indexOf('\n  }',start)+4);
}
function page(options={}){
  const pageSource=options.registration?fs.readFileSync('entry/src/main/ets/pages/RegisterPage.ets','utf8'):source;
  const names=options.registration?['submitForm','sendVerificationCode','clearFeedback','showError']:['submitForm','sendVerificationCode','switchLoginMethod','openRegistration','onRegistrationComplete','clearFeedback','showError','loginTypeName'];
  const methods=names.map(name=>method(name,pageSource)).join('\n');
  const result={},calls=[],state={success:0,logout:0,focused:'',back:0,storage:new Map(),routes:[]};
  const code=ts.transpileModule('export class Page {'+methods+'}',{compilerOptions:{target:ts.ScriptTarget.ES2020,module:ts.ModuleKind.CommonJS}}).outputText;
  vm.runInNewContext(code,{
    exports:result,newPasswordError:policy.newPasswordError,UserRole:{CUSTOMER:0,MERCHANT:1,ADMIN:2,RIDER:3},
    loginRemote:async(...args)=>{calls.push({kind:'password',args});return options.login?options.login(...args):{id:1,role:0};},
    loginByEmailRemote:async(...args)=>{calls.push({kind:'email',args});return options.login?options.login(...args):{id:1,role:0};},
    registerRemote:async(...args)=>{calls.push({kind:'register',args});return options.register?options.register(...args):{id:1,role:0};},
    AppStorage:{setOrCreate:(key,value)=>state.storage.set(key,value)},router:{back:()=>state.back++,pushUrl:route=>state.routes.push(route.url)},
    requestEmailCodeApi:async(...args)=>{calls.push({kind:'send-code',args});return options.sendResult||{success:true,message:''};},
    getLastRemoteErrorMessage:()=>options.error||'',logout:async()=>{state.logout++;},
    logInfo(){},logWarn(){},promptAction:{showToast(){}},
    setTimeout:callback=>{callback();return 1;},setInterval:()=>1,clearInterval(){},
  });
  const instance=new result.Page();
  Object.assign(instance,{useEmailLogin:false,selectedRole:0,phone:'13800138000',email:'test@example.com',emailCode:'123456',captchaId:'picture-id',captchaCode:'ABCDE',captchaRefreshVersion:0,password:'abcdef',confirmPassword:'abcdef',username:'测试用户',errorMsg:'',errorField:'',tipMsg:'',submitting:false,sendingCode:false,cooldownSeconds:0,cooldownTimer:-1,pageActive:true,onLoginSuccess(){state.success++;},getUIContext(){return {getFocusController(){return {requestFocus(id){state.focused=id;}};}};}});
  return {instance,calls,state};
}

test('native code login needs no password and enforces the selected role',async()=>{
  const p=page();Object.assign(p.instance,{useEmailLogin:true,password:''});
  await p.instance.submitForm();
  assert.equal(p.calls[0].kind,'email');
  assert.deepEqual(p.calls[0].args,['13800138000','test@example.com','123456','USER']);
  assert.equal(p.state.success,1);assert.equal(p.instance.submitting,false);
  const wrong=page({login:async()=>({id:1,role:2})});wrong.instance.useEmailLogin=true;
  await wrong.instance.submitForm();assert.equal(wrong.state.success,0);assert.equal(wrong.state.logout,1);
  assert.match(wrong.instance.errorMsg,/账号/);
});

test('registration rejects password mismatch and retains phone after success',async()=>{
  const p=page({registration:true});p.instance.confirmPassword='different';
  await p.instance.submitForm();assert.equal(p.calls.length,0);assert.equal(p.instance.errorField,'login-confirm-password');
  p.instance.confirmPassword='abcdef';await p.instance.submitForm();
  assert.equal(p.calls[0].kind,'register');assert.equal(p.state.back,1);
  assert.equal(p.state.storage.get('registrationCompletedPhone'),'13800138000');
  assert.equal(p.instance.phone,'13800138000');assert.equal(p.instance.password,'');assert.equal(p.instance.confirmPassword,'');
  const login=page();login.instance.registeredPhone=p.state.storage.get('registrationCompletedPhone');login.instance.onRegistrationComplete();
  assert.equal(login.instance.phone,'13800138000');assert.equal(login.instance.registeredPhone,'');
  assert.match(login.instance.tipMsg,/注册成功.*输入密码/);
});

test('registration opens a dedicated route and clears credentials before leaving login',()=>{
  const p=page();p.instance.openRegistration();
  assert.deepEqual(p.state.routes,['pages/RegisterPage']);
  assert.equal(p.state.storage.get('registrationPhone'),'13800138000');
  assert.equal(p.instance.password,'');assert.equal(p.instance.emailCode,'');assert.equal(p.instance.captchaId,'');
});

test('leaving registration ignores a delayed response and does not navigate back again',async()=>{
  let finish;const p=page({registration:true,register:()=>new Promise(resolve=>{finish=resolve;})});
  const submitting=p.instance.submitForm();p.instance.pageActive=false;finish({id:1,role:0});await submitting;
  assert.equal(p.state.back,0);assert.equal(p.state.storage.size,0);assert.equal(p.instance.submitting,false);
});

test('both verification flows require the picture answer and use distinct email purposes',async()=>{
  for(const registration of [false,true]){
    const p=page({registration});Object.assign(p.instance,{useEmailLogin:!registration,captchaCode:''});
    await p.instance.sendVerificationCode();assert.equal(p.calls.length,0);assert.match(p.instance.errorMsg,/校对码/);
    p.instance.captchaCode='ABCDE';await p.instance.sendVerificationCode();
    assert.equal(p.calls[0].kind,'send-code');assert.equal(p.calls[0].args[2],registration?'register':'signin');
    assert.equal(p.calls[0].args[4],'picture-id');assert.equal(p.calls[0].args[5],'ABCDE');
    assert.equal(p.instance.cooldownSeconds,60);assert.equal(p.instance.captchaRefreshVersion,0);
    assert.equal(p.instance.captchaCode,'ABCDE','sending must retain the typed picture answer');
    assert.equal(p.instance.captchaId,'','a consumed picture must never be reused');
    await p.instance.sendVerificationCode();assert.equal(p.calls.length,1);
  }
});

test('failed code requests preserve the picture answer and require an explicit picture refresh before retry',async()=>{
  const p=page({sendResult:{success:false,message:'校对码不正确或已过期'}});
  p.instance.useEmailLogin=true;
  await p.instance.sendVerificationCode();
  assert.equal(p.instance.captchaCode,'ABCDE');assert.equal(p.instance.captchaRefreshVersion,0);
  assert.equal(p.instance.captchaId,'');
  await p.instance.sendVerificationCode();
  assert.equal(p.calls.length,1);assert.match(p.instance.errorMsg,/点击图片更换/);
});

test('server failures stay in the form and switching methods clears secrets but keeps identity',async()=>{
  const p=page({login:async()=>undefined,error:'验证码不正确或已过期'});
  p.instance.useEmailLogin=true;await p.instance.submitForm();
  assert.match(p.instance.errorMsg,/验证码不正确/);assert.equal(p.instance.errorField,'login-email-code');
  p.instance.switchLoginMethod(false);
  assert.equal(p.instance.phone,'13800138000');assert.equal(p.instance.email,'test@example.com');
  assert.equal(p.instance.password,'');assert.equal(p.instance.emailCode,'');assert.equal(p.instance.errorMsg,'');
});

test('pending authentication rejects duplicate submit and releases busy state after exceptions',async()=>{
  let finish;const p=page({login:()=>new Promise(resolve=>{finish=resolve;})});
  const first=p.instance.submitForm();await p.instance.submitForm();assert.equal(p.calls.length,1);finish({id:1,role:0});await first;
  const failed=page({login:async()=>{throw Error('offline');}});await failed.instance.submitForm();
  assert.equal(failed.instance.submitting,false);assert.ok(failed.instance.errorMsg);
});

test('both native login APIs persist the same secure session and leave failures to the form',async()=>{
  const apiSource=fs.readFileSync('entry/src/main/ets/service/api/AuthApi.ets','utf8');
  const start=apiSource.indexOf('export async function apiLogin('),end=apiSource.indexOf('\n/**',start);
  const code=ts.transpileModule(apiSource.slice(start,end),{compilerOptions:{target:ts.ScriptTarget.ES2020,module:ts.ModuleKind.CommonJS}}).outputText;
  const result={},calls=[],saved=[];let response={code:200,data:{token:'access',refreshToken:'refresh',user:{id:1,role:0}}};
  vm.runInNewContext(code,{exports:result,API_CONFIG:{ENDPOINTS:{login:'/api/auth/login'}},
    post:async(...args)=>{calls.push(args);return response;},setAuthTokens:(...args)=>saved.push(args),saveAuthTokens:async(...args)=>saved.push(args),toUser:user=>user,logInfo(){},logWarn(){}});
  await result.apiLogin('13800138000','password','USER');await result.apiLoginByEmail('13800138000','test@example.com','123456','USER');
  assert.equal(calls[0][0],'/api/auth/login');assert.equal(calls[1][0],'/api/auth/login/email');
  assert.equal(calls[0][2],false);assert.equal(calls[1][2],false);
  assert.deepEqual(saved,[['access','refresh'],['access','refresh'],['access','refresh'],['access','refresh']]);
  response={code:400,data:null,message:'验证码不正确'};
  assert.equal(await result.apiLoginByEmail('13800138000','test@example.com','000000','USER'),null);
  assert.equal(saved.length,4);
});

test('native email login restores server cart and addresses and persists login through the shared completion',async()=>{
  const manager=fs.readFileSync('entry/src/main/ets/service/AppStorageManager.ets','utf8');
  const start=manager.indexOf('async function completeRemoteLogin('),end=manager.indexOf('\n}',start)+2;
  const code=ts.transpileModule(manager.slice(start,end)+'\nexport { completeRemoteLogin };',{compilerOptions:{target:ts.ScriptTarget.ES2020,module:ts.ModuleKind.CommonJS}}).outputText;
  const result={},writes=new Map(),synced=[];
  vm.runInNewContext(code,{exports:result,UserRole:{CUSTOMER:0,MERCHANT:1,ADMIN:2,RIDER:3},getAuthToken:()=> 'access',
    AppStorage:{setOrCreate:(k,v)=>writes.set(k,v)},setStoredUser:user=>writes.set('user',user),registerPushForCurrentSession(){},
    syncAddressesRemote:async()=>synced.push('addresses'),syncCartRemote:async()=>synced.push('cart'),saveAllData:async()=>synced.push('persist'),logInfo(){},logWarn(){}});
  await result.completeRemoteLogin({id:1,role:0});
  assert.equal(writes.get('isLoggedIn'),true);assert.equal(writes.get('authToken'),'access');
  assert.deepEqual(synced,['addresses','cart','persist']);
});

function resetPage(options={}){
  const text=fs.readFileSync('entry/src/main/ets/pages/PasswordResetPage.ets','utf8');
  const names=['validAccount','clearFeedback','showError','submit','clearFields','sendCode'];
  const methods=names.map(name=>{const start=text.search(new RegExp('^  (?:private )?(?:async )?'+name+'\\(','m'));assert.ok(start>=0,name);return text.slice(start,text.indexOf('\n  }',start)+4);}).join('\n');
  const result={},calls=[];
  const code=ts.transpileModule('export class Page {'+methods+'}',{compilerOptions:{target:ts.ScriptTarget.ES2020,module:ts.ModuleKind.CommonJS}}).outputText;
  vm.runInNewContext(code,{exports:result,newPasswordError:policy.newPasswordError,
    requestEmailCodeApi:async(...args)=>{calls.push(args);return options.response||{success:false,message:'校对码不正确或已过期'};},
    resetLoginPasswordApi:async(...args)=>{calls.push(args);return options.response||{success:false,message:'验证码不正确或已过期'};},
    resetPaymentPasswordApi:async(...args)=>{calls.push(args);return {success:true};},
    setInterval:()=>1,clearInterval(){},promptAction:{showToast(){}},getAuthToken:()=>'',logout:async()=>{},router:{back(){calls.push('back');},replaceUrl(){calls.push('replace');}}});
  const instance=new result.Page();Object.assign(instance,{mode:'login',phone:'13800138000',email:'test@example.com',code:'123456',newPassword:'abcdef',confirmPassword:'abcdef',busy:false,sendingCode:false,pageActive:true,loggedIn:false,errorMsg:'',errorField:'',tipMsg:'',captchaId:'picture-id',captchaCode:'ABCDE',captchaRefreshVersion:0,cooldownSeconds:0});
  return {instance,calls};
}

test('password recovery preserves completed inputs on server rejection and blocks invalid confirmations',async()=>{
  const p=resetPage();await p.instance.submit();
  assert.equal(p.calls.length,1);assert.match(p.instance.errorMsg,/验证码/);
  assert.equal(p.instance.newPassword,'abcdef');assert.equal(p.instance.code,'123456');assert.equal(p.instance.busy,false);
  p.instance.confirmPassword='different';await p.instance.submit();
  assert.equal(p.calls.length,1);assert.equal(p.instance.errorField,'password-reset-confirm');
});

test('password recovery clears secrets and returns only after successful reset',async()=>{
  const p=resetPage({response:{success:true}});await p.instance.submit();
  assert.equal(p.instance.newPassword,'');assert.equal(p.instance.confirmPassword,'');assert.equal(p.instance.code,'');
  assert.equal(p.calls.at(-1),'back');assert.equal(p.instance.busy,false);
});

test('password recovery retains the picture answer after a successful or failed email request',async()=>{
  for(const success of [false,true]){
    const p=resetPage({response:{success,message:success?'':'校对码不正确或已过期'}});
    await p.instance.sendCode();
    assert.equal(p.calls[0][4],'picture-id');assert.equal(p.calls[0][5],'ABCDE');
    assert.equal(p.instance.captchaCode,'ABCDE');assert.equal(p.instance.captchaId,'');
    assert.equal(p.instance.captchaRefreshVersion,0);
    if(!success){await p.instance.sendCode();assert.equal(p.calls.length,1);assert.match(p.instance.errorMsg,/点击图片更换/);}
  }
});

test('password strength follows digit, digit-letter and digit-letter-symbol levels',()=>{
  for(const [value,expected] of [['',0],['123456',1],['abcdef',1],['Ab123',1],['Ab1234',2],['Ab1234!',3],['Ab1234<script>',0],['Ab1234 ',0]]) {
    assert.equal(policy.passwordStrength(value),expected,value);
  }
  assert.equal(policy.newPasswordError('Ab1234!@#$%^&*._+-=?'),'');
  for(const value of ["Ab1234'",'Ab1234"','Ab1234;','Ab1234`','Ab1234\\','Ab1234中文','Ab1234\n'])assert.ok(policy.newPasswordError(value));
});
