# Annotake Email List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **How to execute:** work through the tasks in order, then the checkpoint (Task 11), which is Fayzan's. For each task:
> 1. Write the listed tests.
> 2. Run them and watch them fail:
>    - site unit tests: `make site-unit`
>    - site page tests: `make site-test FILTER=<grep>`
>    - Swift: `make test FILTER=<suite>`. Never plain `swift test`.
> 3. Implement until they pass.
> 4. Run the task's **Verify** step.
> 5. Commit with a `site:` or `app:` prefix (`docs:` for Task 10), ending with the `Co-Authored-By` line.
>
> **No stops until the checkpoint.** If a test expectation here looks wrong, decide what's right, pin it with a test, and record it under "Decisions" in Task 10's notes. If a step can't finish without someone present, skip only that step and record it under "Skipped".
>
> **Nothing outward-facing before Task 11:** never deploy, never touch Resend's or Vercel's dashboards, never send a real email, and never launch the full app (`make ui-snapshots` is the only app launch allowed, in Task 8).

**Goal:** Every copy of Annotake asks for an email once, in the first run or after an update, and adds it to a Resend list with topics, a consent record, a welcome email, and a working one-click unsubscribe.

**Architecture:**
- **The app:**
  - an email step in `OnboardingModel`, and a new `.emailOnly` mode for existing copies;
  - an `EmailSignup` type that saves the address in `UserDefaults` and posts it to `annotake.app/api/subscribe` in the background, with a backoff;
  - `SessionMachine` refuses to start a recording until an address is saved.
- **The site:** two new Vercel functions in plain Node with no packages, built like `site/api/link.js`. `subscribe.js` creates or updates the Resend contact and sends the welcome email; `unsubscribe.js` serves the one-click unsubscribe with an HMAC-signed link. Their shared code lives in `site/api/_lib/`. Vercel doesn't treat `_`-prefixed paths as functions.
- **The consent wording** lives once, in `site/api/_lib/consent.json`. The Swift copy is checked against it by a test.

**Tech Stack:** Swift 6.2 and SwiftUI (macOS 15+); Node 22 ES modules with `node:test`; Playwright for the page tests; Resend's HTTP API.

**Spec:** `docs/plans/2026-10-15-email-list-design.md` ("design §n"). Read it first. Also read `site/api/link.js` and `site/tests/unit/link.test.js`, the pattern both functions follow.

**Changes from the design,** decided while planning (Task 10 writes them into the design doc):
1. **The welcome email's unsubscribe is ours, not Resend's.** Resend hosts unsubscribe pages only for broadcasts. For `/emails` it expects a `List-Unsubscribe` header pointing at your own URL, which accepts a `POST` (RFC 8058). So design §4.2's `unsubscribe.js` is built, not optional.
2. **The contact's consent properties must exist in Resend first** (`POST /contact-properties`, type `string`). Creating them is a checkpoint step (Task 11), not code.
3. **The mailing address is the `MAILING_ADDRESS` environment variable on the site, and `EmailConsent.mailingAddress` in the app.**
   - The app constant starts as the sentinel `"[mailing address]"`, and `make release` refuses to build while it's still there.
   - Without `MAILING_ADDRESS`, the site function adds the contact but skips the welcome email, logging `subscribe: welcome skipped no address`.
4. **A hold refused for a missing email shows its message only at the reveal (800 ms),** so a Right ⌘ shortcut never flashes it.

**Global Constraints** (every task inherits these):
- **Copy,** exactly as written here; the tests assert it. The site uses `’` (U+2019), and the app uses a straight `'`, as each already does. The parity test treats the two as the same.
  - Step title: `Stay in the loop`
  - Notice: `We’ll email you about security fixes and important changes to Annotake. Every email has an unsubscribe link.`
  - Box: `Also email me feedback requests and news`
  - Footer: `From Fayzan Malik · {address} · annotake.app ·` followed by a `Privacy policy` link to `https://annotake.app/privacy`
  - Pill: `Add your email to start recording`, with the button `Open`
  - Settings: the row `Email`, the button `Change…`, and `Not set` when there's no address
  - Consent id: `consent-2026-10-15`
- **Never log an address,** in the app or the site. Log lines are `email: <outcome>` (app) and `subscribe: <outcome>` / `unsubscribe: <outcome>` (site).
- **The app never waits on the network.** Continue saves locally and moves on. The send runs in the background.
- **An unsubscribe is never undone by code.** `subscribe.js` never sets `unsubscribed: false` and never opts a contact out of a topic.
- **The email check** is the site's `isPlausibleEmail` (`site/assets/email.js`): trimmed, NFC, 3–254 characters, no whitespace or control characters, exactly one `@`, a local part of 1–64 characters, and a domain with a dot that neither starts nor ends with a dot and has no `..`. The Swift port must give the same answer for every case in `site/tests/unit/email.test.js`.
- **Resend** (as of 2026-10-15): base `https://api.resend.com`, `Authorization: Bearer <key>`, and a `User-Agent` header (Resend gives a 403 without one).
  - `GET /contacts/{email}`, `POST /contacts` `{email, unsubscribed:false, properties, topics:[{id, subscription:"opt_in"|"opt_out"}]}`, `PATCH /contacts/{email}` `{properties}` or `{unsubscribed:true}`, `PATCH /contacts/{email}/topics` with a body of `[{id, subscription}]`, and `POST /emails` with `headers`.
  - Every attempt times out after 4 s, and there are at most two attempts, so each call stays inside Vercel's 10 s.
