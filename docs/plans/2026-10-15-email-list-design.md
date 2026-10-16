# Annotake email list design: an email in the first run

**Status:** approved 2026-10-15 in conversation; built through Task 10 on branch `email-list`, 2026-10-16 (§13 has what changed); at Checkpoint 5, cut to collecting addresses only, for now (§13) · **Plan:** [2026-10-15-email-list-build.md](2026-10-15-email-list-build.md) · **Related:** [distribution design](2026-09-30-distribution-design.md) §6 (Stage 2 sign-in), §8 (privacy); [landing page design](2026-10-01-landing-page-design.md) §4.4 (CASL), §5.3 (the link function), §6 (robustness)

**For now (decided 2026-10-16, §13):** the list only collects addresses, which count Annotake's users. Nothing is emailed to it yet, so there's no mailing address: the step has no box, the site sends no welcome email, and nothing is broadcast. The parts marked *parked* below come back, with the address, before the list's first email.

## 1. Goal

- **What it is:** one new first-run step that asks for an email, one small Vercel function that adds it to a Resend list, and one that unsubscribes. Resend is the list.
- **Why:** today a download has no bridge back to Fayzan. Before the announcements, every copy should leave him a way to reach its user: when something goes wrong (a security fix, a broken update), and to ask for feedback.
- **Done means:**
  - a new user can't finish the first run without an email, and an existing copy asks once after its update;
  - every address lands in Resend with its topics and a consent record;
  - every email Annotake sends can be unsubscribed from, in one click where the mail app shows an Unsubscribe button;
  - the privacy policy and the Terms say what's stored, and Fayzan has accepted them;
  - every automated test passes.
- **Principles:**
  - **Ease of use first.** One field, one optional box, one button. Nothing waits on the network, and no inbox trip.
  - **Nothing you record leaves your Mac** stays true: the app sends an email address, one choice, and its version, never anything recorded.
  - **The smallest legal surface:** no database of our own, consent asked only for what needs it, and unsubscribes that apply at once.

## 2. Decisions

| Decision | Why |
|---|---|
| The email is asked for in the app's first run, not on the site | The site's download is a public GitHub link, and a forwarded `.dmg` skips any site gate. Every copy passes through the first run, and existing copies through Sparkle. It uses the slot `OnboardingModel` already keeps for Stage 2's sign-in |
| The email is required; feedback and news are a separate, unticked box | CASL asks for consent separately and never pre-ticked, and the EU's GDPR doesn't count consent that's a condition of getting something. Security and update notices are exempt from consent under CASL ([s. 6(6)(c) and (f)](https://laws-lois.justice.gc.ca/eng/acts/E-1.6/FullText.html)), so the address itself can be required |
| A typed email now, no confirmation step | No inbox trip in setup. Typos and fakes bounce and are dropped. Stage 2's sign-in (Google, GitHub, Apple) verifies addresses later, which is when the paywall needs it (§9) |
| Existing copies ask once, and recording waits for it | The list should reach every user, not only new ones. One field once is the smallest ask |
| Resend, not Mailgun | The site already sends through Resend, with its DNS records and key set up. Its contacts, topics, and hosted preference page do the unsubscribe work. One provider, no new DNS |
| Resend is the list: no database of our own | Nothing to scale, back up, or leak. Stage 2's Supabase arrives with sign-in, and matches contacts by email |
| Two topics: **Important notices** and **Feedback and news** | People can drop the second and keep the first, or leave both. Resend shows a topic page from every broadcast's unsubscribe link |
| An unsubscribe never gets undone by the app | A contact who unsubscribed stays unsubscribed even if they type the address again. Only Fayzan, by hand, can change that |

## 3. The app

### 3.1 The email step

A new `OnboardingModel.Step.email`, right after `.welcome` in the `.firstRun` steps. `.fixPermissions` doesn't have it.

```
  Stay in the loop
  ┌──────────────────────────────┐
  │ you@example.com              │
  └──────────────────────────────┘
  We'll email you about security fixes and important
  changes to Annotake. Every email has an unsubscribe link.

  ☐ Also email me feedback requests and news

  From Fayzan Malik · [mailing address] · annotake.app · Privacy policy
                                        [ Continue ]
```

*Parked* (§13): the box and the mailing address. For now the step shows the field, the notice, and "From Fayzan Malik · annotake.app · Privacy policy", and saves every address with `news: false`.

- **The field:** the same rules as the site's `email.js`, on the address and on its lowercase key, as `/api/subscribe` applies them (`EmailConsent.isPlausible`): trimmed, at most 254 characters, no line breaks, a plain address pattern. Continue is greyed out until it matches, and Return presses it when it's enabled. The field has focus when the step opens.
- **The editing keys** (⌘V, ⌘C, ⌘X, ⌘A, ⌘Z) work through a main menu that never shows (`EditMenu.swift`): a menu-bar app has none of its own.
- **The box** starts unticked, every time.
- **The footer line** is what CASL wants on a consent request: who's asking, a mailing address, and a contact (the web address counts). The policy link opens `annotake.app/privacy`.
- **Continue** saves the address on the Mac (§3.4) and moves straight on to the permissions. The send happens in the background.
- **The wording is versioned:** the step's text and the box's label are one constant with an id, `consent-2026-10-15` (`EmailConsent` in the app). The id goes with the address, and the same text lives in `site/api/_lib/consent.json`, so the consent record names exactly what the person read. A test checks the app's and the site's copies match.
- **A wording change** adds a new version to `consent.json` and moves its `current`; a shipped version is never edited. Deploy it to Production and see `make site-smoke URL=https://annotake.app`'s consent check pass (400, not 422) before releasing the app that sends the new id. Until then the site answers that id 422, and every new copy's address waits on the app's backoff (§3.4).

### 3.2 Existing copies

- A new mode, `.emailOnly`, with the steps `[.email, .done]`. At launch, a copy whose first run is complete but has no saved address opens the onboarding window in this mode.
- **At launch** (`OnboardingModel.launched(hasAddress:)`):
  - a finished pass of any mode with no address becomes the `.emailOnly` pass, and shows;
  - a first run in progress goes on past the email step if an address is saved by now. Without one, a first run that's past where the step now goes, as an update can leave one, goes back to it, and after the step skips what's done again. One left at You're set gets the `.emailOnly` pass instead, rather than show the drop box again;
  - an `.emailOnly` pass in progress shows, unless an address is saved by now: then it finishes, with no window;
  - a Fix permissions… pass in progress shows as before.
