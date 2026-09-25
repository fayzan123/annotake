# Flipbook: v1 spec

**Status:** approved design, 2026-09-23; updated with M0 findings and the M2–M4 design 2026-09-24 · **Owner:** Fayzan Malik · **Platform:** macOS 15 and later

Companion docs:
- [v2-backlog.md](v2-backlog.md): everything deliberately left out of v1, with the design notes gathered so far.
- [research-notes.md](research-notes.md): the facts and sources behind these decisions.
- [spikes/findings.md](spikes/findings.md): what the M0 spikes measured, and the decisions taken from them.
- [plans/2026-09-24-m2-m4-design.md](plans/2026-09-24-m2-m4-design.md): how M2–M4 build the app (capture, input, export, UI), and the two checkpoints.

## 1. Summary

Flipbook is a macOS menu-bar app. Hold Right ⌘ (or double-tap it) to record what you do on screen. When you stop, Flipbook keeps only the frames where the screen meaningfully changed, one per step. It captions each frame with what you did (e.g. `Clicked button "Save"`) and shows a floating card that you drag into any AI chat or agent: Cursor, Claude Code, ChatGPT, and so on.

It exists because reproducing a Jira bug for a coding agent meant screenshotting every click by hand. Flipbook turns that into three steps: press a key, reproduce the bug, drag the card.

## 2. Principles and constraints

- **Ease of use first.** The flow is: press the key, reproduce the bug, drag the card. Nothing may add a step, a confirmation, or a wait to it. Defaults work with no setup, and failures degrade instead of blocking a recording.
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
| Hold Right ⌘ alone for 250 ms | Recording starts silently (**hold mode**). At 800 ms the pill and start sound appear (the **reveal**). Release after the reveal → stop → card. Release before it → nothing is saved (§3.2). |
| A key other than Esc pressed while Right ⌘ is held, after 250 ms but before the reveal, with no click first | It was a shortcut (⌘C, ⌘V). The recording is discarded silently and the shortcut works normally. |
| Double-tap Right ⌘ (second press within 300 ms of the first release) | Recording starts at the second press (**hands-free mode**). |
| Double-tap again while hands-free | Stop → card. |
| Right ⌘ + Esc while recording | Cancel. Nothing is saved. |
| Single tap | Nothing. Reserved for the v2 ring. |
| Another key or mouse button pressed while Right ⌘ is down, before 250 ms | It was a shortcut (⌘C, ⌘-click). Flipbook ignores it and the shortcut works normally. |

Rules:
- A **tap** is a press and release within 250 ms, with no other key or mouse button in between.
- **Plain Esc always passes through** to the app being recorded, because closing a dialog can be part of the bug. The Esc in Right ⌘ + Esc is consumed by Flipbook and never reaches the app.
- **While recording in either mode:**
  - Right ⌘ shortcuts such as Right ⌘+S pass through normally and don't stop the recording (in hold mode, from the reveal on).
  - Single taps are ignored.
- **Click cleanup (hold mode only).** The key is held while you click, so during a hold recording Flipbook removes the trigger's modifier (⌘, or ⌥ when Right ⌥ is the trigger) from mouse and scroll events. Clicks stay plain clicks.
  - In hands-free mode nothing is changed, so a deliberate ⌘-click still works.
- **Why the reveal:** M0 measured Fayzan's natural Right ⌘ shortcuts at 270–670 ms from ⌘ down to the letter, so 250 ms alone mistook 8 of 10 shortcuts for holds. Clicks are still classified at 250 ms, so a hold-and-click at 300 ms is a plain click (cleaned up), not a ⌘-click.
- The hold threshold (250 ms), the hold reveal (800 ms) and the double-tap window (300 ms) are adjustable in Settings → Advanced.

### 3.2 While recording

