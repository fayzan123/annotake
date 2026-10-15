// The unsubscribe function, with a fake fetch, sleep, and log. Nothing here reaches Resend.
import { after, test } from 'node:test';
import assert from 'node:assert/strict';
import { MAX_BODY_BYTES, createHandler } from '../../api/unsubscribe.js';
import { ATTEMPT_TIMEOUT_MS, RETRY_PAUSE_MS } from '../../api/_lib/resend.js';
import { signEmail, unsubscribeUrl } from '../../api/_lib/unsubscribe-token.js';

const SECRET = 'test-secret';
const ENV = { RESEND_CONTACTS_KEY: 're_test', UNSUBSCRIBE_SECRET: SECRET };
const CONTACT = 'https://api.resend.com/contacts/sam%40example.com';
const FORM = 'application/x-www-form-urlencoded';

/** Every log line any test wrote, checked at the end for addresses. */
const allLogs = [];
const usedAddresses = new Set(['sam@example.com', 'sam@example.org']);

/**
 * A handler whose fetch answers from `answers` in turn: { status, json, headers }, 'network' (a rejection), or 'hang'
 * (never answers until its signal aborts).
 */
function harness({ answers = [], env = ENV } = {}) {
  const calls = [], sleeps = [], logs = [];
  const fetch = async (url, init) => {
    calls.push({
      url, method: init.method, headers: new Headers(init.headers),
      body: init.body === undefined ? undefined : JSON.parse(init.body),
    });
    const answer = answers.shift() ?? { status: 200, json: { object: 'contact', id: 'contact-id' } };
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
  const handler = createHandler({ fetch, env, log, sleep: async ms => { sleeps.push(ms); }, timeoutMs: 50 });
  return { handler, calls, sleeps, logs };
}

/** The link the welcome email carries for an address, or the same link with another signature. */
function link(email = 'sam@example.com', { s } = {}) {
  usedAddresses.add(email.trim());
  const url = new URL(unsubscribeUrl(email, SECRET));
  if (s !== undefined) url.searchParams.set('s', s);
  return url.href;
}

/** sam@example.com's link, signed for another address. */
const badLink = () => link('sam@example.com', { s: signEmail('sam@example.org', SECRET) });

const get = url => new Request(url);

function post(url, { type, body } = {}) {
  return new Request(url, { method: 'POST', headers: type === undefined ? {} : { 'content-type': type }, body });
}

/** What a mail app posts for List-Unsubscribe-Post (RFC 8058). */
const oneClick = url => post(url, { type: FORM, body: 'List-Unsubscribe=One-Click' });

/** What the confirm page's form posts. */
const fromPage = url => post(url, { type: FORM, body: 'from=page' });

const ENTITIES = { '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#39;': "'" };
const fromHtml = html => html.replace(/&(amp|lt|gt|quot|#39);/g, entity => ENTITIES[entity]);

/** A page's text, as a reader sees it: no title or tags, entities decoded, whitespace collapsed. */
const textOf = html => fromHtml(html.replace(/<title>[\s\S]*?<\/title>/, '').replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ');

/** The page's form, posted as a browser posts it: to its action, with its hidden fields. */
function submit(html) {
  const action = html.match(/<form method="post" action="([^"]*)">/)?.[1];
  assert.ok(action, 'the page has a form that posts');
  const fields = [...html.matchAll(/<input type="hidden" name="([^"]*)" value="([^"]*)">/g)]
    .map(([, name, value]) => [fromHtml(name), fromHtml(value)]);
  return post(new URL(fromHtml(action), 'https://annotake.app').href, {
    type: FORM, body: new URLSearchParams(fields).toString(),
  });
}

async function answer(response) {
  return { status: response.status, type: response.headers.get('content-type'), body: await response.text() };
}

/** The time each Resend attempt is given while `run` runs: every delay AbortSignal.timeout is asked for, in order. */
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

/** Resend's answer while another request is changing the same contact. */
const LOCKED = {
  status: 409,
  json: { statusCode: 409, name: 'resource_locked', message: 'Another request is already updating this resource.' },
};

test('GET with a good link shows a page that asks first, and makes no fetch', async () => {
  const { handler, calls, logs } = harness();
  const response = await answer(await handler.GET(get(link())));
  assert.equal(response.status, 200);
  assert.equal(response.type, 'text/html; charset=utf-8');
  assert.ok(response.body.includes('Unsubscribe sam@example.com from all Annotake emails?'));
  // The form posts back to the same link, its query HTML-escaped.
  const s = signEmail('sam@example.com', SECRET);
  assert.ok(response.body.includes(`<form method="post" action="/api/unsubscribe?e=sam%40example.com&amp;s=${s}">`));
  assert.match(response.body, /<button class="btn btn-lg" type="submit">Unsubscribe<\/button>/);
  assert.equal(calls.length, 0);
  assert.deepEqual(logs, ['unsubscribe: shown']);
});

test('GET never unsubscribes: a link scanner or a prefetch can open the link any number of times', async () => {
  const { handler, calls, logs } = harness();
  for (let i = 0; i < 3; i++) assert.equal((await handler.GET(get(link()))).status, 200);
  assert.equal(calls.length, 0);
  assert.deepEqual(logs, ['unsubscribe: shown', 'unsubscribe: shown', 'unsubscribe: shown']);
});

test('the page shows the address HTML-escaped, and its form posts back to the same link', async () => {
  for (const [email, shown] of [
    ['<b>sam</b>@example.com', '&lt;b&gt;sam&lt;/b&gt;@example.com'],
    ["o'brien&co@example.com", 'o&#39;brien&amp;co@example.com'],
    ['sam+annotake@gmail.com', 'sam+annotake@gmail.com'],
    ['jürgen@müller.de', 'jürgen@müller.de'],
  ]) {
    const { handler } = harness();
    const page = await answer(await handler.GET(get(link(email))));
    assert.equal(page.status, 200, email);
    assert.ok(page.body.includes(`Unsubscribe ${shown} from all Annotake emails?`), email);
    assert.ok(textOf(page.body).includes(`Unsubscribe ${email} from all Annotake emails?`), email);
    assert.doesNotMatch(page.body, /<b>|o'brien/, email);
    const url = new URL(submit(page.body).url);
    assert.equal(url.pathname, '/api/unsubscribe', email);
    assert.equal(url.searchParams.get('e'), email);
    assert.equal(url.searchParams.get('s'), signEmail(email, SECRET), email);
  }
});

test('GET with a link that isn’t ours answers 400, with no fetch', async () => {
  const s = signEmail('sam@example.com', SECRET);
  usedAddresses.add('sam@example');
  for (const [why, url] of [
    ['another address’s signature', badLink()],
    ['another secret’s signature', link('sam@example.com', { s: signEmail('sam@example.com', 'another-secret') })],
    ['a signature cut short', link('sam@example.com', { s: s.slice(0, 40) })],
    ['this signature on another address', `https://annotake.app/api/unsubscribe?e=sam%40example.org&s=${s}`],
    ['a signed address that isn’t one', `https://annotake.app/api/unsubscribe?e=sam%40example&s=${signEmail('sam@example', SECRET)}`],
    ['no signature', 'https://annotake.app/api/unsubscribe?e=sam%40example.com'],
    ['no address', `https://annotake.app/api/unsubscribe?s=${s}`],
    ['no query', 'https://annotake.app/api/unsubscribe'],
  ]) {
    const { handler, calls, logs } = harness();
    const response = await answer(await handler.GET(get(url)));
    assert.equal(response.status, 400, why);
    assert.equal(response.type, 'text/html; charset=utf-8', why);
    assert.match(textOf(response.body), /This unsubscribe link isn’t valid\./, why);
    assert.equal(calls.length, 0, why);
    assert.deepEqual(logs, ['unsubscribe: invalid'], why);
  }
});

test('a mail app’s one-click POST unsubscribes the contact, and answers 200 with a blank body', async () => {
  const { handler, calls, logs } = harness();
  const response = await answer(await handler.POST(oneClick(link())));
  assert.equal(response.status, 200);
  assert.equal(response.body, '');
  assert.equal(calls.length, 1);
  const [{ url, method, headers, body }] = calls;
  assert.equal(url, CONTACT);
  assert.equal(method, 'PATCH');
  assert.deepEqual(body, { unsubscribed: true });
  assert.equal(headers.get('authorization'), 'Bearer re_test');
  assert.equal(headers.get('content-type'), 'application/json');
  assert.equal(headers.get('user-agent'), 'annotake-site/1.0');
  assert.deepEqual(logs, ['unsubscribe: done']);
});

test('a one-click POST with no body, an empty one, or multipart form data is the same blank 200', async () => {
  const multipart = new FormData();
  multipart.set('List-Unsubscribe', 'One-Click');
  for (const [why, request] of [
    ['no body', post(link())],
    ['an empty body', post(link(), { body: '' })],
    ['an empty form', post(link(), { type: FORM, body: '' })],
    ['multipart form data, which RFC 8058 prefers', new Request(link(), { method: 'POST', body: multipart })],
  ]) {
    const { handler, calls, logs } = harness();
    const response = await answer(await handler.POST(request));
    assert.equal(response.status, 200, why);
    assert.equal(response.body, '', why);
    assert.deepEqual(calls.map(call => `${call.method} ${call.url}`), [`PATCH ${CONTACT}`], why);
    assert.deepEqual(logs, ['unsubscribe: done'], why);
  }
});

test('the confirm page’s own form unsubscribes, and gets the page You’re unsubscribed.', async () => {
  const { handler, calls, logs } = harness();
  const confirm = await answer(await handler.GET(get(link())));
  const request = submit(confirm.body);
  assert.equal(await request.clone().text(), 'from=page');
  const response = await answer(await handler.POST(request));
  assert.equal(response.status, 200);
  assert.equal(response.type, 'text/html; charset=utf-8');
  assert.match(textOf(response.body), /You’re unsubscribed\./);
  assert.deepEqual(calls.map(call => `${call.method} ${call.url}`), [`PATCH ${CONTACT}`]);
  assert.deepEqual(calls[0].body, { unsubscribed: true });
  assert.deepEqual(logs, ['unsubscribe: shown', 'unsubscribe: done']);
});

test('only the confirm page’s from=page gets a page back; the body never decides whether to unsubscribe', async () => {
  for (const [why, type, body, page] of [
    ['from=page', FORM, 'from=page', true],
    ['from=page among other fields', FORM, 'List-Unsubscribe=One-Click&from=page', true],
    ['from=page, with a charset', `${FORM}; charset=UTF-8`, 'from=page', true],
    ['from=elsewhere', FORM, 'from=elsewhere', false],
    ['from=page as plain text', 'text/plain', 'from=page', false],
    ['from=page as JSON', 'application/json', '{"from":"page"}', false],
    ['another one-click value', FORM, 'List-Unsubscribe=Nope', false],
  ]) {
    const { handler, calls, logs } = harness();
    const response = await answer(await handler.POST(post(link(), { type, body })));
    assert.equal(response.status, 200, why);
    if (page) assert.match(textOf(response.body), /You’re unsubscribed\./, why);
    else assert.equal(response.body, '', why);
    assert.equal(calls.length, 1, `${why} unsubscribes`);
    assert.deepEqual(logs, ['unsubscribe: done'], why);
  }
});

test('a body over 2 KB isn’t read, and still unsubscribes, with a blank answer', async () => {
  assert.equal(MAX_BODY_BYTES, 2048);
  for (const [why, request] of [
    ['a long body', post(link(), { type: FORM, body: `from=page&padding=${'x'.repeat(3 * 1024)}` })],
    ['a declared length over the limit', new Request(link(), {
      method: 'POST', headers: { 'content-type': FORM, 'content-length': String(MAX_BODY_BYTES + 1) }, body: 'from=page',
    })],
  ]) {
    const { handler, calls, logs } = harness();
    const response = await answer(await handler.POST(request));
    assert.equal(response.status, 200, why);
    assert.equal(response.body, '', why);
    assert.deepEqual(calls.map(call => `${call.method} ${call.url}`), [`PATCH ${CONTACT}`], why);
    assert.deepEqual(logs, ['unsubscribe: done'], why);
  }
});

test('the link is read from the query alone: an address and a signature in the body aren’t a link', async () => {
  const { handler, calls, logs } = harness();
  const body = new URLSearchParams({ e: 'sam@example.com', s: signEmail('sam@example.com', SECRET), from: 'page' });
  const response = await answer(await handler.POST(post('https://annotake.app/api/unsubscribe', { type: FORM, body: body.toString() })));
  assert.equal(response.status, 400);
  assert.equal(calls.length, 0);
  assert.deepEqual(logs, ['unsubscribe: invalid']);
});

test('a mixed-case or padded address unsubscribes one contact, keyed lowercased', async () => {
  // The welcome email's link for "  Sam@Example.COM ".
  let run = harness();
  assert.equal((await run.handler.POST(oneClick(link('  Sam@Example.COM ')))).status, 200);
  assert.deepEqual(run.calls.map(call => call.url), [CONTACT]);

  // A link whose address kept its capitals carries the same signature, and reaches the same contact.
  const capitals = `https://annotake.app/api/unsubscribe?e=Sam%40Example.COM&s=${signEmail('sam@example.com', SECRET)}`;
  run = harness();
  const shown = await answer(await run.handler.GET(get(capitals)));
  assert.equal(shown.status, 200);
  assert.ok(shown.body.includes('Unsubscribe sam@example.com from all Annotake emails?'));
  assert.equal((await run.handler.POST(oneClick(capitals))).status, 200);
  assert.deepEqual(run.calls.map(call => call.url), [CONTACT]);
});

test('a plus address works even when the link’s + arrives unencoded', async () => {
  const email = 'sam+annotake@gmail.com';
  usedAddresses.add(email);
  const s = signEmail(email, SECRET);
  for (const url of [link(email), `https://annotake.app/api/unsubscribe?e=sam+annotake%40gmail.com&s=${s}`]) {
    const { handler, calls } = harness();
    const shown = await answer(await handler.GET(get(url)));
    assert.ok(shown.body.includes('Unsubscribe sam+annotake@gmail.com from all Annotake emails?'), url);
    assert.equal((await handler.POST(oneClick(url))).status, 200, url);
    assert.deepEqual(calls.map(call => call.url), ['https://api.resend.com/contacts/sam%2Bannotake%40gmail.com'], url);
  }
});

test('a capital whose accent composes only once it’s small still gets a link that works', async () => {
  for (const [email, contact] of [
    // J and a combining caron key to ǰ, one character (U+01F0), which is also the key of that key, as the check finds.
    ['J\u{30C}ohn@example.com', '%C7%B0ohn%40example.com'],
    // İ and a line below key to i, the line below, then the dot above (U+0331, U+0307).
    ['\u{130}\u{331}sa@example.com', 'i%CC%B1%CC%87sa%40example.com'],
  ]) {
    const { handler, calls, logs } = harness();
    assert.equal((await handler.GET(get(link(email)))).status, 200, email);
    assert.equal((await handler.POST(oneClick(link(email)))).status, 200, email);
    const patch = `PATCH https://api.resend.com/contacts/${contact}`;
    assert.deepEqual(calls.map(call => `${call.method} ${call.url}`), [patch], email);
    assert.deepEqual(logs, ['unsubscribe: shown', 'unsubscribe: done'], email);
  }
});

test('a contact Resend doesn’t have still answers as unsubscribed: there’s nothing left to email', async () => {
  for (const [why, request, blank] of [['one-click', oneClick, true], ['the page’s form', fromPage, false]]) {
    const { handler, calls, sleeps, logs } = harness({
      answers: [{ status: 404, json: { statusCode: 404, name: 'not_found', message: 'Contact not found' } }],
    });
    const response = await answer(await handler.POST(request(link())));
    assert.equal(response.status, 200, why);
    if (blank) assert.equal(response.body, '', why);
    else assert.match(textOf(response.body), /You’re unsubscribed\./, why);
    assert.equal(calls.length, 1, `${why}: no retry`);
    assert.deepEqual(sleeps, [], why);
    assert.deepEqual(logs, ['unsubscribe: done already gone'], why);
  }
});

test('POST with a link that isn’t ours answers 400, with no fetch', async () => {
  for (const [why, request] of [
    ['one-click', oneClick(badLink())],
    ['no body', post(badLink())],
    ['the page’s form', fromPage(badLink())],
    ['no signature', oneClick('https://annotake.app/api/unsubscribe?e=sam%40example.com')],
    ['no query', oneClick('https://annotake.app/api/unsubscribe')],
  ]) {
    const { handler, calls, logs } = harness();
    const response = await answer(await handler.POST(request));
    assert.equal(response.status, 400, why);
    assert.equal(response.type, 'text/html; charset=utf-8', why);
    assert.match(textOf(response.body), /This unsubscribe link isn’t valid\./, why);
    assert.equal(calls.length, 0, why);
    assert.deepEqual(logs, ['unsubscribe: invalid'], why);
  }
});

test('a 500 is retried once, after 300 ms, and the retry’s success stands', async () => {
  const { handler, calls, sleeps, logs } = harness({
    answers: [{ status: 500, json: { name: 'application_error' } }, { status: 200, json: { object: 'contact' } }],
  });
  const response = await answer(await handler.POST(oneClick(link())));
  assert.equal(response.status, 200);
  assert.equal(response.body, '');
  assert.equal(calls.length, 2);
  assert.deepEqual(sleeps, [RETRY_PAUSE_MS]);
  assert.deepEqual(logs, ['unsubscribe: done']);
});

test('a contact locked by another request, say a second click, is tried again after 300 ms', async () => {
  for (const [why, request, blank] of [['one-click', oneClick, true], ['the page’s form', fromPage, false]]) {
    const answers = [LOCKED, { status: 200, json: { object: 'contact' } }];
    const { handler, calls, sleeps, logs } = harness({ answers });
    const response = await answer(await handler.POST(request(link())));
    assert.equal(response.status, 200, why);
    if (blank) assert.equal(response.body, '', why);
    else assert.match(textOf(response.body), /You’re unsubscribed\./, why);
    assert.deepEqual(calls.map(call => `${call.method} ${call.url}`), [`PATCH ${CONTACT}`, `PATCH ${CONTACT}`], why);
    assert.deepEqual(sleeps, [RETRY_PAUSE_MS], why);
    assert.deepEqual(logs, ['unsubscribe: done'], why);
  }
});

test('when Resend fails, it answers 502 with a page that says to try again, and logs why', async () => {
  const server = { status: 500, json: { name: 'application_error' } };
  const rate = { status: 429, json: { name: 'rate_limit_exceeded' } };
  for (const [answers, reason, attempts] of [
    [[server, server], 'server', 2],
    [['network', 'network'], 'network', 2],
    [['hang', 'hang'], 'timeout', 2],
    [[rate, rate], 'rate', 2],
    [[LOCKED, LOCKED], 'rejected', 2],
    [[{ status: 429, json: { name: 'daily_quota_exceeded' } }], 'quota', 1],
    [[{ status: 401, json: { name: 'restricted_api_key' } }], 'rejected', 1],
    [[{ status: 422, json: { name: 'validation_error' } }], 'rejected', 1],
  ]) {
    for (const request of [oneClick, fromPage]) {
      const { handler, calls, logs } = harness({ answers: [...answers] });
      const response = await answer(await handler.POST(request(link())));
      assert.equal(response.status, 502, reason);
      assert.equal(response.type, 'text/html; charset=utf-8', reason);
      assert.match(textOf(response.body), /We couldn’t unsubscribe you right now\. Try the link again in a few minutes\./, reason);
      assert.equal(calls.length, attempts, reason);
      assert.deepEqual(logs, [`unsubscribe: failed ${reason}`], reason);
    }
  }
});

test('EMAIL_DRY_RUN=1 checks the link and calls nothing, even without a Resend key', async () => {
  for (const env of [{ ...ENV, EMAIL_DRY_RUN: '1' }, { UNSUBSCRIBE_SECRET: SECRET, EMAIL_DRY_RUN: '1' }]) {
    const { handler, calls, logs } = harness({ env });
    const blank = await answer(await handler.POST(oneClick(link())));
    assert.equal(blank.status, 200);
    assert.equal(blank.body, '');
    const page = await answer(await handler.POST(fromPage(link())));
    assert.equal(page.status, 200);
    assert.match(textOf(page.body), /You’re unsubscribed\./);
    assert.equal((await handler.GET(get(link()))).status, 200);
    assert.equal((await handler.GET(get(badLink()))).status, 400);
    assert.equal((await handler.POST(oneClick(badLink()))).status, 400);
    assert.equal(calls.length, 0);
    assert.deepEqual(logs, [
      'unsubscribe: dry run', 'unsubscribe: dry run', 'unsubscribe: shown', 'unsubscribe: invalid', 'unsubscribe: invalid',
    ]);
  }
});

test('without UNSUBSCRIBE_SECRET no link can be checked: GET and POST answer 502 and log why', async () => {
  for (const env of [
    { RESEND_CONTACTS_KEY: 're_test' }, { RESEND_CONTACTS_KEY: 're_test', UNSUBSCRIBE_SECRET: '' }, { EMAIL_DRY_RUN: '1' },
  ]) {
    for (const request of [get(link()), oneClick(link()), fromPage(link()), get(badLink())]) {
      const { handler, calls, logs } = harness({ env });
      const response = await answer(await handler[request.method](request));
      const why = `${JSON.stringify(env)} ${request.method}`;
      assert.equal(response.status, 502, why);
      assert.match(textOf(response.body), /We couldn’t unsubscribe you right now\./, why);
      assert.equal(calls.length, 0, why);
      assert.deepEqual(logs, ['unsubscribe: failed not configured'], why);
    }
  }
});

test('without RESEND_CONTACTS_KEY the page still shows, and the unsubscribe answers 502 and logs why', async () => {
  for (const env of [{ UNSUBSCRIBE_SECRET: SECRET }, { UNSUBSCRIBE_SECRET: SECRET, RESEND_CONTACTS_KEY: '' }]) {
    const { handler, calls, logs } = harness({ env });
    assert.equal((await handler.GET(get(link()))).status, 200);
    for (const request of [oneClick(link()), fromPage(link())]) {
      const response = await answer(await handler.POST(request));
      assert.equal(response.status, 502);
      assert.match(textOf(response.body), /We couldn’t unsubscribe you right now\./);
    }
    assert.equal((await handler.POST(oneClick(badLink()))).status, 400, 'a bad link is still a bad link');
    assert.equal(calls.length, 0);
    assert.deepEqual(logs, [
      'unsubscribe: shown', 'unsubscribe: failed not configured', 'unsubscribe: failed not configured',
      'unsubscribe: invalid',
    ]);
  }
});

test('each Resend attempt gets ATTEMPT_TIMEOUT_MS as deployed, or the handler’s timeoutMs', async () => {
  // Built as the module builds its GET and POST for Vercel: no timeoutMs.
  const logs = [];
  const deployed = createHandler({
    fetch: async () => new Response('{}', { status: 200 }), env: ENV, sleep: async () => {},
    log: line => { logs.push(line); allLogs.push(line); },
  });
  assert.deepEqual(await attemptTimes(() => deployed.POST(oneClick(link()))), [ATTEMPT_TIMEOUT_MS]);
  assert.deepEqual(logs, ['unsubscribe: done']);

  const { handler } = harness({ answers: ['hang', 'hang'] });
  const times = await attemptTimes(() => handler.POST(oneClick(link())));
  assert.deepEqual(times, [50, 50], 'the harness’s 50 ms, for each attempt');
});

test('every page is in the site’s style, with no inline script or style, and only the confirm page shows the address', async () => {
  const pages = {
    confirm: await answer(await harness().handler.GET(get(link()))),
    invalid: await answer(await harness().handler.GET(get(badLink()))),
    done: await answer(await harness().handler.POST(fromPage(link()))),
    failed: await answer(await harness({ answers: ['network', 'network'] }).handler.POST(fromPage(link()))),
  };
  assert.match(pages.confirm.body, /<title>Unsubscribe · Annotake<\/title>/, 'the title holds no address');
  for (const [kind, page] of Object.entries(pages)) {
    assert.equal(page.type, 'text/html; charset=utf-8', kind);
    assert.match(page.body, /^<!DOCTYPE html>\n<html lang="en">/, kind);
    assert.match(page.body, /<link rel="stylesheet" href="\/assets\/site\.css">/, kind);
    assert.match(page.body, /<link rel="icon" href="\/assets\/img\/favicon\.svg" type="image\/svg\+xml">/, kind);
    assert.match(page.body, /<main class="message">/, kind);
    // The link's URL holds the address: no Referer carries it on, and no search engine keeps the page.
    assert.match(page.body, /<meta name="referrer" content="no-referrer">/, kind);
    assert.match(page.body, /<meta name="robots" content="noindex">/, kind);
    assert.match(page.body, /<a href="\/">annotake\.app<\/a>/, kind);
    assert.doesNotMatch(page.body, /<script|style=|<style/i, kind);
    if (kind !== 'confirm') assert.doesNotMatch(page.body, /sam@|sam%40/, `the ${kind} page never repeats the address`);
  }
});

test('an unexpected error still answers 502, and logs no details', async () => {
  const address = 'privatesam@example.com';
  const logs = [];
  const log = line => { logs.push(line); allLogs.push(line); };
  // A fetch and a pause that fail with the address in their messages: Resend's request sorts it as no answer.
  const leaky = createHandler({
    fetch: async () => { throw new Error(`boom ${address}`); }, env: ENV, log,
    sleep: async () => { throw new Error(`no timers for ${address}`); }, timeoutMs: 50,
  });
  assert.equal((await leaky.POST(oneClick(link(address)))).status, 502);
  // A failure inside the function itself.
  const broken = createHandler({
    fetch: async () => new Response('{}'), log, sleep: async () => {},
    env: { get UNSUBSCRIBE_SECRET() { throw new Error(`no secret for ${address}`); } },
  });
  assert.equal((await broken.GET(get(link(address)))).status, 502);
  assert.equal((await broken.POST(oneClick(link(address)))).status, 502);
  assert.deepEqual(logs, ['unsubscribe: failed network', 'unsubscribe: failed error Error', 'unsubscribe: failed error Error']);
});

after(() => {
  // Privacy: no log line, in any test, holds an address, its local part, or its encoded form.
  assert.ok(allLogs.length > 40, `${allLogs.length} log lines checked`);
  for (const line of allLogs) {
    assert.match(line, /^unsubscribe: (shown|done|done already gone|invalid|dry run|failed \S.*)$/, line);
    const lower = line.toLowerCase();
    for (const address of usedAddresses) {
      const local = address.split('@')[0].toLowerCase();
      const key = address.toLowerCase();
      assert.ok(
        !lower.includes(key) && !lower.includes(encodeURIComponent(key).toLowerCase())
          && !(local.length > 3 && lower.includes(local)),
        `"${line}" mentions ${address}`,
      );
    }
  }
});