- Closing the window on the email step brings it back at the next launch.
- **Until an address is saved, nothing records:**
  - a hold records nothing, and at its reveal (800 ms by default) the pill shows "Add your email to start recording" with an **Open** button, the way it shows Open Settings. A Right ⌘ shortcut ends before the reveal, so it shows nothing;
  - a double-tap or the menu's Start shows the message at once, and the menu keeps offering Start Recording;
  - no recording is ever cut off: the check happens before one starts, while idle.
- **Open** (`OnboardingController.showForEmail()`) brings the window forward under the launch rules, except that a Fix permissions… pass in progress gives way to the `.emailOnly` pass, since the person asked for the email. Settings' Add… does the same (§3.3).
- **"Fix permissions…"** starts its own pass over a pending `.emailOnly` one, which comes back with the pill's Open or at the next launch. A first run or a Fix permissions… pass in progress stays where it is.

### 3.3 Settings

- **Settings → General** gets an **Email** row, in its own section at the end:
  - with an address saved: the address, and a **Change…** button that opens a sheet titled "Change your email": the same field (without the box), a Privacy policy link, Cancel, and Save. Saving sends the new address the same way, with the person's earlier box choice and the id of the wording it was made under;
  - with none: **Not set**, and an **Add…** button that opens the email step, as the pill's Open does (§3.2), so a first address always comes with the notice, the box, and the footer.
- The email isn't a setting: Restore Defaults never touches it.
- A change to the same address in other capitals or padding sends nothing, and so does a change back to an address the site has already taken from this Mac (§3.4): the site can't tell a stored choice sent again from a fresh tick of the box.
- The old address isn't touched: a typo bounces, and a real old address can unsubscribe from any email. That avoids a call that could unsubscribe someone else's address.
- The feedback choice isn't in Settings. It's changed from the link in any email.

### 3.4 Saving and sending