- **Environment:** `RESEND_CONTACTS_KEY`, `RESEND_TOPIC_NOTICES`, `RESEND_TOPIC_NEWS`, `UNSUBSCRIBE_SECRET`, `MAILING_ADDRESS`, and `EMAIL_DRY_RUN=1` (Preview and the local server). `link.js` keeps its own `RESEND_API_KEY`.

**Review Focus** (inputs the tests below must pin; each has its test in the named task):
1. **Someone reinstalls and types an address that already unsubscribed:** nothing changes, no welcome is sent, and the answer is 200 (Task 2).
2. **A Right ⌘ shortcut (⌘C) while no email is saved:** no message, no recording, and the shortcut works (Task 7).
3. **The Mac is offline at Continue, then online hours later:** the first run carries on at once, and the address is sent on a later backoff tick or launch, exactly once (Task 5).
4. **A mail app's one-click unsubscribe `POST` with an empty or form body:** it unsubscribes and answers 200 with a blank body. A `GET` (a link scanner or prefetch) never unsubscribes (Task 1).
5. **Mixed-case and padded addresses** (`  Sam@Example.COM `): one contact, keyed lowercased, and the same signature for any capitalization (Tasks 1 and 2).

## File map

| File | Responsibility |
|---|---|
| `site/api/_lib/consent.json` | **New.** The consent id and wording, the one source of truth |
| `site/api/_lib/resend.js` | **New.** One Resend request with timeout, retry, and outcome sorting, shared by both functions |
| `site/api/_lib/unsubscribe-token.js` | **New.** `signEmail`, `verifyEmail`, `unsubscribeUrl` (HMAC-SHA256) |
| `site/api/_lib/welcome.js` | **New.** The welcome email's subject, text, and HTML |
| `site/api/unsubscribe.js` | **New.** `GET` shows the confirm page; `POST` unsubscribes |
| `site/api/subscribe.js` | **New.** Validates, creates or updates the contact, and sends the welcome once |
| `site/vercel.json` | Adds both functions with `maxDuration: 10` |
| `site/tests/server.mjs` | Runs `/api/subscribe` and `/api/unsubscribe` in dry run, and never runs `_lib` as a function |
| `site/privacy.html`, `site/terms.html` | Design §6.3 |
| `site/tests/unit/{resend,unsubscribe-token,welcome,unsubscribe,subscribe,consent}.test.js` | **New** |
| `site/tests/unit/vercel-json.test.js`, `site/tests/pages/legal.spec.js` | Updated |
| `Sources/AnnotakeApp/EmailConsent.swift` | **New.** The wording, the consent id, the mailing address, and `isPlausibleEmail` |
| `Sources/AnnotakeApp/EmailSignup.swift` | **New.** `EmailRecord` storage, the request, the backoff schedule, and the sender |
| `Sources/AnnotakeApp/OnboardingModel.swift` | `.email` step, `.emailOnly` mode |
| `Sources/AnnotakeApp/Onboarding.swift` | `EmailStep` view, copy, the controller choosing `.emailOnly` |
| `Sources/AnnotakeApp/SettingsWindow.swift` | The Email row and the Change sheet in `GeneralTab` |
| `Sources/AnnotakeApp/SessionMachine.swift`, `SessionController.swift`, `Pill.swift` | The recording gate and its pill message |
| `Sources/AnnotakeApp/AppMain.swift` | Creates `EmailSignup`, wires it to onboarding, settings, and the controller |
| `Sources/AnnotakeApp/UISnapshots.swift` | Snapshots of the email step and the Change sheet |
| `Makefile` | `release` refuses the sentinel mailing address |
| `Tests/AnnotakeAppTests/{EmailConsentTests,EmailSignupTests}.swift` | **New** |
| `Tests/AnnotakeAppTests/{OnboardingModelTests,OnboardingCopyTests,SessionMachineTests,PillTextTests}.swift` | Updated |
| `docs/spec.md`, the distribution and landing page designs, `docs/checkpoints.md`, `docs/plans/README.md` | Task 10 |

---

### Task 1: The unsubscribe link and function

**Files:**
- Create: `site/api/_lib/resend.js`, `site/api/_lib/unsubscribe-token.js`, `site/api/unsubscribe.js`
- Modify: `site/vercel.json`, `site/tests/server.mjs`, `site/tests/unit/vercel-json.test.js`
- Test: `site/tests/unit/resend.test.js`, `site/tests/unit/unsubscribe-token.test.js`, `site/tests/unit/unsubscribe.test.js`

