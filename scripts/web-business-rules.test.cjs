const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
// Reuse the browser fixture without registering the browse suite twice.
const fixture=fs.readFileSync('scripts/web-browse.test.cjs','utf8');
const browser=new Function('require',fixture.slice(0,fixture.indexOf('const cardCount='))+';return browser;')(require);
const tick=()=>new Promise(setImmediate);
const ok=data=>({ok:true,status:200,json:async()=>({code:200,data})});
const asRole=(b,role,page)=>Object.assign(b.state,{role,user:{id:9,role},token:'session-'+role,page});
const cap=(allowedActions,other={})=>({allowedActions,refundRemaining:20,afterSalesDeadline:'2099-01-01 00:00:00',...other});
const clickAction=(action,id)=>({target:{closest:selector=>selector==='[data-action]'?{dataset:{action,id:String(id)}}:null}});

test('present empty malformed or null capabilities deny actions while missing retains legacy buttons',async()=>{
  const b=browser();
  for(const capabilities of [cap([]),{},null,undefined]){
    const order={id:7,status:0,capabilities};
    assert.doesNotMatch(b.orderCard(order),/data-action="(?:pay|alipay-pay|cancel-order)"/);
    b.state.orders=[order];await b.handleAction('cancel-order',7);
    assert.equal(b.calls.length,0);assert.equal(b.confirmMessages.length,0);
  }
  assert.match(b.orderCard({id:7,status:0}),/data-action="pay"/);
  assert.match(b.orderCard({id:7,status:0}),/data-action="cancel-order"/);
});

test('reviewed settled orders may request partial refunds only when the server grants REFUND',async()=>{
  const b=browser();
  const order={id:7,status:4,escrowStatus:1,reviewed:1,payAmount:25,capabilities:cap(['REFUND'])};
  assert.match(b.orderCard(order),/data-action="refund"/);
  assert.doesNotMatch(b.orderCard(order),/data-action="(?:confirm-order|review)"/);
  assert.doesNotMatch(b.orderCard({...order,capabilities:cap([])}),/data-action="refund"/);
  asRole(b,0,'orders');b.state.orders=[order];
  const applying=b.handleAction('refund',7),dialog=b.dialogs.at(-1),form=dialog.form;
  assert.match(dialog.innerHTML,/送达后48小时/);assert.match(dialog.innerHTML,/剩余可退 ¥20.00/);
  form.elements.reasonType.value='QUALITY_ISSUE';form.querySelector('[name="amount"]').value='20.01';
  await form.fire('submit');assert.equal(b.calls.length,0);
  form.querySelector('[name="amount"]').value='2.345';await form.fire('submit');assert.equal(b.calls.length,0);
  form.querySelector('[name="amount"]').value='5.50';await form.fire('submit');await applying;
  const body=JSON.parse(b.calls.find(call=>call.path==='/api/orders/7/refund').init.body);
  assert.equal(body.amount,5.5);assert.deepEqual(body.evidenceImages,[]);
});

test('refund evidence uploads multipart files and replays the exact amount images and request after response loss',async()=>{
  let attempts=0;
  const b=browser('0',{onRequest(path){
    if(path==='/api/upload')return ok({url:'/uploads/proof.png'});
    if(path==='/api/orders/7/refund'&&++attempts===1)throw Error('响应丢失');
  }});
  b.state.orders=[{id:7,status:4,escrowStatus:1,payAmount:25,capabilities:cap(['REFUND'])}];
  const applying=b.handleAction('refund',7),form=b.dialogs.at(-1).form;
  form.elements.reasonType.value='WRONG_ITEM';form.elements.reason.value='缺一份米饭';
  form.querySelector('[name="amount"]').value='5';form.querySelector('[name="evidenceFiles"]').files=[{type:'image/png',name:'proof.png'}];
  await form.fire('submit');
  form.querySelector('[name="amount"]').value='10';form.elements.reason.value='修改内容不会改变待核对请求';
  await form.fire('submit');await applying;
  const uploads=b.calls.filter(call=>call.path==='/api/upload');assert.equal(uploads.length,1);
  assert.equal(uploads[0].init.headers['Content-Type'],undefined);assert.equal(uploads[0].init.body.get('file').name,'proof.png');
  const bodies=b.calls.filter(call=>call.path==='/api/orders/7/refund').map(call=>JSON.parse(call.init.body));
  assert.deepEqual(bodies[0],bodies[1]);assert.equal(bodies[1].amount,5);assert.deepEqual(bodies[1].evidenceImages,['/uploads/proof.png']);
});

