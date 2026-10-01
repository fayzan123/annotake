// The "Email me the link" form, on an iPhone. /api/link is routed, so nothing here reaches the function.
import { PHONE } from '../expected.js';
import { expect, pauseClock, test } from './support.js';

test.use(PHONE);

const LINK = 'https://annotake.app/download';

/** Stubs the clipboard and, unless `share` is false, navigator.share; both record what they get. */
async function stubSharing(page, { share = true } = {}) {
  await page.addInitScript(withShare => {
    window.copied = [];
    window.shared = [];
    Object.defineProperty(Navigator.prototype, 'clipboard', {
      configurable: true,
      get: () => ({ writeText: async text => { window.copied.push(text); } }),
    });
    if (withShare) {
      Object.defineProperty(Navigator.prototype, 'share', {
        configurable: true,
        value: async data => { window.shared.push(data); },
      });
    } else {
      delete Navigator.prototype.share;
      delete navigator.share;
    }
  }, share);
}

/** Routes /api/link to `answer(route)`, and returns the list of request bodies it saw. */
async function routeLink(page, answer) {
  const bodies = [];
  await page.route('**/api/link', async route => {
    bodies.push(route.request().postDataJSON());
    await answer(route);
  });
  return bodies;
}

async function openForm(page) {
  await page.goto('/');
  await page.locator('section.hero details.getlink summary').click();
  return page.locator('section.hero form.linkform');
}

test('a good address reaches the sent state, and the request holds the cleaned address', async ({ page }) => {
  await stubSharing(page);
  const bodies = await routeLink(page, route => route.fulfill({ json: { ok: true } }));
  const form = await openForm(page);
  await expect(form.getByLabel('Your email')).toBeFocused();
  await form.getByLabel('Your email').fill('  Sam+annotake@Example.com ');
  await form.getByRole('button', { name: 'Send link' }).click();
  const sent = page.locator('section.hero .linkform-sent');
  await expect(sent).toBeVisible();
  await expect(sent).toContainText('Check your inbox');
  await expect(sent).toContainText('We sent the link to Sam+annotake@Example.com. Open it on your Mac.');
  await expect(sent.getByRole('button', { name: 'Wrong address? Try again' })).toBeVisible();
  await expect(form).toBeHidden();
  expect(bodies).toHaveLength(1);
  expect(bodies[0].email).toBe('Sam+annotake@Example.com');
  expect(bodies[0].website).toBe('');
  expect(typeof bodies[0].t).toBe('number');
  expect(bodies[0].t).toBeGreaterThanOrEqual(0);
});

test('a 400 shows the error, and the form stays', async ({ page }) => {
  await routeLink(page, route => route.fulfill({ status: 400, json: { ok: false, reason: 'invalid' } }));
  const form = await openForm(page);
  await form.getByLabel('Your email').fill('sam@example.com');
  await form.getByRole('button', { name: 'Send link' }).click();
  await expect(form.locator('.linkform-error')).toHaveText('That doesn’t look like an email address.');
  await expect(form.locator('.linkform-error')).toBeVisible();
  await expect(form).toBeVisible();
  await expect(form.getByRole('button', { name: 'Send link' })).toBeEnabled();
});

for (const [name, answer] of [
  ['a 429', route => route.fulfill({ status: 429, json: { ok: false, reason: 'busy' } })],
  ['a 502', route => route.fulfill({ status: 502, json: { ok: false, reason: 'send' } })],
  ['an aborted request', route => route.abort()],
]) {
  test(`${name} shows the link, with Copy and Share`, async ({ page }) => {
    await stubSharing(page);
    await routeLink(page, answer);
    const form = await openForm(page);
    await form.getByLabel('Your email').fill('sam@example.com');
    await form.getByRole('button', { name: 'Send link' }).click();
    const fallback = page.locator('section.hero .linkform-fallback');
    await expect(fallback).toBeVisible();
    await expect(fallback).toContainText('We couldn’t send it right now. Here’s the link:');
    await expect(fallback).toContainText('annotake.app/download');
    const copy = fallback.getByRole('button', { name: 'Copy' });
    await copy.click();
    await expect(fallback.getByRole('button', { name: 'Copied' })).toBeVisible();
    expect(await page.evaluate(() => window.copied)).toEqual([LINK]);
    await fallback.getByRole('button', { name: 'Share' }).click();
    await expect.poll(() => page.evaluate(() => window.shared)).toEqual([{ title: 'Annotake for Mac', url: LINK }]);
  });
}