**Interfaces:**
- Produces, from `_lib/resend.js`:
  ```js
  export const RESEND_BASE = 'https://api.resend.com';
  export const ATTEMPT_TIMEOUT_MS = 4000, RETRY_PAUSE_MS = 300, MAX_RATE_WAIT_MS = 1000;
  // One call, retried once after a network error, a timeout, a 5xx, or a plain 429. Never throws.
  // Resolves to { ok: true, status, json } | { ok: false, status, reason: 'network'|'timeout'|'quota'|'rate'|'server'|'rejected'|'notfound', name }
  export async function resend({ fetch, sleep, key, method, path, body, headers, timeoutMs, idempotencyKey })
  ```
  `notfound` is any 404. `quota` is a 429 whose `name` is `daily_quota_exceeded` or `monthly_quota_exceeded`. It sets `User-Agent: annotake-site/1.0`.
- Produces, from `_lib/unsubscribe-token.js`:
  ```js
  export function signEmail(email, secret)       // hex HMAC-SHA256 of emailKey(email)
  export function verifyEmail(email, sig, secret) // timingSafeEqual; false for any malformed input
  export function unsubscribeUrl(email, secret)  // `https://annotake.app/api/unsubscribe?e=${encodeURIComponent(emailKey(email))}&s=${sig}`
  ```
- Produces: `site/api/unsubscribe.js` exporting `createHandler({ fetch, env, log, sleep, timeoutMs })` and `{ GET, POST }`, like `link.js`.
- Consumes: `cleanEmail`, `emailKey`, `isPlausibleEmail` from `site/assets/email.js`.

- [ ] **Step 1: Write the failing tests.**
  - `resend.test.js`, with a fake `fetch` like `link.test.js`'s harness:
    - 2xx gives `ok`;
    - 404 gives `notfound`, with no retry;
    - 422 gives `rejected`, with no retry;
    - 500 then 200 gives `ok` after one pause of `RETRY_PAUSE_MS`;
    - 500 twice gives `server`;
    - a 429 with `retry-after: 0.2` waits 200 ms, then retries;
    - a 429 with `name: daily_quota_exceeded` gives `quota` at once;
    - `network` and a hang give `network` and `timeout` (with `timeoutMs: 50`);
    - the URL is `RESEND_BASE + path`, the headers carry `Bearer`, `User-Agent`, and `Idempotency-Key` only when passed;
    - a body is sent as JSON only when given.
  - `unsubscribe-token.test.js`:
    - signing is stable;
    - `Sam@Example.COM` and ` sam@example.com ` sign the same;
    - `verifyEmail` rejects a wrong signature, a signature of the wrong length, a non-hex signature, an empty secret, and `undefined`;
    - `unsubscribeUrl` round-trips through `URL` to the same `e` and `s`.
  - `unsubscribe.test.js`:
    - `GET` with a valid `e` and `s` answers 200 HTML containing `Unsubscribe sam@example.com from all Annotake emails?` and a `<form method="post">` whose action keeps the query. It makes **no** fetch call.
    - `GET` with a bad signature answers 400 HTML `This unsubscribe link isn’t valid.`, with no fetch.
    - `POST` with a valid `e` and `s` (an empty body, a form body `List-Unsubscribe=One-Click`, or the confirm form's body) calls `PATCH /contacts/sam%40example.com` with `{unsubscribed: true}`. When the request's `content-type` is form-encoded and its body is `List-Unsubscribe=One-Click`, it answers 200 with an empty body. The confirm form gets 200 HTML `You’re unsubscribed.`
    - `POST` when Resend answers `notfound` still answers as unsubscribed. There's nothing left to email.
    - `POST` with a bad signature answers 400 with no fetch.
    - `POST` when Resend fails (`server`) answers 502 HTML `We couldn’t unsubscribe you right now. Try the link again in a few minutes.`
    - `EMAIL_DRY_RUN=1` gives no fetch, and success.
    - A missing `RESEND_CONTACTS_KEY` or `UNSUBSCRIBE_SECRET` answers 502, logging `unsubscribe: failed not configured`.
    - Log lines are only `unsubscribe: shown`, `unsubscribe: done`, `unsubscribe: done already gone`, `unsubscribe: invalid`, `unsubscribe: dry run`, and `unsubscribe: failed <reason>`. A final test checks no log line contains any address used (as `link.test.js` does).
  - `vercel-json.test.js`: `config.functions` deep-equals `{ 'api/link.js': {maxDuration: 10}, 'api/subscribe.js': {maxDuration: 10}, 'api/unsubscribe.js': {maxDuration: 10} }`.
- [ ] **Step 2:** `make site-unit`. The new tests fail on the missing modules.
- [ ] **Step 3: Implement.**
  - Pages use the same `page()` shell as `link.js` (`site.css`, the favicons, `<main class="message">`).
  - `unsubscribe.js` reads `e` and `s` from the URL's query in both methods, so the one-click `POST` to the `List-Unsubscribe` URL works without a body. It reads at most 2 KB of body and ignores its content.
  - Add both functions to `vercel.json`. Before them, check `server.mjs`'s `runFunction`:
    - it must load `site/api/<name>.js` for `/api/subscribe` and `/api/unsubscribe`;
    - it must answer 404 for `/api/_lib/...`;
    - it must pass `EMAIL_DRY_RUN=1` to all three functions.
- [ ] **Step 4:** `make site-unit` passes.
- [ ] **Step 5: Verify:** `make site-test`.
- [ ] **Step 6:** commit `site: the unsubscribe link and function`.

### Task 2: The consent wording, the welcome email, and the subscribe function

**Files:**
- Create: `site/api/_lib/consent.json`, `site/api/_lib/welcome.js`, `site/api/subscribe.js`
- Test: `site/tests/unit/consent.test.js`, `site/tests/unit/welcome.test.js`, `site/tests/unit/subscribe.test.js`

**Interfaces:**
- Produces, `consent.json` (the app's tests read this file too):
  ```json
  { "current": "consent-2026-10-15",
    "versions": { "consent-2026-10-15": {
      "title": "Stay in the loop",
      "notice": "We’ll email you about security fixes and important changes to Annotake. Every email has an unsubscribe link.",
      "box": "Also email me feedback requests and news",
      "footer": "From Fayzan Malik · {address} · annotake.app · Privacy policy" } } }
  ```
  A wording change adds a new version and moves `current`. A shipped version is never edited.
- Produces, from `_lib/welcome.js`: `welcomeEmail({ news, address, unsubscribe })` returns `{ subject, text, html }`.
- Produces: `POST /api/subscribe`.
  - Request: JSON `{ email: string, news: boolean, consent: string, appVersion: string }`.
  - Answers: `200 {ok:true}`, `400 {ok:false, reason:"invalid"}`, `429 {ok:false, reason:"busy"}`, `502 {ok:false, reason:"send"}`. `GET` answers 405.
- Consumes: `resend()` from `_lib/resend.js`, `unsubscribeUrl()` from `_lib/unsubscribe-token.js` (Task 1), and `cleanEmail`, `emailKey`, `isPlausibleEmail` from `site/assets/email.js`.

- [ ] **Step 1: Write the failing tests.**
  - `consent.test.js`:
    - `current` names a version that exists;
    - every version has the four strings;
    - `footer` contains `{address}`;
    - apostrophes are `’`.
  - `welcome.test.js`:
    - subject `Welcome to Annotake`;
    - the text contains `Hold Right ⌘`, `Reply to this email any time`, `Didn’t sign up?`, the unsubscribe URL, `Fayzan Malik · <address> · annotake.app`, and `https://annotake.app/privacy`;
    - with `news: true` it says `important notices, plus feedback requests and news`, and with `news: false`, `important notices`;
    - the HTML holds the same links, HTML-escaped, and the address is escaped.
  - `subscribe.test.js`, with a fake `fetch` that records calls and answers by method and path:
    - **Invalid input** answers 400 with no fetch: not JSON, form-encoded, over 2 KB, a missing `email`, a non-boolean `news`, an unknown `consent`, a non-string `appVersion` or one over 32 characters, and an implausible address.
    - **New contact, `news:false`:**
      - `GET /contacts/sam%40example.com` gives `notfound`;
      - then `POST /contacts` with `email: "sam@example.com"` (from `  Sam@Example.COM `, lowercased), `unsubscribed: false`, `topics: [{id: NOTICES, subscription: "opt_in"}, {id: NEWS, subscription: "opt_out"}]`, and `properties: {consent_at: <ISO UTC from the injected clock>, consent_wording: "consent-2026-10-15", consent_source: "app", app_version: "0.3.0 (120)"}`;
      - then `POST /emails` with `from: "Fayzan from Annotake <hello@annotake.app>"`, `reply_to: "fayzanm786@gmail.com"`, subject `Welcome to Annotake`, and `headers` with `List-Unsubscribe: <url>` and `List-Unsubscribe-Post: List-Unsubscribe=One-Click`, where the URL verifies for the address, and `Idempotency-Key: welcome-<sha256 of the lowercased address>`;
      - answers 200.
    - **New contact, `news:true`:** NEWS is `opt_in`, and the welcome says so.
    - **Existing, unsubscribed:** only the `GET`, answering 200, logging `subscribe: kept unsubscribed`. (Review Focus 1.)
    - **Existing, subscribed, `news:false`:** only the `GET`, answering 200, with no topic call and no welcome.
    - **Existing, subscribed, `news:true`:**
      - `GET /contacts/{email}/topics` (or the topics in the contact response, whichever the implementation uses; pin the one used);
      - if NEWS isn't `opt_in`, `PATCH /contacts/{email}/topics` with `[{id: NEWS, subscription: "opt_in"}]`, and `PATCH /contacts/{email}` with the four consent properties;
      - no welcome;
      - never any `opt_out`.
    - **The welcome fails** (`quota`, then separately `server`): still 200, logging `subscribe: added welcome failed <reason>`.
    - **No `MAILING_ADDRESS`:** the contact is created, no `/emails` call, logging `subscribe: added welcome skipped no address`.
    - **The contact `GET` or `POST` fails:** `quota` and `rate` answer 429; `server`, `network`, and `timeout` answer 502; `rejected` answers 502.
    - **A missing key, topic id, or secret** answers 502, logging `subscribe: failed not configured`.
    - **`EMAIL_DRY_RUN=1`:** no fetch, 200.
    - **Addresses never appear in a log line** (the final check across every test).
