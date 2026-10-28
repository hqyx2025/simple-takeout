const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { randomUUID } = require('node:crypto');
const source = fs.readFileSync(require('node:path').join(__dirname, '../server/takeout-gateway/src/main/resources/static/erp.js'), 'utf8');
const tick = () => new Promise(resolve => setImmediate(resolve));

async function runtime({ storage = new Map(), ownerId = 1, materialCount = 1, supplierCount = 0, purchaseCount = 2 } = {}) {
  const listeners = {}, requests = [], writes = [], toasts = [], reads = [], confirmations = [], prompts = [];
  let connected = true, confirmed = true;
  const sessionStorage = { getItem: key => storage.get(key) ?? null, setItem: (key,value) => storage.set(key,value) };
  const selector = { addEventListener(type, listener) { listeners.store = listener; } };
  let forms = [], detailHtml = '';
  const target = { isConnected: true, scrollIntoView() {},
    set innerHTML(html) {
      detailHtml = html;
      forms.forEach(f => { f.isConnected = false; });
      forms = [...html.matchAll(/data-erp-form="([^"]+)"/g)].map(match => ({
        dataset: { erpForm: match[1] }, isConnected: true, data: {},
        closest() { return this; }, querySelector() { return { textContent: '' }; }
      }));
    },
    get innerHTML() { return detailHtml; }, querySelectorAll() { return forms; }
  };
  const pendingNode = { innerHTML: '' };
  const body = { innerHTML: '', insertAdjacentHTML() {}, querySelectorAll() { return []; }, querySelector() { return target; } };
  const shell = { isConnected: true, querySelector(s) { return s === '[data-erp-body]' ? body : s === '[data-erp-pending]' ? pendingNode : selector; },
    querySelectorAll() { return []; }, addEventListener(type, listener) { listeners[type] = listener; } };
  const root = { innerHTML: '', querySelector() { return shell; } };
  const purchases = Array.from({length:purchaseCount},(_,i) => ({ id:i+1, status: 'CONFIRMED', payable: 10, paid: 0 }));
  const catalog=Array.from({length:materialCount},(_,i)=>({id:i+8,name:'餐盒'+i,unit:'只'})).reverse();
  const window = { sessionStorage, confirm(message) { confirmations.push(message);return confirmed; }, prompt() { return prompts.shift(); } };
  let postFailure = null, postDelay = null;
  const api = async (url, options) => {
    if (options?.method === 'POST') {
      writes.push({ url, options });
      if (postDelay) return postDelay;
      if (postFailure) throw postFailure;
      return { id: 99 };
    }
    reads.push(url);
    if (/\/purchases\/\d+\/lines$/.test(url) || url.includes('receipts?')) return new Promise(resolve => requests.push({ url, resolve }));
    if (url.includes('/purchases?')) { const q=new URL(url,'https://example.test').searchParams;return purchases.filter(p=>!Number(q.get('before')) || p.id<Number(q.get('before'))).slice(0,Number(q.get('limit') || 50)); }
    if (url.includes('/suppliers?')) { const q=new URL(url,'https://example.test').searchParams;return Array.from({length:supplierCount},(_,i)=>({id:supplierCount-i,name:'供应商'+(supplierCount-i),enabled:true})).filter(m=>(!Number(q.get('before')) || m.id<Number(q.get('before'))) && m.name.includes(q.get('q') || '')).slice(0,Number(q.get('limit') || 50)); }
    if (url.includes('/materials?')) { const q=new URL(url,'https://example.test').searchParams;return catalog.filter(m=>(!Number(q.get('before')) || m.id<Number(q.get('before'))) && m.name.includes(q.get('q') || '')).slice(0,Number(q.get('limit') || 50)); }
    return [];
  };
  class FormData { constructor(form) { this.form = form; } [Symbol.iterator]() { return Object.entries(this.form.data)[Symbol.iterator](); } }
  vm.runInNewContext(source, { window, crypto: { randomUUID }, FormData });
  await window.TakeoutErp.mount({ root, api, ownerId, toast: (...args) => toasts.push(args), live: () => connected, stores: [{ id: 10, name: '门店' },{ id: 20, name: '分店' }], role: 1 });
  return { requests, writes, reads, target, body, pendingNode, storage, confirmations, prompts,
    hold: () => {let resolve,reject;postDelay=new Promise((yes,no)=>{resolve=yes;reject=no;});return {resolve,reject};},
    disconnect: () => {connected=false;shell.isConnected=false;}, confirm: value => {confirmed=value;},
    store: async value => {listeners.store({target:{value}});await tick();},
    action: (action,id='',node) => listeners.click({target:{closest:()=>({dataset:{erpAction:action,id:String(id)},closest:()=>node})}}),
    forms: () => forms, toasts, fail: error => { postFailure = error; },
    click: id => listeners.click({ target: { closest: () => ({ dataset: { erpAction: 'detail', id: String(id) } }) } }),
    submit: form => listeners.submit({ target: form, preventDefault() {} }) };
}
function resolvePurchase(r, id, name) {
  r.requests.find(q => q.url.includes(`/purchases/${id}/lines`)).resolve([{ material_id: 8, name, quantity: 2, received: 0, factor: 1, unit_price: 5, unit: '只' }]);
  r.requests.find(q => q.url.includes(`purchaseId=${id}`)).resolve([]);
}

