// Search and sharing: each page's head, the preview image, robots.txt, and the sitemap.
import { readFile, stat } from 'node:fs/promises';
import { HOME_TITLE } from '../expected.js';
import { expect, test } from './support.js';

const DESCRIPTION = 'A Mac menu-bar app. Press a key, click through the bug in any app, and drag the card into Claude Code, '
  + 'Cursor, or ChatGPT: one captioned screenshot per step. Free during the beta.';
const OG_IMAGE = new URL('../../assets/img/og.v1.png', import.meta.url);

/** Every meta and link tag in the head, as [selector key, value] pairs. */
const head = page => page.evaluate(() => ({
  meta: Object.fromEntries([...document.head.querySelectorAll('meta[name], meta[property]')]
    .map(meta => [meta.getAttribute('name') ?? meta.getAttribute('property'), meta.getAttribute('content')])),
  canonical: document.head.querySelector('link[rel="canonical"]')?.getAttribute('href'),
  icons: [...document.head.querySelectorAll('link[rel="icon"], link[rel="apple-touch-icon"]')]
    .map(link => ({ rel: link.rel, href: link.getAttribute('href'), type: link.getAttribute('type'), sizes: link.getAttribute('sizes') })),
}));

const ICONS = [
  { rel: 'icon', href: '/assets/img/favicon.svg', type: 'image/svg+xml', sizes: null },
  { rel: 'icon', href: '/assets/img/favicon-32.png', type: 'image/png', sizes: '32x32' },
  { rel: 'apple-touch-icon', href: '/assets/img/apple-touch-icon.png', type: null, sizes: null },
];

test('the home page: its title, description, canonical, sharing tags, and icons, exactly', async ({ page }) => {
  await page.goto('/');
  await expect(page).toHaveTitle(HOME_TITLE);
  const { meta, canonical, icons } = await head(page);
  expect(meta).toEqual({
    viewport: 'width=device-width, initial-scale=1',
    description: DESCRIPTION,
    'og:type': 'website',
    'og:url': 'https://annotake.app/',
    'og:title': HOME_TITLE,
    'og:description': DESCRIPTION,
    'og:image': 'https://annotake.app/assets/img/og.v1.png',
    'og:image:width': '1200',
    'og:image:height': '630',
    'og:image:alt': 'Show your coding agent exactly what happened. A strip of film with three captioned frames.',
    'twitter:card': 'summary_large_image',
  });
  expect(canonical).toBe('https://annotake.app/');
  expect(icons).toEqual(ICONS);
});

test('the JSON-LD describes the app', async ({ page }) => {
  await page.goto('/');
  const blocks = await page.locator('script[type="application/ld+json"]').allTextContents();
  expect(blocks).toHaveLength(1);
  expect(JSON.parse(blocks[0])).toEqual({
    '@context': 'https://schema.org',
    '@type': 'SoftwareApplication',
    name: 'Annotake',
    operatingSystem: 'macOS 15 or later',
    applicationCategory: 'DeveloperApplication',
    description: DESCRIPTION,
    url: 'https://annotake.app',
    downloadUrl: 'https://annotake.app/download',
    offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' },
  });
});

for (const [path, title] of [['/privacy', 'Privacy policy · Annotake'], ['/terms', 'Terms · Annotake']]) {
  test(`${path} has its own title, a description, a canonical, and the icons`, async ({ page }) => {
    await page.goto(path);
    await expect(page).toHaveTitle(title);
    const { meta, canonical, icons } = await head(page);
    expect(meta.description?.length).toBeGreaterThan(50);
    expect(canonical).toBe(`https://annotake.app${path}`);
    expect(icons).toEqual(ICONS);
  });
}

test('the 404 page names the icons too', async ({ page }) => {
  await page.goto('/nope');
  expect((await head(page)).icons).toEqual(ICONS);
});

test('every icon answers 200 with its type', async ({ request }) => {
  for (const { href } of ICONS) {
    const response = await request.get(href);
    expect(response.status(), href).toBe(200);
    expect(response.headers()['content-type'], href).toBe(href.endsWith('.svg') ? 'image/svg+xml' : 'image/png');
  }
});

test('the preview image is 1200 × 630 and at most 300 KB', async ({ request }) => {
  const bytes = await readFile(OG_IMAGE);
  expect(bytes.toString('latin1', 12, 16)).toBe('IHDR');
  expect([bytes.readUInt32BE(16), bytes.readUInt32BE(20)]).toEqual([1200, 630]);
  expect((await stat(OG_IMAGE)).size).toBeLessThanOrEqual(300 * 1024);
  const response = await request.get('/assets/img/og.v1.png');
  expect(response.status()).toBe(200);
  expect(response.headers()['content-type']).toBe('image/png');
});

test('robots.txt allows everything and names the sitemap, which lists the three pages', async ({ request }) => {
  const robots = await request.get('/robots.txt');
  expect(robots.status()).toBe(200);
  expect(await robots.text()).toBe('User-agent: *\nAllow: /\n\nSitemap: https://annotake.app/sitemap.xml\n');
  const sitemap = await request.get('/sitemap.xml');
  expect(sitemap.status()).toBe(200);
  expect(sitemap.headers()['content-type']).toBe('application/xml; charset=utf-8');
  const text = await sitemap.text();
  expect(text).toMatch(/^<\?xml version="1.0" encoding="UTF-8"\?>\n<urlset xmlns="http:\/\/www.sitemaps.org\/schemas\/sitemap\/0.9">/);
  expect([...text.matchAll(/<loc>([^<]+)<\/loc>/g)].map(match => match[1]))
    .toEqual(['https://annotake.app/', 'https://annotake.app/privacy', 'https://annotake.app/terms']);
});