- [ ] **Step 2:** `make site-unit`. The tests fail.
- [ ] **Step 3: Implement.**
  - `subscribe.js` imports `consent.json` with `import consent from './_lib/consent.json' with { type: 'json' };`.
  - Reading the body and building the handler follow `link.js`.
  - The reply-to address is a constant, `REPLY_TO`, with a comment that it must match `Feedback.address` in `Sources/AnnotakeApp/Feedback.swift`. A unit test reads that Swift file and checks they match.
- [ ] **Step 4:** `make site-unit` passes.
- [ ] **Step 5: Verify:** `make site-test`.
- [ ] **Step 6:** commit `site: the subscribe function and the welcome email`.

### Task 3: The privacy policy and the Terms

**Files:**
- Modify: `site/privacy.html`, `site/terms.html`, `site/tests/pages/legal.spec.js`

- [ ] **Step 1: Write the failing page tests** in `legal.spec.js`:
  - `/privacy`'s "The short version" list contains `We get your email address in the app, to send you important notices and, if you agree, feedback requests and news.`, and still contains the line about recordings never leaving the Mac.
  - A new `<h2>Email from Annotake</h2>` section says:
    - what's stored: `your email address, which emails you chose, when and how you agreed, and the app version`;
    - that it's stored with Resend in the United States;
    - `You can unsubscribe from any email with one click`;
    - the retention sentence from design §6.3;
    - the legal bases: legitimate interest for important notices, consent for feedback requests and news.
  - "The link email" section no longer says `We keep no list`, and says `Asking for the link doesn’t add you to any list.`
  - "Your rights" says `reply to any email from Annotake`, in place of `With no accounts and no list, we hold none ourselves`.
  - "The Annotake app" section says the app sends your email address, your choice, and its version once, plus the daily update check.
  - `/terms` gains, under "The beta", `Using Annotake means you’ll get important notices by email. You can unsubscribe from any email.`
