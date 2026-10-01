import { PHONE, UA } from '../expected.js';
import { expect, pauseClock, test } from './support.js';

const HEADLINE = 'Show your coding agent exactly what happened.';
const LINE_1 = 'Press a key, do the thing in any app, and drag the card into Claude Code, Cursor, or ChatGPT.';
const LINE_2 = 'Each step comes out as a screenshot, captioned with what you clicked.';
const NOTE = 'Free during the beta · macOS 15 or later By downloading, you agree to the Terms.';
const HINT = 'Open Annotake.dmg, then drag Annotake to Applications.';

/** Wider than the viewport means sideways scrolling. */
const overflow = page => page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);

test.describe('on a Mac', () => {
  test('the hero offers the download, with its note, and the header has the button too', async ({ page }) => {
    await page.goto('/');
    expect(await page.evaluate(() => navigator.userAgent)).toMatch(/Macintosh/);
    const hero = page.locator('section.hero');
    await expect(hero.locator('h1')).toHaveText(HEADLINE);
    await expect(hero.locator('h1 span')).toHaveText('exactly what happened.');
    await expect(hero.locator('p.sub')).toHaveText(`${LINE_1} ${LINE_2}`);
    await expect(hero.locator('p.sub .sub-more')).toHaveText(LINE_2);
    const download = hero.locator('.cta a.btn.btn-lg');
    await expect(download).toBeVisible();
    await expect(download).toHaveText('Download for Mac');
    await expect(download).toHaveAttribute('href', '/download');
    await expect(hero.locator('.cta p.note.mac-only')).toHaveText(NOTE);
    await expect(hero.locator('.cta p.note.mac-only a')).toHaveAttribute('href', '/terms');
    await expect(hero.locator('details.getlink')).toBeHidden();
    await expect(hero.locator('.dl-hint')).toBeHidden();
    const header = page.locator('header .btn.mac-only');
    await expect(header).toBeVisible();
    await expect(header).toHaveText('Download for Mac');
    await expect(header).toHaveAttribute('href', '/download');
  });

  test('a download click says Downloading… for 2 s, and shows what to do next', async ({ page }) => {
    await pauseClock(page);
    await page.route('https://github.com/**', route => route.fulfill({
      status: 200,
      headers: { 'Content-Type': 'application/octet-stream', 'Content-Disposition': 'attachment; filename="Annotake.dmg"' },
      body: '',
    }));
    await page.goto('/');
    const download = page.locator('section.hero .cta a.btn-lg');
    // The browser follows the link to the disk image and stays on the page. (WebKit reports no download event for a
    // fulfilled attachment, so the test waits for the request.)
    const fetched = page.waitForRequest(request => request.url().startsWith('https://github.com/'));
    await download.click();
    await fetched;
    expect(new URL(page.url()).pathname).toBe('/');
    await expect(download).toHaveText('Downloading…');
    const hint = page.locator('section.hero .dl-hint');
    await expect(hint).toBeVisible();
    await expect(hint).toHaveText(HINT);
    await page.clock.runFor(1900);
    await expect(download).toHaveText('Downloading…');
    await page.clock.runFor(200);
    await expect(download).toHaveText('Download for Mac');
    await expect(hint).toBeVisible();
  });
});

test.describe('on an iPhone', () => {
  test.use(PHONE);

  test('the hero offers the link by email instead, and its line keeps only the first sentence', async ({ page }) => {
    await page.goto('/');
    const hero = page.locator('section.hero');
    const summary = hero.locator('details.getlink summary');
    await expect(summary).toBeVisible();
    await expect(summary).toHaveText('Email me the link');
    await expect(hero.locator('.link-note')).toHaveText(
      'Annotake is a Mac app. Get the link in your inbox and download it there.');
    await expect(hero.locator('a[href="/download"]')).toBeHidden();
    await expect(hero.locator('p.note.mac-only')).toBeHidden();
    await expect(page.locator('header a[href="/download"]')).toBeHidden();
    await expect(hero.locator('p.sub')).toBeVisible();
    await expect(hero.locator('p.sub .sub-more')).toBeHidden();
  });
});

test('an iPad asking for the desktop site (a Mac user agent with touch) gets the link by email', async ({ openPage }) => {
  const page = await openPage({ userAgent: UA.macSafari, viewport: { width: 1024, height: 1366 } });
  await page.addInitScript(() => Object.defineProperty(Navigator.prototype, 'maxTouchPoints', { get: () => 5 }));
  await page.goto('/');
  await expect(page.locator('section.hero details.getlink summary')).toBeVisible();
  await expect(page.locator('a[href="/download"]')).toHaveCount(2);
  for (const link of await page.locator('a[href="/download"]').all()) await expect(link).toBeHidden();
});

test('without JavaScript, both the download and the email link show, download first', async ({ openPage }) => {
  const page = await openPage({ javaScriptEnabled: false });
  await page.goto('/');
  const download = page.locator('section.hero .cta a.btn-lg');
  const summary = page.locator('section.hero details.getlink summary');
  await expect(download).toBeVisible();
  await expect(summary).toBeVisible();
  await expect(summary).toHaveText('Email me the link');
  const [a, b] = [await download.boundingBox(), await summary.boundingBox()];
  expect(b.y).toBeGreaterThan(a.y + a.height);
});

for (const width of [320, 1440]) {
  test(`no sideways scrolling at ${width} px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 });
    await page.goto('/');
    expect(await overflow(page)).toBeLessThanOrEqual(0);
  });
}
