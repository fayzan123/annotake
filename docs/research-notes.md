# Annotake: research notes (2026-09-23)

These are the facts behind [spec.md](spec.md) and [v2-backlog.md](v2-backlog.md), gathered in three web-research passes on 2026-09-23. **(V)** means the claim was seen in the cited source; **(I)** means it's an inference. Recheck anything version-sensitive before relying on it.

## ScreenCaptureKit

**Frame status and dirty rects**
- `SCFrameStatus` has six values: complete, idle ("display didn't change"), blank, suspended, started, stopped. (V) [docs](https://developer.apple.com/documentation/screencapturekit/scframestatus)
- SCK only sends a new frame when something changes. Idle frames carry no new surface. (V) [WWDC22-10156](https://developer.apple.com/videos/play/wwdc2022/10156/)
- `dirtyRects` is "a union of the rectangles redrawn and moved", available since macOS 12.3. (V) [docs](https://developer.apple.com/documentation/screencapturekit/scstreamframeinfo/dirtyrects)
- A redraw isn't always a pixel change, so confirm with pixels. (I)
- A static screen produces no frames. Treat idle callbacks as "stream alive", and settle on timers. (V)
- No shipping app was found that picks keyframes from dirty rects. Apple presents them for partial encoding. (V) [WWDC22-10155](https://developer.apple.com/videos/play/wwdc2022/10155/)

**Recording to a file**
- `SCRecordingOutput` (macOS 15+) allows one per stream. Add it before `startCapture`, and remove it to stop recording while the stream keeps running. Defaults are H.264 in an MP4 container. (V) [WWDC24-10088](https://developer.apple.com/videos/play/wwdc2024/10088/)
- Developers run it on the same stream as `.screen` sample output. Corrupt files were reported only with microphone capture on. (V) [forum](https://developer.apple.com/forums/thread/805892)

**Filters and exclusion**
- A window filter follows the window across displays. (V)
- Exclude your own app with `SCContentFilter(display:excludingApplications:)`. (V)
- `sharingType = .none` is not honored on macOS 15.4+ (Apple DTS), so exclude your own windows through the filter. (V) [forum](https://developer.apple.com/forums/thread/792152)
- Windows created after the filter may still be captured, so create panels at launch. (I)
- Filters and configuration can be updated while the stream runs. (V)

**Latency and cost**
- `SCShareableContent` is usually fast, but has been reported to take 5+ s or hang. Cache it, refresh it on display changes, and use a timeout. (V) [forum](https://developer.apple.com/forums/thread/804083), [Nonstrict sample](https://github.com/nonstrict-hq/SCShareableContent-hangs-sample)
- First-frame latency is 30–100 ms at 1080p and 50–150 ms at 4K. The method wasn't stated. (V) [screencapturekit-rs README](https://github.com/doom-fish/screencapturekit-rs)
- A stream kept warm between recordings:
  - keeps the recording indicator lit,
  - shows "Your screen is being observed" on the lock screen,
  - costs battery. (V)
- `SCScreenshotManager` for every frame is expensive and flashes the indicator. (V)

**Permission prompts**
- Sequoia shows "…requesting to bypass the system private window picker…" with an **Allow For One Month** button. The prompt still exists on Tahoe. (V) [9to5Mac](https://9to5mac.com/2024/08/14/macos-sequoia-screen-recording-prompt-monthly/)
- It's triggered by `SCShareableContent` or `SCScreenshotManager` use outside the system picker. (V) [DTS](https://developer.apple.com/forums/thread/765103)
- `SCContentSharingPicker` avoids the prompt, but needs a pick every session. (V/I)
- CleanShot X and similar apps live with the prompt. (V)

## Trigger key and event taps

**Secure Input**
- Password fields, Terminal's Secure Keyboard Entry, and 1Password turn on Secure Input. While it's on, taps stop receiving key down/up events. (V)
- flagsChanged events still arrive, and Carbon `RegisterEventHotKey` is unaffected. (V) [Handy secure_input.rs](https://github.com/cjpais/Handy/blob/main/src-tauri/src/secure_input.rs), [Wispr docs](https://docs.wisprflow.ai/articles/8841649969-fix-flow-shortcuts-blocked-by-macos-secure-keyboard-entry-secure-event-input)

**Permissions** (V) [DTS](https://developer.apple.com/forums/thread/780626)

| Method | Permission needed |
|---|---|
| NSEvent global monitor | Accessibility |
| Listen-only `CGEventTap` | Input Monitoring |
| Active tap | Accessibility (two underlying permissions, both shown as "Accessibility") |
| Carbon hotkey | None |

**Tap reliability**
- Revoking Accessibility while an active tap was installed blocked all clicks until reboot (2023 report). (V)
- The system can disable a tap on timeout, so re-enable it when that happens. (V)
- Ad-hoc-signed rebuilds silently lose their permission grants, so sign with a stable identity. (V)

**Right ⌘ and click cleanup**
- Keycodes: Right ⌘ = 54, Right ⌥ = 61. Both arrive via flagsChanged. Detection with a listen-only tap survives Secure Input. (V/I)
- WebKit and Chromium/Electron read modifiers from each mouse event's own flags, so stripping ⌘ in an active tap yields plain clicks. (V) [WebKit](https://github.com/WebKit/webkit/blob/main/Source/WebCore/platform/mac/PlatformEventFactoryMac.mm), [Chromium](https://chromium.googlesource.com/chromium/src.git/+/refs/tags/124.0.6353.1/content/common/input/web_input_event_builders_mac.mm)
- Code that reads global modifier state (`+[NSEvent modifierFlags]`, `CGEventSourceFlagsState`) still sees ⌘, and Finder drag operations probably do too. A tap can't clear the hardware state. (I)

**Telling a tap from a shortcut** (Hyperkey pattern) (V) [EventTap.swift](https://raw.githubusercontent.com/feedthejim/hyperkey/main/Sources/hyperkey/EventTap.swift)
- If another key arrives while the trigger is held, mark it "used".
- On release, an unused press shorter than ~250 ms is a tap.
- Handy treats two taps within 400 ms as a double-tap. (V) [Handy PR 1547](https://github.com/cjpais/Handy/pull/1547)
- Don't re-inject events with `CGEventPost`. One report says macOS 26.5 drops synthetic keystrokes from unsigned apps. (V) [report](https://www.nick-liu.com/posts/tahoe-hotkey-dead-end/)
- Holding both ⌘ keys caused stuck modifiers in Karabiner 16.3.0. (V)

**Other apps' gestures** (V)
- Wispr Flow:
  - Hold fn to dictate.
  - Hands-free mode is fn+Space, or a double-tap of fn within 0.5 s.
  - Esc cancels.
  - Up to 4 bindings are allowed, and Caps Lock can't be used.
- Superwhisper: push-to-talk, where a quick tap toggles recording.
- ChatGPT/Codex Appshots: press both ⌘ keys.
- Claude Quick Entry: double-tap ⌥.

## Overlays (panels)

- **Native:** `NSPanel` with `.nonactivatingPanel`, `.canJoinAllSpaces`, and `.fullScreenAuxiliary`, level ≥ status bar, in an accessory app. A plain NSWindow of an inactive app can't join full-screen Spaces. (V) [PR](https://github.com/karansinghgit/speaktype/pull/142)
- **Tauri:** tauri-nspanel is used by Cap, Screenpipe, and Handy. (V) Known problems:
  - An open bug says panels take focus on macOS 27. [#123](https://github.com/ahkohd/tauri-nspanel/issues/123)
  - `transparent:true` uses about 8× the GPU. [#15471](https://github.com/tauri-apps/tauri/issues/15471)
  - Window level and Spaces behave differently in dev and release builds.
- **Electron:**
  - `type:'panel'` exists, but focus and click bugs were closed as "not planned". (V) [#45892](https://github.com/electron/electron/issues/45892), [#35815](https://github.com/electron/electron/issues/35815)
  - `globalShortcut` has no key-up event, and uiohook-napi can't block events. (V)

## Stack comparison (why native Swift)

- **Native Swift:**
  - Full access to the whole macOS toolkit: SCK metadata, zero-copy vImage/Metal, `SCRecordingOutput`, NSPanel, event taps, and Accessibility. The app is a few MB.
  - Builds with `swift build` plus a Makefile, using Command Line Tools only. (V) [hyperkey Makefile](https://github.com/feedthejim/hyperkey)
- **Tauri:**
  - The `screencapturekit` crate exposes dirty rects, frame status, and `SCRecordingOutput`. (V)
  - In one test the bundle was 8.6 MiB versus 244 MiB for Electron. (V) [Hopp](https://www.gethopp.app/blog/tauri-vs-electron)
  - It means working in Rust and TypeScript, and every hard part is still native glue code.
- **Electron:** `desktopCapturer` exposes no change metadata, so it needs native helpers. (I)
- **Shipping apps and their stacks** (V):
  - Cap and Handy: Tauri.
  - Kap, Screen Studio, Loom: Electron plus native recording layers.
  - Wispr Flow: Electron, according to a job posting.
- **Toolchain:**
  - CLT 14.3 can't compile `SCScreenshotManager` (needs 14.0) or `SCRecordingOutput` (needs 15.0).
  - The newest toolchain that runs on Sequoia 15.7 is 26.3 (macOS 26.2 SDK, Swift 6.2.3). Version 26.4 and later need Tahoe. (V) [Apple table](https://developer.apple.com/support/xcode/)

## Frame selection

**Existing detectors and how they fail on screen content**
- **ffmpeg `mpdecimate`:** compares each frame to the last kept frame, using SAD on 8×8 blocks. A frame counts as different if any block exceeds `hi` (768), or if more than `frac` (0.33) of blocks exceed `lo` (320). (V) [ffmpeg docs](https://ffmpeg.org/ffmpeg-filters.html)
  - It keeps caret blinks, cursor moves, and spinners. (I)
- **ffmpeg scene score:** a whole-frame mean absolute difference, so a typed line averages away. (I)
- **PySceneDetect:** tuned for film cuts. On 61 GUI recordings it scored F1 0.475, versus 0.880 for SSIM steady-state detection. (V) [GIFdroid, arXiv 2112.04128](https://arxiv.org/abs/2112.04128)
- **GIFdroid:**
  - Frames with SSIM ≥ 0.954 count as similar, and 5 similar frames in a row count as "steady".
  - Reported misses: slow loads captured half-rendered, early clicks skipping states, ads and video that never settle. (V)
- **Perceptual hashes:** text edits vanish at thumbnail size, so they're only good for a final dedup pass. (I)

**Event-driven capture and settling** (V)
- screenpipe triggers on app switch, click, typing pause, scroll, and clipboard, with an idle fallback.
- Steps Recorder takes one shot per click.
- OpenCUA takes the "last visually distinct frame" before the pointer moved.
- video2pdfslides captures when less than 0.1% of the frame is changing, and re-arms at ≥ 3%.

**Picking N of M frames** (I)
- Visvalingam–Whyatt greedy removal is O(M log M) and produces a nested removal order.
- Uniform-plus-peaks oversamples idle stretches.
- Clustering ignores time order.
- Dynamic programming is O(N·M²) and its subsets aren't nested.
- Reference: [Visvalingam–Whyatt](https://doi.org/10.1179/000870493786962263)

**Reference implementation: Pointer** (MIT, [github.com/abhitsian/pointer](https://github.com/abhitsian/pointer)) (V, README)
- Diffs a 96×96 grayscale thumbnail on a 12×12 grid. A cell counts as changed when its mean moves by more than 10 levels.
- Changes shorter than 1 s count once, at their settled state.
- Keeps 6–12 frames, at most 2000 px.
- Names clicked elements via Accessibility.

## AI image limits (basis for the defaults)

- **Claude API:** (V) [vision docs](https://platform.claude.com/docs/en/build-with-claude/vision)
  - Up to 600 images per request (100 for 200k-context models). claude.ai allows 20 per message.
  - Images can be up to 8000 px, but must each be ≤ 2000 px once a request holds more than 20 images. Earlier turns count.
  - Size limits: 10 MB per image as base64, 32 MB per request.
  - Tokens = ⌈w/28⌉·⌈h/28⌉.
  - Claude 4.7+ accepts up to 2576 px (4784 tokens); older models 1568 px.
- **Claude Code:**
  - Images come in by drag-and-drop, Ctrl+V, or file path, and are not resized. (V)
  - One image over 2000 px in a many-image session blocks every turn until `/compact`. (V) [#53170](https://github.com/anthropics/claude-code/issues/53170), [#46656](https://github.com/anthropics/claude-code/issues/46656)
- **OpenAI:**
  - Up to 1,500 images or 512 MB per request.
  - Cost is ⌈w/32⌉·⌈h/32⌉ patches × 1.2.
  - On GPT-5.5+, "auto" means original resolution. (V)
  - The ChatGPT app allows 20 MB per image. It's reported to allow 10 images per message, possibly 20 on the web since Feb 2026 (unverified).
- **Gemini:** (V)
  - Video is sampled at 1 fps by default.
  - Gemini 3 costs 70 tokens per video frame versus 1,120 per image.
  - Keyframes beat native video for text-heavy UI. (I)
- **Contact sheets:** there's a trade-off between resolution and frame count, and text accuracy tracks effective resolution. Separate frames are better for UI text. (V/I) [IG-VLM](https://arxiv.org/abs/2403.18406)

## Distribution

- **Signing and notarization:** (V) [notarization docs](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
  - The Apple Developer Program costs $99/yr.
  - Notarization needs Developer ID, the hardened runtime, a secure timestamp, and no get-task-allow.
  - Use `notarytool`; altool has been refused since November 2023.
- **macOS 15** removed Control-click as a way to open unsigned apps. (V)
- **Homebrew:** since 2026-09-01 the main cask repo has disabled casks that fail Gatekeeper. A personal tap is unaffected. (V) [discussion 6334](https://github.com/orgs/Homebrew/discussions/6334), [brew#20755](https://github.com/Homebrew/brew/issues/20755)
- **Caps Lock remap** via `hidutil`: no sudo needed per Apple TN2450, but it's lost on restart. (V) [TN2450](https://developer.apple.com/library/archive/technotes/tn2450/_index.html)
- **Mac App Store:** (V)
  - The sandbox allows SCK and listen-only taps, but not Accessibility or active taps.
  - Apps using `CGEvent.post` were rejected under guideline 2.4.5 in 2026.

## Windows (for a future port)

- Windows.Graphics.Capture has per-frame `DirtyRegions` and `DirtyRegionMode` in SDK 10.0.26100 (Windows 11 24H2). (V) [docs](https://learn.microsoft.com/en-us/uwp/api/windows.graphics.capture.direct3d11captureframe.dirtyregions)
- DXGI Desktop Duplication reports dirty and move rects, which may be merged and over-report. (V) [docs](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/desktop-dup-api)

## Prior art (reference only, not a driver)

- **Pointer:** open-source (MIT) Swift menu-bar app, public on 2026-09-23. Needs macOS 26+ and must be built from source.
  - ⌃⌥V records video and produces changed frames with Accessibility click names, OCR diffs, and voice.
  - It pastes into the last-used assistant and has an MCP server.
  - A personal rebuild of Capi (trycapi.com, unreleased, voice + point screenshots).
- **Other tools:**
  - claude-video: a skill that turns a video into frames.
  - Loom Video Prompts: Chrome only, paid.
  - ChatGPT/Codex Appshots and Claude Quick Entry: single screenshots.
- **Demand signals:**
  - Claude Code's video-input request [#12676](https://github.com/anthropics/claude-code/issues/12676) is open, with 45 👍 as of 2026-09-23.
  - Cursor forum threads ask for video input.
  - The 84EM blog describes extracting ffmpeg `fps=1` frames for Claude Code.

## Pricing, competitors, and selling (2026-09-28)

This research is for the [distribution design](plans/2026-09-30-distribution-design.md). Prices change, so recheck them before relying on any of them.

**Wispr Flow**
- **Free plan:** 2,000 words a week on desktop, 1,000 on mobile. (V) [pricing](https://wisprflow.ai/pricing)
  - On the Mac, 2,000 is a soft cap that slows Flow down, and 5,000 is a hard cap that rejects the next dictation. (V) [docs](https://docs.wisprflow.ai/articles/3715544288-weekly-word-limit-not-resetting-troubleshooting-guide)
  - Counts reset Sunday at 12 a.m. Pacific. (V, same doc)
  - Counters appear only within 200 words of the cap, and "if Flow cannot confirm your plan, no limit is applied". (V) [docs](https://docs.wisprflow.ai/articles/4760791189-free-tier-weekly-word-cap-and-bonus-words-remove-desktop-trial-experiment)
- **Pro:** $15 per user per month, or $144 a year. (V) [plans](https://docs.wisprflow.ai/articles/9559327591-flow-plans-and-what-s-included)
- **Trial:** a 14-day Pro trial is "standard", and no card is needed. (V) The cap doc's URL suggests Wispr is testing no trial on desktop. (I)
- **Referrals:** the friend gets a 30-day Pro trial, and the referrer gets a month of Pro once the friend dictates enough or upgrades. (V) [docs](https://docs.wisprflow.ai/articles/6496688316-how-to-find-your-referral-link)
- **Affiliates:** 25% of revenue for the first year. (V) [partners](https://partners.dub.co/flow)
- **Account required:** setup is "Install Flow, sign in, grant permissions". (V) [setup](https://docs.wisprflow.ai/articles/3152211871-setup-guide)
- **Growth:**
  - creator videos, which the CEO says hit "500m views in 60 days" (V) [X](https://x.com/tankots/status/2016205317890089273);
  - referrals, founder posts, and inbound enterprise sales (V, secondary) [Postbeam](https://www.postbeam.ai/blog/how-wisprflow-grows).
- **Funding:** a $280M Series B at a $2B valuation, August 2026. (V) [TechCrunch](https://techcrunch.com/2026/08/17/wispr-raises-280m-at-2b-valuation-as-it-looks-beyond-dictation/)
- **Paying share:** about 19% of users paid between July 2024 and July 2025. (V, stale) [Wikipedia](https://en.wikipedia.org/wiki/Wispr_Flow)

**Comparable Mac apps** (all V)

| App | Price and model | Link |
|---|---|---|
| CleanShot X | $35 once with a year of updates ($19 a year to renew); Cloud Pro $10 per user per month, billed yearly; closed | [pricing](https://cleanshot.com/pricing) |
| Shottr | pay what you want; closed | [site](https://shottr.cc) |
| Screen Studio | $29 a month, or $9 a month billed yearly; closed | [site](https://screen.studio) |
| Cap | AGPL; desktop licence $29 a year or $58 lifetime; Pro $12 a month | [pricing](https://cap.so/pricing) |
| Loom | free for 25 videos of 5 minutes; Business $18 per user per month | [pricing](https://www.loom.com/pricing) |
| Raycast | free; Pro $10 a month ($96 a year) | [pricing](https://www.raycast.com/pricing) |
| Superwhisper | Pro $8.49 a month, $84.99 a year, or $249.99 lifetime (from a third-party source) | [site](https://superwhisper.com) |
| MacWhisper | Pro €65 once | [Gumroad](https://goodsnooze.gumroad.com/l/macwhisper) |
| Handy | free, MIT, funded by sponsors | [site](https://handy.computer) |
| Rectangle / Rectangle Pro | free and MIT / $9.99 once | [Pro](https://rectangleapp.com/pro) |
| Aseprite | $19.99 for the binary; the source is public under an EULA | [trial](https://www.aseprite.org/trial/) |

**Direct competitors** (all V)
- **AI, Look!:** a Mac recorder that pins key frames for Claude Code. Weekly free cap; Pro $20 a year. [site](https://ai-look.app)
- **Clipy:** Mac and Chrome, with Markdown output and an MCP server. Free for 15 recordings or 2 hours, then $9 a month or $72 a year. [pricing](https://clipy.online/pricing)
- **Deiko:** double-tap Right ⌥, point, and talk. Local, no account, free beta, with $3.99 a month floated as the price. Its Hacker News posts got 1 and 5 points. [site](https://deiko.app)
- **Loom Video Prompts:** Chrome only, on Business+AI ($24 per user per month) and Enterprise. A recording becomes an action plan for Claude or Cursor, or Jira tickets. [blog](https://www.atlassian.com/blog/loom/introducing-loom-video-prompts)
- **BugReel** (found 2026-09-30): an open-source, self-hosted Chrome extension. A recording becomes a bug card with key frames, exported to Jira, Linear, or GitHub. [site](https://bugreel.io/)
- **claude-video:** an MIT Claude Code skill that turns video into frames, with 17.8k★. [GitHub](https://github.com/bradautomates/claude-video)
- **Pointer:** MIT, build from source, macOS 26+, 0★ on 2026-09-28. [GitHub](https://github.com/abhitsian/pointer)
- **The platforms:**
  - Claude Code has no video input. Issue #12676 is open with 45 👍 and no reply from Anthropic. [issue](https://github.com/anthropics/claude-code/issues/12676)
  - Claude Code's computer use can take its own screenshots and reproduce bugs. [docs](https://code.claude.com/docs/en/computer-use)
  - Cursor's forum request for video input has 6 votes. [forum](https://forum.cursor.com/t/agent-and-chat-should-accept-video-as-input/103864)

**Selling outside the App Store** (all V)

| Provider | Fee | Licence keys | Link |
|---|---|---|---|
| Polar | 5% + 50¢ for accounts created since 2026-05-27; +1.5% on non-US cards | built in, checked online | [fees](https://polar.sh/docs/merchant-of-record/fees) |
| Paddle | 5% + 50¢ | delivers keys you supply | [pricing](https://www.paddle.com/pricing) |
| Lemon Squeezy | moving users to Stripe Managed Payments (3.5% on top of Stripe's fees) | built in | [2026 update](https://www.lemonsqueezy.com/blog/2026-update) |
| Gumroad | 10% + 50¢ | built in | [pricing](https://gumroad.com/pricing) |
| Keygen | licensing only; doesn't handle tax | signed keys that can be checked offline | [plans](https://api.keygen.sh/v1/plans) |

- **Sparkle 2.10.0** (2026-09-13) needs macOS 12+ and fixes delta updates on macOS 27. [release](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0)
- **macOS 27** shipped 2026-09-14 and runs on Apple silicon only. [MacRumors](https://www.macrumors.com/2026/09/10/macos-27-golden-gate-release-date/)
- **New Apple developer accounts** have reported notarization blocked for days with error 7000. [forum](https://developer.apple.com/forums/thread/819982)
- **Open source and paid together:**
  - Rectangle is MIT with 30k★ and sells the closed Rectangle Pro. [GitHub](https://github.com/rxhanson/Rectangle)
  - VoiceInk is GPL and sells one-time binaries at $25–49, which fund full-time work. [site](https://tryvoiceink.com)
- **No quarantine flag from `curl`:** files that `curl` downloads in Terminal don't get one, so Gatekeeper doesn't check them. The early install relies on this. (V: on 2026-09-30, a `curl` install of the release zip left 0 quarantine entries, and the app passed `codesign --verify --strict --deep`)

## Naming checks (2026-09-30)

- **Method:**
  - Registry lookups over RDAP: Verisign for .com and Google Registry for .app and .dev. A 404 means the name is unregistered.
  - These lookups don't show premium prices: shown.dev was unregistered but premium-priced.
  - Google's endpoint rate-limits rapid lookups. About one second between queries works.
  - Then a web search, GitHub, and the App Store for namesakes.
- **Taken on all of .com, .app, and .dev:** most dictionary words tried, including riffle, retake, footage, witness, tattle, seen, kino, loupe, repro, receipts, encore, showme, cuecard, shotlist, groundtruth, keypoint, zeroshot, oneshot, mosaic, grounding, annotate, and checkpoint.
- **Flipbook:** flipbook.app, flipbook.dev, flipbook.so, getflipbook.app, and useflipbook.com are registered, several by live products called FlipBook or Flipbook. flipbookapp.com is for sale through HugeDomains.
- **Namesakes that ruled names out:**
  - **Flipshot:** a Samsung Galaxy Z Flip feature and a Steam game. [Android Authority](https://www.androidauthority.com/samsung-cover-screen-features-good-lock-3576572/)
  - **Opsis:** a Mac productivity app. [opsis.app](https://opsis.app/)
  - **Showcard:** the SHOW Mastercard and two apps.
  - **Lookit:** Lookit AR on the Mac App Store, MIT's research platform, and a 2011 screenshot uploader. [App Store](https://apps.apple.com/us/app/lookit-ar/id1104409821)
  - **Framecard:** a Framer template, and photo-frame greeting cards fill its search results.
  - **BugReel:** bugreel.io.
  - **SnapSteps:** a Chrome extension that turns browser actions into step-by-step guides. [Chrome Web Store](https://chromewebstore.google.com/detail/snapsteps-nrkgo/dpifnpdnkolgcjffopnghkocmaomjedd)
  - **Kinora:** its get- and -app domains are registered too.
- **Clean, with domains available:** ReproReel (.com, .app, .dev), StepFlip (.app, .dev), and Shown on longer domains (getshown.app, tryshown.com).
- **Annotake, the choice:**
  - annotake.app, annotake.com, annotake.dev, and anotake.app were unregistered.
  - No GitHub project uses the name.
  - A Figma plugin exports design annotations under it. [Figma](https://www.figma.com/community/plugin/1562003383248990114/annotake)
  - Search engines show "annotate" dictionary pages first.
