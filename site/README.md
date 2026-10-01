# annotake.app

The landing page, the privacy policy, the Terms, and one Vercel function that emails the download link. Plain HTML, CSS, and JavaScript modules: no framework, no build step, and no runtime packages. The design is [docs/plans/2026-10-01-landing-page-design.md](../docs/plans/2026-10-01-landing-page-design.md), and the plan that built it is [docs/plans/2026-10-01-landing-page-build.md](../docs/plans/2026-10-01-landing-page-build.md).

This file and `tests/` are never deployed (`.vercelignore`).

## Run it

```
make site-dev
```

Serves the site at http://localhost:4173 the way `vercel.json` says: clean URLs, the `/download` redirect, the headers, and `/api/link` in dry-run mode, so it never sends an email. The server is `tests/server.mjs`. The first run installs the test packages (`npm ci` in `tests/`).

## Test it

```
make site-unit                   # node:test: the server, the function, the email check, the brand, boot.js, the logo, the tools
make site-test                   # the unit tests, then the page tests in Chrome, WebKit, and Firefox
make site-test FILTER=hero       # only the page tests whose names match
```

- The page tests use the installed Google Chrome, and Playwright's WebKit and Firefox. Install those two once with `cd site/tests && npx playwright install webkit firefox`.
- Specs import `test`, `expect`, and the helpers from `tests/pages/support.js`. It works around three browser quirks; the session notes in `docs/plans/README.md` (Session 10) say why.
- Timing tests pause Playwright's clock (`pauseClock`) before loading the page, then move it with `page.clock.runFor`.

## Regenerate

```
make site-brand        # brand.js, img/brand.svg, img/favicon.svg, and img/apple-touch-icon.png from the app's
                       # BrandMark.swift and Wordmark.swift; img/favicon-32.png from Resources/AppIcon.icns
make site-brand-check  # fails if the committed brand files are out of date
make site-og           # img/og.v1.png, the preview image for links, from tests/tools/og.html
```

Never edit the generated files by hand. Fonts and images under `/assets/fonts/` and `/assets/img/` are cached as immutable, so a changed one needs a new name (`og.v2.png`), with every reference to it updated.

## Rules the code keeps

- **The CSP allows no inline scripts or styles:** no `<script>` with code and no `<style>` (JSON-LD data blocks are fine), and no `style="…"` or `style.cssText`. Code sets single properties (`element.style.left`, `style.setProperty('--k', …)`), toggles classes, and sets SVG attributes.
- **No cookies, and nothing from another origin.** The theme choice lives in `localStorage` (`annotake-theme`), and every access is wrapped in `try`/`catch`.
- **The function never logs, stores, or returns an email address.** Each request logs one `link: <outcome>` line.
- **Copy uses `’` for apostrophes in prose,** and straight quotes inside captions.

## Deploy

On Vercel (Checkpoint 4 in [docs/checkpoints.md](../docs/checkpoints.md) has the steps):

- **The project:** from `fayzan123/annotake`, with Root Directory `site` and Framework Preset Other. `vercel.json` skips the build when a commit leaves `site/` alone.
- **Environment variables:** `RESEND_API_KEY` in Production only, and `EMAIL_DRY_RUN=1` in Preview.
- **Web Analytics:** on. It's cookieless, and its script is `/_vercel/insights/script.js`.
- **Domains:** `annotake.app`, with `www.annotake.app`, `annotake.com`, and `www.annotake.com` redirecting to it.
- **The firewall:** a rate limit on `POST /api/link`, 10 requests per 600 s per IP, answering 429.
- **After a deploy:** `make site-smoke URL=https://annotake.app` checks the pages, the headers, the redirects, and the function. `make site-burst URL=https://annotake.app` checks the firewall with 50 honeypot posts, which send no email.
