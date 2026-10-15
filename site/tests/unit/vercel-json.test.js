import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { CSP, DMG_URL, IMMUTABLE, SECURITY_HEADERS } from '../expected.js';

const site = new URL('../../', import.meta.url);
const config = JSON.parse(await readFile(new URL('vercel.json', site), 'utf8'));

test('vercel.json has exactly the planned keys', () => {
  assert.deepEqual(Object.keys(config).sort(), [
    '$schema', 'cleanUrls', 'framework', 'functions', 'headers', 'ignoreCommand', 'redirects', 'trailingSlash',
  ]);
  assert.equal(config.$schema, 'https://openapi.vercel.sh/vercel.json');
  assert.equal(config.framework, null);
  assert.equal(config.cleanUrls, true);
  assert.equal(config.trailingSlash, false);
});

test('a commit that leaves site/ alone skips the build', () => {
  assert.equal(config.ignoreCommand, 'git diff --quiet HEAD^ HEAD -- .');
});

test('the three functions may each run for 10 s', () => {
  assert.deepEqual(config.functions, {
    'api/link.js': { maxDuration: 10 },
    'api/subscribe.js': { maxDuration: 10 },
    'api/unsubscribe.js': { maxDuration: 10 },
  });
});

test('/download is a 302 to the latest disk image on GitHub', () => {
  assert.deepEqual(config.redirects, [{ source: '/download', destination: DMG_URL, statusCode: 302 }]);
});

test('every path gets the CSP and the five headers; fonts and images are immutable', () => {
  const byName = rules => Object.fromEntries(rules.map(({ key, value }) => [key.toLowerCase(), value]));
  assert.deepEqual(config.headers.map(rule => rule.source), ['/(.*)', '/assets/fonts/(.*)', '/assets/img/(.*)']);
  assert.deepEqual(byName(config.headers[0].headers), { 'content-security-policy': CSP, ...SECURITY_HEADERS });
  for (const rule of config.headers.slice(1)) {
    assert.deepEqual(byName(rule.headers), { 'cache-control': IMMUTABLE });
  }
});

test('.vercelignore keeps the tests and the README out of deployments', async () => {
  const lines = (await readFile(new URL('.vercelignore', site), 'utf8')).split('\n').filter(Boolean);
  assert.deepEqual(lines, ['tests/', 'README.md']);
});

test('site/package.json is an ES module package with no dependencies', async () => {
  const pkg = JSON.parse(await readFile(new URL('package.json', site), 'utf8'));
  assert.deepEqual(pkg, { private: true, type: 'module' });
});
