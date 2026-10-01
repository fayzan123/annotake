# Annotake distribution design: from a personal tool to a product

**Status:** agreed with Fayzan in conversation, 2026-09-28 to 2026-09-30; written for his review · **Plan:** the Stage 1 plan comes next (§11) · **Spec:** [../spec.md](../spec.md), updated with the changes in §12

Worked out in Session 7, with web research from 2026-09-28 and name checks from 2026-09-30 (both in [../research-notes.md](../research-notes.md)). The app is being renamed from Flipbook to **Annotake** (§3). The code and older docs say Flipbook until Stage 1's rename lands; this doc says Annotake.

## 1. Goal

- **What this design decides:** how Annotake gets from Fayzan's two Macs to other developers, what it costs them, and how it makes money.
- **Fayzan's goal:** reputation first, with revenue as proof. Success is a product other developers use and pay for, which he can point to: weekly active users, paying customers, and MRR.
  - Small MRR still counts: paying customers prove he can build, ship, and sell. The number to watch is paying customers.
  - Users come first, paid conversion second.
- **Done means:** Annotake is launched publicly with a free plan and Pro, after the beta's bars are met (§6).
- **Principles:**
  - **Ease of use first, setup included.** Download, grant the permissions, start, as with Wispr Flow or Loom. Once Annotake is notarized, no Gatekeeper workarounds and no Terminal commands.
  - **Nothing you record leaves your Mac.** Frames, captions, `steps.md`, window titles, button names, and keys stay on it. The server knows an email, a plan, and counts (§8).
  - **A recording never waits on the network.** Offline, or whenever the plan can't be checked, no limit applies and nothing blocks.
  - **No AI in the product,** as before.
  - **Stages move forward on bars, not dates.** Fayzan sets the pace. New competitors appear every week, so stages overlap wherever they can.

## 2. Decisions

| Decision | Why |
|---|---|
| Reputation first, revenue as proof, measured in MRR | Fayzan wants the reputation of having built it and money from the people using it. MRR on a resume needs a subscription |
| Closed source | What's hard to copy is the tuning from real use, not the idea, and open code is easy to replicate with AI tools. A weekly cap also only works in a closed app |
| Accounts, with sign-in first (Google, GitHub, or Apple), like Wispr | Counting users, retention, and conversion, emailing every user, referrals, and team plans later all need accounts. The cost on a work Mac is small because nothing recorded leaves it |
| "Nothing you record leaves your Mac" replaces "never touches the network" | The old rule was written for a tool only Fayzan used. The promise users care about survives |
| Free plan: a soft limit of N recordings a week, a hard stop at 2.5×N, no slowdown | Wispr's real design (a soft cap at 2,000 words, a hard cap at 5,000, a counter only near the limit, no limit when the plan can't be checked), minus the slowdown, which would slow the thing Annotake is praised for |
| Pro: unlimited recordings, no frame mark, and MP4 with system audio and microphone | Heavy users pay for unlimited. MP4 is the Loom-like mode for sending recordings to people |
| Window recording stays free | 3 of Fayzan's 40 recordings used it, so it won't make anyone pay, and locking a feature that exists makes the free plan feel crippled |
| Referrals: the friend gets 30 days of Pro; the referrer gets a month once the friend has made 3 recordings | Wispr's shape. Fake sign-ups earn nothing |
| No trial at sign-up | While Pro mostly means unlimited, a trial does little in someone's first week. Referred users get 30 days |
| $9 a month or $72 a year; founding members $36 a year for as long as they stay subscribed | The free plan does the reach, so the price only has to suit the people who upgrade. It's a work tool, and it's easier to discount than to raise. The beta checks it |
| Polar as merchant of record; Supabase for sign-in and data | Polar handles worldwide sales tax and subscriptions (5% + 50¢). Supabase gives Google, GitHub, and Apple sign-in plus a database without running servers |
| Three stages: the friends round, the beta, then the paywall and launch | Outside validation comes before productising: strangers must get through setup, keep using it, and pay |
| An early install before notarization | Friends can start while Apple reviews the enrollment |
| The Apple Developer Program now, as an individual | A download that just opens needs Developer ID signing and notarization ($99 a year). The Mac App Store isn't an option: its sandbox blocks the event taps and Accessibility the app needs |
| Rename to Annotake, internals included, in the Developer ID build | A search for "flipbook" is flooded with page-flip makers, and its domains are taken. Two names would confuse Fayzan and every agent working on the code. Permissions have to be granted again in that build anyway |
| Communities first, then one launch; building in public on X from now; creators after launch | There's no existing following, so start where developers already ask for this. Creator videos and referrals drove Wispr's growth; here they speed things up after launch |
| A small "annotake.app" mark in free-plan caption strips | Frames get dropped into Jira tickets and Slack threads, where teammates see them. Pro removes it. It doesn't change the image size, so it costs the agent nothing |

