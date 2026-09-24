# Flipbook: v2 backlog

This file lists everything deliberately left out of v1, together with the design notes and research gathered so far, so nobody has to redo the thinking. See [spec.md](spec.md) for v1 and [research-notes.md](research-notes.md) for sources.

## Radial ring (single tap of the trigger)

**Status:** designed but deferred on 2026-09-23. The core loop doesn't need it, and it's the fiddliest UI in the app.

**Trigger:** the ring opens at the cursor on a **single tap**.
- v1 already reserves that gesture, so no learned gestures change.
- It must wait out the double-tap window (300 ms) before opening. If that feels slow, try showing it optimistically with a short fade-in.

**Layout:** six slices in fixed positions, so muscle memory can form:

```
            Window…
  Settings           Display…
            ( • )
  Folder             Output
            Recent
```

**Interaction:** hover a slice and click to choose it, as in the Logitech Actions Ring.
- Esc or a click outside closes the ring.
- The center is a dead zone.

**Slices:**
- **Window…:** windows highlight under the cursor, like the window mode of macOS screenshots. Click one to start a hands-free recording of that window. This is a one-off and doesn't change the default.
- **Display…:** each screen shows "Click to record this screen". Also a one-off.
- **Output:** cycles Frames → MP4 → Both. The choice sticks because it's a preference. It only matters once MP4 ships.
- **Recent:** the cards for the last 5 captures.
- **Folder** and **Settings**.
- **Future slices:** a voice toggle, "save the last 30 s", and region capture, once they exist.

**Research:**
- Keep it to 8 items or fewer per ring.
- Up/down/left/right are selected more accurately than diagonals (Kurtenbach & Buxton).
- A delay before showing the ring gave no consistent benefit (CHI 2020).
- Blender keeps its pie menu open for clicking after a quick tap, and uses fixed positions.
- Game weapon wheels use a dead zone in the center.

**Implementation:** a non-activating `NSPanel` that joins all Spaces as a full-screen auxiliary, with window level ≥ status bar. Create it at launch and exclude it from capture.

## MP4 / Both output

**Status:** deferred on 2026-09-23. The AI use case doesn't need video, and macOS's ⌘⇧5 covers video in the meantime.

**Use case:** attach a video to a Jira ticket for humans, alongside the frames for the agent.

**Implementation:**
- `SCRecordingOutput` (macOS 15+) can run on the same `SCStream` as the frame output.
  - Only one recording output is allowed per stream, and it must be added before `startCapture`.
  - It defaults to H.264 MP4.
  - Developers report corrupt files only when microphone capture is on.
- **Card:** in MP4 mode the card is the video. In Both mode, a small ▶ MP4 chip drags separately.
- **Settings:** Output mode Frames / MP4 / Both.

## Voice narration

**Status:** deferred on 2026-09-23. In the meantime, Fayzan can dictate context with Handy after dragging.

**Options:**
- Apple `SFSpeechRecognizer` on-device: works on macOS 15, but weaker.
- `SpeechAnalyzer`: macOS 26+ only.
- A bundled Whisper model via WhisperKit: 150 MB or more.
- A variant: record voice into the MP4 only, with no transcription.

**Open question:** transcription runs an on-device ML model. Does that violate the "no AI in the product" rule? There's no cloud and no bill, so it's Fayzan's call.

**Implementation notes:**
- Align words to frames using the recognizer's word timestamps, not arrival time; recognizers report words several seconds late.
- Opening the mic on Bluetooth headphones switches them to headset mode, which drops the first words and lowers audio quality. Prefer the built-in mic.

## "Save the last 30 seconds"

**Status:** later, as an opt-in (decided 2026-09-23).

**Use case:** bugs that already happened. Flipbook captures continuously and keeps a rolling buffer of candidate frames. The frame picker runs all the time instead of buffering video.

