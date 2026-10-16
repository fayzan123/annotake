# Annotake Landing Page Implementation Plan

> **How to execute:** one session (Session 10), run long and unattended, then one checkpoint (Checkpoint 4). Work through the tasks in order. For each task:
> 1. Write the listed tests.
> 2. Run them and watch them fail:
>    - Playwright page tests: `make site-test FILTER=<grep>`
>    - `node:test` unit tests: `make site-unit`
>    - Swift: `make test FILTER=<suite>`
> 3. Implement until they pass.
> 4. Run the task's **Verify** step: always `make site-test`, plus `make test` whenever the task touches Swift, plus whatever else the task lists.
> 5. Commit, with a `site:` prefix (`app:` for the Swift change in Task 2).
>
> Tasks marked **Glue** produce files that tests can't fully judge: the brand generator's PNGs, the preview image, and the checkpoint scripts. They're verified by running them and checking what they write, and they still get tests for any logic they contain.
>
> **No stops until the end.** Fayzan isn't there, so the session never waits for an answer:
> - **A test expectation in this plan looks wrong:** decide what's right, pin it with a test, and record the decision and why under "Decisions" in the Session 10 notes (Task 15). Don't stop to ask.
> - **A step can't finish without someone present** (a system prompt, a command that hangs): give it at most 10 minutes, skip only that step, record it under "Skipped" with what it needs, and carry on.
> - **The network fails** (npm, Playwright's browser download, the font or license download): retry up to three times, a few minutes apart. Meanwhile carry on with tasks that don't need it, and come back to it.
>
> **Nothing outward-facing.** The session never:
> - deploys to Vercel, creates accounts, or touches DNS or any dashboard;
> - sends a real email;
> - pushes anything but `main`, at the end.
>
> All of that is Checkpoint 4. **Never launch the full app;** only Task 2 touches Swift, and its checks are `make test` and the brand generator.
>
> Steps use checkbox (`- [ ]`) syntax for tracking. Don't use any superpowers skills to execute this plan.

**Goal:** Build annotake.app as designed, all tested locally and ready for Fayzan to connect to Vercel at the checkpoint:
- the page: the hero with Through the gate, How it works, the privacy block, the final call, and the animated footer logo;
- `/privacy` and `/terms`;
- the `/download` redirect;
- the "Email me the link" function.

**Architecture:**
- **The site:** `site/` is plain HTML, CSS, and ES modules, plus one Node function, `site/api/link.js`. The function sends the link email through Resend's HTTP API with `fetch`. There's no framework, no build step, and no runtime package.
- **Routing:** `site/vercel.json` holds the routes, redirects, and headers. A local server, `site/tests/server.mjs`, mirrors those rules, so every test runs without Vercel.
- **The brand:** the logo's shapes come from the app's `BrandMark.swift` and `Wordmark.swift`, through a generator script. The site never hand-copies them.
- **Tests:**
  - Playwright runs page tests against the local server in Chrome, WebKit, and Firefox. It's in `site/tests/`, the only npm packages, dev-only.
  - `node:test` covers the function and the pure modules.

**Tech Stack:**
- HTML, CSS, and JavaScript (ES2022 modules).
- Node 22 (at `~/.local/bin/node`) and npm.
- `@playwright/test` and `@axe-core/playwright`, dev-only.
- Swift 6.2 for the brand generator; `iconutil` and `sips` for the PNG icons.
- Make.

**Spec:** read these before starting:
- `docs/plans/2026-10-01-landing-page-design.md`, the design ("design §n").
- `docs/plans/mockups/2026-10-01-landing-page/page-v1.html` and `footer.html`, the approved mockups. They're the reference for the look, the timing, and the animation logic. They load Google Fonts and use inline styles, which the real site must not (Global Constraints). `page-v1.html`'s Phone view shows the phone flow's three states.
- `docs/plans/README.md`, the session rules.

**Changes from the design,** decided while planning; Task 15 writes them into the design doc:
1. **Each Resend attempt times out after 4 s,** not 5, so two attempts plus the pause between them fit inside the function's 10 s limit. The page shows the fallback if no answer comes within 12 s.
2. **Resend's 429 has three causes:**
   - a plain rate limit (10 requests a second by default) gets one retry after its `retry-after`, at most 1 s;
   - a daily or monthly quota answers "busy" at once.

   **A 409 about the idempotency key** means the email already went today, or is going, so it answers success.
3. **The too-fast check is 1 s, not 1.5 s.** Opening the form, accepting autofill, and tapping Send can take a person under 1.5 s, and they'd be told "sent" and get nothing.
4. **Jost is one variable Latin `woff2`** (26.6 KB, every weight), not three files.
5. **Third-party notices are plain files,** linked from the Terms:
   - `/licenses/sparkle.txt`: Sparkle's full LICENSE, the MIT license plus the notices for bsdiff and the other code it bundles;
   - `/licenses/jost-ofl.txt`.
6. **The WAF rate-limit rule stays a dashboard step at Checkpoint 4,** because `vercel.json` takes only deny rules. Skipping builds when `site/` is unchanged is `ignoreCommand` in `vercel.json`.
7. **The CSP drops `upgrade-insecure-requests`.** Every `.app` domain is HTTPS-only already, and the directive would break the local test server's plain HTTP.
8. **`BrandMark` gets two named constants,** `legThickness` and `braceThickness`, so the generator can read them. Nothing it draws changes.
9. **The theme and the Mac check run in one small classic script, `boot.js`, in `<head>`,** so neither the theme nor the button visibly switches during load.
   - The Mac check reads the user agent instead of the deprecated `navigator.platform`: a Mac user agent without iPhone, iPad, or iPod in it, plus `maxTouchPoints < 2`.
10. **One email check, `site/assets/email.js`,** is shared by the page and the function.
11. **The header and the no-JavaScript footer draw the logo from an SVG sprite,** `/assets/img/brand.svg`, through `<use>`. The footer animation builds its own live SVG from `brand.js`.
12. **The PNG icons (the favicon and the Apple touch icon) come from the committed app icon,** `Resources/AppIcon.icns`, so the browser tab and the Dock show the same icon.
13. **The Quick Look panel's second line ends "(from 3 candidates)",** as `StepsDocument` writes it.
14. **The burst test runs against production,** where the firewall rule applies, not a preview. It fills the honeypot field, so no email is sent.

**Global Constraints** (every task inherits these):
- **Copy,** asserted by the tests exactly as written:
  - Apostrophes in prose are `’` (U+2019).
  - The quotes inside captions and chips are straight `"`.
  - `{email}` is the address as the visitor typed it, trimmed.

| Where | Text |
|---|---|
| Home `<title>`, and `og:title` | `Annotake: show your coding agent exactly what happened` |
| Meta description, and `og:description` | `A Mac menu-bar app. Press a key, click through the bug in any app, and drag the card into Claude Code, Cursor, or ChatGPT: one captioned screenshot per step. Free during the beta.` |
| Headline (`h1`, second line in a `span`) | `Show your coding agent` / `exactly what happened.` |
| Hero line (the second sentence in `span.sub-more`, hidden under 600 px wide) | `Press a key, do the thing in any app, and drag the card into Claude Code, Cursor, or ChatGPT.` `Each step comes out as a screenshot, captioned with what you clicked.` |
| Download button (header, hero, final) | `Download for Mac` · while downloading: `Downloading…` |
| Download hint | `Open Annotake.dmg, then drag Annotake to Applications.` |
| Hero note | `Free during the beta · macOS 15 or later` / `By downloading, you agree to the Terms.` ("Terms" links `/terms`) |
| Final note | `Free during the beta · macOS 15 or later · Apple silicon and Intel` / `By downloading, you agree to the Terms.` |
| Link button (a `<summary>`) | `Email me the link` |
| Link note | `Annotake is a Mac app. Get the link in your inbox and download it there.` |
| Form | label `Your email` (visually hidden) · button `Send link`, while sending `Sending…` · note `We’ll send one email with the download link, and that’s all.` followed by a link `Privacy policy` |
| Form error | `That doesn’t look like an email address.` |
| Sent | `Check your inbox` / `We sent the link to {email}. Open it on your Mac.` / button `Wrong address? Try again` |
| Fallback | `We couldn’t send it right now. Here’s the link:` / `annotake.app/download` / buttons `Copy` (then `Copied`) and `Share` (only where `navigator.share` exists) |
| Gate captions, line 1 | `1/3 · 0:01 · Clicked tab "Appearance"` · `2/3 · 0:02 · Clicked switch "Dark mode"` · `3/3 · 0:04 · Clicked button "Save"` |
| Gate captions, line 2 | `Acme — Settings` |
| Acme toast | `Couldn’t save settings` |
| Gate pill | `0:00 · 0 frames` → `0:01 · 1 frame` → `0:02 · 2 frames` → `0:04 · 3 frames` |
| How it works | `h2` `How it works`, then three captions (bold line / grey line): `1/3 · Double-tap your key` / `Right ⌘ out of the box, or Right ⌥ or fn. Double-tap again when you’re done.` · `2/3 · Click through it` / `Each step comes out as a screenshot, captioned with what you clicked.` · `3/3 · Drag the card into your agent` / `Claude Code, Cursor, ChatGPT, or anything else that takes images.` |
| Step 1 keys (glyph · word · name · alternatives) | `⌘` `command` `Right ⌘` `or Right ⌥, or fn` · `⌥` `option` `Right ⌥` `or Right ⌘, or fn` · `fn` `globe` `fn` `or Right ⌘, or Right ⌥` |
| Step 1 pill | `0:0{s} · 0 frames · double-tap {glyph} to stop`, where `{glyph}` is `⌘`, `⌥`, or `fn` |
| Step 2 chips | `1/3` + `Clicked tab "Appearance"` · `2/3` + `Clicked switch "Dark mode"` · `3/3` + `Clicked button "Save"` |
| Step 2 pill | `{time} · {n} frame(s) · double-tap ⌘ to stop` |
| The card | `3 frames · 0:04` / `Drag into a chat · click to review` |
| Step 3 | terminal title `acme — claude` · dim line `~/acme · main` · chips `[Image #1]` `[Image #2]` `[Image #3]` · typed `dark mode doesn't stick after Save` |
| Privacy heading | `Nothing you record` / `leaves your Mac.` |
| Privacy rows | `Plain files` / `Each recording is a folder of PNGs and a steps.md in ~/Pictures/Annotake. They clear out after 30 days unless you choose to keep them.` · `No AI` / `Frames are picked by comparing pixels, and captions come from macOS Accessibility. No models, no uploads.` · `Only while you record` / `Annotake sees your screen only while you record, and it never records what you type.` (`steps.md` and the folder path are in `<code>`) |
| Finder | title `2026-10-01 at 09.41.12` · rows `01_0m01s.png` `412 KB` `PNG image` · `02_0m02s.png` `405 KB` `PNG image` · `03_0m04s.png` `418 KB` `PNG image` · `steps.md` `1 KB` `Markdown` · path `Macintosh HD › Users › you › Pictures › Annotake › 2026-10-01 at 09.41.12` |
| Final call | `Try it on your next bug.` |
| Footer | `© 2026 Fayzan Malik · Made in Ontario, Canada` · links `Privacy` `Terms` `hello@annotake.app` |
| 404 | `This page doesn’t exist.` · link `Go to annotake.app` |

  The Quick Look panel's text, exactly:

```
# Annotake capture — 2026-10-01 at 09.41.12
Screen: Built-in Retina Display · 0:04 · 3 frames (from 3 candidates)

1. 0:01 · Acme — Settings · Clicked tab "Appearance"
2. 0:02 · Acme — Settings · Clicked switch "Dark mode"
3. 0:04 · Acme — Settings · Clicked button "Save"
```

- **Colors and type:** the token table in design §3.9, unchanged. Jost comes from `/assets/fonts/jost-latin.v1.woff2` (`font-weight: 100 900`, `font-display: swap`) and is preloaded. The app's own UI uses `system-ui` and `ui-monospace`.
- **No cookies, no third parties:**
  - No response sets a cookie.
  - The page requests only its own origin. The user's `/download` click is the only exception.
  - No Google Fonts, no external scripts, images, or embeds.
  - The theme choice lives in `localStorage` under `annotake-theme` (`light` or `dark`). Every access is wrapped in `try`/`catch`.
- **The CSP,** exactly: `default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'; object-src 'none'`. So in code:
  - no inline `<script>` (JSON-LD data blocks are fine) and no `<style>`;
  - no `style="…"` in markup or in HTML strings, and no `setAttribute('style', …)` or `style.cssText`;
  - do set single properties (`el.style.left = …`, `el.style.setProperty('--k', …)`), use classes, and use SVG attributes (`points`, `x`, `width`, `transform`, `stroke-dashoffset`).
- **The other headers on every response:**
  - `Referrer-Policy: strict-origin-when-cross-origin`
  - `X-Content-Type-Options: nosniff`
  - `Permissions-Policy: camera=(), microphone=(), geolocation=()`
  - `Cross-Origin-Opener-Policy: same-origin`
  - `Strict-Transport-Security: max-age=63072000; includeSubDomains`

  `/assets/fonts/*` and `/assets/img/*` also get `Cache-Control: public, max-age=31536000, immutable`, and their file names carry a version (`.v1`) that changes whenever the file does.
- **Download:** `GET /download` answers `302` with `Location: https://github.com/fayzan123/annotake-releases/releases/latest/download/Annotake.dmg`.
- **The email:**
  - From `Annotake <hello@annotake.app>`, with `reply_to` `hello@annotake.app`.
  - Subject `Annotake for your Mac`.
  - The text body, exactly:

```
Here’s the Annotake download link you asked for:
https://annotake.app/download

Open it on your Mac (macOS 15 or later). Then open the disk image and drag Annotake to Applications.

This is the only email we’ll send you.

Annotake, made by Fayzan Malik in Ontario, Canada
https://annotake.app · Privacy: https://annotake.app/privacy
```

  The HTML body says the same, with the download URL as a link reading `Download Annotake for Mac`. Inline styles are fine there: it's an email, not the site.
- **Privacy in code:** the function never logs, stores, or returns an email address. It logs one line per request: `link: <outcome>`, plus an optional detail with no address in it. Nothing in `site/` stores an address.
- **No runtime packages:** nothing in `site/` outside `site/tests/` imports a package, and `site/package.json` has no dependencies.
- **Not deployed:** `site/.vercelignore` lists `tests/` and `README.md`.
- **Performance:** the first load transfers at most 200 KB, not counting `/_vercel/insights/script.js`.
- **Accessibility:**
  - WCAG AA contrast.
  - Under `prefers-reduced-motion: reduce`, every animation shows its final state and starts no timers.
  - Controls are labeled and focus rings stay visible.
  - Decorative pictures are `aria-hidden="true"`, and all their meaning is also in real text.
- **Test browsers:** three Playwright projects:
  - `chrome` uses `channel: 'chrome'`, the installed Google Chrome, so nothing downloads;
  - `webkit` and `firefox` are installed once with `npx playwright install webkit firefox`.

  Phone tests use an iPhone user agent and a 390 × 844 viewport, not `isMobile`, which Firefox lacks.
- **Generated files,** never edited by hand:
  - `make site-brand` writes `site/assets/brand.js`, `site/assets/img/brand.svg`, `site/assets/img/favicon.svg`, `favicon-32.png`, and `apple-touch-icon.png`.
  - `make site-og` writes `site/assets/img/og.v1.png`.
- **Environment variables:**
  - `RESEND_API_KEY`: Production only.
  - `EMAIL_DRY_RUN`: `1` in Preview, and always in the local server.
- **Dates:** the policies' "Last updated" is the session's date.

**Review Focus,** five inputs the design implies but nothing above tests directly, most likely first. Each has its pinning test in the named task.
1. **An iPad in desktop mode** (a Mac user agent with `maxTouchPoints` 5) gets "Email me the link", never the disk image. Task 4.
2. **Real-world addresses are accepted:** plus addressing (`sam+annotake@gmail.com`), capitals, surrounding spaces, and non-ASCII (`jürgen@müller.de`, `用户@例子.广告`). "One email per address per day" holds whatever the capitals. Tasks 5 and 6.
3. **Impatient taps:** pressing Send link twice, or Enter and then the button, sends one request and shows one result. Task 5.
4. **A slow or failing Resend:** the function always answers within its 10 s limit, and the page always ends in the sent state or the fallback, never a spinner. Tasks 5 and 6.
5. **Blocked storage** (Safari private browsing, or site data blocked): `localStorage` throws, and the page still renders, follows the system theme, and the toggle still switches for the visit. Task 3.

## File map

| File | Responsibility |
|---|---|
| `site/index.html` | The page: header, hero, gate, How it works, privacy, final call, footer |
| `site/privacy.html`, `site/terms.html`, `site/404.html` | The policies and the not-found page, in the same frame |
| `site/licenses/sparkle.txt`, `site/licenses/jost-ofl.txt` | Third-party notices, as published |
| `site/robots.txt`, `site/sitemap.xml` | For search engines |
| `site/vercel.json` | Routes, the `/download` redirect, headers, the function's limit, skipping unchanged builds |
| `site/.vercelignore` | Keeps `tests/` and `README.md` out of deployments |
| `site/package.json` | `{"private": true, "type": "module"}`, no dependencies |
| `site/README.md` | How to run, test, regenerate, and deploy the site |
| `site/api/link.js` | The link email function |
| `site/assets/site.css` | Every style: tokens, layout, sections, animations |
| `site/assets/boot.js` | A classic script in `<head>`: sets `data-theme` and `data-device` before the first paint, and exposes `window.annotakeBoot` |
| `site/assets/site.js` | The module entry: the toggle, the download hint, and starting each part below |
| `site/assets/email.js` | `cleanEmail`, `isPlausibleEmail`, `emailKey`, shared by the page and the function |
| `site/assets/linkform.js` | The link form's states and requests |
| `site/assets/acme.js` | The drawn Acme Settings window and its three clicks |
| `site/assets/gate.js` | Through the gate |
| `site/assets/steps.js` | How it works |
| `site/assets/logo.js` | The footer tripod animation and its geometry |
| `site/assets/brand.js` | Generated: the brand's numbers and SVG path data |
| `site/assets/fonts/jost-latin.v1.woff2` | Jost, variable, Latin subset |
| `site/assets/img/brand.svg`, `favicon.svg`, `favicon-32.png`, `apple-touch-icon.png`, `og.v1.png` | Generated images |
| `site/tests/package.json`, `package-lock.json`, `playwright.config.js` | The test harness (dev-only) |
| `site/tests/server.mjs` | The local server that mirrors Vercel |
| `site/tests/unit/*.test.js` | `node:test` unit tests |
| `site/tests/pages/*.spec.js` | Playwright page tests |
| `site/tests/tools/og.html`, `make-og.mjs`, `smoke.mjs`, `burst.mjs` | The preview image's source and renderer, and the checkpoint tools |
| `scripts/make-site-brand.swift` | Writes the brand files from `BrandMark.swift` and `Wordmark.swift` |
| `Sources/AnnotakeApp/BrandMark.swift`, `Tests/AnnotakeAppTests/BrandTests.swift` | The two named thicknesses, and their tests |
| `Makefile` | `site-dev`, `site-unit`, `site-test`, `site-brand`, `site-brand-check`, `site-og`, `site-smoke`, `site-burst` |
| `.gitignore` | `site/tests/node_modules/`, `site/tests/test-results/`, `site/tests/playwright-report/` |
| `docs/plans/2026-10-01-landing-page-design.md`, `docs/plans/README.md`, `docs/checkpoints.md` | The planning changes, the session notes, and Checkpoint 4 |

---

### Task 1: The site skeleton, the local server, and the test harness

**Files:**
- Create: `site/package.json`, `site/vercel.json`, `site/.vercelignore`, `site/index.html` (just a frame: `lang="en"`, charset, viewport, the title, and the CSS link), `site/404.html`, `site/assets/site.css` (empty).
- Create: `site/tests/package.json` (with `"type": "module"`), `site/tests/package-lock.json`, `site/tests/playwright.config.js`, `site/tests/server.mjs`.
- Test: `site/tests/unit/server.test.js`, `site/tests/unit/vercel-json.test.js`, `site/tests/pages/routes.spec.js`.
- Modify: `Makefile`, `.gitignore`.

**Interfaces:**
- Produces:
  - `export function createServer({ root, env }) → http.Server`, plus the command line `node site/tests/server.mjs [--port 4173] [--root site]`;
  - the Make targets `site-dev` (the server on port 4173), `site-unit` (`node --test unit/`), and `site-test` (`site-unit`, then `npx playwright test`, with `--grep` from `FILTER`). Each target runs `npm ci` first if `site/tests/node_modules` is missing.
- `site/vercel.json`, exactly these keys:
  - `"$schema": "https://openapi.vercel.sh/vercel.json"`
  - `"framework": null`
  - `"cleanUrls": true`
  - `"trailingSlash": false`
  - `"ignoreCommand": "git diff --quiet HEAD^ HEAD -- ."`. The email list build changed it to skip only when `site/` is unchanged since the last successful deployment (`VERCEL_GIT_PREVIOUS_SHA`), since this one skipped any push whose last commit left `site/` alone ([design §5.2](2026-10-01-landing-page-design.md#52-routes-verceljson)).
  - `"functions": {"api/link.js": {"maxDuration": 10}}`
  - `"redirects": [{"source": "/download", "destination": "<the GitHub URL>", "statusCode": 302}]`
  - `"headers"`: `/(.*)` gets the CSP and the five headers, and `/assets/fonts/(.*)` and `/assets/img/(.*)` get the immutable `Cache-Control`.
- **What the server mirrors:**
  - `cleanUrls`: `/privacy` serves `privacy.html`, and `/privacy.html` answers `308` to `/privacy`.
  - `trailingSlash`: `/privacy/` answers `308` to `/privacy`.
  - The `redirects`.
  - The `headers`: it reads `vercel.json` and matches `source` patterns, where `(.*)` stands for any rest of the path.
  - `404.html`, with status 404.
  - Content types: html, css, js (`text/javascript`), svg, png, woff2, txt (`text/plain; charset=utf-8`), and xml.
  - Nothing under `/tests/`, `/README.md`, or above the root is served (404).
  - `/_vercel/insights/script.js` answers an empty `200` script, standing in for Vercel's analytics.
  - `POST` and `GET` to `/api/link` run `<root>/api/link.js`'s exported handler for that method, with a web `Request`, and `405` when the method isn't exported. `env.EMAIL_DRY_RUN` defaults to `1`.

**Steps:**
- [ ] Create `site/tests/package.json` with the dev dependencies `@playwright/test` and `@axe-core/playwright` (latest). Run `npm install` in `site/tests` and commit the lock file. Then run `npx playwright install webkit firefox` (the network rules apply).
- [ ] Write `server.test.js` against a temporary fixture root: a few HTML files, an asset, a copy of the real `vercel.json`, and a fixture `api/link.js` whose `POST` returns `{ok: true}`. It pins every behavior in "What the server mirrors":
  - each status, `Location`, and content type;
  - the CSP's exact value and the five headers on a page, an asset, and the 404;
  - the immutable cache on a font and an image;
  - no `Set-Cookie` on any response;
  - `/tests/server.mjs` and `/../Makefile` answering 404;
  - `PUT /api/link` answering 405.
- [ ] Write `vercel-json.test.js`: it parses `site/vercel.json` and asserts every key and value above.
- [ ] Write `routes.spec.js`, in all three browsers:
  - `/` answers 200 with the home title;
  - the document's response carries the CSP;
  - there are no console errors;
  - `context.cookies()` is empty.
- [ ] Run `make site-unit` and `make site-test`, and watch them fail.
- [ ] Implement the server, the config files, the frame pages, the Make targets (added to `.PHONY`), and the `.gitignore` lines.
- [ ] **Verify:**
  - `make site-test` passes in all three browsers;
  - `make site-dev`, then `curl -sI localhost:4173/` in another shell shows the CSP, and `curl -sI localhost:4173/download` shows the 302.
- [ ] Commit: `site: the skeleton, a local server that mirrors Vercel, and the test harness`.

### Task 2: The brand, generated from BrandMark.swift

**Files:**
- Modify: `Sources/AnnotakeApp/BrandMark.swift`, `Tests/AnnotakeAppTests/BrandTests.swift`, `Makefile`.
- Create: `scripts/make-site-brand.swift`.
- Generated: `site/assets/brand.js`, `site/assets/img/brand.svg`, `site/assets/img/favicon.svg`, `site/assets/img/favicon-32.png`, `site/assets/img/apple-touch-icon.png`.
- Test: `site/tests/unit/brand.test.js`.

**Interfaces:**
- **BrandMark** gains `static let legThickness = 0.95 * stem` and `static let braceThickness = 0.85 * stem`, and `shapes` uses them where it used those factors. `shapes` stays seven entries in this order: left leg, right leg, brace, body, lens, back reel, front reel.
- **`make site-brand`:**
  1. Compiles `swiftc -parse-as-library -o build/make-site-brand scripts/make-site-brand.swift Sources/AnnotakeApp/BrandMark.swift Sources/AnnotakeApp/Wordmark.swift`, then runs `build/make-site-brand site/assets`.
  2. Runs `iconutil -c iconset Resources/AppIcon.icns -o build/site-icons.iconset`.
  3. Copies `icon_32x32.png` to `site/assets/img/favicon-32.png`, and turns `icon_256x256.png` into `apple-touch-icon.png` with `sips -z 180 180`.

  **`make site-brand-check`** regenerates the text files into `build/site-brand-check/` and `diff`s them against the committed ones. It fails on any difference.
- **`site/assets/brand.js`,** generated:
  - First line: `// Generated by scripts/make-site-brand.swift from BrandMark.swift and Wordmark.swift. Don't edit: run make site-brand.`
  - Exports:
    - `CHARCOAL = '#1C1C1E'` and `RED = '#FF3B30'`;
    - `GEOMETRY = {footSpan, splayDegrees, stem, legThickness, braceThickness, legTop, crossbarY}`, with 4 decimals;
    - `PATHS = {leftLeg, rightLeg, brace, body, lens, backReel, frontReel, letters}`: SVG path data in logo units, with 2 decimals and no trailing zeros. `letters` is `Wordmark.letterPaths` with its whitespace collapsed;
    - `FRONT_REEL = {cx, cy, outer, inner}`;
    - `LOGO_VIEWBOX = [-6, -232.68, 644.06, 240.11]`: the mark and letters, padded by 6;
    - `MARK_VIEWBOX`: the mark alone, square, padded.
  - Number formatting is deterministic: `-0` prints as `0`.
- **`site/assets/img/brand.svg`:** a sprite with two symbols, `<symbol id="logo">` and `<symbol id="mark">`, in those view boxes.
  - Ink paths have `fill="currentColor"`.
  - The front reel's path has no `fill` attribute, so it inherits the `fill` property from the `<use>` element. Pages set `color` for the ink and `fill` for the reel.
  - The rings have `fill-rule="evenodd"`.
- **`site/assets/img/favicon.svg`:** a 64 × 64 view box with a charcoal rounded square (the app icon's body: inset 100/1024 and radius 186/824 of its width). Inside it, the mark in white with a red front reel, at 62% of the body's height, as in `make-icon.swift`.

**Steps:**
- [ ] In `BrandTests`, add tests that:
  - `legThickness == 0.95 * stem` and `braceThickness == 0.85 * stem`;
  - `shapes` has 7 entries in the listed order, judged by bounding boxes (within 0.01):
    - the left leg: x 0 to 76.52;
    - the right leg: x 44.48 to 121;
    - the brace: y −46.8 to −29.2;
    - the body: y −163.76 to −96;
    - the lens: x 119.79 to 151.25;
    - the back reel: center x 27.83;
    - the front reel: `part == .frontReel`.

  Run `make test FILTER=BrandTests` and watch it fail.
- [ ] Add the constants and use them in `shapes`. `make test FILTER=BrandTests` passes, and so does `make test`.
- [ ] Commit: `app: BrandMark names its leg and brace thickness`.
- [ ] Write `brand.test.js`:
  - `brand.js` imports;
  - `GEOMETRY` matches (footSpan 121, splayDegrees 26, stem 20.71, legThickness 19.6745, braceThickness 17.6035, legTop −112, crossbarY −38);
  - parsing `PATHS.leftLeg` gives the points (0, 0), (21.89, 0), (76.52, −112), (54.63, −112), and `PATHS.brace` gives the rectangle at x 29.48–91.52, y −46.8 to −29.2, both within 0.01;
  - `LOGO_VIEWBOX` matches;
  - `PATHS.letters` starts with `M169.45 -40` and ends with `Z`;
  - `brand.svg` has both symbols, and its front reel's path has no `fill` attribute;
  - both PNGs exist, at 32 × 32 and 180 × 180, read from their IHDR chunk.

  Run `make site-unit` and watch it fail.
- [ ] Write `scripts/make-site-brand.swift`. It turns a `CGPath` into path data with `applyWithBlock`, covering move, line, quad, curve, and close. It writes the three text files, and the Make target adds the two PNGs.
- [ ] Run `make site-brand`. Then `make site-unit` passes, and `make site-brand-check` reports no difference.
- [ ] **Verify:** `make test`, `make site-test`, and `make site-brand-check`.
- [ ] Commit: `site: the brand, generated from BrandMark.swift`.

### Task 3: Tokens, the font, the theme, and the page frame

**Files:**
- Create: `site/assets/boot.js`, `site/assets/site.js`, `site/assets/fonts/jost-latin.v1.woff2`, `site/licenses/jost-ofl.txt`.
- Modify: `site/index.html`, `site/404.html`, `site/assets/site.css`.
- Test: `site/tests/unit/boot.test.js`, `site/tests/pages/theme.spec.js`.

**Interfaces:**
- **`boot.js`** is a classic script, the first one in `<head>` (`<script src="/assets/boot.js"></script>`, with no `async` or `defer`). It:
  - sets `document.documentElement.dataset.theme` to the stored choice when that's valid, otherwise to the system's (`matchMedia('(prefers-color-scheme: dark)')`);
  - follows system changes while nothing is stored;
  - defines `window.annotakeBoot = { resolveTheme(stored, systemDark), setTheme(theme), isMacDesktop(userAgent, maxTouchPoints) }`. `isMacDesktop` arrives in Task 4.
  - `setTheme` applies the theme and stores it, and a storage failure is ignored.
- **`site.js`** (`<script type="module" src="/assets/site.js">`) wires every `.theme-toggle` button: it calls `annotakeBoot.setTheme` with the other theme, and keeps the button's `aria-label` at `Switch to dark theme` or `Switch to light theme`. The sun icon shows in light and the moon in dark.
- **The frame on every page:**
  - **The header:** the logo link to `/` (`aria-label="Annotake home"`, and an `<svg class="logo"><use href="/assets/img/brand.svg#logo"/></svg>`), the toggle, and `a.btn.btn-sm.mac-only[href="/download"]`.
  - **The footer:** `div.giant` holding the static `<use href="/assets/img/brand.svg#logo">` logo, then the legal row with the footer copy and links.
  - The `<head>` preloads the font, links `site.css`, and ends with `<script defer src="/_vercel/insights/script.js"></script>` for Vercel Web Analytics. The local server stubs that script.
  - The tokens are on `:root[data-theme="light"]` and `:root[data-theme="dark"]`. A `prefers-color-scheme` fallback covers `:root:not([data-theme])`, for when scripts don't run.
- **The font:**
  - Download the Latin `woff2` that `https://fonts.googleapis.com/css2?family=Jost:wght@400;500;600` lists. Request it with a desktop Chrome user agent and take the `/* latin */` face's URL. It was 26,588 bytes on 2026-10-01.
  - Use that face's `unicode-range`.
  - The license comes from `https://raw.githubusercontent.com/google/fonts/main/ofl/jost/OFL.txt`.

**Steps:**
- [ ] Write `boot.test.js`. It loads `boot.js`'s text into `node:vm` with fake `window`, `document`, `matchMedia`, and `localStorage`:
  - `resolveTheme` covers `'dark'`, `'light'`, null, and junk, against both system values;
  - at load: a stored `'dark'` with a light system gives `data-theme` `dark`, and nothing stored follows the system;
  - a system change applies only when nothing is stored;
  - **Review Focus 5:** a `localStorage` whose getter throws, or whose `setItem` throws, causes no error, and the theme still applies.
- [ ] Write `theme.spec.js`, in all three browsers:
  - the emulated `colorScheme` sets `data-theme` and the `--bg` value (`#ffffff` or `#141416`);
  - the toggle switches, survives a reload, and its `aria-label` updates;
  - `index.html` has `boot.js` as the first script in `<head>`;
  - **Review Focus 5:** with storage blocked by an init script that makes `localStorage` throw, the page renders, there are no console errors, the theme follows the system, and the toggle switches;
  - the `h1`'s computed family starts with `Jost`, and `document.fonts.check('600 16px Jost')` is true after load;
  - the header logo's `<use>` renders (bounding box wider than 0);
  - every page's `<head>` has the deferred `/_vercel/insights/script.js` tag;
  - axe's color-contrast rule passes on the frame, in both themes.

  Run them and watch them fail.
- [ ] Implement `boot.js`, the toggle in `site.js`, the tokens and frame styles in `site.css`, the frame markup on `index.html` and `404.html`, the font, and the license file.
- [ ] **Verify:** `make site-test`.
- [ ] Commit: `site: tokens, Jost, the light and dark themes, and the page frame`.

### Task 4: The hero and the Mac check

**Files:**
- Modify: `site/assets/boot.js`, `site/index.html`, `site/assets/site.css`, `site/assets/site.js`.
- Test: `site/tests/unit/boot.test.js` (extended), `site/tests/pages/hero.spec.js`.

**Interfaces:**
- **`annotakeBoot.isMacDesktop(userAgent, maxTouchPoints)`** is true when all three hold:
  - `/Macintosh/` matches;
  - `/iPhone|iPad|iPod/` doesn't;
  - `maxTouchPoints < 2`.

  `boot.js` sets `document.documentElement.dataset.device` to `mac` or `other` before the first paint.
- **CSS:**
  - `[data-device="mac"] .other-only` and `[data-device="other"] .mac-only` are hidden.
  - With no `data-device` (no JavaScript), both show: the download first, then the details below it, as a secondary link.
  - Under `data-device="other"`, the `<summary>` is styled as the main button.
- **Hero markup:** `section.hero` holds:
  - the `h1`;
  - `p.sub`, with its `span.sub-more`;
  - `div.cta`, which holds:
    - `a.btn.btn-lg.mac-only[href="/download"]`;
    - `p.note.mac-only`, with two lines;
    - `details.getlink.other-only`, holding `<summary>Email me the link</summary>`, the link note, and a form slot that Task 5 fills;
    - `p.dl-hint`, which starts `hidden`.
- **The download click:** `site.js` handles clicks on any `a[href="/download"]` without `preventDefault`, so the browser downloads the DMG.
  - The clicked button's text becomes `Downloading…` for 2 s, then comes back.
  - The nearest `.dl-hint` is unhidden.

**Steps:**
- [ ] Extend `boot.test.js` with an `isMacDesktop` table:

| User agent | `maxTouchPoints` | Expected |
|---|---|---|
| Mac Safari 18 | 0 | true |
| Mac Chrome | 0 | true |
| Mac Firefox | 0 | true |
| iPhone Safari | 5 | false |
| iPad with an `iPad` user agent | 5 | false |
| iPad in desktop mode: Mac Safari's user agent (Review Focus 1) | 5 | false |
| Android Chrome | 5 | false |
| Windows Edge | 0 | false |
| Linux Firefox | 0 | false |
| `''` | 0 | false |

  Also: `data-device` is set at load.
- [ ] Write `hero.spec.js`:
  - **On a Mac** (the browsers' own Mac user agents):
    - the exact headline, hero line, button, and note text;
    - the button's `href` is `/download`;
    - the details are hidden, and the header's button shows.
  - **On an iPhone** (user agent and 390 × 844):
    - `Email me the link` shows, and the download buttons don't;
    - the hero line shows only its first sentence.
  - **On an iPad in desktop mode** (Review Focus 1): a Mac user agent plus an init script that defines `navigator.maxTouchPoints` as 5 gives `Email me the link`.
  - **The download click:** route `https://github.com/**` to an empty attachment response, and use `page.clock`.
    - The button reads `Downloading…`, then `Download for Mac` again after 2 s.
    - The hint shows its exact text.
  - **With JavaScript disabled:** both the download link and the details show, and the summary reads `Email me the link`.
  - **No sideways scrolling** at 320 and 1440 px wide.

  Run them and watch them fail.
- [ ] Implement.
- [ ] **Verify:** `make site-test`.
- [ ] Commit: `site: the hero, and Download for Mac only on a Mac`.

### Task 5: The email check and the link form

**Files:**
- Create: `site/assets/email.js`, `site/assets/linkform.js`.
- Modify: `site/index.html` (a form in the hero's details; Task 9 adds the same form to the final call, with its own ids), `site/assets/site.css`, `site/assets/site.js`.
- Test: `site/tests/unit/email.test.js`, `site/tests/pages/linkform.spec.js`.

**Interfaces:**
- **`email.js`,** pure, for both the browser and Node:
  - `export function cleanEmail(input)`: `String(input ?? '')`, trimmed and normalized to NFC.
  - `export function isPlausibleEmail(input)`: on the cleaned string, all of these hold:
    - its length is 3–254;
    - it has exactly one `@`;
    - the local part has 1–64 characters;
    - the domain contains a `.`, doesn't start or end with one, and has no `..`;
    - there's no whitespace or control character (`\s`, U+0000–U+001F, U+007F);
    - every other Unicode character is allowed.
  - `export function emailKey(input)`: the cleaned string, lowercased.
- **`linkform.js`:** `export function initLinkForm(form, { fetch = window.fetch, now = () => performance.now(), share = navigator.share?.bind(navigator), clipboard = navigator.clipboard, timeoutMs = 12000 } = {})`.
- **The form markup,** one per call to action, with unique ids:

```html
<form class="linkform" action="/api/link" method="post" novalidate>
  <label class="vh" for="email-hero">Your email</label>
  <input id="email-hero" name="email" type="email" autocomplete="email" inputmode="email" required>
  <input class="hp" name="website" tabindex="-1" autocomplete="off" aria-hidden="true">
  <input type="hidden" name="t" value="">
  <button type="submit">Send link</button>
  <p class="linkform-note">We’ll send one email with the download link, and that’s all. <a href="/privacy">Privacy policy</a></p>
  <p class="linkform-error" role="alert" hidden>That doesn’t look like an email address.</p>
</form>
<div class="linkform-sent" role="status" hidden><!-- the Sent copy and its Try again button --></div>
<div class="linkform-fallback" role="status" hidden><!-- the Fallback copy, the link, Copy, and Share --></div>
```

  `.vh` and `.hp` hide things from view without `display: none`, so the label stays readable to screen readers and bots still see the trap.
- **What happens on submit:**
  1. It's ignored while a request is in flight, and the button is disabled and reads `Sending…`.
  2. An implausible address shows the error and refocuses the field, with no request.
  3. Otherwise it `POST`s JSON `{email: cleanEmail(value), website, t: Math.round(now() - loadedAt)}` to `/api/link`, with an `AbortController` that stops it after `timeoutMs`.
  4. **On 200:** the sent state shows the address.
  5. **On 400:** the error shows.
  6. **On anything else, a network error, or the timeout:** the fallback shows.
     - **Copy** calls `clipboard.writeText('https://annotake.app/download')` and then reads `Copied`.
     - **Share** shows only when `share` is a function, and calls `share({title: 'Annotake for Mac', url: 'https://annotake.app/download'})`.
  7. **`Wrong address? Try again`** brings the form back, keeps the address, and focuses the field.
- **Without JavaScript,** the form posts natively, and `t` stays empty.

**Steps:**
- [ ] Write `email.test.js`:
  - **Accepted** (Review Focus 2): `sam@example.com`, `  Sam@Example.COM `, `sam+annotake@gmail.com`, `jürgen@müller.de`, `用户@例子.广告`, `a@b.co`.
  - **Rejected:**
    - `''`, `sam`, `sam@`, and `@example.com`;
    - `sam@example`, `sam@@example.com`, and `sam@exa mple.com`;
    - `sam@example.com\r\nBcc: x@y.z`;
    - `sam@.example.com`, `sam@example.` and `sam@example..com`;
    - a 255-character address, and a 65-character local part.
  - `emailKey('  Sam@Example.COM ') === 'sam@example.com'`.
- [ ] Write `linkform.spec.js`, on an iPhone user agent, with `page.route('/api/link')` and stubs for `navigator.clipboard` and `navigator.share` set by an init script:
  - **A 200:** the sent text with the address, and the request's JSON holds the cleaned `email`, an empty `website`, and a numeric `t`.
  - **A 400:** the error shows, and the form stays.
  - **A 429, a 502, or an aborted request:** the fallback shows.
    - Copy writes the URL, and the button reads `Copied`.
    - Share is called with the URL.
    - Without a `navigator.share` stub, there's no Share button.
  - **Review Focus 4:** a route that never answers ends in the fallback after `page.clock.runFor(12000)`.
  - **Review Focus 3:** clicking Send twice quickly and pressing Enter makes exactly one request.
  - **A bad address:** the error shows, with no request.
  - **Try again:** the form returns with the address kept and the field focused.
  - **The keyboard:** Tab reaches the field and the button, and Enter submits.

  Run them and watch them fail.
- [ ] Implement.
- [ ] **Verify:** `make site-test`.
- [ ] Commit: `site: Email me the link, with a fallback that always shows the link`.

### Task 6: The link function

**Files:**
- Create: `site/api/link.js`.
- Test: `site/tests/unit/link.test.js`, `site/tests/pages/link-integration.spec.js`.

**Interfaces:**
- **Produces:**
  - `export function createHandler({ fetch, env, log, sleep, today, timeoutMs = ATTEMPT_TIMEOUT_MS }) → { POST(request), GET(request) }`.
  - Module-level exports built with the real dependencies: `export const { POST, GET } = createHandler({ fetch: globalThis.fetch, env: process.env, log: line => console.log(line), sleep: ms => new Promise(r => setTimeout(r, ms)), today: () => new Date().toISOString().slice(0, 10) })`.
  - `export const RESEND_URL = 'https://api.resend.com/emails'`, `ATTEMPT_TIMEOUT_MS = 4000`, `RETRY_PAUSE_MS = 300`, `MAX_RATE_WAIT_MS = 1000`, `TOO_FAST_MS = 1000`, `MAX_BODY_BYTES = 2048`, `EMAIL_TEXT`, and `EMAIL_HTML`.
- **Consumes:** `cleanEmail`, `isPlausibleEmail`, and `emailKey` from `../assets/email.js`.
- **`POST`, in order:**
  1. **Parse:** `application/json` reads `{email, website, t}`, and `application/x-www-form-urlencoded` reads the same fields. Any other type, bad JSON, or a body over `MAX_BODY_BYTES` is `invalid`.
  2. A non-empty `website` is ignored: answer success, log `link: ignored honeypot`.
  3. A `t` that's present and parses to a number under `TOO_FAST_MS` is ignored: success, `link: ignored too fast`. A form post without `t` skips this check.
  4. `!isPlausibleEmail(email)` is `invalid`.
  5. `env.EMAIL_DRY_RUN === '1'` answers success, `link: dry run`.
  6. A missing `env.RESEND_API_KEY` is `send`, `link: failed not configured`.
  7. **Send.** Each attempt is a `fetch(RESEND_URL)` with:
     - `method: 'POST'`;
     - the headers `Authorization: Bearer <key>`, `Content-Type: application/json`, and `Idempotency-Key: link-<today()>-<sha256 hex of emailKey(email)>`, using `node:crypto`;
     - a JSON body of `{from: 'Annotake <hello@annotake.app>', to: [cleanEmail(email)], reply_to: 'hello@annotake.app', subject: 'Annotake for your Mac', text: EMAIL_TEXT, html: EMAIL_HTML}`. It's the same every time, so a repeated key never conflicts;
     - `signal: AbortSignal.timeout(timeoutMs)`.

     How each answer maps:

| Resend answers | Outcome |
|---|---|
| 200 | success, `link: sent` |
| 409 (`invalid_idempotent_request` or `concurrent_idempotent_requests`) | success, `link: sent already today` |
| 429 whose JSON `name` is `daily_quota_exceeded` or `monthly_quota_exceeded` | `busy`, `link: busy quota` |
| Any other 429 | Retry once, after `min(retry-after, 1)` seconds (default 1) |
| 5xx, a network error, or the timeout | Retry once, after `RETRY_PAUSE_MS` |
| Any other 4xx | `send`, `link: failed rejected <status>` |

     The retry maps its answer the same way, but never retries again: a 429 is `busy`, and a 5xx or timeout is `send`. The worst case is 4000 + 1000 + 4000 ms, under the 10 s limit.
- **Answers:**
  - **JSON:** success is 200 `{ok: true}`, `invalid` is 400 `{ok: false, reason: "invalid"}`, `busy` is 429 `{ok: false, reason: "busy"}`, and `send` is 502 `{ok: false, reason: "send"}`.
  - **A form-encoded request** gets `text/html` instead: a minimal page that links `/assets/site.css`, with no inline style or script.
    - Success shows `Check your inbox` and `We sent the link to your email. Open it on your Mac.`
    - `invalid` shows `That doesn’t look like an email address.` and a link back to `/`.
    - Anything else shows `We couldn’t send it right now. Here’s the link: https://annotake.app/download`.
  - `GET` answers 405 `{ok: false}`.

**Steps:**
- [ ] Write `link.test.js`, with fake `fetch`, `sleep`, `today` (`'2026-10-01'`), and `log`, and `timeoutMs: 50`:
  - **A good JSON request:**
    - exactly one fetch, to `RESEND_URL`;
    - the headers match;
    - the key matches `/^link-2026-10-01-[0-9a-f]{64}$/`;
    - the body's fields match, with `to` trimmed;
    - the answer is 200.
  - **Review Focus 2:** `Sam@Example.com` and `sam@example.com` give the same key.
  - **Ignored, with no fetch:** the honeypot, and `t: 200`. A form post without `t` does fetch.
  - **400, with no fetch:** a bad address, a 3 KB body, `text/plain`, and bad JSON.
  - **Dry run:** 200, with no fetch.
  - **No key:** 502, and the log says `not configured`.
  - **Retries:**
    - a 500, then a 200, gives 200 after one `sleep(300)`;
    - two network errors give 502 after two attempts;
    - two hangs give 502 after two attempts (the fake fetch rejects on its signal's abort);
    - **Review Focus 4:** `ATTEMPT_TIMEOUT_MS * 2 + MAX_RATE_WAIT_MS < 10000`.
  - **Resend's answers:**
    - a 429 rate limit with `retry-after: 0.5`, then a 200, gives 200 after `sleep(500)`;
    - two 429s give 429;
    - `daily_quota_exceeded` gives 429 with no retry;
    - a 409 gives 200;
    - a 422 gives 502 with no retry.
  - **Other requests:** `GET` gives 405. Form-encoded success gives `text/html` containing `Check your inbox`, and form-encoded failure contains `https://annotake.app/download`.
  - **Privacy:** across every test, no log line contains the address or its local part.
- [ ] Write `link-integration.spec.js`, through the local server, which defaults to dry run:
  - on an iPhone user agent, the hero form reaches the sent state;
  - with JavaScript disabled, opening the details and submitting the form shows a page with `Check your inbox`.

  Run them and watch them fail.
- [ ] Implement.
- [ ] **Verify:** `make site-test`.
- [ ] Commit: `site: the link function, with retries that fit Vercel's 10 s limit`.

### Task 7: Through the gate

**Files:**
- Create: `site/assets/acme.js`, `site/assets/gate.js`.
- Modify: `site/index.html` (`<section class="gate-wrap" aria-hidden="true"></section>` after the hero), `site/assets/site.css` (port the mockup's strip, frame, Acme, ring, press, flash, pill, and unexposed styles, as classes), `site/assets/site.js`.
- Test: `site/tests/pages/gate.spec.js`.

**Interfaces:**
- **`acme.js`:**
  - `export const AT = { start: [118, 74], appearance: [27, 43], dark: [175, 51], save: [164, 88] }`, in Acme units (the window is 196 × 104).
  - `export const START = { side: 0, dark: false, toast: false }`.
  - `export const CLICKS`: three entries, `{ at, change(state) → state, caption, chip, time }`.
    - **Appearance:** `side: 1`, `'1/3 · 0:01 · Clicked tab "Appearance"'`, `'Clicked tab "Appearance"'`, `'0:01'`.
    - **Dark mode:** `dark: true`, `'2/3 · 0:02 · Clicked switch "Dark mode"'`, `'Clicked switch "Dark mode"'`, `'0:02'`.
    - **Save:** `toast: true`, `'3/3 · 0:04 · Clicked button "Save"'`, `'Clicked button "Save"'`, `'0:04'`.
  - `export function stateAfter(n)`: the state after the first `n` clicks.
  - `export function acmeWindow({ cursor = false } = {}) → HTMLElement`, built with `createElement` and classes only:
    - the title bar and the sidebar bars, whose widths come from `:nth-child` rules;
    - the main pane, the switch rows, Save, and the toast;
    - `.ring`, `.press`, and an optional `.cursor` SVG.

    Everything is sized in `em`, with 1 em equal to one Acme unit.
  - `export function setAcme(el, state)` and `export function place(el, [x, y])`. `place` sets `el.style.left` and `el.style.top` in em.
- **`gate.js`:** `export function initGate(root, { reducedMotion }) → { stop() }`.
  - **It builds:**
    - `.strip`, holding `.holes.top`, `.holes.bottom`, and a `.track` of 10 `.slot`s, for i = −3 to 6;
    - in each slot, a `.frame` holding an Acme window and a `.cap` with a `b` and a `span` (`Acme — Settings`), plus an `.unexposed` cover;
    - `.gate`, holding four `.corner`s, `.flash`, and `.pill`, which holds `.dot` and `span.pill-text`.

    The strip's font size is `calc(var(--fw) / 196)`, with `--fw: clamp(180px, 19.5vw, 280px)`. The track moves through the custom property `--k`.
  - **The loop,** in ms: wait 700. For each click:
    1. Move the cursor (780).
    2. Show the press and apply the change.
    3. +240: the flash.
    4. +110: the next slot shows the same state, and its cover fades. `--k` goes up by one, and the pill reads `{time} · {n} frame(s)`.
    5. +560: the slot that left gets its ring and its caption.
    6. +620: the next click.

    After the third click: hold 1800, fade the track 400, and reset. One loop is 9830 ms.
  - **It pauses off screen.** An `IntersectionObserver` at threshold 0.35 holds the loop at its next step while the gate is hidden.
  - **Under reduced motion,** it draws the final state (three captioned slots, and the live slot with the toast and the pill at `0:04 · 3 frames`) and starts no timers.
  - The pill is never inside the track.

**Steps:**
- [ ] Write `gate.spec.js`, with `page.clock.install()` before `goto`, in all three browsers:
  - **The structure:** 10 slots, four corners, the pill, `.track .pill` absent, and the root `aria-hidden`.
  - **At load:** the pill reads `0:00 · 0 frames`, and no caption shows.
  - **At 2450 ms after load** (the times are all from load): slot 0 shows both caption lines exactly, and its ring. The pill reads `0:01 · 1 frame`, and `--k` is `1`.
  - **At 7700 ms:**
    - slots 0–2 show captions 1–3;
    - the pill reads `0:04 · 3 frames`;
    - slot 2's Acme shows the toast `Couldn’t save settings`.
  - **At 10000 ms,** after the loop: it's reset, with the pill at `0:00 · 0 frames` and no caption showing.
  - **Scrolled away:** `runFor(10000)` changes nothing, and scrolling back resumes it.
  - **Reduced motion:** the final state shows at load, and `runFor(20000)` changes nothing.
  - **Clean:** no console errors. The CSP would report inline styles here.
  - **At 320 px wide:** the gate's center is within 2 px of the viewport's.

  Run them and watch them fail.
- [ ] Implement, porting the mockup's logic (`heroLoop` in `page-v1.html`) onto `acme.js`, without inline styles.
- [ ] **Verify:** `make site-test`.
- [ ] Commit: `site: Through the gate`.

### Task 8: How it works

**Files:**
- Create: `site/assets/steps.js`.
- Modify: `site/index.html` (`section.how`, with an `h2` and three `figure.step`s, `#step-key`, `#step-click`, and `#step-drag`, each holding an empty `.canvas` and a static `figcaption.stepcap` with a `b` and a `span` in the exact copy), `site/assets/site.css`, `site/assets/site.js`.
- Test: `site/tests/pages/steps.spec.js`.

**Interfaces:**
- **Consumes:** `acmeWindow`, `setAcme`, `place`, `AT`, `CLICKS`, `START`, and `stateAfter` from `acme.js`.
- **Produces:** `export function initSteps(section, { reducedMotion }) → { stop() }`.
- **Each canvas** is 720 × 450 units, with font size `calc(var(--cw) / 720)` and `--cw: min(752px, calc(94vw - 68px))`. It's built by JavaScript and `aria-hidden`. It holds:
  - the desktop gradient;
  - `.menubar`, with `Acme File Edit View Window` on the left and, on the right, the mark (`<svg><use href="/assets/img/brand.svg#mark"/></svg>`) and `9:41`.

  `.menubar.rec` turns the mark's front reel red by setting `fill` on the `<use>`.
- **Step 1 (`#step-key`):** a keycap (glyph and word), its name and alternatives, and a pill.
  - **The loop:**
    1. Wait 650.
    2. Two taps, each 110 down and 120 up.
    3. +120: the pill shows (`0:00 · 0 frames · double-tap {glyph} to stop`), and the menu bar records.
    4. Two ticks, each +1000, update the pill's time.
    5. +700: two more taps, then the pill hides and recording stops.
    6. +1100: the next key, cycling ⌘, ⌥, fn.
- **Step 2 (`#step-click`):** the Acme window at (96, 52), scaled 2.65, plus three rings and chips in canvas units, a press, a cursor, the pill, and the card.
  - **For each click:**
    1. Move the cursor (760).
    2. Press and change.
    3. +160: the ring.
    4. +140: the chip, and the pill reads `{time} · {n} frame(s) · double-tap ⌘ to stop`.
    5. +650: the next click.
  - **After the third:**
    1. +700: the pill hides, and recording stops.
    2. +250: the rings and chips hide, and the card shows.
    3. +2300: the card hides.
    4. +600: the loop restarts.
  - The chips sit at the ring plus `[+24, +20]`, `[-236, -38]`, and `[-236, +26]`.
- **Step 3 (`#step-drag`):** a terminal at (318, 64), 368 × 268, with the card's home at (64, 214) and its drop point at (364, 150).
  - **The loop:**
    1. +700: the hand shows.
    2. +350: the card lifts (`scale(1.04) rotate(-2deg)`).
    3. +250: the drag starts, a 950 ms ease. At +500 into it, the input gets `.drop`.
    4. At +980: the card shrinks and fades, and `.drop` goes.
    5. Each `[Image #n]` chip appears 140 ms after the last.
    6. +250: the text types at 32 ms a character.
    7. Hold 2000, then reset.
- **Each figure** gets the `in` class (its fade-up) when it enters view, at threshold 0.35. It plays only while it's visible.
- **Under reduced motion,** each figure shows its final state, with no timers:
  - **Step 1:** the pill reads `0:02 · 0 frames · double-tap ⌘ to stop`, and the menu bar is recording.
  - **Step 2:** the rings and chips, and the card.
  - **Step 3:** the chips and all the text, with the card gone.

**Steps:**
- [ ] Write `steps.spec.js`, with `page.clock`:
  - **The captions:** the three figcaptions' exact text, with JavaScript on and off.
  - **Step 1:**
    - after the taps, the pill reads `… double-tap ⌘ to stop` and the menu bar has `rec`;
    - on the next loop, the keycap shows `⌥` and the pill `double-tap ⌥ to stop`;
    - on the third, `fn`.
  - **Step 2:**
    - after three clicks, the three chips' text is exact and the pill reads `0:04 · 3 frames · double-tap ⌘ to stop`;
    - then the card shows `3 frames · 0:04` and `Drag into a chat · click to review`.
  - **Step 3:** after the drop, the three chips show, and the typed text reads `dark mode doesn't stick after Save`.
  - **Off screen:** each figure pauses.
  - **Reduced motion:** the final states.
  - **Clean:** no console errors.

  Run them and watch them fail.
- [ ] Implement, porting `step1`, `step2`, and `step3` from `page-v1.html`.
- [ ] **Verify:** `make site-test`.
- [ ] Commit: `site: How it works, as three captioned frames`.

### Task 9: The privacy block and the final call

**Files:**
- Modify: `site/index.html`, `site/assets/site.css`, `site/assets/site.js` (Finder thumbnails).
- Test: `site/tests/pages/sections.spec.js`.

**Interfaces:**
- **Consumes:** `acmeWindow`, `setAcme`, and `stateAfter` from `acme.js`. `initLinkForm` comes from `linkform.js`, wired by `site.js` for every `form.linkform`.
- **The privacy block** (`section.privacy`):
  - static markup with the exact copy;
  - the Finder window as static HTML, with three empty `.tic` thumbnails. `site.js` fills them with `acmeWindow()` at `stateAfter(1)`, `stateAfter(2)`, and `stateAfter(3)`, with the font size `calc(30px / 196)`. Without JavaScript they stay plain grey;
  - the Quick Look panel's `<pre>`, with the exact text.
- **The final call** (`section.final`): the `h2`, the same call-to-action structure as the hero, with the form ids `email-final`, and the final note.

**Steps:**
- [ ] Write `sections.spec.js`:
  - the privacy copy and the Finder rows are exact;
  - the Quick Look text equals the block in Global Constraints;
  - with JavaScript, three thumbnails render;
  - **at 320 px,** the text sits above the Finder window, and **at 1440 px,** to its left (judged by bounding boxes);
  - the final call behaves like the hero: Download on a Mac, and the link form on an iPhone, which reaches the sent state with a mocked 200;
  - axe passes on both sections, in both themes.

  Run them and watch them fail.
- [ ] Implement.
- [ ] **Verify:** `make site-test`.
- [ ] Commit: `site: Nothing you record leaves your Mac, and the final call`.

### Task 10: The footer and the logo animation

**Files:**
- Create: `site/assets/logo.js`.
- Modify: `site/index.html` (the giant logo gets `data-animate`), `site/assets/site.css`, `site/assets/site.js`.
- Test: `site/tests/unit/logo.test.js`, `site/tests/pages/footer.spec.js`.

**Interfaces:**
- **Consumes:** `GEOMETRY`, `PATHS`, `FRONT_REEL`, and `LOGO_VIEWBOX` from `brand.js`.
- **Produces:**
  - `export function tripodPose(theta, g = GEOMETRY) → { leftLeg, rightLeg, brace: {x, y, width, height}, cameraOffsetY }`. The legs are four `[x, y]` points each, and `theta` is in radians:

```
MID = g.footSpan / 2        HALF = g.legThickness / 2        OPEN = g.splayDegrees · π / 180
LC = (MID − HALF / cos OPEN) / sin OPEN          // ≈ 113.04: a center line, foot to pivot
PIVOT_OPEN = −LC · cos OPEN                       // ≈ −101.6
ABOVE = g.legTop − PIVOT_OPEN                     // ≈ −10.4: the legs run past the pivot, inside the body
foot = MID − LC · sin θ        pivot = −LC · cos θ        top = pivot + ABOVE        w = HALF / cos θ
xAt(y) = foot + (−y) · tan θ
leftLeg  = [[xAt(0) − w, 0], [xAt(0) + w, 0], [xAt(top) + w, top], [xAt(top) − w, top]]
rightLeg = leftLeg with every x replaced by 2·MID − x
brace    = { x: xAt(g.crossbarY), width: max(0, 2·(MID − xAt(g.crossbarY))),
             y: g.crossbarY − g.braceThickness / 2, height: g.braceThickness }
cameraOffsetY = pivot − PIVOT_OPEN
```

  - `export function easeOutBack(x)`, with c1 = 1.55, and `export function easeInOutCubic(x)`.
  - `export function buildLogo(container) → SVGSVGElement`. It replaces the static `<use>` logo with a live SVG:
    - two leg `polygon`s and the brace `rect`;
    - a camera `g` (body, lens, and both reels from `PATHS`, in ink);
    - the sweep `circle` at `FRONT_REEL`, with `r = (outer + inner) / 2`, `stroke-width = outer − inner`, a dash array of its circumference, and `rotate(-90 cx cy)`;
    - the letters.

    The view box is `LOGO_VIEWBOX` with its top raised 13 units, `[-6, -245.68, 644.06, 253.11]`, so the closed pose's raised camera isn't cut off.
  - `export function playLogo(svg, { reducedMotion }) → { stop() }`:
    - θ = OPEN · `easeOutBack(clamp((ms − 250) / 950))`;
    - wind = `easeInOutCubic(clamp((ms − 1150) / 650))`;
    - it stops at 1900 ms.

    An `IntersectionObserver` at threshold 0.6 plays from closed on entry and resets to closed on exit. Under reduced motion, it's open and wound, with no observer.

**Steps:**
- [ ] Write `logo.test.js`:
  - **The open pose** (`tripodPose(OPEN)`):
    - its left leg's points equal `PATHS.leftLeg`'s, and its right leg's equal `PATHS.rightLeg`'s, within 0.01;
    - its brace is (29.48, −46.8, 62.04, 17.6), within 0.01;
    - `cameraOffsetY` is under 1e-9 in size.
  - **The closed pose** (`tripodPose(0)`):
    - the left leg equals the mirrored right leg;
    - its x runs 50.66 to 70.34 (within 0.02);
    - the brace's width is 0;
    - `cameraOffsetY` is −11.44 (within 0.05).
  - **The feet** stay on y = 0 for θ from 0° to 30°.
  - **The easing:** `easeOutBack`'s maximum on [0, 1] is over 1.05, and both easings map 0 to 0 and 1 to 1.
- [ ] Write `footer.spec.js`, with `page.clock`:
  - **Scrolled into view:**
    - at 40 ms the legs are closed (the two polygons are mirror images that overlap);
    - at 1250 ms they match the open pose;
    - at 1900 ms the sweep's `stroke-dashoffset` is 0.
  - **Scrolling away** resets to closed.
  - **Reduced motion:** open and wound at load.
  - **Without JavaScript:** the static `<use>` logo shows.
  - **The legal row:** its text and links are exact.
  - **Clean:** no console errors.

  Run them and watch them fail.
- [ ] Implement, porting `pose` and `play` from `footer.html`.
- [ ] **Verify:** `make site-test`.
- [ ] Commit: `site: the footer logo, its tripod opening into the A`.

### Task 11: The privacy policy, the Terms, the licenses, and the 404 page

**Files:**
- Create: `site/privacy.html`, `site/terms.html`, `site/licenses/sparkle.txt`.
- Modify: `site/404.html`, `site/assets/site.css` (prose styles).
- Test: `site/tests/pages/legal.spec.js`.

**Interfaces:**
- **Every page** has the frame from Task 3, with a static footer logo.
- **`sparkle.txt`** is Sparkle 2.10.0's `LICENSE`, byte for byte: from `.build/checkouts/Sparkle/LICENSE` if it's there, otherwise from `https://raw.githubusercontent.com/sparkle-project/Sparkle/2.10.0/LICENSE`.
- **`privacy.html`,** written in plain language from design §4.2:
  - `h1` `Privacy policy`, then `Last updated: <the session's date>`.
  - The `h2`s, in order: `The short version`, `The Annotake app`, `This website`, `The link email`, `Who else sees data`, `Your rights`, `Children`, `Changes`, `Contact`.
  - Each of these phrases appears verbatim:
    - `Nothing you record leaves your Mac`
    - `This website doesn’t use cookies`
    - `Vercel Web Analytics`
    - `Resend`
    - `30 days`
    - `GitHub`
    - `ImprovMX`
    - `United States`
    - `We never sell`
    - `before that version ships`
    - `Office of the Privacy Commissioner of Canada`
    - `Fayzan Malik`
    - `Ontario, Canada`
    - `hello@annotake.app`
- **`terms.html`,** from design §4.3:
  - `h1` `Terms`, then `Last updated: <date>`.
  - The `h2`s: `Who we are`, `The beta`, `Your license`, `Your recordings`, `No warranty`, `Limitation of liability`, `Trademarks`, `Open-source software`, `Ending`, `Governing law`, `Changes and contact`.
  - The phrases:
    - `free during the beta`
    - `as is`
    - `reverse-engineer`
    - `Claude Code, Cursor, ChatGPT, Mac, and macOS are trademarks of their owners`
    - `isn’t affiliated with or endorsed by them`
    - `Ontario`
  - Links to `/licenses/sparkle.txt` and `/licenses/jost-ofl.txt`.
- **`404.html`:** the frame, `This page doesn’t exist.`, and `Go to annotake.app` linking `/`.

**Steps:**
- [ ] Write `legal.spec.js`:
  - both pages answer 200, with their titles, their `h2`s in order, and every phrase;
  - **the licenses:** `/licenses/sparkle.txt` is `text/plain` and contains `Andy Matuschak` and `bsdiff`, and `/licenses/jost-ofl.txt` contains `SIL OPEN FONT LICENSE`;
  - `/nope` answers 404 with the 404 copy and a link to `/`;
  - axe passes on all three pages, in both themes.

  Run them and watch them fail.
- [ ] Write the pages and copy the license.
- [ ] **Verify:** `make site-test`.
- [ ] Commit: `site: the privacy policy, the Terms, and the licenses`.

### Task 12: Search, sharing, and the preview image (Glue for the image)

**Files:**
- Create: `site/robots.txt`, `site/sitemap.xml`, `site/tests/tools/og.html`, `site/tests/tools/make-og.mjs`, `site/assets/img/og.v1.png` (generated).
- Modify: the `<head>` of every page, and `Makefile` (`site-og`).
- Test: `site/tests/pages/seo.spec.js`.

**Interfaces:**
- **The home page's `<head>`:**
  - the title and the meta description;
  - `<link rel="canonical" href="https://annotake.app/">`;
  - `og:type` `website`, `og:url` `https://annotake.app/`, `og:title`, `og:description`, `og:image` `https://annotake.app/assets/img/og.v1.png`, `og:image:width` 1200, and `og:image:height` 630;
  - `twitter:card` `summary_large_image`;
  - the icons: `favicon.svg` (`type="image/svg+xml"`), `favicon-32.png` (`sizes="32x32"`), and `apple-touch-icon.png`;
  - a JSON-LD data block: `{"@context":"https://schema.org","@type":"SoftwareApplication","name":"Annotake","operatingSystem":"macOS 15 or later","applicationCategory":"DeveloperApplication","description":<the meta description>,"url":"https://annotake.app","downloadUrl":"https://annotake.app/download","offers":{"@type":"Offer","price":"0","priceCurrency":"USD"},"author":{"@type":"Person","name":"Fayzan Malik"}}`.
- **`/privacy` and `/terms`** get their own title (`Privacy policy · Annotake` and `Terms · Annotake`), a description, a canonical, and the icons.
- **`robots.txt`:** `User-agent: *`, `Allow: /`, and `Sitemap: https://annotake.app/sitemap.xml`. **`sitemap.xml`** lists `/`, `/privacy`, and `/terms`.
- **`og.html`** is 1200 × 630, light, using `site.css`:
  - the logo at the top left;
  - the headline on two lines;
  - a still gate strip across the bottom, from `initGate(root, { reducedMotion: true })`.

  **`make-og.mjs`** starts the local server, opens `/`, and then swaps in `og.html`'s markup with `page.setContent`, because the server refuses `/tests/` paths. The page keeps its origin, so `/assets/…` URLs resolve. It waits for the font and the gate, then renders in Chrome at device scale 1 and writes `og.v1.png`. **`make site-og`** runs it.

**Steps:**
- [ ] Write `seo.spec.js`:
  - every tag and value is exact;
  - the JSON-LD parses with the fields above;
  - `og.v1.png` is 1200 × 630 (from its IHDR chunk) and at most 300 KB;
  - `robots.txt` and `sitemap.xml` match;
  - every icon link answers 200 with the right type.

  Run them and watch them fail.
- [ ] Add the tags and files. Run `make site-og`, and look at the PNG: the headline is readable and the strip shows three captioned frames.
- [ ] **Verify:** `make site-test`.
- [ ] Commit: `site: search, sharing, and the preview image`.

### Task 13: Whole-page checks

**Files:**
- Test: `site/tests/pages/whole.spec.js`.
- Modify: whatever the checks find.

**Steps:**
- [ ] Write `whole.spec.js`. **In all three browsers, light and dark,** on `/`, `/privacy`, `/terms`, and the 404:
  - no console errors and no CSP reports;
  - axe finds nothing serious or critical;
  - no `Set-Cookie` on any response, and `context.cookies()` stays empty after the toggle and a mocked form send;
  - every request goes to the page's own origin;
  - no sideways scrolling at 320, 360, 768, 1280, 1440, and 2560 px;
  - **the keyboard:** from the top, Tab reaches the logo link, the toggle, the header's download, the hero's download (on a Mac) or summary (on an iPhone), and the final call. Each focused element shows an outline at least 2 px wide.
- [ ] **Chrome only:**
  - **The byte budget:** the first load's transferred bytes (from `request.sizes()`, leaving out `/_vercel/insights/*`) total at most 204,800, and the font file at most 30 KB.
  - **Reduced motion:** after load, `page.clock.runFor(30000)` causes no DOM mutations in the gate, the steps, or the footer logo (a `MutationObserver` counts zero).
  - **Without JavaScript:** the page renders, the download link and the details form are there, and the form's post returns the HTML page.
- [ ] Run, fix what it finds, and run again until it passes.
- [ ] **Verify:**
  - `make test`, `make site-test`, and `make site-brand-check` pass;
  - `grep -rnE 'fonts\.googleapis|style="' site/*.html site/assets` prints nothing. The email's HTML in `site/api/` is allowed inline styles.
- [ ] Commit: `site: whole-page checks for privacy, accessibility, layout, and weight`.

### Task 14: The checkpoint tools (Glue)

**Files:**
- Create: `site/tests/tools/smoke.mjs`, `site/tests/tools/burst.mjs`.
- Test: `site/tests/unit/tools.test.js`.
- Modify: `Makefile` (`site-smoke URL=…`, `site-burst URL=…`).

**Interfaces:**
- **Both scripts** export their checks as functions and run `main()` only when invoked directly. Each prints `PASS` or `FAIL` per check, and exits 1 if anything fails.
- **`smoke.mjs <baseURL>`** checks:
  1. `/`, `/privacy`, and `/terms` answer 200 `text/html`, with the exact CSP and the five headers, and no `Set-Cookie` (`checkHeaders(headers) → string[]` of problems).
  2. `/download` answers 302 to the GitHub URL. Following it ends at 200, with `Content-Type` `application/x-apple-diskimage` or `application/octet-stream`, and a `Content-Length` over 1 MB.
  3. `GET /api/link` answers 405.
  4. The font's `Cache-Control` contains `immutable`.
  5. `/nope` answers 404.
  6. `/_vercel/insights/script.js` answers 200, which shows Web Analytics is on.
  7. Only when the base is `https://annotake.app`: `https://www.annotake.app/` and `https://annotake.com/` both end at `https://annotake.app/`.
- **`burst.mjs <baseURL> [count=50]`** sends `count` POSTs to `/api/link`, in waves of 10, with JSON `{email: 'burst@example.com', website: 'bot', t: 5000}`. The honeypot means no email is ever sent.
  - It prints each status code's count.
  - `evaluateBurst(counts, count)` passes when at least `count − 10` of them are 429 and none is 5xx.

**Steps:**
- [ ] Write `tools.test.js` for `checkHeaders` (good headers; a missing header; a cookie) and `evaluateBurst` (all 429 after 10 passes; only 200s fails; any 5xx fails). Run `make site-unit` and watch it fail.
- [ ] Implement both scripts and the Make targets.
- [ ] Run `make site-smoke URL=http://localhost:4173` against `make site-dev`. Checks 2 and 7 are expected to stop at the redirect locally: the script follows redirects only for `https` bases, and reports that as `SKIP`.
- [ ] **Verify:** `make site-test`.
- [ ] Commit: `site: smoke and burst tools for the checkpoint`.

### Task 15: Docs, the session notes, and Checkpoint 4

**Files:**
- Create: `site/README.md`: how to run (`make site-dev`), test, regenerate (`make site-brand`, `make site-og`), and deploy (the Vercel settings from Checkpoint 4).
- Modify: `docs/plans/2026-10-01-landing-page-design.md`, `docs/plans/README.md`, `docs/checkpoints.md`.

**Steps:**
- [ ] **In the design doc:**
  - Add the planning changes 1–14 above as "Changes from planning", plus any session decisions.
  - Fix §5.3: 4 s per attempt, and the too-fast check at 1 s.
  - Fix §5.6: drop `upgrade-insecure-requests`.
  - Fix §3.5: the Quick Look's "(from 3 candidates)".
  - Fix §6: Resend's 10-a-second API limit, which Resend raises on request.
- [ ] **In the session guide:** fill in Session 10's notes, as for Session 8. List the **Decisions** and **Skipped** items, then **For later plans**: test counts and run time, anything the next site or app session should know, and the app-side follow-ups from design §9.
- [ ] **In `docs/checkpoints.md`:** add `## Checkpoint 4 (the site)` with the list below, as steps for Fayzan to fill in.
- [ ] **Final checks:** `make test`, `make site-test`, and `make site-brand-check` all pass, and `git status` is clean.
- [ ] Commit: `docs: Session 10 done; Checkpoint 4 next`. Then push `main`.
- [ ] **End the session** by giving Fayzan the Decisions and Skipped lists first, then the Checkpoint 4 list:
  1. **Resend:** create the account and add `annotake.app`. Add its DNS records in Vercel (or have a session run `npx vercel dns add …` under your login), then verify the domain.
  2. **ImprovMX:** create the account and add `annotake.app`. Add its MX records (and anything else it lists) in Vercel. Make `hello@` and `feedback@` forward to your Gmail, and check that a test email to `hello@annotake.app` arrives.
  3. **DMARC:** add `_dmarc` TXT `v=DMARC1; p=none; rua=mailto:hello@annotake.app`.
  4. **Vercel:**
     - create a project from `fayzan123/annotake`, with Root Directory `site` and Framework Preset Other;
     - add the environment variables `RESEND_API_KEY` (Production) and `EMAIL_DRY_RUN=1` (Preview);
     - turn on Web Analytics;
     - add `annotake.app` and `www.annotake.app`.
  5. **annotake.com:** register it in Vercel, and add it and `www` as redirects to `https://annotake.app`.
  6. **The firewall:** add a rule for when the request path is `/api/link` and the method is `POST`: Rate Limit, Fixed Window, 10 requests per 600 s, keyed by IP, answering 429. Then publish it.
  7. **The first deploy:** run `make site-smoke URL=https://annotake.app` and `make site-burst URL=https://annotake.app`. The burst sends no email.
  8. **On your iPhone:** use Email me the link with your own address. The email arrives (outside spam), and a reply reaches your Gmail. Open the link on a Mac, and the DMG downloads.
  9. **The look:** on your iPhone and both Macs, in light and dark, check how the hero, the steps, and the footer look and move.
  10. **PageSpeed Insights on mobile:** performance at least 95, accessibility 100.
  11. **The policies:** read the privacy policy and the Terms, and approve them or ask for changes.
  12. **Optional:** an uptime monitor on `/` and `/download`.
  13. **Before the first public post:** move to Vercel Pro.
