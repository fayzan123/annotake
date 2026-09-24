# M0 spike findings

Results for [the M0 plan](../plans/2026-09-23-m0-spikes.md). Every observation goes here, failures included.

## Toolchain

Checked 2026-09-24 on the personal MacBook (macOS 15.7.9).

- **Install.** `softwareupdate --list` offered only Command Line Tools 16.2 and 16.4, not 26.3. CLT 26.3 was downloaded from developer.apple.com/download/all and installed from the .pkg. It installs and runs on 15.7.9.
- **Versions.** `swift --version` → Apple Swift 6.2.4 (swiftlang-6.2.4.1.4). `xcrun --show-sdk-version` → 26.2. `xcode-select -p` → `/Library/Developer/CommandLineTools`.
- **Test framework: Swift Testing, with extra flags. XCTest does not work.**
  - Plain `swift test` fails with `no such module 'Testing'`.
  - The XCTest fallback fails with `no such module 'XCTest'`. XCTest is not part of the CLT at all.
  - `Testing.framework` does ship in the CLT, at `/Library/Developer/CommandLineTools/Library/Developer/Frameworks`, but SwiftPM doesn't add that folder to the search paths. This command passes:
    ```
    F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
    swift test -Xswiftc -F -Xswiftc $F -Xlinker -F -Xlinker $F -Xlinker -rpath -Xlinker $F
    ```
  - The package also needs `platforms: [.macOS(.v15)]`. Without it, the `@Test` macro expansion fails with `'isolation()' is only available in macOS 10.15 or newer`.
  - **For M1:** use Swift Testing. Put those flags in a `make test` target so plain `swift test` isn't the documented command. Xcode is not needed.
- **Signing.** `make cert` created `Flipbook Local Signing` (the listing shows `CSSMERR_TP_NOT_TRUSTED`, as expected), and a second run printed `Signing identity already exists`.
- **iCloud Drive vs. codesign.** The repo lives in `~/Documents`, which iCloud Drive syncs. A later rebuild failed with `codesign: resource fork, Finder information, or similar detritus not allowed`, because the bundle had picked up `com.apple.FinderInfo`, `com.apple.fileprovider.fpfs#P` and `com.apple.provenance`. **Fix:** `scripts/bundle-app.sh` now runs `xattr -cr "$APP"` just before signing, and three consecutive builds then signed cleanly. (If this ever recurs, build to a directory outside iCloud.)
- **Spike build.** `make spike-run`: the release build took 34 s, `FB` appears in the menu bar, and the log shows `spike launched`. `codesign` shows `Authority=Flipbook Local Signing`, and the designated requirement is `identifier "com.fayzanmalik.flipbook.spike" and certificate leaf = H"4ce02ce5…"`.

## Trigger & click cleanup

Personal MacBook, macOS 15.7.9, 2026-09-24. Log: `~/Library/Logs/FlipbookSpike.log`.

- **Row 1, permission prompts. Pass.**
  - Toggling on showed exactly one prompt, "Keystroke Receiving" ("would like to receive keystrokes from any application"). That is macOS's name for **Input Monitoring**.
  - Before the grant: `CGPreflightListenEventAccess`, `CGPreflightPostEventAccess` and `AXIsProcessTrusted` were all false. `CGRequestListenEventAccess()` returned false and showed the prompt, once per toggle.
  - **`tapCreate` succeeds even without Input Monitoring** (`tap created: yes`), but no events arrive. The real app must check `CGPreflightListenEventAccess()`, not whether the tap was created.
  - After granting and relaunching: listen access is true, `keyDown` events arrive, and post access and AX are still false.
  - Once (at 11:20:30, before the grant) the listen tap was disabled with `tapDisabledByUserInput` (raw 0xFFFFFFFF) and was re-enabled.
