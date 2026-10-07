const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(path.join(process.env.DEVECO_HOME || 'C:/Program Files/Huawei/DevEco Studio',
  'tools/ohpm/node_modules/typescript'));

const source = fs.readFileSync(path.join(__dirname,
  '../entry/src/main/ets/service/AppearanceSettings.ets'), 'utf8').replace(/^import .*$/gm, '');
const storage = new Map(), storageWrites = [];
let disk = new Map(), cached = new Map(), failingFlushes = 0;
const applied = { colorMode: -1, fontScale: 1 };
const application = {
  setColorMode: value => { applied.colorMode = value; },
  setFontSizeScale: value => { applied.fontScale = value; }
};
const context = { getApplicationContext: () => application };
const prefs = {
  get: async (key, fallback) => cached.has(key) ? cached.get(key) : fallback,
  put: async (key, value) => { cached.set(key, value); },
  flush: async () => {
    if (failingFlushes > 0) { failingFlushes--; throw Error('flush failed'); }
    disk = new Map(cached);
  }
};
const settings = {};
vm.runInNewContext(ts.transpileModule(source, { compilerOptions: {
  target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS
} }).outputText, {
  exports: settings,
  ConfigurationConstant: { ColorMode: { COLOR_MODE_DARK: 1, COLOR_MODE_LIGHT: 0, COLOR_MODE_NOT_SET: -1 } },
  preferences: { getPreferences: async (actualContext, name) => {
    assert.equal(actualContext, context); assert.equal(name, 'takeout_appearance'); return prefs;
  } },
  AppStorage: {
    get: key => storage.get(key),
    setOrCreate: (key, value) => { storageWrites.push([key, value]); storage.set(key, value); }
  },
  logWarn() {}
});

async function coldStart(values) {
  if (values !== undefined) disk = new Map(Object.entries(values));
  cached = new Map(disk); storage.clear(); storageWrites.length = 0;
  await settings.loadAppearanceSettings(context);
}
function checkStorage(mode, scale, navigationMode) {
  assert.equal(storage.get('appearanceColorMode'), mode);
  assert.equal(storage.get('appearanceFontScale'), scale);
  assert.equal(storage.get('navigationHandMode'), navigationMode);
}
function checkDisk(mode, scale, navigationMode) {
  assert.equal(disk.get('colorMode'), mode);
  assert.equal(disk.get('fontScale'), scale);
  assert.equal(disk.get('navigationHandMode'), navigationMode);
}

(async () => {
  await coldStart({});
  checkStorage('system', 1, 'auto');
  for (const navigationMode of ['auto', 'left', 'right', 'center']) {
    await coldStart({ colorMode: 'dark', fontScale: 1.15, navigationHandMode: navigationMode });
    checkStorage('dark', 1.15, navigationMode);
  }

  await coldStart({ colorMode: 'sepia', fontScale: 2, navigationHandMode: 'diagonal' });
  checkStorage('system', 1, 'auto');
  await settings.saveAppearanceSettings(context, 'sepia', 2, 'diagonal');
  checkDisk('system', 1, 'auto');

  await settings.saveAppearanceSettings(context, 'dark', 1.15, 'right');
  checkStorage('dark', 1.15, 'right'); checkDisk('dark', 1.15, 'right');
  await coldStart();
  checkStorage('dark', 1.15, 'right');
  await settings.saveAppearanceSettings(context, 'dark', 1.15, 'left');
  checkStorage('dark', 1.15, 'left'); checkDisk('dark', 1.15, 'left');

  const beforeStorage = Array.from(storage), beforeDisk = Array.from(disk);
  storageWrites.length = 0; failingFlushes = 1;
  await assert.rejects(settings.saveAppearanceSettings(context, 'light', 0.9, 'center'), /外观设置保存失败/);
  assert.deepEqual(storageWrites, [], 'failed save must not publish transient settings');
  assert.deepEqual(Array.from(storage), beforeStorage, 'failed save must retain all AppStorage settings');
  assert.deepEqual(Array.from(cached), beforeDisk, 'failed save must roll back the preferences cache');
  assert.deepEqual(Array.from(disk), beforeDisk, 'failed save must retain persisted settings');
  assert.equal(failingFlushes, 0);
  assert.deepEqual(applied, { colorMode: 1, fontScale: 1.15 }, 'failed save must restore application appearance');
  await coldStart();
  checkStorage('dark', 1.15, 'left');

  await settings.saveAppearanceSettings(context, 'system', 1, 'auto');
  checkStorage('system', 1, 'auto'); checkDisk('system', 1, 'auto');
  await coldStart();
  checkStorage('system', 1, 'auto');
  console.log('PASS: default/valid navigation modes, cold restore, normalization, appearance preservation, failed-save rollback and reset');
})().catch(error => { console.error(error); process.exitCode = 1; });
