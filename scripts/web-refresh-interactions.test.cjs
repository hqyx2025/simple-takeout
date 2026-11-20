const {test,before,after}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const http=require('node:http');
let chromium,browser,server,base;
try{({chromium}=require('playwright'));}catch(error){if(error.code!=='MODULE_NOT_FOUND')throw error;}
const web=path.resolve(__dirname,'../web');
before(async()=>{
 if(!chromium)return;
 server=http.createServer((request,response)=>{
  const name=new URL(request.url,'http://localhost').pathname.slice('/takeout/'.length)||'index.html';
  const file=path.resolve(web,name);
  if(!file.startsWith(web+path.sep)||!fs.existsSync(file)){response.writeHead(404).end();return;}
  const types={'.js':'application/javascript','.css':'text/css','.html':'text/html','.svg':'image/svg+xml'};
  response.setHeader('Content-Type',types[path.extname(file)]||'application/octet-stream');
  let source=fs.readFileSync(file);
  // Expose navigation only in this isolated test server, never in the published app.
  if(name==='app.js')source=Buffer.from(source.toString().replace('  boot();','  window.refreshTest={state,navigate,renderPage}; boot();'));
  response.end(source);
 });
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 base=`http://127.0.0.1:${server.address().port}/takeout/`;
 browser=await chromium.launch({headless:true,executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH});
});
after(async()=>{await browser?.close();if(server)await new Promise(resolve=>server.close(resolve));});
const check=(name,body)=>test(name,{skip:!chromium&&'Playwright is required',timeout:15000},body);
const user={id:2,role:0,username:'隔离用户',phone:'13800138000',email:'test@example.com',balance:100};
const pendingOrder={id:10,storeName:'隔离订单',status:0,payAmount:21,items:[],capabilities:{allowedActions:['PAY','CANCEL']}};
async function setup(options={}){
 const page=await browser.newPage({viewport:options.viewport||{width:1100,height:850},reducedMotion:'reduce'});
 const calls=[],errors=[];
 let orders=[pendingOrder],delayProfile=null,orderReads=0;
 page.on('pageerror',error=>errors.push(error.message));
 await page.addInitScript(()=>sessionStorage.setItem('takeout.session',JSON.stringify({token:'isolated-test',refreshToken:''})));
 await page.route('**/api/**',async route=>{
  const request=route.request(),url=new URL(request.url()),endpoint=url.pathname.slice('/takeout'.length);
  calls.push({path:endpoint,method:request.method(),body:request.postDataJSON()});
  let data=[];
  if(endpoint==='/api/auth/me'){
   if(request.method()==='PUT'&&delayProfile)await delayProfile();
   data=options.user||user;
  }
  if(endpoint==='/api/stores'||endpoint==='/api/search')data=options.stores||[];
  if(endpoint==='/api/addresses')data=options.addresses||[];
  if(endpoint==='/api/rider/profile')data={online:1,status:1,latitude:22,longitude:108};
  if(endpoint==='/api/rider/range/location'&&options.locationError){
   await route.fulfill({status:400,json:{code:400,message:options.locationError}});return;
  }
  if(endpoint==='/api/orders'){orderReads++;data=orders;}
  if(endpoint==='/api/auth/me/contacts')data={phoneAvailable:false,phoneVerified:false,emailVerified:true};
  if(endpoint==='/api/auth/me/close'&&options.closeError){
   await route.fulfill({status:409,contentType:'application/json',body:JSON.stringify({code:409,message:options.closeError})});return;
  }
  if(endpoint==='/api/orders/10/pay'){
   orders=[{...pendingOrder,status:1,capabilities:{allowedActions:[]}}];data=orders[0];
  }
  await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({code:200,data})});
 });
 await page.goto(base);
 await page.waitForFunction(()=>window.refreshTest?.state.user?.id===2&&document.querySelector('#app h1'));
 return {page,calls,errors,setOrders:value=>{orders=value;},holdProfile:fn=>{delayProfile=fn;},orderReadCount:()=>orderReads};
}

