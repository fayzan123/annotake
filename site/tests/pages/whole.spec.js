// Whole-page checks, on every page, in light and dark: errors, accessibility, cookies, third parties, widths, and the
// keyboard. Then, in Chrome, the weight of the first load, Reduce Motion, and the page without JavaScript.
import AxeBuilder from '@axe-core/playwright';
import { PAGES, PHONE } from '../expected.js';
import { expect, pauseClock, test, useTheme, watchErrors } from './support.js';

const WIDTHS = [320, 360, 768, 1280, 1440, 2560];
/** The one request that leaves annotake.app: UsefulShelf's badge, whose checker wants its own image URL. /privacy names
 *  it. The tests answer it with a stand-in, so they never reach usefulshelf.co. */
const USEFULSHELF_BADGE = 'https://usefulshelf.co/badge/usefulshelf.svg';
const STAND_IN = '<svg xmlns="http://www.w3.org/2000/svg" width="248" height="66"><rect width="248" height="66"/></svg>';

/** Records every request, and every response that tries to set a cookie. */
function watchNetwork(page) {
  const requests = [];
  const cookies = [];
  page.on('request', request => requests.push(request.url()));
  page.on('response', async response => {
    const headers = await response.headersArray().catch(() => []);
    if (headers.some(({ name }) => name.toLowerCase() === 'set-cookie')) cookies.push(response.url());
  });
  return { requests, cookies };
}

for (const theme of ['light', 'dark']) {
  for (const path of PAGES) {
    test(`${path} in ${theme}: clean, accessible, cookieless, first-party but for one badge, and never wider than the screen`, async ({ page, context, baseURL }) => {
      await useTheme(page, theme);
      const errors = await watchErrors(page);
      const network = watchNetwork(page);
      await page.route(USEFULSHELF_BADGE, route => route.fulfill({ contentType: 'image/svg+xml', body: STAND_IN }));
      await page.goto(path);
      await page.evaluate(() => document.fonts.ready);
      expect(await page.evaluate(() => document.documentElement.dataset.theme)).toBe(theme);

      const results = await new AxeBuilder({ page }).analyze();
      const serious = results.violations.filter(({ impact }) => impact === 'serious' || impact === 'critical');
      expect(serious.map(({ id, nodes }) => `${id}: ${nodes.map(node => node.target).join(', ')}`)).toEqual([]);

      for (const width of WIDTHS) {
        await page.setViewportSize({ width, height: 900 });
        expect(await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth), `${width} px`)
          .toBeLessThanOrEqual(0);
      }

      const origin = new URL(baseURL).origin;
      const elsewhere = network.requests.filter(url => !url.startsWith('data:') && new URL(url).origin !== origin);
      expect(elsewhere).toEqual(path === '/' ? [USEFULSHELF_BADGE] : []);
      expect(network.cookies).toEqual([]);
      expect(await context.cookies()).toEqual([]);
      expect(await page.evaluate(() => document.cookie)).toBe('');
      expect(errors).toEqual([]);
    });
  }
}

test('no cookie after the toggle and a link-form send either', async ({ openPage }) => {
  const page = await openPage(PHONE);
  const network = watchNetwork(page);
  await page.route('**/api/link', route => route.fulfill({ json: { ok: true } }));
  await page.goto('/');
  await page.locator('header .theme-toggle').click();
  await page.locator('section.hero details.getlink summary').click();
  await page.locator('#email-hero').fill('sam@example.com');
  await page.locator('section.hero form.linkform button[type="submit"]').click();
  await expect(page.locator('section.hero .linkform-sent')).toBeVisible();
  expect(network.cookies).toEqual([]);
  expect(await page.context().cookies()).toEqual([]);
  expect(await page.evaluate(() => document.cookie)).toBe('');
});

