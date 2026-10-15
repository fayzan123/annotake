// One request to Resend's HTTP API, shared by the email list's functions (unsubscribe.js and subscribe.js). Plain Node,
// with no packages. Vercel makes no function of a file under a `_` folder.
//
// It never throws: every answer, and every failure to get one, comes back as an outcome for the function to answer
// with. Each attempt times out after 4 s, and a call makes at most two, with a pause of at most 1 s between them, so it
// stays inside Vercel's 10 s limit.

export const RESEND_BASE = 'https://api.resend.com';
export const ATTEMPT_TIMEOUT_MS = 4000;
export const RETRY_PAUSE_MS = 300;
export const MAX_RATE_WAIT_MS = 1000;

const QUOTA_NAMES = ['daily_quota_exceeded', 'monthly_quota_exceeded'];

/**
 * One call, retried once after a network error, a timeout, a 5xx, a plain 429, or a 409 resource_locked. Never throws.
 * Resolves to `{ ok: true, status, json }`, where json is null for an empty body, or to
 * `{ ok: false, status, reason, name }`:
 * - reason: 'notfound' (any 404), 'quota' (a 429 for the daily or monthly quota), 'rate' (any other 429), 'server' (a
 *   5xx), 'network' or 'timeout' (no answer), or 'rejected' (anything else, such as a 422, or a contact still locked);
 * - status: null when nothing answered; name: Resend's name for the error, or null.
 * `headers` adds request headers. The key, the User-Agent, a body's Content-Type, and the Idempotency-Key are set here.
 */
export async function resend({
  fetch, sleep, key, method, path, body, headers, timeoutMs = ATTEMPT_TIMEOUT_MS, idempotencyKey,
}) {
  let init;
  try {
    init = {
      method,
      headers: requestHeaders({ key, headers, idempotencyKey, hasBody: body !== undefined }),
      body: body === undefined ? undefined : JSON.stringify(body),
    };
  } catch {
    // Only a bug gets here, such as a body JSON can't hold: there's nothing to send, or to retry.
    return { ok: false, status: null, reason: 'rejected', name: null };
  }
  const first = await attempt(fetch, RESEND_BASE + path, init, timeoutMs);
  if (first.retryAfter === undefined) return first.outcome;
  try {
    await sleep(first.retryAfter);
  } catch {
    // A pause that fails only makes it shorter.
  }
  return (await attempt(fetch, RESEND_BASE + path, init, timeoutMs)).outcome;
}

function requestHeaders({ key, headers, idempotencyKey, hasBody }) {
  const all = new Headers(headers);
  all.set('Authorization', `Bearer ${key}`);
  // Resend answers 403 to a request without a User-Agent.
  all.set('User-Agent', 'annotake-site/1.0');
  if (hasBody) all.set('Content-Type', 'application/json');
  // The same on both attempts, so Resend can tell a retry from a second request.
  if (idempotencyKey) all.set('Idempotency-Key', idempotencyKey);
  return all;
}

/** One request, sorted: its outcome, and the pause before a retry when one is worth it. */
async function attempt(fetch, url, init, timeoutMs) {
  let response, text;
  try {
    response = await fetch(url, { ...init, signal: AbortSignal.timeout(timeoutMs) });
    text = await response.text();
  } catch (error) {
    // Nothing answered, or the answer broke off.
    const reason = error?.name === 'TimeoutError' ? 'timeout' : 'network';
    return { outcome: { ok: false, status: null, reason, name: null }, retryAfter: RETRY_PAUSE_MS };
  }
  const { status } = response;
  const json = parseJson(text);
  if (status >= 200 && status < 300) return { outcome: { ok: true, status, json } };
  const name = typeof json?.name === 'string' ? json.name : null;
  const failure = reason => ({ ok: false, status, reason, name });
  if (status === 404) return { outcome: failure('notfound') };
  if (status === 429 && QUOTA_NAMES.includes(name)) return { outcome: failure('quota') };
  if (status === 429) return { outcome: failure('rate'), retryAfter: rateWait(response.headers.get('retry-after')) };
  if (status >= 500) return { outcome: failure('server'), retryAfter: RETRY_PAUSE_MS };
  // Another request is changing the same contact, such as a second click on the confirm page's button, and Resend
  // says to retry after a short delay. The 409s about an idempotency key aren't retried: the same request is already
  // on its way, or another used the key, and the caller can tell which by name.
  if (status === 409 && name === 'resource_locked') return { outcome: failure('rejected'), retryAfter: RETRY_PAUSE_MS };
  return { outcome: failure('rejected') };
}

/** The body as JSON, or null when it's empty or isn't JSON. */
function parseJson(text) {
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

/** A plain rate limit's wait: its retry-after, at most MAX_RATE_WAIT_MS, which is also the wait without one. */
function rateWait(retryAfter) {
  const seconds = Number.parseFloat(retryAfter);
  return Number.isFinite(seconds) && seconds >= 0 ? Math.min(seconds * 1000, MAX_RATE_WAIT_MS) : MAX_RATE_WAIT_MS;
}
