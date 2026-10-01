// The first script in <head>, and a classic one, so it runs before the first paint: it sets the theme and whether
// this is a Mac, so the page never flashes the wrong theme or the wrong button. Keep it small; everything else waits
// for site.js.
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

  // A Mac gets Download for Mac; anything else gets Email me the link. An iPad asking for the desktop site sends a Mac
  // user agent, but it has a touch screen, which no Mac has.
  function isMacDesktop(userAgent, maxTouchPoints) {
    return /Macintosh/.test(userAgent) && !/iPhone|iPad|iPod/.test(userAgent) && maxTouchPoints < 2;
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

  root.dataset.device = isMacDesktop(navigator.userAgent, navigator.maxTouchPoints || 0) ? 'mac' : 'other';
  root.dataset.theme = resolveTheme(storedTheme(), media.matches);
  media.addEventListener('change', function (event) {
    if (chosen === null) root.dataset.theme = resolveTheme(storedTheme(), event.matches);
  });

  window.annotakeBoot = { resolveTheme: resolveTheme, setTheme: setTheme, isMacDesktop: isMacDesktop };
})();
