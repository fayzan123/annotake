// POST /api/subscribe: the address someone typed in the app's first run joins the email list in Resend, with its topics
// and a consent record, and gets the welcome email once. A Vercel function in plain Node, with no packages, built like
// link.js. It never logs or returns an address: each request logs one `subscribe: <outcome>` line.
// - A new address becomes a contact in the segment broadcasts are sent to, on Important notices, and on Feedback and
//   news only if the box was ticked. The welcome email (_lib/welcome.js) carries the one-click unsubscribe link that
//   unsubscribe.js serves.
// - An address that unsubscribed stays unsubscribed: nothing changes, and nothing is sent. Only Fayzan, by hand, ever
//   undoes an unsubscribe.
// - An address already subscribed joins Feedback and news if the box was ticked this time, with a new consent record.
//   No topic is ever removed, and no second welcome is sent.
//
// The app retries 429 and 502 later, and a retry after a partial success finishes the job. A request makes at most four
// Resend calls in turn, each at most two attempts of 4 s (_lib/resend.js). Resend answers in well under a second, so a
// request fits Vercel's 10 s limit; if a struggling Resend makes Vercel stop one, the app gets a 504 and retries the
// same way, losing at most the welcome.
import { createHash } from 'node:crypto';
import { emailKey, isPlausibleEmail } from '../assets/email.js';
import consent from './_lib/consent.json' with { type: 'json' };
import { ATTEMPT_TIMEOUT_MS, resend } from './_lib/resend.js';
import { unsubscribeUrl } from './_lib/unsubscribe-token.js';
import { welcomeEmail } from './_lib/welcome.js';

export const MAX_BODY_BYTES = 2048;
export const MAX_APP_VERSION_LENGTH = 32;
export const FROM = 'Fayzan from Annotake <hello@annotake.app>';
/**
 * Replies reach Fayzan's own inbox, since annotake.app receives no mail. It must match Feedback.address in
 * Sources/AnnotakeApp/Feedback.swift, which a unit test checks.
 */
export const REPLY_TO = 'fayzanm786@gmail.com';

/**
 * What a real call needs: the key, the segment and the two topics a contact goes in, and the unsubscribe link's secret.
 * MAILING_ADDRESS isn't one: without it, the contact is still added, with no welcome.
 */
const SETTINGS = [
  'RESEND_CONTACTS_KEY', 'RESEND_SEGMENT', 'RESEND_TOPIC_NOTICES', 'RESEND_TOPIC_NEWS', 'UNSUBSCRIBE_SECRET',
];

/** Resend's answers to a welcome whose Idempotency-Key it has seen: it's on its way, or one went in the last 24 hours. */
const ALREADY_SENT = ['invalid_idempotent_request', 'concurrent_idempotent_requests'];

/**
 * The answers. The app clears its saved address on a 400 alone, so 400 is for an address the function won't take, and
 * a request it can't read is 422, which the app retries. So a newer app's request, under a consent id this deployment
 * doesn't have yet, goes through once the site is deployed, rather than clearing every new address.
 */
const RESULTS = {
  success: { status: 200, json: { ok: true } },
  invalid: { status: 400, json: { ok: false, reason: 'invalid' } },
  request: { status: 422, json: { ok: false, reason: 'request' } },
  busy: { status: 429, json: { ok: false, reason: 'busy' } },
  send: { status: 502, json: { ok: false, reason: 'send' } },
};

/** The body as text, or null when it's over the limit, declared or not. */
async function readBody(request) {
  if (Number(request.headers.get('content-length')) > MAX_BODY_BYTES) return null;
  if (!request.body) return '';
  const reader = request.body.getReader();
  const chunks = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > MAX_BODY_BYTES) {
      reader.cancel().catch(() => {});
      return null;
    }
    chunks.push(value);
  }
  return Buffer.concat(chunks).toString('utf8');
}

