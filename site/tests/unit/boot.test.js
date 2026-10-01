// boot.js runs first in <head>, before the first paint. These run it in node:vm with a fake window: a document, the
// system's light or dark setting, and localStorage, which may throw as it does when site data is blocked.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const BOOT = await readFile(new URL('../../assets/boot.js', import.meta.url), 'utf8');

/**
 * Runs boot.js in a fresh fake window. `stored` is the saved theme; `storage` replaces localStorage entirely
 * ('throws' for a getter that throws, 'setThrows' for a setItem that throws).
 */
function boot({ systemDark = false, stored = null, storage, userAgent = '', maxTouchPoints = 0 } = {}) {
  const listeners = [];
  const media = {
    matches: systemDark,
    addEventListener: (type, listener) => type === 'change' && listeners.push(listener),
  };
  const saved = new Map(stored === null ? [] : [['annotake-theme', stored]]);
  const localStorage = {
    getItem: key => (saved.has(key) ? saved.get(key) : null),
    setItem: (key, value) => {
      if (storage === 'setThrows') throw new Error('QuotaExceededError');
      saved.set(key, String(value));
    },
  };
  const window = {
    document: { documentElement: { dataset: {} } },
    navigator: { userAgent, maxTouchPoints },
    matchMedia: query => {
      assert.equal(query, '(prefers-color-scheme: dark)');
      return media;
    },
  };
  if (storage === 'throws') {
    Object.defineProperty(window, 'localStorage', { get() { throw new Error('SecurityError: blocked'); } });
  } else {
    window.localStorage = localStorage;
  }
  window.window = window;
  vm.runInNewContext(BOOT, window);
  return {
    window,
    root: window.document.documentElement,
    saved,
    setSystem(dark) {
      media.matches = dark;
      for (const listener of listeners) listener({ matches: dark });
    },
  };
}

test('resolveTheme keeps a valid stored choice, and otherwise follows the system', () => {
  const { resolveTheme } = boot().window.annotakeBoot;
  for (const systemDark of [false, true]) {
    assert.equal(resolveTheme('dark', systemDark), 'dark');
    assert.equal(resolveTheme('light', systemDark), 'light');
    for (const junk of [null, undefined, '', 'Dark', 'blue', '{"theme":"dark"}']) {
      assert.equal(resolveTheme(junk, systemDark), systemDark ? 'dark' : 'light', `${junk} with dark ${systemDark}`);
    }
  }
});

test('at load, a stored choice wins over the system, and nothing stored follows it', () => {
  assert.equal(boot({ systemDark: false, stored: 'dark' }).root.dataset.theme, 'dark');
  assert.equal(boot({ systemDark: true, stored: 'light' }).root.dataset.theme, 'light');
  assert.equal(boot({ systemDark: true }).root.dataset.theme, 'dark');
  assert.equal(boot({ systemDark: false }).root.dataset.theme, 'light');
  assert.equal(boot({ systemDark: true, stored: 'junk' }).root.dataset.theme, 'dark');
});

test('a system change applies only while nothing is stored', () => {
  const free = boot({ systemDark: false });
  free.setSystem(true);
  assert.equal(free.root.dataset.theme, 'dark');
  free.setSystem(false);
  assert.equal(free.root.dataset.theme, 'light');

  const chosen = boot({ systemDark: false, stored: 'light' });
  chosen.setSystem(true);
  assert.equal(chosen.root.dataset.theme, 'light');
});

test('setTheme applies the theme and stores it, and then system changes stop applying', () => {
  const page = boot({ systemDark: false });
  page.window.annotakeBoot.setTheme('dark');
  assert.equal(page.root.dataset.theme, 'dark');
  assert.equal(page.saved.get('annotake-theme'), 'dark');
  page.setSystem(false);
  assert.equal(page.root.dataset.theme, 'dark');
});

test('blocked storage (a throwing getter or setItem) causes no error, and the theme still applies', () => {
  for (const storage of ['throws', 'setThrows']) {
    const page = boot({ systemDark: true, storage });
    assert.equal(page.root.dataset.theme, 'dark', storage);
    assert.doesNotThrow(() => page.window.annotakeBoot.setTheme('light'), storage);
    assert.equal(page.root.dataset.theme, 'light', `${storage}: the toggle still switches for the visit`);
    page.setSystem(true);
    assert.equal(page.root.dataset.theme, 'light', `${storage}: and the choice holds for the visit`);
  }
});
