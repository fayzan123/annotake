// The 20-second demo: the hero's link opens it in a dialog, and /demo plays it on a page of its own.
import { IMMUTABLE, PHONE } from '../expected.js';
import { expect, test } from './support.js';

const VIDEO = '/assets/video/demo.v1.mp4';
const POSTER = '/assets/img/demo-poster.v1.jpg';

test('the hero links to the demo, and the first click opens it in a dialog, playing', async ({ page }) => {
  const videoRequests = [];
  page.on('request', request => { if (request.url().endsWith(VIDEO)) videoRequests.push(request.url()); });
  await page.goto('/');
  const link = page.locator('section.hero a.demo-link');
  await expect(link).toHaveText('Watch the 20-second demo');
  await expect(link).toHaveAttribute('href', '/demo');
  expect(videoRequests).toEqual([]);

  await link.click();
  const dialog = page.locator('dialog.demo-dialog');
  await expect(dialog).toBeVisible();
  await expect(page).toHaveURL(/\/$/);
  const video = dialog.locator('video');
  await expect(video).toHaveAttribute('src', VIDEO);
  await expect(video).toHaveAttribute('poster', POSTER);
  await expect.poll(() => video.evaluate(node => node.readyState)).toBeGreaterThanOrEqual(1);
  expect(await video.evaluate(node => node.duration)).toBeCloseTo(20.5, 0);
});

test('Escape, the close button, and the backdrop each close the dialog and pause the video', async ({ page }) => {
  await page.goto('/');
  const link = page.locator('section.hero a.demo-link');
  const dialog = page.locator('dialog.demo-dialog');
  const video = dialog.locator('video');
  const closers = [
    () => page.keyboard.press('Escape'),
    () => dialog.locator('button.demo-close').click(),
    () => page.mouse.click(5, 5),
  ];
  for (const close of closers) {
    await link.click();
    await expect(dialog).toBeVisible();
    await close();
    await expect(dialog).toBeHidden();
    // The dialog's close event, which pauses it, comes a moment after the dialog hides.
    await expect.poll(() => video.evaluate(node => node.paused)).toBe(true);
  }
  expect(await page.locator('dialog.demo-dialog').count()).toBe(1);
});

test('a Command-click leaves the page alone, so the link opens /demo in a new tab', async ({ page }) => {
  await page.goto('/');
  const opened = page.context().waitForEvent('page');
  await page.locator('section.hero a.demo-link').click({ modifiers: ['ControlOrMeta'] });
  const tab = await opened;
  await tab.waitForLoadState();
  expect(new URL(tab.url()).pathname).toBe('/demo');
  await expect(page.locator('dialog.demo-dialog')).toHaveCount(0);
});

test('without JavaScript, the link goes to /demo', async ({ openPage }) => {
  const page = await openPage({ javaScriptEnabled: false });
  await page.goto('/');
  await page.locator('section.hero a.demo-link').click();
  await expect(page).toHaveURL(/\/demo$/);
});

test('/demo plays the video with controls and offers the download on a Mac', async ({ page }) => {
  const response = await page.goto('/demo');
  expect(response.status()).toBe(200);
  await expect(page).toHaveTitle('Demo · Annotake');
  await expect(page.locator('main h1')).toHaveText('Annotake in 20 seconds');
  const video = page.locator('main video.demo-video');
  await expect(video).toHaveAttribute('controls', '');
  await expect(video).toHaveAttribute('src', VIDEO);
  await expect.poll(() => video.evaluate(node => node.readyState)).toBeGreaterThanOrEqual(1);
  await expect(page.locator('main a.btn-lg')).toHaveAttribute('href', '/download');
});

test('/demo on a phone points to the email link instead', async ({ openPage }) => {
  const page = await openPage(PHONE);
  await page.goto('/demo');
  await expect(page.locator('main a.btn-lg')).toBeHidden();
  await expect(page.locator('main p.note.other-only a')).toHaveAttribute('href', '/');
});

test('the video and its poster are served as MP4 and JPEG, cached for good, and the video in byte ranges', async ({ request }) => {
  const video = await request.get(VIDEO, { headers: { Range: 'bytes=0-99' } });
  expect(video.status()).toBe(206);
  expect(video.headers()['content-type']).toBe('video/mp4');
  expect(video.headers()['content-range']).toMatch(/^bytes 0-99\/\d+$/);
  expect(video.headers()['cache-control']).toBe(IMMUTABLE);
  expect((await video.body()).length).toBe(100);
  const poster = await request.get(POSTER);
  expect(poster.status()).toBe(200);
  expect(poster.headers()['content-type']).toBe('image/jpeg');
  expect(poster.headers()['cache-control']).toBe(IMMUTABLE);
});