test('reversed purchase-detail responses keep the visible document and submission ID together', async () => {
  const r = await runtime();
  const first = r.click(1), second = r.click(2);
  resolvePurchase(r, 2, 'B单物料'); await second;
  resolvePurchase(r, 1, 'A单物料'); await first;
  assert.match(r.target.innerHTML, /采购单 2/);
  assert.match(r.target.innerHTML, /B单物料/);
  assert.doesNotMatch(r.target.innerHTML, /A单物料/);
  for (const form of [...r.forms()]) {
    assert.equal(form.dataset.purchaseId, '2');
    form.data = form.dataset.erpForm === 'receive' ? { materialId: '8', quantity: '1' } : { amount: '5', reference: 'BANK-2' };
    await r.submit(form);
    assert.equal(JSON.parse(r.writes.at(-1).options.body).id, 2);
  }
});

test('opening another document immediately removes the old actionable forms', async () => {
  const r = await runtime(), first = r.click(1);
  resolvePurchase(r, 1, 'A单物料'); await first;
  const old = r.forms()[0], second = r.click(2);
  assert.equal(old.isConnected, false);
  assert.equal(r.forms().length, 0);
  resolvePurchase(r, 2, 'B单物料'); await second;
});

test('confirmed rejection clears uncertain input so the user can correct the quantity', async () => {
  const r = await runtime(), load = r.click(1);
  resolvePurchase(r, 1, '餐盒'); await load;
  const form = r.forms().find(f => f.dataset.erpForm === 'receive');
  form.data = { materialId: '8', quantity: '1' };
  r.fail(new Error('网络中断')); await r.submit(form);
  const originalKey = r.writes[0].options.headers['Idempotency-Key'];
  assert.ok(form.dataset.uncertain);
  form.data.quantity = '2';
  r.fail(Object.assign(new Error('数量已变化'), { responseReceived: true }));
  await r.submit(form);
  assert.equal(r.writes[1].options.headers['Idempotency-Key'], originalKey);
  assert.equal(JSON.parse(r.writes[1].options.body).lines[0].quantity, '1');
  assert.equal(form.dataset.uncertain, undefined);
  r.fail(null); await r.submit(form); await tick();
  assert.equal(JSON.parse(r.writes[2].options.body).lines[0].quantity, '2');
  assert.notEqual(r.writes[2].options.headers['Idempotency-Key'], originalKey);
});

