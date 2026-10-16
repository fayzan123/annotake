// The checkpoint tools' logic: the header check the smoke test applies to each page, the smoke checks against the
// local server, and the burst test's verdict.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import consent from '../../api/_lib/consent.json' with { type: 'json' };
import { CSP, SECURITY_HEADERS } from '../expected.js';
import { createServer } from '../server.mjs';
import { checkHeaders, checks } from '../tools/smoke.mjs';
import { evaluateBurst } from '../tools/burst.mjs';

/** What each smoke check finds against the local server, which mirrors Vercel, by the check's name. */
async function smokeLocally() {
  const server = createServer({ root: fileURLToPath(new URL('../../', import.meta.url)) });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    const results = new Map();
    for (const [name, check] of checks(`http://127.0.0.1:${server.address().port}`)) results.set(name, await check());
    return results;
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
}

/** The result of the one check whose name matches `pattern`. */
function only(results, pattern) {
  const names = [...results.keys()].filter(name => pattern.test(name));
  assert.equal(names.length, 1, `${pattern}: ${names}`);
  return results.get(names[0]);
}

const GOOD = { 'content-type': 'text/html; charset=utf-8', 'content-security-policy': CSP, ...SECURITY_HEADERS };

test('checkHeaders passes a page with the exact CSP and the five headers', () => {
  assert.deepEqual(checkHeaders(new Headers(GOOD)), []);
  assert.deepEqual(checkHeaders(GOOD), [], 'a plain object works too');
});

test('checkHeaders names a missing or wrong header', () => {
  const missing = { ...GOOD };
  delete missing['x-content-type-options'];
  assert.deepEqual(checkHeaders(missing), ['x-content-type-options is missing']);
  const wrong = { ...GOOD, 'content-security-policy': `${CSP}; upgrade-insecure-requests` };
  assert.equal(checkHeaders(wrong).length, 1);
  assert.match(checkHeaders(wrong)[0], /^content-security-policy is /);
});

test('checkHeaders fails a page that sets a cookie', () => {
  const headers = new Headers(GOOD);
  headers.append('set-cookie', 'session=1; Path=/');
  assert.deepEqual(checkHeaders(headers), ['a cookie is set']);
});

test('against the local server, every smoke check passes or skips', async () => {
  const results = await smokeLocally();
  for (const [name, { status, detail }] of results) assert.notEqual(status, 'FAIL', `${name}: ${detail}`);
  assert.equal(only(results, /consent id/).status, 'PASS');
});

test('the smoke test fails a deployment that doesn’t have the app’s consent id yet', async () => {
  // The same module object the check and subscribe.js read, changed only for this test: an app whose wording this
  // deployment doesn't have, so a release would have to wait for the site's deploy.
  const shipped = consent.current;
  consent.current = 'consent-test-not-deployed';
  try {
    const result = only(await smokeLocally(), /consent id/);
    assert.equal(result.status, 'FAIL');
    assert.match(result.detail, /^422: /);
  } finally {
    consent.current = shipped;
  }
});

test('evaluateBurst passes when everything past the first 10 is 429', () => {
  assert.deepEqual(evaluateBurst({ 200: 10, 429: 40 }, 50), []);
  assert.deepEqual(evaluateBurst({ 429: 50 }, 50), []);
});

test('evaluateBurst fails when the firewall never answers 429', () => {
  assert.equal(evaluateBurst({ 200: 50 }, 50).length, 1);
  assert.equal(evaluateBurst({ 200: 12, 429: 38 }, 50).length, 1, '38 isn’t at least 40');
});

test('evaluateBurst fails on any 5xx, even with enough 429s', () => {
  assert.equal(evaluateBurst({ 200: 9, 429: 40, 502: 1 }, 50).length, 1);
  assert.equal(evaluateBurst({ 429: 49, 500: 1 }, 50).length, 1, 'enough 429s, but a 5xx');
  assert.equal(evaluateBurst({ 200: 10, 429: 39, 500: 1 }, 50).length, 2, 'too few 429s, and a 5xx');
});
