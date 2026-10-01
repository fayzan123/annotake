// The page's module entry. boot.js has already set the theme; this wires the parts that respond to the visitor.
import { initGate } from './gate.js';
import { initLinkForm } from './linkform.js';
import { initSteps } from './steps.js';

const boot = window.annotakeBoot;
const root = document.documentElement;
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;

/** Each theme toggle switches to the other theme, and its label says which one it will switch to. */
function wireThemeToggles() {
  const toggles = document.querySelectorAll('.theme-toggle');
  const label = () => (root.dataset.theme === 'dark' ? 'Switch to light theme' : 'Switch to dark theme');
  const update = () => toggles.forEach(toggle => toggle.setAttribute('aria-label', label()));
  for (const toggle of toggles) {
    toggle.addEventListener('click', () => {
      boot.setTheme(root.dataset.theme === 'dark' ? 'light' : 'dark');
      update();
    });
  }
  // The system's setting can change the theme too, until the visitor picks one.
  new MutationObserver(update).observe(root, { attributes: true, attributeFilter: ['data-theme'] });
  update();
}

/**
 * A download click lets the browser fetch the disk image, says "Downloading…" for 2 s, and shows what to do with it:
 * the hint in the same call to action, or the hero's when the header's button was clicked.
 */
function wireDownloads() {
  for (const link of document.querySelectorAll('a[href="/download"]')) {
    const label = link.querySelector('.label');
    let timer;
    link.addEventListener('click', () => {
      label.textContent = 'Downloading…';
      clearTimeout(timer);
      timer = setTimeout(() => { label.textContent = 'Download for Mac'; }, 2000);
      const hint = link.closest('.cta')?.querySelector('.dl-hint') ?? document.querySelector('.dl-hint');
      if (hint) hint.hidden = false;
    });
  }
}

wireThemeToggles();
wireDownloads();
for (const form of document.querySelectorAll('form.linkform')) initLinkForm(form);
const gate = document.querySelector('.gate-wrap');
if (gate) initGate(gate, { reducedMotion });
const how = document.querySelector('section.how');
if (how) initSteps(how, { reducedMotion });
