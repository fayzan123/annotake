// The first script in <head>, and a classic one, so it runs before the first paint: it sets the theme, so the page
// never flashes the wrong one. Keep it small; everything else waits for site.js.
//
// The theme is the visitor's choice when they've made one, kept in localStorage, and otherwise the system's, which it
// follows as it changes. Storage can be blocked (Safari private browsing, or site data turned off); the toggle then
// still works for the visit.
(function () {
  var KEY = 'annotake-theme';
  var root = document.documentElement;
  var media = window.matchMedia('(prefers-color-scheme: dark)');
  var chosen = null;

  function resolveTheme(stored, systemDark) {
    if (stored === 'light' || stored === 'dark') return stored;
    return systemDark ? 'dark' : 'light';
  }

  function storedTheme() {
    try {
      return window.localStorage.getItem(KEY);
    } catch (error) {
      return null;
    }
  }

  function setTheme(theme) {
    chosen = theme;
    root.dataset.theme = theme;
    try {
      window.localStorage.setItem(KEY, theme);
    } catch (error) {
      // Blocked storage: the choice lasts for this visit.
    }
  }

  root.dataset.theme = resolveTheme(storedTheme(), media.matches);
  media.addEventListener('change', function (event) {
    if (chosen === null) root.dataset.theme = resolveTheme(storedTheme(), event.matches);
  });

  window.annotakeBoot = { resolveTheme: resolveTheme, setTheme: setTheme };
})();
