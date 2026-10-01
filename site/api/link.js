// POST /api/link: emails the download link to an address, once, through Resend's HTTP API. A Vercel function in plain
// Node, with no packages. It stores nothing and never logs, stores, or returns an address: each request logs one
// `link: <outcome>` line.
//
// The page sends JSON and shows the result; the form without scripts posts form fields and gets a small page back.
// Every path answers within Vercel's 10 s limit: two attempts of at most 4 s, and a pause of at most 1 s between them.
import { createHash } from 'node:crypto';
import { cleanEmail, emailKey, isPlausibleEmail } from '../assets/email.js';

export const RESEND_URL = 'https://api.resend.com/emails';
export const ATTEMPT_TIMEOUT_MS = 4000;
export const RETRY_PAUSE_MS = 300;
export const MAX_RATE_WAIT_MS = 1000;
export const TOO_FAST_MS = 1000;
export const MAX_BODY_BYTES = 2048;

const DOWNLOAD = 'https://annotake.app/download';

export const EMAIL_TEXT = `Here’s the Annotake download link you asked for:
${DOWNLOAD}

Open it on your Mac (macOS 15 or later). Then open the disk image and drag Annotake to Applications.

This is the only email we’ll send you.

Annotake, made by Fayzan Malik in Ontario, Canada
https://annotake.app · Privacy: https://annotake.app/privacy`;

// Inline styles are fine here: it's an email, not the site.
export const EMAIL_HTML = `<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Annotake for your Mac</title></head>
<body style="margin:0;padding:24px;background:#ffffff;color:#1c1c1e;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:16px;line-height:1.5">
<p style="margin:0 0 16px">Here’s the Annotake download link you asked for:</p>
<p style="margin:0 0 24px"><a href="${DOWNLOAD}" style="display:inline-block;padding:12px 22px;border-radius:999px;background:#1c1c1e;color:#ffffff;font-weight:600;text-decoration:none">Download Annotake for Mac</a></p>
<p style="margin:0 0 16px">Open it on your Mac (macOS 15 or later). Then open the disk image and drag Annotake to Applications.</p>
<p style="margin:0 0 24px">This is the only email we’ll send you.</p>
<p style="margin:0;color:#6e6e73;font-size:14px">Annotake, made by Fayzan Malik in Ontario, Canada<br><a href="https://annotake.app" style="color:#6e6e73">annotake.app</a> · Privacy: <a href="https://annotake.app/privacy" style="color:#6e6e73">https://annotake.app/privacy</a></p>
</body>
</html>`;

const RESULTS = {
  success: { status: 200, json: { ok: true } },
  invalid: { status: 400, json: { ok: false, reason: 'invalid' } },
  busy: { status: 429, json: { ok: false, reason: 'busy' } },
  send: { status: 502, json: { ok: false, reason: 'send' } },
};

/** What a form post without scripts sees, as a page in the site's style. */
const PAGES = {
  success: ['Check your inbox', '<p>We sent the link to your email. Open it on your Mac.</p>'],
  invalid: ['That doesn’t look like an email address.', '<p><a href="/">Go back and try again</a></p>'],
  failure: ['We couldn’t send it right now.', `<p>Here’s the link: <span class="message-link">${DOWNLOAD}</span></p>`],
};

function page(kind) {
  const [title, body] = PAGES[kind];
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title} · Annotake</title>
<link rel="stylesheet" href="/assets/site.css">
</head>
<body>
<main class="message">
  <h1>${title}</h1>
  ${body}
  <p><a href="/">annotake.app</a></p>
