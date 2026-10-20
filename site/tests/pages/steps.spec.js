// How it works: three captioned frames, each playing only while it's on screen. Times are from the moment a figure
// comes into view, on a paused clock.
import { expect, pauseClock, test, watchErrors } from './support.js';

const CAPTIONS = [
  ['step-key', '1/3 · Double-tap your key', 'Right ⌘ out of the box, or Right ⌥ or fn. Double-tap again when you’re done.'],
  ['step-click', '2/3 · Click through it', 'Each step comes out as a screenshot, captioned with what you clicked.'],
  ['step-drag', '3/3 · Drag the card into your AI', 'ChatGPT, Claude, Cursor, or anything else that takes images.'],
];
const CHIPS = ['1/3 Clicked tab "Appearance"', '2/3 Clicked switch "Dark mode"', '3/3 Clicked button "Save"'];
const TYPED = "dark mode doesn't stick after Save";

/** Brings a figure into view and waits until it knows. */
async function show(page, id) {
  const figure = page.locator(`#${id}`);
  await figure.evaluate(node => node.scrollIntoView({ block: 'center' }));
  await expect(figure).toHaveAttribute('data-visible', 'true');
  return figure;
}

async function load(page) {
  await pauseClock(page);
  await page.goto('/');
}

test('the heading and the three captions, exactly', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('section.how h2')).toHaveText('How it works');
  await expect(page.locator('section.how figure.step')).toHaveCount(3);
  for (const [id, line1, line2] of CAPTIONS) {
    await expect(page.locator(`#${id} figcaption.stepcap b`)).toHaveText(line1);
    await expect(page.locator(`#${id} figcaption.stepcap span`)).toHaveText(line2);
    await expect(page.locator(`#${id} .canvas`)).toHaveAttribute('aria-hidden', 'true');
  }
});

test('without JavaScript, the captions are there and the frames show', async ({ openPage }) => {
  const page = await openPage({ javaScriptEnabled: false });
  await page.goto('/');
  for (const [id, line1, line2] of CAPTIONS) {
    const figure = page.locator(`#${id}`);
    await expect(figure.locator('figcaption b')).toHaveText(line1);
    await expect(figure.locator('figcaption span')).toHaveText(line2);
    expect(await figure.evaluate(node => getComputedStyle(node).opacity)).toBe('1');
  }
});

test('step 1: a double-tap starts the recording, and the key cycles ⌘, ⌥, fn', async ({ page }) => {
  await load(page);
  const figure = await show(page, 'step-key');
  const pill = figure.locator('.pill');
  const menubar = figure.locator('.menubar');
  await expect(figure.locator('.keycap .glyph')).toHaveText('⌘');
  await expect(figure.locator('.keycap .word')).toHaveText('command');
  await expect(figure.locator('.keyname b')).toHaveText('Right ⌘');
  await expect(figure.locator('.keyname small')).toHaveText('or Right ⌥, or fn');
  await expect(pill).not.toHaveClass(/\bshow\b/);
  await page.clock.runFor(1300);
  await expect(pill).toHaveClass(/\bshow\b/);
  await expect(pill).toHaveText('0:00 · 0 frames · double-tap ⌘ to stop');
  await expect(menubar).toHaveClass(/\brec\b/);
  await page.clock.runFor(2000);
  await expect(pill).toHaveText('0:02 · 0 frames · double-tap ⌘ to stop');
  await page.clock.runFor(1200);
  await expect(pill).not.toHaveClass(/\bshow\b/);
  await expect(menubar).not.toHaveClass(/\brec\b/);
  await page.clock.runFor(2300);
  await expect(figure.locator('.keycap .glyph')).toHaveText('⌥');
  await expect(figure.locator('.keycap .word')).toHaveText('option');
  await expect(figure.locator('.keyname b')).toHaveText('Right ⌥');
  await expect(figure.locator('.keyname small')).toHaveText('or Right ⌘, or fn');
  await expect(pill).toHaveText('0:00 · 0 frames · double-tap ⌥ to stop');
  await expect(pill).toHaveClass(/\bshow\b/);
  await page.clock.runFor(5490);
  await expect(figure.locator('.keycap .glyph')).toHaveText('fn');
  await expect(figure.locator('.keycap .word')).toHaveText('globe');
  await expect(figure.locator('.keyname small')).toHaveText('or Right ⌘, or Right ⌥');
  await expect(pill).toHaveText('0:00 · 0 frames · double-tap fn to stop');
});