test('unknown request survives leaving, re-entry and store switching and replays original key and payload only after review', async () => {
  const storage=new Map(), first=await runtime({storage}), load=first.click(1);
  resolvePurchase(first,1,'餐盒');await load;
  const f=first.forms().find(f=>f.dataset.erpForm==='receive');f.data={materialId:'8',quantity:'1'};
  first.fail(new Error('连接中断'));await first.submit(f);
  const original=first.writes[0];first.disconnect();
  const second=await runtime({storage});
  assert.match(second.pendingNode.innerHTML,/待核对的未确认请求/);
  const key=original.options.headers['Idempotency-Key'];
  await second.store('20');assert.doesNotMatch(second.pendingNode.innerHTML,/待核对的未确认请求/);
  assert.ok(storage.get('erp.pending.1.10').includes(key));
  await second.store('10');assert.match(second.pendingNode.innerHTML,/待核对的未确认请求/);
  second.confirm(false);await second.action('retry-pending',key);assert.equal(second.writes.length,0);
  second.confirm(true);await second.action('retry-pending',key);
  assert.equal(second.writes[0].url,original.url);
  assert.equal(second.writes[0].options.body,original.options.body);
  assert.equal(second.writes[0].options.headers['Idempotency-Key'],key);
  assert.equal(JSON.parse(storage.get('erp.pending.1.10')).length,0);
});

test('supplier purchase filter remains on next, previous and refresh until explicitly cleared',async()=>{
  const r=await runtime({purchaseCount:50});await r.action('supplier-purchases',300);
  await r.action('next');await r.action('refresh');await r.action('previous');
  const queries=r.reads.filter(u=>u.includes('/purchases?')).slice(1);
  assert.equal(queries.length,4);queries.forEach(u=>assert.match(u,/supplierId=300/));
  await r.action('clear-supplier');assert.doesNotMatch(r.reads.filter(u=>u.includes('/purchases?')).at(-1),/supplierId/);
});

function picker(records) {
  let html='';const selected={value:'8',selectedOptions:[{textContent:'原已选餐盒'}],options:records.map(r=>({value:String(r.id)})),
    set innerHTML(value){html=value;},get innerHTML(){return html;},insertAdjacentHTML(_where,value){html+=value;}};
  const status={textContent:''},input={value:''};
  return {isConnected:true,dataset:{erpPicker:'materials'},selected,status,input,
    querySelector(s){return s==='select'?selected:s==='[data-erp-search]'?input:status;}};
}
test('picker traverses beyond 100 with bounded server pages and keeps selected material',async()=>{
  const r=await runtime({materialCount:125}),p=picker(Array.from({length:50},(_,i)=>({id:132-i})));
  await r.action('picker-next','',p);assert.match(r.reads.at(-1),/before=83/);assert.equal(p.erpPage.rows.length,50);
  await r.action('picker-next','',p);assert.match(r.reads.at(-1),/before=33/);assert.equal(p.erpPage.rows.length,25);
  assert.equal(p.selected.value,'8');assert.match(p.selected.innerHTML,/原已选餐盒|餐盒0/);
  p.input.value='餐盒0';await r.action('picker-search','',p);
  assert.match(r.reads.at(-1),/q=%E9%A4%90%E7%9B%920/);assert.equal(p.erpPage.rows.length,1);
  assert.equal(p.erpPage.before,0);assert.equal(p.erpPage.history.length,0);
});

test('payment correction, reversal and actual refund post append-only commands with audit reason',async()=>{
  const r=await runtime();
  r.prompts.push('凭证录错','BANK-CORRECT');await r.action('payment-correct',9);
  assert.equal(JSON.parse(r.writes.at(-1).options.body).reference,'BANK-CORRECT');
  assert.match(r.writes.at(-1).url,/payment-correct$/);
  r.prompts.push('登记有误');await r.action('reverse-payment',9);
  assert.match(r.writes.at(-1).url,/reverse-payment$/);
  r.prompts.push('供应商退款到账','REFUND-BANK','3.20');await r.action('supplier-refund',9);
  const refund=JSON.parse(r.writes.at(-1).options.body);
  assert.deepEqual(refund,{id:9,reason:'供应商退款到账',reference:'REFUND-BANK',amount:'3.20'});
  assert.match(r.writes.at(-1).url,/supplier-refund$/);
});

