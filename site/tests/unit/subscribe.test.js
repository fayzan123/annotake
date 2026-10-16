// The subscribe function, with a fake fetch, sleep, clock, and log. Nothing here reaches Resend. The fake answers by
// method and path, in the shapes of Resend's API reference (read 2026-10-15):
// - Retrieve Contact, GET /contacts/{email}: the contact, with `unsubscribed` and its properties, but no topics;
// - Retrieve Contact Topics, GET /contacts/{email}/topics: { object: 'list', has_more, data: [{ id, name, description,
//   subscription }] }, every topic at once when no limit is given;
// - Create Contact, POST /contacts: { email, properties, segments: [{ id }], topics: [{ id, subscription }] } in, and
//   Update Contact, PATCH /contacts/{email}: { properties } in; both { object: 'contact', id } out;
// - Update Contact Topics, PATCH /contacts/{email}/topics: a bare array of { id, subscription } in,
//   { object: 'contact_topics', id } out;
// - Send Email, POST /emails: { id }.
// Create Broadcast requires a segment_id, and takes an optional topic_id that only narrows the segment down, so a
// contact in no segment gets no broadcast.
import { after, test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { FROM, MAX_APP_VERSION_LENGTH, MAX_BODY_BYTES, REPLY_TO, createHandler } from '../../api/subscribe.js';
import consent from '../../api/_lib/consent.json' with { type: 'json' };
import appRequest from '../subscribe-request.json' with { type: 'json' };
import { ATTEMPT_TIMEOUT_MS, RESEND_BASE, RETRY_PAUSE_MS } from '../../api/_lib/resend.js';
import { unsubscribeUrl, verifyEmail } from '../../api/_lib/unsubscribe-token.js';
import { welcomeEmail } from '../../api/_lib/welcome.js';
import { emailKey, isPlausibleEmail } from '../../assets/email.js';

const SECRET = 'test-secret';
// The topic and segment ids in Resend's examples.
const NOTICES = '07d84122-7224-4881-9c31-1c048e204602';
const NEWS = 'b6d24b8e-af0b-4c3c-be0c-359bbd97381e';
const SEGMENT = '78261eea-8f8b-4381-83c6-79fa7120f1cf';
const MAILING = 'PO Box 1234, Toronto ON M5W 1A1';
const ENV = Object.freeze({
  RESEND_CONTACTS_KEY: 're_contacts', RESEND_SEGMENT: SEGMENT, RESEND_TOPIC_NOTICES: NOTICES, RESEND_TOPIC_NEWS: NEWS,
  UNSUBSCRIBE_SECRET: SECRET, MAILING_ADDRESS: MAILING,
});
/** The injected clock. consent_at is its time, in UTC. */
const NOW = new Date(Date.UTC(2026, 9, 15, 19, 30, 5, 123));
const CONTACT = '/contacts/sam%40example.com';
const LOOKUP = `GET ${CONTACT}`;
const TOPICS = `GET ${CONTACT}/topics`;
const RECORD = `PATCH ${CONTACT}`;
const OPT_IN = `PATCH ${CONTACT}/topics`;

/** The consent record the request below makes. */
const PROPERTIES = {
  consent_at: '2026-10-15T19:30:05.123Z', consent_wording: 'consent-2026-10-15', consent_source: 'app',
  app_version: '0.3.0 (120)',
};

/** Every log line any test wrote, checked at the end for addresses. */
const allLogs = [];
const usedAddresses = new Set(['sam@example.com', 'privatesam@example.com']);

const NOT_FOUND = { status: 404, json: { statusCode: 404, name: 'not_found', message: 'Contact not found' } };
const SERVER = { status: 500, json: { statusCode: 500, name: 'application_error', message: 'An unexpected error occurred.' } };
const RATE = { status: 429, json: { statusCode: 429, name: 'rate_limit_exceeded', message: 'Too many requests.' } };
const LOCKED = {
  status: 409,
  json: { statusCode: 409, name: 'resource_locked', message: 'Another request is already updating this resource.' },
};
const quota = name => ({ status: 429, json: { statusCode: 429, name, message: 'You have exceeded your quota.' } });

/** A contact as Retrieve Contact answers it. */
function contact({ unsubscribed = false } = {}) {
  return {
    status: 200,
    json: {
      object: 'contact', id: 'e169aa45-1ecf-4183-9955-b1499d5701d3', email: 'sam@example.com',
      created_at: '2026-10-06 23:47:56.678+00', unsubscribed,
      properties: { consent_wording: { value: 'consent-2026-10-15', type: 'string' } },
    },
  };
}

const TOPIC_NAMES = {
  [NOTICES]: ['Important notices', 'Security fixes and important changes to Annotake.'],
  [NEWS]: ['Feedback and news', 'Feedback requests and news.'],
};

/** The contact's topics as Retrieve Contact Topics answers them, from [id, subscription] pairs. */
function topics(...subscriptions) {
  const data = subscriptions.map(([id, subscription]) => {
    const [name, description] = TOPIC_NAMES[id];
    return { id, name, description, subscription };
  });
  return { status: 200, json: { object: 'list', has_more: false, data } };
}

/** What Resend answers a route no test set: a new address, a list of its topics as created, and success. */
function defaultAnswer(route) {
  if (route === 'POST /contacts') return { status: 200, json: { object: 'contact', id: '479e3145-dd38-476b-932c-529ceb705947' } };
  if (route === 'POST /emails') return { status: 200, json: { id: '49a3999c-0ce1-4ea6-ab68-afcd6dc2e794' } };
  if (/^GET \/contacts\/[^/]+$/.test(route)) return NOT_FOUND;
  if (/^GET \/contacts\/[^/]+\/topics$/.test(route)) return topics([NOTICES, 'opt_in'], [NEWS, 'opt_out']);
  if (/^PATCH \/contacts\/[^/]+$/.test(route)) {
    return { status: 200, json: { object: 'contact', id: 'e169aa45-1ecf-4183-9955-b1499d5701d3' } };
  }
  if (/^PATCH \/contacts\/[^/]+\/topics$/.test(route)) return { status: 200, json: { object: 'contact_topics', id: NEWS } };
  return { status: 404, json: { statusCode: 404, name: 'not_found', message: 'The requested endpoint does not exist.' } };
}

/**
 * A handler whose fetch records each call and answers by its route ("GET /contacts/sam%40example.com"): from `routes`
 * when it names the route, a list in turn with its last answer repeating, and otherwise from defaultAnswer. An answer
 * is { status, json, text, headers }, 'network' (a rejection), or 'hang' (no answer until its signal aborts).
 */
function harness({ routes = {}, env = ENV } = {}) {
  const calls = [], sleeps = [], logs = [];
  const queues = new Map(Object.entries(routes).map(([route, answers]) => [route, [answers].flat()]));
  const fetch = async (url, init) => {
    const route = `${init.method} ${url.slice(RESEND_BASE.length)}`;
    calls.push({
      url, route, headers: new Headers(init.headers), body: init.body === undefined ? undefined : JSON.parse(init.body),
    });
    const queue = queues.get(route);
    const answer = queue ? (queue.length > 1 ? queue.shift() : queue[0]) : defaultAnswer(route);
    if (answer === 'network') throw new TypeError('fetch failed');
    if (answer === 'hang') {
      // A real hanging request holds a socket open, which keeps Node running; the timer stands in for it.
      return new Promise((resolve, reject) => {
        const socket = setTimeout(() => {}, 60_000);
        init.signal.addEventListener('abort', () => { clearTimeout(socket); reject(init.signal.reason); });
      });
    }
    return new Response(answer.text ?? JSON.stringify(answer.json ?? {}), { status: answer.status, headers: answer.headers });
  };
  const log = line => { logs.push(line); allLogs.push(line); };
  const handler = createHandler({ fetch, env, log, sleep: async ms => { sleeps.push(ms); }, now: () => NOW, timeoutMs: 50 });
  return { handler, calls, sleeps, logs, routes: () => calls.map(call => call.route) };
}

/** What the app sends: its four fields, as JSON. */
const FIELDS = Object.freeze({ email: '  Sam@Example.COM ', news: false, consent: 'consent-2026-10-15', appVersion: '0.3.0 (120)' });

/**
 * The app's request, word for word: EmailSignupTests checks the app sends this text, so a field renamed on one side
 * alone fails one side's tests. FIELDS stays apart, for its capitals and padding.
 */
const APP_REQUEST = appRequest.body;

/** A POST to /api/subscribe. A body that isn't text is sent as JSON. */
function post(body, { type = 'application/json', headers = {} } = {}) {
  if (typeof body?.email === 'string' && body.email.trim()) usedAddresses.add(body.email.trim());
  return new Request('https://annotake.app/api/subscribe', {
    method: 'POST', headers: { 'content-type': type, ...headers }, body: typeof body === 'string' ? body : JSON.stringify(body),
  });
}

/** The app's request, with `extra` fields changed. */
const good = (extra = {}, options = {}) => post({ ...FIELDS, ...extra }, options);

async function answer(response) {
  return { status: response.status, type: response.headers.get('content-type'), json: await response.json() };
}

const sha256 = text => createHash('sha256').update(text).digest('hex');

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

test('a new address: the lookup, then the contact with its topics and consent record, then the welcome', async () => {
  const { handler, calls, logs, routes } = harness();
  const response = await answer(await handler.POST(good()));
  assert.equal(response.status, 200);
  assert.equal(response.type, 'application/json');
  assert.deepEqual(response.json, { ok: true });
  assert.deepEqual(routes(), [LOOKUP, 'POST /contacts', 'POST /emails']);
  const [lookup, create, welcome] = calls;
  assert.equal(lookup.url, 'https://api.resend.com/contacts/sam%40example.com');
  assert.equal(lookup.body, undefined);

  // From "  Sam@Example.COM ": one contact, keyed lowercased, in the segment every broadcast is sent to. Only Feedback
  // and news waits for the box. No `unsubscribed`: a new contact is subscribed anyway, and subscribe.js never sets
  // unsubscribed: false, in case Resend ever applied a create to a contact that exists (its reference doesn't say).
  assert.deepEqual(create.body, {
    email: 'sam@example.com', properties: PROPERTIES, segments: [{ id: SEGMENT }],
    topics: [{ id: NOTICES, subscription: 'opt_in' }, { id: NEWS, subscription: 'opt_out' }],
  });

  const unsubscribe = unsubscribeUrl('sam@example.com', SECRET);
  assert.deepEqual(welcome.body, {
    from: 'Fayzan from Annotake <hello@annotake.app>', to: ['sam@example.com'], reply_to: 'fayzanm786@gmail.com',
    ...welcomeEmail({ news: false, address: MAILING, unsubscribe }),
    headers: { 'List-Unsubscribe': `<${unsubscribe}>`, 'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click' },
  });
  assert.equal(welcome.body.subject, 'Welcome to Annotake');
  assert.equal(FROM, 'Fayzan from Annotake <hello@annotake.app>');
  // The header's link, in RFC 2369's angle brackets, is one the unsubscribe function accepts for this address.
  const link = new URL(welcome.body.headers['List-Unsubscribe'].match(/^<(.+)>$/)[1]);
  assert.equal(link.searchParams.get('e'), 'sam@example.com');
  assert.equal(verifyEmail(link.searchParams.get('e'), link.searchParams.get('s'), SECRET), true);
  // One welcome per address: Resend sends a repeat of the key only once.
  assert.equal(welcome.headers.get('idempotency-key'), `welcome-${sha256('sam@example.com')}`);
  assert.equal(lookup.headers.get('idempotency-key'), null);
  assert.equal(create.headers.get('idempotency-key'), null);

  for (const call of calls) {
    assert.ok(call.url.startsWith('https://api.resend.com/'), call.url);
    assert.equal(call.headers.get('authorization'), 'Bearer re_contacts', call.route);
    assert.equal(call.headers.get('user-agent'), 'annotake-site/1.0', call.route);
  }
  assert.deepEqual(logs, ['subscribe: added']);
});

test('the app’s request, as the app’s own tests pin it, adds the contact, and passes dry run', async () => {
  const { handler, calls, logs, routes } = harness();
  assert.equal((await handler.POST(post(APP_REQUEST))).status, 200);
  assert.deepEqual(routes(), [LOOKUP, 'POST /contacts', 'POST /emails']);
  assert.equal(calls[1].body.email, 'sam@example.com');
  assert.deepEqual(calls[1].body.properties, PROPERTIES);
  assert.deepEqual(calls[1].body.topics, [{ id: NOTICES, subscription: 'opt_in' }, { id: NEWS, subscription: 'opt_in' }]);
  assert.deepEqual(logs, ['subscribe: added']);
  const dry = harness({ env: { EMAIL_DRY_RUN: '1' } });
  assert.equal((await dry.handler.POST(post(APP_REQUEST))).status, 200);
  assert.deepEqual(dry.logs, ['subscribe: dry run']);
});

test('a new address with the box ticked is on Feedback and news, and the welcome says so', async () => {
  const { handler, calls, logs, routes } = harness();
  assert.equal((await handler.POST(good({ news: true }))).status, 200);
  assert.deepEqual(routes(), [LOOKUP, 'POST /contacts', 'POST /emails']);
  assert.deepEqual(calls[1].body.topics, [{ id: NOTICES, subscription: 'opt_in' }, { id: NEWS, subscription: 'opt_in' }]);
  assert.deepEqual(calls[1].body.properties, PROPERTIES);
  assert.deepEqual(calls[1].body.segments, [{ id: SEGMENT }]);
  assert.equal(Object.hasOwn(calls[1].body, 'unsubscribed'), false);
  const unsubscribe = unsubscribeUrl('sam@example.com', SECRET);
  assert.equal(calls[2].body.text, welcomeEmail({ news: true, address: MAILING, unsubscribe }).text);
  assert.ok(calls[2].body.text.includes('important notices, plus feedback requests and news'));
  assert.deepEqual(logs, ['subscribe: added']);
});

test('an address that unsubscribed stays unsubscribed: nothing changes, no welcome, and the answer is 200', async () => {
  for (const news of [false, true]) {
    const { handler, logs, routes } = harness({ routes: { [LOOKUP]: contact({ unsubscribed: true }) } });
    const response = await answer(await handler.POST(good({ news })));
    assert.equal(response.status, 200, `news: ${news}`);
    assert.deepEqual(response.json, { ok: true });
    assert.deepEqual(routes(), [LOOKUP], `news: ${news}`);
    assert.deepEqual(logs, ['subscribe: kept unsubscribed'], `news: ${news}`);
  }
});

test('anything but a clear unsubscribed: false counts as unsubscribed, and changes nothing', async () => {
  const { json } = contact();
  for (const [why, found] of [
    ['no unsubscribed', { status: 200, json: { ...json, unsubscribed: undefined } }],
    ['unsubscribed as text', { status: 200, json: { ...json, unsubscribed: 'false' } }],
    ['unsubscribed null', { status: 200, json: { ...json, unsubscribed: null } }],
    ['an empty answer', { status: 200, text: '' }],
    ['an answer that isn’t JSON', { status: 200, text: 'OK' }],
  ]) {
    const { handler, logs, routes } = harness({ routes: { [LOOKUP]: found } });
    assert.equal((await handler.POST(good({ news: true }))).status, 200, why);
    assert.deepEqual(routes(), [LOOKUP], why);
    assert.deepEqual(logs, ['subscribe: kept unsubscribed'], why);
  }
});

test('a subscribed address without the box changes nothing: no topic call, and no welcome', async () => {
  const { handler, logs, routes } = harness({ routes: { [LOOKUP]: contact() } });
  const response = await answer(await handler.POST(good({ news: false })));
  assert.equal(response.status, 200);
  assert.deepEqual(response.json, { ok: true });
  assert.deepEqual(routes(), [LOOKUP]);
  assert.deepEqual(logs, ['subscribe: kept']);
});

test('a subscribed address with the box, not yet on Feedback and news: the consent record, then the topic', async () => {
  for (const [why, list] of [
    ['opted out of it', topics([NOTICES, 'opt_in'], [NEWS, 'opt_out'])],
    ['not in the list', topics([NOTICES, 'opt_in'])],
    ['no topics at all', topics()],
    ['out of Important notices too', topics([NOTICES, 'opt_out'], [NEWS, 'opt_out'])],
    ['a list Resend answered without data', { status: 200, json: { object: 'list', has_more: false } }],
    ['an empty answer', { status: 200, text: '' }],
  ]) {
    const { handler, calls, logs, routes } = harness({ routes: { [LOOKUP]: contact(), [TOPICS]: list } });
    const response = await answer(await handler.POST(good({ news: true })));
    assert.equal(response.status, 200, why);
    assert.deepEqual(response.json, { ok: true }, why);
    assert.deepEqual(routes(), [LOOKUP, TOPICS, RECORD, OPT_IN], why);
    assert.equal(calls[1].body, undefined, why);
    assert.deepEqual(calls[2].body, { properties: PROPERTIES }, why);
    assert.deepEqual(calls[3].body, [{ id: NEWS, subscription: 'opt_in' }], why);
    assert.deepEqual(logs, ['subscribe: news added'], why);
  }
});

test('a subscribed address already on Feedback and news changes nothing', async () => {
  for (const list of [topics([NOTICES, 'opt_in'], [NEWS, 'opt_in']), topics([NEWS, 'opt_in'], [NOTICES, 'opt_out'])]) {
    const { handler, logs, routes } = harness({ routes: { [LOOKUP]: contact(), [TOPICS]: list } });
    assert.equal((await handler.POST(good({ news: true }))).status, 200);
    assert.deepEqual(routes(), [LOOKUP, TOPICS]);
    assert.deepEqual(logs, ['subscribe: kept']);
  }
});

test('the consent record comes before the topic, so the app’s retry after a partial success redoes both', async () => {
  // The topic fails after the record is written: the retry finds the topic still out, and writes both again.
  const run = harness({
    routes: { [LOOKUP]: contact(), [OPT_IN]: [SERVER, SERVER, { status: 200, json: { object: 'contact_topics', id: NEWS } }] },
  });
  const failed = await answer(await run.handler.POST(good({ news: true })));
  assert.equal(failed.status, 502);
  assert.deepEqual(failed.json, { ok: false, reason: 'send' });
  assert.deepEqual(run.routes(), [LOOKUP, TOPICS, RECORD, OPT_IN, OPT_IN]);
  const retried = await answer(await run.handler.POST(good({ news: true })));
  assert.equal(retried.status, 200);
  assert.deepEqual(run.routes().slice(5), [LOOKUP, TOPICS, RECORD, OPT_IN]);
  assert.deepEqual(run.calls[7].body, { properties: PROPERTIES });
  assert.deepEqual(run.logs, ['subscribe: failed server', 'subscribe: news added']);

  // A record that fails leaves the topic alone: nobody joins Feedback and news without the record of their consent.
  const record = harness({ routes: { [LOOKUP]: contact(), [RECORD]: [SERVER, SERVER] } });
  assert.equal((await record.handler.POST(good({ news: true }))).status, 502);
  assert.deepEqual(record.routes(), [LOOKUP, TOPICS, RECORD, RECORD]);
  assert.deepEqual(record.logs, ['subscribe: failed server']);
});

test('the consent record names the version the app showed, which needn’t be the current one', async () => {
  // A wording change adds a version and moves current, and a copy not yet updated still sends the id of the wording it
  // shows: it's accepted, and it's what the record names, since that record is the proof of consent.
  const shipped = consent.current;
  const versions = Object.keys(consent.versions);
  const next = 'consent-test-next';
  assert.ok(!versions.includes(next));
  // The same module object subscribe.js imported, changed only for this test.
  consent.versions[next] = { ...consent.versions[shipped], box: 'Also email me news' };
  consent.current = next;
  try {
    for (const id of [shipped, next]) {
      const created = harness();
      assert.equal((await created.handler.POST(good({ news: true, consent: id }))).status, 200, id);
      assert.equal(created.calls[1].route, 'POST /contacts', id);
      assert.deepEqual(created.calls[1].body.properties, { ...PROPERTIES, consent_wording: id }, id);
      const ticked = harness({ routes: { [LOOKUP]: contact() } });
      assert.equal((await ticked.handler.POST(good({ news: true, consent: id }))).status, 200, id);
      assert.deepEqual(ticked.routes(), [LOOKUP, TOPICS, RECORD, OPT_IN], id);
      assert.deepEqual(ticked.calls[2].body, { properties: { ...PROPERTIES, consent_wording: id } }, id);
    }
  } finally {
    consent.current = shipped;
    delete consent.versions[next];
  }
  assert.deepEqual(Object.keys(consent.versions), versions);
});

test('a newer app’s consent id answers 422 until the deployment has it, and the app’s retry is taken then', async () => {
  // An app released before Production served its new wording. A 400 would clear every new address it saved, and keep
  // it from recording; the app retries a 422, and the retry after the site's deploy goes through.
  const next = 'consent-test-newer-app';
  assert.ok(!Object.hasOwn(consent.versions, next));
  const { handler, calls, logs } = harness();
  const early = await answer(await handler.POST(good({ consent: next })));
  assert.equal(early.status, 422);
  assert.deepEqual(early.json, { ok: false, reason: 'request' });
  assert.equal(calls.length, 0);
  // The same module object subscribe.js imported, changed only for this test: the deploy.
  consent.versions[next] = { ...consent.versions[consent.current] };
  try {
    assert.equal((await handler.POST(good({ consent: next }))).status, 200);
  } finally {
    delete consent.versions[next];
  }
  assert.deepEqual(calls[1].body.properties, { ...PROPERTIES, consent_wording: next });
  assert.deepEqual(logs, ['subscribe: invalid request', 'subscribe: added']);
});

test('a contact that exists never gets an opt_out, a change to Important notices, or unsubscribed: false', async () => {
  // Nor a change to its segments, which are Fayzan's: a contact this function made is in the segment from the start,
  // and he may take one out.
  let checked = 0;
  for (const unsubscribed of [false, true]) {
    for (const news of [false, true]) {
      for (const list of [
        topics([NOTICES, 'opt_in'], [NEWS, 'opt_out']), topics([NOTICES, 'opt_out']), topics([NEWS, 'opt_in']), topics(),
      ]) {
        const { handler, calls } = harness({ routes: { [LOOKUP]: contact({ unsubscribed }), [TOPICS]: list } });
        assert.equal((await handler.POST(good({ news }))).status, 200);
        for (const { route, body } of calls) {
          assert.ok(!['POST /contacts', 'POST /emails'].includes(route), route);
          assert.doesNotMatch(route, /segments/, route);
          const sent = JSON.stringify(body ?? null);
          assert.doesNotMatch(sent, /opt_out|unsubscribed|segments/, `${route} ${sent}`);
          assert.ok(!sent.includes(NOTICES) && !sent.includes(SEGMENT), `${route} ${sent}`);
          checked++;
        }
      }
    }
  }
  assert.ok(checked > 20, `${checked} calls checked`);
});

test('when the welcome fails, the contact stays and the answer is still 200', async () => {
  for (const [answers, reason, attempts] of [
    [[quota('daily_quota_exceeded')], 'quota', 1],
    [[SERVER, SERVER], 'server', 2],
    [[RATE, RATE], 'rate', 2],
    [['network', 'network'], 'network', 2],
    [['hang', 'hang'], 'timeout', 2],
    [[{ status: 422, json: { statusCode: 422, name: 'validation_error', message: 'Invalid `from` field.' } }], 'rejected', 1],
  ]) {
    const { handler, calls, logs, routes } = harness({ routes: { 'POST /emails': answers } });
    const response = await answer(await handler.POST(good()));
    assert.equal(response.status, 200, reason);
    assert.deepEqual(response.json, { ok: true }, reason);
    assert.deepEqual(routes(), [LOOKUP, 'POST /contacts', ...Array(attempts).fill('POST /emails')], reason);
    const keys = calls.slice(2).map(call => call.headers.get('idempotency-key'));
    assert.deepEqual(keys, Array(attempts).fill(`welcome-${sha256('sam@example.com')}`), `${reason}: a retry keeps its key`);
    assert.deepEqual(logs, [`subscribe: added welcome failed ${reason}`], reason);
  }
});

test('a welcome Resend already has under its key counts as sent, as the link email does', async () => {
  for (const name of ['invalid_idempotent_request', 'concurrent_idempotent_requests']) {
    const { handler, logs, routes } = harness({
      routes: { 'POST /emails': { status: 409, json: { statusCode: 409, name, message: 'Idempotency key in use.' } } },
    });
    assert.equal((await handler.POST(good())).status, 200, name);
    assert.deepEqual(routes(), [LOOKUP, 'POST /contacts', 'POST /emails'], name);
    assert.deepEqual(logs, ['subscribe: added welcome already sent'], name);
  }
});

test('without MAILING_ADDRESS the contact is added and the welcome skipped, since CASL wants the address in it', async () => {
  const { MAILING_ADDRESS, ...rest } = ENV;
  for (const env of [rest, { ...rest, MAILING_ADDRESS: '' }, { ...rest, MAILING_ADDRESS: ' \n ' }]) {
    const { handler, calls, logs, routes } = harness({ env });
    const response = await answer(await handler.POST(good()));
    assert.equal(response.status, 200, JSON.stringify(env.MAILING_ADDRESS));
    assert.deepEqual(response.json, { ok: true });
    assert.deepEqual(routes(), [LOOKUP, 'POST /contacts'], JSON.stringify(env.MAILING_ADDRESS));
    assert.deepEqual(calls[1].body.properties, PROPERTIES);
    assert.deepEqual(logs, ['subscribe: added welcome skipped no address']);
  }
  assert.equal(MAILING_ADDRESS, MAILING);
});

test('a mailing address pasted over two lines is one line in the footer', async () => {
  const { handler, calls } = harness({ env: { ...ENV, MAILING_ADDRESS: ' PO Box 1234\n  Toronto ON M5W 1A1\n' } });
  assert.equal((await handler.POST(good())).status, 200);
  const unsubscribe = unsubscribeUrl('sam@example.com', SECRET);
  const { text, html } = welcomeEmail({ news: false, address: 'PO Box 1234 Toronto ON M5W 1A1', unsubscribe });
  assert.equal(calls[2].body.text, text);
  assert.equal(calls[2].body.html, html);
});

test('a Resend call that fails: its quota or rate limit answers 429, anything else 502, and nothing after it runs', async () => {
  const existing = { [LOOKUP]: contact() };
  const stages = [
    { name: 'the lookup', route: LOOKUP, routes: {}, news: false, before: [] },
    { name: 'the new contact', route: 'POST /contacts', routes: {}, news: false, before: [LOOKUP] },
    { name: 'the topic lookup', route: TOPICS, routes: existing, news: true, before: [LOOKUP] },
    { name: 'the consent record', route: RECORD, routes: existing, news: true, before: [LOOKUP, TOPICS] },
    { name: 'the topic', route: OPT_IN, routes: existing, news: true, before: [LOOKUP, TOPICS, RECORD] },
  ];
  const failures = [
    [[quota('daily_quota_exceeded')], 429, 'busy', 'busy quota', 1],
    [[quota('monthly_quota_exceeded')], 429, 'busy', 'busy quota', 1],
    [[RATE, RATE], 429, 'busy', 'busy rate', 2],
    [[SERVER, SERVER], 502, 'send', 'failed server', 2],
    [['network', 'network'], 502, 'send', 'failed network', 2],
    [['hang', 'hang'], 502, 'send', 'failed timeout', 2],
    [[{ status: 422, json: { statusCode: 422, name: 'validation_error', message: 'Invalid.' } }], 502, 'send', 'failed rejected', 1],
    [[{ status: 401, json: { statusCode: 401, name: 'restricted_api_key', message: 'Restricted.' } }], 502, 'send', 'failed rejected', 1],
    [[LOCKED, LOCKED], 502, 'send', 'failed rejected', 2],
  ];
  for (const stage of stages) {
    // A 404 is how the lookup finds a new address. From any other call, it's unexpected: the contact went away.
    const unexpected = stage.route === LOOKUP ? [] : [[[NOT_FOUND], 502, 'send', 'failed notfound', 1]];
    for (const [answers, status, reason, line, attempts] of [...failures, ...unexpected]) {
      const why = `${stage.name}: ${line}`;
      const { handler, logs, routes } = harness({ routes: { ...stage.routes, [stage.route]: answers } });
      const response = await answer(await handler.POST(good({ news: stage.news })));
      assert.equal(response.status, status, why);
      assert.deepEqual(response.json, { ok: false, reason }, why);
      assert.deepEqual(routes(), [...stage.before, ...Array(attempts).fill(stage.route)], why);
      assert.deepEqual(logs, [`subscribe: ${line}`], why);
    }
  }
});

test('a contact another request created since the lookup answers 502, and the app’s retry finds it', async () => {
  // Resend's reference doesn't say what creating an existing contact answers; any refusal is the same here.
  const { handler, logs, routes } = harness({
    routes: {
      [LOOKUP]: [NOT_FOUND, contact()],
      'POST /contacts': { status: 409, json: { statusCode: 409, name: 'validation_error', message: 'Contact already exists.' } },
    },
  });
  const first = await answer(await handler.POST(good()));
  assert.equal(first.status, 502);
  assert.deepEqual(first.json, { ok: false, reason: 'send' });
  assert.deepEqual(routes(), [LOOKUP, 'POST /contacts']);
  const retry = await answer(await handler.POST(good()));
  assert.equal(retry.status, 200);
  assert.deepEqual(routes(), [LOOKUP, 'POST /contacts', LOOKUP], 'no second create, and no welcome');
  assert.deepEqual(logs, ['subscribe: failed rejected', 'subscribe: kept']);
});

test('one contact per address: capitals, padding, the encoding of an accent, and plus addressing', async () => {
  const decomposed = 'JU\u{308}RGEN@MU\u{308}LLER.DE';
  for (const [email, path] of [
    ['  Sam@Example.COM ', CONTACT],
    ['SAM@EXAMPLE.COM', CONTACT],
    ['sam@example.com', CONTACT],
    [decomposed, '/contacts/j%C3%BCrgen%40m%C3%BCller.de'],
    ['jürgen@müller.de', '/contacts/j%C3%BCrgen%40m%C3%BCller.de'],
    ['sam+annotake@gmail.com', '/contacts/sam%2Bannotake%40gmail.com'],
    // İ lowercases to i and a combining dot: a key one character longer than the address, and still plausible.
    ['\u{130}sa@example.com', '/contacts/i%CC%87sa%40example.com'],
  ]) {
    const { handler, calls, routes } = harness();
    assert.equal((await handler.POST(good({ email }))).status, 200, email);
    const key = emailKey(email);
    assert.deepEqual(routes(), [`GET ${path}`, 'POST /contacts', 'POST /emails'], email);
    assert.equal(calls[1].body.email, key, email);
    assert.deepEqual(calls[2].body.to, [key], email);
    assert.equal(calls[2].headers.get('idempotency-key'), `welcome-${sha256(key)}`, email);
    const link = new URL(calls[2].body.headers['List-Unsubscribe'].slice(1, -1));
    assert.equal(link.searchParams.get('e'), key, email);
    assert.equal(verifyEmail(key, link.searchParams.get('s'), SECRET), true, email);
  }
});

test('an address whose key is longer than the address is refused, so every contact can unsubscribe', async () => {
  // The unsubscribe link carries the key, and unsubscribe.js answers 400 to a key that isn't a plausible address.
  for (const email of [
    `\u{130}${'a'.repeat(63)}@example.com`,  // a 64-character local part whose key has 65
    `\u{130}${'a'.repeat(10)}@${'b'.repeat(238)}.com`,  // 254 characters whose key has 255
  ]) {
    assert.equal(isPlausibleEmail(email), true, email);
    assert.equal(isPlausibleEmail(emailKey(email)), false, email);
    const { handler, calls, logs } = harness();
    const response = await answer(await handler.POST(good({ email })));
    assert.equal(response.status, 400, email);
    assert.deepEqual(response.json, { ok: false, reason: 'invalid' });
    assert.equal(calls.length, 0, email);
    assert.deepEqual(logs, ['subscribe: invalid address'], email);
  }
});

/**
 * How a request is turned away. The app clears its saved address on a 400 alone, so only an address the function won't
 * take is 400; a request it can't read is 422, which the app retries.
 */
const REFUSED = {
  'invalid request': { status: 422, json: { ok: false, reason: 'request' } },
  'invalid address': { status: 400, json: { ok: false, reason: 'invalid' } },
};

test('what isn’t the app’s request answers 422, and an address the site won’t take 400, with no fetch', async () => {
  const json = JSON.stringify(FIELDS);
  const bytes = new TextEncoder().encode(json);
  const without = name => { const fields = { ...FIELDS }; delete fields[name]; return fields; };
  for (const [why, request, line] of [
    ['JSON cut short', post('{"email": "sam@example.com",'), 'invalid request'],
    ['JSON text', post('"sam@example.com"'), 'invalid request'],
    ['a JSON array', post(`[${json}]`), 'invalid request'],
    ['JSON null', post('null'), 'invalid request'],
    ['a JSON number', post('42'), 'invalid request'],
    ['an empty body', post(''), 'invalid request'],
    ['form fields', post(new URLSearchParams(FIELDS).toString(), { type: 'application/x-www-form-urlencoded' }), 'invalid request'],
    ['JSON sent as text', post(json, { type: 'text/plain' }), 'invalid request'],
    ['JSON with no content type', new Request('https://annotake.app/api/subscribe', { method: 'POST', body: bytes }), 'invalid request'],
    ['a body over 2 KB', good({ padding: 'x'.repeat(3 * 1024) }), 'invalid request'],
    ['a declared length over 2 KB', good({}, { headers: { 'content-length': String(MAX_BODY_BYTES + 1) } }), 'invalid request'],
    ['no news', post(without('news')), 'invalid request'],
    ['news as text', good({ news: 'yes' }), 'invalid request'],
    ['news as "false"', good({ news: 'false' }), 'invalid request'],
    ['news as a number', good({ news: 1 }), 'invalid request'],
    ['news null', good({ news: null }), 'invalid request'],
    ['no consent', post(without('consent')), 'invalid request'],
    ['an unknown consent', good({ consent: 'consent-2020-01-01' }), 'invalid request'],
    ['a consent with a space', good({ consent: 'consent-2026-10-15 ' }), 'invalid request'],
    ['a consent that names an inherited property', good({ consent: '__proto__' }), 'invalid request'],
    ['a consent that names a method', good({ consent: 'toString' }), 'invalid request'],
    ['a consent that isn’t text', good({ consent: ['consent-2026-10-15'] }), 'invalid request'],
    ['no appVersion', post(without('appVersion')), 'invalid request'],
    ['an appVersion that isn’t text', good({ appVersion: 120 }), 'invalid request'],
    ['appVersion null', good({ appVersion: null }), 'invalid request'],
    ['an empty appVersion', good({ appVersion: '' }), 'invalid request'],
    ['an appVersion over 32 characters', good({ appVersion: 'x'.repeat(MAX_APP_VERSION_LENGTH + 1) }), 'invalid request'],
    // An address that isn't text is a request the app didn't build, and a 400 would clear the app's saved address.
    ['no email', post(without('email')), 'invalid request'],
    ['an email that isn’t text', good({ email: ['sam@example.com'] }), 'invalid request'],
    ['email null', good({ email: null }), 'invalid request'],
    ['an empty email', good({ email: '' }), 'invalid address'],
    ['no dot in the domain', good({ email: 'privatesam@example' }), 'invalid address'],
    ['a space', good({ email: 'privatesam@exa mple.com' }), 'invalid address'],
    ['a header in the address', good({ email: 'privatesam@example.com\r\nBcc: x@y.z' }), 'invalid address'],
    ['a 65-character local part', good({ email: `${'a'.repeat(65)}@example.com` }), 'invalid address'],
    // Half a surrogate pair, which JSON carries as an escape, no app sends (a Swift string can't hold one), and no URL
    // can encode. Sent as text, since the final check encodes every address a test posts.
    ['half a surrogate pair', post(json.replace('Sam@', 'Sam\\ud800@')), 'invalid address'],
    ['the other half of one', post(json.replace('Sam@', '\\udc00Sam@')), 'invalid address'],
  ]) {
    const { handler, calls, logs } = harness();
    const response = await answer(await handler.POST(request));
    assert.equal(response.status, REFUSED[line].status, why);
    assert.equal(response.type, 'application/json', why);
    assert.deepEqual(response.json, REFUSED[line].json, why);
    assert.equal(calls.length, 0, why);
    assert.deepEqual(logs, [`subscribe: ${line}`], why);
  }
  assert.equal(MAX_BODY_BYTES, 2048);
  assert.equal(MAX_APP_VERSION_LENGTH, 32);
});

test('a charset on the content type, any capitals in it, and a 32-character appVersion are fine', async () => {
  for (const [why, request] of [
    ['a charset', good({}, { type: 'application/json; charset=utf-8' })],
    ['capitals', good({}, { type: 'Application/JSON' })],
    ['32 characters', good({ appVersion: 'x'.repeat(32) })],
    ['a field the app doesn’t send', good({ macOS: '15.7' })],
  ]) {
    const { handler, logs } = harness();
    assert.equal((await handler.POST(request)).status, 200, why);
    assert.deepEqual(logs, ['subscribe: added'], why);
  }
});

test('dry run checks the request and calls nothing, even without Resend’s settings', async () => {
  // Half a surrogate pair is refused before dry run too, so Preview and the local server answer it as Production does.
  // Sent as text, as in the 400 test above, so the final check never encodes it.
  const halfPair = JSON.stringify(FIELDS).replace('Sam@', 'Sam\\ud800@');
  for (const env of [{ EMAIL_DRY_RUN: '1' }, { ...ENV, EMAIL_DRY_RUN: '1' }]) {
    const { handler, calls, logs } = harness({ env });
    const response = await answer(await handler.POST(good()));
    assert.equal(response.status, 200);
    assert.deepEqual(response.json, { ok: true });
    assert.equal((await handler.POST(good({ news: true }))).status, 200);
    assert.equal((await handler.POST(good({ news: 'yes' }))).status, 422, 'the checks still run');
    assert.equal((await handler.POST(good({ email: 'privatesam@example' }))).status, 400, 'the checks still run');
    assert.equal((await handler.POST(post(halfPair))).status, 400, 'half a surrogate pair');
    assert.equal(calls.length, 0);
    assert.deepEqual(logs, [
      'subscribe: dry run', 'subscribe: dry run', 'subscribe: invalid request', 'subscribe: invalid address',
      'subscribe: invalid address',
    ]);
  }
});

test('a missing key, segment id, topic id, or secret answers 502 and says why in the log', async () => {
  const names = [
    'RESEND_CONTACTS_KEY', 'RESEND_SEGMENT', 'RESEND_TOPIC_NOTICES', 'RESEND_TOPIC_NEWS', 'UNSUBSCRIBE_SECRET',
  ];
  for (const name of names) {
    const missing = { ...ENV };
    delete missing[name];
    for (const env of [missing, { ...ENV, [name]: '' }]) {
      const { handler, calls, logs } = harness({ env });
      const response = await answer(await handler.POST(good()));
      assert.equal(response.status, 502, name);
      assert.deepEqual(response.json, { ok: false, reason: 'send' }, name);
      assert.equal(calls.length, 0, name);
      assert.deepEqual(logs, ['subscribe: failed not configured'], name);
    }
  }
  assert.deepEqual(Object.keys(ENV).filter(name => name !== 'MAILING_ADDRESS').sort(), names.toSorted());
  // A request it can't read is still turned away first.
  const { handler } = harness({ env: {} });
  assert.equal((await handler.POST(good({ news: 'yes' }))).status, 422);
});

test('each Resend attempt gets ATTEMPT_TIMEOUT_MS as deployed, or the handler’s timeoutMs', async () => {
  // Built as the module builds its POST for Vercel: no timeoutMs.
  const logs = [];
  const deployed = createHandler({
    fetch: async () => new Response(JSON.stringify(contact({ unsubscribed: true }).json), { status: 200 }), env: ENV,
    sleep: async () => {}, now: () => NOW, log: line => { logs.push(line); allLogs.push(line); },
  });
  assert.deepEqual(await attemptTimes(() => deployed.POST(good())), [ATTEMPT_TIMEOUT_MS]);
  assert.equal(ATTEMPT_TIMEOUT_MS, 4000);
  assert.deepEqual(logs, ['subscribe: kept unsubscribed']);

  const { handler, sleeps } = harness({ routes: { [LOOKUP]: ['hang', 'hang'] } });
  assert.deepEqual(await attemptTimes(() => handler.POST(good())), [50, 50], 'the harness’s 50 ms, for each attempt');
  assert.deepEqual(sleeps, [RETRY_PAUSE_MS]);
});

test('GET answers 405, with Allow: POST', async () => {
  const { handler, calls, logs } = harness();
  const response = await handler.GET(new Request('https://annotake.app/api/subscribe'));
  assert.equal(response.status, 405);
  assert.equal(response.headers.get('allow'), 'POST');
  assert.deepEqual(await response.json(), { ok: false });
  assert.equal(calls.length, 0);
  assert.deepEqual(logs, []);
});

test('the welcome’s reply-to is the app’s Feedback.address, so replies reach the same inbox', async () => {
  const swift = await readFile(new URL('../../../Sources/AnnotakeApp/Feedback.swift', import.meta.url), 'utf8');
  const [, address] = swift.match(/static let address = "([^"]+)"/) ?? [];
  assert.equal(REPLY_TO, address);
  assert.equal(REPLY_TO, 'fayzanm786@gmail.com');
});

