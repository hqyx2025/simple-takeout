// Run with node scripts/check-location-state.cjs; uses the TypeScript bundled with DevEco.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(path.join(process.env.DEVECO_HOME || 'C:/Program Files/Huawei/DevEco Studio',
  'tools/ohpm/node_modules/typescript'));
const root = path.resolve(__dirname, '..');
const memory = new Map();
const disk = new Map();
const AppStorage = { get: k => memory.get(k), has: k => memory.has(k), setOrCreate: (k, v) => memory.set(k, v) };
const prefs = { get: async (k, fallback) => disk.get(k) ?? fallback,
  put: async (k, v) => disk.set(k, v), delete: async k => disk.delete(k), flush: async () => {} };
const logger = { logInfo() {}, logWarn() {}, logError() {} };
function loadModule(file, dependencies) {
  const source = fs.readFileSync(path.join(root, file), 'utf8');
  const code = ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020
  } }).outputText;
  const exports = {};
  vm.runInNewContext(code, { exports, require: name => {
    if (!(name in dependencies)) throw new Error('Missing test dependency: ' + name);
    return dependencies[name];
  }, AppStorage, console, $r: value => value, setTimeout, clearTimeout }, { filename: file });
  return exports;
}
async function testAddressRestore() {
  const models = loadModule('entry/src/main/ets/model/Models.ets', {});
  const http = { setAuthToken() {}, getAuthToken: () => memory.get('authToken') };
  const persistence = loadModule('entry/src/main/ets/service/DataPersistence.ets', {
    '@ohos.data.preferences': { default: { getPreferences: async () => prefs } },
    '../model/Models': models, './AppLogger': logger, './HttpClient': http
  });
  const oldAddress = { id: 9, name: '测试收件人', phone: '', address: '旧地址', detail: '', isDefault: true };
  for (const [key, value] of Object.entries({ privacyConsent: true, authToken: 'test-session-a',
    isLoggedIn: true, user: { id: 1 }, addressList: [oldAddress], currentAddress: oldAddress,
    lastLocationPosition: { latitude: 30, longitude: 114 } })) disk.set(key, JSON.stringify(value));
  memory.set('appContext', {});
  await persistence.loadAllData();
  assert.equal(memory.get('currentAddress'), null, 'cold start must not activate a cached delivery address');
  assert.equal(memory.get('addressList').length, 0, 'address list requires server confirmation');
  assert.equal(memory.get('lastLocationPosition'), null, 'previous GPS result is not a fresh fix');

  let response = null;
  const manager = loadModule('entry/src/main/ets/service/AppStorageManager.ets', {
    '../model/Models': models, './DataPersistence': persistence, './AppLogger': logger,
    './HttpClient': http, './ApiService': { fetchAddressesApi: async () => response },
    '../common/Constants': { API_CONFIG: {} }, './LocationService': {}
  });
  assert.equal(await manager.syncAddressesRemote(), false, 'offline address sync must report failure');
  assert.equal(memory.get('currentAddress'), null);
  response = [oldAddress];
  assert.equal(await manager.syncAddressesRemote(), true);
  assert.equal(memory.get('currentAddress').id, 9);
  response = null;
  assert.equal(await manager.syncAddressesRemote(), false);
  assert.equal(memory.get('currentAddress'), null, 'failed refresh must invalidate an earlier address');
  response = [];
  assert.equal(await manager.syncAddressesRemote(), true, 'empty list is a successful response');
  assert.equal(memory.get('currentAddress'), null);
  assert.equal(disk.get('currentAddress'), 'null', 'clearing an address must clear persistent selection');
  let finish;
  response = new Promise(resolve => { finish = resolve; });
  const pending = manager.syncAddressesRemote();
  memory.set('user', { id: 2 });
  memory.set('authToken', 'test-session-b');
  finish([oldAddress]);
  assert.equal(await pending, false);
  assert.equal(memory.get('currentAddress'), null, 'late response from account A must not populate account B');
}
function testMapSelection() {
  const events = {};
  const notices = [];
  const geocodes = [];
  let center = [116.397428, 39.90923];
  const map = { on: (name, callback) => { events[name] = callback; }, resize() {},
    getCenter: () => ({ getLng: () => center[0], getLat: () => center[1] }),
    setCenter() {}, setZoomAndCenter: (_zoom, pos) => { center = pos; events.moveend(); } };
  const context = vm.createContext({ window: { addEventListener() {},
    ohosBridge: { onCenterChanged: (...args) => notices.push(args) } },
    document: { getElementById: () => ({ style: {} }) }, setTimeout,
    AMap: { Map: function () { return map; }, Geocoder: function () {
      this.getAddress = (_pos, callback) => geocodes.push(callback);
    } } });
  const html = fs.readFileSync(path.join(root, 'entry/src/main/resources/rawfile/amap_map.html'), 'utf8');
  for (const match of html.matchAll(/<script>([\s\S]*?)<\/script>/g)) vm.runInContext(match[1], context);
  context.initMap();
  assert.equal(notices.length, 0, 'default map center must not become a selected location');
  context.refreshMap();
  assert.equal(notices.length, 0, 'refresh without a selection must not invent a location');
  context.moveTo(114, 30);
  context.moveTo(115, 31);
  const count = notices.length;
  geocodes[0]('complete', { regeocode: { formattedAddress: 'stale result' } });
  assert.equal(notices.length, count, 'out-of-order reverse geocoding must be ignored');
  geocodes[1]('complete', { regeocode: { formattedAddress: 'latest result' } });
  assert.equal(notices.at(-1)[2], 'latest result');
  center = [116, 32];
  events.dragend();
  assert.equal(notices.at(-1)[3], 'manual', 'manual selection must cancel pending GPS');
}
async function testLocationFailureAndRace() {
  // Exercise the page's actual async method without requiring the ArkUI renderer.
  const source = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/LocationPage.ets'), 'utf8');
  const start = source.indexOf('  private async locateCurrent(');
  const end = source.indexOf('  // 按关键词搜索地点', start);
  const code = ts.transpileModule('class PageProbe { ' + source.slice(start, end) + ' }; exports.PageProbe = PageProbe;',
    { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
  const exports = {};
  let gps = Promise.reject(new Error('permission denied'));
  let resolveAddress;
  let reverse = Promise.resolve('address');
  vm.runInNewContext(code, { exports, getCurrentPosition: () => gps,
    reverseGeocodePosition: () => reverse, logInfo() {} });
  const page = new exports.PageProbe();
  Object.assign(page, { locationRequestId: 0, getUIContext: () => ({ getHostContext: () => ({}) }) });
  await page.locateCurrent();
  assert.equal(page.isLocating, false, 'permission failure must stop spinner and expose retry');
  assert.equal(page.currentPosition, null);
  gps = Promise.resolve({ latitude: 30, longitude: 114 });
  reverse = new Promise(resolve => { resolveAddress = resolve; });
  const pending = page.locateCurrent();
  await Promise.resolve();
  page.locationRequestId++;
  page.currentPosition = { latitude: 31, longitude: 115 };
  page.currentAddressText = 'manual choice';
  resolveAddress('old GPS address');
  await pending;
  assert.equal(page.currentAddressText, 'manual choice', 'slow GPS address must not overwrite manual choice');
}
(async () => {
  let failures = 0;
  for (const test of [testAddressRestore, testMapSelection, testLocationFailureAndRace]) {
    try { await test(); console.log('PASS ' + test.name); }
    catch (error) { failures++; console.error('FAIL ' + test.name + ': ' + error.message); }
  }
  process.exitCode = failures ? 1 : 0;
})();
