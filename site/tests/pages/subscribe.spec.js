// The email list's functions through the local server, which runs them in dry-run mode and checks unsubscribe links
// against its test secret (server.mjs): what the app's sign-up gets back, and the welcome email's unsubscribe link.
import AxeBuilder from '@axe-core/playwright';
import { readFileSync } from 'node:fs';
import { unsubscribeUrl } from '../../api/_lib/unsubscribe-token.js';
import { CSP } from '../expected.js';
import { expect, test, watchErrors } from './support.js';

/** server.mjs's UNSUBSCRIBE_SECRET. */
const SECRET = 'test-secret';

/** What the app sends (EmailSignup.request), word for word: EmailSignupTests checks the app sends this text. */
const APP_REQUEST = JSON.parse(readFileSync(new URL('../subscribe-request.json', import.meta.url), 'utf8')).body;
const SIGNUP = JSON.parse(APP_REQUEST);

/** The longest address /api/subscribe takes, with nowhere to break a line: 254 characters, 64 of them before the @. */
const LONGEST = `${'a'.repeat(64)}@${'b'.repeat(185)}.com`;

/** The welcome email's unsubscribe link for `address`, as a path on the local server, signed under `secret`. */
function link(address, secret = SECRET) {
  const { pathname, search } = new URL(unsubscribeUrl(address, secret));
  return pathname + search;
}

test('POST /api/subscribe takes what the app sends, and turns away a news that isn’t true or false', async ({ request }) => {
  const added = await request.post('/api/subscribe', {
    data: APP_REQUEST, headers: { 'content-type': 'application/json' },
  });
  expect(added.status()).toBe(200);
  expect(await added.json()).toEqual({ ok: true });
  // 422, which the app retries: only an address the site won't take is 400, which clears it.
  const refused = await request.post('/api/subscribe', { data: { ...SIGNUP, news: 'yes' } });
  expect(refused.status()).toBe(422);
  expect(await refused.json()).toEqual({ ok: false, reason: 'request' });
  const address = await request.post('/api/subscribe', { data: { ...SIGNUP, email: 'sam@example' } });
  expect(address.status()).toBe(400);
  expect(await address.json()).toEqual({ ok: false, reason: 'invalid' });
});

test('GET /api/subscribe answers 405', async ({ request }) => {
  const response = await request.get('/api/subscribe');
  expect(response.status()).toBe(405);
  expect(response.headers().allow).toBe('POST');
});

test('GET /api/unsubscribe shows a signed link’s confirm form, and answers 400 to a bad signature', async ({ request }) => {
  const shown = await request.get(link('sam@example.com'));
  expect(shown.status()).toBe(200);
  expect(shown.headers()['content-type']).toBe('text/html; charset=utf-8');
  const html = await shown.text();
  expect(html).toContain('<p>Unsubscribe sam@example.com from all Annotake emails?</p>');
  expect(html).toContain(`<form method="post" action="${link('sam@example.com').replace('&', '&amp;')}">`);
  // The right shape, signed under a secret that isn't the server's.
  const refused = await request.get(link('sam@example.com', 'another-secret'));
  expect(refused.status()).toBe(400);
  expect(await refused.text()).toContain('<h1>This unsubscribe link isn’t valid.</h1>');
});

// Two rules keep it out: no file in api/ is served, and nothing under a `_` name runs as a function.
test('the functions’ shared code is never served or run: /api/_lib/consent.json and /api/_lib/resend answer 404', async ({ request }) => {
  for (const path of ['/api/_lib/consent.json', '/api/_lib/resend']) {
    const response = await request.get(path);
    expect(response.status(), path).toBe(404);
    expect(await response.text(), path).toContain('<h1>This page doesn’t exist.</h1>');
  }
});

test('on a 320 px phone, the confirm page fits the longest address, and its button unsubscribes it', async ({ page }) => {
  const errors = await watchErrors(page);
  await page.setViewportSize({ width: 320, height: 568 });
  const response = await page.goto(link(LONGEST));
  expect(response.status()).toBe(200);
  // So no error below means the CSP blocked nothing.
  expect(response.headers()['content-security-policy']).toBe(CSP);
  await page.evaluate(() => document.fonts.ready);
  const question = page.locator('main p').first();
  await expect(question).toHaveText(`Unsubscribe ${LONGEST} from all Annotake emails?`);
  // Never wider than the screen, and wrapped, not cut off: nothing spills out of the paragraph either.
  expect(await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth), 'past the screen')
    .toBeLessThanOrEqual(0);
  expect(await question.evaluate(p => p.scrollWidth - p.clientWidth), 'past the paragraph').toBeLessThanOrEqual(0);

  const results = await new AxeBuilder({ page }).analyze();
  const serious = results.violations.filter(({ impact }) => impact === 'serious' || impact === 'critical');
  expect(serious.map(({ id, nodes }) => `${id}: ${nodes.map(node => node.target).join(', ')}`)).toEqual([]);

  // The form posts back to the link, which still verifies.
  await page.getByRole('button', { name: 'Unsubscribe' }).click();
  await expect(page.locator('main h1')).toHaveText('You’re unsubscribed.');
  expect(errors).toEqual([]);
});