check('narrow browse and search show delivery status, restore all cards, and hide the filter after logout',async()=>{
 const stores=[{id:1,name:'三公里餐厅',rating:5,ratingCount:1,latitude:22.03,longitude:108,deliveryRadius:8000},
  {id:2,name:'超出范围餐厅',rating:4,ratingCount:5,latitude:22.09,longitude:108,deliveryRadius:1000}];
 const {page,errors}=await setup({viewport:{width:390,height:844},stores,addresses:[{isDefault:true,latitude:22,longitude:108,mapAddress:'南宁学院北门'}]});
 try{
  for(const mode of ['home','discover']){
   await page.evaluate(mode=>window.refreshTest.navigate(mode),mode);
   if(mode==='discover'){
    await page.locator('#storeSearch').fill('餐厅');
    await Promise.all([
     page.waitForResponse(r=>r.url().includes('/api/search?keyword=')),
     page.locator('#storeSearchForm button[type=submit]').click()
    ]);
   }
   const cards=page.locator('#storeGrid .store-card'), filter=page.getByRole('button',{name:'只看可配送',exact:true});
   await cards.last().waitFor();
   assert.equal(await cards.count(),2);
   assert.match(await cards.first().innerText(),/评价较少[\s\S]*可配送/);
   assert.match(await cards.last().innerText(),/超出配送范围/);
   await filter.click();
   assert.equal(await filter.getAttribute('aria-pressed'),'true');
   assert.equal(await cards.count(),1);
   if(mode==='discover'&&process.env.DELIVERY_UI_EVIDENCE){
    await filter.evaluate(button=>button.scrollIntoView({block:'start'}));
    await page.screenshot({path:path.join(process.env.DELIVERY_UI_EVIDENCE,'browse-mobile.png')});
   }
   await filter.click();
   assert.equal(await cards.count(),2);
  }
  await page.locator('#topLogout').click();
  await page.waitForFunction(()=>!window.refreshTest.state.user&&document.querySelector('#browseDelivery')?.hidden);
  assert.equal(await page.locator('#browseDelivery').isVisible(),false);
  assert.deepEqual(errors,[]);
 }finally{await page.close();}
});

check('rider settings block invalid radius and show partial save feedback',async()=>{
 const {page,calls,errors}=await setup({user:{...user,role:3},locationError:'位置不可用'});
 try{
  await page.evaluate(()=>window.refreshTest.navigate('rider-profile'));
  const form=page.locator('form[data-form=rider-settings]'), radius=form.locator('[name=radiusKm]');
  assert.equal(await radius.inputValue(),'3');
  await radius.fill('5.001');
  await form.getByRole('button',{name:'保存接单范围'}).click();
  assert.equal(calls.filter(c=>c.path.startsWith('/api/rider/range/')).length,0);
  await radius.fill('3.125');
  await form.getByRole('button',{name:'保存接单范围'}).click();
  await page.getByText('半径已保存，位置未更新：位置不可用').waitFor();
  assert.equal(calls.find(c=>c.path.endsWith('/range/radius')).body.radiusMeters,3125);
  if(process.env.DELIVERY_UI_EVIDENCE)await page.screenshot({path:path.join(process.env.DELIVERY_UI_EVIDENCE,'rider-desktop.png')});
  assert.deepEqual(errors,[]);
 }finally{await page.close();}
});
async function advanceAndRefresh(page){
 await page.evaluate(()=>{
  const now=Date.now.bind(Date);Date.now=()=>now()+20000;
  window.dispatchEvent(new Event('focus'));
 });
 // Drain queued promise continuations and timers after the synthetic foreground event.
 await page.evaluate(()=>new Promise(resolve=>setTimeout(resolve,50)));
}

check('saving an unchanged profile unlocks the retained button and permits another save',async()=>{
 const {page,calls,errors}=await setup();
 try{
  await page.evaluate(()=>window.refreshTest.navigate('settings'));
  await page.evaluate(()=>window.savedButton=document.querySelector('form[data-form=profile] button[type=submit]'));
  for(let attempt=1;attempt<=2;attempt++){
   await page.locator('form[data-form=profile] button[type=submit]').click();
   await page.waitForFunction(()=>document.querySelector('#notice').textContent==='资料已保存');
   await page.evaluate(()=>new Promise(resolve=>setTimeout(resolve,30)));
   assert.equal(await page.locator('form[data-form=profile] button[type=submit]').isDisabled(),false);
   assert.equal(calls.filter(c=>c.path==='/api/auth/me'&&c.method==='PUT').length,attempt);
  }
  assert.equal(await page.evaluate(()=>window.savedButton===document.querySelector('form[data-form=profile] button[type=submit]')),true);
  assert.deepEqual(errors,[]);
 }finally{await page.close();}
});

