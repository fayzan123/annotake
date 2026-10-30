// /api/appcast: the app's update feed (SUFeedURL). A Vercel function in plain Node, with no packages. It counts the
// check in Upstash Redis, then answers 302 to the feed on GitHub, which Sparkle follows.
//
// Only Sparkle's own User-Agent, `Annotake/<version> Sparkle/<version>`, is counted. Per UTC day it keeps a
// HyperLogLog of distinct Macs per version and a hash of checks per version. A Mac is HMAC-SHA256(salt, IP), where the
// salt is random per day and expires after 36 h, so no IP is stored and no count follows a Mac across days
// (docs/plans/2026-10-30-update-counts-design.md).
//
// Updates never wait on a count: the counting has COUNT_TIMEOUT_MS in all, and every outcome, counted or not, answers
// the same 302. Each request logs one `appcast: <outcome>` line, never an IP.
import { createHmac, randomBytes } from 'node:crypto';

export const FEED_URL = 'https://raw.githubusercontent.com/fayzan123/annotake-releases/main/appcast.xml';
export const COUNT_TIMEOUT_MS = 500;
export const KEEP_SECONDS = 400 * 24 * 60 * 60;
export const SALT_SECONDS = 36 * 60 * 60;

const USER_AGENT = /^Annotake\/([0-9][0-9A-Za-z.+-]{0,31}) Sparkle\//;

/** The app's version from Sparkle's User-Agent, or null for anything else. */
export function appVersion(userAgent) {
  return USER_AGENT.exec(userAgent ?? '')?.[1] ?? null;
}

/** The client's IP: Vercel puts it first in x-forwarded-for. */
function clientIp(headers) {
  return headers.get('x-forwarded-for')?.split(',')[0].trim() || headers.get('x-real-ip') || null;
}

/** Upstash's REST URL and token, under the Marketplace's names or Vercel KV's older ones, or null. */
function redisConfig(env) {
  const url = env.UPSTASH_REDIS_REST_URL ?? env.KV_REST_API_URL;
  const token = env.UPSTASH_REDIS_REST_TOKEN ?? env.KV_REST_API_TOKEN;
  return url && token ? { url: url.replace(/\/+$/, ''), token } : null;
}

export function createHandler({ fetch, env, log, now, random = () => randomBytes(32).toString('hex'),
  timeoutMs = COUNT_TIMEOUT_MS }) {
  /** One Upstash pipeline: the results in order. Throws on any failure, which count() turns into an outcome. */
  async function pipeline(redis, commands, signal) {
    const response = await fetch(`${redis.url}/pipeline`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${redis.token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(commands),
      signal,
    });
    if (!response.ok) throw Object.assign(new Error('redis'), { reason: `status ${response.status}` });
    const results = await response.json();
    const failed = results.find(result => result.error !== undefined);
    if (failed) throw Object.assign(new Error('redis'), { reason: 'command' });
    return results.map(result => result.result);
  }

  async function count(request) {
    const version = appVersion(request.headers.get('user-agent'));
    if (version === null) return 'skipped';
    const redis = redisConfig(env);
    if (redis === null) return 'not configured';
    const ip = clientIp(request.headers);
    if (ip === null) return 'skipped no ip';
    const day = now().toISOString().slice(0, 10);
    const signal = AbortSignal.timeout(timeoutMs);
    try {
      const [, salt] = await pipeline(redis, [
        ['SET', `salt:${day}`, random(), 'NX', 'EX', SALT_SECONDS],
        ['GET', `salt:${day}`],
      ], signal);
      if (typeof salt !== 'string') return 'failed no salt';
      const mac = createHmac('sha256', salt).update(ip).digest('hex').slice(0, 32);
      const installs = `installs:${day}:${version}`;
      await pipeline(redis, [
        ['PFADD', installs, mac],
        ['EXPIRE', installs, KEEP_SECONDS],
        ['HINCRBY', `checks:${day}`, version, 1],
        ['EXPIRE', `checks:${day}`, KEEP_SECONDS],
      ], signal);
      return 'counted';
    } catch (error) {
      if (signal.aborted) return 'failed timeout';
      return `failed ${error?.reason ?? 'network'}`;
    }
  }

  async function GET(request) {
    let outcome;
    try {
      outcome = await count(request);
    } catch (error) {
      // Only a bug gets here. The feed still answers.
      outcome = `failed error ${error?.name ?? 'unknown'}`;
    }
    log(`appcast: ${outcome}`);
    return new Response(null, { status: 302, headers: { Location: FEED_URL, 'Cache-Control': 'no-store' } });
  }

  return { GET, HEAD: GET };
}

export const { GET, HEAD } = createHandler({
  fetch: globalThis.fetch,
  env: process.env,
  log: line => console.log(line),
  now: () => new Date(),
});
