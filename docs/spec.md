# Flipbook: v1 spec

**Status:** approved design, 2026-09-23 · **Owner:** Fayzan Malik · **Platform:** macOS 15 and later

Companion docs:
- [v2-backlog.md](v2-backlog.md): everything deliberately left out of v1, with the design notes gathered so far.
- [research-notes.md](research-notes.md): the facts and sources behind these decisions.

## 1. Summary

Flipbook is a macOS menu-bar app. Hold Right ⌘ (or double-tap it) to record what you do on screen. When you stop, Flipbook keeps only the frames where the screen meaningfully changed, one per step. It captions each frame with what you did (e.g. `Clicked button "Save"`) and shows a floating card that you drag into any AI chat or agent: Cursor, Claude Code, ChatGPT, and so on.

It exists because reproducing a Jira bug for a coding agent meant screenshotting every click by hand. Flipbook turns that into three steps: press a key, reproduce the bug, drag the card.

## 2. Principles and constraints

- **Built for Fayzan's own workflow first.** Others should be able to download and use it easily later. Competitors do not drive decisions.
- **No AI in the product.** No LLMs, no ML models, no API keys, no bills. Frames are picked by pixel comparison, and "what you clicked" comes from macOS Accessibility.
- **Never touches the network.** No telemetry, no accounts, no update checks. This keeps it acceptable on a work Mac.
- **Agent-agnostic.** The output is plain PNGs plus a text log, with no integration into any specific agent.
- **Bare-bones v1.** Anything the core loop doesn't need goes to the backlog.
- **Native Swift, macOS 15 and later** (§6). It must work on Fayzan's personal Mac (15.7) and his work Mac (26).

## 3. User experience

### 3.1 Trigger key and gestures

The default trigger is **Right ⌘**. Settings also offers Right ⌥ and fn/Globe.

| Gesture | Result |
|---|---|
| Hold Right ⌘ alone for 250 ms | Recording starts (**hold mode**). Release → stop → card. |
| Double-tap Right ⌘ (second press within 300 ms of the first release) | Recording starts at the second press (**hands-free mode**). |
| Double-tap again while hands-free | Stop → card. |
| Right ⌘ + Esc while recording | Cancel. Nothing is saved. |
| Single tap | Nothing. Reserved for the v2 ring. |
| Another key or mouse button pressed while Right ⌘ is down, before 250 ms | It was a shortcut (⌘C, ⌘-click). Flipbook ignores it and the shortcut works normally. |

Rules:
- A **tap** is a press and release within 250 ms, with no other key or mouse button in between.
- **Plain Esc always passes through** to the app being recorded, because closing a dialog can be part of the bug. The Esc in Right ⌘ + Esc is consumed by Flipbook and never reaches the app.
- **While recording in either mode:**
  - Right ⌘ shortcuts such as Right ⌘+S pass through normally and don't stop the recording.
  - Single taps are ignored.
- **Click cleanup (hold mode only).** The key is held while you click, so during a hold recording Flipbook removes ⌘ from mouse and scroll events. Clicks stay plain clicks.
  - In hands-free mode nothing is changed, so a deliberate ⌘-click still works.
- The hold threshold (250 ms) and the double-tap window (300 ms) are adjustable in Settings → Advanced.

### 3.2 While recording

- **Pill.** Shown at the bottom center of the recorded screen:
  - Hold mode: `● 0:04 · 3 frames · release ⌘ to stop`
  - Hands-free mode: `● 0:12 · 5 frames · double-tap ⌘ to stop · ⌘Esc cancels`
- **Sounds.** Soft start and stop sounds, controlled by a Settings toggle that is on by default.
- **Time limit.** Hands-free recordings stop and save automatically at **5 minutes**. Hold recordings end when the key is released.
- **Accidental holds.** Recordings shorter than **0.5 s** are discarded silently.
- **Never in the frames:** Flipbook's own windows (pill, cards, filmstrip, Settings) and **notification banners**.
- **Cursor.** The cursor is visible in frames because it explains hover states, but it is ignored when deciding what changed.

### 3.3 What gets recorded

- **Default:** the screen the cursor is on when recording starts.
- **Settings → Record** uses a Google Meet-style picker:
  - **Entire screen:** "Screen with the cursor" (the default) or a specific screen, chosen from thumbnails.
  - **Window:** a thumbnail grid of open windows. Window capture follows the window across screens.