test('step 2: three clicks leave rings and captions, then the card appears', async ({ page }) => {
  await load(page);
  const figure = await show(page, 'step-click');
  const pill = figure.locator('.pill');
  await expect(figure.locator('.chip.show')).toHaveCount(0);
  await page.clock.runFor(5300);
  const chips = figure.locator('.chip');
  await expect(chips).toHaveCount(3);
  for (const [i, text] of CHIPS.entries()) {
    await expect(chips.nth(i)).toHaveText(text);
    await expect(chips.nth(i)).toHaveClass(/\bshow\b/);
    await expect(figure.locator('.canvas > .ring').nth(i)).toHaveClass(/\bshow\b/);
  }
  await expect(pill).toHaveText('0:04 · 3 frames · double-tap ⌘ to stop');
  await expect(figure.locator('.acme .toast').first()).toHaveClass(/\bshow\b/);
  await page.clock.runFor(1600);
  const card = figure.locator('.appcard');
  await expect(card).toHaveClass(/\bshow\b/);
  await expect(card.locator('.card-title')).toHaveText('3 frames · 0:04');
  await expect(card.locator('.card-hint')).toHaveText('Drag into a chat · click to review');
  await expect(pill).not.toHaveClass(/\bshow\b/);
  await expect(figure.locator('.chip.show')).toHaveCount(0);
});

test('step 3: the card drops into Claude Code as three images, and the prompt types in', async ({ page }) => {
  await load(page);
  const figure = await show(page, 'step-drag');
  await expect(figure.locator('.term .titlebar')).toContainText('acme — claude');
  await expect(figure.locator('.term .dim')).toHaveText('~/acme · main');
  await expect(figure.locator('.tchip.show')).toHaveCount(0);
  await page.clock.runFor(1900);
  await expect(figure.locator('.term .input')).toHaveClass(/\bdrop\b/);
  await page.clock.runFor(2200);
  await expect(figure.locator('.term .input')).not.toHaveClass(/\bdrop\b/);
  const chips = figure.locator('.tchip');
  await expect(chips).toHaveText(['[Image #1]', '[Image #2]', '[Image #3]']);
  for (const chip of await chips.all()) await expect(chip).toHaveClass(/\bshow\b/);
  await expect(figure.locator('.typed')).toHaveText(TYPED);
  await expect(figure.locator('.appcard')).toHaveClass(/\bgone\b/);
});

test('off screen, each figure holds, and carries on when it is back', async ({ page }) => {
  await load(page);
  const figure = await show(page, 'step-click');
  await page.clock.runFor(1800);
  await expect(figure.locator('.chip.show')).toHaveCount(1);
  await page.evaluate(() => window.scrollTo(0, 0));
  await expect(figure).toHaveAttribute('data-visible', 'false');
  for (const id of ['step-key', 'step-drag']) await expect(page.locator(`#${id}`)).not.toHaveAttribute('data-visible', 'true');
  const before = await page.locator('section.how').innerHTML();
  await page.clock.runFor(15000);
  expect(await page.locator('section.how').innerHTML()).toBe(before);
  await show(page, 'step-click');
  await page.clock.runFor(1800);
  await expect(figure.locator('.chip.show')).toHaveCount(2);
});

test('each figure fades up when it first comes into view', async ({ page }) => {
  await load(page);
  const figure = page.locator('#step-drag');
  await expect(figure).not.toHaveClass(/\bin\b/);
  await show(page, 'step-drag');
  await expect(figure).toHaveClass(/\bin\b/);
});

test('with Reduce Motion on, each figure shows its final state, and nothing moves', async ({ openPage }) => {
  const page = await openPage({ reducedMotion: 'reduce' });
  await load(page);
  const key = page.locator('#step-key');
  await expect(key.locator('.pill')).toHaveClass(/\bshow\b/);
  await expect(key.locator('.pill')).toHaveText('0:02 · 0 frames · double-tap ⌘ to stop');
  await expect(key.locator('.menubar')).toHaveClass(/\brec\b/);
  const click = page.locator('#step-click');
  await expect(click.locator('.chip.show')).toHaveCount(3);
  await expect(click.locator('.canvas > .ring.show')).toHaveCount(3);
  await expect(click.locator('.appcard')).toHaveClass(/\bshow\b/);
  const drag = page.locator('#step-drag');
  await expect(drag.locator('.tchip.show')).toHaveCount(3);
  await expect(drag.locator('.typed')).toHaveText(TYPED);
  await expect(drag.locator('.appcard')).toHaveClass(/\bgone\b/);
  for (const id of ['step-key', 'step-click', 'step-drag']) await expect(page.locator(`#${id}`)).toHaveClass(/\bin\b/);
  const before = await page.locator('section.how').innerHTML();
  await page.clock.runFor(20000);
  await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
  await page.clock.runFor(20000);
  expect(await page.locator('section.how').innerHTML()).toBe(before);
});

test('every step plays with no console errors', async ({ page }) => {
  const errors = await watchErrors(page);
  await load(page);
  for (const id of ['step-key', 'step-click', 'step-drag']) {
    await show(page, id);
    await page.clock.runFor(10000);
  }
  expect(errors).toEqual([]);
});
