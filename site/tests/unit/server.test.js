// The local server mirrors Vercel, so the page tests mean something. These run it against a small fixture site that
// uses copies of the real vercel.json, .vercelignore, and package.json.
import { after, before, test } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { copyFile, mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createServer } from '../server.mjs';
import { CSP, DMG_URL, IMMUTABLE, SECURITY_HEADERS } from '../expected.js';

const SITE = fileURLToPath(new URL('../../', import.meta.url));

const FIXTURE = {
  'index.html': '<!DOCTYPE html><title>Home</title>',
  'privacy.html': '<!DOCTYPE html><title>Privacy</title>',
  '404.html': '<!DOCTYPE html><title>Not found</title>',
  'assets/site.css': 'body {}',
  'assets/site.js': 'export {};',
  'assets/fonts/x.v1.woff2': 'wOF2',
  'assets/img/a.v1.png': 'PNG',
  'assets/img/b.svg': '<svg xmlns="http://www.w3.org/2000/svg"/>',
  'licenses/a.txt': 'a license',
  'sitemap.xml': '<urlset/>',
  'README.md': '# not served',
  'tests/server.mjs': '// not served',
  'api/link.js': `
    export async function POST(request) {
      return Response.json({
        ok: true, method: request.method, path: new URL(request.url).pathname,
        type: request.headers.get('content-type'), body: await request.text(), dry: process.env.EMAIL_DRY_RUN ?? null,
      });
    }
    export function GET() { return Response.json({ got: 'GET' }); }
  `,
  'api/unsubscribe.js': `
    export function GET(request) {
      const query = new URL(request.url).searchParams;
      return Response.json({ e: query.get('e'), s: query.get('s'), dry: process.env.EMAIL_DRY_RUN ?? null });
    }
  `,
  // The functions' shared code: Vercel never makes a function of it, so the server mustn't even import it.
  'api/_lib/x.js': `
    globalThis.annotakeLibImported = true;
    export function GET() { return Response.json({ ran: 'GET' }); }
    export function POST() { return Response.json({ ran: 'POST' }); }
  `,
};

let dir, server, port;
const seen = [];

before(async () => {
  dir = await mkdtemp(join(tmpdir(), 'annotake-server-'));
  const root = join(dir, 'site');
  for (const [name, text] of Object.entries(FIXTURE)) {
    await mkdir(dirname(join(root, name)), { recursive: true });
    await writeFile(join(root, name), text);
  }
  for (const name of ['vercel.json', '.vercelignore', 'package.json']) await copyFile(join(SITE, name), join(root, name));
  await writeFile(join(dir, 'Makefile'), 'above the root\n');
  server = createServer({ root });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  port = server.address().port;
});

after(async () => {
  await new Promise(resolve => server.close(resolve));
  await rm(dir, { recursive: true, force: true });
});

/** Sends the path as written, without the URL normalization `fetch` would apply. */
function get(path, { method = 'GET', headers = {}, body } = {}) {
  return new Promise((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port, path, method, headers }, res => {
      const chunks = [];
      res.on('data', chunk => chunks.push(chunk));
      res.on('end', () => {
        const result = { status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks).toString() };
        seen.push({ path, ...result });
        resolve(result);
      });
    });
    req.on('error', reject);
    req.end(body);
  });
}

test('pages are served at clean URLs', async () => {
  const home = await get('/');
  assert.equal(home.status, 200);
  assert.equal(home.headers['content-type'], 'text/html; charset=utf-8');
  assert.match(home.body, /<title>Home<\/title>/);
  const privacy = await get('/privacy');
  assert.equal(privacy.status, 200);
  assert.match(privacy.body, /<title>Privacy<\/title>/);
});

test('.html URLs and trailing slashes answer 308 to the clean URL', async () => {
  for (const [path, location] of [
    ['/privacy.html', '/privacy'],
    ['/privacy/', '/privacy'],
    ['/index.html', '/'],
    ['/privacy.html?from=post', '/privacy?from=post'],
  ]) {
    const res = await get(path);
    assert.equal(res.status, 308, path);
    assert.equal(res.headers.location, location, path);
  }
});

test('/download answers 302 to the latest disk image', async () => {
  const res = await get('/download');
  assert.equal(res.status, 302);
  assert.equal(res.headers.location, DMG_URL);
});

test('an unknown path gets 404.html with status 404', async () => {
  const res = await get('/nope');
  assert.equal(res.status, 404);
  assert.equal(res.headers['content-type'], 'text/html; charset=utf-8');
  assert.match(res.body, /<title>Not found<\/title>/);
});

