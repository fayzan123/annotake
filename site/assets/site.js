// The page's module entry. boot.js has already set the theme; this wires the parts that respond to the visitor.
const boot = window.annotakeBoot;
const root = document.documentElement;

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

wireThemeToggles();