check('contact changes require verification while unavailable SMS still permits nickname edits',async()=>{
 const {page,calls,errors}=await setup();
 try{
  await page.evaluate(()=>window.refreshTest.navigate('settings'));
  const profile=page.locator('form[data-form=profile]');
  assert.equal(await profile.locator('[name=phone]').isEditable(),false);
  await profile.locator('[name=email]').fill('new@example.test');
  await profile.locator('[name=currentPassword]').fill('test-password');
  await profile.locator('button[type=submit]').click();
  await page.waitForFunction(()=>document.querySelector('#notice').textContent.includes('6 位验证码'));
  assert.equal(calls.filter(c=>c.path==='/api/auth/me'&&c.method==='PUT').length,0);
  await profile.locator('[data-action=profile-contact-send][data-id=EMAIL]').click();
  await page.waitForFunction(()=>document.querySelector('#notice').textContent==='验证码已发送');
  assert.equal(calls.find(c=>c.path==='/api/auth/me/contact-code').body.value,'new@example.test');
  await profile.locator('[name=emailCode]').fill('123456');
  await profile.locator('button[type=submit]').click();
  await page.waitForFunction(()=>!window.refreshTest.state.token);
  assert.equal(calls.find(c=>c.path==='/api/auth/me'&&c.method==='PUT').body.emailCode,'123456');
  assert.deepEqual(errors,[]);
 }finally{await page.close();}
});

check('account closure requires confirmation, retains a rejected session and clears a successful session',async()=>{
 for(const closeError of ['余额未结清','']){
  const {page,calls,errors}=await setup({closeError});
  try{
   await page.evaluate(()=>window.refreshTest.navigate('settings'));
   await page.getByText('注销账号',{exact:true}).click();
   const form=page.locator('form[data-form=account-close]');
   await form.locator('[name=currentPassword]').fill('test-password');
   await form.locator('button[type=submit]').click();
   assert.equal(calls.filter(c=>c.path==='/api/auth/me/close').length,0);
   await form.locator('[name=confirmed]').check();await form.locator('button[type=submit]').click();
   await page.waitForFunction(message=>document.querySelector('#notice').textContent===message,closeError||'账号已注销');
   assert.equal(calls.find(c=>c.path==='/api/auth/me/close').body.confirmed,true);
   assert.equal(await page.evaluate(()=>Boolean(window.refreshTest.state.token)),Boolean(closeError));
   assert.deepEqual(errors,[]);
  }finally{await page.close();}
 }
});

check('a foreground refresh cannot invalidate an open payment confirmation',async()=>{
 const {page,calls,errors}=await setup();
 try{
  await page.setViewportSize({width:375,height:812});
  await page.evaluate(()=>window.refreshTest.navigate('orders'));
  await page.locator('[data-action=pay]').click();
  await page.locator('dialog input').fill('123456');
  const reads=calls.filter(c=>c.path==='/api/orders').length;
  await advanceAndRefresh(page);
  assert.equal(calls.filter(c=>c.path==='/api/orders').length,reads,'no refresh while a modal task is open');
  await page.locator('dialog button[value=pay]').click();
  await page.waitForFunction(()=>document.querySelector('#notice').textContent==='余额支付成功');
  assert.equal(calls.filter(c=>c.path==='/api/orders/10/pay').length,1);
  await page.waitForFunction(()=>!document.querySelector('[data-action=pay]'));
  assert.deepEqual(errors,[]);
 }finally{await page.close();}
});

