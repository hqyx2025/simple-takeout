const {test,before,after}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const http=require('node:http');
const ts=require(path.join(process.env.DEVECO_HOME||'C:/Program Files/Huawei/DevEco Studio','tools/ohpm/node_modules/typescript'));
const pageSource=fs.readFileSync(path.join(__dirname,'../entry/src/main/ets/pages/MerchantInventoryPage.ets'),'utf8');
function method(name){
  const start=pageSource.search(new RegExp('^  private (?:async )?'+name+'\\(','m'));
  assert.ok(start>=0,name);
  return pageSource.slice(start,pageSource.indexOf('\n  }',start)+4);
}
const initial={id:10,storeId:1,name:'商品',stock:5,version:3,specs:[{id:20,name:'大份',stock:5,version:7}]};
function mobile(){
  const pending=[],calls=[],clock={epoch:1},storage={user:{id:99,role:1}},exports={};
  const methods=['save','load','applyGoods','updateStock'].map(method).join('\n');
  const code=ts.transpileModule('export class Page {'+methods+'\n}',{compilerOptions:{target:ts.ScriptTarget.ES2020,module:ts.ModuleKind.CommonJS}}).outputText;
  vm.runInNewContext(code,{exports,AppStorage:{get:key=>storage[key]},UserRole:{MERCHANT:1},getAuthSessionEpoch:()=>clock.epoch,
    promptAction:{showToast(){}},changeMerchantStockApi:(...args)=>{calls.push(args);return new Promise(resolve=>pending.push(resolve));},
    fetchMerchantGoodsResultApi:()=>new Promise(resolve=>pending.push(resolve))});
  const page=new exports.Page();
  const sessionExports={};
  const sessionSource=fs.readFileSync(path.join(__dirname,'../entry/src/main/ets/service/PageSession.ets'),'utf8').replace(/^import .*$/gm,'');
  vm.runInNewContext(ts.transpileModule(sessionSource,{compilerOptions:{target:ts.ScriptTarget.ES2020,module:ts.ModuleKind.CommonJS}}).outputText,
    {exports:sessionExports,AppStorage:{get:key=>key==='isLoggedIn'?true:storage[key]},getAuthSessionEpoch:()=>clock.epoch,UserRole:{CUSTOMER:0,MERCHANT:1}});
  const session=new sessionExports.PageSession();session.start(1);

  Object.assign(page,{session,goodsId:10,storeId:1,busy:false,loading:false,failed:false,
    goods:structuredClone(initial),selection:0,amount:'2',currentStock:5,replenish:true});
  return {page,pending,calls,clock,storage};
}
test('mobile replenishment sends the selected SKU version and updates only from the server',async()=>{
  const r=mobile(),work=r.page.save();
  await r.page.save();
  assert.equal(r.calls.length,1);assert.deepEqual(r.calls[0],[10,20,2,7,true]);
  r.pending.shift()({...initial,stock:7,specs:[{...initial.specs[0],stock:7,version:8}]});await work;
  assert.equal(r.page.currentStock,7);assert.equal(r.page.amount,'');assert.equal(r.page.busy,false);
});
test('mobile stale account responses cannot replace inventory or consume pending input',async()=>{
  for(const change of [r=>r.clock.epoch++,r=>r.storage.user={id:100,role:1},r=>r.page.session.pause()]){
    const r=mobile(),work=(r.page.replenish=false,r.page.save());change(r);
    r.pending.shift()({...initial,stock:2});await work;
    assert.equal(r.page.currentStock,5);assert.equal(r.page.amount,'2');
  }
});
test('mobile conflict keeps the original version until an explicit refresh and blocks invalid quantities',async()=>{
  const r=mobile(),work=(r.page.replenish=false,r.page.save());r.pending.shift()(null);await work;
  assert.equal(r.page.goods.specs[0].version,7);assert.equal(r.page.amount,'2');
  for(const value of ['','-1','1.5','10000','0']){r.page.amount=value;await r.page.save();}
  assert.equal(r.calls.length,1);
});

