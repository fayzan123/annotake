# Checkpoint results

> Written when the app was called Flipbook; it's Annotake since 2026-09-30 ([distribution design §3](plans/2026-09-30-distribution-design.md#3-the-name-annotake)).

## Checkpoint 1 (2026-09-24)

Personal Mac, macOS 15.7. Items follow the plan's Task 20 list. Fayzan's summary: "Pretty much everything passed." The failures below are fixed in Session 5 (Task 21).

0. **Install and permissions: pass.** `make install`, then the three prompts. After granting and reopening, the log shows all three permissions, and every recording created the click-cleanup tap and a 1920×1246 screen stream.
1. **Gestures: pass.**
2. **Plain clicks in a hold: pass.**
3. **Labels: fail, one case; the rest pass.**
   - **A click on empty space in a Chrome window's tab strip is labeled with the whole window title.** In capture `2026-09-24 at 16.46.58`, 9 of the 10 captions read like `Clicked group "Inbox (…) - … - Gmail - Google Chrome - Fayzan"`, and frame 1's marker sits on Chrome's tab strip. Chrome exposes that spot as an `AXGroup` whose title is the window's title. This is M0's "a label that's really the window title" problem in a new place: the label rules stop at `AXWindow`, but here the title comes from a group inside the window. Fix: a container whose label equals its window's title counts as no label, so the caption reads `Clicked at (x, y)`.
4. **Output: pass.** Caption strips and markers look right.
5. **Card: pass.** Captures were ready 0.5–1.1 s after stop (the log's timings for all 8). Claude Code in VS Code's integrated terminal received 1 of 10 frames, as a plain path, as M0 found for VS Code.
6. **Filmstrip: pass.**
7. **Password field: not tested, by choice.** Flipbook is fully local; unit tests pin that a secure field's value is never read and that typed characters never leave the event tap.
8. **Design §12 questions:**
   - Cursor ⌘-click during a hold: passed with item 2 (no jump to the definition).
   - Finder drag to another volume, copy or move: not reported.
   - Clearing the AX flags at stop: Chrome and Cursor behaved normally (passed with item 3).
   - How soon Chrome exposes web content: labels passed; the first click's timing wasn't reported separately, so the flag stays as it is.
   - Claude Code in Terminal.app and iTerm: not reported here. VS Code's terminal keeps only the first frame. (Checkpoint 2 on the work Mac: Terminal gets every frame.)

## Checkpoint 2 (2026-09-24)

Items follow the plan's Task 27 list. **Everything passed.** Fixed during the checkpoint: Restore Defaults on each settings tab, and `make replay` with capture paths. Left for the next session: the three minor findings (window-mode caption line 2, slider log lines, and the personal Mac's constant 10 fps dirty frames).

