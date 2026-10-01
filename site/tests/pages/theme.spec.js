import AxeBuilder from '@axe-core/playwright';
import { PAGES } from '../expected.js';
import { expect, test, useTheme, watchErrors } from './support.js';

const bg = page => page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue('--bg').trim().toLowerCase());
const theme = page => page.evaluate(() => document.documentElement.dataset.theme);

for (const [scheme, color] of [['light', '#ffffff'], ['dark', '#141416']]) {
  test(`the system's ${scheme} setting sets the theme`, async ({ openWithScheme }) => {
    const page = await openWithScheme(scheme);
    await page.goto('/');
    expect(await theme(page)).toBe(scheme);
    expect(await bg(page)).toBe(color);
  });
}

test('the toggle switches the theme, keeps it across a reload, and says what it will do', async ({ openWithScheme }) => {
  const page = await openWithScheme('light');
  await page.goto('/');
  const toggle = page.locator('header .theme-toggle');
  await expect(toggle).toHaveAttribute('aria-label', 'Switch to dark theme');
  await expect(toggle.locator('.sun')).toBeVisible();
  await expect(toggle.locator('.moon')).toBeHidden();
  await toggle.click();
  expect(await theme(page)).toBe('dark');
  expect(await bg(page)).toBe('#141416');
  await expect(toggle).toHaveAttribute('aria-label', 'Switch to light theme');
  await expect(toggle.locator('.moon')).toBeVisible();
  await expect(toggle.locator('.sun')).toBeHidden();
  await page.reload();
  expect(await theme(page)).toBe('dark');
  await expect(toggle).toHaveAttribute('aria-label', 'Switch to light theme');
  await toggle.click();
  expect(await theme(page)).toBe('light');
});

test('the theme is set before the first paint: boot.js is the first script in <head>, and blocking', async ({ page }) => {
  await page.goto('/');
  const first = await page.evaluate(() => {
    const script = document.head.querySelector('script');
    return { src: script.getAttribute('src'), async: script.async, defer: script.defer, type: script.type };
  });
  expect(first).toEqual({ src: '/assets/boot.js', async: false, defer: false, type: '' });
});

test('with storage blocked, the page still renders, follows the system, and the toggle switches', async ({ openWithScheme }) => {
  const page = await openWithScheme('dark');
  await page.addInitScript(() => {
    Object.defineProperty(window, 'localStorage', {
      configurable: true,
      get() { throw new DOMException('The operation is insecure.', 'SecurityError'); },
    });
  });
  const errors = await watchErrors(page);
  await page.goto('/');
  await expect(page.locator('h1')).toBeVisible();
  expect(await theme(page)).toBe('dark');
  await page.locator('header .theme-toggle').click();
  expect(await theme(page)).toBe('light');
  expect(errors).toEqual([]);
});

test('Jost is the type, and it loads', async ({ page }) => {
  await page.goto('/');
  const family = await page.locator('h1').evaluate(h1 => getComputedStyle(h1).fontFamily);
  expect(family.replace(/["']/g, '')).toMatch(/^Jost/);
  expect(await page.evaluate(async () => {
    await document.fonts.ready;
    return document.fonts.check('600 16px Jost');
  })).toBe(true);
});

test("the header's logo renders from the sprite", async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('header a[href="/"]')).toHaveAttribute('aria-label', 'Annotake home');
  const use = page.locator('header a[href="/"] svg.logo use');
  await expect(use).toHaveAttribute('href', '/assets/img/brand.svg#logo');
  await expect.poll(async () => (await use.boundingBox())?.width ?? 0).toBeGreaterThan(0);
});

test('without JavaScript, the system setting still picks the colors', async ({ openWithScheme }) => {
  const page = await openWithScheme('dark', { javaScriptEnabled: false });
  await page.goto('/');
  expect(await page.evaluate(() => getComputedStyle(document.body).backgroundColor)).toBe('rgb(20, 20, 22)');
  await expect(page.locator('header .theme-toggle')).toBeHidden();
});

for (const path of PAGES) {
  test(`${path} loads Vercel Web Analytics last in <head>, deferred`, async ({ page }) => {
    await page.goto(path);
    const last = await page.evaluate(() => {
      const element = document.head.lastElementChild;
      return { tag: element.tagName, src: element.getAttribute('src'), defer: element.defer };
    });
    expect(last).toEqual({ tag: 'SCRIPT', src: '/_vercel/insights/script.js', defer: true });
  });
}

for (const scheme of ['light', 'dark']) {
  test(`the frame's colors pass axe's contrast check in ${scheme}`, async ({ page }) => {
    await useTheme(page, scheme);
    await page.goto('/');
    expect(await theme(page)).toBe(scheme);
    await page.evaluate(() => document.fonts.ready);
    const results = await new AxeBuilder({ page }).withRules(['color-contrast']).analyze();
    expect(results.violations).toEqual([]);
  });
}