test('evidence rejects more than nine files and external upload URLs without submitting a refund',async()=>{
  const b=browser('0',{onRequest(path){if(path==='/api/upload')return ok({url:'https://cdn.example/proof.png'});}});
  b.state.orders=[{id:7,status:4,escrowStatus:0}];
  const applying=b.handleAction('refund',7),form=b.dialogs.at(-1).form;
  form.elements.reasonType.value='QUALITY_ISSUE';
  form.querySelector('[name="evidenceFiles"]').files=Array.from({length:10},()=>({type:'image/png'}));
  await form.fire('submit');assert.equal(b.calls.length,0);assert.match(form.querySelector('[data-refund-error]').textContent,/最多9张/);
  form.querySelector('[name="evidenceFiles"]').files=[{type:'image/png'}];await form.fire('submit');
  assert.equal(b.calls.some(call=>call.path.endsWith('/refund')),false);
  assert.match(form.querySelector('[data-refund-error]').textContent,/有效本地地址/);
  await form.querySelector('[data-refund-cancel]').fire('click');await applying;
});

test('merchant history shows escaped evidence and submits an explanation to the exact after-sales endpoint',async()=>{
  const record={id:71,orderId:7,status:'PENDING',evidenceImages:['/uploads/customer.png','javascript:bad'],merchantResponse:'<旧说明>'};
  const b=browser('0',{onRequest(path){if(path==='/api/merchant/orders/7/refunds')return ok([record]);}});
  asRole(b,1,'merchant-orders');await b.handleAction('refund-history',7);
  const history=b.dialogs.at(-1).querySelector('[data-refund-history]');
  assert.match(history.innerHTML,/提交商家举证/);assert.ok(history.innerHTML.includes('/uploads/customer.png'));
  assert.match(history.innerHTML,/&lt;旧说明&gt;/);assert.doesNotMatch(history.innerHTML,/javascript:/);
  const editing=history.fire('click',clickAction('merchant-evidence',71));await tick();
  const form=b.dialogs.at(-1).form;form.formData={response:'已核对打包凭证'};
  await form.fire('submit');await editing;
  const call=b.calls.find(call=>call.path==='/api/after-sales/71/merchant-evidence');
  assert.deepEqual(JSON.parse(call.init.body),{response:'已核对打包凭证',evidenceImages:[]});
});

test('a recent rejected refund offers one appeal with its own reason and images, then hides repeat and expired appeals',async()=>{
  const record={id:71,orderId:7,status:'REJECTED',amount:5,appealCount:0,processTime:new Date().toISOString(),reason:'原申请',evidenceImages:['/uploads/original.png']};
  const b=browser('0',{refundHistory:[record]});await b.handleAction('refund-history',7);
  const history=b.dialogs.at(-1).querySelector('[data-refund-history]');assert.match(history.innerHTML,/提交一次申诉/);
  const appealing=history.fire('click',clickAction('refund-appeal',71));await tick();
  const form=b.dialogs.at(-1).form;form.formData={reason:'补充实际缺餐情况'};await form.fire('submit');await appealing;
  assert.deepEqual(JSON.parse(b.calls.find(call=>call.path.endsWith('/71/appeal')).init.body),{reason:'补充实际缺餐情况',evidenceImages:[]});
  for(const changed of [{appealCount:1},{processTime:'2000-01-01 00:00:00'}]){
    const other=browser('0',{refundHistory:[{...record,...changed}]});await other.handleAction('refund-history',7);
    assert.doesNotMatch(other.dialogs.at(-1).querySelector('[data-refund-history]').innerHTML,/data-action="refund-appeal"/);
  }
});

test('merchant delivery settings read and save the mode without changing existing orders',async()=>{
  const b=browser('0',{merchantStores:[{id:2,name:'店铺'}],onRequest(path,init){if(path.endsWith('/fulfillment')&&init.method!=='PUT')return ok({mode:'MERCHANT'});}});
  asRole(b,1,'catalog');b.state.activeStoreId=2;await b.renderPage();assert.match(b.element('app').innerHTML,/data-action="merchant-fulfillment"/);
  const editing=b.handleAction('merchant-fulfillment',2);await tick();const dialog=b.dialogs.at(-1);
  assert.match(dialog.innerHTML,/仅影响新订单/);assert.match(dialog.innerHTML,/value="MERCHANT" selected/);
  dialog.form.formData={mode:'RIDER'};await dialog.form.fire('submit');await editing;
  const call=b.calls.find(call=>call.path==='/api/merchant/stores/2/fulfillment'&&call.init.method==='PUT');assert.deepEqual(JSON.parse(call.init.body),{mode:'RIDER'});
});

