// Helpers shared by the page tests. Specs import `test` and `expect` from here.
import { test as base } from '@playwright/test';

export { expect } from '@playwright/test';

/**
 * Two workarounds for Playwright's Firefox, both caused by Cross-Origin-Opener-Policy: same-origin, which moves a new
 * tab's first navigation into a new browsing context group.
 * - About 1 first navigation in 80 never reports its load, though the page loads fine. A `goto` that hasn't finished in
 *   5 s is tried once more; the second navigation stays in the group, so it reports normally.
 * - The color-scheme emulation stays behind in the old group. `openWithScheme` launches a Firefox whose own preference
 *   is the scheme instead.
 */
function retryFirstLoad(page, browserName) {
  if (browserName !== 'firefox') return page;
  const goto = page.goto.bind(page);
  page.goto = async (url, options = {}) => {
    try {
      return await goto(url, { ...options, timeout: 5000 });
    } catch (error) {
      if (!/Timeout/.test(error.message)) throw error;
      return goto(url, options);
    }
  };
  return page;
}

/**
 * The page tests' `test`, with two more fixtures, both closed after the test:
 * - `openPage(contextOptions)`: a page in a new context, for user agents, sizes, or no JavaScript.
 * - `openWithScheme(colorScheme, contextOptions)`: the same, with the system set to light or dark, for the tests
 *   about following that setting.
 */
export const test = base.extend({
  // Google Chromes started at the same moment sometimes never finish creating their first context (4 of 80 launches
  // on 2026-10-01, against 0 of 80 started 600 ms apart), so each Chrome worker waits its turn before launching.
  launchOptions: [async ({ launchOptions, browserName }, use, workerInfo) => {
    if (browserName === 'chromium') await new Promise(resolve => setTimeout(resolve, workerInfo.parallelIndex * 600));
    await use(launchOptions);
  }, { scope: 'worker' }],
  page: async ({ page, browserName }, use) => {
    await use(retryFirstLoad(page, browserName));
  },
  openPage: async ({ browser, browserName, baseURL }, use) => {
    const contexts = [];
    await use(async (options = {}) => {
      const context = await browser.newContext({ baseURL, ...options });
      contexts.push(context);
      return retryFirstLoad(await context.newPage(), browserName);
    });
    for (const context of contexts) await context.close();
  },
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
      return retryFirstLoad(await context.newPage(), browserName);
    });
    for (const close of closers) await close();
  },
});

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
    if (message.type() !== 'error') return;
    // The 404 page's own status, which Chrome reports as a failed load.
    if (message.text().startsWith('Failed to load resource') && message.location().url === page.url()) return;
    errors.push(message.text());
  });
  page.on('pageerror', error => errors.push(error.message));
  return errors;
}

/** Starts every load of the page in `theme`, as the visitor's stored choice: dark mode in any browser. */
export async function useTheme(page, theme) {
  await page.addInitScript(value => {
    try {
      localStorage.setItem('annotake-theme', value);
    } catch {}
  }, theme);
}

/**
 * Installs Playwright's fake clock, paused, so nothing on the page moves until the test calls `page.clock.runFor`.
 * Call it before `goto`. (An installed clock that isn't paused keeps flowing in real time.)
 */
export async function pauseClock(page) {
  await page.clock.install({ time: new Date('2026-10-01T09:41:00') });
  await page.clock.pauseAt(new Date('2026-10-01T09:41:01'));
}