- **Row 2, Right ⌘C / Right ⌘V in TextEdit. Copy and paste work, but the gesture was misclassified.**
  - Neither shortcut logged `CHORD`. Both logged `HOLD START`, because Right ⌘ was held for more than 250 ms before the letter key was pressed. The letter arrived 56 ms (⌘C) and 302 ms (⌘V) after `HOLD START`.
  - The resulting "recordings" lasted about 0.20 s (⌘C) and 0.58 s (⌘V). The 0.5 s discard rule would drop the first, but **the ⌘V one would be saved as a spurious capture**.
  - **Retest: 10 more Right ⌘C / ⌘V at a natural pace. 8 were misread as `HOLD START` and only 2 as `CHORD`.**
    - Time from Right ⌘ down to the letter, for the 8 misread ones: 389, 268, 668, 323, 407, 338, 275, 287 ms. Including the first round (306, 552 ms), the typical range is **270–400 ms**, with a maximum of 668 ms.
    - Whole press (⌘ down → ⌘ up): 371–796 ms.
  - **Conclusion: a 250 ms hold threshold can't tell Fayzan's shortcuts from a hold.**
    - Option A: raise the threshold to about 700 ms. Hold recordings would feel slow to start.
    - Option B (suggested): start at 250 ms, but if any key is pressed while Right ⌘ is still held, treat the press as a shortcut and silently discard the recording. The start sound and pill would then need to wait until about 700 ms, so they don't flash during shortcuts.
    - To decide in Task 6.
- **Row 3, hold 1 s. Pass.** `HOLD START`, then `HOLD STOP`.
- **Row 4, double-tap / single tap / double-tap. Pass.** `HANDS-FREE START`, `SINGLE TAP (ignored)`, `HANDS-FREE STOP`.
- **Row 5, before Accessibility. Pass.**
  - With only Input Monitoring granted, every recording logged `active tap created: no`. So **the event-modifying tap needs Accessibility**, and without it clicks keep ⌘.
  - Right ⌘ + clicking a Chrome link opened a new tab. The click came before 250 ms, so it logged `CHORD (leftMouseDown)`, the spec's "⌘-click is a shortcut" case.
- **Row 6, Chrome link during a hold, with Accessibility. Pass: opened in the same tab.**
  - After the grant, the probes show `AXIsProcessTrusted = true`, but `CGPreflightPostEventAccess` is **still false**.
  - `active tap created: yes`, then `stripped ⌘ from leftMouseDown`. The listen tap then saw the click with `⌘ flag: no`.
  - So the modifying tap works with Input Monitoring plus Accessibility, and "post events" access is never needed.
  - `AXIsProcessTrustedWithOptions(prompt)` returned false at the moment it showed the prompt, as expected.
  - After a relaunch (row 14), `CGPreflightPostEventAccess` is **true**. The earlier false was because Accessibility was granted mid-process, and the preflight value is cached until relaunch. The real app should re-check after a relaunch, or not rely on the post-access preflight at all.
- **Row 7, Safari link during a hold. Pass: opened in the same tab.** The log shows `stripped ⌘` and `⌘ flag: no`.
- **Row 8, Cursor. Not tested.** Cursor isn't installed on the personal Mac. Check it on the work Mac with the zip.
- **Row 9, Finder, two clicks during a hold. Pass: the second click replaced the selection.** Both clicks were logged as stripped.
- **Row 10, Finder drag to a folder on the same volume during a hold: moved.** Not conclusive: on the same volume, both a plain drag and a ⌘-drag move. It only shows up on a different volume (plain = copy, ⌘ = move).
- **Spike change made during testing.** The spike gave no visible sign of whether it was recording, which caused two mis-ordered attempts: a cancel ended hands-free mode, so the next "stop" double-tap started a new recording. The menu-bar title now reads `FB ●` while recording, and key logs include `IsSecureEventInputEnabled()`.
  - **For the real app:** state feedback such as the pill is essential for hands-free mode, because it's easy to lose track of whether a recording is running.
- **Row 11, hands-free + Right ⌘ + Esc on Chrome's print dialog. Pass.** `CANCEL (Esc consumed)` was logged and the dialog stayed open. The listen tap never saw that Esc, because the active tap swallowed it first.
- **Row 12, hands-free + plain Esc on the dialog. Pass.** Recording was running (`HANDS-FREE START` at 11:36:54), the Esc at 11:37:00 closed the dialog, and no `CANCEL` was logged.
- **Row 13, Safari password field (facebook.com login). Gestures pass. The spec's Secure Input assumption does not hold.**
  - The single tap and the hold (`SINGLE TAP (ignored)`, `HOLD START`/`HOLD STOP`) work with the password field focused.
  - The 5 letters typed in the field **were delivered to the listen tap as `keyDown`**, and `IsSecureEventInputEnabled()` was false throughout.
  - Spec §4.4 says "macOS also blocks key events there", which is not true in this test. Privacy is unaffected, since only the key class is logged and never the content. But the real app must not rely on Secure Input, and should detect password fields itself through the AX subrole `AXSecureTextField`.