test('merchant self delivery follows server ready deliver complete actions and cannot bypass rider fulfillment',async()=>{
  const b=browser('0',{confirmResult:true});asRole(b,1,'merchant-orders');
  for(const [flow,action,status] of [['deliver','MERCHANT_DELIVER',2],['complete','MERCHANT_COMPLETE',3]]){
    b.state.merchantOrders=[{id:7,status,readyTime:'已出餐',capabilities:cap([action],{fulfillmentMode:'MERCHANT'})}];
    assert.match(b.orderCard(b.state.merchantOrders[0],'merchant'),new RegExp('data-id="7:'+flow+'"'));
    await b.handleAction('merchant-flow','7:'+flow);
    assert.ok(b.calls.some(call=>call.path==='/api/merchant/orders/7/'+flow));
  }
  b.state.merchantOrders=[{id:8,status:2,capabilities:cap([],{fulfillmentMode:'RIDER'})}];
  await b.handleAction('merchant-flow','8:deliver');assert.equal(b.calls.some(call=>call.path==='/api/merchant/orders/8/deliver'),false);
});

test('all three order roles report delivery issues through their own route with one stable key and retained history',async()=>{
  for(const [role,page,prefix,field] of [[0,'orders','orders','orders'],[1,'merchant-orders','merchant/orders','merchantOrders'],[3,'rider-orders','rider/orders','riderOrders']]){
    let attempts=0;const path='/api/'+prefix+'/7/issues';
    const b=browser('0',{onRequest(url,init){if(url===path){if(init.method==='POST'&&++attempts===1)throw Error('响应丢失');return ok(init.method==='POST'?{id:1}:[{id:1,orderId:7,type:'FOOD_DAMAGED',note:'餐盒漏汤',status:'OPEN'}]);}}});
    asRole(b,role,page);b.state[field]=[{id:7,status:3,capabilities:cap(['REPORT_ISSUE'])}];
    const reporting=b.handleAction('report-issue',7),form=b.dialogs.at(-1).form;form.formData={type:'FOOD_DAMAGED',note:'餐盒漏汤'};
    await form.fire('submit');form.formData.note='修改后仍核对原请求';await form.fire('submit');await reporting;
    const bodies=b.calls.filter(call=>call.path===path&&call.init.method==='POST').map(call=>JSON.parse(call.init.body));
    assert.equal(bodies.length,2);assert.deepEqual(bodies[0],bodies[1]);assert.match(bodies[0].idempotencyKey,/^web-issue-/);
    assert.match(b.dialogs.at(-1).querySelector('[data-issue-history]').innerHTML,/餐盒漏汤/);
  }
});

test('admin issue pages preserve the selected filter and submit each explicit resolution with an audit note',async()=>{
  const b=browser('0',{onRequest(path){if(path.startsWith('/api/admin/delivery-issues?'))return ok({list:[{id:1,orderId:7,type:'NO_RIDER',note:'长时间等待',status:'OPEN'}],total:31,page:Number(new URL(path,'https://example.test').searchParams.get('page')),pageSize:30,hasMore:true});}});
  asRole(b,2,'delivery-issues');await b.renderPage();assert.ok(b.requests.includes('/api/admin/delivery-issues?status=OPEN&page=1&pageSize=30'));
  await b.handleAction('delivery-issue-filter','ALL');await b.handleAction('delivery-issues-page',2);
  assert.ok(b.requests.includes('/api/admin/delivery-issues?status=ALL&page=2&pageSize=30'));
  for(const action of ['REASSIGN','RESUME','CANCEL']){
    const handling=b.handleAction('resolve-issue','1:'+action),form=b.dialogs.at(-1).form;
    form.formData={note:'   '};await form.fire('submit');assert.match(form.querySelector('[data-business-error]').textContent,/请填写/);
    form.formData={note:'平台已联系双方并核实'};await form.fire('submit');await handling;
    const call=b.calls.filter(call=>call.path==='/api/admin/delivery-issues/1/resolve').at(-1);assert.deepEqual(JSON.parse(call.init.body),{action,note:'平台已联系双方并核实'});
    assert.equal(b.state.deliveryIssueFilter,'ALL');assert.equal(b.state.deliveryIssuesPage,2);
  }
});

test('merchant ledger uses server debt totals and bounded pagination and account reset clears new state',async()=>{
  const b=browser('0',{onRequest(path){if(path.startsWith('/api/merchant/after-sales/ledger'))return ok({list:[{refundId:71,orderId:7,merchantAmount:15,walletDeducted:5,debtAmount:10,platformAmount:3,createTime:'今天'}],debtAmount:40,total:21,page:Number(new URL(path,'https://example.test').searchParams.get('page')),pageSize:20,hasMore:false});}});
  asRole(b,1,'after-sales-ledger');await b.renderPage();assert.match(b.element('app').innerHTML,/当前待偿 ¥40.00/);assert.match(b.element('app').innerHTML,/¥10.00/);
  await b.handleAction('ledger-page',2);assert.ok(b.requests.includes('/api/merchant/after-sales/ledger?page=2&pageSize=20'));
  b.state.deliveryIssues=[{id:1}];b.state.riderPool=[{id:7}];b.resetAccountState();
  assert.equal(b.state.ledgerPage,1);assert.equal(b.state.deliveryIssueFilter,'OPEN');assert.equal(b.state.deliveryIssues.length,0);assert.equal(b.state.riderPool.length,0);
});