- **Saved** in `UserDefaults` under `email.v1`: `{address, news, consent, savedAt, sent}`.
- **Also saved,** under `email.sentKeys.v1`: a SHA-256, in lowercase hex, of the key of each address the site has answered 200 for from this Mac, so a Change… back to one of them posts nothing (§3.3). No old address is kept in the clear.
- **Sent** by a small `EmailSignup` type: `POST https://annotake.app/api/subscribe` with JSON `{email, news, consent, appVersion}`. Nothing else: no device id, no macOS version. It sets its own `User-Agent` (`Annotake/<version>`) and `Accept-Language: en`, and sends no cookies, since URLSession's own headers would name the CFNetwork and Darwin versions and the region.
- **When:** right after Continue, then at each launch (last, after the update check) and on a backoff (1 min, 5 min, 30 min, then every 6 hours) until the site takes or refuses it, one post at a time:
  - 200: `sent = true`, done.
  - 400 (`invalid`, an address the site won't take): the app clears the address and asks again at the next launch, or when the pill's Open or Settings' Add… brings the step back.
  - 422 (`request`, a request the site can't read, such as a consent id from an app newer than the deployment), 429, 5xx (Vercel's 504 included), a timeout, or no network: try again later.
- **Logged** as `email: sent`, `email: invalid`, or `email: retry later` only, never the address, matching the log's rule.
- The app's network calls become two: the daily update check, and this one.

## 4. The server

### 4.1 `site/api/subscribe.js`

Plain Node, no packages, built like `link.js`, and sharing its address check (`assets/email.js`). The Resend call, with its timeout and retries, is `api/_lib/resend.js`, shared with `unsubscribe.js`. Vercel runs nothing under `_lib` as a function.

- **Accepts** only `POST` with `application/json`, at most 2 KB: `email` (string), `news` (boolean), `consent` (any id in `_lib/consent.json`, so an older app's request still goes through), `appVersion` (1–32 characters).
  - A request it can't read (not JSON, over 2 KB, an unknown consent id, a missing or mistyped field) is `422 request`, which the app retries.
  - Only an address it won't take is `400 invalid`, the one answer that makes the app clear the address: an implausible one, or one whose lowercase key isn't plausible (İ lowercases to two characters), since its unsubscribe link couldn't work.
- **Then,** keyed by the address's key (trimmed, lowercased, NFC):
  1. Looks up the contact (`GET /contacts/{key}`).
  2. **Not there:** creates it (`POST /contacts`), with:
     - the segment every broadcast goes to (`RESEND_SEGMENT`, §4.3);
     - **Important notices** subscribed, and **Feedback and news** subscribed only if `news` is true;
     - the consent record as properties: `consent_at` (UTC time, when the request arrives), `consent_wording` (the id), `consent_source` (`app`), `app_version`.

     Then it sends the welcome email (§5.1), unless `MAILING_ADDRESS` isn't set.
  3. **Already there and unsubscribed:** changes nothing, sends nothing, and answers 200. Anything but a clear `unsubscribed: false` counts as unsubscribed. An unsubscribe is never undone by the app (§2).
  4. **Already there and subscribed:** if `news` is true and the contact isn't on Feedback and news (`GET /contacts/{key}/topics`), it updates the consent properties, then adds that topic, so nobody is on it under an older consent record. It never removes a topic or touches a contact's segments. It sends no welcome.
- **Answers:** `200 {ok: true}`, `400 invalid`, `422 request`, `429 busy` (Resend's quota or rate limit), `502 send`, and `405` to a `GET`.
- **Time:** each Resend call is at most two attempts of 4 s, and a request makes up to four calls in a row. Resend answers in well under a second, so a request fits Vercel's 10 s limit. If a struggling Resend pushes one past it, the app gets a 504 and retries, and the retry finishes the contact's part; a welcome cut off then is lost, as §5.1 says.
- **Logs** one `subscribe: <outcome>` line, never the address: `added`, `added welcome skipped no address`, `added welcome already sent`, `added welcome failed <reason>`, `kept`, `kept unsubscribed`, `news added`, `invalid request`, `invalid address`, `dry run`, `busy <reason>`, `failed <reason>`, `failed not configured`, or `failed error <name>`.
- **Preview deployments** use `EMAIL_DRY_RUN=1`, as `link.js` does: the checks run, and nothing is created or sent.
- **The Resend calls** were confirmed against Resend's API reference while planning and building (§13): `POST /contacts` takes `{email, properties, segments: [{id}], topics: [{id, subscription}]}`, Retrieve Contact returns no topics, and `PATCH /contacts/{key}/topics` changes them.

### 4.2 `site/api/unsubscribe.js`

Broadcasts get Resend's own unsubscribe link and preference page. The welcome email is sent through `/emails`, which gets no Resend unsubscribe page, so it needs its own link (§13, change 1):

- `GET /api/unsubscribe?e=<email>&s=<signature>` shows a small page in the site's style, headed "Unsubscribe": "Unsubscribe {email} from all Annotake emails?" with one button. A `GET` never unsubscribes, so a link scanner or a prefetch can't.
- `POST` to the same URL sets the contact `unsubscribed: true` (`PATCH /contacts/{key}`). The page's button gets "You're unsubscribed." back; a mail app's one-click `List-Unsubscribe-Post`, with any body or none, gets a blank 200. The signed link alone decides, never the body. A contact Resend doesn't have counts as unsubscribed.
- A link that doesn't verify answers 400 ("This unsubscribe link isn't valid."), and a Resend failure 502 ("We couldn't unsubscribe you right now."). Every page sends no referrer and asks not to be indexed, since its URL holds the address.
- `s` is an HMAC-SHA256 of the address's key (trimmed, lowercased, NFC) with `UNSUBSCRIBE_SECRET`, so nobody can unsubscribe an address they don't have a link for. Links never expire, well past CASL's 60 days, so the secret is set once and never replaced (§4.3).
- **Logs** one `unsubscribe: <outcome>` line, never the address: `shown`, `done`, `done already gone`, `invalid`, `dry run`, `failed <reason>`, `failed not configured`, or `failed error <name>`.

### 4.3 Secrets and settings

- **`RESEND_CONTACTS_KEY`:** a Resend key with full access, used only by these two functions. `link.js` keeps its sending-only `RESEND_API_KEY`.
- **`RESEND_TOPIC_NOTICES` and `RESEND_TOPIC_NEWS`:** the two topic ids.
- **`RESEND_SEGMENT`:** the id of the one segment every contact joins and every broadcast goes to (§5.2). Resend sends a broadcast to a segment, and its topic only narrows it, so a contact in no segment would get none.
- **`UNSUBSCRIBE_SECRET`:** 32 random bytes (`openssl rand -hex 32`). It's set once and never replaced: every welcome email already sent carries a link signed with it, and a new value would make them all answer 400. Keep a copy, since Vercel never shows a Secret again, and carry the same value to a new project or team. If it must ever change, accept the old one beside the new.
- **`MAILING_ADDRESS`:** the CASL mailing address for the welcome email's footer. Without it, the contact is still added, and the welcome is skipped.
- `/api/subscribe` needs all but `MAILING_ADDRESS`, and answers 502 `failed not configured` without them. `/api/unsubscribe` needs the secret to check any link, in dry run too.
- All of them are set in Vercel's Production settings only, so on a Preview deployment `/api/unsubscribe` answers 502.
- The WAF rate-limit rule's path changes from `/api/link` to `/api/*`, so it covers all three functions with Hobby's one rule.

## 5. The emails

### 5.1 The welcome email

*Parked until the list has a mailing address* (§13): with no `MAILING_ADDRESS`, `/api/subscribe` adds the contact and sends no welcome.

- **From** `Fayzan from Annotake <hello@annotake.app>`, on the domain Resend already sends for. **Reply-to** `Feedback.address`, Fayzan's personal Gmail (decided 2026-10-15: no Google Workspace, and no inbox at annotake.app). Reply-to is only a header, so sending stays on Resend and replies land in Gmail. Every recipient sees the Gmail address.
- **Subject:** "Welcome to Annotake".
- **Body,** as plain text and simple HTML like the link email:
  - a one-line thank-you;
  - the shortcut: hold Right ⌘, click through it, let go, then drag the card;
  - "Reply to this email any time: I read every one";
  - what they'll get: important notices, plus feedback requests and news if they ticked the box;
  - "Didn't sign up? Unsubscribe" with the §4.2 link.
- **Footer:** "Fayzan Malik · [mailing address] · annotake.app", the privacy policy link, and the unsubscribe link.
- **Headers:** `List-Unsubscribe` with the §4.2 URL, and `List-Unsubscribe-Post: List-Unsubscribe=One-Click`. The request to Resend carries an `Idempotency-Key`, `welcome-<SHA-256 of the key>`, so a retried call sends it once; Resend keeps the key for 24 hours.
- Sent once, when the contact is created, and only with `MAILING_ADDRESS` set (§4.3). If sending fails (the daily quota, or Resend is down), the contact stays and the welcome is skipped. No later request sends it, so nobody gets it twice.
- **The wording** is pinned word for word in `site/tests/unit/welcome.test.js`, for Fayzan to accept at Checkpoint 5.

### 5.2 Broadcasts

*Parked until the list's first email* (§13).

Fayzan sends these from Resend's dashboard:
- **Every broadcast goes to the one segment (§4.3) and picks one topic.** Security fixes and broken updates go to Important notices; feedback requests, surveys, and news go to Feedback and news. When in doubt, Feedback and news. Resend's broadcast editor asks for a segment, and offers no "all contacts".
- **One saved footer** on every broadcast: "Fayzan Malik · [mailing address] · annotake.app" and Resend's unsubscribe placeholder, which opens the topic page.
- **Reply-To is the Gmail address** (`Feedback.address`) on every broadcast: annotake.app receives no mail, and /privacy tells people to reply to any email from the list.
- **Open and click tracking stay off** for annotake.app: /privacy mentions no tracking.
- Resend's docs don't confirm that it adds the one-click `List-Unsubscribe` headers to broadcasts, which Gmail and Yahoo require from bulk senders, so Checkpoint 5 checks a test broadcast's raw headers.

## 6. Legal

### 6.1 CASL

| CASL needs | Where it's met |
|---|---|
| Consent asked separately, never pre-ticked | The unticked box, only for Feedback and news (§3.1) |
| Who's asking, a mailing address, a contact, and that consent can be withdrawn | The step's footer line and "Every email has an unsubscribe link" |
| In every email: the name, the mailing address, a contact, and an unsubscribe link | The welcome email's footer (§5.1) and the broadcast footer (§5.2) |
| Unsubscribe works for 60 days, honoured within 10 business days | Links that never expire; Resend applies an unsubscribe at once |
| Proof of consent | The contact's consent properties, plus the wording kept in `site/api/_lib/consent.json` under its id |
| Notices are exempt from consent but still need the ID and unsubscribe | Important notices carry the same footer and link |

- **The mailing address** is a PO box or a virtual mailbox, never Fayzan's home. It has to exist before the release with this step ships, because it's on the step itself.

### 6.2 Everyone else

- **The EU and UK:** Important notices rest on legitimate interest (telling users about their software's security), and Feedback and news on consent. The app asks for only what it needs: an address and a choice.
- **The US (CAN-SPAM):** met by the same footer and unsubscribe.

### 6.3 Privacy policy and Terms

*Changed at Checkpoint 5* (§13): for now /privacy says the address counts Annotake's users and gets important notices, with no welcome email and no Feedback and news. What follows is the list's full version, for when it sends.

The privacy policy changes:
- **The short version:** "We get your email address in the app, to send you important notices and, if you agree, feedback requests and news." Nothing you record leaves your Mac.
- **What's stored:** the email, the two topic choices, when and how you agreed, and the app version. It's stored in Resend, in the US, under US law.
- **How long:** until you ask for it to be deleted. After an unsubscribe the address is kept, marked unsubscribed, as proof and so it's never emailed again, unless you ask for deletion.
- **Unsubscribing:** "You can unsubscribe from any email with its unsubscribe link, or with your mail app's Unsubscribe button where it shows one. To stop only feedback requests and news, use the unsubscribe link in one of them." It promises no single click: the welcome's own link asks first, and a broadcast's opens Resend's topic page.
- **Your rights:** to see, correct, or delete it, by replying to any email from Annotake's email list (the link email comes from a no-reply address), or with Send Feedback.
- **What the app sends:** the email, the choice, and the app version, once, and again only after a change of address in Settings.
- **Gone:** "we keep no list" and "no stored email addresses".

The Terms gain one line: using Annotake means getting important notices, and any email can be unsubscribed from.

## 7. Robustness and scale

| Part | Under load | If it fails |
|---|---|---|
| The email step | Local only | Nothing to fail: the address is saved on the Mac first |
| Sending from the app | One call per user, ever (plus a Change) | Retried on a backoff; the app never waits on it |
| `/api/subscribe` | A Vercel function; Resend's API takes 10 requests a second, raised on request | `422`, `429`, `502`, or Vercel's `504`; the app retries later, and a retry after a partial success finishes the contact's part, though a welcome cut off is lost (§5.1) |
| The welcome email | Shares Resend's free 100 emails a day with the link email | Skipped; the contact is still added |
| The list | Resend's free plan holds 1,000 contacts | Resend emails Fayzan near the limit; see the upgrade table |
| Fake sign-ups | The WAF rule (10 requests per 10 minutes per IP), and the welcome's "Didn't sign up?" link | Next step: BotID on `/api/*`, free, after checking it sets no cookies, and keeping `/api/subscribe` open to the app's request, which isn't a browser's: otherwise every copy retries every 6 hours |
| Bounces | Resend marks hard-bounced addresses and stops sending to them | — |

**When to upgrade** (Resend's prices on 2026-10-15):

| When | Do | Cost |
|---|---|---|
| Before this release ships | A PO box or a virtual mailbox for the CASL address | about CA$100–300 a year |
| Sign-ups pass about 60 a day, or before a launch push | Resend Pro: no daily cap, 50,000 emails a month | US$20 a month (about CA$28) |
| The list passes about 800 contacts | Resend Marketing Pro, up to 5,000 contacts | US$40 a month (about CA$55) |
| Stage 2 | Sign-in replaces the email step (§9) | Supabase's free plan to start |

## 8. Testing

- **Swift unit tests:**
  - `OnboardingModel`: `.email` comes after `.welcome` in `.firstRun`, and isn't in `.fixPermissions`;
  - `.emailOnly` is `[.email, .done]`, and is chosen when the first run is complete but there's no address;
  - Continue is enabled only for a plausible address, using the same cases as the site's `email.js` tests;
  - `EmailSignup`'s outcomes: 200 marks it sent, 400 clears it, and everything else keeps it and backs off on the schedule;
  - recording is refused, with the pill message, while there's no address.
- **Site unit tests** (`site/tests/unit`, with a fake `fetch`, like `link.js`'s):
  - every answer of `subscribe.js`: new, new with news, existing, existing and unsubscribed, adding news, never removing it;
  - the welcome is sent only on create, and a failed welcome still answers 200;
  - dry run;
  - the unsubscribe signature: a wrong signature is refused, and `GET` never unsubscribes;
  - no log line ever holds an address;
  - the app's consent wording matches `site/api/_lib/consent.json`;
  - the app's exact request (`site/tests/subscribe-request.json`, which the app's tests check the app sends) is taken.
- **End to end** (`site/tests/pages/subscribe.spec.js`): the functions on the local server, in dry run.
- **By hand, at the end (§9):** a real sign-up from a fresh first run, the welcome email in Gmail with its one-click unsubscribe, a test broadcast to each topic, and unsubscribing from it.

## 9. Fayzan's part (all at the end)

*Cut at Checkpoint 5* (§13): the release that collects addresses needs only check 2's contact, with no welcome (Checkpoint 5's one real sign-up). The mailing address, the welcome, and checks 2–4's emails wait for the list's first email.

The steps, in order, are Checkpoint 5 in [../checkpoints.md](../checkpoints.md#checkpoint-5-the-email-list).
- **Get the mailing address** (a PO box or a virtual mailbox), and put it in the step (`EmailConsent.mailingAddress`), the welcome email (`MAILING_ADDRESS`), and the broadcast footer.
- **In Resend,** before Vercel's settings:
  - create the topics Important notices (default: subscribed) and Feedback and news (default: not subscribed);
  - create the four contact properties (§13, change 2) and the segment (§4.3);
  - create a full-access key;
  - save the broadcast footer.
- **In Vercel:** set `RESEND_CONTACTS_KEY`, `RESEND_SEGMENT`, the two topic ids, `UNSUBSCRIBE_SECRET`, and `MAILING_ADDRESS` in Production, and change the WAF rule's path to `/api/*`.
- **Read and accept** the step's wording, the welcome email, the Settings copy, and the privacy policy and Terms changes, and answer §13's open questions. A short review by a Canadian lawyer before the first email to the list is cheap insurance, but it isn't required to ship.
- **Try it:** a fresh first run, the welcome email, a test broadcast to each topic, and an unsubscribe.

**Resend works before this ships.** On 2026-10-15 a live `POST /api/link` to Fayzan's Gmail answered `502 send`, and Gmail had never received an Annotake email: the domain is verified and its DNS is right (DKIM, SPF and the bounce MX on `send.annotake.app`, DMARC `p=none`), but `RESEND_API_KEY` was never added to Vercel (Checkpoint 4, step 3). The release with the email step doesn't ship until each of these passes, in order:
1. **The link email:** with `RESEND_API_KEY` set, `POST /api/link` answers 200, and the email arrives in Gmail's inbox, not spam, with `spf=pass`, `dkim=pass` (`d=annotake.app`) and `dmarc=pass` in its Authentication-Results header. **Passed 2026-10-15** after the key was added: inbox, in the Updates tab.
2. **The list:** with §4.3's settings, a fresh first run creates the contact in Resend with the right topics and consent properties, and the welcome email passes the same checks.
3. **Replies:** replying to the welcome email from another address lands in Fayzan's Gmail.
4. **Unsubscribing:** the welcome email's one-click unsubscribe and a test broadcast's topic page both work, and an unsubscribed contact gets neither the next broadcast nor a second welcome after typing the address again.

**Stage 2, later:** sign-in takes the email step's place. A signed-in account is matched to its Resend contact by email: nobody is subscribed twice or asked again, and an existing copy is asked to sign in once.

## 10. Open items

- **The mailing address:** parked until the list's first email (§13).
- **The open questions for Fayzan** in §13: 3 and 5 at Checkpoint 5's copy review, and the rest with the list.

## 11. Changes to other docs

Made in the build (Task 3 for the site, Task 10 for the rest):
- **[spec.md](../spec.md):**
  - §2: the daily update check and the email sign-up are the app's two network calls;
  - §3.2 and §7: recording waits for an address;
  - §3.5: the main menu that never shows;
  - §3.6: the Email row in General;
  - §3.7: the email step after the welcome, and `.emailOnly`;
  - §6, §8, §9, and §11: the libraries' one network call, the log, the release guard, and what's out of scope;
  - §13: a decision-log row.
- **[distribution design](2026-09-30-distribution-design.md):** §8 privacy now includes an email from the app, ahead of Stage 2; §6 notes that sign-in replaces the email step.
- **[landing page design](2026-10-01-landing-page-design.md):** §1's "no stored email addresses" and §4.4's "no list is kept" point here, and so do §2, §4.2, §5.1, §5.2, §6, and §9. §5.2 has the new ignore step, and so does its plan.
- **The site:** `/privacy` and `/terms` as in §6.3, and `site/README.md`. No page copy said Annotake needs no email; the link form's "We'll send one email with the download link, and that's all." stays, since it's true of a link request.
- **[checkpoints.md](../checkpoints.md):** Checkpoint 5.
- **[The session guide](README.md):** the email list's entries.

## 12. Not in this design

- An email gate on the site; the download stays one click.
- Confirmation codes or a confirm-your-email link.
- Sign-in, accounts, or the paywall (Stage 2 and 3).
- Email preferences inside the app.
- Automated sequences beyond the one welcome email.
- Removing the old address when someone changes it.

## 13. Changes from planning and building

**Decided while planning** (the [plan](2026-10-15-email-list-build.md)'s "Changes from the design"); §3.2, §4.2, §4.3, and §9 above are updated to match:
1. **The welcome email's unsubscribe is ours, not Resend's.** Resend hosts unsubscribe pages only for broadcasts. For `/emails` it expects a `List-Unsubscribe` header pointing at your own URL, which accepts a `POST` (RFC 8058). So §4.2's `unsubscribe.js` is built, not optional.
2. **The contact's consent properties must exist in Resend first** (`POST /contact-properties`, type `string`). Creating them is a checkpoint step, not code.
3. **The mailing address is `MAILING_ADDRESS` on the site, and `EmailConsent.mailingAddress` in the app.** The app's starts as the sentinel `"[mailing address]"`, and `make release` refuses to run while it's still there. Without `MAILING_ADDRESS`, the function adds the contact but skips the welcome email, logging `subscribe: added welcome skipped no address`.
4. **A hold refused for a missing email shows its message only at the reveal (800 ms),** so a Right ⌘ shortcut never flashes it.

**Decided while building** (2026-10-15 and 16, on branch `email-list`), one line each with its reason. §3 to §9 above are updated to match.

*Task 1, the unsubscribe link and function (c236445):*
- Only the confirm page's button (a hidden `from=page`) gets the "You're unsubscribed." page. Every other `POST`, such as a mail app's one-click with any body or none, gets the blank 200 a mail app expects. The signed link alone decides, never the body.
- The secret is checked first, in dry run too, since no link can be checked without it. Only a real unsubscribe needs Resend's key, and dry run comes before that check, as in `link.js`.
- A known-answer test pins the signature scheme, since links never expire. `verifyEmail` takes only 64 lowercase hex characters and never throws; signing with an empty secret throws, since anyone could make such a link.
- `resend()` never throws, so a function can always answer. An empty or non-JSON 2xx is ok, an answer that breaks off counts as `network` or `timeout` and is retried, and a request that can't be built is `rejected`, with no fetch.
- Resend's 409 `resource_locked` (another request is changing the same contact) is retried once after 300 ms, as Resend's errors docs advise. The idempotency 409s aren't retried, and keep their names.
- `emailKey` in `assets/email.js` composes again after lowercasing, so a key is its own key and every address's link verifies: 460 letter-and-mark pairs failed before. Only rare addresses with a capital and a combining mark get another key, which changes `link.js`'s daily Idempotency-Key for them.
- A `+` in the link's `e` stays a plus, since an address never holds a space.
- The confirm page is headed "Unsubscribe", with the plan's sentence below it, where a long address has room. No page title holds an address.
- Every unsubscribe page sends no referrer and asks not to be indexed, because its URL holds the address.
- The local server answers 404 for any `api/` path with a `_` or `.` name and never runs it, as Vercel does. That also closed `..%2f` escapes out of `api/`.
- `link.js` is untouched: the new functions keep their own body reading and pages.

*Task 2, the subscribe function and the welcome email (0fd0320):*
- A contact's topics come from `GET /contacts/{key}/topics`, since Retrieve Contact returns none. Feedback and news counts as on only when it's listed as `opt_in`.
- For a subscribed contact who ticks the box, the new consent record goes on before the topic, so nobody is on Feedback and news under an older record, and a retry after a partial failure redoes both.
- `appVersion` must be 1–32 characters; an empty one is a request the site can't read.
- The address's lowercase key must pass the check too (İ lowercases to two characters), or the answer is 400, so no contact is made whose unsubscribe link would answer 400.
- When Resend answers the welcome with an idempotency 409 (its key already went with another payload, or that send is still under way), the function answers 200 and logs `subscribe: added welcome already sent`, as `link.js` does. Any other failure logs `subscribe: added welcome failed <reason>`.
- Anything but a clear `unsubscribed: false` from Resend counts as unsubscribed: when in doubt, nothing changes.
- A `MAILING_ADDRESS` that's unset, empty, or only spaces means none, so no welcome. Line breaks collapse, so the footer stays on one line.
- The no-address log line is `subscribe: added welcome skipped no address`, as Task 2's tests had it. Change 3 above had another form, now corrected in the plan.
- `consent_wording` is the id the request names, any version in `consent.json`, so an older app's record names the wording it showed.
- The welcome email's wording is new, pinned word for word in `welcome.test.js`, for Fayzan to accept.
- Someone who dropped Feedback and news on Resend's topic page and ticks the box again in a fresh first run is added back, with a new consent record, as §4.1 says. A full unsubscribe is never undone. The site can't tell a fresh tick from a stored choice, so the app never sends a stored choice again for the same address (Task 5).
- A new contact joins one segment, `RESEND_SEGMENT`, required like the topic ids. Resend sends every broadcast to a segment, a topic only narrows it, and a contact made through the API is in none.
- An existing contact's segments are never touched. Resend doesn't say what adding a contact to a segment it's already in answers, and a refusal would turn every returning subscriber's request into a 502 the app retries forever.
- `POST /contacts` sends no `unsubscribed: false`, which the plan had. A new contact is subscribed anyway, and if a create ever updated an existing contact, it would undo an unsubscribe.
- An address with half a surrogate pair, which only a hand-made request can hold, answers 400, before dry run. It used to fail with a 502.

*Task 3, the privacy policy and the Terms (7ff7bbe):*
- /privacy's "Email from Annotake" comes right after "The link email".
- Both pages say "Last updated: October 15, 2026"; Fayzan can move it to the release day.
- The rights line says to reply to any email from Annotake's email list, not any Annotake email: the link email comes from a no-reply address.
- Vercel's request logs are "kept for up to 30 days", which holds on every plan: 1 hour on Hobby, 1 day on Pro, and 30 days with Observability Plus.
- The retention sentence says "the list" never emails an unsubscribed address again, since the link email doesn't check the list. A changed address leaves the old one on the list.
- New copy beyond the plan, so the policy is complete: the app won't record without an address (the GDPR asks to say what happens when data isn't given); Resend's 30-day sending logs; the welcome email's legal basis, legitimate interest; annotake.app seeing the IP address; and Google (Gmail), where replies and Send Feedback arrive.
- "Coming later" no longer calls Stage 2's sign-in optional, since sign-in takes the email step's place (§9). If sign-in stays optional, the word goes back, and out of `legal.spec.js`'s GONE list.
- Send Feedback's paragraph names the Mac's model, which the draft has always included.
- The link email's "This is the only email we'll send you." and the home page's "We'll send one email with the download link, and that's all." stay: both are true of a link request.

*Task 4, `EmailConsent` and the release guard (40ffc58):*
- `EmailConsent.isPlausible` checks the address and its lowercase key, as `/api/subscribe` does. Otherwise an address the site refuses would loop: saved, refused, cleared, and typed again.
- `clean()` and the key compose with ICU's NFC (`Any-NFC`), not Foundation's `precomposedStringWithCanonicalMapping`, whose tables get Hangul and some Tibetan wrong: U+1100 U+1176 becomes another letter, so the app would save an address other than the one typed. ICU matched Node 22 on every code point; only characters newer than the Mac's ICU can differ.
- It measures as JavaScript does: lengths in UTF-16 code units, JavaScript's own whitespace, and code points, not Characters. Like the site, it accepts the C1 controls (U+0080–U+009F).
- Every `email.test.js` case is ported one for one, its `emailKey` addresses as accepted cases. Only these cases tie `email.js` to `EmailConsent.swift`, so a change to one changes the other and both test files.
- A test ties `make release`'s guard to the sentinel's exact declaration, so reformatting it can't let a release ship the sentinel.
- The guard goes on only when grep read the file and found no sentinel, so a moved or unreadable `EmailConsent.swift` stops a release too.
- The guard stops `make release DRY_RUN=1` too, until the address is set.

*Task 5, `EmailSignup` (089ff41):*
- `EmailSignup`'s static `request`, `post`, `schedule`, and `outcome` are `nonisolated`: a main-actor class's statics are main-actor-isolated, and the default `schedule` couldn't otherwise be the plan's closure type.
- The request sets `User-Agent: Annotake/<version>` and `Accept-Language: en`, and sends no cookies: URLSession's own headers would name the CFNetwork and Darwin versions and the region.
- The request cuts `appVersion` to the site's 32 code units, never through a code point, since the site would never take a longer one.
- Change… keeps the stored record's consent id with its box choice: the choice was made under that wording, and the site takes every id it shipped.
- Change… to the same address in other capitals or padding does nothing, so a stored choice is never sent again for one address.
- A change back to an address the site has taken from this Mac is saved as sent and never posted, or it could add Feedback and news back for someone who dropped it. The Mac keeps a SHA-256 of each such key under `email.sentKeys.v1`, so no old address is kept in the clear. Continue in the email step always posts, since the box was just chosen.
- `EmailConsent.key` is the site's `emailKey`, lowercasing with ICU, so a Greek final Σ becomes ς as in JavaScript.
- The log has three lines, `email: sent`, `email: invalid`, and `email: retry later`, one for each post.
- One post at a time: an answer applies only while the saved record is still the one posted, and a save, a change, or a launch starts the backoff over, so a stale retry never sends an old record.
- Unreadable data under `email.v1` reads as no address, so the step asks again. The stored field names are pinned, since renaming one would lose every saved address.
- Every test builds its `EmailSignup` through one harness, on a throwaway defaults suite with a fake post, and a test fails if another test file builds one, so no test can post for real.
- `Package.swift` and `Updater.swift` say the libraries' one network call is `EmailSignup.post`, which only the app makes.

*Task 6, the email step and `.emailOnly` (a3e8dc9):*
- `OnboardingModel` stays pure, seeing only whether an address is saved. The JSON the previous version saves is pinned, so an existing copy's state still decodes.
- A first run that an update reaches past the email step goes back to it while no address is saved; one left at You're set gets the `.emailOnly` pass instead, rather than show the drop box again (§3.2).
- At launch, a finished pass with no address gets the `.emailOnly` pass, and an `.emailOnly` pass whose address arrived meanwhile finishes with no window (§3.2).
- The pill's Open (`showForEmail()`) follows the launch rules, except that a Fix permissions… pass in progress gives way to the email step, since the person asked for it. An address cleared mid-session changes nothing on screen.
- Fix permissions… starts its own pass over a pending `.emailOnly` one, but not over a first run or a Fix permissions… pass in progress: restarting one would reset the permissions it has requested.
- Continue and Return in the field act only at the email step, on a plausible address, so one Return can't also press the next step's button (the Accessibility prompt).
- What's typed and the box are never saved, and the onboarding's saved state holds no address.
- With no signup, as in the UI snapshots, Continue does nothing, so nothing is sent.
- `AppDelegate` creates the app's one `EmailSignup` at launch step 3, beside Settings; `--selftest` never creates one, and the ones `--render-ui` builds (Task 8) have a post that never sends.
- The footer's Privacy policy link keeps the link color, since a grey link doesn't read as one, and it moves below the text when a longer mailing address won't fit on one line.
- The field's placeholder is `you@example.com`, and its VoiceOver label "Email address". Autocorrection is off, and it's at most 340 pt wide, as in the sketch.
- The `.emailOnly` pass ends on You're set, unchanged: it reads right for someone who already uses Annotake.
- A test measures the email step at 285 pt of the window's 440, so nothing is clipped.
- A main menu that never shows (`EditMenu.swift`) gives text fields ⌘X, ⌘C, ⌘V, ⌘A, ⌘Z, and ⇧⌘Z. A menu-bar app has no main menu, so pasting an address did nothing. AppKit adds its own hidden items with it, so ⌃⌘Space opens Emoji & Symbols while an Annotake window is key.
- Showing the window again first catches up on permissions granted while it was closed.

*Task 7, recording waits for an email (9145059):*
- A hold with no address becomes a refused hold, with no engine. Its message waits for the reveal, and a double-tap or the menu's Start shows it at once (§3.2). A recording under way is never cut off, since the address is read only while idle.
- The menu keeps offering Start Recording through a refused hold, since nothing records, and Start then shows the message and ends the hold.
- Letting go or Esc after the reveal leaves the message up for its 5 s, as Open Settings does, so Open can still be clicked.
- `SessionMachine.State.isRecording`, true only while recording, drives the menu's Start/Stop title, so a refused hold reads as not recording.
- The machine takes the saved address before each input through `prepare(sounds:hasAddress:)`, so the gate is in tested code. The controller's call is pinned by its source text, since a real controller in a test would start a capture if the gate failed open.
- `SessionController` takes the signup in its initializer, so the gate can't be left unwired. `PillButton` (Open Settings, Open) replaces the pill's `openSettings` flag.
- The pill's Open calls `showForEmail()`, built for it in Task 6, since the plan's `show()` is private.

*Task 8, Settings and the wiring (d5c78e0):*
- Settings gets the signup in the General tab, not in `SettingsModel`: the email isn't a setting, so Restore Defaults never touches it. The row follows the saved address while the window is open, even one a 400 clears.
- The Change… sheet opens with the address selected, so a typo can be fixed in place or the whole address typed over. Return saves a plausible address.
- The sheet's title, "Change your email", and its Privacy policy link are new copy, for Fayzan to accept.
- The Email row is its own section, last in General, above Restore Defaults. A long address is cut in the middle, as Save location is.
- `signup.resume()` runs last at launch, after the update check, in step 10, "The network, last, and in the background".
- A scan of `Sources/` finds exactly two `EmailSignup`s: AppDelegate's, and the UI snapshots', whose post never sends.
- New UI snapshots: `onboarding-email`, `onboarding-email-filled`, `onboarding-email-only` (the same picture, since the window's title isn't drawn), `pill-email`, `settings-email-change`, `settings-email-change-empty`, and `settings-general-no-email`. `settings-general` shows an address.

*Task 9, end to end on the local server (76258f0):*
- The local server checks unsubscribe links against `UNSUBSCRIBE_SECRET=test-secret`, set as `EMAIL_DRY_RUN` is, so the tests' signatures match and a real secret never reaches it, `make site-dev` included.
- The `api/_lib` test asks for an extensionless path too, so both rules are pinned: no file in `api/` is served, and nothing under a `_` name runs.
- A long address no longer makes the confirm page wider than a phone: `.message p` wraps anywhere, and `link.js`'s download link opts out, since broken anywhere it would leave a letter alone on a 360 px phone.
- The 320 px test uses the longest address `/api/subscribe` takes, with nowhere to break, so only wrapping passes it.
- `email.js` says `EmailConsent.swift` mirrors it, ICU's lowercasing included.

*The integration review, after Task 9 (215c9db, aec43f5, 4816c1f, 703bc1c, c9e50db, 339a8db, e9da75f, 4ba77a6, 35fb866, 0b2ecda, b496c70).* Three reviewers checked the app against the site, the promises against the behaviour, and the flows end to end. They confirmed ten findings, all fixed in these commits, and left four design questions, which are below.
- A request the site can't read answers 422 `request`, which the app retries, and 400 means only an address the site won't take. Before, a site deployed after an app with a new wording, or a field renamed on one side, would have cleared every new address and blocked recording.
- So a wording change deploys first: the new `consent.json`, then `make site-smoke`'s consent check passing (400, not 422), then the app's release (§3.1).
- Vercel's ignore step skips a build only when `site/` is unchanged since the last successful deployment (`VERCEL_GIT_PREVIOUS_SHA`). It compared only a push's last commit with its parent, so landing this branch with a docs commit on top would have left Production without `/api/subscribe`.
- `make site-smoke` checks the email functions too, and posts the invalid address `smoke@example` under the current consent id: 400 means the deployment has the app's wording, and 422 that it doesn't yet.
- With no address, Settings shows Not set with Add…, which opens the email step, so the site never records a wording the person didn't see. `change(address:)` with nothing saved now changes nothing, where Task 5's saved it.
- `site/tests/subscribe-request.json` holds the app's exact request, and both sides' tests use it, so a field renamed on one side fails a test.
- `UNSUBSCRIBE_SECRET` is set once and never replaced (§4.3).
- The Swift key test compares a decomposed address, as `email.test.js` does.
- /privacy no longer promises one-click unsubscribing, which the emails' own links don't give (§6.3).
- A menu Start refused while idle no longer resets the gestures: a Right ⌘ hold begun just before could be left as a refused hold that letting go never ended.
- Comments say that only tests set `EmailSignup.onChange`, and that Settings' Add… opens the email step too.

**Skipped:** nothing.

**Known, and left as is:**
- Resend doesn't document what `POST /contacts` does for an address it already has. The function gets there only when a contact appears between its lookup and its create, and the create carries no `unsubscribed: false`.
- `consent_at` is the server's time when the request arrives, which can be hours after the click if the Mac was offline.
- Vercel's runtime logs keep a request's query and its outgoing requests (an hour on Hobby), so an unsubscribe link's address and Resend's contact paths show there briefly. /privacy covers it.
- A first run that was moved back to the email step asks again, after it, for any permission it had declined, as any first run does.
- An older build can't read the new saved step or mode, and starts its first run again. Sparkle never downgrades.
- The app's request was checked over HTTP/1.1 on localhost only, not over HTTP/2 and TLS to Vercel: Checkpoint 5's sign-up covers it.
- /privacy names no contact for someone who only used the website, and the GDPR asks for the controller's contact details. An address on /privacy once one receives mail, or a contact form, would close it.
- On Vercel Pro, opting the project out of Observability Plus keeps runtime logs to a day. The policy holds either way.

**Open questions for Fayzan** (the code does the first choice today):
1. **Change… carries the earlier box choice to the new address,** and the site records it as a fresh consent (`consent_at` now, `consent_source` app), for an address the person never ticked the box for. The Mac never hears of a drop on Resend's topic page, so someone who dropped Feedback and news gets it again at the new address, and so does an address another Mac signed up that later dropped it. Keep it; or Change… always sends `news: false`, so a new address gets notices only; or the request says it's a change, and the site never adds Feedback and news to an existing contact on one.
2. **A lost 200:** if the site did its work but its answer was lost (a timeout, a 504, a Mac that slept, went offline, or quit mid-post), the app posts the same choice again, possibly days later. If Feedback and news was dropped in between, that adds it back with no fresh tick. Accept it as rare; or the app sends the tick's time (the record's `savedAt`), and the site keeps it as a contact property and never re-adds Feedback and news for a tick it has recorded. That's a new Resend property, and a request change on both sides and in `site/tests/subscribe-request.json`.
3. **The window title:** the `.emailOnly` pass an existing copy gets after its update is titled "Welcome to Annotake", above "Stay in the loop". Keep it; or retitle that pass, e.g. "Annotake", a one-line change.
4. **A one-click unsubscribe from the welcome email that fails is lost without a trace:** with Resend down for both attempts (about 8 s), the function answers 502 and logs no address, and whether the mail app retries is unknown. Rare, and only the welcome uses `/api/unsubscribe`. Accept it; or log a pseudonym (a truncated HMAC of the address), so a failure can be found and applied by hand; or keep `/api/unsubscribe` out of the rate-limit rule (question 7).
5. **The Change… sheet doesn't say the old address stays on the list;** only /privacy does. Leave it; or add a line to the sheet.
6. **The step's notice names security fixes and important changes, not the welcome email** everyone gets, which /privacy discloses. Leave it; or name it in the step. That's cheap only before `consent-2026-10-15` ships: after that, any change to the wording needs a new id.
7. **The rate-limit rule on `/api/*`** also limits mail apps' one-click `POST`s to `/api/unsubscribe`, at 10 per 600 s per IP. Fine at this scale, where the free plan caps welcomes near 100 a day; revisit with growth.

**Decided at Checkpoint 5 (2026-10-16): the list collects addresses only, for now.** Fayzan isn't emailing the list yet, and until he does, the addresses count Annotake's users. CASL wants a mailing address beside a consent request and in every commercial email, so none is needed before the first email, and the parts that need one wait. Checkpoint 5's "Parked until the list's first email" has them in order.
- The step has no box. Asking for Feedback and news is the consent request that needs the address, and ticks gathered without it might not count as consent later.
- `consent-2026-10-15`, not yet shipped, was edited rather than replaced: no box, and the footer "From Fayzan Malik · annotake.app · Privacy policy". The box comes back in a new version with `{address}` in its footer, which `consent.test.js` requires of any version with a box.
- The app saves every address with `news: false`. `EmailSignup`, the request, and `/api/subscribe` keep `news` for the box's return.
- `EmailConsent.mailingAddress` and `make release`'s guard against the unset address are gone. They return with the box.
- No `MAILING_ADDRESS` in Vercel, so `/api/subscribe` adds each contact and logs `subscribe: added welcome skipped no address`. With no welcome, nothing links to `/api/unsubscribe` yet; it's deployed anyway.
- /privacy says the address counts Annotake's users and gets important notices, both on legitimate interest. It no longer mentions a welcome email, Feedback and news, or a "choice of emails".
- Open questions 1, 2, 4, 6, and 7 are about the box, the welcome, or unsubscribing, so they wait with the list. Questions 3 and 5 stay for Checkpoint 5's copy review.
- Copies that save an address now are never offered the box. When it returns, decide whether they're asked once, and whether the list's first email does the welcome's job for the contacts added without one.
