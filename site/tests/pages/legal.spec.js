// The privacy policy, the Terms, the third-party licenses, and the 404 page.
import AxeBuilder from '@axe-core/playwright';
import { expect, test, useTheme } from './support.js';

const UPDATED = 'Last updated: October 19, 2026';

const PAGES = {
  '/privacy': {
    title: 'Privacy policy · Annotake',
    h1: 'Privacy policy',
    h2s: ['The short version', 'The Annotake app', 'This website', 'The link email', 'Email from Annotake',
      'Who else sees data', 'Your rights', 'Children', 'Changes'],
    phrases: ['Nothing you record leaves your Mac', 'This website doesn’t use cookies', 'Vercel Web Analytics', 'Resend',
      '30 days', 'GitHub', 'United States', 'We never sell', 'before that version ships',
      'Office of the Privacy Commissioner of Canada', 'Fayzan Malik', 'Ontario, Canada'],
  },
  '/terms': {
    title: 'Terms · Annotake',
    h1: 'Terms',
    h2s: ['Who we are', 'The beta', 'Your license', 'Your recordings', 'No warranty', 'Limitation of liability',
      'Trademarks', 'Open-source software', 'Ending', 'Governing law', 'Changes'],
    phrases: ['free during the beta', 'as is', 'GNU General Public License, version 3',
      'not Annotake’s name or logo',
      'Claude Code, Cursor, ChatGPT, Mac, and macOS are trademarks of their owners',
      'isn’t affiliated with or endorsed by them', 'Ontario'],
  },
};

for (const [path, page] of Object.entries(PAGES)) {
  test(`${path}: its title, its sections in order, and every phrase it promises`, async ({ page: tab }) => {
    const response = await tab.goto(path);
    expect(response.status()).toBe(200);
    await expect(tab).toHaveTitle(page.title);
    await expect(tab.locator('main h1')).toHaveText(page.h1);
    await expect(tab.locator('main .updated')).toHaveText(UPDATED);
    await expect(tab.locator('main h2')).toHaveText(page.h2s);
    const text = (await tab.locator('main').textContent()).replace(/\s+/g, ' ');
    for (const phrase of page.phrases) expect(text, phrase).toContain(phrase);
    await expect(tab.locator('header a[href="/"]')).toBeVisible();
    await expect(tab.locator('footer .legal')).toContainText('Made in Ontario, Canada');
    await expect(tab.locator('footer .giant svg use')).toHaveAttribute('href', '/assets/img/brand.svg#logo');
  });
}

/**
 * The page's main, section by section: each h2's text, and under it the text of each paragraph and each list item,
 * with white space collapsed.
 */
async function sections(tab) {
  return tab.locator('main').evaluate(main => {
    const result = {};
    let blocks = null;
    for (const element of main.children) {
      if (element.tagName === 'H2') result[element.textContent] = blocks = [];
      else if (blocks) {
        const parts = element.tagName === 'UL' ? [...element.children] : [element];
        blocks.push(...parts.map(part => part.textContent.replace(/\s+/g, ' ').trim()));
      }
    }
    return result;
  });
}

// The email list (design §6.3), word for word. The short version and the new section are pinned whole; elsewhere, the
// paragraphs and list items the email list changed.
const SHORT_VERSION = [
  'Nothing you record leaves your Mac. Annotake has no server that sees your recordings.',
  'If you give the app your email address, we use it to send you important notices. Giving it is optional.',
  'This website doesn’t use cookies, and it counts visits without identifying you.',
  'If you ask us to email you the download link, we use your address only to send that one email.',
];

