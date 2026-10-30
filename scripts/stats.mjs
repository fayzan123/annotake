// make stats: how Annotake is doing. GitHub's download counts for every release (with gh), and, with Upstash's
// UPSTASH_REDIS_REST_URL and UPSTASH_REDIS_REST_TOKEN (or Vercel KV's KV_REST_API_* names) in the environment or in
// site/.env.local, the last DAYS UTC days of distinct Macs that checked for updates, by version (site/api/appcast.js).
// It only reads.
import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';

const DAYS = Number(process.env.DAYS ?? 14);
const RELEASES = 'fayzan123/annotake-releases';
const ENV_FILE = new URL('../site/.env.local', import.meta.url);

if (existsSync(ENV_FILE)) process.loadEnvFile(ENV_FILE);

function downloads() {
  const releases = JSON.parse(execFileSync('gh', ['api', `repos/${RELEASES}/releases`, '--paginate'],
    { encoding: 'utf8' }));
  let dmg = 0, zip = 0;
  console.log('Downloads (GitHub)');
  for (const release of releases) {
    const count = name => release.assets.find(asset => asset.name === name)?.download_count ?? 0;
    dmg += count('Annotake.dmg');
    zip += count('Annotake.zip');
    console.log(`  ${release.tag_name.padEnd(16)} ${release.published_at.slice(0, 10)}  ` +
      `disk image ${String(count('Annotake.dmg')).padStart(4)}  updates ${String(count('Annotake.zip')).padStart(4)}`);
  }
  console.log(`  ${'all'.padEnd(16)} ${''.padEnd(10)}  disk image ${String(dmg).padStart(4)}  updates ${String(zip).padStart(4)}`);
}

async function redis(commands) {
  const url = (process.env.UPSTASH_REDIS_REST_URL ?? process.env.KV_REST_API_URL).replace(/\/+$/, '');
  const token = process.env.UPSTASH_REDIS_REST_TOKEN ?? process.env.KV_REST_API_TOKEN;
  const response = await fetch(`${url}/pipeline`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(commands),
  });
  if (!response.ok) throw new Error(`Upstash answered ${response.status}`);
  return (await response.json()).map(({ result, error }) => {
    if (error) throw new Error(`Upstash: ${error}`);
    return result;
  });
}

async function macs() {
  console.log('\nMacs that checked for updates (annotake.app), by UTC day');
  if (!(process.env.UPSTASH_REDIS_REST_URL ?? process.env.KV_REST_API_URL)) {
    console.log('  no Upstash URL and token: set them, or put them in site/.env.local');
    return;
  }
  const today = Date.now();
  const days = Array.from({ length: DAYS }, (_, i) => new Date(today - i * 86_400_000).toISOString().slice(0, 10));
  // HGETALL answers a flat [field, value, …] list: the versions seen that day, and their checks.
  const hashes = (await redis(days.map(day => ['HGETALL', `checks:${day}`]))).map(flat => {
    const versions = {};
    for (let i = 0; i < flat.length; i += 2) versions[flat[i]] = Number(flat[i + 1]);
    return versions;
  });
  const commands = days.flatMap((day, i) => {
    const keys = Object.keys(hashes[i]).map(version => `installs:${day}:${version}`);
    return keys.length ? [['PFCOUNT', ...keys], ...keys.map(key => ['PFCOUNT', key])] : [];
  });
  const counts = commands.length ? await redis(commands) : [];
  let at = 0;
  days.forEach((day, i) => {
    const versions = Object.keys(hashes[i]).sort();
    if (!versions.length) return console.log(`  ${day}  0`);
    const total = counts[at++];
    const each = versions.map(version => `${version}: ${counts[at++]}`).join(', ');
    const checks = Object.values(hashes[i]).reduce((sum, n) => sum + n, 0);
    console.log(`  ${day}  ${String(total).padStart(4)} Macs  (${each}; ${checks} checks)`);
  });
}

downloads();
await macs();
