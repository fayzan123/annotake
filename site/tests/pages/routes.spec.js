import { expect, test } from '@playwright/test';
import { CSP, DMG_URL, HOME_TITLE } from '../expected.js';
import { watchErrors } from './support.js';

test('the home page loads with the CSP, no console errors, and no cookies', async ({ page, context }) => {
  const errors = await watchErrors(page);
  const response = await page.goto('/');
  expect(response.status()).toBe(200);
  await expect(page).toHaveTitle(HOME_TITLE);
  expect(response.headers()['content-security-policy']).toBe(CSP);
  await page.waitForLoadState('load');
  expect(errors).toEqual([]);
  expect(await context.cookies()).toEqual([]);
});

test('/download answers 302 to the disk image on GitHub', async ({ request }) => {
  const response = await request.get('/download', { maxRedirects: 0 });
  expect(response.status()).toBe(302);
  expect(response.headers().location).toBe(DMG_URL);
});
