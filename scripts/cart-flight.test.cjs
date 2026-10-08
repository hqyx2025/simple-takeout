const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('C:/Program Files/Huawei/DevEco Studio/tools/ohpm/node_modules/typescript');

// Run the actual lifecycle and animation admission logic with a controlled rendering clock.
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/components/CartAddFlight.ets'), 'utf8');
const parent = source.slice(0, source.indexOf('  @Builder')) + '}';
const childStart = source.indexOf('struct CartFlightParticle');
const child = source.slice(childStart, source.indexOf('  build()', childStart)) + '}';
const code = (parent + '\n' + child)
  .replace(/^import .*$/gm, '').replace(/@Component\s*/g, '')
  .replace(/@StorageLink\([^)]*\)\s*@Watch\([^)]*\)\s*/g, '')
  .replace(/@State\s*/g, '').replace(/\bstruct\b/g, 'class');
const result = {}, timers = new Map(), renders = [];
let reduced = false, sequence = 0;
const ui = {
  vp2px: x => x * 3, px2vp: x => x / 3,
  getComponentUtils: () => ({ getRectangleById: id => ({
    size: { width: 96 }, windowOffset: { x: 300, y: id === 'store-cart-target' ? 1500 : 600 }
  }) }),
  animateTo: (options, change) => { change(); renders.push(options.onFinish); }
};
vm.runInNewContext(ts.transpileModule(code + '\nexports.Parent = CartAddFlight; exports.Child = CartFlightParticle;', {
  compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
}).outputText, {
  exports: result, AppMotion: { isReduced: () => reduced, CART_ADD: 480 }, Curve: { EaseIn: 0 },
  setTimeout: fn => { timers.set(++sequence, fn); return sequence; },
  clearTimeout: id => timers.delete(id)
});

(async () => {
  const parent = new result.Parent(); parent.getUIContext = () => ui; parent.aboutToAppear();
  const pending = Array.from({ length: 20 }, () => parent.animator.play('goods-plus-10'));
  assert.equal(parent.flights.length, 20, 'all 20 animations coexist');
  assert.equal(new Set(parent.flights.map(f => f.id)).size, 20, 'each animation is independent');
  assert.equal(await parent.animator.play('goods-plus-10'), false, '21st simultaneous animation is skipped');
  assert.equal(parent.flights.length, 20, 'overflow never cancels active animations');
  const children = parent.flights.map(flight => {
    const child = new result.Child(); child.flight = flight; child.getUIContext = () => ui;
    child.onFinish = () => parent.finish(flight.id); child.aboutToAppear(); return child;
  });
  for (const [id, fn] of timers) { timers.delete(id); fn(); }
  assert.equal(renders.length, 20, 'each child starts its own native animation');
  renders[7](); assert.equal(await pending[7], true);
  assert.equal(parent.flights.length, 19, 'one completion frees only its own slot');
  const replacement = parent.animator.play('goods-plus-11');
  assert.equal(parent.flights.length, 20, 'freed capacity can be reused immediately');
  children.forEach(child => child.aboutToDisappear());
  parent.animator.cancel();
  const settled = await Promise.all(pending);
  assert.equal(settled.filter(Boolean).length, 1, 'cancellation settles all outstanding animations');
  assert.equal(await replacement, false); assert.equal(parent.flights.length, 0);
  renders[0](); assert.equal(parent.flights.length, 0, 'late completion cannot revive canceled animations');
  const motion = parent.animator.play('goods-plus-10');
  parent.reducedMotion = true; parent.onMotionChange(); assert.equal(await motion, true);
  reduced = true; assert.equal(await parent.animator.play('goods-plus-10'), true);
  assert.equal(parent.flights.length, 0, 'reduced motion never allocates particles');
  const child = new result.Child(); child.flight = { startX: 1, startY: 2 }; child.getUIContext = () => ui;
  child.aboutToAppear(); child.aboutToDisappear(); assert.equal(timers.size, 0, 'unmount clears startup timers');
  parent.aboutToDisappear(); assert.equal(await parent.animator.play('goods-plus-10'), false);
  console.log('PASS: 20 independent flights, overflow cap, slot reuse, native completion, cancellation, reduced motion and timer cleanup');
})().catch(error => { console.error(error); process.exitCode = 1; });
