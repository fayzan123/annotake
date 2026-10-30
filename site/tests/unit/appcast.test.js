// The update feed's counter, with a fake Upstash and log. Nothing here reaches Redis.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { FEED_URL, KEEP_SECONDS, SALT_SECONDS, appVersion, createHandler } from '../../api/appcast.js';

const ENV = { UPSTASH_REDIS_REST_URL: 'https://redis.example/', UPSTASH_REDIS_REST_TOKEN: 'token' };
const SPARKLE = 'Annotake/0.3.1 Sparkle/2.10.0';
const IP = '203.0.113.7';
const DAY = '2026-10-30';

/**
 * A handler over a small in-memory Redis that answers Upstash's /pipeline. `answer` replaces the store's answer:
 * { status }, 'network' (a rejection), or 'hang' (never answers until its signal aborts).
 */
function harness({ env = ENV, answer, day = DAY } = {}) {
  const store = new Map(), ttls = new Map(), calls = [], logs = [];
  const run = ([name, key, ...args]) => {
    switch (name) {
      case 'SET':
        if (!store.has(key)) { store.set(key, args[0]); ttls.set(key, args[3]); }
        return 'OK';
      case 'GET': return store.get(key) ?? null;
      case 'PFADD': store.set(key, new Set([...(store.get(key) ?? []), ...args])); return 1;
      case 'HINCRBY': {
        const hash = store.get(key) ?? {};
        hash[args[0]] = (hash[args[0]] ?? 0) + args[1];
        store.set(key, hash);
        return hash[args[0]];
      }
      case 'EXPIRE': ttls.set(key, args[0]); return 1;
      default: return { error: `unknown ${name}` };
    }
  };
  const fetch = async (url, init) => {
    calls.push({ url, headers: new Headers(init.headers), body: JSON.parse(init.body) });
    if (answer === 'network') throw new TypeError('fetch failed');
    if (answer === 'hang') {
      return new Promise((resolve, reject) => {
        const socket = setTimeout(() => {}, 60_000);
        init.signal.addEventListener('abort', () => { clearTimeout(socket); reject(init.signal.reason); });
      });
    }
    if (answer) return new Response('{}', { status: answer.status });
    const results = JSON.parse(init.body).map(command => {
      const result = run(command);
      return result?.error ? result : { result };
    });
    return Response.json(results);
  };
  const { GET, HEAD } = createHandler({
    fetch, env, log: line => logs.push(line), now: () => new Date(`${day}T12:00:00Z`), random: () => 'salt',
    timeoutMs: 50,
  });
  return { GET, HEAD, store, ttls, calls, logs };
}

const check = ({ ua = SPARKLE, ip = IP } = {}) => new Request('https://annotake.app/api/appcast', {
  headers: { ...(ua ? { 'user-agent': ua } : {}), ...(ip ? { 'x-forwarded-for': `${ip}, 10.0.0.1` } : {}) },
});

function assertFeedRedirect(response) {
  assert.equal(response.status, 302);
  assert.equal(response.headers.get('location'), FEED_URL);
  assert.equal(response.headers.get('cache-control'), 'no-store');
}

test('the version comes only from Sparkle’s User-Agent', () => {
  assert.equal(appVersion('Annotake/0.3.0 Sparkle/2.10.0'), '0.3.0');
  assert.equal(appVersion('Annotake/1.0.0-beta.2 Sparkle/2.10.0'), '1.0.0-beta.2');
  for (const ua of [null, '', 'curl/8.7.1', 'Mozilla/5.0', 'Annotake/0.3.0', 'Annotake/x Sparkle/2',
    `Annotake/${'1'.repeat(40)} Sparkle/2`, 'Annotake/0.3.0 <script> Sparkle/2']) {
    assert.equal(appVersion(ua), null, ua);
  }
});

test('a check is counted under the day and version, and redirected to the feed', async () => {
  const { GET, store, ttls, calls, logs } = harness();
  assertFeedRedirect(await GET(check()));
  assert.equal(calls.length, 2);
  assert.equal(calls[0].url, 'https://redis.example/pipeline');
  assert.equal(calls[0].headers.get('authorization'), 'Bearer token');
  const mac = createHmac('sha256', 'salt').update(IP).digest('hex').slice(0, 32);
  assert.deepEqual([...store.get(`installs:${DAY}:0.3.1`)], [mac]);
  assert.deepEqual(store.get(`checks:${DAY}`), { '0.3.1': 1 });
  assert.equal(ttls.get(`salt:${DAY}`), SALT_SECONDS);
  assert.equal(ttls.get(`installs:${DAY}:0.3.1`), KEEP_SECONDS);
  assert.equal(ttls.get(`checks:${DAY}`), KEEP_SECONDS);
  assert.deepEqual(logs, ['appcast: counted']);
});