0. **Personal Mac setup: done.** Flipbook quit, `tccutil reset All com.fayzanmalik.flipbook`, `make install`, then opened. An earlier run of the Session 5 build had already completed the checklist, so `firstLaunch.v1` and `loginItem.initialized` were also deleted from Flipbook's defaults; without that, the checklist wouldn't have shown. Settings were kept.
1. **First launch: pass.** The checklist appeared. Each button prompted first and opened System Settings after that. Quit & Reopen brought the checklist back where it was. Double-tapping Right ⌘ closed it and gave a card, and Flipbook is in Login Items. The log: the first launch had all three permissions off and logged `launch at login on`; after the reopens, all three were on; the first capture was ready 1.07 s after stop.
2. **Settings: pass, with two fixes.** Every tab worked; Right ⌥ (hold, double-tap, and a hold-click on a Chrome link didn't download it); fn with Handy off and the 🌐 key set to Do Nothing; the Advanced sliders changed how the gestures feel.
   - **Putting the Advanced sliders back by hand missed the defaults** (260 / 800 / 250 ms instead of 250 / 800 / 300). Fayzan: every tab with settings needs a reset button. Fixed: each tab but Permissions now has **Restore Defaults** at its bottom right. It resets only that tab's settings, and is greyed out while they're already the defaults (spec §3.6). **Checked on the new build:** Advanced's button put the timings back to exactly 250 / 800 / 300 ms, and General's turned Launch at login back on.
   - Minor: dragging a slider logs `trigger key and gesture timings updated` once per step (dozens of lines a drag). Harmless, but noisy in the log.
   - **`make replay SESSION="<capture>/.raw/session"` failed on real captures:** the Makefile passed `$(SESSION)` unquoted, and capture folder names have spaces, so it printed the usage line. Fixed by quoting it. On capture `2026-09-24 at 17.47.39`, the replay then picked the same 4 frames as the live capture, with the same captions as its `steps.md`.
3. **Picker: pass.**
   - **A window: pass.** Capture `2026-09-24 at 17.58.54` recorded a Finder window alone (the log: `1840×928, window`).
   - Minor: that frame's caption line 2 reads `Code — main.swift — flipbook`, the app that had focus at the start, under a picture of Finder. In window mode, line 2 could name the recorded window when the focus is elsewhere.
   - **A specific screen (the ultrawide), and a window moved to the other screen: pass, per Fayzan** (tested earlier; this Mac's log, which starts at 16:02, has no recording on another display).
   - **A window closed mid-recording: pass.** Capture `2026-09-24 at 18.00.33`: ⌘W closed the recorded Chrome window, the log shows `capture stream ended: targetGone`, and the capture was saved 549 ms later with 3 frames (Start, Pressed ⌘W, End).
   - **The fallback after the chosen window's app quits: pass, per Fayzan** (not in this Mac's log).
4. **Output: pass, per Fayzan** (not in this Mac's log: no compact or 5-frame capture, and none outside `~/Pictures/Flipbook`).
5. **Retention: pass** (run by Claude). A copy of capture `2026-09-24 at 17.58.54` with its marker set to `2026-08-15T12:00:00Z` was moved to the Trash at the next launch (the log: `retention: 1 capture(s) moved to the Trash`). A folder without a marker, with 60-day-old files, stayed.
6. **Permissions: pass, on the work Mac** (macOS 26): turning Accessibility off made "Fix permissions…" appear, and revoking it during a hold left the mouse working.
7. **Sounds and login: pass, on the work Mac:** the sounds toggle and the launch-at-login toggle both work.
8. **Recording coverage: pass.** Full screen: capture `2026-09-25 at 00.29.54` recorded full-screen Chrome (8 frames, the click ring on the right bookmark), and Fayzan confirmed it on the work Mac too. Both displays: pass, per Fayzan (item 3's ultrawide checks). No frame looked at in this checkpoint shows the pill or the card.
   - **Feedback: the start sound sounds like an error.** It's Tink, one of macOS's alert sounds (the one for clicking where you can't), so starting a recording sounds like a mistake. The stop sound, Pop, is an alert sound too. Fayzan compared it with four sounds that aren't alert sounds (CoreAudio's `begin_record`, `mic_unmute`, and `screen_sharing_started`, and FaceTime's `multiway_join`) and kept Tink, and Pop for the finish. No change.
9. Work Mac (macOS 26):
   - **Install, first-launch checklist, permissions, recording, and a drag into Cursor: pass.** Installed by dragging the app into `/Applications` (not `~/Applications`); the quarantine flag was removed with `xattr -dr com.apple.quarantine /Applications/Flipbook.app`.
   - **Menu-bar icon in frames: pass.** macOS 26 gives the icon's window to Control Center (the log's `ownedBy(bundleID: "com.apple.controlcenter")`). Flipbook excluded Control Center along with itself and Notification Center, kept Control Center's 24 other windows as exceptions, and the icon is not in the frames.
   - **Bottom-center dirty region: M0's 10 fps region doesn't recur on the work Mac.** A 10 s hands-off recording was idle most of the time (26 complete, 81 idle): about one complete frame a second, about 295,000 px dirty, 0 changed. That matches the pill's once-a-second clock: the pill is excluded, but macOS still reports its redraw. Negligible cost, and the capture was right (1 frame kept).
     - **The personal Mac (macOS 15.7) is the odd one out:** the same test there got 10 complete frames a second, each with about 60,000 px dirty and 0 changed (107 frames, about 5% of a core). That's something on that Mac's screen, not macOS 26; the source is unknown because the log has totals only. Next: log the dirty region's bounding box in that line.
   - Drags: **Cursor, Terminal, Slack, and Jira: pass.** Terminal got every frame, which answers Checkpoint 1's open question for Terminal.app (VS Code's integrated terminal keeps only the first). iTerm: not tested.
   - **Self-test: pass** on the work Mac (macOS 26).
   - **Chrome labels: pass,** including the Session 5 fix: a click on empty tab-strip space reads `Clicked at (x, y)`, not the window title.
   - **Slack labels: pass.**

## Checkpoint 3 (2026-10-01)

Items follow the Stage 1 plan's Task 15 list. Every step passed, with the `feedback@annotake.app` forwarding deferred (step 0). Still open: the items marked "not reported yet". Fixed during it: Developer ID signing, the self-test on a 1× monitor, a `make release` that picks up after a slow notarization, and three first-run bugs.

0. **Before starting:** the Apple Developer membership is active (team `GX473Q97WQ`). **annotake.app was bought on Vercel** during the checkpoint (registered 18:57 UTC through Name.com, on Vercel's DNS). The email forwarding is deferred. Fayzan: `feedback@annotake.app` isn't mission critical, so Send Feedback goes to Fayzan's Gmail (`Feedback.address`) until the forwarding is set up.
1. **The Developer ID certificate: pass, with two fixes.** `make devid-import` imported `Developer ID Application: Fayzan Malik (GX473Q97WQ)`.
   - **Signing with it failed** with `errSecInternalComponent`. The log showed `leaf MissingIntermediate`: while signing, `codesign` checks the chain again without the keychains on the search list, so Apple's G2 intermediate has to be in the login keychain, where Xcode would put it. `make devid-import` now puts it there, and the bundler puts it back if it's missing.
   - **`make selftest` then failed** only because its window opened on the 1× Lenovo T24i-10: an 800×528 capture, and an extra Start frame. The window now opens on the sharpest screen.
   - After both, builds carry the Developer ID (team `GX473Q97WQ`; Sparkle signed by the same team; no library-validation exception), and `make selftest` and `make selftest-intel` pass.
2. **The notarization login: done another way.** The App Store Connect API page asked to request access, so the profile uses an app-specific password instead: `xcrun notarytool store-credentials annotake-notary --apple-id … --team-id GX473Q97WQ`. Validated.
3. **Backups:** the Developer ID export ran; macOS asked for the signing keychain's password, `annotake-local`, once per key. Storing both secrets: not reported yet.
4. **The releases repo: renamed** to `fayzan123/annotake-releases`.
5. **The first release: pass, after a fix.** Apple took 49 minutes over the app's first notarization, past the script's 30-minute wait, and the run stopped before publishing. `make release` now picks up where it left off. It finished 0.2.0 (93) from the same commit by stapling the ticket Apple had issued, and Apple notarized the disk image within minutes. Checked on GitHub's copies: the zip's Sparkle signature verifies, and Gatekeeper accepts the disk image and the app as notarized, with the tickets stapled.
6. **The old command: pass.** The old `flipbook-releases` address serves the new installer, so no stub repo is needed.
7. **Installing like a stranger: pass, with three first-run fixes.** From the log: migration imported the settings, moved `~/Pictures/Flipbook` to `~/Pictures/Annotake`, and renamed both captures' markers; Flipbook was quit and moved to the Trash (no App Management block); a practice recording and a dropped card (3 frames) finished the first run.
   - **macOS asked for Input Monitoring and Screen Recording as soon as Annotake launched,** before the first run reached them: the launch created the key's event tap and listed the screens. Each grant from those prompts made macOS quit and reopen Annotake, so the window kept closing. Fixed: neither happens before its permission is granted, and a grant noticed while the window is behind System Settings brings it back in front.
   - **The relaunch forgot that this Mac is an existing user** and ran the new-user flow (welcome, practice run, drop box): nothing had saved the fresh state yet. And that fresh state started at the welcome, which the existing-user flow doesn't have, so Get Started would have skipped every permission. Fixed: a step the mode doesn't have means its first step, and the fresh state is saved at once.
   - Not reported yet: the first-open dialog, and the move offer (7.3).
8. **Updates: pass.** The first check found nothing: the logo session had installed a local build from the working tree, numbered 99 like the published 0.2.0 (99). Once 0.2.0 (100) was published, Check for Updates installed it: the notarized, stapled 100 replaced the local 99 at 13:59:26, Annotake relaunched at 13:59:29, and all three permissions stayed granted.
9. **Send Feedback: pass.**
10. **The first run as a new user: pass.** At 14:03 Annotake was quit, its permissions reset (`tccutil reset All com.fayzanmalik.annotake`), and `onboarding.v1` deleted, keeping the settings; then it was reopened. The log shows `listen tap not created: no Input Monitoring yet` with all three permissions off, so nothing asked before its step.
    - **Fayzan: the practice run made no sense.** Its Open button and Remember me box were in the first run's own window, which Annotake keeps out of every recording, so they never appeared in the frames. Now: double-tap, click through something in another app, double-tap again, and the window comes back with the drop box once the recording is saved (7af8c96, shipped in 0.2.0 (102)).
    - The permission steps, Quit & Reopen, and the icon and the first run: pass, per Fayzan. In the log, the relaunch at 14:06:32 came 8 s after the Screen Recording step with no `onboarding: reopen` before it, so the first run's own Quit & Reopen button wasn't what relaunched it.

**After step 10, the Flipbook upgrade path was removed** (7c994d9, in 0.2.0 (102)). Only Fayzan ever installed Flipbook, and the path matched the name: the installer deleted any `Flipbook.app` (on a case-insensitive disk, DigiCel's FlipBook.app too), and migration moved any `~/Pictures/Flipbook`. So step 7's migration and existing-user fixes describe code that no longer exists, and for step 11 Fayzan drags Flipbook to the Trash on the work Mac before running the install command, which no longer removes it or resets its permissions.

11. **The work Mac (macOS 26): pass, per Fayzan,** installed from the disk image instead of the install command, so the command itself wasn't run in this checkpoint.
    - **Once, after a permission grant, Quit & Reopen quit Annotake without reopening it,** and Fayzan opened it again by hand. Not investigated: it waits until a user reports it. To start then: whether it was macOS's prompt in System Settings or the first run's Reopen step (only that one logs `onboarding: reopen` first), and the work Mac's `~/Library/Logs/Annotake.log`. The first run's button runs `sleep 1; /usr/bin/open` on the app, then quits.

## Checkpoint 4 (the site)

Steps from the landing page plan's Task 15, for connecting annotake.app. Session 10 built and tested the site locally, and did none of this: it never deploys, creates accounts, or touches DNS. After the session, Fayzan dropped the ImprovMX step: annotake.app receives no mail, and the site shows no email address. Fill in each result.

1. **Resend:** create the account and add `annotake.app`. Add its DNS records in Vercel (or have a session run `npx vercel dns add …` under your login), then verify the domain.
   Result: **done by Fayzan.** `annotake.app` is verified in Resend, with its three records in Vercel's DNS (`resend._domainkey` TXT, and `send` TXT and MX). The API key isn't in Vercel yet: see step 3.
2. **DMARC:** add `_dmarc` TXT `v=DMARC1; p=none`. (No report address: nothing receives mail at annotake.app.)
   Result: **done** (by Claude, 2026-10-01); Vercel's nameservers serve it.
3. **Vercel:**
   - create a project from `fayzan123/annotake`, with Root Directory `site` and Framework Preset Other;
   - add the environment variables `RESEND_API_KEY` (Production) and `EMAIL_DRY_RUN=1` (Preview);
   - turn on Web Analytics;
   - add `annotake.app` and `www.annotake.app`.

   Result: **done** (by Claude, 2026-10-01), except the API key. The project is `annotake-site` (Root Directory `site`, preset Other), at `annotake-site.vercel.app`. `EMAIL_DRY_RUN=1` is set for Preview only, Web Analytics is on (Hobby, free), `annotake.app` serves Production, and `www.annotake.app` answers 308 to it. **Still to do (Fayzan): `RESEND_API_KEY`.** In Resend, create a key with Sending access for `annotake.app`; in Vercel, add it as a Secret for Production only, then redeploy. Until then, the email form shows its fallback, the link to copy. **Done 2026-10-15:** Fayzan added `RESEND_API_KEY` (Secret, Production) and redeployed. Before that, a live `POST /api/link` answered 502 and logged `link: failed not configured`. After it, the same request answered 200, and the email reached Gmail's inbox (the Updates tab) with `dkim=pass` (`d=annotake.app`, selector `resend`), `spf=pass` (`send.annotake.app`), and `dmarc=pass` (`p=none`).
4. **annotake.com:** register it in Vercel, and add it and `www` as redirects to `https://annotake.app`.
   Result: not done yet: it costs money, so it's Fayzan's call.
5. **The firewall:** add a rule for when the request path is `/api/link` and the method is `POST`: Rate Limit, Fixed Window, 10 requests per 600 s, keyed by IP, answering 429. Then publish it.
   Result: **done** (by Claude, 2026-10-01): "Email link rate limit", published.
6. **The first deploy:** run `make site-smoke URL=https://annotake.app` and `make site-burst URL=https://annotake.app`. The burst sends no email.
   Result: **pass** (by Claude, 2026-10-01). Smoke: every check passed after a redeploy turned Web Analytics on, except annotake.com's redirect (not registered; step 4). The disk image is 3.6 MB, and `tests/` and the README aren't served. Burst: 10 × 200, then 40 × 429.
7. **On your iPhone:** use Email me the link with your own address. The email arrives (outside spam), from `noreply@annotake.app`. Open the link on a Mac, and the DMG downloads.
   Result: not done yet.
8. **The look:** on your iPhone and both Macs, in light and dark, check how the hero, the steps, and the footer look and move.
   Result: not done yet.
9. **PageSpeed Insights on mobile:** performance at least 95, accessibility 100.
   Result: **pass** (by Claude, 2026-10-01): Performance 99, Accessibility 100, Best Practices 100, SEO 100. First Contentful Paint 1.1 s, Largest Contentful Paint 1.4 s, Total Blocking Time 0 ms, Cumulative Layout Shift 0.066.
10. **The policies:** read the privacy policy and the Terms, and approve them or ask for changes.
    Result: not done yet.
11. **Optional:** an uptime monitor on `/` and `/download`.
    Result: not done yet.
12. **Before the first public post:** move to Vercel Pro.
    Result: not done yet.

## Checkpoint 5 (the email list)

Steps from the email list plan's Task 11, with what the build found ([email list design §13](plans/2026-10-15-email-list-design.md#13-changes-from-planning-and-building) has why). The build, on branch `email-list`, did none of this: it never deployed, touched Resend or Vercel, or sent an email. Fill in each result.

**For now, the list only collects addresses** (decided 2026-10-16, design §13). Fayzan isn't emailing it yet, and the addresses count Annotake's users. CASL wants a mailing address beside a consent request and in every email, so until the first email there's no address, no box in the step, and no welcome email. What sending needs waits under "Parked until the list's first email", after the steps.

1. **The step without the box or the mailing address:**
   - `consent-2026-10-15`, not yet shipped, loses its box and `{address}`, and the app saves every address with `news: false`;
   - `make release`'s guard against an unset address is gone;
   - /privacy says the address counts Annotake's users and gets important notices, with no welcome email and no Feedback and news.

   Result: **done** (by Claude, 2026-10-16, e6b7888 and 805932d). `make test`: 534 tests. `make site-test`: 162 unit and 363 page tests (6 skipped).
2. **Read and accept the copy,** after a fresh `make ui-snapshots` (`build/ui/settings-general-no-email.png` predates Add…). It comes before Resend, Vercel, and the deploy, so any change ships in one deploy:
   - the email step (`build/ui/onboarding-email-filled.png`);
   - the "Change your email" sheet and its Privacy policy link (`settings-email-change.png`), and Not set with Add… (`settings-general-no-email.png`);
   - `/privacy` and `/terms`. Both say "Last updated: October 15, 2026": move it to the deploy day if you like. /privacy's Changes section says big changes are noted on the home page: decide whether the email list is one;
   - design §13's open questions 3 (the window title) and 5 (the Change… sheet and the old address). The rest wait with the list.

   Result: **done** (Fayzan, 2026-10-16), with no wording changes asked for, and four answers:
   - the `.emailOnly` pass's window is titled "Annotake" (open question 3); a first run and Fix permissions… keep "Welcome to Annotake";
   - the email list is a big change, so the home page notes it beside the footer's Privacy link: "Privacy policy updated: the app now asks for your email.", until the policy changes again;
   - both pages' "Last updated" becomes the deploy day, set in step 5;
   - the Change… sheet stays as it is (open question 5).

   Built in bdf6e48 (the title) and b49a97d (the note). `make test`: 535 tests. `make site-test`: 162 unit and 366 page tests (6 skipped).
3. **In Resend,** all before Vercel's settings: until the four properties exist, every new contact answers 502 (`subscribe: failed rejected`), and the app's retries soon slow to every 6 hours.
   - the topics `Important notices` (Defaults to: Opt-in; Visibility: Public) and `Feedback and news` (Defaults to: Opt-out; Visibility: Private, so only the app's box, which records consent, adds anyone to it). A topic's default can't be changed later. Note both ids;
   - the string contact properties `consent_at`, `consent_wording`, `consent_source`, and `app_version`;
   - one segment, such as "Annotake users"; note its id;
   - a full-access key.

   Result: **done** (2026-10-16). Fayzan made the full-access key "Annotake contacts", and Claude made the rest with it through Resend's API: `Important notices` (opt-in, public) is `8ff665b1-6687-4b24-bd56-ef007df3e4f5`, `Feedback and news` (opt-out, private) is `57d87515-4ce3-42a8-95e9-4f3c04f0018a`, the segment "Annotake users" is `166e1752-e585-4b15-9e44-6f3762f36a68`, and the four string properties exist. The ids aren't secret: Resend's API needs the key for anything.
4. **In Vercel (Production, Secret):** `RESEND_CONTACTS_KEY`, `RESEND_SEGMENT`, `RESEND_TOPIC_NOTICES`, `RESEND_TOPIC_NEWS`, and `UNSUBSCRIBE_SECRET`. Not `MAILING_ADDRESS`: without it, `/api/subscribe` adds the contact and sends no welcome.
   - `UNSUBSCRIBE_SECRET`: make it with `openssl rand -hex 32`, and save it in the password manager before pasting it in; Vercel never shows a Secret again. Never make a new one: once welcome emails go out, each one's unsubscribe link depends on it. Carry the same value to a Pro team.
   - Change the firewall rule's path from `/api/link` to everything under `/api/` (Request Path, Starts with, `/api/`), and publish it.
   - Preview gets none of these, so there `/api/unsubscribe` answers 502 (`unsubscribe: failed not configured`). That's expected.

   Result: **done** (2026-10-17). Fayzan saved the five settings in his password manager, added them (Production, Secret), and redeployed, which only rebuilt the old `main`. Claude changed the firewall rule in Chrome and published it: it's now "API rate limit" (it was "Email link rate limit"), for a Request Path starting with `/api/` and the method `POST`, still Fixed Window, 10 requests per 600 s, keyed by IP, answering 429.
5. **Deploy:** first, set both policy pages' "Last updated" to the deploy day, and `UPDATED` in `site/tests/pages/legal.spec.js` to match (step 2). Then merge `email-list` into `main` and push, or redeploy if it's there already, so the functions get step 4's settings. Push the branch whole: Vercel builds the last commit, and Task 1's commit alone fails its build.
   - Vercel shows the pushed commit as Ready on Production, not Canceled.
   - If a later push that leaves `site/` alone still builds, check that Vercel exposes system environment variables: the ignore step reads `VERCEL_GIT_PREVIOUS_SHA`, and without it every push builds, which is safe.

   Result: **done** (2026-10-17). With Fayzan's go-ahead, Claude fast-forwarded `main` to `email-list` and pushed it whole: 34 commits, `f75a744..6be64e6`. About 20 s later, production answered a GET to `/api/subscribe` with 405 and showed the home page's policy note, and both policy pages read "Last updated: October 17, 2026".
6. **The smoke check:** `make site-smoke URL=https://annotake.app` passes every check except annotake.com's redirect. That one fails, and so does the command, until Checkpoint 4's step 4 registers the domain. Besides Checkpoint 4's checks, it reads `/api/subscribe` (405), `/api/unsubscribe` with nothing to check (400; it fails until `UNSUBSCRIBE_SECRET` is set), and `/api/_lib/consent.json` (404). It also posts the invalid address `smoke@example` under the current consent id: 400 means the deployment has the app's wording, and 422 that it doesn't yet. The gate is that consent check, "POST /api/subscribe has the app's consent id": it must read PASS (400). It comes before any sign-up below, and before the release.
   Result: **passed** (2026-10-17), but for annotake.com, as expected (`ENOTFOUND`: the domain isn't registered). The gate read PASS: `POST /api/subscribe` answered 400 under `consent-2026-10-15`. `/api/unsubscribe` with nothing to check answered 400, so `UNSUBSCRIBE_SECRET` is set, and every other check passed. The smoke check reports www.annotake.app together with annotake.com, so it was checked alone: 308 to `https://annotake.app/`.
7. **The app in a real window,** with a build of `main` (`make install`):
   - **The email step:** with Annotake quit, run `defaults delete com.fayzanmalik.annotake email.v1` only, leaving the first run finished, then open it. Expect the email step alone, with the field focused. ⌘V pastes an address, and ⌘A, ⌘X, and ⌘Z work. Return with `sam@example` does nothing.
   - **Recording waits:** close the window. Hold Right ⌘: nothing records, and at the reveal the pill says "Add your email to start recording" with Open. A quick Right ⌘ shortcut (⌘C) shows nothing, and works. The menu offers Start Recording throughout, and Start shows the message. Held past 5 s, the message goes while the key is still down. Open brings the email step forward.
   - **Saving:** Return with a new Gmail `+alias` submits once and shows You're set, and the next hold records.
   - **Settings:** the Email row shows the address with Change…, which opens "Change your email": the field focused with the address selected; ⌘V pastes, Return saves, and Esc cancels. With Annotake quit and `email.v1` deleted again, the row shows Not set with Add…, which opens the email step.
   - **The typo hint:** type `sam@gmial.com` and stop: "Did you mean sam@gmail.com?" shows below the field after a moment, and clicking it puts that in the field. Typing on hides it until the next pause. Continue and Return take a hinted address as typed. `sam@hotmail.ca` and `sam@me.com` get no hint. Change… shows the hint as it opens if the saved address has a typo.
   - **The Dock:** while the first run or Settings is open, Annotake is in the Dock and ⌘-Tab, and its menus (Annotake, Edit, Window) are in the menu bar. Clicking the Dock icon brings the window back from behind another app. ⌘, opens Settings, ⌘W closes the window, and About shows the version. Closing the last window takes Annotake out of the Dock; note whether the menu bar then shows the app behind or still Annotake's menus until you click elsewhere. The pill and the cards never put it in the Dock.

   Result: in progress (2026-10-17). Claude installed a build of `main` (0.2.0, 167, Developer ID, so permissions carried over). `email.v1` wasn't set, so it opened on the email step alone. There Fayzan had "Every email has an unsubscribe link." taken out of the notice: up front it's beside the point, the step asks for no consent, and /privacy, linked from its footer, says how to unsubscribe. `consent-2026-10-15` was on Production, so the new wording is a new version, `consent-2026-10-17`. Production needs it before an address is saved under it: push `main`, see the smoke check's consent check pass under the new id, then reinstall and run step 7 again from the top. Claude's shell can't reach Annotake's settings with `defaults` (Recorded, not debugged, below), so run this checkpoint's `defaults` commands in Terminal. With Fayzan's go-ahead, Claude pushed `main` (`6be64e6..5a3f4d7`): Vercel deployed it, and the smoke check's consent check passed under `consent-2026-10-17` (400), with every other check but annotake.com's. Claude then installed build 173 (0.2.0, Developer ID), with the Dock, the typo hint, and the new wording, and opened it with no address saved. Before step 7 started on it, Fayzan asked to stay as anonymous as the law allows, so his name came out of everything but /privacy and /terms, which must say who's responsible: the step's footer is now "annotake.app · Privacy policy" (`consent-2026-10-17b`, a new version again, since `consent-2026-10-17` was live), the site's footer says only "Made in Ontario, Canada", the link email signs off "Annotake, made in Ontario, Canada", and the home page's search data and the About panel name no one. That went to Production with Fayzan's go-ahead (`5a3f4d7..3f9e928`): the smoke check's consent check passed under `consent-2026-10-17b`, and Claude installed build 177 and opened it with no address saved, for step 7 from the top.
8. **One real sign-up:** a fresh first run. With Annotake quit, run `defaults delete com.fayzanmalik.annotake email.v1`, then the same for `email.sentKeys.v1` and `onboarding.v1`; open it, and sign up with a new Gmail `+alias`.
   - In Resend, the contact is in the segment, on Important notices and not on Feedback and news, with all four properties: `consent_wording` is `consent-2026-10-17b`, and `consent_source` is `app`.
   - Vercel's log for the request says `subscribe: added welcome skipped no address`, and no email arrives.

   Result: not done yet.
9. **Release:** `make release DRY_RUN=1 NOTES="…"`, then `make release NOTES="…"`, only once every step above passes. Existing copies get the email step after their next Sparkle update.
   - The real release wants a clean tree, so stash `.vscode/launch.json` around it: `git stash push -- .vscode/launch.json`, then `git stash pop` after.
   - `VERSION` goes to 0.3.0 first, since the email step, the Dock, and the typo hint are new, in a commit pushed before the release (it checks that `HEAD` is `origin/main`).

   Result: not done yet. A dry run on 2026-10-17 (0.2.0, 173) built the app, made the disk image, signed the update for Sparkle, and wrote the feed.

**Parked until the list's first email,** even a security notice, in this order:
1. **The mailing address:** rent a PO box or a virtual mailbox, never your home address (design §6.1). CASL wants it valid for 60 days after each email.
2. **The box comes back with it,** in a new consent version (below), with `{address}` in its footer: `consent.test.js` holds every version with a box to one. Its notice says again that consent can be withdrawn, as CASL wants of a consent request: "Every email has an unsubscribe link.", which `consent-2026-10-17` dropped. In the app, `EmailConsent` gets the box and the address back, the step its checkbox, and `make release` a guard against an unset address again (e6b7888 removed the last one). Copies that saved an address under `consent-2026-10-15` or `consent-2026-10-17` were never offered the box: decide whether they're asked once.
3. **`MAILING_ADDRESS` in Vercel,** which turns on the welcome email for new contacts. Contacts added before then never got one: decide whether the list's first email does its job. Nothing has checked those addresses, and since an address is required to record, some will be fake: the first email to them can bounce a lot at once, and a high bounce rate hurts annotake.app with mail providers and Resend. If the list looks padded, send that email in batches and watch Resend's bounces; Resend stops sending to an address that hard-bounces. The welcome's From is "Fayzan from Annotake", and its footer, like the broadcasts' and the box's consent request, names Fayzan Malik, since CASL wants the sender's name in them. To keep his name out of those too, register "Annotake" as an Ontario business name first (about $60 for 5 years; the registry is public), and use it there.
4. **In Resend:**
   - the broadcast footer, `Fayzan Malik · <address> · annotake.app`, with the unsubscribe link (the editor's Unsubscribe footer block, or `{{{RESEND_UNSUBSCRIBE_URL}}}`). Resend has no saved footer, so keep it in a draft broadcast to copy, or paste it each time;
   - open and click tracking off for annotake.app, since /privacy mentions no tracking. They're off by default: check they still are.
5. **Design §13's open questions 1, 2, 4, 6, and 7.**
6. **Design §9's checks 2–4,** in order. By then the segment holds real users, so test broadcasts go to a second segment holding only your aliases, added by hand (the free plan allows 3). Send each as a real broadcast, not with Test email, which leaves out the custom Reply-To.
   - **The list:** a fresh first run. With Annotake quit, run `defaults delete com.fayzanmalik.annotake email.v1`, then the same for `email.sentKeys.v1` and `onboarding.v1`; open it, and sign up with a new Gmail `+alias`, with the box ticked so it gets both test broadcasts below. Resend keeps the welcome's Idempotency-Key for 24 hours after that welcome, so an address that got one in the last 24 hours gets no second one, even after you delete its contact in Resend, though the log says `subscribe: added` (or `subscribe: added welcome already sent`, if the box changed). One whose contact is still there gets no welcome either: the log says `subscribe: kept`, `subscribe: kept unsubscribed`, or `subscribe: news added`. In Resend, the contact is in the segment, with both topics and all four properties. The welcome email arrives in the inbox with `dkim=pass`, `spf=pass`, and `dmarc=pass`, and Gmail shows its Unsubscribe link.
   - **Replies:** a reply to the welcome email from another address lands in `fayzanm786@gmail.com`.
   - **Unsubscribing,** in this order:
     - a test broadcast to each topic, sent to the test segment with Reply-To set to the Gmail address, reaches the alias: its unsubscribe link opens Resend's topic page, its raw headers (Gmail's Show original) carry `List-Unsubscribe` and `List-Unsubscribe-Post`, and a reply from another address lands in Gmail;
     - then Gmail's one-click unsubscribe on the welcome email marks the contact unsubscribed in Resend;
     - after that, the next broadcast doesn't reach the alias. Check its To: address: every alias lands in the same inbox;
     - typing the address again in a fresh first run, with the three keys cleared, sends no second welcome.

   A Change… to an address this Mac has sent before saves it as sent and posts nothing, even if its contact was deleted in Resend since: use a new alias for Change… tests, or clear the three keys first.
7. **The release** with the new wording, once its consent version is deployed.

**For any later change to the step's wording:** add a new version to `site/api/_lib/consent.json` and move its `current`, deploy it, and see `make site-smoke URL=https://annotake.app`'s consent check pass (400, not 422). Only then release the app that sends the new id: until the site has it, it answers that id 422, and every new copy's address waits on the app's backoff.

**Recorded, not debugged** (found during the build; each was there before it):
- From Claude's shell, `defaults` reads no domain at all, `com.apple.dock` and the global one included, sandbox or not, though the plists are there and Python reads them: it's that shell's environment, not Annotake. Run the checkpoints' `defaults` commands in Terminal.
- `InputBridgeTests.tabStartsNewLookup()` fails about 1 run in 40. Start: its two unstructured Tasks race for `FakeLabels`' fields.
- Tests that use a throwaway `UserDefaults` suite leave an empty `annotake-tests-*.plist` in `~/Library/Preferences` each (3,550 on this Mac by 2026-10-16): `SettingsTests` and `SettingsWindowTests`, and now `Tests/AnnotakeAppTests/Support/SignupHarness.swift`. Start: `removePersistentDomain(forName:)` empties a suite but leaves its file.
- With an address saved, the menu's Start clicked just as a Right ⌘ hold begins starts a hands-free recording while `InputMonitor` still holds the hold, so a double-tap can't stop it; the menu's Stop or the 5-minute limit does. Start: `SessionController.toggleFromMenu()` and `InputMonitor.handsFreeStartedElsewhere()`.
