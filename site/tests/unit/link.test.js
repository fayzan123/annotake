// The link function, with a fake fetch, sleep, clock, and log. Nothing here reaches Resend.
import { after, test } from 'node:test';
import assert from 'node:assert/strict';
import {
  ATTEMPT_TIMEOUT_MS, EMAIL_HTML, EMAIL_TEXT, MAX_BODY_BYTES, MAX_RATE_WAIT_MS, RESEND_URL, RETRY_PAUSE_MS, TOO_FAST_MS,
  createHandler,
} from '../../api/link.js';

const ADDRESS = 'privatesam@example.com';
/** Every log line any test wrote, checked at the end for addresses. */
const allLogs = [];
const usedAddresses = new Set([ADDRESS]);

/**
 * A handler whose fetch answers from `answers` in turn: { status, json, headers }, 'network' (a rejection), or 'hang'
 * (never answers until its signal aborts).
 */
function harness({ answers = [], env = { RESEND_API_KEY: 're_test' } } = {}) {
  const calls = [], sleeps = [], logs = [];
  const fetch = async (url, init) => {
    calls.push({ url, init, headers: new Headers(init.headers), body: JSON.parse(init.body) });
    const answer = answers.shift() ?? { status: 200, json: { id: 'email-id' } };
    if (answer === 'network') throw new TypeError('fetch failed');
    if (answer === 'hang') {
      // A real hanging request holds a socket open, which keeps Node running; the timer stands in for it.
      return new Promise((resolve, reject) => {
        const socket = setTimeout(() => {}, 60_000);
        init.signal.addEventListener('abort', () => { clearTimeout(socket); reject(init.signal.reason); });
      });
    }
    return new Response(JSON.stringify(answer.json ?? {}), { status: answer.status, headers: answer.headers });
  };
  const log = line => { logs.push(line); allLogs.push(line); };
  const handler = createHandler({
    fetch, env, log, sleep: async ms => { sleeps.push(ms); }, today: () => '2026-10-01', timeoutMs: 50,
  });
  return { handler, calls, sleeps, logs };
}

function json(body, { headers = {} } = {}) {
  if (typeof body === 'object' && body?.email) usedAddresses.add(String(body.email).trim());
  return new Request('https://annotake.app/api/link', {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...headers },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  });
}

function form(fields) {
  if (fields.email) usedAddresses.add(fields.email.trim());
  return new Request('https://annotake.app/api/link', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(fields).toString(),
  });
}

const good = (extra = {}) => json({ email: `  ${ADDRESS} `, website: '', t: 5000, ...extra });

/** A page's text, as a reader sees it: tags gone, whitespace collapsed. */
const textOf = html => html.replace(/<title>[\s\S]*?<\/title>/, '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ');

async function answer(response) {
  return { status: response.status, type: response.headers.get('content-type'), body: await response.text() };
}

test('a good JSON request sends one email through Resend, keyed for the day', async () => {
  const { handler, calls, logs } = harness();
  const response = await answer(await handler.POST(good()));
  assert.equal(response.status, 200);
  assert.deepEqual(JSON.parse(response.body), { ok: true });
  assert.equal(calls.length, 1);
  const [{ url, init, headers, body }] = calls;
  assert.equal(url, RESEND_URL);
  assert.equal(RESEND_URL, 'https://api.resend.com/emails');
  assert.equal(init.method, 'POST');
  assert.ok(init.signal instanceof AbortSignal);
  assert.equal(headers.get('authorization'), 'Bearer re_test');
  assert.equal(headers.get('content-type'), 'application/json');
  assert.match(headers.get('idempotency-key'), /^link-2026-10-01-[0-9a-f]{64}$/);
  // Resend rejects requests without a User-Agent with a 403.
  assert.equal(headers.get('user-agent'), 'annotake-link/1.0');
  assert.deepEqual(body, {
    from: 'Annotake <noreply@annotake.app>', to: [ADDRESS], subject: 'Annotake for your Mac', text: EMAIL_TEXT,
    html: EMAIL_HTML,
  });
  assert.deepEqual(logs, ['link: sent']);
});