test('nothing sent to Redis or logged holds the IP', async () => {
  const { GET, calls, logs, store } = harness();
  await GET(check());
  const sent = JSON.stringify(calls.map(call => call.body)) + JSON.stringify([...store.entries()].map(([k, v]) =>
    [k, v instanceof Set ? [...v] : v])) + logs.join('\n');
  assert.ok(!sent.includes(IP));
});

test('the same Mac twice is one install and two checks; another Mac is another install', async () => {
  const { GET, store } = harness();
  await GET(check());
  await GET(check());
  await GET(check({ ip: '198.51.100.9' }));
  assert.equal(store.get(`installs:${DAY}:0.3.1`).size, 2);
  assert.deepEqual(store.get(`checks:${DAY}`), { '0.3.1': 3 });
});

test('the day’s salt is set only once', async () => {
  const { GET, calls } = harness();
  await GET(check());
  await GET(check());
  assert.deepEqual(calls[0].body[0], ['SET', `salt:${DAY}`, 'salt', 'NX', 'EX', SALT_SECONDS]);
  assert.deepEqual(calls[2].body[0], calls[0].body[0]);
});

test('HEAD answers like GET', async () => {
  const { HEAD, logs } = harness();
  assertFeedRedirect(await HEAD(check()));
  assert.deepEqual(logs, ['appcast: counted']);
});

test('a browser, a bot, or no User-Agent is redirected without a count', async () => {
  for (const ua of ['Mozilla/5.0', 'curl/8.7.1', '']) {
    const { GET, calls, logs } = harness();
    assertFeedRedirect(await GET(check({ ua })));
    assert.equal(calls.length, 0);
    assert.deepEqual(logs, ['appcast: skipped']);
  }
});

test('with no IP, nothing is counted', async () => {
  const { GET, calls, logs } = harness();
  assertFeedRedirect(await GET(check({ ip: null })));
  assert.equal(calls.length, 0);
  assert.deepEqual(logs, ['appcast: skipped no ip']);
});

test('Vercel KV’s older variable names work too; with neither, it isn’t configured', async () => {
  const kv = harness({ env: { KV_REST_API_URL: 'https://kv.example', KV_REST_API_TOKEN: 'kv' } });
  await kv.GET(check());
  assert.equal(kv.calls[0].url, 'https://kv.example/pipeline');
  assert.deepEqual(kv.logs, ['appcast: counted']);

  for (const env of [{}, { UPSTASH_REDIS_REST_URL: 'https://redis.example' }]) {
    const none = harness({ env });
    assertFeedRedirect(await none.GET(check()));
    assert.equal(none.calls.length, 0);
    assert.deepEqual(none.logs, ['appcast: not configured']);
  }
});

test('a Redis failure is logged, and the feed still answers', async () => {
  const cases = [
    [{ status: 500 }, 'appcast: failed status 500'],
    [{ status: 429 }, 'appcast: failed status 429'],
    ['network', 'appcast: failed network'],
    ['hang', 'appcast: failed timeout'],
  ];
  for (const [answer, line] of cases) {
    const { GET, logs } = harness({ answer });
    const started = Date.now();
    assertFeedRedirect(await GET(check()));
    assert.ok(Date.now() - started < 1000);
    assert.deepEqual(logs, [line]);
  }
});

test('a command Redis refuses is a failure', async () => {
  const logs = [];
  const { GET } = createHandler({
    fetch: async () => Response.json([{ error: 'ERR' }, { result: null }]),
    env: ENV, log: line => logs.push(line), now: () => new Date(), timeoutMs: 50,
  });
  assertFeedRedirect(await GET(check()));
  assert.deepEqual(logs, ['appcast: failed command']);
});

test('days are UTC dates', async () => {
  const { GET, store } = harness({ day: '2026-12-31' });
  await GET(check());
  assert.ok(store.has('checks:2026-12-31'));
});