## 3. The name: Annotake

- **Annotake** is annotate + take: you take a recording, and each frame comes out annotated. "Send me an annotake" works as a noun.
- **Domain:** annotake.app. On 2026-09-30, annotake.com, annotake.dev, and the misspelling anotake.app were also unregistered.
- **Checked:** there's no GitHub project or Mac app with the name. A Figma plugin called Annotake exports design annotations; Fayzan decided it isn't a reason to change course. Search engines treat the word as a typo of "annotate" at first.
- **Fayzan's to-dos:** register annotake.app (and annotake.com), and run a USPTO search for "Annotake" in software (classes 9 and 42) before spending money on branding.
- **Names considered and dropped:**
  - Flipbook, because of its search results and domains.
  - Shown: it sounds like "shone" or "Sean" in conversation, a common word gets buried in search, and shown.dev is premium-priced.
  - Framecard: a Framer template and photo-frame greeting cards fill its search results.
  - Lookit: an App Store app and several others already use it.
  - ReproReel and StepFlip were clean, but Fayzan preferred Annotake.
  - The full list and the method are in the [research notes](../research-notes.md).

### 3.1 The rename

Everything switches, in the Stage 1 build (§5.2), because permissions get granted again in that build anyway.

| Today | After |
|---|---|
| Flipbook.app, `com.fayzanmalik.flipbook` | Annotake.app, `com.fayzanmalik.annotake` |
| `FlipbookCore`, `FlipbookCapture`, `FlipbookInput`, `FlipbookExport`, `FlipbookApp`, the `Flipbook` executable, and their test targets | `AnnotakeCore`, `AnnotakeCapture`, `AnnotakeInput`, `AnnotakeExport`, `AnnotakeApp`, `Annotake`, and theirs |
| `flipbook-replay` | `annotake-replay` |
| `~/Pictures/Flipbook`, the hidden `.flipbook` marker, and `.flipbook-tmp` | `~/Pictures/Annotake`, `.annotake`, and `.annotake-tmp` |
| `~/Library/Logs/Flipbook.log` | `~/Library/Logs/Annotake.log` |
| "Flipbook capture" in the `steps.md` header, and the "Flipbook Self-Test" window | "Annotake capture" and "Annotake Self-Test" |
| The repos `fayzan123/flipbook` and `fayzan123/flipbook-releases` | `fayzan123/annotake` and `fayzan123/annotake-releases` |
| `~/Documents/GitHub/flipbook` | `~/Documents/GitHub/annotake`. Claude's project memory moves with it |
| The local signing identity "Flipbook Local Signing" | "Annotake Local Signing", for development builds only; releases use the Developer ID |

- **Migration, once, at Annotake's first launch:**
  - If `~/Pictures/Flipbook` exists, the save location is still the default, and `~/Pictures/Annotake` doesn't exist yet, the folder is renamed.
  - Each capture's `.flipbook` marker becomes `.annotake`, wherever the captures are, so the 30-day cleanup keeps finding them.
  - Settings are copied from the old `com.fayzanmalik.flipbook` domain, except the first-run state (`firstLaunch.v1`, `loginItem.initialized`), because permissions have to be granted again.
- **Docs:** the spec, backlog, research notes, and session guide switch to Annotake. The dated plans and checkpoint logs keep their text, with one line at the top saying they were written when the app was called Flipbook.
- **Friends on the early install:** the same install command installs Annotake and removes Flipbook.app. The old command keeps working: GitHub redirects renamed repos, which is checked at the rename, and a stub stays at the old address if it doesn't.

## 4. The business model

- **Free:** the whole app as it is today, window recording included, with:
  - **A soft limit of N recordings a week.** A recording counts when it's saved; cancelled and discarded ones don't. Past N, recording still works, and each card says it's over the free limit and offers Pro or an invite.
  - **A hard stop at 2.5×N.** Pressing the trigger shows the offer (upgrade, invite someone, or wait for the reset) instead of recording.
  - **A counter in the pill and the menu for the last 3 recordings before each limit,** and not otherwise.
  - **The limit is checked only when a recording starts,** so a running recording is never cut off.
  - **No limit when offline, or when the plan can't be checked.**
  - **A weekly reset,** every Monday at midnight, the user's local time.
  - **The "annotake.app" mark** in the caption strip.
