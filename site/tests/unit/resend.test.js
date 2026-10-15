// One request to Resend, with a fake fetch and sleep. Nothing here reaches Resend.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  ATTEMPT_TIMEOUT_MS, MAX_RATE_WAIT_MS, RESEND_BASE, RETRY_PAUSE_MS, resend,
} from '../../api/_lib/resend.js';

/**
 * A call whose fetch answers from `answers` in turn: { status, json, text, headers }, 'network' (a rejection), 'hang'
 * (never answers until its signal aborts), or 'broken' (a 200 whose body breaks off).
 */
function harness(answers = []) {
  const calls = [], sleeps = [];
  const fetch = async (url, init) => {
    calls.push({ url, init, headers: new Headers(init.headers) });
    const answer = answers.shift() ?? { status: 200, json: { object: 'contact', id: 'contact-id' } };
    if (answer === 'network') throw new TypeError('fetch failed');
    if (answer === 'hang') {
      // A real hanging request holds a socket open, which keeps Node running; the timer stands in for it.
      return new Promise((resolve, reject) => {
        const socket = setTimeout(() => {}, 60_000);
        init.signal.addEventListener('abort', () => { clearTimeout(socket); reject(init.signal.reason); });
      });
    }
    if (answer === 'broken') {
      const body = new ReadableStream({ start(controller) { controller.error(new TypeError('terminated')); } });
      return new Response(body, { status: 200 });
    }
    const text = answer.text ?? (answer.json === undefined ? '' : JSON.stringify(answer.json));
    // A 204 can't have a body, not even an empty one.
    return new Response(answer.status === 204 ? null : text, { status: answer.status, headers: answer.headers });
  };
  const call = (options = {}) => resend({
    fetch, sleep: async ms => { sleeps.push(ms); }, key: 're_test', method: 'GET', path: '/contacts/sam%40example.com',
    timeoutMs: 50, ...options,
  });
  return { call, calls, sleeps, fetch };
}

/** The time each attempt is given while `run` runs: every delay AbortSignal.timeout is asked for, in order. */
async function attemptTimes(run) {
  const real = AbortSignal.timeout;
  const times = [];
  AbortSignal.timeout = ms => { times.push(ms); return real.call(AbortSignal, ms); };
  try {
    await run();
  } finally {
    AbortSignal.timeout = real;
  }
  return times;
}

test('a 2xx is ok, with the JSON it answered, and an empty body is fine', async () => {
  let run = harness([{ status: 200, json: { object: 'contact', id: 'contact-id' } }]);
  assert.deepEqual(await run.call(), { ok: true, status: 200, json: { object: 'contact', id: 'contact-id' } });
  assert.equal(run.calls.length, 1);
  assert.deepEqual(run.sleeps, []);

  run = harness([{ status: 201, json: { id: 'email-id' } }]);
  assert.deepEqual(await run.call({ method: 'POST', path: '/emails', body: {} }), { ok: true, status: 201, json: { id: 'email-id' } });

  for (const status of [200, 204]) {
    run = harness([{ status }]);
    assert.deepEqual(await run.call(), { ok: true, status, json: null }, `${status} with no body`);
  }
});

test('a 404 is notfound, with no retry', async () => {
  const run = harness([{ status: 404, json: { statusCode: 404, name: 'not_found', message: 'Contact not found' } }]);
  assert.deepEqual(await run.call(), { ok: false, status: 404, reason: 'notfound', name: 'not_found' });
  assert.equal(run.calls.length, 1);
  assert.deepEqual(run.sleeps, []);
});

test('a 422, like any other 4xx, is rejected, with no retry', async () => {
  for (const [status, name] of [
    [422, 'missing_required_field'], [400, 'validation_error'], [401, 'restricted_api_key'], [403, 'validation_error'],
    [405, 'method_not_allowed'], [409, 'invalid_idempotent_request'], [409, 'concurrent_idempotent_requests'],
  ]) {
    const run = harness([{ status, json: { statusCode: status, name, message: 'refused' } }]);
    assert.deepEqual(await run.call(), { ok: false, status, reason: 'rejected', name }, `${status} ${name}`);
    assert.equal(run.calls.length, 1, `${status} ${name}`);
    assert.deepEqual(run.sleeps, [], `${status} ${name}`);
  }
});