- **Row 14, rebuild + relaunch. Pass: no new permission prompts.** The self-signed identity keeps the grants.
- **Row 15, Accessibility revoked mid-hold. Pass.** The switch was turned off at 11:39:14.7. `ACCESSIBILITY REVOKED — active tap removed` came 0.5 s later (the next 2 s watchdog tick), and the mouse kept working. (An earlier attempt at 11:39:00 didn't revoke anything: the click apparently didn't flip the switch.)

### Permissions

| Capability | Permission needed | Evidence |
|---|---|---|
| Listen-only tap sees Right ⌘, keys, clicks | Input Monitoring | Before the grant, the tap is created but no events arrive. After the grant and a relaunch, events arrive |
| Active (modifying) tap: click cleanup, Esc consumption | Accessibility (plus Input Monitoring) | `active tap created: no` until Accessibility was granted |
| "Post events" access | Not needed | The active tap worked while `CGPreflightPostEventAccess` was false |
| Prompts | Only Input Monitoring prompts automatically, via `CGRequestListenEventAccess()`. Accessibility needs `AXIsProcessTrustedWithOptions(prompt)` | Row 1, row 6 |

### Pass / fail

| # | Result |
|---|---|
| 1 | Pass (one prompt: Input Monitoring) |
| 2 | **Fail**: shortcuts at a natural pace are misread as holds (8 of 10) |
| 3 | Pass |
| 4 | Pass |
| 5 | Pass (no active tap without Accessibility; clicks keep ⌘) |
| 6 | Pass (Chrome: same tab) |
| 7 | Pass (Safari: same tab) |
| 8 | Not tested (no Cursor on the personal Mac; check on the work Mac) |
| 9 | Pass (Finder: selection replaced) |
| 10 | Inconclusive (a same-volume drag moves either way) |
| 11 | Pass |
| 12 | Pass |
| 13 | Pass for gestures. Key events were **not** blocked in the password field |
| 14 | Pass |
| 15 | Pass (0.5 s) |

**Conclusion: click cleanup is reliable → keep hold mode.** It works in Chrome, Safari and Finder clicks. Cursor is untested, and the Finder copy/move case is unverified. **Separate blocker for Task 6:** the 250 ms hold threshold misfires on normal Right ⌘ shortcuts (row 2).

## Accessibility labels

Personal MacBook, macOS 15.7.9, 2026-09-24. Three rounds:
1. Plan method: parent walk ≤ 3.
2. After `Enable AX in Chrome/Electron`.
3. Controlled: Chrome and Slack freshly relaunched, with a diagnostic walk ≤ 8 that logs the role chain and the depth where a label appears.

No jerky animations or slowness were observed after setting the flags.

**Side effect found later (during Task 5):** after `AXManualAccessibility` was set, Cursor showed its own prompt: *"Screen reader usage detected. Do you want to enable editor.accessibilitySupport to optimize the editor for screen reader usage?"* VS Code-based apps react to the flag visibly. The real app should expect this prompt (the user can answer No), and it's another reason to set the flag only while recording, and to test clearing it at stop.

