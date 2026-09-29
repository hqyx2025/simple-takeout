const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(path.join(process.env.DEVECO_HOME || 'C:/Program Files/Huawei/DevEco Studio',
  'tools/ohpm/node_modules/typescript'));
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/Index.ets'), 'utf8');
const start = source.indexOf('  private enqueueCartOperation(');
const end = source.indexOf('  // 该菜品是否是多规格菜品', start);
const code = ts.transpileModule('class Probe {' + source.slice(start, end) + '} exports.Probe = Probe;',
  { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
const calls = [];
const exportsObject = {};
vm.runInNewContext(code, { exports: exportsObject, isLoggedIn: () => true,
  AppStorage: { get: () => 'session' }, promptAction: { showToast() {} },
  addCartItemRemote: async item => { calls.push(item); return true; },
  AppMotion: { duration: n => n }, Curve: { EaseOut: 0 } });
function page() {
  const instance = new exportsObject.Probe();
  let land;
  Object.assign(instance, { active: true, storeId: 1, storeName: 'test', cartOperationQueue: Promise.resolve(),
    cartAnimator: { play: () => new Promise(resolve => { land = resolve; }) },
    getUIContext: () => ({ animateTo: (_options, update) => update() }) });
  return { instance, land: value => land(value) };
}
(async () => {
  const goods = { id: 42, stock: 10, specs: [] };
  const first = page();
  first.instance.addGoodsToCart(goods);
  await Promise.resolve();
  assert.equal(calls.length, 0, 'cart must not update before landing');
  first.land(true);
  await first.instance.cartOperationQueue;
  assert.equal(calls.length, 1);
  assert.equal(calls[0].quantity, 1, 'one completed animation adds exactly one item');
  const left = page();
  left.instance.addGoodsToCart(goods);
  await Promise.resolve();
  left.instance.active = false;
  left.land(true);
  await left.instance.cartOperationQueue;
  assert.equal(calls.length, 1, 'leaving during flight cancels add');
  const canceled = page();
  canceled.instance.addGoodsToCart(goods);
  await Promise.resolve();
  canceled.land(false);
  await canceled.instance.cartOperationQueue;
  assert.equal(calls.length, 1, 'canceled flight does not mutate cart');
  console.log('PASS: landing order, quantity, navigation cancellation');
})().catch(error => { console.error(error); process.exitCode = 1; });