test('an unexpected error still answers 502, and logs no details', async () => {
  const address = 'privatesam@example.com';
  const logs = [];
  const log = line => { logs.push(line); allLogs.push(line); };
  // A fetch and a pause that fail with the address in their messages: Resend's request sorts it as no answer.
  const leaky = createHandler({
    fetch: async () => { throw new Error(`boom ${address}`); }, env: ENV, log,
    sleep: async () => { throw new Error(`no timers for ${address}`); }, now: () => NOW, timeoutMs: 50,
  });
  assert.equal((await leaky.POST(good({ email: address }))).status, 502);
  // Failures inside the function itself: its settings, and its clock.
  const broken = createHandler({
    fetch: async () => new Response('{}'), log, sleep: async () => {}, now: () => NOW,
    env: { get EMAIL_DRY_RUN() { throw new Error(`no settings for ${address}`); } },
  });
  assert.equal((await broken.POST(good({ email: address }))).status, 502);
  const clockless = createHandler({
    fetch: async () => new Response(JSON.stringify(NOT_FOUND.json), { status: 404 }), env: ENV, log,
    sleep: async () => {}, now: () => { throw new RangeError(`no time for ${address}`); },
  });
  assert.equal((await clockless.POST(good({ email: address }))).status, 502);
  assert.deepEqual(logs, ['subscribe: failed network', 'subscribe: failed error Error', 'subscribe: failed error RangeError']);
});

after(() => {
  // Privacy: no log line, in any test, holds an address, its key, its encoded form, or its local part. Each is one of
  // the outcomes the function has, and nothing else.
  assert.ok(allLogs.length > 100, `${allLogs.length} log lines checked`);
  const outcome = new RegExp(`^subscribe: (${[
    'invalid request', 'invalid address', 'dry run', 'failed not configured', 'added', 'added welcome already sent',
    'added welcome skipped no address', 'added welcome failed (notfound|quota|rate|server|network|timeout|rejected)',
    'kept unsubscribed', 'kept', 'news added', 'busy (quota|rate)',
    'failed (notfound|server|network|timeout|rejected)', 'failed error \\w+',
  ].join('|')})$`);
  for (const line of allLogs) {
    assert.match(line, outcome, line);
    const lower = line.toLowerCase();
    for (const address of usedAddresses) {
      const key = emailKey(address);
      const local = key.split('@')[0];
      assert.ok(
        !lower.includes(key) && !lower.includes(encodeURIComponent(key).toLowerCase())
          && !(local.length > 3 && lower.includes(local)),
        `"${line}" mentions ${address}`,
      );
    }
  }
});
