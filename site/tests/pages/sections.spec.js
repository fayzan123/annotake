// The privacy block, with its Finder window and Quick Look panel, and the final call.
import AxeBuilder from '@axe-core/playwright';
import { PHONE } from '../expected.js';
import { expect, test, useTheme } from './support.js';

const FACTS = [
  ['Plain files', 'Each recording is a folder of PNGs and a steps.md in ~/Pictures/Annotake. They clear out after 30 days unless you choose to keep them.'],
  ['No AI', 'Frames are picked by comparing pixels, and captions come from macOS Accessibility. No models, no uploads.'],
  ['Only while you record', 'Annotake sees your screen only while you record, and it never records what you type.'],
];

const ROWS = [
  ['01_0m01s.png', '412 KB', 'PNG image'],
  ['02_0m02s.png', '405 KB', 'PNG image'],
  ['03_0m04s.png', '418 KB', 'PNG image'],
  ['steps.md', '1 KB', 'Markdown'],
];

const STEPS_MD = `# Annotake capture — 2026-10-01 at 09.41.12
Screen: Built-in Retina Display · 0:04 · 3 frames (from 3 candidates)

1. 0:01 · Acme — Settings · Clicked tab "Appearance"
2. 0:02 · Acme — Settings · Clicked switch "Dark mode"
3. 0:04 · Acme — Settings · Clicked button "Save"`;

test('the privacy block says what stays on the Mac, exactly', async ({ page }) => {
  await page.goto('/');
  const privacy = page.locator('section.privacy');
  await expect(privacy.locator('h2')).toHaveText('Nothing you record leaves your Mac.');
  await expect(privacy.locator('h2 span')).toHaveText('leaves your Mac.');
  const facts = privacy.locator('.fact');
  await expect(facts).toHaveCount(3);
  for (const [i, [label, text]] of FACTS.entries()) {
    await expect(facts.nth(i).locator('dt')).toHaveText(label);
    await expect(facts.nth(i).locator('dd')).toHaveText(text);
  }
  await expect(facts.nth(0).locator('code')).toHaveText(['steps.md', '~/Pictures/Annotake']);
});

test('the Finder window lists the recording, and Quick Look shows steps.md as the app writes it', async ({ page }) => {
  await page.goto('/');
  const finder = page.locator('section.privacy .finder');
  await expect(finder.locator('.title')).toHaveText('2026-10-01 at 09.41.12');
  const rows = finder.locator('.list > .row:not(.head)');
  await expect(rows).toHaveCount(4);
  for (const [i, [name, size, kind]] of ROWS.entries()) {
    await expect(rows.nth(i).locator('> .n .name')).toHaveText(name);
    await expect(rows.nth(i).locator('> .m')).toHaveText([size, kind]);
  }
  await expect(finder.locator('.path')).toHaveText('Macintosh HD › Users › you › Pictures › Annotake › 2026-10-01 at 09.41.12');
  expect(await page.locator('section.privacy .ql pre').evaluate(pre => pre.textContent)).toBe(STEPS_MD);
  await expect(page.locator('section.privacy .ql .bar')).toHaveText('steps.md');
});

test('with JavaScript, the three thumbnails show the frames', async ({ page }) => {
  await page.goto('/');
  const thumbnails = page.locator('section.privacy .finder .tic');
  await expect(thumbnails).toHaveCount(3);
  for (const [i, thumbnail] of (await thumbnails.all()).entries()) {
    await expect(thumbnail.locator('.acme')).toHaveCount(1);
    await expect(thumbnail.locator('.acme .side b').nth(1)).toHaveClass(/\bon\b/);
    await expect(thumbnail.locator('.acme .switch').first()).toHaveClass(i >= 1 ? /\bon\b/ : /^switch$/);
    await expect(thumbnail.locator('.acme .toast')).toHaveClass(i >= 2 ? /\bshow\b/ : /^toast$/);
    const box = await thumbnail.boundingBox();
    expect(Math.round(box.width)).toBe(30);
  }
});

test('without JavaScript, the thumbnails stay plain', async ({ openPage }) => {
  const page = await openPage({ javaScriptEnabled: false });
  await page.goto('/');
  await expect(page.locator('section.privacy .finder .tic')).toHaveCount(3);
  await expect(page.locator('section.privacy .finder .tic .acme')).toHaveCount(0);
});

for (const [width, side] of [[320, 'above'], [1440, 'left of']]) {
  test(`at ${width} px, the text sits ${side} the Finder window`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 });
    await page.goto('/');
    const text = await page.locator('section.privacy .privacy-text').boundingBox();
    const finder = await page.locator('section.privacy .finder').boundingBox();
    if (side === 'above') {
      expect(text.y + text.height).toBeLessThanOrEqual(finder.y);
    } else {
      expect(text.x + text.width).toBeLessThanOrEqual(finder.x);
      expect(Math.abs((text.y + text.height / 2) - (finder.y + finder.height / 2))).toBeLessThan(finder.height);
    }
    expect(await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)).toBeLessThanOrEqual(0);
  });
}

test('the final call on a Mac: the download, with its note', async ({ page }) => {
  await page.goto('/');
  const final = page.locator('section.final');
  await expect(final.locator('h2')).toHaveText('Try it on what’s on your screen.');
  const download = final.locator('.cta a.btn-lg');
  await expect(download).toBeVisible();
  await expect(download).toHaveText('Download for Mac');
  await expect(download).toHaveAttribute('href', '/download');
  await expect(final.locator('.cta p.note.mac-only')).toHaveText(
    'Free during the beta · macOS 15 or later · Apple silicon and Intel By downloading, you agree to the Terms.');
  await expect(final.locator('.cta p.note.mac-only a')).toHaveAttribute('href', '/terms');
  await expect(final.locator('details.getlink')).toBeHidden();
});

test('the final call on an iPhone: its own link form, which reaches the sent state', async ({ openPage }) => {
  const page = await openPage(PHONE);
  await page.route('**/api/link', route => route.fulfill({ json: { ok: true } }));
  await page.goto('/');
  const final = page.locator('section.final');
  await expect(final.locator('a[href="/download"]')).toBeHidden();
  await final.locator('details.getlink summary').click();
  const field = final.locator('#email-final');
  await expect(field).toBeFocused();
  await expect(final.getByLabel('Your email')).toHaveAttribute('id', 'email-final');
  await field.fill('sam@example.com');
  await final.getByRole('button', { name: 'Send link' }).click();
  await expect(final.locator('.linkform-sent')).toBeVisible();
  await expect(final.locator('.linkform-sent')).toContainText('We sent the link to sam@example.com.');
  await expect(page.locator('section.hero .linkform-sent')).toBeHidden();
});

for (const theme of ['light', 'dark']) {
  for (const [device, options] of [['a Mac', {}], ['an iPhone', PHONE]]) {
    test(`axe finds nothing in the privacy block or the final call, in ${theme}, on ${device}`, async ({ openPage }) => {
      const page = await openPage(options);
      await useTheme(page, theme);
      await page.goto('/');
      await page.evaluate(() => document.fonts.ready);
      await page.locator('section.final details.getlink summary').evaluate(summary => {
        if (getComputedStyle(summary).display !== 'none') summary.click();
      });
      const results = await new AxeBuilder({ page }).include('section.privacy').include('section.final').analyze();
      expect(results.violations.map(({ id, nodes }) => `${id}: ${nodes.map(node => node.target).join(', ')}`)).toEqual([]);
    });
  }
}