test('new issue and after-sales dialogs discard delayed requests after an account switch',async()=>{
  let release;
  const b=browser('0',{onRequest(path){if(path==='/api/orders/7/issues')return new Promise(resolve=>{release=resolve;});}});
  const loading=b.handleAction('order-issues',7);await tick();const dialog=b.dialogs.at(-1);
  b.resetAccountState();release(ok([{id:1,note:'旧账号私密说明'}]));await loading;
  assert.equal(dialog.removed,true);assert.doesNotMatch(dialog.querySelector('[data-issue-history]').innerHTML,/旧账号私密说明/);
});

test('checkout and cancellation help describe the final server calculation and responsibility policy',async()=>{
  const b=browser('0',{confirmResult:false});b.state.checkoutStoreId=2;await b.renderCheckout();
  assert.match(b.element('app').innerHTML,/最优折扣→新客立减→优惠券/);assert.match(b.element('app').innerHTML,/本店首次成功支付/);assert.match(b.element('app').innerHTML,/赠品门槛按折扣后商品金额/);
  b.state.orders=[{id:7,status:1,payAmount:20}];await b.handleAction('cancel-order',7);assert.match(b.confirmMessages.at(-1),/用户主动取消不返优惠券/);
});

test('rider pool capabilities gate both rendered grabs and dispatched mutation',async()=>{
  const b=browser('0',{riderPool:[{id:7,status:2,capabilities:cap([])}]});asRole(b,3,'rider-pool');await b.renderPage();
  assert.doesNotMatch(b.element('app').innerHTML,/data-action="rider-grab"/);
  await b.handleAction('rider-grab',7);assert.equal(b.calls.some(call=>call.init.method==='POST'),false);
});

test('unpaid platform cancellation uses the cancel route while paid refunds keep the existing route',async()=>{
  const b=browser('0',{confirmResult:true});asRole(b,2,'admin-orders');
  b.state.adminOrders=[{id:7,status:0,capabilities:cap(['CANCEL'])}];
  assert.match(b.orderCard(b.state.adminOrders[0],'admin'),/data-action="admin-cancel-order"/);
  assert.doesNotMatch(b.orderCard(b.state.adminOrders[0],'admin'),/data-action="admin-refund-order"/);
  await b.handleAction('admin-cancel-order',7);
  assert.ok(b.calls.some(call=>call.path==='/api/admin/orders/7/cancel'&&call.init.method==='PUT'));
});

test('an upload completing after logout never submits a refund for the previous account',async()=>{
  let release;const b=browser('0',{onRequest(path){if(path==='/api/upload')return new Promise(resolve=>{release=resolve;});}});
  b.state.orders=[{id:7,status:4,escrowStatus:0}];const applying=b.handleAction('refund',7),form=b.dialogs.at(-1).form;
  form.elements.reasonType.value='QUALITY_ISSUE';form.querySelector('[name="evidenceFiles"]').files=[{type:'image/png'}];
  const sending=form.fire('submit');await tick();b.resetAccountState();release(ok({url:'/uploads/old.png'}));await sending;await applying;
  assert.equal(b.calls.some(call=>call.path==='/api/orders/7/refund'),false);assert.equal(b.element('notice').textContent,'');
});


test('merchant rejection and acceptance follow their own server actions',async()=>{
  const b=browser();asRole(b,1,'merchant-orders');
  const rejectedOnly={id:7,status:1,capabilities:cap(['MERCHANT_REJECT'])};
  const acceptOnly={id:8,status:1,capabilities:cap(['MERCHANT_ACCEPT'])};
  assert.match(b.orderCard(rejectedOnly,'merchant'),/data-action="merchant-reject"/);
  assert.doesNotMatch(b.orderCard(rejectedOnly,'merchant'),/data-action="merchant-flow"/);
  assert.doesNotMatch(b.orderCard(acceptOnly,'merchant'),/data-action="merchant-reject"/);
  assert.match(b.orderCard(acceptOnly,'merchant'),/data-action="merchant-flow"/);
  b.state.merchantOrders=[acceptOnly];await b.handleAction('merchant-reject',8);
  assert.equal(b.dialogs.length,0);assert.equal(b.calls.length,0);
});

test('mixed-type server action arrays fail closed for valid action names too',async()=>{
  const b=browser(),order={id:7,status:0,capabilities:cap(['PAY',null])};
  assert.doesNotMatch(b.orderCard(order),/data-action="(?:pay|alipay-pay)"/);
  b.state.orders=[order];await b.handleAction('pay',7);assert.equal(b.calls.length,0);
});