- **Fallback.** If the chosen window no longer exists, or the chosen screen is disconnected, Flipbook records the cursor's screen and the pill says so: "Window not found — recording your screen".
  - Windows are matched by ID only, never guessed by title.

### 3.4 The card and filmstrip

- **The card.** When a recording stops, a card appears at the bottom right of the screen the cursor is on.
  - It shows stacked thumbnails, the frame count, and the duration.
  - It appears immediately and becomes draggable when export finishes. The target is under 1.5 s.
- **Dragging the card** drops all frames, in order, as PNG files.
  - This works in chat inputs (Cursor, Copilot, ChatGPT, Claude web), Slack, and Jira.
  - Terminals receive the file paths.
- **Dismissing.** After a successful drop the card disappears. ✕ or a swipe right dismisses it.
  - Otherwise cards stay until dragged or dismissed, and new cards stack on top of older ones.
- **Clicking the card** opens the **filmstrip**, a horizontal strip of the frames with their captions.
  - Click ✕ on a frame to remove it. Clicking again restores it while the filmstrip is open.
  - Drag a single frame out of the strip.
  - Closing the filmstrip applies the removals:
    - Removed frames move to the capture's hidden `.raw/removed/` folder.
    - The remaining frames are re-rendered and renumbered with no gaps (1/6 … 6/6).
    - A removed frame's actions merge into the previous frame's caption.
    - `steps.md` is regenerated.
- **Recent Captures** in the menu bar brings back the cards for the last 5 captures.

### 3.5 Menu bar

