const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME || 'C:/Program Files/Huawei/DevEco Studio',
  'tools/ohpm/node_modules/typescript'));

const source = fs.readFileSync(path.join(__dirname,
  '../entry/src/main/ets/service/CacheService.ets'), 'utf8');
const compiled = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
const entries = new Map([
  ['/sandbox/cache', { directory: true, size: 0 }],
  ['/sandbox/cache/image', { size: 17 }],
  ['/sandbox/cache/nested', { directory: true, size: 0 }],
  ['/sandbox/cache/nested/thumbnail', { size: 5 }],
  ['/sandbox/cache/outside-link', { link: true, target: '/sandbox/files', size: 7 }],
  ['/sandbox/files', { directory: true, size: 0 }],
  ['/sandbox/files/address', { size: 28 }],
  ['/sandbox/files/cart', { size: 12 }]
]);
let failRead = false, failRemove = false;
const fileApi = {
  async listFile(directory) {
    if (failRead) throw new Error('read denied');
    assert.ok(directory === '/sandbox/cache' || directory.startsWith('/sandbox/cache/'),
      'only cache directories may be traversed');
    assert.ok(!entries.get(directory).link, 'symbolic links must never be followed');
    const prefix = directory + '/';
    return [...entries.keys()].filter(name => name.startsWith(prefix) && !name.slice(prefix.length).includes('/'))
      .map(name => name.slice(prefix.length));
  },
  async lstat(name) {
    const entry = entries.get(name);
    assert.ok(entry, 'lookup stays inside known paths');
    return { size: entry.size, isDirectory: () => !!entry.directory, isSymbolicLink: () => !!entry.link };
  },
  async unlink(name) {
    if (failRemove) throw new Error('file busy');
    assert.ok(!entries.get(name).directory);
    entries.delete(name);
  },
  async rmdir(name) {
    assert.ok(![...entries.keys()].some(other => other.startsWith(name + '/')), 'directory emptied first');
    entries.delete(name);
  }
};
const cache = {};
const forbidStorageWrite = () => assert.fail('cache operations must never write AppStorage');
vm.runInNewContext(compiled, {
  exports: cache,
  require: name => {
    assert.equal(name, '@ohos.file.fs');
    return { default: fileApi };
  },
  AppStorage: {
    set: forbidStorageWrite, setOrCreate: forbidStorageWrite,
    delete: forbidStorageWrite, clear: forbidStorageWrite
  }
});

(async () => {
  const context = { cacheDir: '/sandbox/cache' };
  assert.equal(await cache.getCacheSize(context), 29);
  assert.equal(entries.size, 8, 'measurement preserves all data');
  await cache.clearAppCache(context);
  assert.equal(await cache.getCacheSize(context), 0);
  assert.ok(entries.has(context.cacheDir), 'cache root retained');
  assert.equal(entries.get('/sandbox/files/address').size, 28, 'addresses untouched');
  assert.equal(entries.get('/sandbox/files/cart').size, 12, 'cart untouched');
  assert.equal(entries.size, 4, 'links unlinked without following them');
  entries.set('/sandbox/cache/busy', { size: 3 });
  failRemove = true;
  await assert.rejects(cache.clearAppCache(context), /file busy/);
  assert.equal(await cache.getCacheSize(context), 3, 'failed cleanup retains the inaccessible file');
  failRead = true;
  await assert.rejects(cache.getCacheSize(context), /read denied/);
  await assert.rejects(cache.clearAppCache(context), /read denied/);
  await assert.rejects(cache.clearAppCache({ cacheDir: '/' }), /应用缓存目录不可用/);
  await assert.rejects(cache.clearAppCache({ cacheDir: '' }), /应用缓存目录不可用/);
  console.log('PASS: cache byte size, recursive cleanup, business data preserved, links and errors');
})().catch(error => { console.error(error); process.exitCode = 1; });