- **Setting N:** from the beta's data, it's the number that about 3 in 4 weekly users stay under. The starting guess is 10, which puts the hard stop at 25.
- **Pro:** unlimited recordings, no mark, and MP4 with system audio and the microphone. MP4 asks for the microphone only the first time someone uses it. Later candidates: "save the last 30 seconds", voice narration, and region capture ([backlog](../v2-backlog.md)).
- **Referrals:** a personal invite link in the menu. The friend gets 30 days of Pro at sign-up. The referrer gets a month of Pro once the friend has made 3 recordings.
- **No trial at sign-up.** Add one once Pro has something people can see, like MP4.
- **Pricing:**

| Plan | Price |
|---|---|
| Pro | $9 a month, or $72 a year, shown as "$6/month billed yearly" |
| Founding members (beta, week 3) | $36 a year, for as long as they stay subscribed |
| Launch week | the first year at half price ($36), then $72. The for-life price stays exclusive to beta founding members |
| Later | students 50% off with a school email; team plans once companies ask |

- **Why push the yearly plan:** Polar takes 5% plus 50¢ per charge. That's 11% of a $9 month but 6% of a $72 year.
- **Comparable prices on 2026-09-28:** Clipy $9 a month or $72 a year, AI, Look! $20 a year, Raycast Pro $10 a month, Wispr Pro $15 a month. Annotake competes on how it feels (one key, any app, frames that explain themselves) and on privacy, not on price.

## 5. Stage 1: the friends round

- **Who:** 3–5 friends and classmates who code, plus coworkers once Fayzan has checked his employer's rules. Ideally one is on macOS 27, watched over screen share.
- **What it answers:** can someone who isn't Fayzan install and use it without help, and what breaks on Macs that aren't his?

### 5.1 The early install (done 2026-09-30)