for(const filter of ['', '0'])check(`unchanged order refresh retains button, focus and filter (${filter||'all'})`,async()=>{
 const {page,errors}=await setup();
 try{
  if(filter==='0')await page.evaluate(()=>document.documentElement.dataset.theme='dark');
  await page.evaluate(()=>window.refreshTest.navigate('orders'));
  await page.locator('#orderFilter').selectOption(filter);
  await page.evaluate(()=>{window.savedButton=document.querySelector('[data-action=pay]');window.savedButton.focus();});
  await advanceAndRefresh(page);
  assert.equal(await page.evaluate(()=>window.savedButton===document.querySelector('[data-action=pay]')),true);
  assert.equal(await page.evaluate(()=>document.activeElement===window.savedButton),true);
  assert.equal(await page.locator('#orderFilter').inputValue(),filter);
  assert.deepEqual(errors,[]);
 }finally{await page.close();}
});

check('changed orders still update while the filter controls remain mounted',async()=>{
 const {page,setOrders,errors}=await setup();
 try{
  await page.evaluate(()=>window.refreshTest.navigate('orders'));
  await page.locator('#orderFilter').selectOption('0');
  await page.evaluate(()=>{window.savedFilter=document.querySelector('#orderFilter');window.savedRefresh=document.querySelector('[data-action=refresh]');document.activeElement.blur();});
  setOrders([{...pendingOrder,status:1,capabilities:{allowedActions:[]}}]);
  await advanceAndRefresh(page);
  await page.waitForFunction(()=>document.querySelector('#orderList').textContent.includes('没有匹配订单'));
  assert.equal(await page.evaluate(()=>window.savedFilter===document.querySelector('#orderFilter')&&window.savedRefresh===document.querySelector('[data-action=refresh]')),true);
  await page.locator('#orderFilter').selectOption('1');
  assert.match(await page.locator('#orderList').innerText(),/隔离订单/);
  assert.equal(await page.locator('[data-action=pay]').count(),0);
  assert.deepEqual(errors,[]);
 }finally{await page.close();}
});

check('canceling a modal resumes an expired refresh without creating a payment',async()=>{
 const {page,calls,setOrders,orderReadCount}=await setup();
 try{
  await page.evaluate(()=>window.refreshTest.navigate('orders'));
  await page.locator('[data-action=pay]').click();
  const reads=orderReadCount();setOrders([]);
  await advanceAndRefresh(page);assert.equal(orderReadCount(),reads);
  await page.locator('dialog button[value=cancel]').click();
  await page.waitForFunction(()=>document.querySelector('#orderList').textContent==='暂无订单');
  assert.ok(orderReadCount()>reads);
  assert.equal(calls.filter(c=>c.path==='/api/orders/10/pay').length,0);
 }finally{await page.close();}
});

check('a slow save stays locked against double submit and releases on completion',async()=>{
 const {page,calls,holdProfile}=await setup();let finish;
 try{
  holdProfile(()=>new Promise(resolve=>{finish=resolve;}));
  await page.evaluate(()=>window.refreshTest.navigate('settings'));
  const request=page.waitForRequest(request=>request.method()==='PUT');
  await page.locator('form[data-form=profile] button[type=submit]').click();
  await request;
  assert.equal(await page.locator('form[data-form=profile] button[type=submit]').isDisabled(),true);
  await page.evaluate(()=>document.querySelector('form[data-form=profile]').requestSubmit());
  assert.equal(calls.filter(c=>c.path==='/api/auth/me'&&c.method==='PUT').length,1);
  finish();await page.waitForFunction(()=>!document.querySelector('form[data-form=profile] button[type=submit]').disabled);
 }finally{finish?.();await page.close();}
});

check('a save completing after logout cannot restore the previous account or success feedback',async()=>{
 const {page,holdProfile}=await setup();let finish;
 try{
  holdProfile(()=>new Promise(resolve=>{finish=resolve;}));
  await page.evaluate(()=>window.refreshTest.navigate('settings'));
  const request=page.waitForRequest(request=>request.method()==='PUT');
  await page.locator('form[data-form=profile] button[type=submit]').click();await request;
  await page.locator('#topLogout').click();
  await page.waitForFunction(()=>window.refreshTest.state.user===null);
  finish();await page.evaluate(()=>new Promise(resolve=>setTimeout(resolve,50)));
  assert.equal(await page.evaluate(()=>window.refreshTest.state.user),null);
  assert.equal(await page.locator('#topLogin').isVisible(),true);
  assert.doesNotMatch(await page.locator('#notice').innerText(),/资料已保存/);
 }finally{finish?.();await page.close();}
});
