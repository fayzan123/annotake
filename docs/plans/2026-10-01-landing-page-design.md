# Annotake landing page design: annotake.app

**Status:** approved 2026-10-01, in Session 9 · **Plan:** next, with `superpowers:writing-plans` · **Related:** [distribution design](2026-09-30-distribution-design.md) §6 (Stage 2), §8 (privacy), §9 (risks)

Worked out with the brainstorming companion. The mockups (`visual-style`, `graphic`, `hero-steps`, `page-v1`, `footer`) are kept in the git-ignored `.superpowers/brainstorm/32148-1790882887/content/`; this doc is the record. The page is pulled ahead of the rest of Stage 2, as a side project while the friends round runs. Sign-in, the daily counts, and the founding-member checkout keep their own design session.

## 1. Goal

- **What it is:** one page at annotake.app, plus `/privacy` and `/terms`, and one small email function.
- **Its job:** a developer arrives from a community post, understands Annotake in a few seconds, and downloads it. Strangers should find it credible.
- **Done means:**
  - annotake.app serves the page, the policies, the download, and the link email;
  - every automated test passes;
  - Fayzan has read and accepted the privacy policy and the Terms;
  - the first public post can go out.
- **Principles:**
  - **As simple as the product.** One idea per section. No section the visitor doesn't need.
  - **Ease of use first.** One click to the disk image. No login, no waitlist.
  - **The site keeps the app's promise.** No cookies, no trackers, no third-party scripts, and no stored email addresses.
  - **Robust at any traffic.** Every part keeps working under load, and degrades instead of breaking when something fails (§6).
  - **Inspired by Wispr Flow, not a copy.** Big type, few words, one button, one picture that shows the transformation, an animated footer logo. Their look (a serif on cream) and their squiggle were tried and dropped.

## 2. Decisions