test('a 409 resource_locked, another request changing the contact, is retried once after RETRY_PAUSE_MS', async () => {
  // Resend's advice for it: "Retry the request after a short delay."
  const locked = {
    status: 409,
    json: { statusCode: 409, name: 'resource_locked', message: 'Another request is already updating this resource.' },
  };
  let run = harness([locked, { status: 200, json: { object: 'contact', id: 'contact-id' } }]);
  const outcome = await run.call({ method: 'PATCH', body: { unsubscribed: true } });
  assert.deepEqual(outcome, { ok: true, status: 200, json: { object: 'contact', id: 'contact-id' } });
  assert.equal(run.calls.length, 2);
  assert.deepEqual(run.sleeps, [RETRY_PAUSE_MS]);
  assert.equal(run.calls[1].init.body, '{"unsubscribed":true}', 'the same request again');

  run = harness([locked, locked]);
  const stillLocked = { ok: false, status: 409, reason: 'rejected', name: 'resource_locked' };
  assert.deepEqual(await run.call(), stillLocked, 'still locked: the second answer stands');
  assert.equal(run.calls.length, 2);
  assert.deepEqual(run.sleeps, [RETRY_PAUSE_MS]);

  run = harness([{ status: 409, text: 'Conflict' }]);
  assert.deepEqual(await run.call(), { ok: false, status: 409, reason: 'rejected', name: null }, 'a 409 with no name');
  assert.equal(run.calls.length, 1, 'a 409 with no name isn’t retried');
});

test('a 500 then a 200 is ok, after one pause of RETRY_PAUSE_MS, with the same request twice', async () => {
  const run = harness([{ status: 500, json: { name: 'application_error' } }, { status: 200, json: { id: 'contact-id' } }]);
  const outcome = await run.call({ method: 'PATCH', body: { unsubscribed: true }, idempotencyKey: 'key-1' });
  assert.deepEqual(outcome, { ok: true, status: 200, json: { id: 'contact-id' } });
  assert.equal(run.calls.length, 2);
  assert.deepEqual(run.sleeps, [RETRY_PAUSE_MS]);
  assert.equal(RETRY_PAUSE_MS, 300);
  for (const call of run.calls) {
    assert.equal(call.url, `${RESEND_BASE}/contacts/sam%40example.com`);
    assert.equal(call.init.method, 'PATCH');
    assert.equal(call.init.body, '{"unsubscribed":true}');
    assert.equal(call.headers.get('idempotency-key'), 'key-1');
  }
});

test('two 5xx answers are server, with Resend’s name for it', async () => {
  for (const [status, name] of [[500, 'application_error'], [503, 'service_unavailable']]) {
    const run = harness([{ status, json: { name } }, { status, json: { name } }]);
    assert.deepEqual(await run.call(), { ok: false, status, reason: 'server', name }, String(status));
    assert.equal(run.calls.length, 2);
    assert.deepEqual(run.sleeps, [RETRY_PAUSE_MS]);
  }
});

test('the second attempt’s answer stands', async () => {
  const run = harness([{ status: 502, text: 'Bad gateway' }, { status: 404, json: { name: 'not_found' } }]);
  assert.deepEqual(await run.call(), { ok: false, status: 404, reason: 'notfound', name: 'not_found' });
  assert.equal(run.calls.length, 2);
});

