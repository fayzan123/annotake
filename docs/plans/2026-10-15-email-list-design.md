# Annotake email list design: an email in the first run

**Status:** approved 2026-10-15 in conversation; this written spec awaits Fayzan's review · **Plan:** next, with `superpowers:writing-plans` · **Related:** [distribution design](2026-09-30-distribution-design.md) §6 (Stage 2 sign-in), §8 (privacy); [landing page design](2026-10-01-landing-page-design.md) §4.4 (CASL), §5.3 (the link function), §6 (robustness)

## 1. Goal

- **What it is:** one new first-run step that asks for an email, one small Vercel function that adds it to a Resend list, and one that unsubscribes. Resend is the list.
- **Why:** today a download has no bridge back to Fayzan. Before the announcements, every copy should leave him a way to reach its user: when something goes wrong (a security fix, a broken update), and to ask for feedback.
- **Done means:**
  - a new user can't finish the first run without an email, and an existing copy asks once after its update;
  - every address lands in Resend with its topics and a consent record;
  - every email Annotake sends can be unsubscribed from in one click;
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

- **The field:** the same rules as the site's `email.js`: trimmed, at most 254 characters, no line breaks, a plain address pattern. Continue is greyed out until it matches, and Return presses it when it's enabled. The field has focus when the step opens.
- **The box** starts unticked, every time.
- **The footer line** is what CASL wants on a consent request: who's asking, a mailing address, and a contact (the web address counts). The policy link opens `annotake.app/privacy`.
- **Continue** saves the address on the Mac (§3.4) and moves straight on to the permissions. The send happens in the background.
- **The wording is versioned:** the step's text and the box's label are one constant with an id, e.g. `consent-2026-10-15`. The id goes with the address, and the same text lives in `site/api/consent.js`, so the consent record names exactly what the person read. A test checks the app's and the site's copies match.

### 3.2 Existing copies

- A new mode, `.emailOnly`, with the steps `[.email, .done]`. At launch, a copy whose first run is complete but has no saved address opens the onboarding window in this mode.
- Until an address is saved, the trigger key doesn't start a recording. The pill shows "Add your email to start recording" with an **Open** button that brings the window forward, the way it shows Open Settings today. No recording is ever cut off: the check happens before one starts.
- "Fix permissions…" is unaffected.

### 3.3 Settings

- **Settings → General** gets an **Email** row: the address, and a **Change…** button that opens the same field (without the box) in a sheet. Saving sends the new address the same way, with the person's earlier box choice.
- The old address isn't touched: a typo bounces, and a real old address can unsubscribe from any email. That avoids a call that could unsubscribe someone else's address.
- The feedback choice isn't in Settings. It's changed from the link in any email.

### 3.4 Saving and sending

- **Saved** in `UserDefaults` under `email.v1`: `{address, news, consent, savedAt, sent}`.
- **Sent** by a small `EmailSignup` type: `POST https://annotake.app/api/subscribe` with JSON `{email, news, consent, appVersion}`. Nothing else: no device id, no macOS version.
- **When:** right after Continue, then at each launch and on a backoff (1 min, 5 min, 30 min, then every 6 hours) until it gets an answer:
  - 200: `sent = true`, done.
  - 400 (`invalid`): the app clears the address and asks again at the next launch.
  - 429, 5xx, a timeout, or no network: try again later.
- **Logged** as `email: <outcome>` only, never the address, matching the log's rule.
- The app's network calls become two: the daily update check, and this one.

## 4. The server

### 4.1 `site/api/subscribe.js`

Plain Node, no packages, built like `link.js` and sharing its helpers (`email.js`, body reading, timeouts).

- **Accepts** only `POST` with `application/json`, at most 2 KB: `email` (string), `news` (boolean), `consent` (a known id from `consent.js`), `appVersion` (a short string). Anything else is `400 invalid`.
- **Then:**
  1. Looks up the contact by email.
  2. **Not there:** creates it, with:
     - **Important notices** subscribed, and **Feedback and news** subscribed only if `news` is true;
     - the consent record as properties: `consent_at` (UTC time), `consent_wording` (the id), `consent_source` (`app`), `app_version`.

     Then it sends the welcome email (§5.1).
  3. **Already there and unsubscribed:** changes nothing, sends nothing, and answers 200. An unsubscribe is never undone by the app (§2).
  4. **Already there and subscribed:** if `news` is true and the contact isn't on Feedback and news, it adds that topic and updates the consent properties. It never removes a topic. It sends no welcome.
- **Answers** like `link.js`: `200 {ok: true}`, `400 invalid`, `429 busy`, `502 send`. Two attempts of at most 4 s, so it stays inside Vercel's 10 s limit.
- **Logs** `subscribe: <outcome>` only, never the address.
- **Preview deployments** use `EMAIL_DRY_RUN=1`, as `link.js` does: the checks run, and nothing is created or sent.
- The exact Resend calls (topic subscription, properties, finding a contact by email) are confirmed against Resend's API reference in the plan. The docs as of today show `POST /contacts` taking `topics` and `properties`.

