// /api/unsubscribe?e=<address>&s=<signature>: the welcome email's unsubscribe link. A Vercel function in plain Node,
// with no packages. The signature (_lib/unsubscribe-token.js) keeps anyone from unsubscribing an address they weren't
// sent a link for.
// - GET shows a page that asks first, so a link scanner or a prefetch never unsubscribes anyone.
// - POST sets the contact unsubscribed in Resend: the page's button, or a mail app's one-click unsubscribe
//   (List-Unsubscribe-Post, RFC 8058), which posts to the link itself.
//
// Both read the address and the signature from the query, so a one-click POST works without a body. It never logs an
// address: each request logs one `unsubscribe: <outcome>` line. Every path answers within Vercel's 10 s limit
// (_lib/resend.js).
import { emailKey, isPlausibleEmail } from '../assets/email.js';
import { ATTEMPT_TIMEOUT_MS, resend } from './_lib/resend.js';
import { verifyEmail } from './_lib/unsubscribe-token.js';

export const MAX_BODY_BYTES = 2048;

const STATUS = { shown: 200, done: 200, invalid: 400, failed: 502 };
const HTML = { 'Content-Type': 'text/html; charset=utf-8' };

const ESCAPES = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
const escapeHtml = text => text.replace(/[&<>"']/g, char => ESCAPES[char]);

/**
 * A page in the site's style. The link's URL holds an address, so no Referer carries it on (to the home page's
 * analytics, say), and no search engine keeps the page.
 */
function page(title, ...lines) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer">
<meta name="robots" content="noindex">
<title>${title} · Annotake</title>
<link rel="icon" href="/assets/img/favicon.svg" type="image/svg+xml">
<link rel="icon" href="/assets/img/favicon-32.png" sizes="32x32" type="image/png">
<link rel="stylesheet" href="/assets/site.css">
</head>
<body>
<main class="message">
  <h1>${title}</h1>
${[...lines, '<p><a href="/">annotake.app</a></p>'].map(line => `  ${line}`).join('\n')}
</main>
</body>
</html>
`;
}

/** Every page but the one that asks; none of them repeats the link's address. */
const PAGES = {
  invalid: page('This unsubscribe link isn’t valid.'),
  done: page('You’re unsubscribed.'),
  failed: page('We couldn’t unsubscribe you right now.', '<p>Try the link again in a few minutes.</p>'),
};

/**
 * Asks first. The address sits in the text below the heading, where a long one has more room. The form posts back to
 * the link with from=page, which asks for a page in return: without it, the answer is a mail app's blank 200.
 */
function confirmPage({ key, signature }) {
  const action = `/api/unsubscribe?e=${encodeURIComponent(key)}&s=${signature}`;
  return page(
    'Unsubscribe',
    `<p>Unsubscribe ${escapeHtml(key)} from all Annotake emails?</p>`,
    `<form method="post" action="${escapeHtml(action)}">`,
    '  <input type="hidden" name="from" value="page">',
    '  <p><button class="btn btn-lg" type="submit">Unsubscribe</button></p>',
    '</form>',
  );
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

/** True for the confirm page's form. A mail app's one-click, an empty body, and anything else are false. */
function isFromPage(contentType, text) {
  const type = (contentType ?? '').split(';')[0].trim().toLowerCase();
  if (type !== 'application/x-www-form-urlencoded' || text === null) return false;
  return new URLSearchParams(text).get('from') === 'page';
}

export function createHandler({ fetch, env, log, sleep, timeoutMs = ATTEMPT_TIMEOUT_MS }) {
  /**
   * The link's address, keyed, and its signature, when the signature is ours; otherwise the outcome to answer with.
   * Checking needs the secret, in dry run too.
   */
  function readLink(request) {
    // A + that lost its encoding on the way stays a plus, as in sam+annotake@gmail.com: an address never holds a
    // space, which URLSearchParams would make of it.
    const query = new URLSearchParams(new URL(request.url).search.replaceAll('+', '%2B'));
    const email = query.get('e');
    const signature = query.get('s');
    if (!env.UNSUBSCRIBE_SECRET) return { outcome: { result: 'failed', line: 'failed not configured' } };
    if (!isPlausibleEmail(email) || !verifyEmail(email, signature, env.UNSUBSCRIBE_SECRET)) {
      return { outcome: { result: 'invalid', line: 'invalid' } };
    }
    return { link: { key: emailKey(email), signature } };
  }

  /** Sets the contact unsubscribed. Only this needs Resend's key, and dry run doesn't. */
  async function unsubscribe(key) {
    if (env.EMAIL_DRY_RUN === '1') return { result: 'done', line: 'dry run' };
    if (!env.RESEND_CONTACTS_KEY) return { result: 'failed', line: 'failed not configured' };
    const answer = await resend({
      fetch, sleep, key: env.RESEND_CONTACTS_KEY, method: 'PATCH', path: `/contacts/${encodeURIComponent(key)}`,
      body: { unsubscribed: true }, timeoutMs,
    });
    if (answer.ok) return { result: 'done', line: 'done' };
    // A contact Resend doesn't have can't be emailed either.
    if (answer.reason === 'notfound') return { result: 'done', line: 'done already gone' };
    return { result: 'failed', line: `failed ${answer.reason}` };
  }

  function GET(request) {
    let outcome, link;
    try {
      ({ outcome, link } = readLink(request));
      outcome ??= { result: 'shown', line: 'shown' };
    } catch (error) {
      // Never the message: it could hold the address.
      outcome = { result: 'failed', line: `failed error ${error?.name ?? 'unknown'}` };
    }
    log(`unsubscribe: ${outcome.line}`);
    const html = outcome.result === 'shown' ? confirmPage(link) : PAGES[outcome.result];
    return new Response(html, { status: STATUS[outcome.result], headers: HTML });
  }

  async function POST(request) {
    // The body only picks the answer's form. Whether to unsubscribe is the signed link's alone.
    const fromPage = isFromPage(request.headers.get('content-type'), await readBody(request).catch(() => null));
    let outcome;
    try {
      const { outcome: refused, link } = readLink(request);
      outcome = refused ?? await unsubscribe(link.key);
    } catch (error) {
      outcome = { result: 'failed', line: `failed error ${error?.name ?? 'unknown'}` };
    }
    log(`unsubscribe: ${outcome.line}`);
    if (outcome.result === 'done' && !fromPage) return new Response(null, { status: 200 });
    return new Response(PAGES[outcome.result], { status: STATUS[outcome.result], headers: HTML });
  }

  return { GET, POST };
}

export const { GET, POST } = createHandler({
  fetch: globalThis.fetch,
  env: process.env,
  log: line => console.log(line),
  sleep: ms => new Promise(resolve => setTimeout(resolve, ms)),
});