| App | Label quality, no flag | Needs flag? | Label quality, with flag | Typical lookup |
|---|---|---|---|---|
| Safari (web + chrome) | **Good**: `button "Google Search"`, `button "Go back"`, `combo box "Search"` | No | — | 2–23 ms |
| Chrome, its own UI (toolbar) | **Good**: `button "New Tab"`, `"Back"`, `"Reload"` | No | — | 2–20 ms |
| Chrome, web content | **None**: the hit is `AXScrollArea` > groups; nothing inside is exposed, even after 10 s of AX queries | **Yes**: `AXEnhancedUserInterface` | **Good**: `link "https://fayzanmalik.com/"`, `button "Edit profile"`, `button "Save"`, `link "Rungraph"` | 1–3 ms |
| Cursor | **None**: unlabeled `AXGroup`s | **Yes**: `AXManualAccessibility` | **Good**: `outline row "CLAUDE.md"`, `button "Plan New Idea ⇧Tab"` | 0.5–12 ms |
| Slack | **None** | **Yes**: `AXManualAccessibility` | **Good**: `"Channel hacker-badges"`, `text entry area "Message to hacker-badges"`, `outline "Channels and direct messages"` | 1–8 ms |
| VS Code (bonus, not a target) | None | Flag accepted (AXError 0) | Still none (`AXImage` inside ≥ 8 groups) | 0.4–28 ms |
| Finder (file in list view) | **Generic**: the hit is `AXCell` (empty) > `AXRow` > `AXOutline "list view"`. The file name is in a child of the cell | No flag; needs a child lookup | — | 2–37 ms |
| System Settings (a switch) | **None**: `AXCheckBox/AXSwitch` with no title or description. The text is a sibling in the same row | No flag; needs a sibling or `AXTitleUIElement` lookup | — | 18–100 ms |
| Dock, menu bar, menus | **Good**: `dock item "Safari"`, `menu item "System Settings…"` | No | — | 0.5–93 ms |

Details:
- **Chrome returns `AXError -25208` (`kAXErrorNotImplemented`) when `AXEnhancedUserInterface` is set, but the flag takes effect anyway.** Web content appeared on the next click, about 4 s later. The real app must ignore this error code.
- Electron apps (Slack, Cursor, VS Code, GitHub Desktop) accept `AXManualAccessibility` with `AXError 0`. Detecting Electron by the presence of `Contents/Frameworks/Electron Framework.framework` worked.
- In round 2, a single Slack click right after enabling still had no label; in round 3 it worked on every click. Most likely a one-off.
- **A naive parent walk gives wrong labels.** When nothing is exposed, walking up reaches the window and returns the **window title** as the label (e.g. `"Who's using Chrome?"`, `"hardware (Channel) - … - Slack"`). The real app must stop at `AXWebArea`/`AXWindow`, treat a label found there as "no label", and log `Clicked at (x, y)`.
- Useful lookups: when the hit is `AXStaticText` inside `AXLink`/`AXButton`, use the parent's label. The `AXStaticText` value alone was a fragment (`" to search"`).
- Lookup time: usually 0.5–25 ms; the first lookup in an app, and the menu bar or System Settings, took up to about 100 ms. Do it off the event-tap callback, as the spike does.

**Decision for M2:**
- **Flipbook sets the flags, only while recording.**
  - At recording start, set `AXEnhancedUserInterface` on running Chrome instances and `AXManualAccessibility` on running Electron apps.
  - Do the same for any such app launched or activated during the recording.
  - Ignore -25208 from Chrome.
  - Clearing the flags at stop is untested; verify in M2, and keep them set if clearing breaks a screen reader the user runs.
- **Label rules:**
  - title → description → the parent's label for static text in a link or button → the first child's value for `AXCell`/`AXRow` → the row sibling's text for an unlabeled switch or checkbox.
  - Never read past `AXWebArea`/`AXWindow`.
  - Otherwise fall back to `Clicked at (x, y)`.

## Capture

### Personal MacBook (macOS 15.7.9), 2026-09-24

Displays: built-in Retina (1512×982 pt, 3024×1964 px, output 1920×1246), and a 2560×1080 external "E29w-20" (1×, output **1920×810**, aspect preserved).

- **Permission.**
  - The first run failed right away: `SCShareableContent` threw `SCStreamErrorDomain -3801 "The user declined TCCs for application, window, display capture"` and macOS showed the Screen Recording prompt.
  - After granting it and relaunching, everything worked.
  - No re-prompt appeared during the session.

| Run | Scenario | Shareable content | `startCapture()` returned | First complete frame | Complete / idle (of 100) |
|---|---|---|---|---|---|
| 1 | Hands off | 32 ms (+29 ms 2nd query) | 84 ms | **112 ms** | 37 / 63 |
| 2 | Typing in TextEdit | 21 ms (+37 ms) | 37 ms | **44 ms** | 87 / 13 |
| 3 | Scrolling a long web page | 25 ms (+31 ms) | 37 ms | **48 ms** | 99 / 0 |
| 4 | Ultrawide, moving a window | 26 ms (+44 ms) | 38 ms | **41 ms** | 100 / 0 |

