// Renders the preview image that X, Reddit, and Discord show for a link: site/assets/img/og.v1.png, 1200 × 630, from
// og.html. `make site-og` runs it. The local server refuses /tests/ paths, so this opens the home page for its origin
// and then swaps in og.html's markup; the page keeps its origin, so /assets/… URLs resolve.
//
// A new image needs a new name (og.v2.png), and the pages' og:image updated: images are cached as immutable.
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { chromium } from '@playwright/test';
import { createServer } from '../server.mjs';

const site = fileURLToPath(new URL('../../', import.meta.url));
const out = fileURLToPath(new URL('../../assets/img/og.v1.png', import.meta.url));

const server = createServer({ root: site });
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const browser = await chromium.launch({ channel: 'chrome' });
try {
  const context = await browser.newContext({
    viewport: { width: 1200, height: 630 }, deviceScaleFactor: 1, colorScheme: 'light', reducedMotion: 'reduce',
    bypassCSP: true,
  });
  const page = await context.newPage();
  await page.goto(`http://127.0.0.1:${server.address().port}/`);
  await page.setContent(await readFile(new URL('og.html', import.meta.url), 'utf8'), { waitUntil: 'load' });
  // The gate's still: three captioned frames, and the live one with the pill.
  await page.evaluate(async () => {
    const { initGate } = await import('/assets/gate.js');
    initGate(document.querySelector('.gate-wrap'), { reducedMotion: true });
    await document.fonts.load('600 84px Jost');
    await document.fonts.ready;
  });
  await page.waitForFunction(() => document.querySelector('.og .logo use').getBoundingClientRect().width > 0);
  await page.screenshot({ path: out, clip: { x: 0, y: 0, width: 1200, height: 630 } });
  console.log(`wrote ${out}`);
} finally {
  await browser.close();
  server.close();
}