const EMAIL_SECTION = [
  // No welcome email and no Feedback and news until the list has a mailing address (design §13).
  // The email is optional, and recording never waits for it (design §13).
  'Annotake asks for your email address, and you can skip it: everything works without one. If you give it, we use ' +
    'it to send you important notices, such as security fixes.',
  'What we keep is your email address, when you gave it, what the app said when it asked, and the app version. ' +
    'Resend stores it for us, in the United States, and keeps its sending logs for 30 days.',
  // Not "one click": the welcome's link asks first, so a link scanner can't unsubscribe anyone, and a broadcast's opens
  // Resend's page. Only a mail app's own Unsubscribe button, where it shows one, is a single click.
  'Unsubscribing. You can unsubscribe from any email with its unsubscribe link, or with your mail app’s Unsubscribe ' +
    'button where it shows one.',
  // Settings' Change… adds the new address and leaves the old one as it is (design §3.3, §12).
  'How long. We keep your address until you ask us to delete it, even after you unsubscribe: it stays, marked ' +
    'unsubscribed, as proof and so the list never emails it again. Changing your address in Settings doesn’t remove ' +
    'the old one: it stays on the list, and gets our emails until you unsubscribe it or ask us to delete it.',
  'Logs. Our own logs never record your address. Vercel’s request logs, kept for up to 30 days, can include it ' +
    'when the app sends it or you use an unsubscribe link.',
  // The address has one use since the email became optional (design §13), and its basis.
  'Legal basis. In the EU and the UK, emailing the address you give rests on our legitimate interest in telling ' +
    'you about security fixes and important changes. Giving it is your choice.',
];

const CHANGED = {
  'The Annotake app': [
    // Feedback.summary puts the Mac's model in the draft too.
    'Send Feedback. Send Feedback opens a draft in your mail app with the app’s and macOS’s versions, your Mac’s ' +
      'model, which permissions are granted, the app’s recent log, and its latest crash report. You see the draft, ' +
      'and you choose whether to send it. The log never holds button names, window titles, or keys.',
    'What goes over the network. Once a day, Annotake checks for updates by fetching its update feed from GitHub, ' +
      'which sees the app’s version and your IP address, as with any download. Updates download from GitHub too. ' +
      'The check sends no other information about your Mac. If you give Annotake your email address, it sends it ' +
      'and its version to annotake.app once, for the email list below, and again only if you change the address in ' +
      'Settings. Like GitHub, annotake.app sees your IP address. Nothing you record is ever sent.',
    // Stage 2's sign-in takes the email step's place (design §9), so the policy doesn't promise how it will ask.
    'Coming later. A later version will add sign-in and daily counts of how much Annotake is used. This policy will ' +
      'be updated before that version ships, and the app will ask you before it sends anything new.',
  ],
  'The link email': [
    'If you ask us to email you the download link, we use your address only to send that one email, through ' +
      'Resend. Asking for the link doesn’t add you to any list. Resend keeps its sending logs for 30 days. Our own ' +
      'logs record only whether the email went out, never your address.',
  ],
  // Replies to our emails and Send Feedback's drafts reach Fayzan's Gmail, so Google is named, with no address.
  'Who else sees data': [
    'Only these services: Vercel (hosting and analytics), Resend (our emails and the email list), GitHub (downloads ' +
      'and updates), and Google (Gmail, where your replies and feedback arrive). They’re in the United States, so ' +
      'what they process is handled there, under US law. We never sell personal information, and we don’t share it ' +
      'for advertising.',
  ],
  'Your rights': [
    'You have the right to see, correct, or delete the personal information we hold about you. To ask, reply to ' +
      'any email from Annotake’s email list, or use Send Feedback in the app. The services above keep only what ' +
      'this policy says.',
    'In the EU or the UK, you also have rights under the GDPR, including access, correction, deletion, and ' +
      'objection, and you can complain to your data protection authority. The legal basis for the link email is ' +
      'your request for it; for the email list and keeping this website secure, our legitimate interest.',
  ],
};

/** What the policy said before the email list, and mustn't say now. */
const GONE = ['We keep no list', 'With no accounts and no list, we hold none ourselves', 'we won’t email you again',
  'We get your email address only if', 'an optional sign-in'];

test('/privacy: the short version adds the email list, and keeps recordings on the Mac', async ({ page }) => {
  await page.goto('/privacy');
  expect((await sections(page))['The short version']).toEqual(SHORT_VERSION);
});

test('/privacy: Email from Annotake says what’s kept, where, how long, and why', async ({ page }) => {
  await page.goto('/privacy');
  expect((await sections(page))['Email from Annotake']).toEqual(EMAIL_SECTION);
});