let chromium,browser,server,base;
try{({chromium}=require('playwright'));}catch(e){if(e.code!=='MODULE_NOT_FOUND')throw e;}
before(async()=>{
  if(!chromium)return;
  const web=path.resolve(__dirname,'../web');
  server=http.createServer((req,res)=>{
    const name=new URL(req.url,'http://localhost').pathname.slice('/takeout/'.length)||'index.html';
    const file=path.resolve(web,name);
    if(!file.startsWith(web+path.sep)||!fs.existsSync(file)){res.writeHead(404).end();return;}
    res.setHeader('Content-Type',({'.js':'application/javascript','.css':'text/css','.html':'text/html','.svg':'image/svg+xml'})[path.extname(file)]||'application/octet-stream');
    let data=fs.readFileSync(file);
    if(name==='app.js')data=Buffer.from(data.toString().replace('  boot();','  window.inventoryTest={state,navigate}; boot();'));
    res.end(data);
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  base=`http://127.0.0.1:${server.address().port}/takeout/`;
  browser=await chromium.launch({headless:true,executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH});
});
after(async()=>{await browser?.close();if(server)await new Promise(resolve=>server.close(resolve));});
test('web inventory uses explicit operations and preserves stale-version conflicts for review',
  {skip:!chromium&&'Playwright is required',timeout:20000},async()=>{
    const page=await browser.newPage(),calls=[],errors=[];
    const goods={...initial,price:10,originalPrice:10,categoryId:1,status:1,sales:0,rating:5};
    page.on('pageerror',e=>errors.push(e.message));
    await page.addInitScript(()=>sessionStorage.setItem('takeout.session',JSON.stringify({token:'test',refreshToken:''})));
    await page.route('**/api/**',async route=>{
      const req=route.request(),url=new URL(req.url()),endpoint=url.pathname.replace('/takeout','');
      let data=[],code=200,message='';
      if(endpoint==='/api/auth/me')data={id:99,role:1,username:'商户'};
      if(endpoint==='/api/merchant/stores')data=[{id:1,name:'店铺',ownerId:99,status:1,platformStatus:1,reviewStatus:1}];
      if(endpoint==='/api/merchant/stats')data={};
      if(endpoint==='/api/merchant/stores/1/goods')data=[goods];
      if(endpoint.includes('/goods/10/stock')){
        calls.push({path:endpoint,method:req.method(),body:req.postDataJSON()});
        if(endpoint.endsWith('/replenish'))data=goods;
        else {code=409;message='库存已变化，请刷新后核对再提交';}
      }
      await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({code,data,message})});
    });
    try{
      await page.goto(base);await page.waitForFunction(()=>window.inventoryTest?.state.user?.id===99);
      await page.evaluate(()=>window.inventoryTest.navigate('catalog'));
      await page.locator('[data-action=merchant-goods-edit]').click();
      assert.equal(await page.locator('form[data-form=merchant-goods] input[name=stock]').getAttribute('readonly'),'');
      await page.locator('[data-action=merchant-stock-replenish]').click();
      await page.locator('dialog input[name=amount]').fill('2');
      await page.locator('dialog [data-business-submit]').click();
      await page.waitForFunction(()=>!document.querySelector('dialog'));
      assert.deepEqual(calls[0],{path:'/api/merchant/goods/10/stock/replenish',method:'POST',body:{specId:20,expectedVersion:7,quantity:2}});
      await page.locator('[data-action=merchant-stock-count]').click();
      await page.locator('dialog input[name=amount]').fill('0');
      await page.locator('dialog [data-business-submit]').click();
      await page.locator('[data-business-error]').filter({hasText:'库存已变化'}).waitFor();
      assert.equal(await page.locator('dialog input[name=amount]').inputValue(),'0');
      assert.deepEqual(calls[1].body,{specId:20,expectedVersion:7,stock:0});assert.deepEqual(errors,[]);
    }finally{await page.close();}
  });