- **Icon:** shows idle or recording.
- **Menu:**
  - Start/Stop Recording (a fallback when the key isn't available)
  - Recent Captures ▸ (last 5)
  - Open Captures Folder
  - Settings…
  - Quit
- There is no Dock icon.

### 3.6 Settings

| Section | Setting | Default |
|---|---|---|
| General | Trigger key: Right ⌘ / Right ⌥ / fn | Right ⌘ |
| | Sounds | On |
| | Launch at login | On |
| Record | Entire screen (the cursor's, or a specific one) or Window | Screen with the cursor |
| Output | Max frames (2–50) | 20 |
| | Frame size (long edge): 1920 px, or 1568 px compact | 1920 px |
| | Caption strip | On |
| | Click markers | On |
| | Save location | `~/Pictures/Flipbook` |
| | Keep captures: 7 days / 30 days / forever | 30 days |
| Permissions | Status of each permission, with "Open System Settings" | — |
| Advanced | Hold threshold | 250 ms |
| | Double-tap window | 300 ms |
| | Save raw sessions (for tuning, §8) | Off |

Choosing fn shows a note with two warnings:
- macOS's "Press 🌐 key to" setting must be "Do Nothing".
- Dictation apps (Wispr Flow, Handy) often use fn already.

### 3.7 First launch

First launch walks through three permissions, then asks you to double-tap Right ⌘ to try it:
1. **Screen Recording:** required to record.
2. **Input Monitoring:** needed to see Right ⌘, clicks, and keys.
3. **Accessibility:** needed for click cleanup and button names.

For each permission it:
- explains why in one sentence,
- deep-links to the right System Settings pane,
- re-checks the permission live.

Flipbook works with only 1 and 2, in a degraded mode (§7). Spike M0 confirms exactly which permission each capability needs.

First launch also registers Flipbook to launch at login (`SMAppService`), because the key has to work right after a restart. It can be turned off in Settings → General.

## 4. Output

### 4.1 Folder layout

```
~/Pictures/Flipbook/
  2026-09-23 at 14.05.12/
    01_0m00s.png
    02_0m03s.png
    …
    steps.md
    .flipbook          # marker file: cleanup only ever touches folders that have it
    .raw/              # unrendered kept frames, used to re-render after trims
      removed/         # frames removed in the filmstrip
```

- Captures are written to a temp folder and moved into place once complete, so a crash never leaves a half-finished capture.
- **Cleanup** runs at launch and every 24 h. It moves capture folders older than the retention period to the Trash, but only if they contain `.flipbook`.

### 4.2 Frames

- **Format:** PNG.
- **Size:** the long edge is at most 1920 px by default (1568 px in compact mode). The final image, caption strip included, never exceeds 2000 px on either side, because Claude rejects larger images once a conversation holds more than 20.
- **File names:** a two-digit step number plus the time from start, e.g. `03_0m07s.png`. The order survives any tool.
- **Click markers:** a high-contrast ring at each click point, on the frame where the click happened. When a frame has more than one click, the rings are numbered.
- **Caption strip:** drawn under the screenshot, never over it.

```
3/8 · 0:07 · Clicked button "Save"
Google Chrome — Dayforce · Timesheets
```

Line 1 is step/total · time · action(s). Line 2 is app — window title.

### 4.3 steps.md

```
# Flipbook capture — 2026-09-23 at 14.05.12
Screen: Built-in Retina Display · 0:21 · 8 frames (from 12 candidates)

1. 0:00 · Google Chrome — Dayforce · Timesheets · Start
2. 0:03 · Google Chrome — Dayforce · Timesheets · Clicked pop-up button "Country"
3. 0:07 · Google Chrome — Dayforce · Timesheets · Clicked button "Save"
4. 0:09 · Google Chrome — Dayforce · Timesheets · Screen changed
…
8. 0:21 · Google Chrome — Dayforce · Timesheets · End
```

### 4.4 What the log records, and what it never records

| Event | Logged as |
|---|---|
| Click on a labeled element | `Clicked <role> "<label>"` (from macOS Accessibility) |
| Click with no label available | `Clicked at (x, y)` |
| Right-click / double-click | `Right-clicked …` / `Double-clicked …` (same forms as a click) |
| Typing | `Typed in field "<label>"`. The typed text is never logged. |
| Return / Esc | `Pressed Return` / `Pressed Esc` |
| ⌘ or ⌃ shortcut | e.g. `Pressed ⌘S` |
| App or window switch | `Switched to <app> — <window>` |
| Scroll | `Scrolled` |
| Change with no input | `Screen changed` |

Never recorded:
- typed text,
- anything in password fields. Secure text fields are never read, and macOS also blocks key events there.
- audio.

## 5. Frame picking

Every number here is a starting point. Numbers are tuned against recorded sessions (§8) and then locked in by golden tests.

### 5.1 Inputs

- **Frames:** a ScreenCaptureKit stream of the target, at up to 10 fps, already scaled to the output size, with the cursor shown.
  - macOS delivers a new frame only when the screen changed, and reports the changed ("dirty") rectangles.
  - Idle and blank frames are skipped.
- **Tile signatures:** each frame is reduced to a grayscale copy at ¼ scale and split into 8×8-pixel tiles (≈32 px at output size).
  - A tile's signature is its 4×4 grid of mean brightness values.
  - Core never sees raw pixels.
- **Input events:** clicks (with their Accessibility label), keys (class only, never content), scrolls, app/window switches, and the cursor position.

### 5.2 What counts as change

- A tile has **changed** if its signature's mean absolute difference from the comparison frame exceeds 3/255.
- Three things are ignored:
  - Tiles under the cursor, at both its old and new position.
  - A **blinking caret**: a thin dirty rect, at most 4 × 48 pt, toggling on and off. Its tiles stay ignored for 2 s.
  - **Busy regions** such as video, spinners, and animated ads. Tiles that changed in ≥ 60% of frames over the last 1.5 s (with at least 5 frames in that window) are masked until they have been still for 2 s. Two kinds of frame don't count toward this: frames that change more than half the screen, and frames that arrive while you're scrolling. Otherwise scrolling would look like a spinner.
- **Motion** means at least 2 changed tiles remain after those exclusions. A single isolated tile, like a clock digit, doesn't count.
- **D(a, b)** is the fraction of tiles that differ between frames a and b. It ignores busy tiles, recent caret tiles, and tiles under the cursor in either frame.

### 5.3 Triggers, settle, keep

- **Pending.** A frame might be needed when either of these happens:
  - **Input:** the mouse-up of a click, Return, Esc, a ⌘/⌃ shortcut, an app/window switch, the end of a scroll (no scroll events for 0.3 s), or a 1.2 s pause in typing.
  - **Visual:** D(last kept, current) ≥ 0.02, or ≥ 0.005 when nothing has been kept for 10 s.
- **Settle.** A pending trigger resolves once there has been no motion for 400 ms. The 400 ms are counted from the later of the last motion and the trigger itself, so a click's result has time to appear. After 3 s it resolves anyway, using the latest frame.
- **Keep.** The settled frame is kept if D(last kept, settled) ≥ 0.005.
  - When the trigger was a click, a commit (Return, Esc, or a shortcut), a switch, or a typing pause, a single changed tile is enough. A ticked checkbox, an inline error, or a filled-in field still counts.
- **Scrolling.** Each time scrolling has moved ≥ 80% of a screen since the last kept frame, the latest frame is kept immediately, without waiting to settle.
- **Start and stop.**
  - The first frame is always kept.
  - At stop, Flipbook waits up to 1 s for the screen to settle, then keeps the final state if it differs from the last kept frame.

### 5.4 Each frame is "the screen, plus what I did on it"

At mouse-down, the click (point, label, app, window) is attached to the current screen state:
- If the screen still matches the last kept frame, the click is attached to that frame.
- Otherwise, the latest frame before the click is kept as a new frame and the click is attached to it.

The result of the click becomes the next frame once it settles. Every frame therefore reads "this was the screen, and this is what I did on it". Several clicks on an unchanged screen stack on one frame, with numbered markers.

Non-click actions attach the same way: typing, Return, shortcuts, switches, and scrolls.

### 5.5 Fitting the cap

When more than N frames were kept (N = 20 by default), Flipbook repeatedly removes the frame whose removal loses the least. This is a greedy method in the style of Visvalingam–Whyatt line simplification:

```
cost(k) = D(prev,k) + D(k,next) − D(prev,next)   # what k adds over its neighbors
        + bonus(k)                               # click .15 · Return/shortcut .15 · app switch .30 · scroll end .05
        + 0.05 · (t_next − t_prev) / duration    # discourages big time gaps
First and last frames are pinned. Remove the lowest-cost frame, update its neighbors, repeat until N remain.
```

- A removed frame's actions merge into the previous kept frame's caption and stay in `steps.md`, so no action disappears.
- The candidate pool is capped at 300 per recording. When it fills up, the same greedy step trims it to 150.

## 6. Architecture

- **Toolchain:** native Swift (Swift 6.2), built with SwiftPM and a Makefile. There is no Xcode project.
- **App identity:** bundle id `com.fayzanmalik.flipbook`, `LSUIElement` (menu-bar only), minimum macOS 15.0.

```
Sources/
  FlipbookCore/     Foundation only, no macOS frameworks:
                    frame picker (§5), gesture recognizer (§3.1), cap fitting (§5.5),
                    caption and steps.md text
  FlipbookCapture/  ScreenCaptureKit: target resolution, stream, frame → tile signatures
  FlipbookInput/    event taps: trigger key and click cleanup; clicks/keys/scrolls;
                    Accessibility labels; active app/window tracking
  FlipbookExport/   scaling, click markers, caption strips, PNGs + steps.md,
                    folder writes, retention cleanup
  Flipbook/         the app: menu bar, pill, card, filmstrip, Settings, first launch,
                    SessionController
  flipbook-replay/  CLI: runs a saved raw session through FlipbookCore and prints its decisions
Tests/
  FlipbookCoreTests/  unit and golden tests
  Fixtures/           raw sessions (never work data, see §8)
```

**Why Core has no macOS code:** it is the part the golden tests pin down. It is also the part a future Windows version would reuse, or port against the same tests.

### 6.1 Data flow

```
Right ⌘ ─▶ Input (trigger tap) ─gesture─▶ SessionController ─start/stop─▶ Capture (SCStream)
                                               ▲                           │ tile signatures + dirty rects
Input (clicks, keys, scrolls, ─────events──────┴──────────────────────────▶ Core (frame picker)
 switches, AX labels, cursor)                                               │ keep decisions
                                                                            ▼
                                                  Capture writes full-size kept frames → temp .raw/
                                                                            │ on stop: settle, fit cap
                                                                            ▼
                                                  Export renders PNGs + steps.md → capture folder
                                                                            ▼
                                                                  Card (drag / filmstrip)
```

- **Session states:** `idle → recording(hold | handsFree) → finishing → idle`, plus `cancelled`.
- **Threads:** Capture and Core run on one serial queue, PNG writing runs on a background queue, and the UI runs on the main thread.
- **Memory:** kept frames are written to disk as soon as they are kept, so memory use stays flat.

### 6.2 Key macOS pieces

| Need | API |
|---|---|
| Capture and changed regions | ScreenCaptureKit `SCStream`, `SCStreamFrameInfo` (status, dirtyRects) |
| Exclude own windows and notification banners | `SCContentFilter(display:excludingApplications:…)`; panels are created at launch |
| Trigger and input events | `CGEventTap`: listen-only for flagsChanged/keys/mouse. The active (event-modifying) tap exists only while a recording is running. It strips ⌘ from mouse events during hold recordings, and it consumes the Esc of Right ⌘ + Esc. |
| Button names | `AXUIElementCopyElementAtPosition` plus role/title/description |
| App and window | `NSWorkspace` notifications; AX focused-window title |
| Panels that don't take focus | `NSPanel` with `.nonactivatingPanel`, `.canJoinAllSpaces`, `.fullScreenAuxiliary` |
| Scaling and encoding | vImage / Core Graphics; ImageIO (PNG) |
| Settings, launch at login | SwiftUI, `UserDefaults`, `SMAppService` |

## 7. Permissions and failure handling

| Situation | Behavior |
|---|---|
| Screen Recording missing or expired (macOS re-prompts monthly) | Pill shows "Screen Recording permission needed" with Open Settings. Nothing is saved. |
| Input Monitoring missing | The key doesn't work, but the menu bar Start/Stop still does. Settings shows the fix. |
| Accessibility missing | Still records. Hold-mode clicks keep ⌘, and captions say `Clicked at (x, y)`. |
| Accessibility revoked while click cleanup runs | macOS can block all clicks until reboot if an active tap outlives its permission. Flipbook checks trust every 2 s and removes the active tap immediately. |
| macOS disables the event tap (timeout) | Re-enabled automatically. |
| Password field / Secure Input | The trigger still works because modifier events still arrive. Typing there isn't logged. |
| Recorded window closes or screen is unplugged mid-recording | Stop and save what was captured. |
| Default window or screen missing at start | Record the cursor's screen, and the pill says so. |
| macOS's screen/window list is slow or hangs | The list is cached and refreshed on display changes. After a 2 s timeout the pill shows an error instead of freezing. |
| Disk full / write error | Error card with "Show Folder". Temp files are cleaned up, and nothing half-written lands in the captures folder. |
| Crash mid-recording | The leftover temp session is removed on the next launch. |
| Nothing changed during the recording | One frame: the first, plus the last if it differs. |

## 8. Testing

- **Core unit tests** with synthetic scenes:
  - a blinking caret,
  - cursor-only movement,
  - a toast appearing,
  - a spinner followed by a page load,
  - scrolling,
  - video playing in a corner,
  - a dialog that opens and then closes (A→B→A),
  - a click whose only result is a checkbox,
  - over-cap selection,
  - action merging.
- **Gesture tests:** timed key and mouse sequences, checked against the expected outcome:
  - hold,
  - double-tap start,
  - double-tap stop,
  - cancel,
  - "was a shortcut",
  - single tap ignored.
- **Golden tests:** raw sessions paired with the frames that should be kept. A raw session holds tile signatures, dirty rects, and events, and is saved via the Advanced setting.
  - `swift test` fails if picking changes.
  - `flipbook-replay` prints the picker's decisions, for tuning.
- **Fixture privacy:** sessions recorded on the work Mac never go in the repo, because window titles and labels can be internal. Work sessions stay local, or have all text stripped before use.
- **Manual checklist (Fayzan):**
  - Drag the card into Cursor chat, Claude Code in Terminal, ChatGPT and Claude web, Slack, and Jira.
  - Right ⌘ shortcuts still work.
  - Click cleanup works in Chrome, Safari, Cursor, and Finder.
  - Both displays.
  - Window mode.
  - Full-screen apps.
  - Password fields.
  - The pill and card never appear in frames.
  - Permissions revoked mid-use.

## 9. Build, install, distribution

- **One-time prerequisite:** Command Line Tools 26.3, the newest that runs on macOS 15.7. It includes the macOS 26.2 SDK and Swift 6.2. Install it from Software Update or developer.apple.com/download.
- **Make targets:**
  - `make cert` runs once. It creates a free self-signed signing identity so macOS permissions survive rebuilds (ad-hoc signatures silently lose them).
  - `make` builds and assembles `Flipbook.app`.
  - `make install` copies it into `~/Applications`.
  - `make zip` produces a zip for the work Mac.
- **Work Mac, until the app is notarized:**
  - The app is built only on the personal MacBook, using Fayzan's own Claude membership rather than work AI.
  - AirDrop the zip over and unzip it into `~/Applications`.
  - Once per update, run `xattr -dr com.apple.quarantine ~/Applications/Flipbook.app`.
- **Later:** signed and notarized downloads plus a Homebrew tap, once Fayzan starts sharing it ([backlog](v2-backlog.md)).

## 10. Milestones

- **M0: Spikes.** Throwaway code that answers the risky questions first.
  1. **Gestures and click cleanup.** Do Right ⌘ gestures and click cleanup work in Chrome, Safari, Cursor, and Finder? Which permission does each part need?
     - If click cleanup is unreliable, hold mode becomes look-only and click-through flows use double-tap.
  2. **Button names.** Are they readable in Chrome and in Electron apps (Cursor, Slack)?
     - These apps may only expose web content to Accessibility after Flipbook sets `AXEnhancedUserInterface` or `AXManualAccessibility` on them (inferred; verify).
  3. **Capture behavior.** Measure capture start latency and dirty-rect/idle behavior on macOS 15.7 and 26.
  4. **Dropping into Cursor.** Does Cursor's chat accept 20 dropped PNGs, and in order?
     - If not, revisit the drag payload.
  5. **Exclusion.** Confirm the pill and card never appear in recordings.
- **M1: Core.** Frame picker, gesture recognizer, cap fitting, tests, `flipbook-replay`.
- **M2: Recording end to end.** Right ⌘ → capture → frames in a folder, with no polish.
- **M3: Output.** Caption strips, click markers, `steps.md`, the card, and filmstrip trimming.
- **M4: The rest of the app.** Settings with the Meet-style picker, first launch, menu bar, retention cleanup, sounds.
- **M5: Dogfood.** A week of real use at work, tuning thresholds from local raw sessions.

## 11. Not in v1

- Radial ring
- MP4/Both output
- Voice narration
- "Save the last 30 s"
- On-screen text changes (OCR)
- Region capture
- Caps Lock and mouse-button triggers
- Windows
- Signed download and Homebrew tap
- Any AI
- Any network access
- Agent-specific integrations (MCP, auto-paste)

Details for each are in [v2-backlog.md](v2-backlog.md).

## 12. Risks

- **Permission re-prompts.** macOS re-asks for Screen Recording permission monthly, on both 15 and 26, and Flipbook can only surface this clearly.
  - The system picker avoids the prompt, but it requires choosing a target every time, which breaks instant capture.
- **macOS 27** shipped 2026-09-14 and is untested.
- **Limits of click cleanup.** Click cleanup can't change the global modifier state.
  - Code that reads that state (e.g. Finder deciding copy vs move during a drag) may still see ⌘ during hold recordings.
  - Apps may show ⌘-hover hints while the key is held.
- **Ergonomics.** Holding Right ⌘ while using a right-handed mouse is awkward, so click-heavy flows will mostly use double-tap.
- **Untuned numbers.** Thresholds are untested starting points. M5 exists to tune them.

## 13. Decision log (2026-09-23)

| Decision | Why |
|---|---|
| Right ⌘, one key | fn is taken by dictation apps (Fayzan uses Handy on fn). People use Caps Lock. Not everyone's mouse has side buttons. Chords can't be held while clicking. |
| Hold, plus double-tap on/off; single tap unused | Wispr-style. Single tap is reserved so the v2 ring doesn't change learned gestures, and accidental taps can't stop a recording. |
| Right ⌘ + Esc cancels | Plain Esc is often part of the bug flow. |
| Dragging drops all frames as images | Folder drops fail in most web chats, while separate PNGs work almost everywhere. |
| Caption strip on each frame | The drag carries only images, so the strip carries the step log anywhere the images go. |
| 20-frame cap, 1920 px PNG | claude.ai takes 20 images per message, and Claude requires ≤ 2000 px once there are more than 20. PNG keeps text sharp. |
| Native Swift, not Tauri or Electron | Every hard part is native API: capture metadata, event taps, non-activating panels, Accessibility. A cross-platform framework would only share the easy parts. A Windows version later is a sibling app tested against the same Core tests. |
| No AI, no network | Works on company computers, and there are no bills. |
| 30-day retention, then Trash | Work screenshots don't pile up, and deleted captures stay recoverable. |
| Ring and MP4 deferred | Keeps v1 bare-bones. |