/**
 * { email, news, wording, appVersion } when the body is what the app sends, or null. The address is checked after:
 * `news` a boolean, `consent` the id of a wording in consent.json, and `appVersion` the app's "0.3.0 (120)", which is
 * never empty.
 */
function readFields(text) {
  let data;
  try {
    data = JSON.parse(text);
  } catch {
    return null;
  }
  if (!data || typeof data !== 'object' || Array.isArray(data)) return null;
  const { email, news, consent: wording, appVersion } = data;
  if (typeof news !== 'boolean') return null;
  if (typeof wording !== 'string' || !Object.hasOwn(consent.versions, wording)) return null;
  if (typeof appVersion !== 'string' || appVersion === '' || appVersion.length > MAX_APP_VERSION_LENGTH) return null;
  return { email, news, wording, appVersion };
}

/** True when Resend's list of a contact's topics has this one opted in. Without a limit, the list holds every topic. */
function isOptedIn(list, topic) {
  return Array.isArray(list?.data) && list.data.some(entry => entry?.id === topic && entry?.subscription === 'opt_in');
}

/** A contact call that failed: Resend's quota or rate limit is busy (429), and anything else send (502). */
function failed({ reason }) {
  if (reason === 'quota' || reason === 'rate') return { result: 'busy', line: `busy ${reason}` };
  return { result: 'send', line: `failed ${reason}` };
}

