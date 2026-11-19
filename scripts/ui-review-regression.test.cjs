const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('web/app.js', 'utf8');
const begin = source.indexOf('  const api = async (');
const cache = source.slice(source.indexOf('  const pageData ='), source.indexOf('  let authRequestVersion'));
const code = cache + source.slice(begin, source.indexOf('\n  };', begin) + 5) + '\nglobalThis.callApi = api;';

test('offline reads and writes have actionable copy and retain uncertain write classification without replay', async () => {
  for (const method of ['GET', 'POST']) {
    const calls = [];
    const context = vm.createContext({
      state: { token: 'isolated-test-token' }, FormData: class FormData {}, clearTimeout,
      TakeoutUrls: { localPath: path => '/takeout' + path }, document: { baseURI: 'https://example.test/takeout/' },
      fetch: async (...args) => { calls.push(args); throw new TypeError('Failed to fetch'); }
    });
    vm.runInContext(code, context);
    await assert.rejects(context.callApi('/api/orders', { method, body: method === 'POST' ? '{"idempotencyKey":"same-intent"}' : undefined }), error => {
      assert.match(error.message, /网络请求未完成/);
      assert.equal(error.responseReceived, false);
      return true;
    });
    assert.equal(calls.length, 1);
    assert.equal(calls[0][0], '/takeout/api/orders');
    if (method === 'POST') assert.equal(calls[0][1].body, '{"idempotencyKey":"same-intent"}');
  }
});
