// What the tests expect, exactly as the plan's Global Constraints write it. Shared by the unit and page tests.

export const CSP =
  "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; " +
  "connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'; object-src 'none'";

/** The five headers every response carries besides the CSP, by lowercased name. */
export const SECURITY_HEADERS = {
  'referrer-policy': 'strict-origin-when-cross-origin',
  'x-content-type-options': 'nosniff',
  'permissions-policy': 'camera=(), microphone=(), geolocation=()',
  'cross-origin-opener-policy': 'same-origin',
  'strict-transport-security': 'max-age=63072000; includeSubDomains',
};

export const IMMUTABLE = 'public, max-age=31536000, immutable';

export const DMG_URL = 'https://github.com/fayzan123/annotake-releases/releases/latest/download/Annotake.dmg';

export const HOME_TITLE = 'Annotake: show your coding agent exactly what happened';

/** A path to each page the site serves; /nope reaches the 404 page. */
export const PAGES = ['/', '/nope'];
