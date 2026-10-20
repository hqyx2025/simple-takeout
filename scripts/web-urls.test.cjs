const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const context = vm.createContext({ URL });
vm.runInContext(fs.readFileSync('server/takeout-gateway/src/main/resources/static/urls.js', 'utf8'), context);
const { localPath } = context.TakeoutUrls;

test('API and uploaded resources stay beneath the mounted application path', () => {
  for (const origin of ['https://hqyx.website', 'http://localhost:8087']) {
    for (const prefix of ['/', '/takeout/']) {
      const base = origin + prefix;
      assert.equal(localPath('/api/stores?keyword=a%20b', base), prefix + 'api/stores?keyword=a%20b');
      assert.equal(localPath('/uploads/dish.svg', base), prefix + 'uploads/dish.svg');
      assert.equal(localPath(prefix + 'uploads/dish.svg', base), prefix + 'uploads/dish.svg');
      assert.equal(localPath('https://images.example.com/dish.jpg', base), 'https://images.example.com/dish.jpg');
      assert.equal(localPath('', base), '');
    }
  }
});

test('public entrypoints use domains or relative URLs', () => {
  for (const file of ['README.md', 'entry/src/main/ets/common/Constants.ets', 'server/docker/nginx-domain.conf', 'server/takeout-gateway/src/main/resources/static/app.js']) {
    const source = fs.readFileSync(file, 'utf8');
    for (const match of source.matchAll(/https?:\/\/((?:\d{1,3}\.){3}\d{1,3})/g)) {
      assert.match(match[1], /^(?:127\.|10\.|192\.168\.)/, `${file} contains a public IP URL`);
    }
  }
});
