# annotake.app

The landing page, the privacy policy, the Terms, and three Vercel functions. `api/link.js` emails the download link. The app's email list has the other two: `api/subscribe.js` adds the address the app sends to Resend, with a welcome email, and `api/unsubscribe.js` serves the welcome email's unsubscribe link. Their shared code is in `api/_lib/`, which Vercel never runs as a function. Plain HTML, CSS, and JavaScript modules: no framework, no build step, and no runtime packages.

This file and `tests/` are never deployed (`.vercelignore`).

## Run it

```
make site-dev
```

Serves the site at http://localhost:4173 the way `vercel.json` says: clean URLs, the `/download` redirect, the headers, and the functions in dry-run mode (`EMAIL_DRY_RUN=1`), so they never send an email or change a contact. They check unsubscribe links against `UNSUBSCRIBE_SECRET=test-secret`, never a real secret, and nothing under `api/_lib` is served or run. The server is `tests/server.mjs`. The first run installs the test packages (`npm ci` in `tests/`).

## Test it

```
make site-unit                   # node:test: the server, the functions, the email check, the brand, boot.js, the logo, the tools
make site-test                   # the unit tests, then the page tests in Chrome, WebKit, and Firefox
make site-test FILTER=hero       # only the page tests whose names match
```

- The page tests use the installed Google Chrome, and Playwright's WebKit and Firefox. Install those two once with `cd site/tests && npx playwright install webkit firefox`.
- Specs import `test`, `expect`, and the helpers from `tests/pages/support.js`. It works around three browser quirks.
- Timing tests pause Playwright's clock (`pauseClock`) before loading the page, then move it with `page.clock.runFor`.
- `tests/subscribe-request.json` is the exact request the app sends to `/api/subscribe`. The app's `EmailSignupTests` check the app sends it, and `subscribe.test.js` and `subscribe.spec.js` post it, so a field renamed on one side alone fails a test.

## Regenerate

```
make site-brand        # brand.js, img/brand.svg, img/favicon.svg, and img/apple-touch-icon.png from the app's
                       # BrandMark.swift and Wordmark.swift; img/favicon-32.png from Resources/AppIcon.icns
make site-brand-check  # fails if the committed brand files are out of date
make site-og           # img/og.v2.png, the preview image for links, from tests/tools/og.html
```

Never edit the generated files by hand. Fonts, images, and video under `/assets/fonts/`, `/assets/img/`, and `/assets/video/` are cached as immutable, so a changed one needs a new name (`og.v2.png`), with every reference to it updated. The demo video (`video/demo.v1.mp4`, played by `/demo` and the hero's dialog in `assets/demo.js`) is the 1080p cut re-encoded for the web: `ffmpeg -i <cut>.mp4 -c:v libx264 -preset slow -crf 22 -pix_fmt yuv420p -tune stillimage -c:a aac -b:a 128k -movflags +faststart`. `+faststart` puts the index first, so it plays before it finishes loading. Its poster, `img/demo-poster.v1.jpg`, is the frame at 1.5 s, 1280 px wide.

## Rules the code keeps

- **The CSP allows no inline scripts or styles:** no `<script>` with code and no `<style>` (JSON-LD data blocks are fine), and no `style="…"` or `style.cssText`. Code sets single properties (`element.style.left`, `style.setProperty('--k', …)`), toggles classes, and sets SVG attributes.
- **No cookies, and nothing from another origin.** The theme choice lives in `localStorage` (`annotake-theme`), and every access is wrapped in `try`/`catch`.
- **No function logs an email address.** Each request logs one `link: <outcome>`, `subscribe: <outcome>`, or `unsubscribe: <outcome>` line. `/api/link` never stores or returns one, and `/api/subscribe` keeps it only in Resend, as the list.
- **The consent wording** lives in `api/_lib/consent.json`, and the app's copy (`Sources/AnnotakeApp/EmailConsent.swift`) is tested against it. A change adds a new version and moves `current`; a shipped version is never edited. Deploy it, and see `make site-smoke URL=https://annotake.app`'s consent check pass (400, not 422), before releasing an app that sends the new id: until then the site answers that id 422, and every new copy's address waits on the app's backoff.
- **The address check** is `assets/email.js`, shared by the page and the functions. `EmailConsent.swift` mirrors it, tied to it only by test cases ported one for one, so a change to one changes the other and both test files.
- **Copy uses `’` for apostrophes in prose,** and straight quotes inside captions.

## Deploy

On Vercel:

- **The project:** from `fayzan123/annotake`, with Root Directory `site` and Framework Preset Other. `vercel.json` skips a build only when `site/` is unchanged since the last successful deployment (`VERCEL_GIT_PREVIOUS_SHA`).
- **Environment variables,** in Production only: `RESEND_API_KEY`, the link email's sending key, and for the email list `RESEND_CONTACTS_KEY` (full access), `RESEND_SEGMENT`, `RESEND_TOPIC_NOTICES`, `RESEND_TOPIC_NEWS`, `UNSUBSCRIBE_SECRET`, and `MAILING_ADDRESS`. `UNSUBSCRIBE_SECRET` is set once and never replaced: every unsubscribe link already sent depends on it. In Preview: `EMAIL_DRY_RUN=1`.
- **Web Analytics:** on. It's cookieless, and its script is `/_vercel/insights/script.js`.
- **Domains:** `annotake.app`, with `www.annotake.app`, `annotake.com`, and `www.annotake.com` redirecting to it.
- **The firewall:** a rate limit on `POST /api/link`, 10 requests per 600 s per IP, answering 429. Checkpoint 5 widens its path to `/api/*`.
- **After a deploy:** `make site-smoke URL=https://annotake.app` checks the pages, the headers, the redirects, and the functions. Its one `POST`, to `/api/subscribe`, is an address the function turns away before calling Resend, under the current consent id: 400 means the deployment has the app's wording, and 422 that it doesn't yet. `make site-burst URL=https://annotake.app` checks the firewall with 50 honeypot posts, which send no email.