</main>
</body>
</html>
`;
}

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

/** { email, website, t } from JSON or form fields, or null for anything else. */
function parseFields(type, text) {
  if (type === 'application/json') {
    try {
      const data = JSON.parse(text);
      return data && typeof data === 'object' && !Array.isArray(data) ? data : null;
    } catch {
      return null;
    }
  }
  if (type === 'application/x-www-form-urlencoded') {
    const fields = new URLSearchParams(text);
    return { email: fields.get('email'), website: fields.get('website'), t: fields.get('t') };
  }
  return null;
}

export function createHandler({ fetch, env, log, sleep, today, timeoutMs = ATTEMPT_TIMEOUT_MS }) {
  /** One request to Resend, sorted into what to do next. */
  async function attempt(apiKey, email) {
    let response;
    try {
      response = await fetch(RESEND_URL, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
          'Idempotency-Key': `link-${today()}-${createHash('sha256').update(emailKey(email)).digest('hex')}`,
          // Resend rejects requests without a User-Agent.
          'User-Agent': 'annotake-link/1.0',
        },
        // The same every time for an address, so a repeated key never conflicts with itself.
        body: JSON.stringify({
          from: 'Annotake <hello@annotake.app>', to: [email], reply_to: 'hello@annotake.app',
          subject: 'Annotake for your Mac', text: EMAIL_TEXT, html: EMAIL_HTML,
        }),
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch (error) {
      const why = error?.name === 'TimeoutError' ? 'timeout' : 'network';
      return { retryAfter: RETRY_PAUSE_MS, last: { result: 'send', line: `failed ${why}` } };
    }
    const { status } = response;
    const name = status >= 400 ? (await response.json().catch(() => ({})))?.name : undefined;
    if (status >= 200 && status < 300) return { done: { result: 'success', line: 'sent' } };
    if (status === 409 && ['invalid_idempotent_request', 'concurrent_idempotent_requests'].includes(name)) {
      return { done: { result: 'success', line: 'sent already today' } };
    }
    if (status === 429 && ['daily_quota_exceeded', 'monthly_quota_exceeded'].includes(name)) {
      return { done: { result: 'busy', line: 'busy quota' } };
    }
    if (status === 429) {
      const seconds = Number.parseFloat(response.headers.get('retry-after'));
      const wait = Number.isFinite(seconds) && seconds >= 0 ? Math.min(seconds * 1000, MAX_RATE_WAIT_MS) : MAX_RATE_WAIT_MS;
      return { retryAfter: wait, last: { result: 'busy', line: 'busy rate limit' } };
    }
    if (status >= 500) return { retryAfter: RETRY_PAUSE_MS, last: { result: 'send', line: `failed resend ${status}` } };
    return { done: { result: 'send', line: `failed rejected ${status}` } };
  }

  /** Sends once, and once more after a pause if the first answer allows it. */
  async function send(apiKey, email) {
    const first = await attempt(apiKey, email);
    if (first.done) return first.done;
    await sleep(first.retryAfter);
    const second = await attempt(apiKey, email);
    return second.done ?? second.last;
  }

  async function decide(request, type) {
    const text = await readBody(request);
    const fields = text === null ? null : parseFields(type, text);
    if (!fields) return { result: 'invalid', line: 'invalid request' };
    const { email, website, t } = fields;
    if (website !== undefined && website !== null && String(website) !== '') {
      return { result: 'success', line: 'ignored honeypot' };
    }
    const elapsed = t === undefined || t === null || t === '' ? NaN : Number(t);
    if (Number.isFinite(elapsed) && elapsed < TOO_FAST_MS) return { result: 'success', line: 'ignored too fast' };
    if (typeof email !== 'string' || !isPlausibleEmail(email)) return { result: 'invalid', line: 'invalid address' };
    if (env.EMAIL_DRY_RUN === '1') return { result: 'success', line: 'dry run' };
    if (!env.RESEND_API_KEY) return { result: 'send', line: 'failed not configured' };
    return send(env.RESEND_API_KEY, cleanEmail(email));
  }

  async function POST(request) {
    const type = (request.headers.get('content-type') ?? '').split(';')[0].trim().toLowerCase();
    let outcome;
    try {
      outcome = await decide(request, type);
    } catch (error) {
      // Never the message: it could hold the address.
      outcome = { result: 'send', line: `failed error ${error?.name ?? 'unknown'}` };
    }
    log(`link: ${outcome.line}`);
    const { status, json } = RESULTS[outcome.result];
    if (type !== 'application/x-www-form-urlencoded') return Response.json(json, { status });
    const kind = outcome.result === 'success' ? 'success' : outcome.result === 'invalid' ? 'invalid' : 'failure';
    return new Response(page(kind), { status, headers: { 'Content-Type': 'text/html; charset=utf-8' } });
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
  today: () => new Date().toISOString().slice(0, 10),
});