test('one key per address per day, whatever the capitals or the accents’ encoding', async () => {
  const keyFor = async (email, day = '2026-10-01') => {
    const calls = [];
    const handler = createHandler({
      fetch: async (url, init) => { calls.push(new Headers(init.headers)); return new Response('{}', { status: 200 }); },
      env: { RESEND_API_KEY: 're_test' }, log: line => allLogs.push(line), sleep: async () => {}, today: () => day,
    });
    usedAddresses.add(email.trim());
    await handler.POST(json({ email, website: '', t: 5000 }));
    return calls[0].get('idempotency-key');
  };
  assert.equal(await keyFor('Sam@Example.com'), await keyFor('sam@example.com'));
  assert.equal(await keyFor('JÜRGEN@müller.de'), await keyFor('jürgen@müller.de'));
  assert.notEqual(await keyFor('sam@example.com'), await keyFor('sam@example.com', '2026-10-02'));
  assert.notEqual(await keyFor('sam@example.com'), await keyFor('sam@example.org'));
});

test('a filled honeypot and a too-fast send succeed quietly, with no email', async () => {
  for (const [extra, line] of [[{ website: 'https://spam.example' }, 'link: ignored honeypot'], [{ t: 200 }, 'link: ignored too fast']]) {
    const { handler, calls, logs } = harness();
    const response = await answer(await handler.POST(good(extra)));
    assert.equal(response.status, 200);
    assert.deepEqual(JSON.parse(response.body), { ok: true });
    assert.equal(calls.length, 0);
    assert.deepEqual(logs, [line]);
  }
  assert.equal(TOO_FAST_MS, 1000);
  const { handler, calls } = harness();
  assert.equal((await handler.POST(good({ t: TOO_FAST_MS }))).status, 200);
  assert.equal(calls.length, 1, 'exactly 1 s is a person');
});

test('a form post without t is checked as usual, and sends', async () => {
  const { handler, calls } = harness();
  const response = await answer(await handler.POST(form({ email: ADDRESS, website: '', t: '' })));
  assert.equal(response.status, 200);
  assert.equal(calls.length, 1);
});

test('what isn’t a plausible request answers 400, with no email', async () => {
  for (const request of [
    json({ email: 'privatesam@example', website: '', t: 5000 }),
    json({ email: `${'a'.repeat(3000)}@example.com`, website: '', t: 5000 }),
    json({ email: ADDRESS, website: '', t: 5000, padding: 'x'.repeat(3 * 1024) }),
    new Request('https://annotake.app/api/link', { method: 'POST', headers: { 'content-type': 'text/plain' }, body: ADDRESS }),
    json('{"email": "privatesam@example.com",'),
    json('"privatesam@example.com"'),
    json({ email: ['privatesam@example.com'], t: 5000 }),
  ]) {
    const { handler, calls } = harness();
    const response = await answer(await handler.POST(request));
    assert.equal(response.status, 400);
    assert.deepEqual(JSON.parse(response.body), { ok: false, reason: 'invalid' });
    assert.equal(calls.length, 0);
  }
  assert.equal(MAX_BODY_BYTES, 2048);
});

test('a declared body over the limit is refused before it is read', async () => {
  const { handler, calls } = harness();
  const request = json({ email: ADDRESS, t: 5000 }, { headers: { 'content-length': String(MAX_BODY_BYTES + 1) } });
  assert.equal((await handler.POST(request)).status, 400);
  assert.equal(calls.length, 0);
});

test('dry run checks everything and sends nothing', async () => {
  const { handler, calls, logs } = harness({ env: { EMAIL_DRY_RUN: '1', RESEND_API_KEY: 're_test' } });
  assert.equal((await handler.POST(good())).status, 200);
  assert.equal(calls.length, 0);
  assert.deepEqual(logs, ['link: dry run']);
  const invalid = harness({ env: { EMAIL_DRY_RUN: '1' } });
  assert.equal((await invalid.handler.POST(json({ email: 'nope', t: 5000 }))).status, 400);
});

test('without an API key it answers 502 and says why in the log', async () => {
  const { handler, calls, logs } = harness({ env: {} });
  const response = await answer(await handler.POST(good()));
  assert.equal(response.status, 502);
  assert.deepEqual(JSON.parse(response.body), { ok: false, reason: 'send' });
  assert.equal(calls.length, 0);
  assert.deepEqual(logs, ['link: failed not configured']);
});

