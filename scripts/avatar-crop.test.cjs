const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME || 'C:/Program Files/Huawei/DevEco Studio', 'tools/ohpm/node_modules/typescript'));
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/common/AvatarCrop.ets'), 'utf8');
const exportsObject = {};
vm.runInNewContext(ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS } }).outputText, { exports: exportsObject });
const { AvatarCrop } = exportsObject;
const near = (actual, expected) => assert.ok(Math.abs(actual - expected) < 0.00001, `${actual} should equal ${expected}`);
test('a square logo can shrink until all four corners fit inside the circular avatar', () => {
  const crop = new AvatarCrop(800, 800); crop.setZoom(0.7);
  const p = crop.placement(300);
  assert.ok(Math.hypot(p.width / 2, p.height / 2) <= 150);
  near(p.width, 210); near(p.height, 210);
});
test('portrait and landscape images start centered and cover the circle without stretching', () => {
  for (const [width, height] of [[1200, 800], [800, 1200]]) {
    const p = new AvatarCrop(width, height).placement(240);
    near(p.width / p.height, width / height); near(Math.min(p.width, p.height), 240);
    near(p.x, 0); near(p.y, 0);
  }
});
test('preview and exported image use identical relative scale and position after drag and zoom', () => {
  const crop = new AvatarCrop(1200, 800); crop.setZoom(2.1); crop.move(0.2, -0.3);
  const preview = crop.placement(280), exported = crop.placement(512);
  for (const key of ['width', 'height', 'x', 'y']) near(preview[key] / 280, exported[key] / 512);
  crop.setZoom(0.7);
  const p = crop.placement(280);
  assert.ok(Math.abs(p.x) <= Math.abs(p.width - 280) / 2 + 0.001);
});
test('extreme gestures clamp to usable bounds, invalid input stays finite and reset restores the original framing', () => {
  const crop = new AvatarCrop(1200, 800); crop.setZoom(1000); assert.equal(crop.zoom, 4);
  crop.move(1000, -1000); const p = crop.placement(240);
  near(p.x, (p.width - 240) / 2); near(p.y, -(p.height - 240) / 2);
  crop.setZoom(-100); assert.equal(crop.zoom, 0.5);
  crop.setZoom(NaN); assert.equal(crop.zoom, 0.5);
  crop.move(NaN, Infinity); near(crop.offsetX, 0); near(crop.offsetY, 0);
  crop.reset(); assert.equal(crop.zoom, 1); near(crop.offsetX, 0); near(crop.offsetY, 0);
});

function profileRuntime() {
  const page = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/ProfileEditPage.ets'), 'utf8');
  const methods = ['changeAvatar', 'uploadAvatar'].map(name => {
    const start = page.indexOf('  private async ' + name + '(');
    return page.slice(start, page.indexOf('\n  }', start) + 4);
  }).join('\n');
  const exported = {}, state = { epoch: 1, picks: ['/selected.png'], uploads: [], saves: [], dialogs: 0 };
  class PhotoViewPicker { async select() { return { photoUris: state.picks }; } }
  vm.runInNewContext(ts.transpileModule('export class Profile {\n' + methods + '\n}', {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
  }).outputText, { exports: exported, getAuthSessionEpoch: () => state.epoch,
    photoAccessHelper: { PhotoViewPicker, PhotoSelectOptions: class {}, PhotoViewMIMETypes: { IMAGE_TYPE: 'image' } },
    uploadImageApi: async path => { state.uploads.push(path); return { url: '/uploads/cropped.jpg' }; },
    updateUserAvatarRemote: async url => { state.saves.push(url); return { avatar: url }; }, promptAction: { showToast() {} }, getLastApiErrorMessage: () => '' });
  const profile = new exported.Profile();
  Object.assign(profile, { alive: true, loggedIn: true, saving: false, avatarUploading: false, avatar: '/uploads/old.jpg', avatarCropDialog: { open: () => state.dialogs++ } });
  return { profile, state };
}
test('selecting a photo opens adjustment and cancellation leaves the original avatar without any upload', async () => {
  const { profile, state } = profileRuntime(); await profile.changeAvatar();
  assert.equal(state.dialogs, 1); assert.equal(profile.selectedAvatarUri, '/selected.png');
  assert.equal(state.uploads.length, 0); assert.equal(state.saves.length, 0); assert.equal(profile.avatar, '/uploads/old.jpg');
});
test('confirmation uploads the cropped file and refuses a crop belonging to an earlier session', async () => {
  const { profile, state } = profileRuntime(); await profile.changeAvatar();
  assert.equal(await profile.uploadAvatar('/cache/cropped.jpg', profile.avatarEpoch), true);
  assert.deepEqual(state.uploads, ['/cache/cropped.jpg']); assert.equal(profile.avatar, '/uploads/cropped.jpg');
  state.epoch++; assert.equal(await profile.uploadAvatar('/cache/old.jpg', profile.avatarEpoch), false);
  assert.equal(state.uploads.length, 1);
});
