// Helpers shared by the page tests.
import { test as base } from '@playwright/test';

export { expect } from '@playwright/test';

/**
 * Collects console errors, uncaught exceptions, and CSP violations from the page's next loads. Call it before `goto`.
 * Returns the live list.
 */
export async function watchErrors(page) {
  const errors = [];
  await page.addInitScript(() => {
    document.addEventListener('securitypolicyviolation', event => {
      console.error(`CSP blocked ${event.blockedURI || 'inline code'} (${event.violatedDirective})`);
    });
  });
  page.on('console', message => {
    // Until Task 12 names the icons, Chrome asks for /favicon.ico on its own.
    if (new URL(message.location().url || 'about:blank').pathname === '/favicon.ico') return;
    if (message.type() === 'error') errors.push(message.text());
  });
  page.on('pageerror', error => errors.push(error.message));
  return errors;
}

/**
 * The page tests' `test`, with one more fixture: `openWithScheme(colorScheme, contextOptions)` opens a page in a new
 * context whose system setting is that scheme, for the tests about following it, and closes it after the test.
 * Playwright's Firefox loses its color-scheme emulation when Cross-Origin-Opener-Policy moves a navigation into a new
 * browsing context group, so for Firefox it launches a browser whose own preference is that scheme.
 */
export const test = base.extend({
  openWithScheme: async ({ browser, browserName, playwright, baseURL }, use) => {
    const closers = [];
    await use(async (colorScheme, options = {}) => {
      if (browserName !== 'firefox') {
        const context = await browser.newContext({ baseURL, ...options, colorScheme });
        closers.push(() => context.close());
        return context.newPage();
      }
      const firefox = await playwright.firefox.launch({
        firefoxUserPrefs: { 'layout.css.prefers-color-scheme.content-override': colorScheme === 'dark' ? 0 : 1 },
      });
      closers.push(() => firefox.close());
      const context = await firefox.newContext({ baseURL, ...options, colorScheme: null });
      return context.newPage();
    });
    for (const close of closers) await close();
  },
});

/** Starts every load of the page in `theme`, as the visitor's stored choice: dark mode in any browser. */
export async function useTheme(page, theme) {
  await page.addInitScript(value => {
    try {
      localStorage.setItem('annotake-theme', value);
    } catch {}
  }, theme);
}