test('a 500 is retried once, after 300 ms', async () => {
  const { handler, calls, sleeps, logs } = harness({ answers: [{ status: 500, json: { name: 'application_error' } }, { status: 200 }] });
  assert.equal((await handler.POST(good())).status, 200);
  assert.equal(calls.length, 2);
  assert.deepEqual(sleeps, [RETRY_PAUSE_MS]);
  assert.equal(RETRY_PAUSE_MS, 300);
  assert.deepEqual(logs, ['link: sent']);
  assert.equal(calls[0].headers.get('idempotency-key'), calls[1].headers.get('idempotency-key'));
  assert.deepEqual(calls[0].body, calls[1].body);
});

test('two network errors answer 502 after two attempts', async () => {
  const { handler, calls, sleeps, logs } = harness({ answers: ['network', 'network'] });
  const response = await answer(await handler.POST(good()));
  assert.equal(response.status, 502);
  assert.deepEqual(JSON.parse(response.body), { ok: false, reason: 'send' });
  assert.equal(calls.length, 2);
  assert.deepEqual(sleeps, [RETRY_PAUSE_MS]);
  assert.deepEqual(logs, ['link: failed network']);
});

test('two attempts that hang answer 502 after two timeouts', async () => {
  const { handler, calls, logs } = harness({ answers: ['hang', 'hang'] });
  assert.equal((await handler.POST(good())).status, 502);
  assert.equal(calls.length, 2);
  assert.deepEqual(logs, ['link: failed timeout']);
});

test('the worst case fits inside Vercel’s 10 s limit', () => {
  assert.equal(ATTEMPT_TIMEOUT_MS, 4000);
  assert.equal(MAX_RATE_WAIT_MS, 1000);
  assert.ok(ATTEMPT_TIMEOUT_MS * 2 + MAX_RATE_WAIT_MS < 10000);
  assert.ok(ATTEMPT_TIMEOUT_MS * 2 + RETRY_PAUSE_MS < 10000);
});

test('a plain rate limit waits its retry-after, at most 1 s, and tries once more', async () => {
  const rate = (after) => ({ status: 429, json: { name: 'rate_limit_exceeded' }, headers: after === undefined ? {} : { 'retry-after': after } });
  let run = harness({ answers: [rate('0.5'), { status: 200 }] });
  assert.equal((await run.handler.POST(good())).status, 200);
  assert.deepEqual(run.sleeps, [500]);

  run = harness({ answers: [rate('30'), { status: 200 }] });
  assert.equal((await run.handler.POST(good())).status, 200);
  assert.deepEqual(run.sleeps, [1000], 'capped at 1 s');

  run = harness({ answers: [rate(undefined), { status: 200 }] });
  await run.handler.POST(good());
  assert.deepEqual(run.sleeps, [1000], 'no retry-after means 1 s');

  run = harness({ answers: [rate('1'), rate('1')] });
  const response = await answer(await run.handler.POST(good()));
  assert.equal(response.status, 429);
  assert.deepEqual(JSON.parse(response.body), { ok: false, reason: 'busy' });
  assert.equal(run.calls.length, 2);
  assert.deepEqual(run.logs, ['link: busy rate limit']);
});

test('a daily or monthly quota answers busy at once', async () => {
  for (const name of ['daily_quota_exceeded', 'monthly_quota_exceeded']) {
    const { handler, calls, sleeps, logs } = harness({ answers: [{ status: 429, json: { name } }] });
    assert.equal((await handler.POST(good())).status, 429);
    assert.equal(calls.length, 1);
    assert.deepEqual(sleeps, []);
    assert.deepEqual(logs, ['link: busy quota']);
  }
});

test('a 409 about the idempotency key means the email already went today', async () => {
  for (const name of ['invalid_idempotent_request', 'concurrent_idempotent_requests']) {
    const { handler, calls, logs } = harness({ answers: [{ status: 409, json: { name } }] });
    assert.equal((await handler.POST(good())).status, 200);
    assert.equal(calls.length, 1);
    assert.deepEqual(logs, ['link: sent already today']);
  }
});

