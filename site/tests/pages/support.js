// Helpers shared by the page tests.

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