- [ ] **Step 2:** `make site-test FILTER=legal` fails.
- [ ] **Step 3:** edit the two pages. Keep their structure. The policy's existing "Changes" section stays: it already promises an update before anything new is sent.
- [ ] **Step 4: Verify:** `make site-test` passes, including the axe checks.
- [ ] **Step 5:** commit `site: the privacy policy and Terms cover the email list`.

### Task 4: `EmailConsent`: the wording, the address check, and the release guard

**Files:**
- Create: `Sources/AnnotakeApp/EmailConsent.swift`, `Tests/AnnotakeAppTests/EmailConsentTests.swift`
- Modify: `Makefile` (the `release` target)

**Interfaces:**
- Produces:
  ```swift
  enum EmailConsent {
      static let id = "consent-2026-10-15"
      static let title = "Stay in the loop"
      static let notice = "We'll email you about security fixes and important changes to Annotake. Every email has an unsubscribe link."
      static let box = "Also email me feedback requests and news"
      static let mailingAddress = "[mailing address]"  // Fayzan replaces this at the checkpoint
      static let unsetMailingAddress = "[mailing address]"
      static var footer: String { "From Fayzan Malik · \(mailingAddress) · annotake.app ·" }  // then the Privacy policy link
      static let privacyURL = URL(string: "https://annotake.app/privacy")!
      static func clean(_ input: String) -> String          // trimmed, precomposedStringWithCanonicalMapping (NFC)
      static func isPlausible(_ input: String) -> Bool       // the Global Constraints' rule, on clean(input)
  }
  ```

- [ ] **Step 1: Write the failing tests.**
  - **Parity:** `EmailConsentTests` reads `site/api/_lib/consent.json` (the path from `#filePath`, up to the repo root). It checks that `current == EmailConsent.id`, and that `title`, `notice`, and `box` equal the Swift strings after replacing `’` with `'`. It checks that `footer` with `{address}` filled in equals `EmailConsent.footer + " Privacy policy"`.
  - **The address check:** the accepted and rejected cases are taken one for one from `site/tests/unit/email.test.js`. Read that file and port every case, including the length limits (254 and 64) and the line break and control-character cases.
- [ ] **Step 2:** `make test FILTER=EmailConsentTests` fails.
- [ ] **Step 3:** implement. In `Makefile`'s `release` target, add a first line: `@! grep -q 'mailingAddress = "\[mailing address\]"' Sources/AnnotakeApp/EmailConsent.swift || (echo "Set EmailConsent.mailingAddress before a release" && exit 1)`.
- [ ] **Step 4:** `make test FILTER=EmailConsentTests` passes. Run `make -n release | head -3` and check the guard is the first command.
- [ ] **Step 5: Verify:** `make test`.
- [ ] **Step 6:** commit `app: the email consent wording and address check`.

### Task 5: `EmailSignup`: saving, sending, and the backoff