test('another 4xx, like a 422 or a 409 about something else, is a failure with no retry', async () => {
  for (const [status, name] of [[422, 'validation_error'], [403, 'validation_error'], [409, 'resource_locked']]) {
    const { handler, calls, logs } = harness({ answers: [{ status, json: { name } }] });
    const response = await answer(await handler.POST(good()));
    assert.equal(response.status, 502);
    assert.equal(calls.length, 1);
    assert.deepEqual(logs, [`link: failed rejected ${status}`]);
  }
});

test('GET answers 405', async () => {
  const { handler } = harness();
  const response = await handler.GET(new Request('https://annotake.app/api/link'));
  assert.equal(response.status, 405);
  assert.deepEqual(await response.json(), { ok: false });
});

test('a form post gets a small HTML page instead of JSON, with no inline style or script', async () => {
  const sent = await answer(await harness().handler.POST(form({ email: ADDRESS, website: '', t: '' })));
  assert.equal(sent.status, 200);
  assert.match(sent.type, /^text\/html/);
  assert.match(textOf(sent.body), /Check your inbox We sent the link to your email\. Open it on your Mac\./);
  assert.match(sent.body, /<link rel="stylesheet" href="\/assets\/site\.css">/);

  const failed = await answer(await harness({ answers: ['network', 'network'] }).handler.POST(form({ email: ADDRESS })));
  assert.equal(failed.status, 502);
  assert.match(failed.type, /^text\/html/);
  assert.match(textOf(failed.body), /We couldn’t send it right now\. Here’s the link: https:\/\/annotake\.app\/download/);

  const invalid = await answer(await harness().handler.POST(form({ email: 'privatesam@example' })));
  assert.equal(invalid.status, 400);
  assert.match(textOf(invalid.body), /That doesn’t look like an email address\./);
  assert.match(invalid.body, /<a href="\/">/);

  for (const page of [sent.body, failed.body, invalid.body]) {
    assert.doesNotMatch(page, /<script|style=|<style/i);
    assert.doesNotMatch(page, /privatesam/, 'the page never repeats the address');
  }
});

test('the email says what the plan says, word for word', () => {
  assert.equal(EMAIL_TEXT, [
    'Here’s the Annotake download link you asked for:',
    'https://annotake.app/download',
    '',
    'Open it on your Mac (macOS 15 or later). Then open the disk image and drag Annotake to Applications.',
    '',
    'This is the only email we’ll send you.',
    '',
    'Annotake, made by Fayzan Malik in Ontario, Canada',
    'https://annotake.app · Privacy: https://annotake.app/privacy',
  ].join('\n'));
  assert.match(EMAIL_HTML, /<a href="https:\/\/annotake\.app\/download"[^>]*>Download Annotake for Mac<\/a>/);
  for (const phrase of [
    'Here’s the Annotake download link you asked for:',
    'Open it on your Mac (macOS 15 or later). Then open the disk image and drag Annotake to Applications.',
    'This is the only email we’ll send you.', 'Annotake, made by Fayzan Malik in Ontario, Canada',
    'https://annotake.app/privacy',
  ]) {
    assert.ok(EMAIL_HTML.includes(phrase), phrase);
  }
});

test('an unexpected error inside the function still answers, and logs no details', async () => {
  const handler = createHandler({
    fetch: async () => { throw new Error(`boom ${ADDRESS}`); },
    env: { RESEND_API_KEY: 're_test' }, log: line => allLogs.push(line),
    sleep: async () => { throw new Error(`sleep failed for ${ADDRESS}`); }, today: () => '2026-10-01',
  });
  const response = await handler.POST(good());
  assert.equal(response.status, 502);
});

after(() => {
  // Privacy: no log line, in any test, holds an address or its local part.
  assert.ok(allLogs.length > 20, `${allLogs.length} log lines checked`);
  for (const line of allLogs) {
    assert.match(line, /^link: /, line);
    for (const address of usedAddresses) {
      const local = address.split('@')[0];
      assert.ok(!line.includes(address) && !(local.length > 3 && line.toLowerCase().includes(local.toLowerCase())),
        `"${line}" mentions ${address}`);
    }
  }
});
