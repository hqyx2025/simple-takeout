const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const fixture=fs.readFileSync('scripts/web-browse.test.cjs','utf8');
const browser=new Function('require',fixture.slice(0,fixture.indexOf('const cardCount='))+';return browser;')(require);
const ok=data=>({ok:true,status:200,json:async()=>({code:200,data})});
const unauthorized=()=>({ok:false,status:401,json:async()=>({code:401,message:'登录已过期'})});
const user={id:2,role:0,username:'测试用户'};

test('reload restores the verified session and server cart quantity; logout clears both',async()=>{
  const first=browser();
  await first.loginWith({phone:'13800138000',password:'password',loginType:'CUSTOMER'});
  const reloaded=browser('0',{session:first.session,cart:[{storeId:1,goodsId:11,quantity:3,price:10}],onRequest(path){
    if(path==='/api/auth/me')return ok(user);
  }});
  reloaded.state.user=null;reloaded.state.token='';
  await reloaded.boot();
  assert.equal(reloaded.state.user?.id,2,'page reload must keep login');
  assert.equal(reloaded.element('topLogin').hidden,true);
  assert.equal(reloaded.element('cartCount').textContent,'3');
  await reloaded.logout();
  assert.equal(reloaded.session.size,0);
  assert.equal(reloaded.element('cartCount').textContent,'0');
});

test('cart badge follows loading, adding, quantity changes and clear from server data',async()=>{
  let cart=[{storeId:1,storeName:'测试店铺',goodsId:11,quantity:2,price:10,goods:{name:'商品'}}];
  const b=browser('0',{cart:()=>cart,confirmResult:true,onRequest(path,init){
    if(path==='/api/cart/items'&&init.method==='POST')cart[0].quantity++;
    if(path.startsWith('/api/cart/items/11')&&init.method==='PUT')cart[0].quantity=JSON.parse(init.body).quantity;
    if(path.startsWith('/api/cart/items?')&&init.method==='DELETE')cart=[];
  }});
  b.state.page='cart';await b.renderPage();
  assert.equal(b.element('cartCount').textContent,'2');
  await b.handleAction('add-cart',11);
  assert.equal(b.element('cartCount').textContent,'3');
  await b.handleAction('cart-inc',11,{dataset:{spec:'0'}});
  assert.equal(b.element('cartCount').textContent,'4');
  await b.handleAction('cart-clear',1);
  assert.equal(b.element('cartCount').textContent,'0');
});

test('registration returns to password login with phone retained and a visible success message',async()=>{
  const b=browser('0',{onRequest(path){if(path==='/api/auth/register')return ok({phone:'13800138000'});}});
  b.openAuth('register');const form=b.element('authForm');
  form.formData={username:'用户',phone:'13800138000',password:'abcdef',confirmPassword:'abcdef'};
  await form.fire('submit');
  assert.equal(form.dataset.mode,'login');
  assert.equal(form.querySelector('[name="phone"]').value,'13800138000');
  assert.equal(form.querySelector('[name="password"]').focused,true);
  assert.match(b.element('authSuccess').textContent,/注册成功.*输入密码/);
  assert.equal(b.element('authSuccess').hidden,false);
});

test('reload rotates an expired access token and rejects a revoked session',async()=>{
  const first=browser();await first.loginWith({phone:'test',password:'password'});
  let refreshed=false;
  const b=browser('0',{session:first.session,onRequest(path){
    if(path==='/api/auth/me')return refreshed?ok(user):unauthorized();
    if(path==='/api/auth/refresh'){refreshed=true;return ok({token:'new-access',refreshToken:'new-refresh'});}
  }});
  b.state.token='';b.state.user=null;await b.boot();
  assert.equal(b.state.user?.id,2);assert.equal(b.state.token,'new-access');
  assert.equal(refreshed,true);
  const revoked=browser('0',{session:b.session,onRequest(path){if(path.startsWith('/api/auth/'))return unauthorized();}});
  revoked.state.token='';revoked.state.user=null;await revoked.boot();
  assert.equal(revoked.state.user,null);assert.equal(revoked.session.size,0);
});

test('temporary connection failures keep saved credentials available for the next reload',async()=>{
  const first=browser();await first.loginWith({phone:'test',password:'password'});
  const saved=first.session.get('takeout.session');
  const offline=browser('0',{session:first.session,onRequest(path){if(path==='/api/auth/me')throw new TypeError('offline');}});
  offline.state.user=null;offline.state.token='';await offline.boot();
  assert.equal(offline.state.user,null);assert.equal(offline.session.get('takeout.session'),saved);
  const online=browser('0',{session:offline.session,onRequest(path){if(path==='/api/auth/me')return ok(user);}});
  online.state.user=null;online.state.token='';await online.boot();
  assert.equal(online.state.user.id,2);
});

test('logout while restoring a session cannot resurrect the previous account',async()=>{
  const first=browser();await first.loginWith({phone:'test',password:'password'});
  let release;
  const b=browser('0',{session:first.session,onRequest(path){if(path==='/api/auth/me')return new Promise(resolve=>{release=()=>resolve(ok(user));});}});
  b.state.user=null;b.state.token='';const restoring=b.boot();
  await b.logout();release();await restoring;
  assert.equal(b.state.user,null);assert.equal(b.state.token,'');assert.equal(b.session.size,0);
});

test('verification login sends a signin email code only after a picture answer is supplied',async()=>{
  const b=browser('0',{onRequest(path){if(path==='/api/auth/login/email')return ok({token:'email-access',refreshToken:'email-refresh',user});}});
  b.openAuth('email');const form=b.element('authForm');
  form.formData={phone:'13800138000',email:'test@example.com',code:'123456',loginType:'CUSTOMER'};
  await b.handleAction('send-code');
  assert.equal(b.calls.some(call=>call.path==='/api/auth/email-code'),false);
  assert.match(b.element('authError').textContent,/请先输入图片/);
  Object.assign(form.formData,{captchaId:'test-captcha',captchaCode:'ABCDE'});
  await b.handleAction('send-code');
  const sent=JSON.parse(b.calls.find(call=>call.path==='/api/auth/email-code').init.body);
  assert.equal(sent.captchaCode,'ABCDE');assert.equal(sent.purpose,'signin');
  await form.fire('submit');
  assert.equal(b.state.token,'email-access');assert.equal(b.state.user.id,2);
  assert.equal(JSON.parse(b.session.get('takeout.session')).token,'email-access');
});
