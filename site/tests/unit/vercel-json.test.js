import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { CSP, DMG_URL, IMMUTABLE, SECURITY_HEADERS } from '../expected.js';

const site = new URL('../../', import.meta.url);
const config = JSON.parse(await readFile(new URL('vercel.json', site), 'utf8'));

/** Git without the user's own settings, hooks, or signing, so the scratch repository's commits are plain. */
const GIT_ENV = { PATH: process.env.PATH, HOME: tmpdir(), GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_NOSYSTEM: '1' };

function git(repo, ...args) {
  return execFileSync('git', ['-C', repo, '-c', 'user.name=Test', '-c', 'user.email=test@example.com', ...args],
    { env: GIT_ENV, encoding: 'utf8' }).trim();
}

/**
 * Whether Vercel builds a push to `repo`: it runs the ignore command in the project's root directory, site/, with the
 * last successful deployment's commit in VERCEL_GIT_PREVIOUS_SHA, and builds unless the command exits 0.
 */
function builds(repo, previous) {
  const env = previous === undefined ? GIT_ENV : { ...GIT_ENV, VERCEL_GIT_PREVIOUS_SHA: previous };
  const { status } = spawnSync('sh', ['-c', config.ignoreCommand], { cwd: join(repo, 'site'), env });
  assert.ok(status === 0 || status === 1, `exit ${status}: Vercel skips on 0 and builds on 1`);
  return status === 1;
}

test('vercel.json has exactly the planned keys', () => {
  assert.deepEqual(Object.keys(config).sort(), [
    '$schema', 'cleanUrls', 'framework', 'functions', 'headers', 'ignoreCommand', 'redirects', 'trailingSlash',
  ]);
  assert.equal(config.$schema, 'https://openapi.vercel.sh/vercel.json');
  assert.equal(config.framework, null);
  assert.equal(config.cleanUrls, true);
  assert.equal(config.trailingSlash, false);
});

test('a push builds unless site/ is unchanged since the last deployment, whatever its last commit touched', async () => {
  const repo = await mkdtemp(join(tmpdir(), 'annotake-ignore-'));
  try {
    git(repo, 'init', '-q', '-b', 'main');
    for (const folder of ['site', 'docs']) await mkdir(join(repo, folder));
    await writeFile(join(repo, 'site/index.html'), 'one');
    await writeFile(join(repo, 'docs/plan.md'), 'one');
    git(repo, 'add', '.');
    git(repo, 'commit', '-q', '-m', 'the deployed commit');
    const deployed = git(repo, 'rev-parse', 'HEAD');
    await writeFile(join(repo, 'site/index.html'), 'two');
    git(repo, 'commit', '-q', '-am', 'site: a change');
    const changed = git(repo, 'rev-parse', 'HEAD');
    await writeFile(join(repo, 'docs/plan.md'), 'two');
    git(repo, 'commit', '-q', '-am', 'docs: after it, in the same push');
    const head = git(repo, 'rev-parse', 'HEAD');

    // A branch landing as a fast-forward whose last commit is docs: site/ changed since the deployment, so it builds.
    assert.equal(builds(repo, deployed), true, 'site/ changed since the last deployment');
    assert.equal(builds(repo, changed), false, 'site/ unchanged since the last deployment');
    // And it builds whenever there's nothing to compare with: a redeploy of the deployed commit itself, a branch's
    // first deployment, or a deployed commit older than Vercel's shallow clone.
    assert.equal(builds(repo, head), true, 'a redeploy');
    assert.equal(builds(repo, undefined), true, 'no previous deployment');
    assert.equal(builds(repo, ''), true, 'an empty previous deployment');
    assert.equal(builds(repo, 'f'.repeat(40)), true, 'a commit the clone doesn’t have');
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
  // vercel.json's schema takes at most 256 characters.
  assert.ok(config.ignoreCommand.length <= 256, `${config.ignoreCommand.length} characters`);
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