- **The repo:** [github.com/fayzan123/flipbook-releases](https://github.com/fayzan123/flipbook-releases) is public and holds only a README, `install.sh`, and release zips. Release `build-9d9b3b0` is commit 9d9b3b0, built after `make test` (322 tests) and `make selftest` passed.
- **The command:** `curl -fsSL https://raw.githubusercontent.com/fayzan123/flipbook-releases/main/install.sh | sh`
  - **What it does:**
    1. checks for Apple silicon and macOS 15 or later;
    2. downloads the latest release and verifies its signature;
    3. quits a copy that's running;
    4. installs to `/Applications`, or to `~/Applications` on a Mac without admin rights;
    5. removes a copy in the other Applications folder;
    6. opens the app.
  - **The same command updates it.**
  - **No quarantine flag.** Files that `curl` downloads don't get one, so Gatekeeper doesn't block the self-signed app.
  - **Permissions survive updates,** because every build is signed with the same local certificate.
  - **For testing,** `FLIPBOOK_INSTALL_DIR=<folder>` installs there and quits and opens nothing.
- **The zip** is made with `ditto -c -k --keepParent --norsrc --noextattr --noacl`. That leaves out the `._` AppleDouble entries `make zip` packs in, which carry iCloud's tags and the provenance attribute.
- **Limits:**
  - It's today's build, and Apple silicon only.
  - It's only for people who know Fayzan. A stranger shouldn't paste a command from someone they don't know, so the beta waits for the notarized download.
- **New builds for friends:** a new GitHub release on the same repo, until `make release` exists (§5.2).

### 5.2 The Stage 1 build

One long unattended session, then one checkpoint. It lands while friends use the early install, and they move to it with the same command.

1. **The rename to Annotake** (§3.1), first, so everything after it uses the new names.
2. **Developer ID signing and notarization:** the hardened runtime (already on), a secure timestamp, `notarytool`, and stapling. The Command Line Tools already include `notarytool` and `stapler`, so Xcode isn't needed.
3. **A disk image** with the drag-to-Applications arrow.
4. **An app icon.**
5. **Version numbers** in place of the fixed 0.0.1.
6. **Sparkle 2 auto-updates:**
   - updates signed with an EdDSA key, whose private half stays in the keychain and never goes in the repo;
   - an update feed hosted in `annotake-releases`;
   - a daily check that sends only the app's version, with no system profile;
   - "Check for Updates…" in the menu.

   This is the app's first network call.
7. **Intel as well as Apple silicon** in one app, smoke-tested on Fayzan's Mac through Rosetta.
8. **A new first run, like Wispr's:**
   - what Annotake does, with a short looping demo;
   - the three permissions one at a time, each with a one-line reason, the line "it sees your screen only while you record; nothing you record leaves your Mac", and a picture of where to click in System Settings;
   - a practice run in the same window: double-tap Right ⌘, click a few buttons, double-tap again, and drag the card into a drop box, followed by "next time, drag it into Claude Code, Cursor, or ChatGPT";
   - an offer to move Annotake to Applications if it was opened from somewhere else;
   - no sign-in yet, but the flow leaves a slot for it before the permissions.
9. **Send Feedback in the menu:** an email to Fayzan with the version, the macOS version, the permission states, the recent log, and the latest crash report if there is one. The log never holds button names, window titles, or keys.
10. **`make release`:**
    - builds, signs, notarizes, and staples;
    - makes the disk image and a clean zip;
    - publishes a release to `annotake-releases` and updates the Sparkle feed.

    `make zip` switches to the clean zip as well.

**Fayzan's part at the checkpoint:**
- **Enroll** in the Apple Developer Program as an individual, as early as possible. New accounts have had notarization stuck for days.
- **Create the Developer ID Application certificate and the notarization credentials.** Both need his Apple ID; the session prepares the certificate signing request.
- **Install from the disk image** the way a stranger would, and grant the permissions again for the new signature and bundle ID.
- **Judge** the icon and the first run.

**Done when:**
- at least three people have installed it and recorded without help;
- whatever blocked them is fixed;
- at least two have used it on real work.

After that, a 15-minute chat with each: what they used it for, what confused them, and how disappointed they'd be if it went away.

## 6. Stage 2: the beta

- **Who:** 20–30 developers who use AI coding agents on a Mac, at least half of them strangers. Strangers are the real test, because they don't owe Fayzan anything.
- **Where they come from:**
  - a landing page at annotake.app with the 20-second video, three lines (one key, any app, nothing you record leaves your Mac), and a "Join the beta" email box;
  - one helpful post or comment where people already ask for this: Claude Code's video-input request, Cursor's forum thread, r/ClaudeAI, r/cursor, and AI-coding Discords;
  - two waves of invites a week apart, so support keeps up;
  - posting on X, a habit that starts now: the demo first, then what the beta teaches.
- **What gets built,** with its own design and plan, during the friends round:
  - sign-in with Google, GitHub, or Apple on Supabase, in the first run's slot;
  - the daily counts in §8;
  - the landing page, the waitlist, and a short privacy policy;
  - the founding-member checkout ($36 a year) through Polar, matched to the account by email.

  Everything stays free and unlimited; the server only counts.
- **The bars for moving on to Stage 3:**

| Measure | Bar |
|---|---|
| Signed in, granted all permissions, and recorded, all on day one | 70% |
| Still recording in week 3 or 4 | 40% of those who got that far |
| "Very disappointed" if Annotake went away, in the week-3 survey | 40% |
| Founding members | 5, at least 2 of them strangers |

- **It also sets N,** from how many recordings people make a week, and **checks the $9 price** with four survey questions: at what price would it feel too cheap to trust, a bargain, getting expensive, and too expensive.
- **If a bar is missed:**
  - **Day one:** fix the first run and invite another wave.
  - **Still recording, or "very disappointed":** talk to the people who stopped. If it doesn't turn around, Fayzan decides between iterating and releasing it as open source for the reputation.
  - **People stay but don't pay:** lower the price or rethink Pro before building the paywall.
- **Length:** the week-3-or-4 bar needs at least three weeks from the first wave. To move faster, shorten that bar, to week 2 for example.

## 7. Stage 3: the paywall and the launch

**What gets built.** The paywall waits until the beta's bars are met; anything that doesn't depend on them, like MP4, can start earlier.
- **Plans on the server:** free, Pro, and founding, with the weekly counts and limits from §4 enforced from the server's counts.
- **In the app:**
  - the counter near each limit;
  - the over-the-limit note on the card, with Upgrade and Invite;
  - the offer on the pill at the hard stop;
  - Upgrade opens Polar's checkout, and Settings shows the plan with a link to manage it.
- **Referrals:** the invite link in the menu, credited as in §4.
- **Pro's features.** MP4 gets its own design and plan. If it isn't ready, Pro launches with unlimited recordings and no mark, and MP4 follows.
- **The free-plan mark** in the caption strip.
- **The website:**
  - pricing, the download, an FAQ on permissions and privacy, and a changelog;
  - Sparkle's update feed moves there.
- **Homebrew:** `brew install --cask` from Fayzan's own tap.

**Launch week.** There's one shot, so launch only once the first run is smooth and the paywall works.
- **Day 1:** Product Hunt, plus an email to the waitlist and the beta testers.
- **Day 2:** Show HN.
- **Days 2–4:** r/ClaudeAI, r/macapps, r/cursor, developer newsletters, and curated "awesome" lists on GitHub.
- **All week:** 3–5 short videos on X, LinkedIn, and YouTube Shorts, covering Claude Code, Cursor, ChatGPT, a drop into Jira, and MP4.
- **The launch offer** from §4.

**After launch:**
- Referrals and the frame mark do the ongoing work.
- **Creators:** an affiliate program paying 25% of revenue for the first year (Wispr's terms), and free Pro for AI-coding creators.
- **Students:** 50% off with a school email.
- **Building in public:** MRR posts on X.
- **Team plans,** once companies ask.

## 8. Measurement and privacy

- **What the server stores, from Stage 2:**
  - an email, a plan, and referral credits;
  - per day: recordings started, saved, and discarded; frames kept; screen or window; whether a card was dragged somewhere; the app and macOS versions; which permissions are granted.
- **Never sent:** frames, captions, `steps.md`, window titles, app names, button names, keys, typed text, and file paths.
- **The log stays local.** It reaches Fayzan only through Send Feedback, when the user sends it.
- **A plain-language privacy policy** is published before the beta.
- **"Why does a local tool need an account?"** will come up, on Hacker News especially. The answer, in the FAQ and the launch post: the account holds your plan and a count; nothing you record leaves your Mac.

## 9. Risks

- **The platforms build it in.**
  - Claude Code's computer use can already take its own screenshots and reproduce a bug. Claude Code's video-input request is still open.
  - *Defense:* speed, and the niche the platforms don't cover: any app, one key, nothing leaves your Mac, and frames any agent can read.
- **Cheap and free rivals:** AI, Look!, Clipy, Deiko, BugReel, claude-video, Pointer, and Loom Video Prompts. Fayzan's review on 2026-09-30: none of them is good yet.
  - *Defense:* how it feels, privacy, and the tuning that only comes from real use.
- **Fayzan's job.** Check two things:
  - the employment contract (who owns what he builds, and whether side businesses are allowed), before anyone pays in the beta;
  - the IT rules, before inviting coworkers.
- **The name reads as a typo of "annotate" at first.** The domain, the launch links, and "Annotake for Mac" fix it over time.
- **macOS:**
  - the monthly Screen Recording re-prompt stays;
  - macOS 27 is untested until the friends round;
  - Sparkle lets fixes ship fast.
- **Notarization delays for new Apple accounts.** Enroll as early as possible.
- **Support load for a solo developer:**
  - Polar's customer portal lets people manage or cancel their plan themselves;
  - Send Feedback with diagnostics keeps bug reports short.

## 10. Open items

- **Decided by the beta:** N and the final price.
- **Decided at the Stage 1 checkpoint:** the icon and the look.
- **The Stage 2 design:** the Supabase schema, the sign-in flow in the app, how counts are uploaded, and the landing page.
- **MP4:** its own design and plan.
- **When their stage comes:** team plans, how school emails are checked, and the creator program.
- **Fayzan's checks:** the employment contract and IT rules, and the USPTO search for "Annotake".
- **The address Send Feedback writes to.** It ships inside the app, so Fayzan picks it before the Stage 1 build, for example a new address at annotake.app.

## 11. Sessions

1. **Now: the Stage 1 plan,** with `superpowers:writing-plans`. It covers §5.2 in one long unattended session and one checkpoint.
2. **Next: the Stage 2 design and plan,** so that build runs during the friends round.
3. **During the beta: the MP4 design and plan.**
4. **Once the beta's numbers look on track: the paywall design and plan** (Stage 3).

## 12. Spec changes

Made in [../spec.md](../spec.md) alongside this doc:
- **Status line:** notes the rename to Annotake and points here.
- **§2:**
  - "Built for Fayzan's own workflow first" now covers other developers too, with setup as easy as Wispr Flow or Loom.
  - Competitors still don't drive product decisions, but pricing and positioning look at them.
  - "Never touches the network" becomes "Nothing you record leaves your Mac", with what goes over the network and from which stage.
- **§9:** the early install, and the notarized path to come.
- **§10:** a new M6, distribution, pointing here.
- **§11:**
  - the signed download is no longer "not in v1";
  - network access is limited to what this design adds;
  - MP4 is noted as planned for Pro.
- **§13:** decision-log rows for the main decisions.

The spec's own Flipbook → Annotake rename happens in Stage 1's rename task, with the code.

## 13. Not in this design

- The Stage 2 and Stage 3 builds in detail. Each gets its own design.
- MP4 in detail. It gets its own design.
- Team plans, Windows, and Setapp.
- The Mac App Store, which isn't possible because of its sandbox.
- Open-sourcing any part of the app.