- **Start latency.**
  - About 40–50 ms from `startCapture()` to the first complete frame. The first run after launch took about 110 ms.
  - Adding `SCShareableContent` (20–35 ms), the total from key press to first frame is about 70–150 ms. **No pre-warming is needed.**
- **Idle behavior.**
  - When nothing changes, SCK keeps delivering frames at the 10 fps interval, but with `status = idle` (1) and no image to process.
  - Run 1: all 37 complete frames came in the first ~3.8 s (the menu closing, the hand leaving the trackpad, a menu-bar indicator animation). From 3.9 s to 10 s, every frame was `idle`.
  - The spec's assumption holds: skip idle frames, and nothing new arrives while the screen is still.
- **Dirty-rect coordinate space: output pixels.**
  - Rects span 0…1919 × 0…1241 on the 1920×1246 output, and 0…1921 × 0…811 on the 1920×810 output, with a top-left origin.
  - They are not in points (1512×982) or native pixels (3024×1964).
  - `contentRect` is reported in output points (`959×623` = 1920×1246 / `scaleFactor` 2; `1920×810` at scaleFactor 1). `contentScale` = 0.634 (built-in) or 0.75 (ultrawide).
  - **Conversion for the Capture module:** none for tile math, because dirty rects are already in the same pixel space as the delivered buffer. To map to global screen points, divide by (output width / display width in points).
- **Caret and typing.** The caret shows up as a thin dirty rect, e.g. `(1063,530 3×18)` output px (≈2.4×14 pt), well inside the spec's 4 × 48 pt caret filter. While typing, each frame's dirty rect is the growing text run, e.g. `(1058,527 454×25)` → `(1058,527 553×25)`.
- **Scrolling.** Mostly large rects over the scrolled area, 99 complete frames out of 100.
- **Other small changes.** A 13×24 px rect in the menu bar at (1700,11) changed at 10 fps for the first ~3.8 s of run 1. Most likely the macOS screen-recording indicator animating in. Thin 2 px-tall rects at the top of the ultrawide came from the same area.
- **Exclusion. Pass.** In the checked frames (run1-04, run3-05, run4-04), the red pill panel does not appear, and neither does the notification banner. The spike's own `FB` status item is also excluded (the whole app is filtered out).
    - **Validity check:** Fayzan saw the red pill on screen during the runs. A notification posted the same way (`osascript display notification`) afterwards did display as a banner on this Mac, so the banner was on screen during the runs and its absence from frames is real.
- **Important: `com.apple.notificationcenterui` is not in `SCShareableContent(onScreenWindowsOnly: true)` while no banner is showing.** Filtering with that list alone would not exclude banners. The spike detected this and re-queried with `onScreenWindowsOnly: false` (+30–45 ms), which found it.
  - The real app must get Notification Center from the all-windows query, or cache it. Spec §7 already plans for a cached list.