**Files:**
- Create: `Sources/AnnotakeApp/EmailSignup.swift`, `Tests/AnnotakeAppTests/EmailSignupTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct EmailRecord: Codable, Equatable {
      var address: String; var news: Bool; var consent: String; var savedAt: Date; var sent: Bool
      static let storeKey = "email.v1"
  }
  enum EmailSendOutcome: Equatable { case sent, invalid, retryLater }
  @MainActor final class EmailSignup: ObservableObject {
      static let endpoint = URL(string: "https://annotake.app/api/subscribe")!
      static let backoff: [TimeInterval] = [60, 300, 1800, 21_600]  // then 21_600 forever
      @Published private(set) var record: EmailRecord?
      var hasAddress: Bool { record != nil }
      var onChange: (() -> Void)?   // fired after save or clear, for the controller and onboarding
      init(defaults: UserDefaults, appVersion: String = AppVersion.current.description,
           post: @escaping (URLRequest) async -> EmailSendOutcome = EmailSignup.post,
           schedule: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void = EmailSignup.schedule,
           now: @escaping () -> Date = Date.init, report: @escaping (String) -> Void = { log($0) })
      func save(address: String, news: Bool)   // clean()s, stores sent:false, then sends
      func change(address: String)             // keeps news, as save
      func resume()                            // at launch: sends if record exists and !sent
      static func request(for record: EmailRecord, appVersion: String) -> URLRequest
      static func outcome(status: Int?) -> EmailSendOutcome   // 200 → sent, 400 → invalid, else retryLater
  }
  ```
  `request` is a `POST` with `Content-Type: application/json`, a 10 s timeout, and the body `{"email","news","consent","appVersion"}`. `EmailSignup.post` uses `URLSession.shared` and maps a thrown error to `.retryLater`.

- [ ] **Step 1: Write the failing tests,** with a fake `post` and a fake `schedule` that records delays and lets the test fire them:
  - `save` stores the record in a test suite's `UserDefaults` under `email.v1` with `sent: false`, then posts once. The request body decodes to the four fields, with the cleaned address and `consent: "consent-2026-10-15"`.
  - **`.sent`:** the record is stored with `sent: true`, nothing is scheduled, and it logs `email: sent`.
  - **`.invalid`:** the record is cleared, `hasAddress` is false, `onChange` fires, and it logs `email: invalid`.
  - **`.retryLater` four times, then `.sent`:** the scheduled delays are `[60, 300, 1800, 21600]`, and the fifth attempt marks it sent.
  - **Offline, then a relaunch** (Review Focus 3): `save` gets `.retryLater` and schedules 60. Then a new `EmailSignup` on the same defaults calls `resume()`, which posts once. When that answers `.sent`, the old instance's scheduled closure firing afterwards posts nothing, because it re-reads `sent`. Exactly one `.sent` post in total.
  - **`resume()`** with no record, or with `sent: true`, posts nothing.
  - **`change`** keeps `news`, resets `sent` to false, and posts the new address.
  - **One send at a time:** a second `save` while a post is in flight results in one post for the newer address after the first returns.
  - **No log line contains the address.**
- [ ] **Step 2:** `make test FILTER=EmailSignupTests` fails.
- [ ] **Step 3:** implement. `schedule` defaults to a one-shot main-run-loop `Timer`, as `Pill` uses (`Timer.onMainRunLoop`).
- [ ] **Step 4:** `make test FILTER=EmailSignupTests` passes.
- [ ] **Step 5: Verify:** `make test`.
- [ ] **Step 6:** commit `app: EmailSignup saves the address and sends it in the background`.

### Task 6: The email step in the first run, and `.emailOnly`

**Files:**
- Modify: `Sources/AnnotakeApp/OnboardingModel.swift`, `Sources/AnnotakeApp/Onboarding.swift`, `Tests/AnnotakeAppTests/OnboardingModelTests.swift`, `Tests/AnnotakeAppTests/OnboardingCopyTests.swift`

**Interfaces:**
- Produces:
  - `OnboardingModel.Step.email`, `OnboardingModel.Mode.emailOnly`, `OnboardingModel.Action.submitEmail`;
  - `mutating func emailSaved()`, which advances past `.email`;
  - `static func emailOnly() -> Persisted`, which returns `Persisted(mode: .emailOnly, step: .email)`.
  - Steps:
    - `.firstRun`: `[.welcome, .email] + permissions + [.reopen, .practice, .dropCard, .done]`;
    - `.fixPermissions`: unchanged;
    - `.emailOnly`: `[.email, .done]`.
  - `OnboardingController.init(trigger:defaults:signup:)` takes the `EmailSignup` from Task 5.
- Consumes: `EmailSignup.save(address:news:)`, `EmailSignup.hasAddress`, and `EmailConsent` (Tasks 4–5).

