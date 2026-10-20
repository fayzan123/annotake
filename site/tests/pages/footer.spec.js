// The footer: the full logo, whose tripod opens into the A when it comes into view, and the legal row.
import { expect, pauseClock, test, watchErrors } from './support.js';

/** The two legs' points, read from the live SVG. */
const legs = page => page.locator('.giant svg').evaluate(svg => {
  const read = polygon => polygon.getAttribute('points').trim().split(/\s+/).map(pair => pair.split(',').map(Number));
  const [left, right] = svg.querySelectorAll('polygon.leg');
  return { left: read(left), right: read(right) };
});

const near = (a, b, tolerance = 0.02) => Math.abs(a - b) <= tolerance;

/** Closed: the two legs are mirror images over the middle, covering the same stem. */
function isClosed({ left, right }) {
  const xs = leg => leg.map(([x]) => x);
  return near(Math.min(...xs(left)), Math.min(...xs(right))) && near(Math.max(...xs(left)), Math.max(...xs(right)))
    && left.every(([x, y], i) => near(121 - x, right[i][0]) && near(y, right[i][1]));
}

/** Open: the legs are the brand's A (BrandMark's left leg). */
function isOpen({ left }) {
  const expected = [[0, 0], [21.89, 0], [76.52, -112], [54.63, -112]];
  return left.every(([x, y], i) => near(x, expected[i][0]) && near(y, expected[i][1]));
}

const sweepOffset = page => page.locator('.giant svg circle.sweep').evaluate(circle => Number(circle.getAttribute('stroke-dashoffset')));

async function scrollToLogo(page) {
  await page.locator('.giant').evaluate(node => node.scrollIntoView({ block: 'end' }));
  await expect(page.locator('.giant')).toHaveAttribute('data-visible', 'true');
}

test('scrolled into view, the legs open into the A, and then the front reel winds red', async ({ page }) => {
  await pauseClock(page);
  await page.goto('/');
  await expect(page.locator('.giant svg polygon.leg')).toHaveCount(2);
  expect(isClosed(await legs(page))).toBe(true);
  await scrollToLogo(page);
  await page.clock.runFor(40);
  expect(isClosed(await legs(page))).toBe(true);
  await page.clock.runFor(1210);
  expect(isOpen(await legs(page))).toBe(true);
  expect(await sweepOffset(page)).toBeGreaterThan(0);
  await page.clock.runFor(650);
  expect(await sweepOffset(page)).toBeCloseTo(0, 6);
  const rect = await page.locator('.giant svg rect.brace').evaluate(node => ({
    x: Number(node.getAttribute('x')), width: Number(node.getAttribute('width')),
  }));
  expect(rect.x).toBeCloseTo(29.48, 1);
  expect(rect.width).toBeCloseTo(62.04, 1);
});

test('scrolling away closes it again, ready to replay', async ({ page }) => {
  await pauseClock(page);
  await page.goto('/');
  await scrollToLogo(page);
  await page.clock.runFor(2000);
  expect(isOpen(await legs(page))).toBe(true);
  await page.evaluate(() => window.scrollTo(0, 0));
  await expect(page.locator('.giant')).toHaveAttribute('data-visible', 'false');
  expect(isClosed(await legs(page))).toBe(true);
  expect(await sweepOffset(page)).toBeGreaterThan(100);
  await scrollToLogo(page);
  await page.clock.runFor(1300);
  expect(isOpen(await legs(page))).toBe(true);
});

test('the live logo keeps the static one’s name for screen readers', async ({ page }) => {
  await page.goto('/');
  const svg = page.locator('.giant svg');
  await expect(svg).toHaveCount(1);
  await expect(svg).toHaveAttribute('role', 'img');
  await expect(svg).toHaveAttribute('aria-label', 'Annotake');
  await expect(svg).toHaveAttribute('viewBox', '-6 -245.68 644.06 253.11');
});

test('with Reduce Motion on, the logo is open and wound at load, and stays so', async ({ openPage }) => {
  const page = await openPage({ reducedMotion: 'reduce' });
  await pauseClock(page);
  await page.goto('/');
  expect(isOpen(await legs(page))).toBe(true);
  expect(await sweepOffset(page)).toBeCloseTo(0, 6);
  await page.locator('.giant').evaluate(node => node.scrollIntoView({ block: 'end' }));
  await page.clock.runFor(3000);
  expect(isOpen(await legs(page))).toBe(true);
  await expect(page.locator('.giant')).not.toHaveAttribute('data-visible', /.*/);
});

test('without JavaScript, the static logo shows', async ({ openPage }) => {
  const page = await openPage({ javaScriptEnabled: false });
  await page.goto('/');
  const use = page.locator('.giant svg use');
  await expect(use).toHaveAttribute('href', '/assets/img/brand.svg#logo');
  await expect.poll(async () => (await use.boundingBox())?.width ?? 0).toBeGreaterThan(300);
});

test('the legal row, exactly', async ({ page }) => {
  await page.goto('/');
  const legal = page.locator('footer .legal');
  await expect(legal.locator('> span')).toHaveText('Made in Ontario, Canada');
  const links = legal.locator('nav a');
  await expect(links).toHaveText(['Privacy', 'Terms']);
  expect(await links.evaluateAll(all => all.map(a => a.getAttribute('href')))).toEqual(['/privacy', '/terms']);
});

// /privacy says big changes are noted on the home page: the email list was one (Checkpoint 5), and the email becoming
// optional is another (design §13). The note stays until
// the policy changes again.
test('the legal row notes the privacy policy’s change', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('footer .legal .policy-note'))
    .toHaveText('Privacy policy updated: giving the app your email is optional.');
});

test('the footer plays with no console errors', async ({ page }) => {
  const errors = await watchErrors(page);
  await pauseClock(page);
  await page.goto('/');
  await scrollToLogo(page);
  await page.clock.runFor(2500);
  expect(errors).toEqual([]);
});