**Costs:**
- Always-on capture keeps macOS's purple recording indicator lit.
- The lock screen shows "Your screen is being observed".
- It keeps the capture daemon busy, which costs battery.

It must therefore be opt-in and obvious, and it needs its own trigger: a ring slice or a distinct gesture.

## On-screen text changes (OCR)

**Status:** deferred.

**Implementation:**
- Run Vision `VNRecognizeTextRequest` (fast or accurate mode) on kept frames only.
- List the lines that appeared or disappeared since the previous frame, in the caption and in `steps.md`. Example: "New: 'Changes not saved'".
- Exclude the menu bar.
- OCR jitter creates fake "new" words, so diff with a tolerance.

**Open question:** same as voice. On-device ML versus the no-AI rule.

## Region capture

Drag a rectangle to capture, using `SCStreamConfiguration.sourceRect`. It would likely be a ring slice.

## More trigger options

**Caps Lock:**
- Remap it to F18 with this command:

  ```
  hidutil property --set '{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x70000006D}]}'
  ```

- Per Apple TN2450 this needs no sudo, but the mapping is lost on reboot.
  - Re-apply it at launch, when a keyboard connects, and on wake.
  - Merge it with any existing mappings, and restore the originals on quit.
  - A crash leaves Caps Lock sending F18 until Flipbook relaunches or the Mac reboots.
- Catch F18 with a Carbon `RegisterEventHotKey`. It reports both press and release, swallows the key, needs no Accessibility permission, and still works under Secure Input.
- If Karabiner is running, let Karabiner handle the Caps Lock remap instead.
- It was rejected as the default because people who use Caps Lock would lose it. It's fine as an option.

**Mouse side buttons:** these arrive as other-mouse events (button 3 or 4). An active tap blocks their Back/Forward action.

## Windows version

- **Build it as a sibling app.** It must pass the same FlipbookCore golden tests, or a port of them, and write an identical output format.
- **Capture:**
  - Windows.Graphics.Capture, with per-frame `DirtyRegions` (Windows 11 24H2, SDK 10.0.26100).
  - Or DXGI Desktop Duplication, which gives dirty and move rects but may over-report.
- **Trigger:** Right Ctrl, via low-level keyboard and mouse hooks.
- **Labels:** UI Automation.
- **Overlays:** exclude them from capture with `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)`.
- **Language:** whatever is best at the time: C#, Rust/Tauri, or Swift. Swift runs on Windows; Arc's Windows browser is written in it.

## Signed download + Homebrew tap

**Status:** planned for when Fayzan is ready to share. He chose "pay later" on 2026-09-23.

**Signing:**
- The Apple Developer Program costs $99/yr.
- A notarized app needs Developer ID signing, the hardened runtime, and a secure timestamp. It must not have the get-task-allow entitlement.
- Notarize with `notarytool`.

**Without signing:**
- macOS blocks downloaded apps.
- Since macOS 15 the Control-click bypass is gone. Users have to go to System Settings → Open Anyway, and many work Macs disable that.

**Homebrew:** since 2026-09-01 the main cask repo has disabled casks that fail Gatekeeper. A personal tap is unaffected.

**Updates:** there's no in-app updater, because v1 never touches the network. Updates come through Homebrew or a manual download. Revisit this if an opt-in update check is ever wanted.

**Mac App Store:** not viable. The sandbox disallows Accessibility and active event taps.

## Considered and not planned

- **Folder drag, steps.md in the drag, or a copy-log button:** caption strips were chosen instead.
  - Web chats reject dropped folders.
  - It's unverified whether Cursor accepts a dropped .md file.
  - Revisit if an agent needs the text log separately.
- **Contact sheet** (a grid of frames in one image): worse for UI text at the same token cost.
- **Machine-readable capture.json:** v1 writes only `steps.md`. Add it if tools need it.
- **Agent-specific integrations** (an MCP server, auto-paste into the last-used assistant): Flipbook stays agent-agnostic by design.