- [ ] **Step 1: Write the failing tests.**
  - `.firstRun` steps are in the order above, and `.fixPermissions` doesn't contain `.email`.
  - At `.email`, `action == .submitEmail`. `perform()` doesn't advance it; only `emailSaved()` does, to the first permission not yet granted (or `.reopen` and beyond, as `advance()` already decides).
  - **`.emailOnly`:** `emailSaved()` goes to `.done`, and `perform()` at `.done` completes.
  - **Decoding a `Persisted` saved by the old version** (JSON with `step: welcome`, `completed: true`) still works, because `Step` stays `Codable` with the new case added.
  - `OnboardingCopy.title(.email) == "Stay in the loop"`, and `paragraphs(.email, …) == [EmailConsent.notice]`.
  - `OnboardingCopy.logName(.email) == "email"` (the view model's `logName`).
- [ ] **Step 2:** `make test FILTER=Onboarding` fails.
- [ ] **Step 3: Implement.**
  - **`EmailStep`,** a SwiftUI view in `Onboarding.swift`:
    - a `TextField` (focused on appear, `.textContentType(.emailAddress)`);
    - the notice paragraph;
    - a `Toggle` with `EmailConsent.box`, starting off;
    - the footer as `Text` plus a `Link("Privacy policy", destination: EmailConsent.privacyURL)` in `.font(.footnote)` and `.foregroundStyle(.secondary)`.
  - **The buttons row** shows `primary("Continue")`, disabled unless `EmailConsent.isPlausible(text)`, with `.keyboardShortcut(.defaultAction)`. It calls the view model's `submitEmail(address:news:)`, which calls `signup.save` then `change { $0.emailSaved() }`.
  - **In `OnboardingController.showIfNeeded()`:** if the first run is complete and `!signup.hasAddress`, switch to `OnboardingModel.emailOnly()` and show. When `signup.onChange` reports the address was cleared (`.invalid`), the same happens at the next launch, not mid-session.
- [ ] **Step 4:** `make test FILTER=Onboarding` passes.
- [ ] **Step 5: Verify:** `make test`.
- [ ] **Step 6:** commit `app: the email step in the first run, and once for existing copies`.

### Task 7: Recording waits for an email

**Files:**
- Modify: `Sources/AnnotakeApp/SessionMachine.swift`, `Sources/AnnotakeApp/SessionController.swift`, `Sources/AnnotakeApp/Pill.swift`, `Tests/AnnotakeAppTests/SessionMachineTests.swift`, `Tests/AnnotakeAppTests/PillTextTests.swift`

**Interfaces:**
- Produces:
  - `SessionMachine.emailNeeded: Bool`, set by the controller before each `handle`, like `sounds`;
  - `PillMessage.emailNeeded`;
  - `State.refusedHold`, a hold that started while `emailNeeded`, with no engine;
  - `Pill.showMessage(_ text: String, button: PillButton?, hideAfter:)`, where `enum PillButton { case openSettings, openEmail }`. The existing `openSettings: Bool` callers move to `button:`.
- Consumes: `EmailSignup.hasAddress` (Task 5), and `OnboardingController.show()` for the Open button (Task 6).

- [ ] **Step 1: Write the failing tests** in `SessionMachineTests`, with `emailNeeded = true`:
  - `startHold` gives `[]` and the state `.refusedHold`;
  - then `revealHold` gives `[.showMessage(.emailNeeded)]`;
  - then `stopHold` gives `[]` and `.idle`.
  - **A shortcut** (Review Focus 2): `startHold` then `discardHold` gives `[]` twice, with no `.showMessage` at any point, and ends `.idle`.
  - `startHold`, then `cancel`, gives `.idle`.
  - `startHandsFree` gives `[.showMessage(.emailNeeded), .resetGestures]`, and `.idle`.
  - `menuStart` gives the same.
  - With `emailNeeded = false`, every existing test is unchanged (run the suite).
  - In `PillTextTests`, `PillText.message(.emailNeeded) == "Add your email to start recording"`.
- [ ] **Step 2:** `make test FILTER=SessionMachineTests` fails.
- [ ] **Step 3: Implement.**
  - The controller sets `machine.emailNeeded = !signup.hasAddress` beside `machine.sounds` in `handle(_:at:)`.
  - `showMessage` maps `.emailNeeded` to `button: .openEmail`. Its action calls a closure, `onOpenEmail`, that `AppMain` wires to the onboarding controller's `show()`.
  - A message with a button takes clicks, as Open Settings does today.
- [ ] **Step 4:** `make test FILTER='SessionMachineTests|PillTextTests'` passes.
- [ ] **Step 5: Verify:** `make test`.
- [ ] **Step 6:** commit `app: recording waits for an email`.

### Task 8: Settings, wiring, and the UI snapshots

**Files:**
- Modify: `Sources/AnnotakeApp/SettingsWindow.swift` (`GeneralTab`), `Sources/AnnotakeApp/AppMain.swift`, `Sources/AnnotakeApp/UISnapshots.swift`, `Tests/AnnotakeAppTests/SettingsWindowTests.swift`

**Interfaces:**
- Consumes: `EmailSignup` (`record`, `change(address:)`), `EmailConsent.isPlausible`, `OnboardingController.init(trigger:defaults:signup:)`, `SessionController`'s signup and `onOpenEmail`.

- [ ] **Step 1: Write the failing tests** in `SettingsWindowTests`:
  - `GeneralTab`'s email row text is the saved address, or `Not set` with no record;
  - the Change sheet's Save is disabled for `not-an-email` and enabled for `sam@example.com`;
  - saving calls `change(address:)` with the cleaned address.

  Use a test `EmailSignup` with a fake `post`.
- [ ] **Step 2:** `make test FILTER=SettingsWindowTests` fails.
- [ ] **Step 3: Implement.**
  - **`GeneralTab`:** add a `Section` with `LabeledContent("Email") { Text(address ?? "Not set"); Button("Change…") }`. The sheet holds a `TextField`, Cancel, and Save (the default action). Changing doesn't count toward Restore Defaults: the email isn't a setting, and Restore Defaults never touches it.
  - **`AppMain`:**
    - create one `EmailSignup(defaults: .standard)` before the controller and the onboarding;
    - pass it to both, and to the settings model;
    - call `signup.resume()` after launch.
  - **`UISnapshots`:** add `onboarding-email` (empty field), `onboarding-email-filled` (a valid address, box ticked), `onboarding-email-only`, and `settings-general` with an address. Use an `EmailSignup` on a throwaway `UserDefaults(suiteName:)` with a `post` that never runs.
- [ ] **Step 4:** `make test` passes.
- [ ] **Step 5: Verify:**
  - `make ui-snapshots` exits 0 with an empty `problems.txt`;
  - open `build/ui/onboarding-email*.png` and check: nothing is clipped at 560×440; Continue is greyed out with the field empty; the footer's link is visible.
- [ ] **Step 6:** commit `app: the email in Settings, and the wiring`.

### Task 9: End-to-end against the local server

**Files:**
- Create: `site/tests/pages/subscribe.spec.js`

- [ ] **Step 1:** write Playwright `request` tests against the local server, which runs in dry run:
  - `POST /api/subscribe` with a valid body answers `200 {ok:true}`; with `news: "yes"` it answers 400;
  - `GET /api/subscribe` answers 405;
  - `GET /api/unsubscribe` with a signature made by `signEmail` under the server's test secret answers 200 HTML with the confirm form, and with a bad signature, 400;
  - `GET /api/_lib/consent.json` answers 404.

  The server passes `UNSUBSCRIBE_SECRET=test-secret` to the functions; add that to `server.mjs` beside `EMAIL_DRY_RUN`.
- [ ] **Step 2:** `make site-test FILTER=subscribe` fails until the server change is in; then it passes.
- [ ] **Step 3: Verify:** `make site-test`.
- [ ] **Step 4:** commit `site: the email functions end to end on the local server`.

### Task 10: Docs

**Files:**
- Modify:
  - `docs/spec.md`: §2's network line; §3.6, a Settings row `General | Email: the address, with Change… | Asked in the first run`; §3.7, the email step and `.emailOnly`;
  - `docs/plans/2026-09-30-distribution-design.md`: §6 and §8;
  - `docs/plans/2026-10-01-landing-page-design.md`: §1's "no stored email addresses" and §4.4, both pointing to the email list design;
  - `docs/plans/2026-10-15-email-list-design.md`: a "§13 Changes from planning and building" with this plan's four changes and the session's Decisions and Skipped lists; the Status line;
  - `docs/checkpoints.md`: a new "Checkpoint 5 (the email list)" with Task 11's steps;
  - `docs/plans/README.md`: the session entry.

- [ ] **Step 1:** make the edits. The spec's wording style is short sentences and lists, as in the files themselves.
- [ ] **Step 2: Verify:**
  - `make test` and `make site-test` still pass;
  - `grep -n "keep no list\|no stored email" docs/spec.md docs/plans/2026-10-01-landing-page-design.md site/*.html` shows only lines that now point to the email list design.
- [ ] **Step 3:** commit `docs: the email list, built`.

### Task 11: Checkpoint 5 (Fayzan, with a session to help)

Not code; these steps are written into `docs/checkpoints.md` by Task 10. Each one needs Fayzan's logins or decisions.

- [ ] **The mailing address:**
  - rent a PO box or a virtual mailbox;
  - set `EmailConsent.mailingAddress` in `Sources/AnnotakeApp/EmailConsent.swift`, and add `MAILING_ADDRESS` in Vercel (Production);
  - commit `app: the CASL mailing address`.
- [ ] **In Resend:**
  - create the topics `Important notices` (default: opt in) and `Feedback and news` (default: opt out), and note their ids;
  - create the string contact properties `consent_at`, `consent_wording`, `consent_source`, `app_version`;
  - create a full-access key;
  - save a broadcast footer: `Fayzan Malik · <address> · annotake.app` and the unsubscribe placeholder.
- [ ] **In Vercel (Production, Secret):** `RESEND_CONTACTS_KEY`, `RESEND_TOPIC_NOTICES`, `RESEND_TOPIC_NEWS`, `UNSUBSCRIBE_SECRET` (`openssl rand -hex 32`), and `MAILING_ADDRESS`. Change the WAF rule's path to `/api/*`, then redeploy.
- [ ] **Read and accept:** the email step (`build/ui/onboarding-email-filled.png`), the welcome email, and the `/privacy` and `/terms` changes.
- [ ] **Design §9's checks 2–4,** in order, with a release build on Fayzan's Mac:
  - **The list:** a fresh first run (`defaults delete com.fayzanmalik.annotake email.v1` and `onboarding.v1`) with a Gmail `+alias` address creates the Resend contact with both topics and all four properties. The welcome email arrives in the inbox with `dkim=pass`, `spf=pass`, and `dmarc=pass`, and Gmail shows its Unsubscribe link.
  - **Replies:** replying from another address lands in `fayzanm786@gmail.com`.
  - **Unsubscribing:**
    - Gmail's one-click unsubscribe marks the contact unsubscribed in Resend;
    - a test broadcast to each topic shows Resend's topic page;
    - after unsubscribing, the next broadcast doesn't arrive;
    - typing the address again in a fresh first run sends no second welcome.
- [ ] **Release** with `make release` (its new guard passes only once the address is set). Existing copies get the email screen on their next Sparkle update.
