// Checkpoint 4's smoke test against a deployment: `make site-smoke URL=https://annotake.app`. Prints PASS, FAIL, or
// SKIP for each check, and exits 1 if anything fails. It changes nothing: no form is sent, its one POST is turned away
// before /api/subscribe calls Resend, and nothing is downloaded beyond the disk image's headers. Against a local server
// (an http base) it doesn't follow redirects off the site, so the checks that need GitHub or the real domains say SKIP.
import { fileURLToPath } from 'node:url';
import consent from '../../api/_lib/consent.json' with { type: 'json' };
import { CSP, DMG_URL, SECURITY_HEADERS } from '../expected.js';

const EXPECTED = { 'content-security-policy': CSP, ...SECURITY_HEADERS };
const MIN_DMG_BYTES = 1024 * 1024;

/** What's wrong with a page's headers: each missing or wrong security header, and any cookie. Empty means fine. */
export function checkHeaders(headers) {
  const all = headers instanceof Headers ? headers : new Headers(headers);
  const problems = [];
  for (const [name, value] of Object.entries(EXPECTED)) {
    const actual = all.get(name);
    if (actual === null) problems.push(`${name} is missing`);
    else if (actual !== value) problems.push(`${name} is ${JSON.stringify(actual)}, not ${JSON.stringify(value)}`);
  }
  if (all.has('set-cookie') || all.getSetCookie?.().length) problems.push('a cookie is set');
  return problems;
}

/** The checks, in order, each resolving to { status: 'PASS' | 'FAIL' | 'SKIP', detail }. */
export function checks(base) {
  const url = path => new URL(path, base).href;
  const secure = new URL(base).protocol === 'https:';
  const pass = detail => ({ status: 'PASS', detail });
  const fail = detail => ({ status: 'FAIL', detail });
  const skip = detail => ({ status: 'SKIP', detail });
  return [
    ['/, /privacy, and /terms answer 200 HTML, with the CSP and the five headers, and no cookie', async () => {
      const problems = [];
      for (const path of ['/', '/privacy', '/terms']) {
        const response = await fetch(url(path), { redirect: 'manual' });
        await response.body?.cancel();
        if (response.status !== 200) problems.push(`${path}: ${response.status}`);
        if (!response.headers.get('content-type')?.startsWith('text/html')) problems.push(`${path}: not HTML`);
        problems.push(...checkHeaders(response.headers).map(problem => `${path}: ${problem}`));
      }
      return problems.length ? fail(problems.join('; ')) : pass('3 pages');
    }],
    ['/download answers 302 to the disk image on GitHub, which is over 1 MB', async () => {
      const response = await fetch(url('/download'), { redirect: 'manual' });
      await response.body?.cancel();
      const location = response.headers.get('location');
      if (response.status !== 302 || location !== DMG_URL) return fail(`${response.status} to ${location}`);
      if (!secure) return skip('302 to GitHub; not followed from a local server');
      const dmg = await fetch(location);
      await dmg.body?.cancel();
      const type = dmg.headers.get('content-type');
      const bytes = Number(dmg.headers.get('content-length'));
      if (dmg.status !== 200) return fail(`the disk image answered ${dmg.status}`);
      if (!['application/x-apple-diskimage', 'application/octet-stream'].includes(type)) return fail(`type ${type}`);
      if (!(bytes > MIN_DMG_BYTES)) return fail(`${bytes} bytes`);
      return pass(`${(bytes / 1024 / 1024).toFixed(1)} MB, ${type}`);
    }],
    ['GET /api/link answers 405', async () => {
      const response = await fetch(url('/api/link'));
      await response.body?.cancel();
      return response.status === 405 ? pass('405') : fail(`${response.status}`);
    }],
    // The email list's functions: a deployment from before them answers 404, and the app only retries.
    ['GET /api/subscribe answers 405', async () => {
      const response = await fetch(url('/api/subscribe'));
      await response.body?.cancel();
      return response.status === 405 ? pass('405') : fail(`${response.status}`);
    }],
    // The function reads the request before the address, so an address it won't take answers 400 only once the
    // deployment has the consent id the app sends: release an app with new wording only after this passes.
    [`POST /api/subscribe has the app’s consent id, ${consent.current}`, async () => {
      const request = { email: 'smoke@example', news: false, consent: consent.current, appVersion: 'smoke' };
      const response = await fetch(url('/api/subscribe'), {
        method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(request),
      });
      await response.body?.cancel();
      if (response.status === 422) return fail('422: this deployment doesn’t have it yet');
      return response.status === 400 ? pass('400 for an address it won’t take') : fail(`${response.status}`);
    }],
    // With UNSUBSCRIBE_SECRET set, as in Production only, a link with nothing to check is 400; without it, 502.
    ['GET /api/unsubscribe with no address or signature answers 400', async () => {
      const response = await fetch(url('/api/unsubscribe'));
      await response.body?.cancel();
      return response.status === 400 ? pass('400') : fail(`${response.status}`);
    }],
    ['/api/_lib/consent.json, the functions’ shared code, answers 404', async () => {
      const response = await fetch(url('/api/_lib/consent.json'));
      await response.body?.cancel();
      return response.status === 404 ? pass('404') : fail(`${response.status}`);
    }],
    ['the font is cached as immutable', async () => {
      const response = await fetch(url('/assets/fonts/jost-latin.v1.woff2'));
      await response.body?.cancel();
      const cache = response.headers.get('cache-control') ?? '';
      return response.status === 200 && cache.includes('immutable') ? pass(cache) : fail(`${response.status}, ${cache}`);
    }],
    ['/nope answers 404', async () => {
      const response = await fetch(url('/nope'));
      await response.body?.cancel();
      return response.status === 404 ? pass('404') : fail(`${response.status}`);
    }],
    ['Vercel Web Analytics is on (/_vercel/insights/script.js answers 200)', async () => {
      const response = await fetch(url('/_vercel/insights/script.js'));
      await response.body?.cancel();
      return response.status === 200 ? pass('200') : fail(`${response.status}`);
    }],
    ['www.annotake.app and annotake.com end at https://annotake.app/', async () => {
      if (new URL(base).origin !== 'https://annotake.app') return skip('only for https://annotake.app');
      const problems = [];
      for (const other of ['https://www.annotake.app/', 'https://annotake.com/']) {
        const response = await fetch(other);
        await response.body?.cancel();
        if (response.url !== 'https://annotake.app/') problems.push(`${other} ended at ${response.url}`);
      }
      return problems.length ? fail(problems.join('; ')) : pass('both redirect');
    }],
  ];
}

async function main() {
  const base = process.argv[2];
  if (!base) {
    console.error('usage: node smoke.mjs <base URL>, e.g. https://annotake.app');
    process.exit(2);
  }
  let failed = false;
  for (const [name, check] of checks(base)) {
    let result;
    try {
      result = await check();
    } catch (error) {
      result = { status: 'FAIL', detail: error.cause?.code ?? error.message };
    }
    if (result.status === 'FAIL') failed = true;
    console.log(`${result.status.padEnd(4)}  ${name}: ${result.detail}`);
  }
  process.exit(failed ? 1 : 0);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) await main();
