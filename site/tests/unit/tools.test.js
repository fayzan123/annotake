// The checkpoint tools' logic: the header check the smoke test applies to each page, and the burst test's verdict.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CSP, SECURITY_HEADERS } from '../expected.js';
import { checkHeaders } from '../tools/smoke.mjs';
import { evaluateBurst } from '../tools/burst.mjs';

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