test('a plain 429 waits its retry-after, at most MAX_RATE_WAIT_MS, then tries once more', async () => {
  const rate = after => ({
    status: 429, json: { name: 'rate_limit_exceeded' }, headers: after === undefined ? {} : { 'retry-after': after },
  });
  let run = harness([rate('0.2'), { status: 200 }]);
  assert.equal((await run.call()).ok, true);
  assert.deepEqual(run.sleeps, [200], 'retry-after: 0.2 waits 200 ms');
  assert.equal(run.calls.length, 2);

  assert.equal(MAX_RATE_WAIT_MS, 1000);
  for (const [after, why] of [
    ['30', 'capped'], [undefined, 'no retry-after'], ['Wed, 21 Oct 2026 07:28:00 GMT', 'a date'], ['-1', 'negative'],
  ]) {
    run = harness([rate(after), { status: 200 }]);
    assert.equal((await run.call()).ok, true, why);
    assert.deepEqual(run.sleeps, [MAX_RATE_WAIT_MS], why);
  }

  run = harness([rate('1'), rate('1')]);
  assert.deepEqual(await run.call(), { ok: false, status: 429, reason: 'rate', name: 'rate_limit_exceeded' });
  assert.equal(run.calls.length, 2);
});

test('a 429 for the daily or monthly quota is quota at once, with no retry', async () => {
  for (const name of ['daily_quota_exceeded', 'monthly_quota_exceeded']) {
    const run = harness([{ status: 429, json: { name }, headers: { 'retry-after': '0' } }]);
    assert.deepEqual(await run.call(), { ok: false, status: 429, reason: 'quota', name });
    assert.equal(run.calls.length, 1);
    assert.deepEqual(run.sleeps, []);
  }
});

test('a network error and a hang are network and timeout, each tried twice', async () => {
  let run = harness(['network', 'network']);
  assert.deepEqual(await run.call(), { ok: false, status: null, reason: 'network', name: null });
  assert.equal(run.calls.length, 2);
  assert.deepEqual(run.sleeps, [RETRY_PAUSE_MS]);

  run = harness(['hang', 'hang']);
  assert.deepEqual(await run.call({ timeoutMs: 50 }), { ok: false, status: null, reason: 'timeout', name: null });
  assert.equal(run.calls.length, 2);
  assert.deepEqual(run.sleeps, [RETRY_PAUSE_MS]);
  assert.ok(run.calls.every(call => call.init.signal instanceof AbortSignal));
  assert.notEqual(run.calls[0].init.signal, run.calls[1].init.signal, 'each attempt gets its own time');

  for (const first of ['network', 'hang']) {
    run = harness([first, { status: 200, json: { id: 'contact-id' } }]);
    assert.deepEqual(await run.call(), { ok: true, status: 200, json: { id: 'contact-id' } }, `${first}, then an answer`);
  }
});

test('the URL is RESEND_BASE and the path, with Bearer and a User-Agent, and an Idempotency-Key only when passed', async () => {
  assert.equal(RESEND_BASE, 'https://api.resend.com');
  let run = harness();
  await run.call({ method: 'GET', path: '/contacts/sam%40example.com' });
  const [{ url, init, headers }] = run.calls;
  assert.equal(url, 'https://api.resend.com/contacts/sam%40example.com');
  assert.equal(init.method, 'GET');
  assert.equal(headers.get('authorization'), 'Bearer re_test');
  // Resend answers 403 to a request without a User-Agent.
  assert.equal(headers.get('user-agent'), 'annotake-site/1.0');
  assert.equal(headers.get('idempotency-key'), null);

  run = harness();
  await run.call({
    method: 'POST', path: '/emails', body: {}, idempotencyKey: 'welcome-abc',
    headers: { 'X-Test': 'yes', Authorization: 'Bearer another' },
  });
  assert.equal(run.calls[0].url, 'https://api.resend.com/emails');
  assert.equal(run.calls[0].headers.get('idempotency-key'), 'welcome-abc');
  assert.equal(run.calls[0].headers.get('x-test'), 'yes', 'more headers go along');
  assert.equal(run.calls[0].headers.get('authorization'), 'Bearer re_test', 'but the key is the one passed as key');
});

