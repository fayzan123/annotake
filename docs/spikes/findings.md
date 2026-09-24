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

## Capture

## Drag card

## Decisions
