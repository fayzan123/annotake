# Flipbook: research notes (2026-09-23)

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