export function createHandler({ fetch, env, log, sleep, now, timeoutMs = ATTEMPT_TIMEOUT_MS }) {
  const call = options => resend({ fetch, sleep, key: env.RESEND_CONTACTS_KEY, timeoutMs, ...options });

  /** The consent record, as the contact's properties: what the person agreed to, when, where, and in which version. */
  function consentRecord(wording, appVersion) {
    const consentAt = now().toISOString();
    return { consent_at: consentAt, consent_wording: wording, consent_source: 'app', app_version: appVersion };
  }

  /** Adds a new address to the list, then sends the welcome. */
  async function create({ key, news, wording, appVersion }) {
    const created = await call({
      method: 'POST',
      path: '/contacts',
      // No `unsubscribed`: a new contact is subscribed anyway, and Resend doesn't say what a create does to a contact
      // that exists, so an `unsubscribed: false` here could undo an unsubscribe.
      body: {
        email: key,
        properties: consentRecord(wording, appVersion),
        // Every broadcast goes to a segment, and its topic only narrows that down: a contact in no segment gets none.
        segments: [{ id: env.RESEND_SEGMENT }],
        topics: [
          { id: env.RESEND_TOPIC_NOTICES, subscription: 'opt_in' },
          { id: env.RESEND_TOPIC_NEWS, subscription: news ? 'opt_in' : 'opt_out' },
        ],
      },
    });
    // Another request may have added the address since the lookup: the app's retry finds it.
    if (!created.ok) return failed(created);
    return welcome(key, news);
  }

  /**
   * The welcome email, sent only here, right after the contact is created. However it goes, the contact stays and the
   * answer is 200. No later request sends it, so nobody gets it twice (design §5.1).
   */
  async function welcome(key, news) {
    // CASL wants the mailing address in every email, on one line here however it was pasted.
    const address = (env.MAILING_ADDRESS ?? '').replace(/\s+/g, ' ').trim();
    if (!address) return { result: 'success', line: 'added welcome skipped no address' };
    const unsubscribe = unsubscribeUrl(key, env.UNSUBSCRIBE_SECRET);
    const sent = await call({
      method: 'POST',
      path: '/emails',
      body: {
        from: FROM, to: [key], reply_to: REPLY_TO, ...welcomeEmail({ news, address, unsubscribe }),
        // A mail app's own Unsubscribe: the URL in angle brackets (RFC 2369), which takes a one-click POST (RFC 8058).
        headers: { 'List-Unsubscribe': `<${unsubscribe}>`, 'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click' },
      },
      // The same for every attempt at this address's welcome, so Resend sends it once.
      idempotencyKey: `welcome-${createHash('sha256').update(key).digest('hex')}`,
    });
    if (sent.ok) return { result: 'success', line: 'added' };
    if (ALREADY_SENT.includes(sent.name)) return { result: 'success', line: 'added welcome already sent' };
    return { result: 'success', line: `added welcome failed ${sent.reason}` };
  }

  /** Adds Feedback and news for a subscribed contact not on it yet: the consent record, then the topic. */
  async function addNews(contact, { wording, appVersion }) {
    const topics = await call({ method: 'GET', path: `${contact}/topics` });
    if (!topics.ok) return failed(topics);
    if (isOptedIn(topics.json, env.RESEND_TOPIC_NEWS)) return { result: 'success', line: 'kept' };
    // The new consent goes on record before the topic it allows: if the topic call fails, the app's retry does both
    // again, and nobody is on Feedback and news with a record older than the consent that put them there.
    const properties = consentRecord(wording, appVersion);
    const recorded = await call({ method: 'PATCH', path: contact, body: { properties } });
    if (!recorded.ok) return failed(recorded);
    const added = await call({
      method: 'PATCH', path: `${contact}/topics`, body: [{ id: env.RESEND_TOPIC_NEWS, subscription: 'opt_in' }],
    });
    if (!added.ok) return failed(added);
    return { result: 'success', line: 'news added' };
  }

  /** Creates the contact, or keeps it as it is, adding only Feedback and news. Never opts out, never resubscribes. */
  async function subscribe(fields) {
    const contact = `/contacts/${encodeURIComponent(fields.key)}`;
    const found = await call({ method: 'GET', path: contact });
    if (!found.ok) return found.reason === 'notfound' ? create(fields) : failed(found);
    // Anything but a clear "subscribed" counts as unsubscribed: when in doubt, nothing changes.
    if (found.json?.unsubscribed !== false) return { result: 'success', line: 'kept unsubscribed' };
    if (!fields.news) return { result: 'success', line: 'kept' };
    return addNews(contact, fields);
  }

  async function decide(request) {
    const type = (request.headers.get('content-type') ?? '').split(';')[0].trim().toLowerCase();
    const text = type === 'application/json' ? await readBody(request) : null;
    const fields = text === null ? null : readFields(text);
    if (!fields) return { result: 'request', line: 'invalid request' };
    const { email } = fields;
    // JSON can carry half a surrogate pair, which no app sends and no URL can encode. And the unsubscribe link carries
    // the address's key, which can be longer than the address (İ lowercases to i and a dot), and unsubscribe.js turns
    // away a key that isn't a plausible address: no contact without a working link.
    const plausible = typeof email === 'string' && email.isWellFormed() && isPlausibleEmail(email)
      && isPlausibleEmail(emailKey(email));
    if (!plausible) return { result: 'invalid', line: 'invalid address' };
    if (env.EMAIL_DRY_RUN === '1') return { result: 'success', line: 'dry run' };
    if (!SETTINGS.every(name => env[name])) return { result: 'send', line: 'failed not configured' };
    return subscribe({ ...fields, key: emailKey(email) });
  }

  async function POST(request) {
    let outcome;
    try {
      outcome = await decide(request);
    } catch (error) {
      // Never the message: it could hold the address.
      outcome = { result: 'send', line: `failed error ${error?.name ?? 'unknown'}` };
    }
    log(`subscribe: ${outcome.line}`);
    const { status, json } = RESULTS[outcome.result];
    return Response.json(json, { status });
  }

  function GET() {
    return Response.json({ ok: false }, { status: 405, headers: { Allow: 'POST' } });
  }

  return { POST, GET };
}

export const { POST, GET } = createHandler({
  fetch: globalThis.fetch,
  env: process.env,
  log: line => console.log(line),
  sleep: ms => new Promise(resolve => setTimeout(resolve, ms)),
  now: () => new Date(),
});