- **Pill placement.** The spike moves the pill to the recorded screen at capture start, so exclusion is tested on the screen being recorded (the plan put it on the main screen only).
- PNGs are saved as `~/Desktop/flipbook-spike-frames/run<N>-<NN>.png` (a run prefix, so runs don't overwrite each other).

### Work Mac (macOS 26), 2026-09-24

The zip was built on the personal Mac and installed into `/Applications` (not `~/Applications`), then the quarantine flag was cleared. Built-in Retina: 1728×1117 pt, 3456×2234 px, output **1920×1240**. Work-Mac frames were inspected locally only and are not stored anywhere in the repo (§8 fixture privacy).

- **Permission.** Same as 15: the first run hit `-3801 "The user declined TCCs…"` plus the Screen Recording prompt. After granting and relaunching, it worked, with no further re-prompt.

| Run | Scenario | Shareable content | `startCapture()` returned | First complete frame | Complete / idle |
|---|---|---|---|---|---|
| 1 | Hands off | 39 ms | 92 ms | **123 ms** | 47 / 52 |
| 3 (logged as run 2) | Scrolling | 38 ms | 47 ms | **53 ms** | 100 / 0 |

- **Start latency.** Same pattern as 15: about 120 ms on the first run after launch, then about 50 ms.
- **Dirty rects are in output pixels here too.** They extend to 1919 × 1194 on the 1920×1240 output.
- **Notification Center is in the on-screen-only list on 26.** `com.apple.notificationcenterui` was found by `onScreenWindowsOnly: true` in both runs, so no second query was needed. This differs from 15, so the real app must handle both.
- **Exclusion. The pill and the banner pass. The status item fails.**
  - Frame run1-06 (6 s) has no pill and no notification banner. (Pill visibility on screen was confirmed. Banner display on the work Mac was not checked separately.)
  - **But the spike's `FB` menu-bar status item *is* visible in the macOS 26 frame.** On 15 it was excluded along with the app. On 26, excluding the application apparently doesn't cover its `NSStatusItem`.
  - For the real app, the menu-bar icon, including its "recording" state, will show up in frames on 26. The spec only promises that the pill, cards, filmstrip and Settings stay out. Fix options: exclude the status item's window explicitly (`exceptingWindows`/window-level filter), or accept it as cosmetic. Decide in Task 6.
- **Idle behavior.**
  - Hands-off run 1 had idle stretches (1.3–1.4 s, 2.4–5.1 s, 7.7–10 s).
  - But **from 5.2 s to 7.6 s, and in single frames at 8.5 s and 9.6 s, 6–7 identical dirty rects were reported at 10 fps at the bottom center** (x ≈ 664–1257, y ≈ 1090–1177 output px), with nobody touching the Mac.
  - That region overlaps where the excluded pill sits, but also app UI underneath it. The saved frames show no visible change there. It could be an app redrawing behind the scenes, or the excluded pill panel's region being reported as dirty on 26. **Unexplained.**
  - For M2: Core compares tile signatures, not dirty rects alone, so identical pixels produce no "motion" and the cost is only CPU. Recheck when the real pill updates its timer every second.

## Drag card

Personal MacBook, macOS 15.7.9, 2026-09-24. The card drags 20 `NSDraggingItem`s (file URLs to `01_0m00s.png` … `20_0m19s.png`, each 1920×1200 with a big number), and the source offers `.copy`.

- **Claude Code in VS Code's integrated terminal:** `operation=1` (copy, reported as success), so the card hid. **Only the first path was inserted** (`…/flipbook-drag/01_0m00s.png`), as **plain text**; Claude Code did not turn it into an `[Image #1]` attachment. So 1 of 20 arrived.
  - **Lesson: a non-empty drag operation does not mean every frame landed.** VS Code reported success after keeping 1 of 20 items.

| Target | Accepted? | Images | In order? | Logged operation |
|---|---|---|---|---|
| Cursor (Agents chat input) | Yes | **20** | **Yes, 1→20** | 1 (copy) |
| Claude Code in VS Code's terminal | Partly | **1**, as a plain-text path (no `[Image #1]`) | — | 1 |
| Claude Code in Terminal.app / iTerm | Not tested | — | — | — |
| ChatGPT web (Chrome, free plan) | Partly | **2** (free-plan upload limit) | Not noted | 1 |
| Claude.ai web (Chrome) | Yes | **20** | **Yes, 1→20** | 1 |
| Slack message box | Partly | **10** (Slack's per-message limit) | **Yes, 1→10** | 1 |
| Jira | Not tested (not reachable from the personal Mac) | — | — | — |
| Finder folder | Yes | **20 files copied** | — | 1 |

- **Every target reported a successful drop (`operation = 1`, copy), including the partial ones.** So the card's "hide after a successful drop" can't tell a full drop from a partial one.
- The order is preserved everywhere the order could be seen (Cursor, Claude.ai, Slack). Targets that cap the count keep the **first** N.
- **Decision: the drag payload is OK** (20 file URLs in step order).
  - Limits are the target's, not Flipbook's: Slack 10, ChatGPT free 2, VS Code terminal 1.
  - File names (`01_…`) and the caption numbers already carry the order when a target drops some.
  - Follow-ups for Task 6 or M3:
    - (a) Maybe keep the card after a drop into known-limited targets, or always keep it for a few seconds, so the rest can be dragged again. The filmstrip already allows dragging single frames.
    - (b) Test Claude Code in Terminal.app/iTerm and Jira on the work Mac.

## Decisions
