// Checkpoint 4's burst test of the firewall's rate limit on /api/link: `make site-burst URL=https://annotake.app`.
// It sends `count` POSTs (50 by default) in waves of 10, and passes when the firewall answers 429 to all but the first
// 10 and nothing fails with a 5xx. Every post fills the honeypot field, so the function sends no email, ever.
import { fileURLToPath } from 'node:url';

const WAVE = 10;
const ALLOWED = 10;
const BODY = JSON.stringify({ email: 'burst@example.com', website: 'bot', t: 5000 });

/** What's wrong with a burst's status counts ({ 200: 10, 429: 40 }, say). Empty means the firewall held. */
export function evaluateBurst(counts, count) {
  const problems = [];
  const limited = counts[429] ?? 0;
  if (limited < count - ALLOWED) problems.push(`only ${limited} of ${count} answered 429; expected at least ${count - ALLOWED}`);
  const errors = Object.entries(counts).filter(([status]) => Number(status) >= 500);
  if (errors.length) problems.push(`server errors: ${errors.map(([status, n]) => `${n} × ${status}`).join(', ')}`);
  return problems;
}

/** Sends the burst and counts each status; a request that fails outright counts as "error". */
export async function burst(base, count) {
  const counts = {};
  const url = new URL('/api/link', base).href;
  for (let sent = 0; sent < count; sent += WAVE) {
    const wave = Array.from({ length: Math.min(WAVE, count - sent) }, () =>
      fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: BODY })
        .then(async response => {
          await response.body?.cancel();
          return response.status;
        })
        .catch(() => 'error'));
    for (const status of await Promise.all(wave)) counts[status] = (counts[status] ?? 0) + 1;
  }
  return counts;
}

async function main() {
  const base = process.argv[2];
  const count = Number(process.argv[3] ?? 50);
  if (!base || !(count > 0)) {
    console.error('usage: node burst.mjs <base URL> [count=50]');
    process.exit(2);
  }
  const counts = await burst(base, count);
  for (const [status, n] of Object.entries(counts)) console.log(`${String(n).padStart(4)} × ${status}`);
  const problems = evaluateBurst(counts, count);
  console.log(problems.length ? `FAIL  ${problems.join('; ')}` : `PASS  the firewall answered 429 after ${ALLOWED}`);
  process.exit(problems.length ? 1 : 0);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) await main();