for (const [device, options, start] of [['a Mac', {}, 'section.hero .cta a.btn-lg'], ['an iPhone', PHONE, 'section.hero details.getlink summary']]) {
  test(`on ${device}, Tab reaches the header, the hero's action, and the final call, each with a visible focus ring`, async ({ openPage, browserName }) => {
    const page = await openPage(options);
    await page.goto('/');
    // Safari moves through buttons and links with Option-Tab, unless "Press Tab to highlight each item" is on.
    const tab = browserName === 'webkit' ? 'Alt+Tab' : 'Tab';
    const finalAction = start.replace('section.hero', 'section.final');
    const wanted = ['header a.home', 'header a.github', 'header .theme-toggle', ...(device === 'a Mac' ? ['header a.btn'] : []), start, finalAction];
    const reached = [];
    for (let i = 0; i < 30 && reached.length < wanted.length; i++) {
      await page.keyboard.press(tab);
      const focused = await page.evaluate(selectors => {
        const element = document.activeElement;
        const style = getComputedStyle(element);
        return {
          match: selectors.findIndex(selector => element.matches(selector)),
          outline: style.outlineStyle === 'none' ? 0 : parseFloat(style.outlineWidth),
          name: `${element.tagName.toLowerCase()}.${element.className}`,
        };
      }, wanted);
      expect(focused.outline, `${focused.name} shows its focus ring`).toBeGreaterThanOrEqual(2);
      if (focused.match === reached.length) reached.push(wanted[focused.match]);
    }
    expect(reached).toEqual(wanted);
  });
}

test.describe('in Chrome', () => {
  test.skip(({ browserName }) => browserName !== 'chromium', 'Chrome only');

  test('the first load weighs at most 200 KB, and the font at most 30 KB', async ({ page }) => {
    const sizes = [];
    page.on('requestfinished', async request => {
      if (new URL(request.url()).pathname.startsWith('/_vercel/insights/')) return;
      const { responseHeadersSize, responseBodySize } = await request.sizes();
      sizes.push({ url: request.url(), bytes: responseHeadersSize + responseBodySize });
    });
    await page.goto('/');
    await page.evaluate(() => document.fonts.ready);
    await page.waitForLoadState('networkidle');
    await expect.poll(() => sizes.length).toBeGreaterThan(5);
    const total = sizes.reduce((sum, { bytes }) => sum + bytes, 0);
    expect(total, sizes.map(({ url, bytes }) => `${bytes} ${url}`).join('\n')).toBeLessThanOrEqual(204_800);
    const font = sizes.find(({ url }) => url.endsWith('.woff2'));
    expect(font.bytes).toBeLessThanOrEqual(30 * 1024);
  });

  test('with Reduce Motion on, nothing in the gate, the steps, or the footer logo changes after load', async ({ openPage }) => {
    const page = await openPage({ reducedMotion: 'reduce' });
    await pauseClock(page);
    await page.goto('/');
    await page.evaluate(() => {
      window.mutations = 0;
      const observer = new MutationObserver(records => { window.mutations += records.length; });
      for (const selector of ['.gate-wrap', 'section.how', '.giant']) {
        observer.observe(document.querySelector(selector), { subtree: true, childList: true, attributes: true, characterData: true });
      }
    });
    await page.clock.runFor(30_000);
    expect(await page.evaluate(() => window.mutations)).toBe(0);
  });

  test('without JavaScript, the page renders, the download and the form are there, and the form posts', async ({ openPage }) => {
    const page = await openPage({ javaScriptEnabled: false });
    await page.goto('/');
    await expect(page.locator('h1')).toHaveText('Show any AI exactly what you see.');
    await expect(page.locator('section.hero a[href="/download"]')).toBeVisible();
    await expect(page.locator('section.final a[href="/download"]')).toBeVisible();
    const details = page.locator('section.hero details.getlink');
    await expect(details).toBeVisible();
    await details.locator('summary').click();
    await page.locator('#email-hero').fill('sam@example.com');
    await page.locator('section.hero form.linkform button[type="submit"]').click();
    await expect(page).toHaveURL(/\/api\/link$/);
    await expect(page.locator('h1')).toHaveText('Check your inbox');
  });
});
