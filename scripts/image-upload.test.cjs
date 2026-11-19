const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME || 'C:/Program Files/Huawei/DevEco Studio', 'tools/ohpm/node_modules/typescript'));
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/components/ImageUpload.ets'), 'utf8');
const methods = source.slice(source.indexOf('class PendingImage'), source.indexOf('  @Builder'))
  .replace('@Component\nexport struct ImageUpload', 'export class ImageUpload').replace(/@(Prop|State)\s+/g, '') + '\n}';
const code = ts.transpileModule(methods, { compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS } }).outputText;
const tick = () => new Promise(resolve => setImmediate(resolve));
function runtime(maxFiles) {
  const exports = {}, requests = [], changes = [], busy = [], state = { epoch: 1, context: 1, active: 0, peak: 0 };
  vm.runInNewContext(code, { exports, getAuthSessionEpoch: () => state.epoch, getApiBaseUrl: () => 'https://example.invalid/takeout',
    getLastApiErrorMessage: () => '上传失败', uploadImageApi: uri => {
      state.peak = Math.max(state.peak, ++state.active);
      return new Promise(resolve => requests.push({ uri, resolve: result => { state.active--; resolve(result); } }));
    } });
  const component = new exports.ImageUpload(); component.maxFiles = maxFiles;
  component.contextVersion = () => state.context;
  component.onChange = images => changes.push(Array.from(images)); component.onBusy = value => busy.push(value);
  return { component, requests, changes, busy, state };
}
test('20 and 50 photo limits accept the boundary, reject the extra selection and upload at most three at once', async () => {
  for (const limit of [20, 50]) {
    const r = runtime(limit);
    r.component.add(Array.from({ length: limit + 1 }, (_, i) => '/file-' + i + '.png'));
    assert.equal(r.component.pending.length, limit); assert.match(r.component.error, new RegExp(String(limit)));
    assert.equal(r.requests.length, 3);
    for (let i = 0; i < limit; i++) {
      r.requests[i].resolve({ url: 'https://cdn.example.invalid/uploads/photo-' + i + '.png' }); await tick();
    }
    assert.equal(r.state.peak, 3); assert.equal(r.component.images.length, limit);
    assert.equal(r.component.pending.length, 0); assert.equal(r.busy.at(-1), false);
  }
});
test('account and form changes discard queued images and late responses', async () => {
  for (const key of ['epoch', 'context']) {
    const r = runtime(50); r.component.add(Array.from({ length: 50 }, (_, i) => '/file-' + i + '.png'));
    r.state[key]++;
    for (const request of r.requests) request.resolve({ url: '/uploads/old.png' });
    await tick(); assert.equal(r.requests.length, 3); assert.equal(r.changes.length, 0);
    assert.equal(r.component.pending.length, 0); assert.equal(r.busy.at(-1), false);
  }
});
test('removing a running upload keeps its slot occupied until completion and cannot resurrect it', async () => {
  const r = runtime(20); r.component.add(['/1.png', '/2.png', '/3.png', '/4.png']);
  const removed = r.component.pending[0].id;
  r.component.pending = r.component.pending.filter(row => row.id !== removed); r.component.startQueued();
  assert.equal(r.requests.length, 3);
  r.requests[0].resolve({ url: '/uploads/deleted.png' }); await tick();
  assert.equal(r.requests.length, 4); assert.equal(r.state.peak, 3); assert.equal(r.component.images.length, 0);
});
test('a failed upload retains the error, starts queued work and leaves successful photos usable', async () => {
  const r = runtime(20); r.component.add(['/1.png', '/2.png', '/3.png', '/4.png']);
  r.requests[0].resolve(null); await tick();
  assert.equal(r.requests.length, 4); assert.equal(r.component.pending[0].error, '上传失败');
  for (let i = 1; i < 4; i++) r.requests[i].resolve({ url: '/uploads/photo-' + i + '.png' });
  await tick(); assert.equal(r.component.images.length, 3); assert.equal(r.busy.at(-1), false);
});
