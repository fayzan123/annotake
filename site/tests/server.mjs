// A local stand-in for Vercel, so every test runs without it. It serves a site folder the way that folder's
// vercel.json says: clean URLs, no trailing slashes, the redirects, the headers, 404.html, and the functions in api/,
// which get a web Request as on Vercel. Files .vercelignore lists, dotfiles, and anything above the root aren't served.
// /api/link runs in dry-run mode (EMAIL_DRY_RUN=1) unless `env` says otherwise, so it never sends an email.
//
//   node site/tests/server.mjs [--port 4173] [--root site]
import http from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { readFileSync } from 'node:fs';
import { extname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { parseArgs } from 'node:util';

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.woff2': 'font/woff2',
  '.txt': 'text/plain; charset=utf-8',
  '.xml': 'application/xml; charset=utf-8',
};

const ANALYTICS = '/_vercel/insights/script.js';

/** A vercel.json `source` as a regular expression: `(.*)` stands for any rest of the path. */
function sourcePattern(source) {
  const parts = source.split('(.*)').map(part => part.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
  return new RegExp(`^${parts.join('(.*)')}$`);
}

/** The paths .vercelignore keeps out of a deployment: `dir/` entries hide a folder, others one path. */
function ignoredPaths(root) {
  let text = '';
  try {
    text = readFileSync(join(root, '.vercelignore'), 'utf8');
  } catch {
    return [];
  }
  return text.split('\n').map(line => line.trim()).filter(line => line && !line.startsWith('#'))
    .map(line => line.replace(/^\//, ''));
}

export function createServer({ root, env = {} }) {
  root = resolve(root);
  const config = JSON.parse(readFileSync(join(root, 'vercel.json'), 'utf8'));
  const headerRules = (config.headers ?? []).map(rule => ({ pattern: sourcePattern(rule.source), headers: rule.headers }));
  const redirects = new Map((config.redirects ?? []).map(rule => [rule.source, rule]));
  const ignored = ignoredPaths(root);
  // Vercel gives functions their environment through process.env.
  process.env.EMAIL_DRY_RUN = env.EMAIL_DRY_RUN ?? '1';
  for (const [key, value] of Object.entries(env)) process.env[key] = value;

  function configHeaders(pathname) {
    const headers = {};
    for (const rule of headerRules) {
      if (rule.pattern.test(pathname)) for (const { key, value } of rule.headers) headers[key] = value;
    }
    return headers;
  }

  function isHidden(rel) {
    const segments = rel.split('/');
    if (segments.some(segment => segment.startsWith('.'))) return true;
    if (segments[0] === 'api') return true;  // functions run; their sources aren't served
    return ignored.some(entry => (entry.endsWith('/') ? rel.startsWith(entry) : rel === entry));
  }

  /** The file a clean URL names, or null. */
  async function findFile(pathname) {
    const target = resolve(root, `.${pathname}`);
    if (target !== root && !target.startsWith(root + sep)) return null;
    const rel = relative(root, target).split(sep).join('/');
    if (rel && isHidden(rel)) return null;
    for (const candidate of [target, `${target}.html`, join(target, 'index.html')]) {
      try {
        if ((await stat(candidate)).isFile()) return candidate;
      } catch {}
    }
    return null;
  }

  async function runFunction(req, res, pathname, search) {
    const file = join(root, `${pathname}.js`);
    let module;
    try {
      // The modification time keeps edits live while `make site-dev` runs.
      module = await import(`${pathToFileURL(file).href}?v=${(await stat(file)).mtimeMs}`);
    } catch (error) {
      if (error.code === 'ENOENT') return send(req, res, pathname, 404, ...(await notFound()));
      throw error;
    }
    const handler = module[req.method];
    if (typeof handler !== 'function') {
      return send(req, res, pathname, 405, { 'Content-Type': 'text/plain; charset=utf-8' }, 'Method Not Allowed');
    }
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    const hasBody = !['GET', 'HEAD'].includes(req.method);
    const request = new Request(`http://${req.headers.host}${pathname}${search}`, {
      method: req.method,
      headers: Object.entries(req.headers).flatMap(([name, value]) =>
        (Array.isArray(value) ? value : [value]).map(one => [name, one])),
      body: hasBody ? Buffer.concat(chunks) : undefined,
    });
    const response = await handler(request);
    const headers = Object.fromEntries(response.headers);
    send(req, res, pathname, response.status, headers, Buffer.from(await response.arrayBuffer()));
  }

  async function notFound() {
    const page = join(root, '404.html');
    try {
      return [{ 'Content-Type': TYPES['.html'] }, await readFile(page)];
    } catch {
      return [{ 'Content-Type': 'text/plain; charset=utf-8' }, 'Not Found'];
    }
  }

  function send(req, res, pathname, status, headers, body = '') {
    const buffer = Buffer.isBuffer(body) ? body : Buffer.from(body);
    const all = {};
    for (const [name, value] of Object.entries({ ...headers, ...configHeaders(pathname) })) all[name.toLowerCase()] = value;
    all['content-length'] = buffer.length;
    res.writeHead(status, all);
    res.end(req.method === 'HEAD' ? undefined : buffer);
  }

  function redirect(req, res, pathname, status, location) {
    send(req, res, pathname, status, { Location: location });
  }

  async function handle(req, res) {
    const url = new URL(req.url, 'http://localhost');
    let pathname;
    try {
      pathname = decodeURIComponent(url.pathname);
    } catch {
      return send(req, res, url.pathname, 404, ...(await notFound()));
    }
    const search = url.search;

    const rule = redirects.get(pathname);
    if (rule) return redirect(req, res, pathname, rule.statusCode ?? 308, rule.destination);
    if (config.trailingSlash === false && pathname.length > 1 && pathname.endsWith('/')) {
      return redirect(req, res, pathname, 308, pathname.replace(/\/+$/, '') + search);
    }
    if (config.cleanUrls && pathname.endsWith('.html')) {
      const clean = pathname.replace(/(\/index)?\.html$/, '') || '/';
      return redirect(req, res, pathname, 308, clean + search);
    }
    if (pathname === ANALYTICS) return send(req, res, pathname, 200, { 'Content-Type': TYPES['.js'] }, '');
    if (pathname.startsWith('/api/') && !extname(pathname)) return runFunction(req, res, pathname, search);

    if (!['GET', 'HEAD'].includes(req.method)) {
      return send(req, res, pathname, 405, { 'Content-Type': 'text/plain; charset=utf-8' }, 'Method Not Allowed');
    }
    const file = await findFile(pathname);
    if (!file) return send(req, res, pathname, 404, ...(await notFound()));
    const type = TYPES[extname(file)] ?? 'application/octet-stream';
    send(req, res, pathname, 200, { 'Content-Type': type }, await readFile(file));
  }

  return http.createServer((req, res) => {
    handle(req, res).catch(error => {
      console.error(error);
      if (!res.headersSent) res.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('Internal Server Error');
    });
  });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const { values } = parseArgs({ options: { port: { type: 'string', default: '4173' }, root: { type: 'string' } } });
  const root = values.root ? resolve(values.root) : fileURLToPath(new URL('..', import.meta.url));
  const port = Number(values.port);
  createServer({ root }).listen(port, '127.0.0.1', () => {
    console.log(`Serving ${root} at http://localhost:${port} (/api/link in dry-run mode)`);
  });
}
