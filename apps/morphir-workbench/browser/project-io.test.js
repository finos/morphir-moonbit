import test from 'node:test';
import assert from 'node:assert/strict';
import { fetchText } from './project-io.js';

test('fetchText reports text, HTTP errors and network errors without throwing', async () => {
  const replies = [];
  globalThis.fetch = async path => path === 'ok' ? { ok: true, status: 200, text: async () => 'body' } : { ok: false, status: 404 };
  await fetchText('ok', r => replies.push(JSON.parse(r)));
  await fetchText('missing', r => replies.push(JSON.parse(r)));
  globalThis.fetch = async () => { throw new Error('offline'); };
  await fetchText('any', r => replies.push(JSON.parse(r)));
  assert.deepEqual(replies[0], { ok: true, text: 'body' });
  assert.equal(replies[1].ok, false);
  assert.match(replies[1].message, /404/);
  assert.match(replies[2].message, /offline/);
});