test('storage failure prevents posting a request whose idempotency key cannot survive navigation',async()=>{
  const storage=new Map(),r=await runtime({storage}),load=r.click(1);resolvePurchase(r,1,'餐盒');await load;
  const f=r.forms().find(f=>f.dataset.erpForm==='receive');f.data={materialId:'8',quantity:'1'};
  storage.set=()=>{throw new Error('会话保存失败');};await r.submit(f);
  assert.equal(r.writes.length,0);assert.ok(r.toasts.some(t=>t[0].includes('会话保存失败')));
});

test('late completion from a departed mount never removes newer pending requests in the same store',async()=>{
  const storage=new Map(),first=await runtime({storage}),load=first.click(1);resolvePurchase(first,1,'餐盒');await load;
  const f=first.forms().find(f=>f.dataset.erpForm==='receive');f.data={materialId:'8',quantity:'1'};
  const hold=first.hold(),sending=first.submit(f);await tick();first.disconnect();
  const second=await runtime({storage}),key=first.writes[0].options.headers['Idempotency-Key'];
  await second.action('retry-pending',key);
  second.fail(new Error('中断'));await second.action('submit',2);
  const newer=second.writes.at(-1).options.headers['Idempotency-Key'];
  hold.resolve({id:99});await sending;
  assert.ok(storage.get('erp.pending.1.10').includes(newer));
  assert.ok(!storage.get('erp.pending.1.10').includes(key));
});

test('supplier picker can select a supplier beyond 100 and retains server enabled filter',async()=>{
  const r=await runtime({supplierCount:125}),p=picker(Array.from({length:50},(_,i)=>({id:125-i})));
  p.dataset.erpPicker='suppliers';p.selected.value='1';p.selected.selectedOptions=[{textContent:'供应商1'}];
  await r.action('picker-next','',p);await r.action('picker-next','',p);
  assert.equal(p.erpPage.rows.length,25);assert.match(r.reads.at(-1),/before=26/);
  assert.match(r.reads.at(-1),/enabled=true/);assert.equal(p.selected.value,'1');assert.match(p.selected.innerHTML,/供应商1/);
});

test('pending procurement intent belongs to its original account as well as its store',async()=>{
  const storage=new Map(),first=await runtime({storage,ownerId:1}),load=first.click(1);
  resolvePurchase(first,1,'餐盒');await load;
  const form=first.forms().find(f=>f.dataset.erpForm==='receive');form.data={materialId:'8',quantity:'1'};
  first.fail(new Error('响应未确认'));await first.submit(form);
  const key=first.writes[0].options.headers['Idempotency-Key'];first.disconnect();
  const other=await runtime({storage,ownerId:2});
  assert.doesNotMatch(other.pendingNode.innerHTML,/待核对的未确认请求/);
  assert.ok(storage.get('erp.pending.1.10').includes(key));other.disconnect();
  const original=await runtime({storage,ownerId:1});
  assert.match(original.pendingNode.innerHTML,/待核对的未确认请求/);
  await original.action('retry-pending',key);
  assert.equal(original.writes[0].options.headers['Idempotency-Key'],key);
});

test('corrupted persisted requests fail closed and preserve the original recovery record',async()=>{
  for(const raw of ['{broken', '{}', '[{"store":10,"key":"lost","action":"receive","payload":{}}]']){
    const storage=new Map([['erp.pending.1.10',raw]]);
    await assert.rejects(runtime({storage}),/待确认请求记录/);
    assert.equal(storage.get('erp.pending.1.10'),raw);
  }
});