| Decision | Why |
|---|---|
| A download, not a waitlist | The notarized disk image removed the reason for invites (a stranger shouldn't paste a Terminal command). A waitlist loses people between sign-up and invite, and gates nothing: `Annotake.dmg` is already public. The beta's numbers come from Stage 2's sign-in, which reaches every copy through Sparkle, and Fayzan sets the pace by when and where he posts |
| No login on the site, now or later | Annotake works without an account. Wispr's button opens a sign-up because Flow needs one first. In Stage 2, sign-in goes in the app's first run, in the slot after the welcome |
| Light and dark, following the visitor's setting, with a toggle | Fayzan picked both looks (mockup B and C) |
| Jost, charcoal, grey, and the click-marker red | The logo's own type and colors. The serif-on-cream look read as a copy of Wispr |
| The hero picture is "Through the gate" | It's Annotake's own: film running through a camera, and it acts out the name (a frame is taken, then annotated). The first idea, a squiggle into the pill, was too close to Wispr's |
| How it works is a vertical strip of three captioned frames | It uses the app's first-run words and its caption format, so the explanation looks like an Annotake recording of itself. Each step plays as it scrolls into view; the page isn't pinned |
| No trigger key in the hero; step 1 cycles ⌘, ⌥, fn | Right ⌘ is only the default. The app offers three keys, so the page never says "any key" |
| The footer logo animates: the tripod opens into the A | Fayzan's idea. Wispr's footer logo moves too; this one is ours |
| Phones and other computers get "Email me the link", with no news tick box | A requested email is exempt from CASL's consent rules. A news list would need a mailing address on the form and in every email. News consent can come through Stage 2's sign-in |
| Plain HTML, CSS, and JavaScript in `site/`, with one Vercel function | The mockups become the code. No framework, no build step, no runtime packages. Sessions keep this repo's memory and docs. Revisit (Astro, say) when Stage 3 adds pricing, a changelog, and an FAQ |
| Resend sends the link email; ImprovMX forwards `hello@` and `feedback@` | Their free plans fit the beta, and both upgrade without code changes |
| Vercel Web Analytics | Cookieless, so there's no banner. Referrers show which post brought people |
| No cookies, self-hosted fonts, no third-party scripts | No cookie banner is needed, and a strict content security policy (CSP) is possible |
| A privacy policy and Terms on the site, with Terms linked under every download button | Fayzan wants every legal base covered. PIPEDA expects an open policy, and Terms limit liability for free beta software |
| Register annotake.com and point it at annotake.app; skip annotake.dev and anotake.app | It catches people who type .com and protects the name, for about US$12 a year |
| Vercel Hobby now, Pro before the first public post | Hobby is non-commercial only and can pause a project that passes its limits |

## 3. The page, top to bottom

### 3.1 Header

- The logo (40 px tall) on the left, linking to `/`.
- On the right: the theme toggle (a sun or moon in a 40 px circle) and, on a Mac only, a small "Download for Mac" button. Elsewhere the header holds just the logo and the toggle, because the hero's button is right below.

### 3.2 Hero

- **Headline,** on two lines, the second in grey (`--head-2`): **Show your coding agent / exactly what happened.**
- **Line under it:** "Press a key, do the thing in any app, and drag the card into Claude Code, Cursor, or ChatGPT. Each step comes out as a screenshot, captioned with what you clicked." Phones show only the first sentence.
- **On a Mac:** a "Download for Mac" button (a download-arrow icon, never the Apple logo) linking to `/download`.
  - Under it: "Free during the beta · macOS 15 or later", then "By downloading, you agree to the Terms."
  - After a click, the button reads "Downloading…" for 2 s, and a line appears: "Open Annotake.dmg, then drag Annotake to Applications."
- **Anywhere else:** "Email me the link" (§3.8).

### 3.3 Through the gate (the hero picture)

- **The strip:** film runs across the full width under the hero text, with sprocket holes along the top and bottom.
  - Frames are 196 × 104 units with a 28-unit caption strip. One frame is `clamp(180px, 19.5vw, 280px)` wide, and everything inside scales with it.
  - The gate is centered, marked with white viewfinder corners. The live frame sits in it, with the recording pill over it.
- **What it shows:** a made-up app, "Acme Settings", drawn in HTML and CSS. It stays sharp at any size and works in both themes. The real captures in `~/Pictures/Annotake` can't be used: they show private tab titles, file names, the `.signing` folder, and the old Flipbook name.
- **The loop,** about 10 s:
  - Three clicks: the "Appearance" tab, the "Dark mode" switch, then the "Save" button, which brings up a red "Couldn't save settings" toast.
  - **Each click:**
    1. The cursor moves (0.78 s).
    2. A press ripple shows and the screen changes.
    3. A white shutter flash peaks at 40% (0.22 s).
    4. The strip advances one frame (0.65 s, ease in and out).
    5. The frame leaving the gate gets its red click ring and caption: `1/3 · 0:01 · Clicked tab "Appearance"`, `2/3 · 0:02 · Clicked switch "Dark mode"`, `3/3 · 0:04 · Clicked button "Save"`, with `Acme — Settings` underneath.
  - The pill counts: "0:00 · 0 frames", "0:01 · 1 frame", up to "0:04 · 3 frames".
  - The pill stays with the live screen and never appears in a finished frame, just as Annotake keeps its own windows out of recordings.
  - After the third frame: a 1.8 s hold, a fade, and a restart.
- **Unexposed film,** dark grey, fills the slots to the right, and to the left before the first frame.
- **Motion rules:**
  - The loop pauses when it's off screen.
  - With Reduce Motion on, the strip is a still: three finished frames and the live one.
  - It's decorative (`aria-hidden`); the hero text carries the meaning.

### 3.4 How it works

- **Heading:** "How it works".
- **The film:** a vertical strip, at most 752 px of picture plus sprocket edges, holding three frames.
  - Each frame is a 720 × 450-unit desktop: a soft grey gradient, and a menu bar with Acme's menus, the Annotake mark, and 9:41.
  - Under each frame is a caption strip in the app's style: line 1 bold white, line 2 grey.
  1. **`1/3 · Double-tap your key`** / "Right ⌘ out of the box, or Right ⌥ or fn. Double-tap again when you're done."
     - A large keycap presses twice, the pill rises ("0:00 · 0 frames · double-tap ⌘ to stop"), and the menu-bar mark's front reel turns red.
     - The timer ticks twice, then a second double-tap ends the recording.
     - The keycap cycles ⌘, ⌥, fn on each loop, with its name underneath ("Right ⌘ / or Right ⌥, or fn"), and the pill's key follows.
  2. **`2/3 · Click through it`** / "Each step comes out as a screenshot, captioned with what you clicked."
     - Three clicks in Acme. Each leaves a red ring and a caption chip ("1/3 Clicked tab "Appearance"", and so on) while the pill counts frames.
     - Then the recording stops, and the card appears: "3 frames · 0:04", "Drag into a chat · click to review".
  3. **`3/3 · Drag the card into your agent`** / "Claude Code, Cursor, ChatGPT, or anything else that takes images."
     - A hand grabs the card and drags it into a Claude Code prompt, in a terminal titled "acme — claude".
     - The prompt's box outlines in dashed red while the card hovers over it.
     - On the drop, `[Image #1] [Image #2] [Image #3]` appear, and "dark mode doesn't stick after Save" types in.
- **Motion rules:**
  - Each frame fades up as it enters the view and loops only while it's visible.
  - With Reduce Motion on, each frame shows its final state.

### 3.5 Privacy

- **Heading,** on two lines, the second in grey: **Nothing you record / leaves your Mac.**
- **Three rows,** each a label and one sentence, with thin rules between them:
  - **Plain files:** "Each recording is a folder of PNGs and a `steps.md` in `~/Pictures/Annotake`. They clear out after 30 days unless you choose to keep them."
  - **No AI:** "Frames are picked by comparing pixels, and captions come from macOS Accessibility. No models, no uploads."
  - **Only while you record:** "Annotake sees your screen only while you record, and it never records what you type."
- **Beside them, a Finder window:**
  - A recording folder holding `01_0m01s.png`, `02_0m02s.png`, `03_0m04s.png` (with thumbnails) and `steps.md`.
  - The path bar: Macintosh HD › Users › you › Pictures › Annotake › 2026-10-01 at 09.41.12.
  - A Quick Look panel of `steps.md` overlaps the window's lower corner, in its real format:

```
# Annotake capture — 2026-10-01 at 09.41.12
Screen: Built-in Retina Display · 0:04 · 3 frames

1. 0:01 · Acme — Settings · Clicked tab "Appearance"
2. 0:02 · Acme — Settings · Clicked switch "Dark mode"
3. 0:04 · Acme — Settings · Clicked button "Save"
```

- On narrow screens, the text stacks above the Finder window.

### 3.6 Final call

- **Heading:** "Try it on your next bug."
- **The button** behaves as in the hero.
- **The note:** "Free during the beta · macOS 15 or later · Apple silicon and Intel", then "By downloading, you agree to the Terms."

### 3.7 Footer and the logo animation

- **The full logo** spans the content width, up to 1200 px. Its shapes come from `BrandMark.swift` and `Wordmark.swift` (§5.1).
- **The animation** starts when the logo is 60% in view:
  - **Closed:** the two legs sit together as one stem under the camera, so the word reads as a camera on a pole beside "nnotake". The camera rides higher, by the closed legs' extra height (about 11 logo units). There's no brace, and the front reel is in ink.
  - **0.25–1.2 s:** the legs swing open to 26° with a slight overshoot (ease-out-back), so the A forms. The brace grows with them, and the camera settles with a small bounce.
  - **1.15–1.8 s:** the front reel winds red, clockwise from 12 o'clock. It's the same red the menu-bar icon turns while recording.
  - It replays whenever the logo returns to view. With Reduce Motion on, it's shown open.
- **The geometry,** derived from the brand numbers:
  - Each leg pivots where the two legs' center lines meet, at (60.5, −101.6), which is hidden inside the camera body.
  - The center line runs 113.0 units from foot to pivot, and the feet stay on the baseline.
  - The open pose matches the brand SVG exactly.
- **Under the logo:** "© 2026 Fayzan Malik · Made in Ontario, Canada", with links to Privacy, Terms, and `hello@annotake.app`.

### 3.8 Phones and other computers

- **What counts as a Mac:** the browser reports a Mac platform and `navigator.maxTouchPoints < 2`. iPads report themselves as Macs, and this rule catches them. Everything else gets the link flow.
- **The button** reads "Email me the link", with "Annotake is a Mac app. Get the link in your inbox and download it there."
- **The form** is a native `<details>` element, so it opens even without JavaScript. Inside:
  - one email field and a "Send link" button;
  - the line "We'll send one email with the download link, and that's all." with a link to the privacy policy.
- **Sent:** "✓ Check your inbox", then "We sent the link to {email}. Open it on your Mac.", then "Wrong address? Try again".
- **If sending fails** (the daily cap, the rate limit, Resend down, or the network): "We couldn't send it right now. Here's the link:" with `annotake.app/download`, a Copy button, and a Share button. Share uses `navigator.share` where the browser has it; on a phone it opens AirDrop and Messages.
- **A bad address** gets an inline message, and the form stays open.

### 3.9 Colors and type

| Token | Light | Dark |
|---|---|---|
| `--bg` | `#FFFFFF` | `#141416`, with a soft glow behind the hero (`rgba(255,255,255,.07)`) |
| `--ink` | `#1C1C1E` | `#F5F5F7` |
| `--ink-2` (body copy) | `#515154` | `#AEAEB2` |
| `--ink-3` (notes) | `#6E6E73` | `#8E8E93` |
| `--head-2` (grey headline line) | `#8E8E93` | `#8E8E93` |
| `--line`, `--line-2` | `#E5E5EA`, `#D1D1D6` | `#2C2C2E`, `#3A3A3C` |
| `--film`, `--hole`, `--blank` | `#1C1C1E`, `#FFFFFF`, `#262628` | `#2A2A2D`, `#141416`, `#3A3A3D` |
| `--red` | `#FF3B30` | `#FF3B30` |

- **Buttons:** charcoal with white text in light; white with charcoal text in dark.
- **Contrast:** text has at least 4.5:1, and large text at least 3:1. The grey headline line on white is 3.26:1, which is why it's `#8E8E93` and not the lighter `#A1A1A6` the first mockup used.
- **Type:**
  - Jost 400, 500, and 600, self-hosted as Latin-subset `woff2` files under the SIL Open Font License.
  - **Sizes:** the headline is `clamp(44px, 6.1vw, 88px)`, with line height 1.02 and letter spacing −0.035em. Section headings are `clamp(34px, 4.2vw, 56px)`, and body text is 17–20 px.
  - The app's own UI (the pill, captions, Finder, the terminal) uses `system-ui` and `ui-monospace`, as on a real Mac.
- **The theme:**
  - The visitor's `prefers-color-scheme` sets it. The toggle overrides it, and the choice is kept in `localStorage`.
  - A small blocking script in `<head>` sets it before the first paint, so the page never flashes the wrong theme.

### 3.10 Motion, accessibility, and fallbacks

- **Motion:** animations move only `transform` and `opacity`, and pause off screen. Under `prefers-reduced-motion`, everything shows its final state.
- **Screen readers:** decorative pictures are `aria-hidden`, and every meaning is also in text (captions and step text are real text).
- **Keyboard and labels:** focus rings stay visible, the toggle is a labeled button, and the email field has a label.
- **Without JavaScript:** the download is a plain link, and the `<details>` form posts straight to `/api/link`, which answers with a small HTML page.
- **Layout:** works from 360 px wide, and at 200% zoom without sideways scrolling.
- **Browsers:** the last two versions of Safari, Chrome, Firefox, and Edge, and iOS Safari 16 and later.

## 4. Legal and privacy

Not legal advice. This covers the usual ground for free beta software. Before Stage 3 takes money, a lawyer should read the Terms once.

### 4.1 Cookies and tracking

- **The site sets no cookies,** and none of these are used:
  - analytics cookies: Vercel Web Analytics is cookieless;
  - third-party scripts or embeds: when the video exists, it'll be a self-hosted file, not YouTube;
  - Google Fonts: Jost is served from annotake.app.
- **The light/dark choice** stays in the visitor's `localStorage`. It's a setting the visitor asked for, so EU rules don't require consent for it, and it never leaves the browser.
- **So there's no cookie banner,** in Canada or the EU.
- **Tests check it:** no `Set-Cookie` header on any response, and an empty `document.cookie` after every interaction.

### 4.2 The privacy policy (`/privacy`)

Plain language. It opens with a "Last updated" date, and old versions stay in git.

1. **Who:** Annotake is made by Fayzan Malik, an individual in Ontario, Canada, who is the person responsible for privacy. The contact is `hello@annotake.app`.
2. **The short version:** nothing you record leaves your Mac. The site uses no cookies. We get your email only if you ask for the link, and only to send it.
3. **The app:**
   - **What stays on your Mac:** frames, captions, `steps.md`, window titles, button names, keys, and file paths. They're saved in `~/Pictures/Annotake` and cleared after 30 days by default.
   - **The three permissions,** and why each is needed. They're used only on the Mac.
   - **What goes over the network:** a daily update check, which sends the app's version to GitHub, and the update downloads. GitHub sees your IP address, as with any download.
   - **Send Feedback:** it opens a draft in your mail app with the app and macOS versions, the permission states, the recent log, and the latest crash report. You see it and choose whether to send it. The log never holds button names, window titles, or keys.
   - **Coming later:** Stage 2 adds sign-in and daily counts. This policy is updated before that version ships, and the app asks before anything new is sent.
4. **The website:**
   - **Hosting:** Vercel. Like any host, it processes IP addresses and browser details to deliver pages and stop abuse.
   - **Analytics:** Vercel Web Analytics counts visits and referrers without cookies, and doesn't identify you.
   - **Downloads** come from GitHub (`fayzan123/annotake-releases`), under GitHub's privacy statement.
5. **The link email:** your address is used to send that one email through Resend. We keep no list. Resend keeps its sending logs for 30 days.
6. **Who else sees data:** only the services above: Vercel, Resend, GitHub, and ImprovMX, which forwards email sent to `hello@` and `feedback@`. They're in the US. Nothing is sold.
7. **Your rights:**
   - To see, correct, or delete your data: email us.
   - Complaints go to the Office of the Privacy Commissioner of Canada.
   - EU and UK visitors also have GDPR rights. The legal basis is your request for the link, and legitimate interest for site security.
8. **Children:** the site isn't for children under 13, or under 16 in the EU.
9. **Changes:** the date at the top changes, and big changes are noted on the site.

### 4.3 The Terms (`/terms`)

1. **Who:** Fayzan Malik, Ontario, Canada. The Terms cover annotake.app and the Annotake app.
2. **The beta:** free while it lasts. Features may change. Paid plans may come later, but nothing you use becomes paid without notice and your agreement.
3. **The license:** use it for personal and work use. Don't reverse-engineer, redistribute, or resell it. Annotake stays Fayzan's.
4. **Your recordings are yours,** and so is what you record and share: follow your employer's rules and other people's privacy.
5. **No warranty:** provided as is, and beta software has bugs.
6. **Limited liability,** as far as the law allows. Liability is capped at what you paid in the past 12 months, which in the beta is nothing.
7. **Trademarks:** "Claude Code, Cursor, ChatGPT, Mac, and macOS are trademarks of their owners. Annotake isn't affiliated with or endorsed by them."
8. **Open source:** Sparkle's MIT license notice, and the SIL Open Font License for Jost.
9. **Ending:** you can stop at any time by deleting the app. The beta can end.
10. **The law:** Ontario's, and Canada's federal laws.
11. **Changes and contact.**

### 4.4 CASL

- **The link email doesn't need a consent box.** CASL's regulations exempt a message "sent in response to a request, inquiry or complaint or is otherwise solicited by the person to whom the message is sent" ([SOR/2013-221, s. 3(b)](https://laws-lois.justice.gc.ca/eng/regulations/SOR-2013-221/FullText.html)).
  - It still names the sender and gives a contact, and it says it's the only email.
  - That exemption doesn't cover later messages, so no list is kept.
- **A news list, if one comes in Stage 2 or later, needs all of this:**
  - an unticked box;
  - the sender's name, a mailing address, and a contact on the form, plus a statement that consent can be withdrawn;
  - in every message: the name, the mailing address, a contact, and an unsubscribe link that works for 60 days and is honoured within 10 business days;
  - a record of each consent.
- **The mailing address** would be a PO box or a virtual mailbox, not Fayzan's home.

### 4.5 Whose name is on it

- **The maker is Fayzan Malik** in the Terms, the policy, the emails, and the footer, and "Annotake" stays a product name. That needs no Ontario business-name registration.
- **Trading under "Annotake" itself,** on invoices, say, would need that registration (about CA$60 through the Ontario Business Registry) or a company.

### 4.6 Outside the site

- **The app ships Sparkle without its MIT license notice.** Add the notice to the app bundle in the next app release. The site's Terms lists it too.
- **Still open from the distribution design:**
  - the employment contract and IT rules;
  - the USPTO and Canadian trademark searches for "Annotake".

  Both are bigger risks than anything on the site.
- **A lawyer reads the Terms before Stage 3 takes money.**

## 5. Architecture

### 5.1 Files

```
site/
  index.html, privacy.html, terms.html, 404.html, robots.txt, sitemap.xml
  vercel.json
  api/link.js                 the email function (Node, no packages)
  assets/
    site.css
    theme.js                  sets the theme before the first paint (in <head>)
    site.js                   the toggle, the Mac check, the link form
    gate.js, steps.js, logo.js  the three animations
    brand.js                  generated: the mark's and wordmark's paths and numbers
    acme.js                   the drawn Acme window, shared by the animations
    fonts/jost-{400,500,600}.v1.woff2, fonts/OFL.txt
    img/og.v1.png, favicon.svg, favicon-32.png, apple-touch-icon.png
  tests/                      Playwright page tests and node:test function tests
  package.json                dev dependencies only (@playwright/test, @axe-core/playwright)
scripts/make-site-brand.swift  writes site/assets/brand.js and favicon.svg from BrandMark.swift and Wordmark.swift
```

- **The brand comes from one source.** `BrandMark.swift` and `Wordmark.swift` stay the only source of the logo. `scripts/make-site-brand.swift` compiles them, the same way `make-icon.swift` does, and writes SVG path data and the leg numbers into `brand.js`.
  - A test fails if the committed file is out of date.
  - `make site-brand` regenerates it.
- **Make targets:** `make site-dev` serves the site locally, with a stub for `/api/link`, and `make site-test` runs every site test.
- **CSP rules for the code:** no inline scripts, and no `style="…"` attributes in markup, because both are blocked by the CSP. Code sets positions through `element.style` instead.

### 5.2 Routes (`vercel.json`)

- **URLs:** `cleanUrls: true` and `trailingSlash: false`, so the pages are `/privacy` and `/terms`.
- **`/download`** redirects (302) to `https://github.com/fayzan123/annotake-releases/releases/latest/download/Annotake.dmg`. That asset name is fixed by `make release`.
  - The redirect runs at Vercel's edge, with no function.
  - If hosting moves, only this line changes.
- **Domains:** `www.annotake.app`, `annotake.com`, and `www.annotake.com` redirect (308) to `https://annotake.app`, set in Vercel's domain settings.
- **Caching:** `/assets/fonts/*` and `/assets/img/*` are served `public, max-age=31536000, immutable`. Their names carry a version (`.v1`), which changes whenever the file does. Everything else uses Vercel's default, which re-checks on each visit.
- **The function:** `api/link.js`, with a 10 s maximum duration.
- **Vercel project:** the root directory is `site`. The "Ignored Build Step" is `git diff --quiet HEAD^ HEAD -- .`, so commits to the app don't redeploy the site.

### 5.3 The link function

- **Request:**
  - `POST /api/link`, as JSON from the page, or form-encoded from the no-JavaScript form.
  - Fields: `email`, the hidden `website` field (a honeypot), and `t`, the milliseconds since the page loaded.
- **Checks:**
  - The email is trimmed and at most 254 characters, with no line breaks, and matches a plain address pattern.
  - A filled honeypot, or a `t` under 1,500 ms, gets a silent success with no send, so bots learn nothing. The no-JavaScript form sends no `t`, so it skips that check.
- **Send,** through Resend's HTTP API (`POST https://api.resend.com/emails`) with `fetch`:
  - the key comes from the `RESEND_API_KEY` environment variable;
  - `Idempotency-Key: sha256(lowercased email + UTC date)`, so an address gets at most one email a day, and a retry can never send twice;
  - a 5 s timeout;
  - one retry, 300 ms later, after a network error or a 5xx; none after a 4xx.
- **Replies:**

| Status | Body | When |
|---|---|---|
| 200 | `{ok: true}` | Sent, or quietly ignored as a bot |
| 400 | `{ok: false, reason: "invalid"}` | Not an email address |
| 429 | `{ok: false, reason: "busy"}` | The rate limit, or Resend's limit |
| 502 | `{ok: false, reason: "send"}` | Resend failed, or timed out twice |

  - The page shows the Copy and Share fallback for anything but 200.
  - A form-encoded request gets a small HTML page instead: "Check your inbox", or the fallback link.
- **Logs:** the outcome and Resend's status only, never the address.
- **Preview deployments** set `EMAIL_DRY_RUN=1`: the checks run but nothing is sent. Tests and the burst test (§7) use it. `RESEND_API_KEY` exists only in Production.

### 5.4 The email

- **From:** `Annotake <hello@annotake.app>`, with replies to `hello@annotake.app`, which forwards to Fayzan's Gmail.
- **Subject:** "Annotake for your Mac".
- **Body,** as plain text and simple HTML: "Here's the download link you asked for: https://annotake.app/download. Open it on your Mac (macOS 15 or later), open the disk image, and drag Annotake to Applications. This is the only email we'll send you." It's signed "Annotake, made by Fayzan Malik in Ontario, Canada", with links to annotake.app and the privacy policy.
- **DNS records,** in Vercel:
  - Resend's DKIM record, and the MX and SPF records for its sending subdomain, exactly as Resend lists them;
  - `_dmarc` TXT `v=DMARC1; p=none; rua=mailto:hello@annotake.app`, tightened to `p=quarantine` once reports are clean;
  - ImprovMX's two MX records and the records it lists.

  Resend's SPF sits on its own subdomain, so the two don't clash.

### 5.5 Counting

- **Visits and referrers:** Vercel Web Analytics, through the first-party `/_vercel/insights/script.js`. Hobby includes 50,000 events a month, kept for one month, with no custom events and no UTM tags.
- **Downloads:** GitHub's download count per asset, from `gh release view -R fayzan123/annotake-releases --json assets`.
- **Link emails:** Resend's dashboard.

### 5.6 Security headers

- **The Content Security Policy:**
  - `default-src 'self'`, `script-src 'self'`, `style-src 'self'`, `font-src 'self'`, `connect-src 'self'`;
  - `img-src 'self' data:`;
  - `frame-ancestors 'none'`, `base-uri 'none'`, `form-action 'self'`, `object-src 'none'`;
  - `upgrade-insecure-requests`.
- **The other headers:**
  - `Referrer-Policy: strict-origin-when-cross-origin`
  - `X-Content-Type-Options: nosniff`
  - `Permissions-Policy: camera=(), microphone=(), geolocation=()`
  - `Cross-Origin-Opener-Policy: same-origin`
  - `Strict-Transport-Security: max-age=63072000; includeSubDomains`. The `.app` domain is HTTPS-only anyway.

### 5.7 Search and sharing

- **Title:** "Annotake: show your coding agent exactly what happened".
- **Description:** "A Mac menu-bar app. Press a key, click through the bug in any app, and drag the card into Claude Code, Cursor, or ChatGPT: one captioned screenshot per step. Free during the beta."
- **The preview image** for X, Reddit, and Discord: 1200 × 630, showing the headline over the gate strip. It's rendered from the page by a script and committed as `og.v1.png`, with `twitter:card` set to `summary_large_image`.
- **The rest:**
  - a canonical URL;
  - a `SoftwareApplication` JSON-LD block: macOS 15 or later, a developer application, price 0 during the beta;
  - `robots.txt` that allows everything, and a three-page sitemap.

### 5.8 Performance budget

- **The first load transfers at most 200 KB:**
  - HTML up to 30 KB, CSS up to 25 KB, and JS up to 40 KB;
  - three fonts of up to 25 KB each;
  - no images above the fold beyond inline SVG.
- **Lighthouse on mobile:** at least 95 for performance and 100 for accessibility.

## 6. Robustness and scale

**The app itself has no server,** so more users cost nothing. The shared pieces are the site, the email function, the download, and the update feed. Each keeps working at any traffic, and degrades instead of breaking when something fails.

| Part | Under load | If it fails |
|---|---|---|
| Pages | Static files cached across Vercel's network; no server to overload. At 200 KB, Hobby's 100 GB covers about 500,000 visits a month | Instant rollback to the last good deploy |
| Download | An edge redirect to GitHub's CDN, at any volume, free | Change one redirect to move hosting |
| Email me the link | A separate function; Resend free sends 100 a day, Pro 50,000 a month with no daily cap | The form shows the link with Copy and Share. The page never depends on it |
| Bots on the function | A honeypot, a too-fast check, one email per address per day, and a WAF rule of 10 requests per 10 minutes per IP (Hobby allows one rule). The limit is loose because phones on one carrier often share an IP, and the fallback covers anyone it catches | Next step: BotID Basic, free on all plans, after confirming it sets no cookies |
| Analytics | Hobby counts 50,000 events a month | Counting pauses; the site is unaffected |
| `hello@` and `feedback@` | ImprovMX free forwards 500 a day | Upgrade, or move to a helpdesk |
| Without JavaScript | A plain link and a plain form | Still downloads, and still sends the link |

- **No database.** Nothing is stored on our side, so there's nothing to scale, back up, migrate, or leak.
- **Secrets:** the Resend key lives only in Vercel's Production settings. There are no runtime packages to update or be attacked through.
- **Deploys:** every change gets a preview link before production.
- **Monitoring:**
  - a free uptime monitor (UptimeRobot, say) checks `/` and `/download` every 5 minutes and emails Fayzan;
  - Vercel and Resend email him as he nears their limits.

**When to upgrade:**

| When | Do | Cost |
|---|---|---|
| Now, through the friends round | Stay on free plans | $0 |
| Before the first public post (Stage 2's Reddit and Discord posts) | Vercel Pro: no pausing past Hobby's limits, and the commercial-use rule is settled | US$20 a month |
| Link emails pass about 60 a day, or before a launch | Resend Pro | US$20 a month |
| Bots get past the rate limit | BotID on `/api/link` | Free |
| Stage 3, or installs in the thousands | Move Sparkle's feed from GitHub to annotake.app (edge-cached), in an app release. Not before Vercel Pro, so a paused project can't stop updates | Free |
| Send Feedback passes 500 emails a day | ImprovMX's paid plan, or a helpdesk | About US$9 a month |

Real per-user server load arrives with Stage 2: Supabase sign-in and the daily counts. Its design plans for that the same way.

## 7. Testing

**Automated** (`make site-test`, test first wherever the code is testable):
- **Pages:** each loads with no console errors, in light and in dark.
- **Cookies:** no `Set-Cookie` on any response, and `document.cookie` stays empty.
- **The toggle** switches the theme and keeps the choice, with no flash on reload.
- **The Mac check:**
  - a Mac browser gets "Download for Mac", linking to `/download`;
  - an iPhone, and an iPad posing as a Mac, get "Email me the link".
- **The link form:**
  - a good address shows the sent state, and a bad one an inline error;
  - a 429 or 502 shows the Copy and Share fallback;
  - a filled honeypot gets a silent success.
- **Reduce Motion:** every animation shows its final state.
- **No JavaScript:** the download link works, and the `<details>` form posts.
- **Accessibility:** axe finds no serious problems.
- **Widths:** no sideways scrolling at 360, 768, 1280, and 1440 px.
- **Routes:** `/privacy`, `/terms`, and the 404 page load, and `/download` answers 302 to the GitHub URL.
- **The function** (`node:test`, with a fake `fetch`):
  - the checks, the honeypot, and the too-fast rule;
  - the idempotency key, the timeout and retry, and dry-run mode;
  - every status code, both request formats, and no address in any log line.
- **The brand:** `brand.js` matches `BrandMark.swift` and `Wordmark.swift`.

**On a preview deployment:**
- Run the page tests against the preview URL.
- **Burst test:** send 50 requests to `/api/link` from one machine within seconds (dry run). It passes if the WAF answers 429 after 10, and the page shows the fallback.

**Fayzan, at the end:**
- A real link email reaches his phone, outside spam, and a reply lands in his Gmail.
- The site looks and moves right on his iPhone and both Macs, in light and dark.
- He reads the privacy policy and the Terms.

## 8. Fayzan's part (all at the end)

- **Accounts:** create the Resend and ImprovMX accounts, and the Vercel project connected to `fayzan123/annotake`, with `site` as its root directory.
- **The Resend API key** goes into Vercel as a Production-only variable. `EMAIL_DRY_RUN=1` goes into Preview.
- **DNS:** add the records Resend and ImprovMX list in Vercel, or let a session add them with the Vercel CLI under his login.
- **The domain:** register annotake.com in Vercel and set its redirect.
- **The firewall:** turn on the WAF rate-limit rule for `/api/link`: 10 requests per 10 minutes per IP, fixed window, answering 429.
- **Optional:** an uptime monitor account.
- **Before the first public post:** Vercel Pro.
- **Later,** when the triggers in §6 come: Resend Pro.

## 9. Open items

- **The 20-second video.** When it exists, it goes in a section after How it works: self-hosted MP4 and WebM, muted and looping while in view, with a poster frame. It also goes on X and Reddit.
- **The app's Send Feedback address** switches to `feedback@annotake.app` in the next app release, once forwarding works. It's one line (`Feedback.address`).
- **Sparkle's MIT notice** goes into the app bundle in the next app release.
- **Stage 2:** news consent at sign-in, if wanted, under §4.4's rules. The privacy policy is updated before sign-in ships.
- **Stage 3:** pricing, the FAQ, a changelog, the feed move, and maybe Astro.

## 10. Changes to other docs

Made alongside this doc:
- **[Distribution design](2026-09-30-distribution-design.md):**
  - §6: the page offers a download instead of a "Join the beta" box, and points here;
  - §6's build list: "the landing page, the waitlist, and a short privacy policy" becomes the landing page and its policies, done in this design;
  - §7's launch-day email goes to the beta testers, since there's no waitlist.
- **[Session guide](README.md):** Session 9 is added to the order.

## 11. Not in this design

- Stage 2's sign-in, the daily counts, and the founding-member checkout. They keep their own design.
- Pricing, the FAQ, the changelog, and Homebrew, which belong to Stage 3.
- Recording the video.
- A blog, a newsletter, or other languages.
