// Through the gate: the hero's strip of film. Times are from load, on a paused clock.
import { expect, pauseClock, test, watchErrors } from './support.js';

const CAPTIONS = [
  '1/3 · 0:01 · Clicked tab "Appearance"',
  '2/3 · 0:02 · Clicked switch "Dark mode"',
  '3/3 · 0:04 · Clicked button "Save"',
];

const pill = page => page.locator('.gate-wrap .gate .pill-text');
const slot = (page, i) => page.locator('.gate-wrap .track .slot').nth(i + 3);
const k = page => page.locator('.gate-wrap .strip').evaluate(el => getComputedStyle(el).getPropertyValue('--k').trim());
const shownCaptions = page => page.locator('.gate-wrap .cap.show');

async function expectCaptioned(page, i) {
  const frame = slot(page, i);
  await expect(frame.locator('.cap')).toHaveClass(/\bshow\b/);
  await expect(frame.locator('.cap b')).toHaveText(CAPTIONS[i]);
  await expect(frame.locator('.cap span')).toHaveText('Acme — Settings');
  await expect(frame.locator('.acme .ring')).toHaveClass(/\bshow\b/);
}

async function load(page) {
  await pauseClock(page);
  await page.goto('/');
}

test('the strip: ten slots, the gate with its corners and pill, all hidden from screen readers', async ({ page }) => {
  await load(page);
  const wrap = page.locator('section.gate-wrap');
  await expect(wrap).toHaveAttribute('aria-hidden', 'true');
  await expect(wrap.locator('.strip .track .slot')).toHaveCount(10);
  await expect(wrap.locator('.strip .holes.top')).toHaveCount(1);
  await expect(wrap.locator('.strip .holes.bottom')).toHaveCount(1);
  await expect(wrap.locator('.gate .corner')).toHaveCount(4);
  await expect(wrap.locator('.gate .flash')).toHaveCount(1);
  await expect(wrap.locator('.gate .pill .dot')).toHaveCount(1);
  await expect(wrap.locator('.track .pill')).toHaveCount(0);
  for (const each of await wrap.locator('.slot').all()) {
    await expect(each.locator('.frame .acme')).toHaveCount(1);
    await expect(each.locator('.frame .cap span')).toHaveText('Acme — Settings');
    await expect(each.locator('.unexposed')).toHaveCount(1);
  }
});

test('at load, the pill reads 0:00 · 0 frames, and no caption shows', async ({ page }) => {
  await load(page);
  await expect(pill(page)).toHaveText('0:00 · 0 frames');
  await expect(shownCaptions(page)).toHaveCount(0);
  expect(await k(page)).toBe('0');
});

test('at 2450 ms, the first frame has its ring and caption, and the strip has moved one frame', async ({ page }) => {
  await load(page);
  await page.clock.runFor(2450);
  await expectCaptioned(page, 0);
  await expect(shownCaptions(page)).toHaveCount(1);
  await expect(pill(page)).toHaveText('0:01 · 1 frame');
  expect(await k(page)).toBe('1');
});

test('at 7700 ms, three captioned frames, and the third shows the toast', async ({ page }) => {
  await load(page);
  await page.clock.runFor(7700);
  for (const i of [0, 1, 2]) await expectCaptioned(page, i);
  await expect(pill(page)).toHaveText('0:04 · 3 frames');
  expect(await k(page)).toBe('3');
  const toast = slot(page, 2).locator('.acme .toast');
  await expect(toast).toHaveText('Couldn’t save settings');
  await expect(toast).toHaveClass(/\bshow\b/);
  await expect(slot(page, 1).locator('.acme .toast')).not.toHaveClass(/\bshow\b/);
});

test('at 10000 ms, the loop has started again', async ({ page }) => {
  await load(page);
  await page.clock.runFor(10000);
  await expect(pill(page)).toHaveText('0:00 · 0 frames');
  await expect(shownCaptions(page)).toHaveCount(0);
  expect(await k(page)).toBe('0');
});

test('off screen, the loop holds; back on screen, it carries on', async ({ page }) => {
  // A short window, so the gate starts below it and can be scrolled fully out of view.
  await page.setViewportSize({ width: 1280, height: 400 });
  await load(page);
  const wrap = page.locator('section.gate-wrap');
  await expect(wrap).toHaveAttribute('data-visible', 'false');
  await page.clock.runFor(5000);
  await expect(pill(page)).toHaveText('0:00 · 0 frames');
  const showGate = () => wrap.evaluate(node => node.scrollIntoView({ block: 'center' }));
  await showGate();
  await expect(wrap).toHaveAttribute('data-visible', 'true');
  await page.clock.runFor(2450);
  await expect(pill(page)).toHaveText('0:01 · 1 frame');
  await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
  await expect(wrap).toHaveAttribute('data-visible', 'false');
  const before = await wrap.innerHTML();
  await page.clock.runFor(10000);
  expect(await wrap.innerHTML()).toBe(before);
  await showGate();
  await expect(wrap).toHaveAttribute('data-visible', 'true');
  await page.clock.runFor(1200);
  await expect(pill(page)).toHaveText('0:02 · 2 frames');
});

test('with Reduce Motion on, the strip is a still of the finished recording', async ({ openPage }) => {
  const page = await openPage({ reducedMotion: 'reduce' });
  await load(page);
  for (const i of [0, 1, 2]) await expectCaptioned(page, i);
  await expect(slot(page, 3).locator('.acme .toast')).toHaveClass(/\bshow\b/);
  await expect(slot(page, 3).locator('.unexposed')).toHaveClass(/\bopen\b/);
  await expect(pill(page)).toHaveText('0:04 · 3 frames');
  expect(await k(page)).toBe('3');
  const before = await page.locator('section.gate-wrap').innerHTML();
  await page.clock.runFor(20000);
  expect(await page.locator('section.gate-wrap').innerHTML()).toBe(before);
});

test('a whole loop runs with no console errors, inline styles included', async ({ page }) => {
  const errors = await watchErrors(page);
  await load(page);
  await page.clock.runFor(10000);
  expect(errors).toEqual([]);
});

test('at 320 px wide, the gate sits in the middle', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 800 });
  await load(page);
  const box = await page.locator('.gate-wrap .gate').boundingBox();
  expect(Math.abs(box.x + box.width / 2 - 160)).toBeLessThanOrEqual(2);
});
