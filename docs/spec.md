# Annotake: v1 spec

**Status:** approved design, 2026-09-23; updated with M0 findings and the M2–M4 design 2026-09-24, with the distribution design 2026-09-30, and with the email list 2026-10-16 · **Owner:** Fayzan Malik · **Platform:** macOS 15 and later

**Name:** Annotake, called Flipbook until 2026-09-30 ([distribution design §3](plans/2026-09-30-distribution-design.md#3-the-name-annotake))

Companion docs:
- [v2-backlog.md](v2-backlog.md): everything deliberately left out of v1, with the design notes gathered so far.
- [research-notes.md](research-notes.md): the facts and sources behind these decisions.
- [spikes/findings.md](spikes/findings.md): what the M0 spikes measured, and the decisions taken from them.
- [plans/2026-09-24-m2-m4-design.md](plans/2026-09-24-m2-m4-design.md): how M2–M4 build the app (capture, input, export, UI), and the two checkpoints.
- [plans/2026-09-30-distribution-design.md](plans/2026-09-30-distribution-design.md): how the app reaches other developers and makes money: the stages, the free plan and Pro, accounts, and the rename to Annotake.
- [plans/2026-10-15-email-list-design.md](plans/2026-10-15-email-list-design.md): the email address the first run asks for, the list in Resend, and its unsubscribe.

## 1. Summary

Annotake is a macOS menu-bar app. Hold Right ⌘ (or double-tap it) to record what you do on screen. When you stop, Annotake keeps only the frames where the screen meaningfully changed, one per step. It captions each frame with what you did (e.g. `Clicked button "Save"`) and shows a floating card that you drag into any AI chat or agent: Cursor, Claude Code, ChatGPT, and so on.

It exists because reproducing a Jira bug for a coding agent meant screenshotting every click by hand. Annotake turns that into three steps: press a key, reproduce the bug, drag the card.

## 2. Principles and constraints

- **Ease of use first.** The flow is: press the key, reproduce the bug, drag the card. Nothing may add a step, a confirmation, or a wait to it. Defaults work with no setup, and failures degrade instead of blocking a recording.
- **Built for Fayzan's own workflow first, and now for other developers too.** Setup must be as easy as Wispr Flow or Loom: download, grant the permissions, start ([distribution design](plans/2026-09-30-distribution-design.md)). Competitors don't drive product decisions; pricing and positioning look at them.
- **No AI in the product.** No LLMs, no ML models, no API keys, no bills. Frames are picked by pixel comparison, and "what you clicked" comes from macOS Accessibility.
- **Nothing you record leaves your Mac.** Frames, captions, `steps.md`, window titles, button names, and keys never leave it, which keeps it acceptable on a work Mac. The app makes two network calls:
  - a daily update check (Sparkle, §6.2), which sends only the app's version and never a system profile;
  - the email sign-up (§3.7), which sends the address, the box's choice, the consent id, and the app's version to `annotake.app/api/subscribe`: after Continue, then at each launch (last, after the update check) and on a backoff until the site takes or refuses it, and again only on a Change… to a new address ([email list design](plans/2026-10-15-email-list-design.md) §3.4).

  The [distribution design](plans/2026-09-30-distribution-design.md) adds sign-in, the plan, and daily counts in Stage 2. A recording never waits on the network.
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
| Another key or mouse button pressed while Right ⌘ is down, before 250 ms | It was a shortcut (⌘C, ⌘-click). Annotake ignores it and the shortcut works normally. |

Rules:
- A **tap** is a press and release within 250 ms, with no other key or mouse button in between.
- **Plain Esc always passes through** to the app being recorded, because closing a dialog can be part of the bug. The Esc in Right ⌘ + Esc is consumed by Annotake and never reaches the app.
- **While recording in either mode:**
  - Right ⌘ shortcuts such as Right ⌘+S pass through normally and don't stop the recording (in hold mode, from the reveal on).
  - Single taps are ignored.
- **Click cleanup (hold mode only).** The key is held while you click, so during a hold recording Annotake removes the trigger's modifier (⌘, or ⌥ when Right ⌥ is the trigger) from mouse and scroll events. Clicks stay plain clicks.
  - In hands-free mode nothing is changed, so a deliberate ⌘-click still works.
- **Why the reveal:** M0 measured Fayzan's natural Right ⌘ shortcuts at 270–670 ms from ⌘ down to the letter, so 250 ms alone mistook 8 of 10 shortcuts for holds. Clicks are still classified at 250 ms, so a hold-and-click at 300 ms is a plain click (cleaned up), not a ⌘-click.
- The hold threshold (250 ms), the hold reveal (800 ms) and the double-tap window (300 ms) are adjustable in Settings → Advanced.

### 3.2 While recording

- **Pill.** Shown at the bottom center of the recorded screen (in hold mode, from the reveal at 800 ms):
  - Hold mode: `● 0:04 · 3 frames · release ⌘ to stop`
  - Hands-free mode: `● 0:12 · 5 frames · double-tap ⌘ to stop · ⌘Esc cancels`
  - The key glyph follows the trigger key. Past Max frames the count reads `best 20 of 27`: it never promises more than the card will hold, and the growing total shows recording goes on (the best frames are picked at the end, §5.5).
  - The pill sits over the app being recorded, so it ignores clicks while recording. It only takes clicks when it shows a message with a button, such as Open Settings or Open.
- **Sounds.** Soft start and stop sounds, controlled by a Settings toggle that is on by default. In hold mode the start sound plays at the reveal. No sound plays when a recording is discarded or cancelled.
- **Time limit.** Hands-free recordings stop and save automatically at **5 minutes**. Hold recordings end when the key is released.
- **No address, no recording.** Until the email step has saved an address (§3.7), nothing records:
  - a hold shows "Add your email to start recording", with Open, at its reveal, so a quick shortcut shows nothing;
  - a double-tap or the menu's Start shows it at once, and the menu keeps offering Start Recording;
  - Open brings the email step forward;
  - a recording under way is never cut off.
- **Accidental recordings are discarded silently:**
  - a hold released before the reveal: if the pill never appeared, nothing was recorded;
  - a hands-free recording shorter than **0.5 s**.
- **Never in the frames:** Annotake's own windows (pill, cards, filmstrip, Settings), its menu-bar icon, and **notification banners**. On macOS 26 the menu-bar icon needs an explicit window exclusion (§6.2).
- **Cursor.** The cursor is visible in frames because it explains hover states, but its movement is ignored when deciding what changed (§5.2).

### 3.3 What gets recorded

- **Default:** the screen the cursor is on when recording starts.
- **Settings → Record** uses a Google Meet-style picker:
  - **Entire screen:** "Screen with the cursor" (the default) or a specific screen, chosen from thumbnails.
  - **Window:** a thumbnail grid of open windows. Window capture follows the window across screens.
- **Fallback.** If the chosen window no longer exists, or the chosen screen is disconnected, Annotake records the cursor's screen and the pill says so: "Window not found — recording your screen".
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
  - Click ✕ on a frame to remove it, and Restore to bring it back while the filmstrip is open. The last remaining frame can't be removed. Clicking anywhere else on a frame shows it full screen.
  - **Keys.** A ring marks the current frame: the first when the filmstrip opens, or the one last clicked. ← and → move it, stopping at the ends, and the strip scrolls to keep it in view. ⌫ removes the current frame, or restores it. Space shows it full screen. Return applies the removals and closes the filmstrip.
  - **Full screen,** because the strip's frames are too small to read: the current frame as large as fits on a dark backdrop over the whole screen, with its caption above it. ← and → flip through the frames, ⌫ removes or restores the one on screen, and the ring in the strip follows. Esc, Space, ✕, or a click on the backdrop goes back to the filmstrip. Return applies the removals and closes both.
  - The header counts the frames to remove, e.g. `20 frames · 3 to remove`.
  - Drag a single frame out of the strip.
  - Closing the filmstrip (✕, Return, Esc, a click outside it, or a click on the card) applies the removals:
    - Removed frames move to the capture's hidden `.raw/removed/` folder.
    - The remaining frames are re-rendered and renumbered with no gaps (1/6 … 6/6).
    - A removed frame's actions merge into the previous frame's caption.
    - `steps.md` is regenerated.
    - The card stays. Until the removals are done, it shows "Saving…" and can't be dragged or opened, so a drag never picks up half-renamed files.
- **Recent Captures** in the menu bar brings back the cards for the last 5 captures.

### 3.5 Menu bar

- **Icon:** the Annotake mark (§6), as a template image in the menu bar's own color. While recording, its front reel turns red.
- **Menu:**
  - Fix permissions… (only when a permission is missing; it opens the first run's permission steps, §3.7)
  - Start/Stop Recording (a fallback when the key isn't available; it starts a hands-free recording)
  - Recent Captures ▸ (last 5)
  - Open Captures Folder
  - Settings…
  - Send Feedback… (a draft to Fayzan's inbox with a diagnostic report, §8)
  - Check for Updates… (Sparkle checks now and shows the result)
  - Quit
- **In the Dock only while a window is open** (`DockPresence.swift`): the first run or Settings puts Annotake in the Dock and ⌘-Tab, and the last one closed takes it out, so a window behind another app, such as System Settings during the permissions, can be found again. The pill, the cards, and the filmstrip don't count. Otherwise Annotake lives in the menu bar alone.
- **The main menu** (`MainMenu.swift`) shows only while Annotake is in the Dock: About, Settings… (⌘,), and Quit (⌘Q); Edit; and Window's Close (⌘W). Otherwise it holds Edit alone, since the filmstrip and the frame viewer take keys while another app's menus show, and ⌘Q there mustn't quit Annotake. A text field, such as the email step's, gets ⌘X, ⌘C, ⌘V, ⌘A, ⌘Z, and ⇧⌘Z only through it. AppKit adds its AutoFill, Start Dictation…, and Emoji & Symbols items with it, so ⌃⌘Space opens Emoji & Symbols while an Annotake window is key.

### 3.6 Settings

| Section | Setting | Default |
|---|---|---|
| General | Trigger key: Right ⌘ / Right ⌥ / fn | Right ⌘ |
| | Sounds | On |
| | Launch at login | On |
| | Email: the address with Change…, or Not set with Add… | Asked in the first run (§3.7) |
| Record | Entire screen (the cursor's, or a specific one) or Window | Screen with the cursor |
| Output | Max frames (2–50) | 20 |
| | Frame size (long edge): 1920 px, or 1568 px compact | 1920 px |
| | Caption strip | On |
| | Click markers | On |
| | Save location | `~/Pictures/Annotake` |
| | Keep captures: 7 days / 30 days / forever | 30 days |
| Permissions | Status of each permission, with "Open System Settings" | — |
| Advanced | Hold threshold (150–500 ms) | 250 ms |
| | Hold reveal (hold threshold + 200 ms, up to 1500 ms) | 800 ms |
| | Double-tap window (200–500 ms) | 300 ms |
| | Save raw sessions (for tuning, §8) | Off |

A change applies to the next recording and never interrupts one in progress. A new trigger key or new gesture timings take effect as soon as Annotake is idle.

Every tab ends in a footer bar: the Annotake logo on the left and the version on the right, e.g. "Version 0.2.0 (99)", selectable for bug reports.

Each tab with settings (all but Permissions) has a **Restore Defaults** button at its bottom right (Checkpoint 2: a slider is hard to put back exactly). It resets only that tab's settings, and is greyed out while they're already the defaults.

**The email** isn't a setting, and Restore Defaults never touches it. Its row is last in General. Change… opens a sheet titled "Change your email": the field, with the email step's typo hint below it, a Privacy policy link, Cancel, and Save, with no box, since the new address keeps the earlier choice. Add… opens the email step ([email list design](plans/2026-10-15-email-list-design.md) §3.3).

Choosing fn shows a note with three warnings:
- macOS's "Press 🌐 key to" setting must be "Do Nothing".
- Dictation apps (Wispr Flow, Handy) often use fn already.
- Some third-party keyboards handle fn themselves and never send it to macOS, so fn works reliably only on Apple keyboards.

### 3.7 First launch

The first run is one window, "Welcome to Annotake" (560 pt wide; "Annotake" for the email step alone, which an existing copy gets once after its update), showing one step at a time, like Wispr Flow's ([distribution design §5.2](plans/2026-09-30-distribution-design.md#52-the-stage-1-build)). Every key name follows the trigger key (Right ⌘ below).
1. **Welcome:** the Annotake logo (§6), "Show your coding agent exactly what happened.", one paragraph on what it does, and a demo of three tiles lit in turn every 1.6 s ("Double-tap Right ⌘", "Click through it", "Drag the card into your agent"). Get Started.
2. **Stay in the loop:** an email field, focused, then "We'll email you about security fixes and important changes to Annotake.", and the footer "annotake.app · Privacy policy". For now there's no box for feedback and news: it comes back with the list's mailing address ([email list design](plans/2026-10-15-email-list-design.md) §13). Below the field, "Did you mean sam@gmail.com?" offers a fix for a likely typo of a common provider's domain (`EmailTypo.swift`), after a pause in typing; one click takes it, and nothing waits on it. Continue waits for an address the site will take, saves it on the Mac, and moves straight on; the send runs in the background (§2, [email list design](plans/2026-10-15-email-list-design.md) §3).
3. **The three permissions, one at a time,** in this order, because Accessibility applies without a relaunch:
   - **Accessibility:** "So Annotake can name the buttons you click, and keep ⌘ out of your clicks while you hold the key."
   - **Input Monitoring:** "So Annotake can notice Right ⌘, and your clicks and keys while you record. It never records what you type."
   - **Screen Recording:** "So Annotake can capture your screen while you record."

   Each one shows its reason, then "Annotake sees your screen only while you record. Nothing you record leaves your Mac.", a picture of the row to turn on in System Settings (the app's icon and name, and its switch, ringed), the path to it, and a ✓ for each permission already granted. Allow… shows macOS's prompt; after that, Open System Settings deep-links to the pane, and Continue moves on without waiting for the grant to show. A grant made anywhere, in any order, moves the step on, and a permission that's already granted is never asked for.
4. **Reopen,** only when Input Monitoring or Screen Recording was requested and isn't granted yet, because those apply only after a relaunch. Quit & Reopen saves where the window is, relaunches, and the window comes back at the next step.
5. **A practice run:** double-tap Right ⌘, click through something in another app, and double-tap again. Annotake keeps its own windows out of recordings, so the practice happens elsewhere (Checkpoint 3: an Open button and a Remember me box in the first run's own window never appeared in the frames). Once the recording is saved, the window comes back in front with the drop box. A recording saved earlier in the first run skips this step.
6. **A drop box:** "Now drag the card here." A dropped card shows how many frames it held and the first three, then "Next time, drag it into Claude Code, Cursor, or ChatGPT." Skip or Continue.
7. **You're set:** hold the key for quick recordings, Right ⌘ + Esc cancels, and everything else is in the menu-bar icon.

- **Nothing is asked for before its step.** Listing screens makes macOS ask for Screen Recording, and creating the key's event tap makes it ask for Input Monitoring, so until each is granted Annotake does neither at launch; neither works before then anyway (M0). A grant noticed by the once-a-second check brings the window back in front of System Settings at the next step (Checkpoint 3).
- **Where it is** is saved after every change (`onboarding.v1`), and the window shows at each launch until it's done. Closing it on the email step or a permission step brings it back at the next launch; closing it on the practice run, the drop box, or You're set finishes it. Permissions are re-checked every second while it's open.
- **Fix permissions…** in the menu shows the first run where it is, or once it's done, a pass over the missing permissions alone. Closing that pass finishes it. It starts its own pass even over a pending email-only pass, which comes back with the pill's Open or at the next launch.
- **The email-only pass** (`.emailOnly`): the email step, then You're set. A copy whose first run is done but has no saved address, from before the email step or because the site refused the address, gets it at launch. A first run that an update reaches past where the email step now goes moves back to it; one left at You're set gets the email-only pass instead. The pill's Open and Settings' Add… bring the email step forward the same way ([email list design](plans/2026-10-15-email-list-design.md) §3.2).
- **In Stage 2,** sign-in takes the email step's place.
- Annotake works without Accessibility, in a degraded mode (§7).

Confirmed by M0:
- **Input Monitoring** covers the listen-only tap (Right ⌘, clicks, keys). Request it with `CGRequestListenEventAccess()`, and check it with `CGPreflightListenEventAccess()`: `tapCreate` succeeds even without the permission, but no events arrive.
- **Accessibility** covers the active tap (click cleanup, consuming the Esc of Right ⌘ + Esc), button names, and setting the Chrome/Electron flags (§6.2). Request it with `AXIsProcessTrustedWithOptions` and the prompt option. "Post events" access is never needed.
- **Screen Recording** is requested by the first `SCShareableContent` call, which fails with error −3801 until it is granted. The first run requests it with `CGRequestScreenCaptureAccess()`.
- Input Monitoring and Screen Recording take effect only after a relaunch. Accessibility applies without one.

**Move to Applications.** Opened from anywhere else (the disk image, Downloads, or a build folder), Annotake first asks "Move Annotake to Applications?" ("Annotake needs to be in Applications to start when you log in."), before migration and the first run.
- Move to Applications copies it to `/Applications`, or to `~/Applications` when `/Applications` isn't writable, replacing any copy there; opens the copy; and quits. A copy opened from a quarantined download runs translocated (from a path under `/AppTranslocation/`), so the move starts from the original, found with Security.framework's `SecTranslocateCreateOriginalPathForURL`. The original goes to the Trash unless it's on a read-only volume such as the disk image. The copy's quarantine flag is removed, since Gatekeeper has just checked it.
- Not Now is remembered (`moveToApplications.declined`), and Annotake runs where it is.
- A failure is logged and shown ("Couldn't move Annotake: …"), and Annotake keeps running.

First launch also registers Annotake to launch at login (`SMAppService`), because the key has to work right after a restart.
- It registers only when Annotake runs from `/Applications` or `~/Applications`, so a development build never leaves a stale login item. Otherwise Settings → General says to move Annotake there.
- It can be turned off in Settings → General.

## 4. Output

### 4.1 Folder layout

```
~/Pictures/Annotake/
  2026-09-23 at 14.05.12/
    01_0m00s.png
    02_0m03s.png
    …
    steps.md
    .annotake          # marker file holding the capture's date: cleanup only ever touches folders that have one
    .raw/              # used to re-render after trims; internal, not a public format
      capture.json     # name, target, date, render options, picked frames and their actions, removals
      frame-000017.png # unrendered picked frames, named by frame index
      removed/         # frames removed in the filmstrip
      session/         # raw session, only with Advanced → Save raw sessions (§8)
  .annotake-tmp/       # captures being written
```

- Captures are written to a temp folder inside the save location (`.annotake-tmp/`) and moved into place once complete, which is a rename on the same volume. A crash never leaves a half-finished capture, and leftovers are removed at the next launch.
- A capture whose folder name is already taken gets " (2)", " (3)", and so on.
- `.raw/capture.json` exists so the filmstrip and Recent Captures work after a relaunch. It is not the machine-readable capture file the backlog defers.
- **Cleanup** runs at launch and every 24 h. It moves capture folders older than the retention period to the Trash, but only if they contain `.annotake`, and it reads the date from that marker.

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
- **Window mode:** the recorded window, whatever has focus: its app, and its title at that step (Checkpoint 2: a window recording of Finder, started from another app, captioned Finder's picture with the focused editor's window, `Code — main.swift — …`). The title is read by window ID with `CGWindowListCopyWindowInfo` as each frame arrives.

`steps.md` names the same app and window for each step. Actions don't change: `Switched to …` still names the app that got focus.

### 4.3 steps.md

```
# Annotake capture — 2026-09-23 at 14.05.12
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
- anything in password fields. Secure text fields (`AXSecureTextField`) are never read. Annotake does not rely on macOS to hide typing there: in M0, keystrokes in a Safari password field still reached the event tap with Secure Input off. Only the key *kind* is ever used.
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
  - At stop, Annotake waits up to 1 s for the screen to settle, then keeps the final state if it differs from the last kept frame.

### 5.4 Each frame is "the screen, plus what I did on it"

At mouse-down, the click (point, label, app, window) is attached to the current screen state:
- If the screen still matches the last kept frame, the click is attached to that frame.
- Otherwise, the latest frame before the click is kept as a new frame and the click is attached to it.

The result of the click becomes the next frame once it settles. Every frame therefore reads "this was the screen, and this is what I did on it". Several clicks on an unchanged screen stack on one frame, with numbered markers.

Non-click actions attach the same way: typing, Return, shortcuts, switches, and scrolls.

### 5.5 Fitting the cap

When more than N frames were kept (N = 20 by default), Annotake repeatedly removes the frame whose removal loses the least. This is a greedy method in the style of Visvalingam–Whyatt line simplification:

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
- **App identity:** bundle id `com.fayzanmalik.annotake`, `LSUIElement` (menu-bar only), minimum macOS 15.0.
- **Brand:** the mark is a two-reel movie camera standing on a capital A, its tripod, and the logo uses the mark as the A of "Annotake", followed by "nnotake" in Jost SemiBold with its single-story a, outlined. The mark is charcoal `#1C1C1E` (white on dark) with the front reel in the click marker's red, `#FF3B30`. `AnnotakeApp/BrandMark.swift` holds the mark's shapes and `Wordmark.swift` the outlined letters, so the app icon, the menu-bar icon (§3.5), and the welcome step's logo (§3.7) draw the same thing.
- **Icon:** `Resources/AppIcon.icns`, drawn by `scripts/make-icon.swift` (`make icon` compiles it with `BrandMark.swift`): the mark in white, its front reel red, on a dark body in the caption strip's color. One drawing serves every size.

```
Sources/
  AnnotakeCore/     Foundation only, no macOS frameworks:
                    frame picker (§5), LiveSession (the ordered feed, §6.1), gesture recognizer (§3.1),
                    cap fitting (§5.5), caption and steps.md text, raw sessions and replay
  AnnotakeCapture/  ScreenCaptureKit: target resolution, exclusions, stream, output size,
                    frame → tile signatures, point mapping
  AnnotakeInput/    event taps: trigger key and click cleanup; clicks/keys/scrolls;
                    Accessibility labels and flags; active app/window tracking
  AnnotakeExport/   caption strips, click markers, PNGs + steps.md, capture folders,
                    filmstrip trims, retention cleanup
  AnnotakeApp/      the app, as a library: SessionController, recording pipeline, menu bar, pill,
                    card, filmstrip, Settings, the first run, the email sign-up, Send Feedback,
                    the move to Applications, self-test (§8), the brand mark and logo
  Annotake/         the executable: main.swift, and SparkleUpdater.swift (Sparkle is linked only here)
  annotake-replay/  CLI: runs a saved raw session through AnnotakeCore and prints its decisions
  AnnotakeRelease/  Foundation only: the Sparkle feed (appcast) writer
  annotake-appcast/ CLI: adds a release to the feed; make release runs it
Tests/
  AnnotakeCoreTests/     unit and golden tests; Fixtures/ holds raw sessions (never work data, see §8)
  AnnotakeCaptureTests/, AnnotakeInputTests/, AnnotakeExportTests/, AnnotakeReleaseTests/, AnnotakeAppTests/
```

The app is a library plus a small executable so its tests can import it the normal way. `AnnotakeApp` defines an `Updater` protocol, and the executable injects a Sparkle-backed one, so Sparkle stays out of the libraries. The libraries' one network call is `EmailSignup.post`, the email sign-up, which only the app itself makes. Tests and `--render-ui` give their signups a post that never sends, and `--selftest` and `--render-ui` never create the updater, so the tests and those two modes make no network calls.

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
| Updates | Sparkle 2.10 (`SPUStandardUpdaterController`), embedded in `Contents/Frameworks` and signed inside out with the app's identity. Info.plist: `SUFeedURL` (the `appcast.xml` in `fayzan123/annotake-releases`), `SUEnableAutomaticChecks` true and `SUScheduledCheckInterval` 86400 (a daily check with no opt-in prompt), `SUEnableSystemProfiling` false, and `SUPublicEDKey`: every update's zip must carry an EdDSA signature from the matching private key |

## 7. Permissions and failure handling

| Situation | Behavior |
|---|---|
| Screen Recording missing or expired (macOS re-prompts monthly) | Pill shows "Screen Recording permission needed" with Open Settings. Nothing is saved. |
| Input Monitoring missing | The key doesn't work, but the menu bar Start/Stop still does. Settings shows the fix. Detected with `CGPreflightListenEventAccess()`, not by tap creation. |
| Accessibility missing | Still records. Hold-mode clicks keep the trigger's modifier (⌘), and captions say `Clicked at (x, y)`. |
| Any permission missing | The menu shows "Fix permissions…", which opens the first run's permission steps (§3.7). |
| No email address saved | Nothing records. The pill says "Add your email to start recording", with Open, which brings the email step forward (§3.2). |
| Accessibility revoked while click cleanup runs | macOS can block all clicks until reboot if an active tap outlives its permission. Annotake checks trust every 2 s and removes the active tap immediately. |
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
  - `annotake-replay` prints the picker's decisions, for tuning.
- **Module unit tests:** Capture, Input, Export, and the app each test their pure logic:
  - output size, signatures, and point mapping;
  - key classification, and label rules over a fake Accessibility tree;
  - rendering, capture folders, trims, and retention;
  - the session state machine, the pill text, and card stacking.

  Event taps, the stream, AX calls, and the UI are covered by the self-test and the checkpoints.
- **Self-test:** `make selftest` opens a test window of Annotake's own with a scripted scene. It records the window through the real ScreenCaptureKit → picker → export path, with no permission needed, and reports the architecture, frames, timings, and picked captions in `selftest.json`. `make selftest-intel` runs the Intel half through Rosetta, where the signature-time limit is twice as loose, because it measures translation rather than a Mac. The test window opens on the sharpest screen: on a 1× external monitor the drawn pointer covers fewer tiles, and the picker keeps an extra frame (Checkpoint 3). `make ui-snapshots` renders every panel and window to PNGs the same way. Implementation sessions run both unattended.
- **Log:** `~/Library/Logs/Annotake.log` records gestures, state changes, timings, and errors. It never records labels, window titles, keys, or email addresses: the sign-up logs only `email: sent`, `email: invalid`, or `email: retry later`.
- **Send Feedback…** prepares a draft to Fayzan's Gmail for now, and to `feedback@annotake.app` once that receives mail (defined once, as `Feedback.address`); the user sends it. The report is the version, the macOS version and Mac model, the three permissions' states, the last 400 lines of the log, and the newest `Annotake-*.ips` crash report from the last 7 days, capped at 200,000 bytes. It's written to a temporary `Annotake-report-<date>.txt`:
  - When Mail can take an attachment, its compose window opens with "What happened?", the three fact lines, and the report attached.
  - Otherwise (Gmail in a browser, say, or no account set up) a mailto draft opens with the same text, its body capped at 1,500 characters, and Finder shows the report to attach.
  - The log records only that a report was prepared, never its contents.
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
  - `make icon` redraws the app icon; the `.icns` is committed.
  - `make sparkle-keys` runs once. It creates Sparkle's EdDSA key in the login keychain (account `annotake`), exports the private half to `.signing/sparkle-private-key` for signing updates without prompts, and writes the public half to `Resources/sparkle-public-key.txt`, which is committed. Losing the private key means existing installs can never be updated, so it's backed up in a password manager.
  - `make cert` runs once. It creates a free self-signed signing identity, "Annotake Local Signing", so macOS permissions survive rebuilds (ad-hoc signatures silently lose them).
  - `make devid-csr` writes `.signing/devid.csr`, the request to upload to Apple for a Developer ID Application certificate (G2 Sub-CA). `make devid-import CER=<file>` imports the certificate Apple issues, with Apple's Developer ID G2 intermediate (without Xcode nothing installs it), into `.signing/annotake-signing.keychain-db`, and writes the team id to `.signing/team-id`. The intermediate also goes into the login keychain, where Xcode would put it: while signing, `codesign` checks the chain again without the other keychains on the search list, and fails with `errSecInternalComponent` ("leaf MissingIntermediate") when the intermediate is only in the signing keychain (Checkpoint 3). The bundler puts it back if it's missing.
  - `make` builds and assembles `Annotake.app`: one app for Apple silicon and Intel, from two release builds (`--triple arm64-apple-macosx15.0` and `x86_64-apple-macosx15.0`) merged with `lipo`. Two `--arch` flags would need Xcode's XCBuild.
  - `make run` builds it and opens it.
  - `make install` copies it into `/Applications`, removing any older copy in `~/Applications`.
  - `make zip` produces a zip for the work Mac, without resource forks, extended attributes, or ACLs (`ditto --norsrc --noextattr --noacl`), so iCloud's tags and the provenance attribute stay out.
  - `make release NOTES="…"` makes a release (below); `make release DRY_RUN=1 NOTES="…"` runs the same pipeline locally, without credentials, and publishes nothing.
  - `make dmg-background` redraws the disk image's background (`scripts/make-dmg-background.swift`, 600 × 400 at 1× and 2×, combined with `tiffutil`); `Resources/dmg-background.tiff` is committed. `make dmg-venv` puts dmgbuild 1.6.5 in a Python virtual environment in `.build/dmgbuild-venv`.
  - `make selftest` runs the self-test, `make selftest-intel` runs it as Intel through Rosetta, and `make ui-snapshots` renders the UI to PNGs (§8); it fails if a first-run step would be clipped.
  - Bundling assembles and signs the app in a temporary folder, then copies it to `build/`: iCloud Drive syncs `~/Documents` and tags bundle folders with Finder information faster than it can be stripped, and `codesign` rejects that.
- **Signing:** every build is signed with the hardened runtime, nested code first. The bundler uses the Developer ID Application identity once it's in the signing keychain, and "Annotake Local Signing" until then (`SIGN_IDENTITY` overrides both). Development and release builds then share one signature, so permissions granted to one carry over to the other. A release (`RELEASE=1`) requires the Developer ID and adds a secure timestamp; other builds use `--timestamp=none`. Secrets stay in `.signing/` (gitignored) or the keychain, never in the repo. The hardened runtime loads only libraries signed by the app's own team, and the local identity has none, so only builds without a Developer ID carry `com.apple.security.cs.disable-library-validation`, to load their own Sparkle.
- **Versions:** `VERSION` holds the marketing version (`0.2.0`), and the build number is the commit count (`git rev-list --count HEAD`). The bundler writes them into `CFBundleShortVersionString` and `CFBundleVersion`, and each launch logs them, e.g. `launched Annotake 0.2.0 (78)`.
- **The app is built only on the personal MacBook,** using Fayzan's own Claude membership rather than work AI.
- **Releases** come from `make release` (`scripts/release.sh`), on `main` with a clean tree that matches `origin/main`. It:
  1. builds with `RELEASE=1`, then notarizes the app (`notarytool`, keychain profile `annotake-notary`), staples it, and checks that Gatekeeper sees it as notarized;
  2. zips it with `ditto --norsrc --noextattr --noacl`: Sparkle's archive, and what the install command downloads;
  3. makes the disk image with dmgbuild (`scripts/dmg-settings.py`): the app and an Applications link side by side over a background with an arrow, and the app icon as the volume icon. The image is signed, notarized, and stapled too;
  4. signs the zip for Sparkle (`sign_update --ed-key-file .signing/sparkle-private-key`);
  5. publishes last, so a failure leaves everything public untouched: a GitHub release `v<version>-<build>` in the public, releases-only repo `fayzan123/annotake-releases` with the zip and the disk image, then that repo's `appcast.xml` (written by `annotake-appcast`), `install.sh`, and `README.md` (from `scripts/releases-README.md`).

  The work is done in a temporary folder outside iCloud Drive; the zip, the disk image, and a dry run's feed end up in `build/release`.

  A release whose app sends a new consent id waits for the site: deploy its `site/api/_lib/consent.json` and see `make site-smoke URL=https://annotake.app`'s consent check pass (400, not 422) first. Until then the site answers the new id 422, and every new copy's address waits on the app's backoff ([email list design](plans/2026-10-15-email-list-design.md) §3.1).

  Apple took 49 minutes over the first notarization (Checkpoint 3), so a release survives a slow one. The script uploads, then waits up to `NOTARY_TIMEOUT` (30 minutes by default). If Apple isn't done by then, it stops before publishing. Running the same command again picks up where it left off: the signed app, the disk image, and Apple's submission ids stay in a work folder for that version and build until it's published, and anything Apple has notarized by then just gets its ticket stapled.
- **Installing:** the disk image at `https://github.com/fayzan123/annotake-releases/releases/latest/download/Annotake.dmg`, or `curl -fsSL https://raw.githubusercontent.com/fayzan123/annotake-releases/main/install.sh | sh`. The command checks for macOS 15 or later, downloads the latest zip, verifies its signature, quits a running Annotake, installs to `/Applications` (or `~/Applications` without admin rights), removes a copy left in the other Applications folder, and opens Annotake. It finds Annotake by its bundle id, never by name alone, so an app that shares the name is never touched. Files `curl` downloads get no quarantine flag.
- **Updates** come through Sparkle (§6.2): a daily check of the feed, and Check for Updates… in the menu.
- **Next:** a Homebrew tap in Stage 3 ([distribution design](plans/2026-09-30-distribution-design.md)).

## 10. Milestones

- **M0: Spikes. Done 2026-09-24.** Throwaway code that answers the risky questions first. Results and decisions: [spikes/findings.md](spikes/findings.md).
  1. **Gestures and click cleanup.** Do Right ⌘ gestures and click cleanup work in Chrome, Safari, Cursor, and Finder? Which permission does each part need?
     - If click cleanup is unreliable, hold mode becomes look-only and click-through flows use double-tap.
  2. **Button names.** Are they readable in Chrome and in Electron apps (Cursor, Slack)?
     - These apps may only expose web content to Accessibility after Annotake sets `AXEnhancedUserInterface` or `AXManualAccessibility` on them (inferred; verify).
  3. **Capture behavior.** Measure capture start latency and dirty-rect/idle behavior on macOS 15.7 and 26.
  4. **Dropping into Cursor.** Does Cursor's chat accept 20 dropped PNGs, and in order?
     - If not, revisit the drag payload.
  5. **Exclusion.** Confirm the pill and card never appear in recordings.
- **M1: Core. Done 2026-09-24.** Frame picker, gesture recognizer, cap fitting, tests, `annotake-replay`.
- **M2: Recording end to end.** Right ⌘ → capture → frames in a folder, with no polish.
- **M3: Output.** Caption strips, click markers, `steps.md`, the card, and filmstrip trimming.
- **M4: The rest of the app.** Settings with the Meet-style picker, first launch, menu bar, retention cleanup, sounds.
- M2–M4 are designed in [plans/2026-09-24-m2-m4-design.md](plans/2026-09-24-m2-m4-design.md):
  - Session 4 builds M2 and M3, then comes Checkpoint 1 on the personal Mac.
  - Session 5 builds M4, then comes Checkpoint 2 on both Macs.
- **M5: Dogfood.** A week of real use at work, tuning thresholds from local raw sessions.
- **M6: Distribution.** The friends round, the beta, then the paywall and launch, in the [distribution design](plans/2026-09-30-distribution-design.md). The Stage 1 build (Session 8) is done; Checkpoint 3 makes the first notarized release.

## 11. Not in v1

- Radial ring
- MP4/Both output (MP4 is planned for Pro and gets its own design; see the [distribution design](plans/2026-09-30-distribution-design.md))
- Voice narration
- "Save the last 30 s"
- On-screen text changes (OCR)
- Region capture
- Caps Lock and mouse-button triggers
- Windows
- Any AI
- Network access beyond what the distribution and email list designs add (update checks, the email sign-up, sign-in, the plan, counts)
- Agent-specific integrations (MCP, auto-paste)

Details for each are in [v2-backlog.md](v2-backlog.md).

## 12. Risks

- **Permission re-prompts.** macOS re-asks for Screen Recording permission monthly, on both 15 and 26, and Annotake can only surface this clearly.
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
| The mark: a movie camera on an A (2026-10-01) | "Take" is a film take, and the A starts the name. The red reel is the click marker's red, and in the menu bar it turns red only while recording. Jost, not Avenir Next: it's free to use on the website too. |
| Frames and events reach the picker through `LiveSession`, one time-ordered queue (2026-09-24, M2–M4 design) | A click's label arrives up to ~100 ms after the click. Ordering keeps each click on the screen it happened on, and makes raw sessions replay exactly as they ran live. |
| A change under a pointer that stayed put counts (2026-09-24) | After a click the pointer sits on what it clicked, so a ticked checkbox produced no frame. |
| A hold released before the reveal is discarded (2026-09-24) | If the pill never appeared, nothing was recorded. |
| `--selftest` records Annotake's own scripted window (2026-09-24) | It needs no permission, so unattended implementation sessions can test the real capture path. |
| Clicks and scrolls outside the recorded area aren't logged (2026-09-24) | The frames can't show them. |
| First launch is one checklist; the menu gains "Fix permissions…" (2026-09-24) | Fewer clicks than a wizard, and Screen Recording expires monthly. |
| The first run becomes one step at a time, with a welcome, a practice run, and a drop box (2026-09-30) | Strangers need to understand it and succeed once without help, as with Wispr Flow. [Distribution design §5.2](plans/2026-09-30-distribution-design.md#52-the-stage-1-build) |
| Launch at login only from an Applications folder (2026-09-24) | A development build never leaves a stale login item. |
| Distribution in three stages (friends round, beta, paywall and launch), moved forward by bars, not dates (2026-09-30) | Outside validation comes before productising, and Fayzan sets the pace. [Distribution design](plans/2026-09-30-distribution-design.md) |
| Closed source and freemium: a weekly soft limit, a hard stop at 2.5×, Pro at $9/month or $72/year (2026-09-30) | Reputation first, with revenue as proof. Wispr's cap design, without the slowdown |
| Accounts, with sign-in first; "nothing you record leaves your Mac" replaces "never touches the network" (2026-09-30) | Counting users, emails, referrals, and team plans need accounts. Nothing recorded is ever sent |
| Rename to Annotake, internals included, in the Developer ID build (2026-09-30) | "Flipbook" search results and domains are crowded, and one name everywhere avoids confusion |
| No upgrade path from Flipbook (2026-10-01) | Only Fayzan ever installed Flipbook. The migration, the old app's retirement, and the existing-user first run went with it; they also matched "Flipbook" by name, so another app or folder with that name could have been moved or deleted. |
| Updates through Sparkle 2, linked only into the executable (2026-09-30, Session 8) | Fixes reach everyone fast, and the libraries and their tests keep no network code |
| One app for Intel and Apple silicon (2026-09-30, Session 8) | Friends and coworkers may have Intel Macs, and one download fits everyone |
| Builds signed without a Developer ID opt out of library validation (2026-09-30, Session 8) | The self-signed identity has no team, so the hardened runtime wouldn't load the app's own Sparkle. Developer ID builds share one team and don't need it |
| The first run asks for an email address, with feedback and news only through an unticked box, and recording waits for one (2026-10-15) | Every copy leaves a way to reach its user about security fixes and broken updates, which CASL exempts from consent; feedback and news need it. [Email list design](plans/2026-10-15-email-list-design.md) |