### 4.2 `site/api/unsubscribe.js`

Broadcasts get Resend's own unsubscribe link and preference page. The welcome email is sent through `/emails`, so it needs its own link:

- `GET /api/unsubscribe?e=<email>&s=<signature>` shows a small page in the site's style: "Unsubscribe {email} from all Annotake emails?" with one button.
- `POST` to the same URL (the button, or a mail app's one-click `List-Unsubscribe-Post`) sets the contact `unsubscribed: true` and shows "You're unsubscribed."
- `s` is an HMAC-SHA256 of the lowercased email with `UNSUBSCRIBE_SECRET`, so nobody can unsubscribe an address they don't have a link for. Links never expire, well past CASL's 60 days.
- If the plan finds that Resend's transactional emails can carry its own unsubscribe placeholder, use that and drop this function.

### 4.3 Secrets and settings

- **`RESEND_CONTACTS_KEY`:** a Resend key with full access, used only by these two functions. `link.js` keeps its sending-only `RESEND_API_KEY`.
- **`RESEND_TOPIC_NOTICES` and `RESEND_TOPIC_NEWS`:** the two topic ids.
- **`UNSUBSCRIBE_SECRET`:** 32 random bytes.
- All of them are set in Vercel's Production settings only.
- The WAF rate-limit rule's path changes from `/api/link` to `/api/*`, so it covers all three functions with Hobby's one rule.

## 5. The emails

### 5.1 The welcome email

- **From** `Fayzan from Annotake <hello@annotake.app>`, on the domain Resend already sends for. **Reply-to** `Feedback.address`, Fayzan's personal Gmail (decided 2026-10-15: no Google Workspace, and no inbox at annotake.app). Reply-to is only a header, so sending stays on Resend and replies land in Gmail. Every recipient sees the Gmail address.
- **Subject:** "Welcome to Annotake".
- **Body,** as plain text and simple HTML like the link email:
  - a one-line thank-you;
  - the shortcut: hold Right ⌘, click through it, let go, then drag the card;
  - "Reply to this email any time: I read every one";
  - what they'll get: important notices, plus feedback requests and news if they ticked the box;
  - "Didn't sign up? Unsubscribe" with the §4.2 link.
- **Footer:** "Fayzan Malik · [mailing address] · annotake.app", the privacy policy link, and the unsubscribe link.
- **Headers:** `List-Unsubscribe` with the §4.2 URL, and `List-Unsubscribe-Post: List-Unsubscribe=One-Click`.
- Sent once, when the contact is created. If sending fails (the daily quota, or Resend is down), the contact stays and the welcome is skipped. It's never retried, so nobody gets it twice.

### 5.2 Broadcasts

Fayzan sends these from Resend's dashboard:
- **Every broadcast picks one topic.** Security fixes and broken updates go to Important notices; feedback requests, surveys, and news go to Feedback and news. When in doubt, Feedback and news.
- **One saved footer** on every broadcast: "Fayzan Malik · [mailing address] · annotake.app" and Resend's unsubscribe placeholder, which opens the topic page.
- The plan confirms Resend adds the one-click `List-Unsubscribe` headers to broadcasts. Gmail and Yahoo require them from bulk senders.

## 6. Legal

### 6.1 CASL

| CASL needs | Where it's met |
|---|---|
| Consent asked separately, never pre-ticked | The unticked box, only for Feedback and news (§3.1) |
| Who's asking, a mailing address, a contact, and that consent can be withdrawn | The step's footer line and "Every email has an unsubscribe link" |
| In every email: the name, the mailing address, a contact, and an unsubscribe link | The welcome email's footer (§5.1) and the broadcast footer (§5.2) |
| Unsubscribe works for 60 days, honoured within 10 business days | Links that never expire; Resend applies an unsubscribe at once |
| Proof of consent | The contact's consent properties, plus the wording kept in `consent.js` under its id |
| Notices are exempt from consent but still need the ID and unsubscribe | Important notices carry the same footer and link |

- **The mailing address** is a PO box or a virtual mailbox, never Fayzan's home. It has to exist before the release with this step ships, because it's on the step itself.

### 6.2 Everyone else

- **The EU and UK:** Important notices rest on legitimate interest (telling users about their software's security), and Feedback and news on consent. The app asks for only what it needs: an address and a choice.
- **The US (CAN-SPAM):** met by the same footer and unsubscribe.

### 6.3 Privacy policy and Terms

The privacy policy changes:
- **The short version:** "we get your email in the app, to send you important notices and, if you agree, feedback requests and news." Nothing you record leaves your Mac.
- **What's stored:** the email, the two topic choices, when and how you agreed, and the app version. It's stored in Resend, in the US, under US law.
- **How long:** until you ask for it to be deleted. After an unsubscribe the address is kept, marked unsubscribed, as proof and so it's never emailed again, unless you ask for deletion.
- **Your rights:** to see, correct, or delete it, by replying to any Annotake email.
- **What the app sends:** the email, the choice, and the app version, once.
- **Gone:** "we keep no list" and "no stored email addresses".

The Terms gain one line: using Annotake means getting important notices, and any email can be unsubscribed from.

## 7. Robustness and scale

| Part | Under load | If it fails |
|---|---|---|
| The email step | Local only | Nothing to fail: the address is saved on the Mac first |
| Sending from the app | One call per user, ever (plus a Change) | Retried on a backoff; the app never waits on it |
| `/api/subscribe` | A Vercel function; Resend's API takes 10 requests a second, raised on request | `429` or `502`; the app retries later |
| The welcome email | Shares Resend's free 100 emails a day with the link email | Skipped; the contact is still added |
| The list | Resend's free plan holds 1,000 contacts | Resend emails Fayzan near the limit; see the upgrade table |
| Fake sign-ups | The WAF rule (10 requests per 10 minutes per IP), and the welcome's "Didn't sign up?" link | Next step: BotID on `/api/*`, free, after checking it sets no cookies |
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
  - the app's consent wording matches `consent.js`.
- **By hand, at the end (§9):** a real sign-up from a fresh first run, the welcome email in Gmail with its one-click unsubscribe, a test broadcast to each topic, and unsubscribing from it.

## 9. Fayzan's part (all at the end)

- **Get the mailing address** (a PO box or a virtual mailbox), and put it in the step, the welcome email, and the broadcast footer.
- **In Resend:**
  - create the topics Important notices (default: subscribed) and Feedback and news;
  - create a full-access key;
  - save the broadcast footer.
- **In Vercel:** set `RESEND_CONTACTS_KEY`, the two topic ids, and `UNSUBSCRIBE_SECRET` in Production, and change the WAF rule's path to `/api/*`.
- **Read and accept** the step's wording, the welcome email, and the privacy policy and Terms changes. A short review by a Canadian lawyer before the first email to the list is cheap insurance, but it isn't required to ship.
- **Try it:** a fresh first run, the welcome email, a test broadcast to each topic, and an unsubscribe.

**Resend works before this ships.** On 2026-10-15 a live `POST /api/link` to Fayzan's Gmail answered `502 send`, and Gmail had never received an Annotake email: the domain is verified and its DNS is right (DKIM, SPF and the bounce MX on `send.annotake.app`, DMARC `p=none`), but `RESEND_API_KEY` was never added to Vercel (Checkpoint 4, step 3). The release with the email step doesn't ship until each of these passes, in order:
1. **The link email:** with `RESEND_API_KEY` set, `POST /api/link` answers 200, and the email arrives in Gmail's inbox, not spam, with `spf=pass`, `dkim=pass` (`d=annotake.app`) and `dmarc=pass` in its Authentication-Results header.
2. **The list:** with §4.3's settings, a fresh first run creates the contact in Resend with the right topics and consent properties, and the welcome email passes the same checks.
3. **Replies:** replying to the welcome email from another address lands in Fayzan's Gmail.
4. **Unsubscribing:** the welcome email's one-click unsubscribe and a test broadcast's topic page both work, and an unsubscribed contact gets neither the next broadcast nor a second welcome after typing the address again.

**Stage 2, later:** sign-in takes the email step's place. A signed-in account is matched to its Resend contact by email: nobody is subscribed twice or asked again, and an existing copy is asked to sign in once.

## 10. Open items

- **The mailing address,** above.

## 11. Changes to other docs

- **[spec.md](../spec.md):**
  - §2: "The app's only network call is a daily update check" gains the one sign-up call;
  - §3.6: the Email row in General;
  - §3.7: the email step after the welcome, and `.emailOnly`.
- **[distribution design](2026-09-30-distribution-design.md):** §8 privacy now includes an email from the app, ahead of Stage 2; §6 notes that sign-in replaces the email step.
- **[landing page design](2026-10-01-landing-page-design.md):** §1's "no stored email addresses" and §4.4's "no list is kept" point here.
- **The site:** `/privacy` and `/terms` as in §6.3. Any page copy that says Annotake needs no email is updated.

## 12. Not in this design

- An email gate on the site; the download stays one click.
- Confirmation codes or a confirm-your-email link.
- Sign-in, accounts, or the paywall (Stage 2 and 3).
- Email preferences inside the app.
- Automated sequences beyond the one welcome email.
- Removing the old address when someone changes it.