- **Pill.** Shown at the bottom center of the recorded screen (in hold mode, from the reveal at 800 ms):
  - Hold mode: `● 0:04 · 3 frames · release ⌘ to stop`
  - Hands-free mode: `● 0:12 · 5 frames · double-tap ⌘ to stop · ⌘Esc cancels`
  - The key glyph follows the trigger key. Past Max frames the count reads `best 20 of 27`: it never promises more than the card will hold, and the growing total shows recording goes on (the best frames are picked at the end, §5.5).
  - The pill sits over the app being recorded, so it ignores clicks while recording. It only takes clicks when it shows a message with a button, such as Open Settings.
- **Sounds.** Soft start and stop sounds, controlled by a Settings toggle that is on by default. In hold mode the start sound plays at the reveal. No sound plays when a recording is discarded or cancelled.
- **Time limit.** Hands-free recordings stop and save automatically at **5 minutes**. Hold recordings end when the key is released.
- **Accidental recordings are discarded silently:**
  - a hold released before the reveal: if the pill never appeared, nothing was recorded;
  - a hands-free recording shorter than **0.5 s**.
- **Never in the frames:** Flipbook's own windows (pill, cards, filmstrip, Settings), its menu-bar icon, and **notification banners**. On macOS 26 the menu-bar icon needs an explicit window exclusion (§6.2).
- **Cursor.** The cursor is visible in frames because it explains hover states, but its movement is ignored when deciding what changed (§5.2).

### 3.3 What gets recorded

- **Default:** the screen the cursor is on when recording starts.
- **Settings → Record** uses a Google Meet-style picker:
  - **Entire screen:** "Screen with the cursor" (the default) or a specific screen, chosen from thumbnails.
  - **Window:** a thumbnail grid of open windows. Window capture follows the window across screens.
- **Fallback.** If the chosen window no longer exists, or the chosen screen is disconnected, Flipbook records the cursor's screen and the pill says so: "Window not found — recording your screen".
  - Windows are matched by ID only, never guessed by title.

### 3.4 The card and filmstrip

- **The card.** When a recording stops, a card appears at the bottom right of the screen the cursor is on.
  - It shows stacked thumbnails, the frame count, and the duration, with "Saving…" until export finishes.
  - It appears immediately and becomes draggable when export finishes. The target is under 1.5 s.
  - It never takes focus and accepts the first click, so it drags straight into a chat.
- **Dragging the card** drops all frames, in order, as PNG files.
  - M0: Cursor and Claude web took all 20 in order, and Finder copied all 20.
  - Targets cap the count themselves and keep the first N: Slack 10 per message, ChatGPT's free plan 2. File names and caption numbers carry the order.
  - Terminals receive file paths. VS Code's integrated terminal inserts only the first path, as plain text. Terminal.app/iTerm and Jira are still untested.
- **Dismissing.** After a drop the card fades out over about 5 s instead of vanishing, and stays while hovered, so it can be dragged again. Drop targets report success even when they keep only some frames, so a drop can't be trusted to mean "done". ✕ or a swipe right dismisses it.
  - Otherwise cards stay until dismissed (or until they fade after a drop).
  - The newest card sits in the corner and older ones stack upward. At most 4 are visible; a fifth pushes the oldest out, and that one stays in Recent Captures.
- **Clicking the card** (moving less than 4 pt) opens the **filmstrip**, a horizontal strip of the frames with their captions.
  - Click ✕ on a frame to remove it. Clicking again restores it while the filmstrip is open. The last remaining frame can't be removed.
  - Drag a single frame out of the strip.
  - Closing the filmstrip (✕, Esc, a click outside it, or a click on the card) applies the removals:
    - Removed frames move to the capture's hidden `.raw/removed/` folder.
    - The remaining frames are re-rendered and renumbered with no gaps (1/6 … 6/6).
    - A removed frame's actions merge into the previous frame's caption.
    - `steps.md` is regenerated.
- **Recent Captures** in the menu bar brings back the cards for the last 5 captures.

### 3.5 Menu bar