test('each kind of file gets its content type', async () => {
  for (const [path, type] of [
    ['/assets/site.css', 'text/css; charset=utf-8'],
    ['/assets/site.js', 'text/javascript; charset=utf-8'],
    ['/assets/img/b.svg', 'image/svg+xml'],
    ['/assets/img/a.v1.png', 'image/png'],
    ['/assets/fonts/x.v1.woff2', 'font/woff2'],
    ['/licenses/a.txt', 'text/plain; charset=utf-8'],
    ['/sitemap.xml', 'application/xml; charset=utf-8'],
  ]) {
    const res = await get(path);
    assert.equal(res.status, 200, path);
    assert.equal(res.headers['content-type'], type, path);
  }
});

test('a page, an asset, and the 404 carry the exact CSP and the five headers', async () => {
  for (const path of ['/', '/assets/site.css', '/nope']) {
    const res = await get(path);
    assert.equal(res.headers['content-security-policy'], CSP, path);
    for (const [name, value] of Object.entries(SECURITY_HEADERS)) assert.equal(res.headers[name], value, `${path} ${name}`);
  }
});

test('fonts and images are cached as immutable, and nothing else is', async () => {
  assert.equal((await get('/assets/fonts/x.v1.woff2')).headers['cache-control'], IMMUTABLE);
  assert.equal((await get('/assets/img/a.v1.png')).headers['cache-control'], IMMUTABLE);
  assert.notEqual((await get('/assets/site.css')).headers['cache-control'], IMMUTABLE);
  assert.notEqual((await get('/')).headers['cache-control'], IMMUTABLE);
});

test('the tests, the README, dotfiles, function sources, and anything above the root answer 404', async () => {
  for (const path of [
    '/tests/server.mjs', '/README.md', '/.vercelignore', '/api/link.js',
    '/../Makefile', '/%2e%2e/Makefile', '/..%2fMakefile', '/assets/..%2f..%2fMakefile',
  ]) {
    const res = await get(path);
    assert.equal(res.status, 404, path);
    assert.doesNotMatch(res.body, /above the root|not served/, path);
  }
});

test("Vercel's analytics script is stubbed with an empty script", async () => {
  const res = await get('/_vercel/insights/script.js');
  assert.equal(res.status, 200);
  assert.equal(res.headers['content-type'], 'text/javascript; charset=utf-8');
  assert.equal(res.body, '');
});

test('POST /api/link runs the function with a web Request, in dry-run mode', async () => {
  const body = JSON.stringify({ email: 'sam@example.com' });
  const res = await get('/api/link', { method: 'POST', headers: { 'content-type': 'application/json' }, body });
  assert.equal(res.status, 200);
  assert.equal(res.headers['content-type'], 'application/json');
  assert.deepEqual(JSON.parse(res.body), {
    ok: true, method: 'POST', path: '/api/link', type: 'application/json', body, dry: '1',
  });
  assert.equal(res.headers['content-security-policy'], CSP);
});

test("GET /api/link runs the function's GET, and a method it doesn't export answers 405", async () => {
  const got = await get('/api/link');
  assert.equal(got.status, 200);
  assert.deepEqual(JSON.parse(got.body), { got: 'GET' });
  assert.equal((await get('/api/link', { method: 'PUT', body: '{}' })).status, 405);
});

test('another function gets its query, in dry-run mode too', async () => {
  const res = await get('/api/unsubscribe?e=sam%40example.com&s=abc');
  assert.equal(res.status, 200);
  assert.deepEqual(JSON.parse(res.body), { e: 'sam@example.com', s: 'abc', dry: '1' });
});

test('the shared code in api/_lib never runs as a function, and nothing outside api/ does either', async () => {
  for (const [method, path] of [
    ['GET', '/api/_lib/x'], ['POST', '/api/_lib/x'], ['GET', '/api/_lib/x.js'], ['GET', '/api/_lib'],
    ['GET', '/api/link/..%2f_lib%2fx'], ['GET', '/api/..%2fassets%2fsite'], ['GET', '/api/.hidden'],
  ]) {
    const res = await get(path, { method, body: method === 'POST' ? '{}' : undefined });
    assert.equal(res.status, 404, `${method} ${path}`);
    assert.match(res.body, /<title>Not found<\/title>/, `${method} ${path}`);
  }
  assert.equal(globalThis.annotakeLibImported, undefined, 'api/_lib/x.js was never imported');
});

test('HEAD answers the headers without a body', async () => {
  const res = await get('/', { method: 'HEAD' });
  assert.equal(res.status, 200);
  assert.equal(res.headers['content-security-policy'], CSP);
  assert.equal(res.body, '');
});

test('no response sets a cookie', async () => {
  assert.ok(seen.length > 30, `checked ${seen.length} responses`);
  for (const res of seen) assert.equal(res.headers['set-cookie'], undefined, res.path);
});