test('without navigator.share, the fallback has no Share button', async ({ page }) => {
  await stubSharing(page, { share: false });
  await routeLink(page, route => route.fulfill({ status: 502, json: { ok: false, reason: 'send' } }));
  const form = await openForm(page);
  await form.getByLabel('Your email').fill('sam@example.com');
  await form.getByRole('button', { name: 'Send link' }).click();
  const fallback = page.locator('section.hero .linkform-fallback');
  await expect(fallback.getByRole('button', { name: 'Copy' })).toBeVisible();
  await expect(fallback.getByRole('button', { name: 'Share' })).toHaveCount(0);
});

test('a request that never answers ends in the fallback after 12 s, never a spinner', async ({ page }) => {
  await pauseClock(page);
  await stubSharing(page);
  await routeLink(page, () => {});
  const form = await openForm(page);
  await form.getByLabel('Your email').fill('sam@example.com');
  await form.getByRole('button', { name: 'Send link' }).click();
  await expect(form.getByRole('button', { name: 'Sending…' })).toBeDisabled();
  await page.clock.runFor(11_900);
  await expect(page.locator('section.hero .linkform-fallback')).toBeHidden();
  await page.clock.runFor(100);
  await expect(page.locator('section.hero .linkform-fallback')).toBeVisible();
});

test('impatient taps: two quick clicks on Send, then Enter, make one request', async ({ page }) => {
  let release;
  const held = new Promise(resolve => { release = resolve; });
  const bodies = await routeLink(page, async route => {
    await held;
    await route.fulfill({ json: { ok: true } });
  });
  const form = await openForm(page);
  const field = form.getByLabel('Your email');
  await field.fill('sam@example.com');
  await form.getByRole('button', { name: 'Send link' }).click({ clickCount: 2 });
  await field.press('Enter');
  await expect(form.locator('button[type="submit"]')).toHaveText('Sending…');
  release();
  await expect(page.locator('section.hero .linkform-sent')).toBeVisible();
  expect(bodies).toHaveLength(1);
  await expect(page.locator('section.hero .linkform-sent')).toHaveCount(1);
});

test('a bad address shows the error at once, with no request, and keeps the field focused', async ({ page }) => {
  const bodies = await routeLink(page, route => route.fulfill({ json: { ok: true } }));
  const form = await openForm(page);
  const field = form.getByLabel('Your email');
  await field.fill('sam@example');
  await form.getByRole('button', { name: 'Send link' }).click();
  await expect(form.locator('.linkform-error')).toBeVisible();
  await expect(field).toBeFocused();
  await expect(field).toHaveAttribute('aria-invalid', 'true');
  expect(bodies).toHaveLength(0);
  await field.fill('sam@example.com');
  await form.getByRole('button', { name: 'Send link' }).click();
  await expect(page.locator('section.hero .linkform-sent')).toBeVisible();
  expect(bodies).toHaveLength(1);
});

test('Try again brings the form back with the address kept, and the field focused', async ({ page }) => {
  await routeLink(page, route => route.fulfill({ json: { ok: true } }));
  const form = await openForm(page);
  await form.getByLabel('Your email').fill('sam@exmaple.com');
  await form.getByRole('button', { name: 'Send link' }).click();
  await page.getByRole('button', { name: 'Wrong address? Try again' }).click();
  await expect(form).toBeVisible();
  await expect(page.locator('section.hero .linkform-sent')).toBeHidden();
  await expect(form.getByLabel('Your email')).toHaveValue('sam@exmaple.com');
  await expect(form.getByLabel('Your email')).toBeFocused();
  await expect(form.getByRole('button', { name: 'Send link' })).toBeEnabled();
});

test('the keyboard: Enter opens the form, Tab reaches the field and the button, and Enter sends', async ({ page, browserName }) => {
  // Safari moves through buttons and links with Option-Tab, unless "Press Tab to highlight each item" is on.
  const tab = browserName === 'webkit' ? 'Alt+Tab' : 'Tab';
  const bodies = await routeLink(page, route => route.fulfill({ json: { ok: true } }));
  await page.goto('/');
  await page.locator('section.hero details.getlink summary').focus();
  await page.keyboard.press('Enter');
  const form = page.locator('section.hero form.linkform');
  const field = form.getByLabel('Your email');
  await expect(field).toBeFocused();
  await page.keyboard.type('sam@example.com');
  await page.keyboard.press(tab);
  await expect(form.getByRole('button', { name: 'Send link' })).toBeFocused();
  await page.keyboard.press(`Shift+${tab}`);
  await expect(field).toBeFocused();
  await page.keyboard.press('Enter');
  await expect(page.locator('section.hero .linkform-sent')).toBeVisible();
  expect(bodies).toHaveLength(1);
});