- **Icon:** shows idle or recording (tinted red while recording).
- **Menu:**
  - Fix permissions… (only when a permission is missing; it opens the first-launch checklist, §3.7)
  - Start/Stop Recording (a fallback when the key isn't available; it starts a hands-free recording)
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
| Advanced | Hold threshold (150–500 ms) | 250 ms |
| | Hold reveal (hold threshold + 200 ms, up to 1500 ms) | 800 ms |
| | Double-tap window (200–500 ms) | 300 ms |
| | Save raw sessions (for tuning, §8) | Off |

A change applies to the next recording and never interrupts one in progress. A new trigger key or new gesture timings take effect as soon as Flipbook is idle.

Each tab with settings (all but Permissions) has a **Restore Defaults** button at its bottom right (Checkpoint 2: a slider is hard to put back exactly). It resets only that tab's settings, and is greyed out while they're already the defaults.

Choosing fn shows a note with three warnings:
- macOS's "Press 🌐 key to" setting must be "Do Nothing".
- Dictation apps (Wispr Flow, Handy) often use fn already.
- Some third-party keyboards handle fn themselves and never send it to macOS, so fn works reliably only on Apple keyboards.

### 3.7 First launch

First launch shows one checklist window with three permissions, then asks you to double-tap Right ⌘ (or the chosen trigger) to try it:
1. **Screen Recording:** required to record.
2. **Input Monitoring:** needed to see Right ⌘, clicks, and keys.
3. **Accessibility:** needed for click cleanup and button names.

Each permission's row:
- explains why in one sentence,
- has a button: the first press shows the system prompt, and later presses deep-link to the right System Settings pane,
- re-checks the permission live.

Confirmed by M0:
- **Input Monitoring** covers the listen-only tap (Right ⌘, clicks, keys). Request it with `CGRequestListenEventAccess()`, and check it with `CGPreflightListenEventAccess()`: `tapCreate` succeeds even without the permission, but no events arrive.
- **Accessibility** covers the active tap (click cleanup, consuming the Esc of Right ⌘ + Esc), button names, and setting the Chrome/Electron flags (§6.2). Request it with `AXIsProcessTrustedWithOptions` and the prompt option. "Post events" access is never needed.
- **Screen Recording** is requested by the first `SCShareableContent` call, which fails with error −3801 until it is granted.
- Input Monitoring and Screen Recording take effect only after a relaunch. Once either button has been pressed, the window offers "Quit & Reopen", and it reopens where you left off. Accessibility applies without one.

Your first recording closes the window. You can also close it at any time: Flipbook works with only 1 and 2, in a degraded mode (§7).

First launch also registers Flipbook to launch at login (`SMAppService`), because the key has to work right after a restart.
- It registers only when Flipbook runs from `/Applications` or `~/Applications`, so a development build never leaves a stale login item. Otherwise Settings → General says to move Flipbook there.
- It can be turned off in Settings → General.

## 4. Output

### 4.1 Folder layout

```
~/Pictures/Flipbook/
  2026-09-23 at 14.05.12/
    01_0m00s.png
    02_0m03s.png
    …
    steps.md
    .flipbook          # marker file holding the capture's date: cleanup only ever touches folders that have it
    .raw/              # used to re-render after trims; internal, not a public format
      capture.json     # name, target, date, render options, picked frames and their actions, removals
      frame-000017.png # unrendered picked frames, named by frame index
      removed/         # frames removed in the filmstrip
      session/         # raw session, only with Advanced → Save raw sessions (§8)
  .flipbook-tmp/       # captures being written
```

- Captures are written to a temp folder inside the save location (`.flipbook-tmp/`) and moved into place once complete, which is a rename on the same volume. A crash never leaves a half-finished capture, and leftovers are removed at the next launch.
- A capture whose folder name is already taken gets " (2)", " (3)", and so on.
- `.raw/capture.json` exists so the filmstrip and Recent Captures work after a relaunch. It is not the machine-readable capture file the backlog defers.
- **Cleanup** runs at launch and every 24 h. It moves capture folders older than the retention period to the Trash, but only if they contain `.flipbook`, and it reads the date from that marker.

### 4.2 Frames

- **Format:** PNG, sRGB.
- **Size:** the long edge is at most 1920 px by default (1568 px in compact mode). The final image, caption strip included, never exceeds 2000 px on either side, because Claude rejects larger images once a conversation holds more than 20. The capture size reserves room for the tallest strip, so in practice only portrait windows come out smaller.
- **File names:** a two-digit step number plus the time from start, e.g. `03_0m07s.png`. The order survives any tool.
- **Click markers:** a high-contrast ring at each click point, on the frame where the click happened: 3 px of red (`#FF3B30`) over a 6 px white halo, with a radius of width ÷ 80 (24 px at 1920 wide). When a frame has more than one click, each ring gets a numbered red badge, in click order. A click that falls outside the frame gets no marker.
- **Caption strip:** drawn under the screenshot, never over it.
  - Dark background (`#1C1C1E`).
  - Line 1 is semibold white at width ÷ 64 (30 px at 1920 wide, about twice the size of the UI text in the frame). It wraps to at most 3 lines and then ends with "…".
  - Line 2 is regular gray at 85% of that size, on one line, truncated with "…".
  - `steps.md` always has the full text.

```
3/8 · 0:07 · Clicked button "Save"
Google Chrome — Dayforce · Timesheets
```

Line 1 is step/total · time · action(s). Line 2 is app — window title:
- **Screen mode:** the app and window that have focus.
- **Window mode:** the recorded window, whatever has focus: its app, and its title at that step (Checkpoint 2: a window recording of Finder, started from another app, captioned Finder's picture with `Code — main.swift — flipbook`). The title is read by window ID with `CGWindowListCopyWindowInfo` as each frame arrives.

`steps.md` names the same app and window for each step. Actions don't change: `Switched to …` still names the app that got focus.

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
| ⌘ or ⌃ shortcut | e.g. `Pressed ⌘S`, `Pressed ⇧⌘T`: modifiers in Apple's order ⌃⌥⇧⌘, then the key as the current keyboard layout prints it |
| App or window switch | `Switched to <app> — <window>` |
| Scroll | `Scrolled` |
| Change with no input | `Screen changed` |

Not logged as actions:
- clicks and scrolls outside the recorded area, because the frames can't show them;
- arrows, navigation keys, and F-keys pressed alone (the frames still show what they change);
- key auto-repeats.

Never recorded:
- typed text,
- anything in password fields. Secure text fields (`AXSecureTextField`) are never read. Flipbook does not rely on macOS to hide typing there: in M0, keystrokes in a Safari password field still reached the event tap with Secure Input off. Only the key *kind* is ever used.
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
- **Order.** Every frame and input event is timestamped when it reaches the recording queue, and the picker sees them in that order (§6.1).

### 5.2 What counts as change

- A tile has **changed** if its signature's mean absolute difference from the comparison frame exceeds 3/255.
- Three things are ignored:
  - Tiles under the cursor, at both its old and new position, but only when the cursor moved between the two frames being compared. If it stayed put, its pixels are the same in both frames, so a change under it counts: a checkbox ticked under the pointer is a real change.
  - A **blinking caret**: a thin dirty rect, at most 4 × 48 pt, toggling on and off. Its tiles stay ignored for 2 s. Dirty rects arrive in output pixels (M0), so this limit is converted with the output scale.
  - **Busy regions** such as video, spinners, and animated ads. Tiles that changed in ≥ 60% of frames over the last 1.5 s (with at least 5 frames in that window) are masked until they have been still for 2 s. Two kinds of frame don't count toward this: frames that change more than half the screen, and frames that arrive while you're scrolling. Otherwise scrolling would look like a spinner.
- **Motion** means at least 2 changed tiles remain after those exclusions. A single isolated tile, like a clock digit, doesn't count.
- **D(a, b)** is the fraction of tiles that differ between frames a and b. It ignores busy tiles, recent caret tiles, and, when the cursor moved between a and b, the tiles under it in either frame.

### 5.3 Triggers, settle, keep

- **Pending.** A frame might be needed when either of these happens:
  - **Input:** the mouse-up of a click, Return, Esc, a ⌘/⌃ shortcut, an app/window switch, the end of a scroll (no scroll events for 0.3 s), or a 1.2 s pause in typing.
  - **Visual:** D(last kept, current) ≥ 0.02, or ≥ 0.005 when nothing has been kept for 10 s.
- **Settle.** A pending trigger resolves once there has been no motion for 400 ms. The 400 ms are counted from the later of the last motion and the trigger itself, so a click's result has time to appear. After 3 s it resolves anyway, using the latest frame.
- **Keep.** The settled frame is kept if D(last kept, settled) ≥ 0.005.
  - When the trigger was a click, a commit (Return, Esc, or a shortcut), a switch, or a typing pause, a single changed tile is enough. A ticked checkbox, an inline error, or a filled-in field still counts.
  - For those same triggers, the settled frame is also compared with the frame that was on screen at the input: the mouse-down, the first key of the typing run, the commit key, or the switch. One changed tile there is enough too. The pointer was in the same place then, so this catches a change right under a pointer that stayed put, which D(last kept, settled) misses when the pointer was elsewhere in the last kept frame.
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
                    frame picker (§5), LiveSession (the ordered feed, §6.1), gesture recognizer (§3.1),
                    cap fitting (§5.5), caption and steps.md text, raw sessions and replay
  FlipbookCapture/  ScreenCaptureKit: target resolution, exclusions, stream, output size,
                    frame → tile signatures, point mapping
  FlipbookInput/    event taps: trigger key and click cleanup; clicks/keys/scrolls;
                    Accessibility labels and flags; active app/window tracking
  FlipbookExport/   caption strips, click markers, PNGs + steps.md, capture folders,
                    filmstrip trims, retention cleanup
  FlipbookApp/      the app, as a library: SessionController, recording pipeline, menu bar, pill,
                    card, filmstrip, Settings, first launch, self-test (§8)
  Flipbook/         the executable: main.swift only
  flipbook-replay/  CLI: runs a saved raw session through FlipbookCore and prints its decisions
Tests/
  FlipbookCoreTests/     unit and golden tests; Fixtures/ holds raw sessions (never work data, see §8)
  FlipbookCaptureTests/, FlipbookInputTests/, FlipbookExportTests/, FlipbookAppTests/
```

The app is a library plus a one-file executable so its tests can import it the normal way.

**Why Core has no macOS code:** it is the part the golden tests pin down. It is also the part a future Windows version would reuse, or port against the same tests.

### 6.1 Data flow

```
Right ⌘ ─▶ Input thread (taps + GestureRecognizer) ─gesture─▶ SessionController (main)
              │ click / key / scroll / switch                     │ start / stop
              │   (click → reserve a slot; AX thread fills label) ▼
              └──────────────▶ Recording queue: LiveSession ◀── SCStream frames + signatures
                                    │ persist / discard
                                    ▼
               Writer: kept frames → temp .raw/ ──on stop: settle, fit cap──▶ Export: PNGs + steps.md
                                                                                  ▼
                                                                        Card (drag / filmstrip)
```

- **Session states:** `idle → recording(hold | handsFree) → finishing → idle`, plus `cancelled`. Finishing and export run per capture in the background, so a new recording can start while the last one saves.
- **Threads:**
  - Main: UI and `SessionController`.
  - Input thread (its own run loop): both event taps and the gesture recognizer. Callbacks only classify and hand off, because macOS disables a slow tap.
  - AX thread (its own run loop): label lookups, focused field and window title, observers, and the Chrome/Electron flags, with a 0.25 s Accessibility messaging timeout.
  - Recording queue: Capture and Core on one serial queue: frames, signatures, and `LiveSession`.
  - Writer queue: PNG encoding.
- **`LiveSession`** is the only way frames and events reach the frame picker, live and in replay.
  - Items are stamped when they reach the recording queue and wait in one first-in-first-out queue.
  - An event that needs an Accessibility lookup reserves a slot: a mouse-down, the first key of a typing run, a switch, or the window title at start. Items behind an unfilled slot wait. After 0.5 s the slot is released without a label.
  - Ticks fall on the replayer's 50 ms grid.
  - The replayer runs the same code, so a saved raw session replays exactly as it ran live.
- **Memory:** kept frames are written to disk as soon as they are kept, so memory use stays flat. Capture holds the pixels only of frames the picker hasn't taken yet, plus the latest one it took.

### 6.2 Key macOS pieces

| Need | API |
|---|---|
| Capture and changed regions | ScreenCaptureKit `SCStream`, `SCStreamFrameInfo` (status, dirtyRects) |
| Exclude own windows and notification banners | `SCContentFilter(display:excludingApplications:exceptingWindows:)`; panels are created at launch. The content comes from one `SCShareableContent` query that includes off-screen windows (on macOS 15, `com.apple.notificationcenterui` is missing from the on-screen-only list while no banner shows), with a 2 s timeout and a cache refreshed at launch and on display changes. On macOS 26, excluding the app doesn't cover its menu-bar status item: its window is found by window number or frame, and if another process owns it, that app is excluded too, with its other windows listed in `exceptingWindows` |
| Trigger and input events | `CGEventTap` on a dedicated input thread: listen-only for flagsChanged/keys/mouse. The active (event-modifying) tap exists only while a recording is running. It strips the trigger's modifier from mouse and scroll events during hold recordings, and it consumes the Esc of Right ⌘ + Esc. |
| Button names | `AXUIElementCopyElementAtPosition` plus role/title/description, looked up on the AX thread (0.5–100 ms; `AXUIElementSetMessagingTimeout` 0.25 s). Chrome web content and Electron apps need a flag, set only while recording: `AXEnhancedUserInterface` on Chrome (it returns −25208 but works), `AXManualAccessibility` on Electron apps. Never take a label from `AXWebArea`/`AXWindow` or above, nor from a container labeled with its window's title (Chrome's tab strip, Checkpoint 1); fall back to `Clicked at (x, y)` |
| App and window | `NSWorkspace` notifications; AX focused-window title; an AX observer for window and title changes. In window mode, the recorded window's title by window ID (`CGWindowListCopyWindowInfo`, which Screen Recording permits) |
| Panels that don't take focus | `NSPanel` with `.nonactivatingPanel`, `.canJoinAllSpaces`, `.fullScreenAuxiliary` |
| Scaling and encoding | ScreenCaptureKit scales to the output size (sRGB); Core Graphics and Core Text draw strips and markers; ImageIO writes PNGs |
| Self-test capture | `SCShareableContent.currentProcess` (macOS 14.4+) lets the app capture its own test window without Screen Recording permission |
| Settings, launch at login | SwiftUI, `UserDefaults`, `SMAppService` |

## 7. Permissions and failure handling

| Situation | Behavior |
|---|---|
| Screen Recording missing or expired (macOS re-prompts monthly) | Pill shows "Screen Recording permission needed" with Open Settings. Nothing is saved. |
| Input Monitoring missing | The key doesn't work, but the menu bar Start/Stop still does. Settings shows the fix. Detected with `CGPreflightListenEventAccess()`, not by tap creation. |
| Accessibility missing | Still records. Hold-mode clicks keep the trigger's modifier (⌘), and captions say `Clicked at (x, y)`. |
| Any permission missing | The menu shows "Fix permissions…", which opens the first-launch checklist (§3.7). |
| Accessibility revoked while click cleanup runs | macOS can block all clicks until reboot if an active tap outlives its permission. Flipbook checks trust every 2 s and removes the active tap immediately. |
| macOS disables the event tap (timeout or user input) | Re-enabled automatically. |
| An app reacts to the Accessibility flags | Cursor shows "Screen reader usage detected…" once the flag is set. Flags are set only while recording and cleared at stop, unless VoiceOver is running. Checkpoint 1 verifies that apps behave normally after the flags are cleared. |
| Password field / Secure Input | The trigger still works (M0). Key events may still arrive there; only their kind is used, and the text is never logged. |
| Recorded window closes or screen is unplugged mid-recording | Stop and save what was captured. |
| Default window or screen missing at start | Record the cursor's screen, and the pill says so. |
| macOS's screen/window list is slow or hangs | Each start makes a fresh query with a 2 s timeout and falls back to a cached list, refreshed at launch and on display changes. With neither, the pill shows "Couldn't start recording — try again" instead of freezing. |
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
  - a click whose only result is a checkbox, including one under a pointer that stayed put,
  - over-cap selection,
  - action merging,
  - the live feed (`LiveSession`, with late labels) giving the same result as replaying what it recorded.
- **Gesture tests:** timed key and mouse sequences, checked against the expected outcome:
  - hold,
  - double-tap start,
  - double-tap stop,
  - cancel,
  - "was a shortcut" (before 250 ms, and after 250 ms but before the reveal),
  - single tap ignored.
- **Golden tests:** raw sessions paired with the frames that should be kept. A raw session holds tile signatures, dirty rects, and events. It's saved into the capture's `.raw/session/` when Advanced → Save raw sessions is on.
  - `make test` fails if picking changes.
  - `flipbook-replay` prints the picker's decisions, for tuning.
- **Module unit tests:** Capture, Input, Export, and the app each test their pure logic:
  - output size, signatures, and point mapping;
  - key classification, and label rules over a fake Accessibility tree;
  - rendering, capture folders, trims, and retention;
  - the session state machine, the pill text, and card stacking.

  Event taps, the stream, AX calls, and the UI are covered by the self-test and the checkpoints.
- **Self-test:** `make selftest` opens a test window of Flipbook's own with a scripted scene. It records the window through the real ScreenCaptureKit → picker → export path, with no permission needed, and reports frames, timings, and picked captions in `selftest.json`. `make ui-snapshots` renders every panel and window to PNGs the same way. Implementation sessions run both unattended.
- **Log:** `~/Library/Logs/Flipbook.log` records gestures, state changes, timings, and errors. It never records labels, window titles, or keys.
- **Fixture privacy:** sessions recorded on the work Mac never go in the repo, because window titles and labels can be internal. Work sessions stay local, or have all text stripped before use.
- **Manual checklist (Fayzan).** It's run at the two checkpoints in [plans/2026-09-24-m2-m4-design.md](plans/2026-09-24-m2-m4-design.md) §10:
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
- **Tests:** `make test` runs Swift Testing with the Command Line Tools' framework path added, because plain `swift test` can't find `Testing` without Xcode, and XCTest isn't in the CLT at all (M0).
- **Make targets:**
  - `make cert` runs once. It creates a free self-signed signing identity so macOS permissions survive rebuilds (ad-hoc signatures silently lose them).
  - `make` builds and assembles `Flipbook.app`.
  - `make run` builds it and opens it.
  - `make install` copies it into `/Applications`, removing any older copy in `~/Applications`.
  - `make zip` produces a zip for the work Mac.
  - `make selftest` runs the self-test, and `make ui-snapshots` renders the UI to PNGs (§8).
  - Bundling strips extended attributes before signing, because iCloud Drive syncs `~/Documents` and tags new bundles in ways `codesign` rejects.
- **Work Mac, until the app is notarized:**
  - The app is built only on the personal MacBook, using Fayzan's own Claude membership rather than work AI.
  - AirDrop the zip over and unzip it into `/Applications`.
  - Once per update, run `xattr -dr com.apple.quarantine /Applications/Flipbook.app`.
- **Later:** signed and notarized downloads plus a Homebrew tap, once Fayzan starts sharing it ([backlog](v2-backlog.md)).

## 10. Milestones

- **M0: Spikes. Done 2026-09-24.** Throwaway code that answers the risky questions first. Results and decisions: [spikes/findings.md](spikes/findings.md).
  1. **Gestures and click cleanup.** Do Right ⌘ gestures and click cleanup work in Chrome, Safari, Cursor, and Finder? Which permission does each part need?
     - If click cleanup is unreliable, hold mode becomes look-only and click-through flows use double-tap.
  2. **Button names.** Are they readable in Chrome and in Electron apps (Cursor, Slack)?
     - These apps may only expose web content to Accessibility after Flipbook sets `AXEnhancedUserInterface` or `AXManualAccessibility` on them (inferred; verify).
  3. **Capture behavior.** Measure capture start latency and dirty-rect/idle behavior on macOS 15.7 and 26.
  4. **Dropping into Cursor.** Does Cursor's chat accept 20 dropped PNGs, and in order?
     - If not, revisit the drag payload.
  5. **Exclusion.** Confirm the pill and card never appear in recordings.
- **M1: Core. Done 2026-09-24.** Frame picker, gesture recognizer, cap fitting, tests, `flipbook-replay`.
- **M2: Recording end to end.** Right ⌘ → capture → frames in a folder, with no polish.
- **M3: Output.** Caption strips, click markers, `steps.md`, the card, and filmstrip trimming.
- **M4: The rest of the app.** Settings with the Meet-style picker, first launch, menu bar, retention cleanup, sounds.
- M2–M4 are designed in [plans/2026-09-24-m2-m4-design.md](plans/2026-09-24-m2-m4-design.md):
  - Session 4 builds M2 and M3, then comes Checkpoint 1 on the personal Mac.
  - Session 5 builds M4, then comes Checkpoint 2 on both Macs.
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
- **Accessibility flags change other apps.** Setting them makes Cursor offer screen-reader mode, and may affect others. Hence recording-only, and clearing them is verified at Checkpoint 1.
- **Chrome may expose web content late.** M0 saw labels on the next click, about 4 s after setting the flag, so the first Chrome clicks after a recording starts may be unlabeled. Checkpoint 1 measures it.
- **Unexplained dirty rects on macOS 26.** A bottom-center region was reported dirty at 10 fps with nobody touching the Mac. Tile comparison should ignore it; it's rechecked at Checkpoint 2, once the real pill ticks every second.
- **The self-test needs an awake, unlocked Mac.** While the Mac is asleep or locked, capture delivers no frames, so unattended sessions retry the self-test later.

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
| Hold mode reveals at 800 ms; a key before that discards it as a shortcut (2026-09-24) | M0: natural Right ⌘ shortcuts take 270–670 ms to the letter, so 250 ms alone misfired 8 of 10 times. A longer threshold would turn early clicks into ⌘-clicks. |
| Card lingers ~5 s after a drop (2026-09-24) | Every drop target reported success, even Slack keeping 10 of 20. |
| Exclude the menu-bar icon explicitly (2026-09-24) | On macOS 26 it appeared in frames despite excluding the app. |
| Frames and events reach the picker through `LiveSession`, one time-ordered queue (2026-09-24, M2–M4 design) | A click's label arrives up to ~100 ms after the click. Ordering keeps each click on the screen it happened on, and makes raw sessions replay exactly as they ran live. |
| A change under a pointer that stayed put counts (2026-09-24) | After a click the pointer sits on what it clicked, so a ticked checkbox produced no frame. |
| A hold released before the reveal is discarded (2026-09-24) | If the pill never appeared, nothing was recorded. |
| `--selftest` records Flipbook's own scripted window (2026-09-24) | It needs no permission, so unattended implementation sessions can test the real capture path. |
| Clicks and scrolls outside the recorded area aren't logged (2026-09-24) | The frames can't show them. |
| First launch is one checklist; the menu gains "Fix permissions…" (2026-09-24) | Fewer clicks than a wizard, and Screen Recording expires monthly. |
| Launch at login only from an Applications folder (2026-09-24) | A development build never leaves a stale login item. |