for (const [heading, blocks] of Object.entries(CHANGED)) {
  test(`/privacy: ${heading} covers the email list, word for word`, async ({ page }) => {
    await page.goto('/privacy');
    const section = (await sections(page))[heading];
    for (const block of blocks) expect(section).toContain(block);
  });
}

test('/privacy no longer says there’s no list', async ({ page }) => {
  await page.goto('/privacy');
  const text = (await page.locator('main').textContent()).replace(/\s+/g, ' ');
  for (const phrase of GONE) expect(text, phrase).not.toContain(phrase);
});

test('/terms: an address given means important notices by email, and any email can be unsubscribed from', async ({ page }) => {
  await page.goto('/terms');
  expect((await sections(page))['The beta']).toEqual([
    'Annotake is free during the beta, for as long as the beta lasts. Its features may change, and the beta may end. ' +
      'Paid plans may come later, but nothing you use becomes paid without notice and your agreement.',
    'If you give Annotake your email address, you’ll get important notices by email. You can unsubscribe from any email.',
  ]);
});

test('the Terms link the three licenses, the code, and the privacy policy', async ({ page }) => {
  await page.goto('/terms');
  await expect(page.locator('main a[href="/licenses/gpl-3.0.txt"]')).toHaveCount(1);
  await expect(page.locator('main a[href="https://github.com/fayzan123/annotake"]')).toHaveCount(1);
  await expect(page.locator('main a[href="/licenses/sparkle.txt"]')).toHaveCount(1);
  await expect(page.locator('main a[href="/licenses/jost-ofl.txt"]')).toHaveCount(1);
  await expect(page.locator('main a[href="/privacy"]')).not.toHaveCount(0);
});

// annotake.app receives no mail, so no page gives an address.
for (const path of ['/', '/privacy', '/terms', '/nope']) {
  test(`${path} shows no email address`, async ({ page }) => {
    await page.goto(path);
    await expect(page.locator('a[href^="mailto:"]')).toHaveCount(0);
    expect(await page.locator('body').textContent()).not.toMatch(/[^\s@]+@[^\s@]+\.[a-z]{2,}/i);
  });
}

test('the licenses are published as plain text', async ({ request }) => {
  const sparkle = await request.get('/licenses/sparkle.txt');
  expect(sparkle.status()).toBe(200);
  expect(sparkle.headers()['content-type']).toBe('text/plain; charset=utf-8');
  const sparkleText = await sparkle.text();
  expect(sparkleText).toContain('Andy Matuschak');
  expect(sparkleText).toContain('bsdiff');
  const jost = await request.get('/licenses/jost-ofl.txt');
  expect(jost.status()).toBe(200);
  expect(jost.headers()['content-type']).toBe('text/plain; charset=utf-8');
  expect(await jost.text()).toContain('SIL OPEN FONT LICENSE');
  const gpl = await request.get('/licenses/gpl-3.0.txt');
  expect(gpl.status()).toBe(200);
  expect(gpl.headers()['content-type']).toBe('text/plain; charset=utf-8');
  expect(await gpl.text()).toContain('GNU GENERAL PUBLIC LICENSE');
});

test('an unknown path answers 404, with a way home', async ({ page }) => {
  const response = await page.goto('/nope');
  expect(response.status()).toBe(404);
  await expect(page.locator('main h1')).toHaveText('This page doesn’t exist.');
  const home = page.locator('main a', { hasText: 'Go to annotake.app' });
  await expect(home).toHaveAttribute('href', '/');
});

for (const theme of ['light', 'dark']) {
  for (const path of ['/privacy', '/terms', '/nope']) {
    test(`axe finds nothing on ${path} in ${theme}`, async ({ page }) => {
      await useTheme(page, theme);
      await page.goto(path);
      await page.evaluate(() => document.fonts.ready);
      const results = await new AxeBuilder({ page }).analyze();
      expect(results.violations.map(({ id, nodes }) => `${id}: ${nodes.map(node => node.target).join(', ')}`)).toEqual([]);
    });
  }
}