test('a body goes as JSON, with its Content-Type, only when one is given', async () => {
  let run = harness();
  await run.call({ method: 'GET' });
  assert.equal(run.calls[0].init.body, undefined);
  assert.equal(run.calls[0].headers.get('content-type'), null);

  run = harness();
  await run.call({ method: 'PATCH', body: { unsubscribed: true } });
  assert.equal(run.calls[0].init.body, '{"unsubscribed":true}');
  assert.equal(run.calls[0].headers.get('content-type'), 'application/json');

  run = harness();
  await run.call({ method: 'PATCH', path: '/contacts/sam%40example.com/topics', body: [{ id: 'news', subscription: 'opt_in' }] });
  assert.equal(run.calls[0].init.body, '[{"id":"news","subscription":"opt_in"}]');
});

test('it never throws: bodies that aren’t JSON, a body that breaks off, a fetch that throws at once, a failed pause', async () => {
  let run = harness([{ status: 502, text: '<html>Bad gateway</html>' }, { status: 503, text: '' }]);
  assert.deepEqual(await run.call(), { ok: false, status: 503, reason: 'server', name: null });

  run = harness([{ status: 404, text: 'Not Found' }]);
  assert.deepEqual(await run.call(), { ok: false, status: 404, reason: 'notfound', name: null });

  run = harness([{ status: 429, text: 'Slow down' }, { status: 429, text: '' }]);
  assert.deepEqual(await run.call(), { ok: false, status: 429, reason: 'rate', name: null }, 'no name: a plain rate limit');

  run = harness([{ status: 400, json: ['not', 'an', 'object'] }]);
  assert.deepEqual(await run.call(), { ok: false, status: 400, reason: 'rejected', name: null });

  run = harness([{ status: 422, json: { name: 42 } }]);
  assert.deepEqual(await run.call(), { ok: false, status: 422, reason: 'rejected', name: null }, 'a name that isn’t text');

  run = harness([{ status: 200, text: 'not JSON' }]);
  assert.deepEqual(await run.call(), { ok: true, status: 200, json: null });

  run = harness(['broken', 'broken']);
  assert.deepEqual(await run.call(), { ok: false, status: null, reason: 'network', name: null }, 'a body that breaks off');
  assert.equal(run.calls.length, 2);

  const base = { sleep: async () => {}, key: 're_test', method: 'GET', path: '/contacts/sam%40example.com', timeoutMs: 50 };
  const thrown = await resend({ ...base, fetch: () => { throw new TypeError('no fetch'); } });
  assert.deepEqual(thrown, { ok: false, status: null, reason: 'network', name: null });

  let attempts = 0;
  const paused = await resend({
    ...base, fetch: async () => { attempts++; return new Response('', { status: 500 }); },
    sleep: async () => { throw new Error('no timers'); },
  });
  assert.deepEqual(paused, { ok: false, status: 500, reason: 'server', name: null });
  assert.equal(attempts, 2, 'a pause that fails only makes it shorter');

  run = harness();
  const unsendable = await run.call({ method: 'PATCH', body: { count: 1n } });
  assert.deepEqual(unsendable, { ok: false, status: null, reason: 'rejected', name: null }, 'a body JSON can’t hold');
  assert.equal(run.calls.length, 0);
});

test('each attempt is given ATTEMPT_TIMEOUT_MS, or the timeoutMs passed', async () => {
  const run = harness();
  const times = await attemptTimes(() => resend({
    fetch: run.fetch, sleep: async () => {}, key: 're_test', method: 'GET', path: '/contacts/sam%40example.com',
  }));
  assert.deepEqual(times, [ATTEMPT_TIMEOUT_MS], 'with no timeoutMs, the 4 s the functions rely on');
  assert.equal(run.calls.length, 1);

  const hung = harness(['hang', 'hang']);
  assert.deepEqual(await attemptTimes(() => hung.call({ timeoutMs: 50 })), [50, 50], 'each attempt, its own 50 ms');
});

test('the worst case fits inside Vercel’s 10 s limit', () => {
  assert.equal(ATTEMPT_TIMEOUT_MS, 4000);
  assert.ok(ATTEMPT_TIMEOUT_MS * 2 + Math.max(RETRY_PAUSE_MS, MAX_RATE_WAIT_MS) < 10000);
});
