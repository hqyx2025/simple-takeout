const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const html = fs.readFileSync(path.join(__dirname, '../entry/src/main/resources/rawfile/amap_map.html'), 'utf8');

// Execute the shipped Web map rather than a copy of its bridge implementation.
function createMap({ delayMoveEnd = false } = {}) {
  const requests = [];
  const nearby = [];
  const centers = [];
  const events = {};
  let center;
  function location(lng, lat) {
    return { getLng: () => lng, getLat: () => lat };
  }
  class Map {
    constructor(id, options) {
      center = location(...options.center);
    }
    on(event, callback) {
      events[event] = callback;
    }
    getCenter() {
      return center;
    }
    setZoomAndCenter(zoom, coordinates) {
      center = location(...coordinates);
      if (!delayMoveEnd) events.moveend();
    }
  }
  class Geocoder {
    constructor(options) {
      this.options = options;
    }
    getAddress(coordinates, callback) {
      requests.push({ coordinates, options: this.options, callback });
    }
  }
  const context = vm.createContext({
    AMap: { Map, Geocoder },
    window: {
      addEventListener() {},
      ohosBridge: {
        onCenterChanged: (...args) => centers.push(args),
        onNearbyResult: (...args) => nearby.push(args)
      }
    },
    document: { getElementById: () => ({ style: {}, textContent: '' }) }
  });
  for (const match of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)) {
    if (!/\bsrc\s*=/.test(match[1])) {
      vm.runInContext(match[2], context, { filename: 'amap_map.html' });
    }
  }
  context.initMap();
  return {
    context, requests, nearby, centers, location,
    finishMove: () => events.moveend(),
    dragTo(lng, lat) {
      center = location(lng, lat);
      events.dragend();
    }
  };
}

test('nearby bridge preserves POI identity, addresses, coordinates and usable distances', () => {
  const map = createMap();
  map.context.moveTo(108.320004, 22.822601);
  assert.equal(map.requests.length, 1);
  assert.equal(map.requests[0].options.extensions, 'all');
  map.requests[0].callback('complete', {
    regeocode: {
      formattedAddress: '广西南宁市兴宁区人民路',
      addressComponent: { district: '兴宁区' },
      pois: [
        { name: '邮政局宿舍', address: '人民路28号', adname: '西乡塘区', location: map.location(108.3205, 22.823), distance: '65' },
        { name: '附近公交站', address: '友爱南路', location: { lng: 108.3201, lat: 22.8227 }, distance: '18.5' },
        { name: '距离未知的地点', district: '青秀区', location: { lng: 108.32, lat: 22.82 }, distance: 'unknown' },
        { name: '没有坐标的地点', address: '不能确认配送位置' }
      ]
    }
  });
  assert.equal(map.nearby.length, 1);
  const [lng, lat, json, success] = map.nearby[0];
  assert.equal(lng, '108.320004');
  assert.equal(lat, '22.822601');
  assert.equal(success, '1');
  const places = JSON.parse(json);
  assert.equal(places.length, 3);
  assert.deepEqual(places.find(place => place.name === '邮政局宿舍'), {
    name: '邮政局宿舍', district: '西乡塘区', address: '人民路28号', lng: 108.3205, lat: 22.823, distance: 65
  });
  assert.deepEqual(places.find(place => place.name === '附近公交站'), {
    name: '附近公交站', district: '兴宁区', address: '友爱南路', lng: 108.3201, lat: 22.8227, distance: 18.5
  });
  assert.equal(places.find(place => place.name === '距离未知的地点').distance, -1);
  assert.equal(map.centers.at(-1)[2], '广西南宁市兴宁区人民路');
});

test('delayed geocoder results cannot replace nearby places after a map drag', () => {
  const map = createMap();
  map.context.moveTo(108.32, 22.82);
  map.dragTo(108.35, 22.85);
  const countBefore = map.nearby.length;
  map.requests[0].callback('complete', { regeocode: { formattedAddress: '过期地址', pois: [] } });
  assert.equal(map.nearby.length, countBefore);
  assert.ok(!map.centers.some(center => center[2] === '过期地址'));
  map.requests[1].callback('complete', { regeocode: { formattedAddress: '新地址', pois: [] } });
  assert.deepEqual(map.nearby.at(-1), ['108.350000', '22.850000', '[]', '1']);
});

test('starting another move invalidates old nearby callbacks before its moveend event', () => {
  const map = createMap({ delayMoveEnd: true });
  map.context.moveTo(108.32, 22.82);
  map.finishMove();
  map.context.moveTo(108.35, 22.85);
  const countBefore = map.nearby.length;
  map.requests[0].callback('complete', { regeocode: { formattedAddress: '过期地址', pois: [] } });
  assert.equal(map.nearby.length, countBefore);
  assert.ok(!map.centers.some(center => center[2] === '过期地址'));
  map.finishMove();
  map.requests[1].callback('complete', { regeocode: { formattedAddress: '新地址', pois: [] } });
  assert.deepEqual(map.nearby.at(-1), ['108.350000', '22.850000', '[]', '1']);
});

test('failed geocoding differs from a successful location with no nearby places', () => {
  const map = createMap();
  map.context.moveTo(108.32, 22.82);
  map.requests[0].callback('error', { info: 'NETWORK_ERROR' });
  assert.deepEqual(map.nearby.at(-1), ['108.320000', '22.820000', '[]', '0']);
  map.context.moveTo(108.35, 22.85);
  map.requests[1].callback('complete', { regeocode: { formattedAddress: '新地址', pois: [] } });
  assert.deepEqual(map.nearby.at(-1), ['108.350000', '22.850000', '[]', '1']);
});
