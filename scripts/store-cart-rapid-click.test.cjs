const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('C:/Program Files/Huawei/DevEco Studio/tools/ohpm/node_modules/typescript');

// Exercise the actual store-detail click handlers with an animation that never finishes.
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/Index.ets'), 'utf8');
const methods = source.slice(source.indexOf('  private enqueueCartOperation('),
  source.indexOf('  // 该菜品是否是多规格菜品'));
const compiled = ts.transpileModule(`class StoreClicks { ${methods} } exports.StoreClicks = StoreClicks;`, {
  compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
}).outputText;
const moduleExports = {};
const calls = [], responses = [], animations = [], messages = [];
let session = 'session-a';
vm.runInNewContext(compiled, {
  exports: moduleExports,
  AppStorage: { get: () => session }, isLoggedIn: () => true,
  AppMotion: { duration: value => value }, Curve: { EaseOut: 0 },
  promptAction: { showToast: value => messages.push(value.message) },
  getLastRemoteErrorMessage: () => '',
  addCartItemRemote: item => {
    calls.push(item);
    return new Promise(resolve => responses.push(resolve));
  }
});
const flush = async () => { for (let i = 0; i < 12; i++) await Promise.resolve(); };
const page = new moduleExports.StoreClicks();
Object.assign(page, {
  active: true, storeId: 3, storeName: 'Test store', cartOperationQueue: Promise.resolve(),
  cartAnimator: { play: id => { animations.push(id); return new Promise(() => {}); } },
  getUIContext: () => ({ animateTo: (_options, change) => change() })
});
const goods = { id: 10, name: 'Test goods', stock: 100 };
(async () => {
  page.addGoodsToCart(goods);
  page.addGoodsToCart(goods);
  page.addGoodsToCart(goods);
  await flush();
  assert.equal(calls.length, 1, 'the first request must start before animation completes');
  responses.shift()(true); await flush();
  assert.equal(calls.length, 2, 'the second click must not wait for animation');
  responses.shift()(false); await flush();
  assert.equal(calls.length, 3, 'a failed request must not discard the next click');
  responses.shift()(true); await flush();
  assert.equal(calls.reduce((sum, item) => sum + item.quantity, 0), 3, 'each accepted click adds exactly one');
  // The animation overlay skips new particles at its cap; this must never skip cart writes.
  page.cartAnimator.play = () => Promise.resolve(false);
  for (let i = 0; i < 21; i++) page.addGoodsToCart(goods);
  await flush();
  for (let i = 0; i < 21; i++) {
    assert.equal(calls.length, 4 + i, 'skipped animation still submits every queued click');
    responses.shift()(true); await flush();
  }
  page.addGoodsToCart(goods); session = 'session-b'; await flush();
  assert.equal(calls.length, 24, 'queued work must not cross login sessions');
  console.log('PASS: rapid clicks run without animation waits, preserve ordering and quantity, recover after failure, survive skipped animations, and isolate sessions');
})().catch(error => { console.error(error); process.exitCode = 1; });
