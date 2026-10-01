// The form and the function together, through the local server, which runs /api/link in dry-run mode.
import { PHONE } from '../expected.js';
import { expect, test } from './support.js';

test('on an iPhone, the hero form reaches the sent state', async ({ openPage }) => {
  const page = await openPage(PHONE);
  await page.goto('/');
  await page.locator('section.hero details.getlink summary').click();
  await page.locator('#email-hero').fill('sam@example.com');
  const answered = page.waitForResponse('**/api/link');
  await page.locator('section.hero form.linkform button[type="submit"]').click();
  expect((await answered).status()).toBe(200);
  await expect(page.locator('section.hero .linkform-sent')).toBeVisible();
  await expect(page.locator('section.hero .linkform-sent')).toContainText('We sent the link to sam@example.com.');
});

test('without JavaScript, the form posts and the function answers with a page', async ({ openPage }) => {
  const page = await openPage({ ...PHONE, javaScriptEnabled: false });
  await page.goto('/');
  await page.locator('section.hero details.getlink summary').click();
  await page.locator('#email-hero').fill('sam@example.com');
  await page.locator('section.hero form.linkform button[type="submit"]').click();
  await expect(page).toHaveURL(/\/api\/link$/);
  await expect(page.locator('h1')).toHaveText('Check your inbox');
  await expect(page.locator('main')).toContainText('We sent the link to your email. Open it on your Mac.');
});
