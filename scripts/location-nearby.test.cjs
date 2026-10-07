const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const sdk = process.env.DEVECO_SDK_HOME || 'C:/Program Files/Huawei/DevEco Studio/sdk';
const ts = require(path.join(sdk, 'default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js'));
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/service/LocationService.ets'), 'utf8');
const code = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS } }).outputText;
const center = { longitude: 108.32, latitude: 22.82 };

// Exercise the shipped service with deterministic provider responses, without native/device dependencies.
function service(response) {
  const urls = [];
  const exports = {};
  const requireStub = name => {
    if (name === '@ohos/axios') return { default: { async get(url) {
      urls.push(url);
      return { data: await response(new URL(url)) };
    } } };
    if (name.endsWith('/Constants')) return { AMAP_CONFIG: { MAP_JS_KEY: 'test-key', TIMEOUT: 1000 } };
    if (name.endsWith('/AppLogger')) return { logInfo() {}, logWarn() {}, logError() {} };
    if (name.startsWith('@kit.')) return {};
    throw new Error(`Unexpected dependency: ${name}`);
  };
  vm.runInNewContext(code, { exports, require: requireStub }, { filename: 'LocationService.ets' });
  return { search: exports.searchNearbyAddress, urls };
}

function poi(index, extra = {}) {
  return { name: `地点 ${index}`, address: `人民路 ${index} 号`, adname: '兴宁区',
    location: `${108.32 + index / 100000},22.82`, distance: `${index}`, ...extra };
}

test('a full nearest page exposes more results and requests the next provider page', async () => {
  const api = service(url => {
    assert.equal(url.searchParams.get('radius'), '1000');
    const size = Number(url.searchParams.get('offset'));
    const page = Number(url.searchParams.get('page'));
    assert.ok(size > 0);
    return { status: '1', count: `${size * 3}`, pois: Array.from({ length: size }, (_, i) => poi((page - 1) * size + i + 1)) };
  });
  const first = await api.search(center);
  const size = Number(new URL(api.urls[0]).searchParams.get('offset'));
  assert.equal(first.places.length, size);
  assert.equal(first.hasMore, true);
  const next = await api.search(center, 2);
  assert.equal(new URL(api.urls[1]).searchParams.get('page'), '2');
  assert.equal(next.places[0].name, `地点 ${size + 1}`);
  assert.equal(next.hasMore, true);
});

test('pagination stops at the provider total rather than at the first nearby batch', async () => {
  const api = service(url => {
    const size = Number(url.searchParams.get('offset'));
    return { status: '1', count: `${size * 2 + 3}`, pois: [poi(size * 2 + 1), poi(size * 2 + 2), poi(size * 2 + 3)] };
  });
  const last = await api.search(center, 3);
  assert.equal(new URL(api.urls[0]).searchParams.get('page'), '3');
  assert.equal(last.places.length, 3);
  assert.equal(last.hasMore, false);
});

test('an empty provider page ends pagination even when its reported total is larger', async () => {
  const result = await service(() => ({ status: '1', count: '600', pois: [] })).search(center, 5);
  assert.equal(result.places.length, 0);
  assert.equal(result.hasMore, false);
});

test('invalid, duplicate and outside-radius POIs are filtered without losing usable details', async () => {
  const api = service(() => ({ status: '1', count: '8', pois: [
    poi(89), poi(89), poi(90, { location: 'invalid' }), poi(91, { location: '200,22' }),
    poi(92, { location: '0,0' }), poi(93, { name: '   ' }), poi(94, { distance: 'unknown' }), poi(1001)
  ] }));
  const result = await api.search(center);
  assert.equal(result.places.length, 2);
  assert.equal(result.places[0].address, '人民路 89 号');
  assert.equal(result.places[0].district, '兴宁区');
  assert.equal(result.places[0].distance, 89);
  assert.equal(result.places[1].distance, -1);
  assert.equal(result.hasMore, false);
});

test('filtered entries do not hide subsequent provider pages', async () => {
  const api = service(url => {
    const size = Number(url.searchParams.get('offset'));
    return { status: '1', count: `${size * 2}`, pois: Array.from({ length: size }, () => poi(10)) };
  });
  const result = await api.search(center);
  assert.equal(result.places.length, 1);
  assert.equal(result.hasMore, true);
});

test('provider and transport failures reject so the page can offer retry', async () => {
  await assert.rejects(service(() => ({ status: '0', info: 'INVALID_USER_KEY', count: '0', pois: [] })).search(center), /附近地点查询失败/);
  const failure = new Error('connection timed out');
  await assert.rejects(service(() => { throw failure; }).search(center), error => error === failure);
});
