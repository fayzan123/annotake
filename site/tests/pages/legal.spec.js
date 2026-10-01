// The privacy policy, the Terms, the third-party licenses, and the 404 page.
import AxeBuilder from '@axe-core/playwright';
import { expect, test, useTheme } from './support.js';

const UPDATED = 'Last updated: October 1, 2026';

const PAGES = {
  '/privacy': {
    title: 'Privacy policy · Annotake',
    h1: 'Privacy policy',
    h2s: ['The short version', 'The Annotake app', 'This website', 'The link email', 'Who else sees data', 'Your rights',
      'Children', 'Changes'],
    phrases: ['Nothing you record leaves your Mac', 'This website doesn’t use cookies', 'Vercel Web Analytics', 'Resend',
      '30 days', 'GitHub', 'United States', 'We never sell', 'before that version ships',
      'Office of the Privacy Commissioner of Canada', 'Fayzan Malik', 'Ontario, Canada'],
  },
  '/terms': {
    title: 'Terms · Annotake',
    h1: 'Terms',
    h2s: ['Who we are', 'The beta', 'Your license', 'Your recordings', 'No warranty', 'Limitation of liability',
      'Trademarks', 'Open-source software', 'Ending', 'Governing law', 'Changes'],
    phrases: ['free during the beta', 'as is', 'reverse-engineer',
      'Claude Code, Cursor, ChatGPT, Mac, and macOS are trademarks of their owners',
      'isn’t affiliated with or endorsed by them', 'Ontario'],
  },
};

for (const [path, page] of Object.entries(PAGES)) {
  test(`${path}: its title, its sections in order, and every phrase it promises`, async ({ page: tab }) => {
    const response = await tab.goto(path);
    expect(response.status()).toBe(200);
    await expect(tab).toHaveTitle(page.title);
    await expect(tab.locator('main h1')).toHaveText(page.h1);
    await expect(tab.locator('main .updated')).toHaveText(UPDATED);
    await expect(tab.locator('main h2')).toHaveText(page.h2s);
    const text = (await tab.locator('main').textContent()).replace(/\s+/g, ' ');
    for (const phrase of page.phrases) expect(text, phrase).toContain(phrase);
    await expect(tab.locator('header a[href="/"]')).toBeVisible();
    await expect(tab.locator('footer .legal')).toContainText('© 2026 Fayzan Malik · Made in Ontario, Canada');
    await expect(tab.locator('footer .giant svg use')).toHaveAttribute('href', '/assets/img/brand.svg#logo');
  });
}

test('the Terms link the two licenses and the privacy policy', async ({ page }) => {
  await page.goto('/terms');
  await expect(page.locator('main a[href="/licenses/sparkle.txt"]')).toHaveCount(1);
  await expect(page.locator('main a[href="/licenses/jost-ofl.txt"]')).toHaveCount(1);
  await expect(page.locator('main a[href="/privacy"]')).not.toHaveCount(0);
});

// annotake.app receives no mail, so no page gives an address.
for (const path of ['/', '/privacy', '/terms', '/nope']) {
  test(`${path} shows no email address`, async ({ page }) => {
    await page.goto(path);
    await expect(page.locator('a[href^="mailto:"]')).toHaveCount(0);
    expect(await page.locator('body').textContent()).not.toMatch(/[^\s@]+@[^\s@]+\.[a-z]{2,}/i);
  });
}

test('the licenses are published as plain text', async ({ request }) => {
  const sparkle = await request.get('/licenses/sparkle.txt');
  expect(sparkle.status()).toBe(200);
  expect(sparkle.headers()['content-type']).toBe('text/plain; charset=utf-8');
  const sparkleText = await sparkle.text();
  expect(sparkleText).toContain('Andy Matuschak');
  expect(sparkleText).toContain('bsdiff');
  const jost = await request.get('/licenses/jost-ofl.txt');
  expect(jost.status()).toBe(200);
  expect(jost.headers()['content-type']).toBe('text/plain; charset=utf-8');
  expect(await jost.text()).toContain('SIL OPEN FONT LICENSE');
});

test('an unknown path answers 404, with a way home', async ({ page }) => {
  const response = await page.goto('/nope');
  expect(response.status()).toBe(404);
  await expect(page.locator('main h1')).toHaveText('This page doesn’t exist.');
  const home = page.locator('main a', { hasText: 'Go to annotake.app' });
  await expect(home).toHaveAttribute('href', '/');
});

for (const theme of ['light', 'dark']) {
  for (const path of ['/privacy', '/terms', '/nope']) {
    test(`axe finds nothing on ${path} in ${theme}`, async ({ page }) => {
      await useTheme(page, theme);
      await page.goto(path);
      await page.evaluate(() => document.fonts.ready);
      const results = await new AxeBuilder({ page }).analyze();
      expect(results.violations.map(({ id, nodes }) => `${id}: ${nodes.map(node => node.target).join(', ')}`)).toEqual([]);
    });
  }
}
