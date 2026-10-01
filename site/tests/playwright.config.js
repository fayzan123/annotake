// Page tests run against the local server (server.mjs), which mirrors vercel.json, in three browsers: the installed
// Google Chrome (so nothing downloads for it), and Playwright's WebKit and Firefox. No device presets: the browsers keep
// their own Mac user agents, and the phone tests set an iPhone's user agent and size themselves.
import { defineConfig } from '@playwright/test';

const PORT = 4174;

export default defineConfig({
  testDir: 'pages',
  fullyParallel: true,
  // Google Chromes starting at the same moment sometimes stick creating their first context, so Chrome workers start
  // 600 ms apart (pages/support.js), and there are four of them.
  workers: 4,
  forbidOnly: !!process.env.CI,
  reporter: [['line']],
  use: {
    baseURL: `http://127.0.0.1:${PORT}`,
    viewport: { width: 1280, height: 800 },
  },
  projects: [
    { name: 'chrome', use: { browserName: 'chromium', channel: 'chrome' } },
    { name: 'webkit', use: { browserName: 'webkit' } },
    { name: 'firefox', use: { browserName: 'firefox' } },
  ],
  webServer: {
    command: `node server.mjs --port ${PORT}`,
    url: `http://127.0.0.1:${PORT}/`,
    reuseExistingServer: false,
    timeout: 15_000,
  },
});
