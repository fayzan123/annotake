# Annotake plans: how to run them

Sessions 1–7 were written when the app was called Flipbook.

Each session starts fresh in Claude Code: paste its prompt from below, and the plan files hold the details.

Rules for every session:
- **Superpowers skills only where the prompt names them.** The superpowers plugin loads at the start of every session, and each prompt below says which skills to use:
  - Planning sessions use `superpowers:brainstorming` and `superpowers:writing-plans`.
  - Implementation sessions use none. Test-first is a plain instruction there, not the `test-driven-development` skill.
- **`writing-plans` only in its skilleted form.** Superpowers updates install a fresh, full copy of every skill; the update to 6.4.1 undid the earlier reduction, and 6.4.1 has been reduced again. After an update, run skillet on `writing-plans` before the next planning session. To check, run `wc -l ~/.claude/plugins/cache/claude-plugins-official/superpowers/*/skills/writing-plans/SKILL.md`: the newest version should show about 43 lines, not about 190.
- **Implementation sessions run long and unattended.** You're on the Max 20x plan, so each session works through as many tasks as it can on its own, and your hands-on checks (permissions, real apps, both Macs) are batched into as few checkpoints as possible, ideally one per milestone, instead of pauses after every task. Ultracode isn't needed: most tasks build on each other in the same files, so one long session fits better than many parallel agents.
- **A checkpoint only where you're needed.** A plan stops for you only where you must act (keys, permissions, real apps, the work Mac) or where a question needs your opinion. Everything else the session verifies itself, with tests, the self-test, UI snapshots, and the log. Mid-session, a session stops only for a permission prompt it can't answer, or a plan expectation that looks wrong.
- **Test-first wherever the code is testable:**
  1. Write the tests.
  2. Watch them fail.
  3. Implement.
  4. Watch the tests pass.
  5. Commit.
- **Build only on the personal MacBook,** using your own Claude membership.

## Order

1. **Session 1: M0 spikes. Done 2026-09-24.** Results and decisions are in [../spikes/findings.md](../spikes/findings.md); the spec and the M1 plan are already updated with them. The repo is pushed to the private GitHub repo `fayzan123/flipbook`, renamed `fayzan123/annotake` at the end of Session 8.
2. **Session 2: M1 core. Done 2026-09-24.** `AnnotakeCore` (the frame picker, gesture recognizer, cap fitting, and caption and `steps.md` text), its tests, and `annotake-replay` are on `main`. What it found for later plans is under Session 2 below.
3. **Session 3: the M2–M4 plan. Done 2026-09-24.** The design is [2026-09-24-m2-m4-design.md](2026-09-24-m2-m4-design.md) and the plan is [2026-09-24-m2-m4-app.md](2026-09-24-m2-m4-app.md); `docs/spec.md` has the changes the design made.
4. **Session 4: M2 + M3, the recording loop. Done 2026-09-24.** Recording end to end: capture, input, `LiveSession`, export with caption strips and markers, the pill, card, filmstrip, and Recent Captures, plus `make selftest` and `make ui-snapshots`. Checkpoint 1 passed apart from one label bug; the results are in [../checkpoints.md](../checkpoints.md).
5. **Session 5: M4, the rest of the app. Done 2026-09-24,** run straight after Checkpoint 1 in the same session. The label fix, Settings with the Meet-style picker, the first-launch checklist and launch at login, the full menu with live settings, the retention schedule, and `spikes/` deleted. What both sessions found for later plans is under Session 5 below.
6. **Checkpoint 2 on both Macs. Done 2026-09-25.** Everything passed; the results are in [../checkpoints.md](../checkpoints.md). Fixed during it: Restore Defaults on each settings tab, and `make replay` with capture paths (they have spaces).
7. **Session 6: the Checkpoint 2 fixes. Done 2026-09-25.** Caption line 2 names the recorded window in window mode, a slider drag logs one line, and the `stream` log line says where the dirty area is. Your checks are in its section below.
8. **M5: real use,** under way since Checkpoint 2 (no plan).
9. **Session 7: the distribution design and the Stage 1 plan. Done 2026-09-30.**
   - The design covers how the app reaches other developers and makes money, and the rename from Flipbook to Annotake: [2026-09-30-distribution-design.md](2026-09-30-distribution-design.md). Friends can already install the current build with the one-line command in its §5.1.
   - The plan: [2026-09-30-stage-1-build.md](2026-09-30-stage-1-build.md).
10. **Session 8: the Stage 1 build. Done 2026-09-30.** Flipbook is Annotake everywhere, with migration from Flipbook; one signed app for Intel and Apple silicon, with an icon, version numbers, Sparkle updates, Send Feedback, a step-by-step first run, the move to Applications, and `make release` with a disk image (369 tests). What it decided and skipped is under Session 8 below.
11. **Checkpoint 3 on both Macs. Done 2026-10-01.** The results are in [../checkpoints.md](../checkpoints.md).
12. **Next: the friends round** ([distribution design §5](2026-09-30-distribution-design.md#5-stage-1-the-friends-round)), on a release whose Send Feedback goes to Fayzan's Gmail, and alongside it the Stage 2 design and plan ([§11](2026-09-30-distribution-design.md#11-sessions)).
13. **Session 9: the landing page design and plan. Done 2026-10-01.** Pulled ahead of the rest of Stage 2: annotake.app offers the download directly (no waitlist), with a privacy policy, Terms, and the link by email for phones. The design is [2026-10-01-landing-page-design.md](2026-10-01-landing-page-design.md), and the plan is [2026-10-01-landing-page-build.md](2026-10-01-landing-page-build.md).
14. **Session 10: the landing page build. Done 2026-10-01.** annotake.app is built and tested locally in `site/`: the page with its three animations, the policies, the `/download` redirect, and the "Email me the link" function (73 unit tests, 312 page tests in Chrome, WebKit, and Firefox). What it decided and skipped is under Session 10 below.
15. **Next: Checkpoint 4,** which connects the site to Vercel, email, and DNS: the list is in [../checkpoints.md](../checkpoints.md#checkpoint-4-the-site). It can run alongside the friends round.
16. **2026-10-11, inline (no session prompt): fixes from Fayzan's own use, released the same day.** Dragging a card with 17 or more frames quit Annotake (9bfed66). The filmstrip got its keys: ← → move a ring between frames, ⌫ removes or restores, Return applies, and the card shows "Saving…" while a trim re-renders. A click on a frame, or Space, shows it full screen, where the same keys work (spec §3.4). Frame sensitivity and `steps.md` in the drag were parked in [../v2-backlog.md](../v2-backlog.md). For later plans:
    - AppKit lays out a drag of 17 or more items on worker threads, which read the source view's `isFlipped`, and its ancestors'. In Swift 6 a main-actor override traps there, so a drag source's `isFlipped` must be `nonisolated`. The filmstrip drags one frame at a time, so its views don't need it yet.
    - `make app` failed until `.build/*/release/ModuleCache` was deleted: its precompiled headers still pointed at `flipbook/`.
17. **2026-10-15: the email list design and plan.** Every copy asks for an email once, in the first run or after its update, and joins a list in Resend, with topics, a consent record, a welcome email, and an unsubscribe. The design is [2026-10-15-email-list-design.md](2026-10-15-email-list-design.md), and the plan is [2026-10-15-email-list-build.md](2026-10-15-email-list-build.md).
18. **The email list build. Done 2026-10-16,** unattended, on branch `email-list`, which isn't on `main` yet. The app has the email step and its email-only pass, recording that waits for an address, and the Email row in Settings; the site has `/api/subscribe`, `/api/unsubscribe`, and the policies' email sections. What it decided is in the design's §13, and what it found is under "The email list build" below.
19. **Next: Checkpoint 5,** which connects the list to Resend and Vercel, then releases it: the list is in [../checkpoints.md](../checkpoints.md#checkpoint-5-the-email-list).

## Session 1: M0 spikes (done)

Plan: [2026-09-23-m0-spikes.md](2026-09-23-m0-spikes.md). Kept for reference.

| Task | The agent builds | You do |
|---|---|---|
| 1. Setup | Checks Swift 6.2 and which test framework works. Creates the signing certificate (`make cert`), the app-packaging script, and an empty menu-bar app. | Install Command Line Tools 26.3. Confirm "FB" shows up in the menu bar. |
| 2. Right ⌘ | Hold and double-tap detection, click cleanup, swallowing the Esc of Right ⌘ + Esc. | Run 15 checks. Key ones: ⌘C still works; holding Right ⌘ and clicking a link in Chrome or Safari opens it in the same tab; Cursor ⌘-click doesn't jump to a definition; Finder; password fields; permissions survive a rebuild. |
| 3. Button names | Reads the name of whatever you click, through macOS Accessibility. | Click buttons, links, and fields in Chrome, Safari, Cursor, Slack, Finder, and System Settings, before and after the "Enable AX in Chrome/Electron" toggle. Note which names come back. |
| 4. Capture | 10-second test captures that log start time, changed regions, and saved frames. | Four captures: idle, typing, scrolling, and on the ultrawide. Confirm the pill and notifications aren't in the saved frames. Repeat two runs on the work Mac (AirDrop plus one Terminal command). |
| 5. Drag | A card that drags out 20 numbered PNGs. | Drag it into Cursor, Claude Code, ChatGPT, Claude.ai, Slack, Jira, and Finder. Note whether all 20 arrive, and in order. |
| 6. Decisions | Writes the results into `docs/spikes/findings.md` and updates the spec. | Review the decisions. |

Prompt:

```
In ~/Documents/GitHub/flipbook, execute docs/plans/2026-09-23-m0-spikes.md task by task. Read docs/spec.md and the plan first. Don't use any superpowers skills. Pause at every "Manual check" block and wait for my results, record them in docs/spikes/findings.md, and commit after each task.
```

## Session 2: M1 core (done)

Plan: [2026-09-23-m1-core.md](2026-09-23-m1-core.md). Kept for reference.

What M0 changed in this plan:
- Tests run with `make test` (or `make test FILTER=<suite>`). Plain `swift test` fails with only the Command Line Tools, because it can't find Swift Testing.
- The gesture logic has the 800 ms hold reveal: a key pressed before it means the hold was a shortcut, and the recording is discarded.

1. Package scaffold
2. Tile grid
3. Frame signatures, plus the test scene builder
4. Data model, settings numbers, caption text
5. Change detection: ignoring the cursor, a blinking caret, and spinners
6. Trimming to the 20-frame limit
7. The frame picker: triggers, settling, which frames to keep, stopping
8. Removing frames from the filmstrip
9. `steps.md`
10. Right ⌘ gesture logic, including the hold reveal
11. Raw sessions, the replayer, golden tests
12. The `flipbook-replay` command and final checks

To watch it pick frames from a test recording, run `swift run flipbook-replay Tests/FlipbookCoreTests/Fixtures/synthetic-click-flow` (add `--cap 3` to see frames merge), or `make replay SESSION=<dir>`.

What M1 found, for later plans:
- `make test` also passes `-disable-cross-import-overlays`. The Command Line Tools ship Swift Testing's `_Testing_Foundation` overlay without its `Modules` folder, so any test file that imports both `Testing` and `Foundation` fails to compile without the flag. New test targets rely on it too.
- `Bundle.module` only exists once a test target declares `resources:`, and SwiftPM needs the resource folder to exist first. So create the folder and declare it before generating fixtures; the M1 plan had these the other way round. The first `FLIPBOOK_REGENERATE_FIXTURES=1` run then fails `goldenFixturesMatch` once, because the test bundle was copied before the files existed. The next run passes.
- Git treats `tiles.bin` as text because it has no zero bytes. Mark `*.bin` as binary in `.gitattributes` before real raw sessions get saved.

Prompt:

```
In ~/Documents/GitHub/flipbook, execute docs/plans/2026-09-23-m1-core.md task by task, test-first: write the listed tests, run them with `make test FILTER=<suite>` and watch them fail, implement, watch them pass, commit after each task. Never use plain `swift test`; it can't find Swift Testing without Xcode. M0 is done: read docs/spec.md, the Decisions section of docs/spikes/findings.md, and the plan before starting. Leave spikes/ and the M0 scripts alone. Don't use any superpowers skills. If a test expectation in the plan looks wrong, stop and tell me instead of changing it. When all tasks pass, push main to origin.
```

## Session 3: M2–M4 plan (done)

Design: [2026-09-24-m2-m4-design.md](2026-09-24-m2-m4-design.md). Plan: [2026-09-24-m2-m4-app.md](2026-09-24-m2-m4-app.md). Kept for reference.

What it decided, beyond the spec:
- Two implementation sessions with two checkpoints, and a checkpoint only where you're needed.
- `LiveSession` in Core feeds the picker in time order, so a click waits for its label and raw sessions replay exactly.
- A change under a pointer that stayed put now counts, so a ticked checkbox gets its own frame.
- A hold released before the reveal saves nothing.
- `make selftest` records Flipbook's own scripted window through the real pipeline without any permission, and `make ui-snapshots` renders every panel to PNGs, so unattended sessions can check their own work.
- The plan is lean: exact test expectations for the logic that's easy to get subtly wrong, and constraints plus verification for the macOS glue.

Prompt:

```
In ~/Documents/GitHub/flipbook, M0 and M1 are done. Read docs/spikes/findings.md, docs/spec.md, both plans and the session guide in docs/plans/, and Sources/FlipbookCore. Use superpowers:brainstorming to work out the M2–M4 design with me (capture, input, export, app UI), then superpowers:writing-plans to write the plan. Keep the design doc and the plan in docs/plans/, and if we change anything the spec decides, update docs/spec.md too. Implementation runs later in fresh sessions without superpowers skills, test-first wherever the code is testable, so give the plan a how-to-execute header like the M1 plan's instead of the "For agentic workers" line. Size those sessions to run long and unattended, as the guide's rules say: as few sessions as the work allows, with my hands-on checks batched into as few checkpoints as possible. Add the sessions and their prompts to docs/plans/README.md. Don't start implementing; once I've approved the plan, commit and push main to origin.
```

## Session 4: M2 + M3, the recording loop

Plan: [2026-09-24-m2-m4-app.md](2026-09-24-m2-m4-app.md), Tasks 1–20.

1. App targets, build targets, app skeleton
2. A change under a pointer that stayed put counts
3. `LiveSession`, the raw session writer, the replayer on top
4. `TriggerKey` and the Settings model
5. Output size, point mapping, the cursor box
6. Frame signatures from pixels
7. Capture folders and the manifest
8. Caption strip and click markers
9. Finishing a capture, filmstrip trims, retention
10. Content, target resolution, exclusions, the stream
11. The recording pipeline and the self-test
12. Trigger keys and event classification
13. The input thread, event taps, gestures
14. Accessibility labels and the Chrome/Electron flags
15. App and window context
16. The session rules
17. Wiring, the pill, the menu, sounds, UI snapshots
18. The card
19. The filmstrip and Recent Captures
20. Final checks, push, and the Checkpoint 1 list

Before you leave it running: keep the Mac awake and unlocked, for example with `caffeinate -dims` in a spare terminal tab. The self-test can't capture while the Mac is asleep or locked.

Your part is Checkpoint 1 at the end, on the personal Mac, taking about 40 minutes. The list is in the plan's Task 20: grant the permissions, then try gestures, click cleanup, labels, the output, the card, the filmstrip, and a password field. Keep your results for Session 5.

Prompt:

```
In ~/Documents/GitHub/flipbook, execute Tasks 1–20 of docs/plans/2026-09-24-m2-m4-app.md, test-first as its header says. Read docs/spec.md, docs/plans/2026-09-24-m2-m4-design.md, and the plan before starting. Don't use any superpowers skills. Run tests only with `make test` (never plain `swift test`), and commit after each task. From Task 11 on, run `make selftest` wherever the plan says, and look at its frames and at the UI snapshots yourself. Never launch the full app: it requests permissions at launch. Stop only if macOS shows a permission prompt you can't answer, or a test expectation in the plan looks wrong (tell me why; don't change it). When Task 20 passes, push main to origin and give me the Checkpoint 1 list.
```

## Session 5: M4, the rest of the app (done)

Plan: [2026-09-24-m2-m4-app.md](2026-09-24-m2-m4-app.md), Tasks 21–27.

What Sessions 4 and 5 found, for later plans:
- `make test` runs 298 tests. `make selftest` records the app's own scripted window through the real pipeline (about 12 frames, first frame in about 65 ms, stop to a finished capture in about 0.6 s), and `make ui-snapshots` writes every panel and window to `build/ui`.
- `scripts/bundle-app.sh` retries signing up to 3 times: iCloud Drive can tag the new bundle between `xattr -cr` and `codesign`.
- Additions beyond the plan's interfaces: `InputMonitor.handsFreeStartedElsewhere()` (menu-started recordings record input, and a double-tap or trigger + Esc ends them), `InputLog` (the Input module's log hook), `RecordingPipeline.onStreamEnded`, and `AXNode.window`.
- A container labeled with its window's title counts as no label (Checkpoint 1: Chrome's tab strip).
- Retention runs at every launch, as the spec says, and then on wake and hourly once 24 h have passed; the plan had the launch run check the 24 h too.
- Captures in window mode show macOS's "being shared" badge in the window's title bar from the second frame on.
- Claude Code in VS Code's integrated terminal receives only the first dropped frame, as a path. Terminal.app receives every frame (Checkpoint 2); iTerm is untested.

21. Checkpoint 1 results and fixes
22. The Settings window
23. The Record tab's Meet-style picker
24. The first-launch checklist and launch at login
25. The full menu and live settings
26. The retention schedule
27. Delete the spikes, final checks, push, zip, and the Checkpoint 2 list

Your part:
- Paste your Checkpoint 1 results into the prompt.
- Answer any decision a result needs.
- Run Checkpoint 2 at the end, on both Macs. The list is in the plan's Task 27: first launch after a permission reset, every setting, the picker, retention, and the work-Mac pass.

Prompt:

```
In ~/Documents/GitHub/flipbook, Session 4 is done. My Checkpoint 1 results:

<paste your results here>

Execute Tasks 21–27 of docs/plans/2026-09-24-m2-m4-app.md, test-first as its header says; Task 21 records my results in docs/checkpoints.md and fixes what failed. Read docs/spec.md, docs/plans/2026-09-24-m2-m4-design.md, and the plan before starting. Don't use any superpowers skills. Run tests only with `make test`, and commit after each task. Never launch the full app; use `make selftest` and `make ui-snapshots`. Stop only if macOS shows a permission prompt you can't answer, a test expectation in the plan looks wrong, or one of my results needs a decision from me. When Task 27 passes, push main to origin, run `make zip`, and give me the Checkpoint 2 list.
```

## Session 6: Checkpoint 2 fixes (done)

No plan file. The three fixes are below, from Checkpoint 2 in [../checkpoints.md](../checkpoints.md). Do each one test-first, and commit each one on its own.

What Session 6 found, for later plans:
- `make test` runs 318 tests. The self-test renames its window as the dialog closes, and checks each frame's line 2, live and replayed.
- The window server has a renamed window's new title at once, and reading it by window ID takes about 0.1 ms, so window recordings read it as each frame arrives.
- Raw sessions of window recordings carry `"contextSource" : "recordedWindow"`. Sessions without it follow focus, so older ones replay unchanged.
- The `stream` line reads like `dirty 61440 px in 320×192 at (1480, 1190)`: the box around that second's dirty rects, in capture pixels from the top left. The capture's size is in the `recording started` line.
- New trigger or gesture settings log a line for the first change of a burst, or the first after a 2 s pause.

1. **Window mode: caption line 2 names the recorded window.** Line 2, and each step's context in `steps.md`, names whichever app and window have focus. So a window recording started from another app captions a picture of Finder with `Code — main.swift — flipbook` (capture `2026-09-24 at 17.58.54`). In window mode, line 2 should name the recorded window: its app, and its title at that step, whatever has focus.
   - Screen mode doesn't change, and neither do actions: `Switched to …` still names the app that got focus.
   - A window's title can be read by its window ID with `CGWindowListCopyWindowInfo`, since Flipbook has Screen Recording. Titles still never go in the log.
   - Raw sessions saved before the change must still replay, and the golden tests mustn't change.
   - Update spec §4.2.
2. **One log line per slider drag.** Every step of an Advanced slider logs `trigger key and gesture timings updated` (from `InputMonitor.applyPendingConfigurationIfIdle`, reached through `settingsChanged` in `AppMain.swift`), so one drag writes dozens of lines. A burst of changes should log one line. Settings still save on every step, and new timings still apply as soon as Flipbook is idle (spec §3.6).
3. **Where the personal Mac's constant redraws are.** On the personal Mac (macOS 15.7), a hands-off recording gets 10 complete frames a second, each with about 60,000 px dirty and nothing changed (Checkpoint 2, item 9). The once-a-second `stream` log line (`LogWindow` in `RecordingPipeline.swift`) has totals only. Add the bounding box of that second's dirty rects, in capture pixels (x, y, width, height), so the log shows where the redraws are. Coordinates are fine in the log, which never holds labels, window titles, or keys (spec §8).

To finish: `make test`, `make selftest` (look at its frames), and `make ui-snapshots` if anything visible changed. Mark Session 6 done in the list at the top of this file, push main to origin, and run `make zip`.

Your part, about 10 minutes:
- Quit Flipbook, run `make install`, and reopen it.
- Record 10 seconds hands-off, then run `grep " stream " ~/Library/Logs/Flipbook.log | tail -12`. The box says where the redraws are; see what's on screen there.
- In Settings → Record → Window, pick a window, then start a recording from another app. Line 2 should name the recorded window.
- Drag an Advanced slider, then press Restore Defaults. The log should get one line for the drag, not dozens.
- Put `build/Flipbook.zip` on the work Mac, as in Checkpoint 2.

Prompt:

```
In ~/Documents/GitHub/flipbook, run Session 6 in docs/plans/README.md: the three Checkpoint 2 fixes, each test-first. Read docs/spec.md, docs/checkpoints.md, and the Session 6 section before starting. Don't use any superpowers skills. Run tests only with `make test`, and commit after each fix. Never launch the full app; use `make selftest` and `make ui-snapshots`. Stop only if macOS shows a permission prompt you can't answer, or a fix needs a decision from me. When all three are done, push main to origin, run `make zip`, and give me the "Your part" list from the Session 6 section.
```

## Session 8: the Stage 1 build

Plan: [2026-09-30-stage-1-build.md](2026-09-30-stage-1-build.md), Tasks 1–15. Design: [2026-09-30-distribution-design.md](2026-09-30-distribution-design.md) §5.2.

1. The rename to Annotake, internals included
2. The rename in the docs
3. Migrating from Flipbook: settings, the captures folder, and retiring the old app
4. Version numbers
5. Intel and Apple silicon in one app
6. The app icon
7. Developer ID signing, with the local identity as a fallback
8. Sparkle updates and Check for Updates…
9. Send Feedback
10. The first run's rules
11. The first-run window
12. Move to Applications
13. The appcast writer
14. The disk image, the release script, and the Annotake installer
15. Final checks, push, the repo rename, and Checkpoint 3

Before you leave it running:
- **Keep the Mac awake and unlocked,** for example with `caffeinate -dims` in a spare terminal tab. The self-test can't capture while the Mac is asleep or locked.
- **The first build downloads Sparkle,** which took about 19 minutes on 2026-09-30.
- **The Apple Developer membership doesn't need to be active yet.** The session prepares the certificate request and signs with the local identity. The Developer ID, notarization, and the first real release happen at the checkpoint.

Your part is Checkpoint 3 at the end, on both Macs. The list is in the plan's Task 15:
- the certificate and notarization key;
- backing up two secrets;
- renaming the releases repo;
- the first `make release`;
- installing like a stranger;
- an update through Sparkle;
- Send Feedback;
- the first run as a new user;
- the work Mac;
- renaming the local folder once the session is closed.

What Session 8 decided, skipped, and found (everything else went as the plan says):

**Decisions:**
- **Task 1:** the old Flipbook keychain was deleted as planned, but a copy stays in `.signing/retired/` (gitignored, off the search list). It holds the only key that signed friends' Flipbook installs; delete it once Annotake has shipped.
- **Task 3:** `Migration.run` takes `oldDomain` and `report`, which default to Flipbook's real preferences and the log. Without them a test would import this Mac's real Flipbook settings, could rename markers in the real `~/Pictures/Flipbook`, and wrote into the real log.
- **Task 3:** when the captures folder can't be moved, `~/Pictures/Flipbook` stays the save location, so its captures stay listed and cleaned up (`failedMoveKeepsTheOldFolder`). The plan said only that the folder stays where it is. A `.flipbook` marker also counts when `.annotake` is unreadable, not only missing.
- **Task 5:** the self-test report names its architecture, and `make selftest-intel` checks it ran as `x86_64 (Rosetta)`. Under Rosetta the signature-time limit is 16 ms instead of 8: it measures translation, not a Mac, and the first Intel run averaged 7.3 ms.
- **Task 6:** icon sizes up to 64 px come from a simplified drawing with a bolder ring. Scaled down from the full one, the 32 px icon had no clearly red pixel; now it has 18.
- **Task 7:** `scripts/devid.sh` takes `SIGNING_DIR`, and the whole request → import ran against a throwaway keychain with a fake certificate. That caught a bug that made a good import fail and leave the `.p12` behind. The import refuses a certificate from another request, and expands `~` in `CER=` (zsh passes it to make as is). The bundler puts the signing keychain back on the search list when the folder moves.
- **Task 8:** the bundler assembles, signs, and checks the app in a temporary folder, then copies it to `build/`. With Sparkle's nested bundles, iCloud Drive re-tagged folders faster than they could be signed: three of three attempts failed. `codesign --verify --strict` inside `build/` stays unreliable for the same reason.
- **Task 8:** builds signed without a Developer ID carry `com.apple.security.cs.disable-library-validation`: without it the app crashed at launch, because the self-signed identity has no team, and the hardened runtime loads only libraries from the app's team. Developer ID builds don't carry it.
- **Task 8:** Sparkle's key is in the login keychain under its own account, `annotake`, as Sparkle recommends; `make sparkle-keys` ran without a prompt. "Check for Updates…" sits with Settings… above Quit.
- **Task 9:** the report ends with a newline, so its crash section ends with "… (truncated)" and a newline; the crash text is cut at a line.
- **Task 11:** the first-run window is 560 × 440 pt (the plan set only the width; the tallest step needs 392). Closing it on a permission step brings it back at the next launch; closing it on the practice run, the drop box, or You're set, or closing a Fix permissions… pass, finishes it (`closingLeavesOnlyPermissionsToComeBack`). Fix permissions… during an unfinished first run shows it where it is.
- **Task 11:** "a ✓ once granted" is a row above each permission step with a ✓ on every granted permission, since a grant moves the step on at once. The System Settings picture's switch is drawn, so it looks on even when the window isn't key. `make ui-snapshots` fails when a step would be clipped, through `build/ui/problems.txt`, because the app's printed output goes nowhere under `open`.
- **Task 11:** the "Flipbook was moved to the Trash" line is on the welcome step, as planned, which existing users skip; they see "Annotake replaces Flipbook, so macOS asks for these again." instead.
- **Tasks 3 and 11:** the constraint's grep also matches the plan's own identifiers outside the allowed files (`retiredFlipbook`, and the `LegacyFlipbook` type for its two notes). No string literal names the old app outside the allowed files; Task 15's check excluded those two identifiers.
- **Task 12:** the original goes to the Trash before the relaunch, since nothing runs after quitting, and the moved copy's quarantine flag is removed, so it gets no second Gatekeeper prompt. A development build in `build/` gets the offer too, and Not Now is remembered for the whole `com.fayzanmalik.annotake` domain.
- **Task 14:** `make release` works in a temporary folder outside iCloud Drive and copies the zip, the disk image, and a dry run's feed to `build/release`. Every zip, the one sent to Apple included, is made with `--norsrc --noextattr --noacl`. Publishing commits the feed, `install.sh`, and README in the releases repo's clone, then creates the GitHub release, then pushes, so the feed never names a release that doesn't exist.
- **Task 14:** dmgbuild 1.6.5 puts the background at `.background.tiff` in the volume's root, not in a `.background` folder; Finder finds it through `.DS_Store` either way. `install.sh` also removes an Annotake.app from the other Applications folder, and refuses a tampered or missing download (both checked).
- **Task 15:** the releases README doesn't name Flipbook, since the grep covers `scripts/`; `install.sh` says "Flipbook, Annotake's old name, was removed." when it removes one.
- **After Checkpoint 3's step 10,** commit 7c994d9 removed the whole Flipbook upgrade path: Task 3's migration, the existing-user first run, the legacy marker, and the installer's Flipbook steps. Only Fayzan ever installed Flipbook, and matching the name could touch another app's files. The Task 3, Task 11, and Task 15 decisions above about migration, existing users, and the installer's Flipbook note describe code that no longer exists.

**Skipped:** nothing. Every step ran, including `make cert`, `make devid-csr`, `make sparkle-keys`, the dmgbuild install, and the dry run. What only a person can check (notarization, the real first run, Sparkle installing an update, Send Feedback's draft, retiring Flipbook) is in Checkpoint 3.

**For later plans:**
- `make test` runs 369 tests in 58 suites (322 before the session).
- Sparkle 2.10.0 resolved in 3 s from SwiftPM's cache in `~/Library/Caches/org.swift.swiftpm`, not 19 minutes.
- The self-test's signature time varied between runs: 2.8–6.1 ms natively (limit 8) and 6.3–7.3 ms through Rosetta (limit 16).
- macOS's App Management protection may stop Annotake from moving Flipbook.app to the Trash ("Annotake was prevented from modifying apps on your Mac"). Flipbook is still quit, and the failure is logged. Checkpoint 3 step 7 shows whether it happens.
- The disk image's background is light (#F5F5F7); in dark mode Finder may draw the icon labels in white over it.
- Run strict `codesign` checks on copies outside `~/Documents`: iCloud Drive tags bundles in `build/` within a second.

Prompt:

```
In ~/Documents/GitHub/flipbook, run Session 8: execute Tasks 1–15 of docs/plans/2026-09-30-stage-1-build.md, test-first as its header says. Read docs/plans/2026-09-30-distribution-design.md, docs/spec.md, and the plan before starting. Don't use any superpowers skills. Run tests only with `make test` (never plain `swift test`), and commit after each task. Never launch the full app; use `make selftest`, `make selftest-intel`, `make ui-snapshots`, and `make release DRY_RUN=1`. I'm not here, so never stop to ask me anything: follow the plan header's "No stops until the end" rules, deciding or skipping, recording it, and carrying on. When Task 15 passes, push main, rename the GitHub repo as Task 15 says, and give me the Checkpoint 3 list with your Decisions and Skipped lists first.
```

## Session 10: the landing page build

Plan: [2026-10-01-landing-page-build.md](2026-10-01-landing-page-build.md), Tasks 1–15. Design: [2026-10-01-landing-page-design.md](2026-10-01-landing-page-design.md). The approved mockups are in [mockups/2026-10-01-landing-page/](mockups/2026-10-01-landing-page/).

1. The site skeleton, the local server, and the test harness
2. The brand, generated from BrandMark.swift
3. Tokens, the font, the theme, and the page frame
4. The hero and the Mac check
5. The email check and the link form
6. The link function
7. Through the gate
8. How it works
9. The privacy block and the final call
10. The footer and the logo animation
11. The privacy policy, the Terms, the licenses, and the 404 page
12. Search, sharing, and the preview image
13. Whole-page checks
14. The checkpoint tools
15. Docs, the session notes, and Checkpoint 4

Before you leave it running:
- **The first `make site-test` downloads Playwright's WebKit and Firefox,** a few hundred MB. A failed download is covered by the plan's network rules. Chrome tests use your installed Google Chrome, so keep it installed.
- **The session needs no screen and no permissions.** Keep the Mac awake anyway (`caffeinate -dims` in a spare terminal tab) so it doesn't stall.
- **Nothing goes live during the session.** It never deploys, creates accounts, or touches DNS, so nothing reaches annotake.app until Checkpoint 4.

Your part is Checkpoint 4 at the end, in the plan's Task 15:
- the Resend account and its DNS records;
- the Vercel project, its settings, and the firewall rule;
- registering annotake.com;
- the first deploy, with the smoke and burst checks;
- a real link email to your phone;
- the look on your iPhone and both Macs;
- reading the policies.

What Session 10 decided, skipped, and found (everything else went as the plan says):

**Decisions:**
- **Task 1:** `make site-unit` runs `node --test 'unit/*.test.js'`: Node 22's `--test` takes files or globs, not a directory. The page tests' server uses port 4174, so a running `make site-dev` (4173) never collides with it. The local server reads `site/.vercelignore` to decide what it never serves, as Vercel would. No Playwright device presets: their desktop Chrome and Firefox carry Windows user agents, and the Mac tests need each browser's own.
- **Task 2:** the Apple touch icon is drawn full-bleed from `BrandMark` instead of scaled from the app icon: iOS fills a touch icon's transparent margin with black. A test checks it's opaque. The favicon PNG still comes from the app icon.
- **Task 3:** the headline's second line is a block `span` after a space, not after a `<br>`, so the heading reads as one sentence. The toggle hides when scripts don't run. Once the visitor uses it, system changes stop applying for the visit, even when storage is blocked.
- **Task 4:** "Annotake is a Mac app. …" sits right after the "Email me the link" `<details>`, not inside it, so it shows under the closed button as in the phone mockup, and hides while the form is open. Under 480 px the header's Download for Mac hides; at 320 px it didn't fit. The download hint sits in an always-present `role="status"` region.
- **Task 5:** opening the form focuses the field within the tap, so a phone shows its keyboard; focus then moves to the sent or fallback box. The error line comes right under the field, in a darker red (`#D70015` / `#FF6961`), since the brand red is 3.55:1 on white. The fallback shows the link as selectable text, not a link, which a phone would follow into a disk image.
- **Task 6:** requests to Resend carry `User-Agent: annotake-link/1.0`: Resend's API reference says requests without one get a 403, and the plan's header list had none. A non-string `email` is invalid. The extra log lines (`invalid request`, `invalid address`, `busy rate limit`, `failed resend <status>`, `failed network`, `failed timeout`, `failed error <name>`) never carry an error message, which could hold the address.
- **Task 7:** `assets/player.js`, a small shared module, runs each animation only while it's on screen and marks it `data-visible`, so CSS animations pause too. It checks the position once at load as well, so a loop on screen starts at once. Instant changes use an `.instant` class, and the switch's knob slides with `transform`.
- **Task 8:** How it works has no side padding of its own: its film sizes itself to the window, and the padding pushed it 0.8 px past 320 px (the mockup hid that with `overflow-x: hidden` on the body, which the site doesn't use). The fade-up hides the figures only once `steps.js` runs. The card's title and hint are paragraphs, so the decorative canvas adds no headings. **The Task 8 commit went in with that 320 px failure:** a piped `make site-test | tail` hid make's exit status. The next commit fixed it, and from then on test runs and commits were separate steps.
- **Task 9:** the Finder window and Quick Look are `aria-hidden` (the "Plain files" row says the same in text). On a phone the Finder drops its sidebar and Kind column, and Quick Look sits under it; it overhangs by 28 px, not 34, to stay inside the section at 1024 px. The privacy grid's columns are `minmax(0, …)`: a plain `1fr` stayed as wide as the Finder's longest line. Styles for containers holding Acme windows use child combinators, since Acme has its own `.row`, `.side`, and `.ring`. The final call has no mark above its heading, as in the footer mockup.
- **Task 10:** the home page's static footer logo already has the live logo's raised view box, so swapping in the live SVG doesn't shift the page. **The implementation went in before its tests were seen failing;** they were then run with `logo.js` and its wiring set aside, and the new ones failed.
- **Task 11:** the policies' facts come from the app's code: the permission reasons from the first run, retention from Settings (7 days, 30 days, or Forever; 30 by default), and the update check from `bundle-app.sh` (once a day, system profiling off). The privacy policy adds that the US services handle data under US law (cross-border disclosure, as Canada's privacy commissioner expects) and that earlier versions are kept (it offered to send them on request until the contact was removed after the session). `sparkle.txt` is the 2.10.0 checkout's LICENSE, checked identical to GitHub's at the tag.
- **Task 12:** the home page also has `og:image:alt`, and every page, the function's small result page included, names its icons. In the preview image the gate sits at 78% of the width, so all three captioned frames are in the picture.
- **Task 13:** the checks found nothing to fix in the site. The first load is 137 KB uncompressed; raw, the CSS (35 KB) and JavaScript (44 KB) are over design §5.8's per-type figures, which are transfers, and compress to about 9 KB and 15 KB.
- **Task 14:** `checkHeaders` and `evaluateBurst` return lists of problems, so the tools print why. The smoke test cancels the disk image's body after its headers, and both targets refuse to run without `URL=`. Locally, the smoke test gave 5 PASS and 2 SKIP; the burst tool, run with 20 posts, gave all 200 and FAIL, as expected without a firewall, and the function logged only `ignored honeypot`.
- **The test harness, three workarounds,** all for browser quirks rather than the site:
  - **Firefox and `Cross-Origin-Opener-Policy`.** The header moves a new tab's first navigation into a new browsing context group. Playwright's Firefox then loses its color-scheme emulation, so the tests about the system setting launch a Firefox whose own preference is the scheme. It also misses about 1 first load in 80, so a Firefox `goto` that hasn't finished in 5 s is tried once more. Without the header, no load was missed in 240.
  - **Chrome launches.** Google Chromes started at the same moment sometimes never finished creating their first context: 4 of 80 launches stuck when four started together, 0 of 80 when started 600 ms apart. So Chrome workers start 600 ms apart, and the page tests run in 4 workers. With that, 6 Chrome-only runs and 3 full runs passed with nothing flaky. A retry on the Chrome project, tried in between, came out again.
  - **WebKit and the keyboard.** The keyboard tests use Option-Tab in WebKit, as Safari does by default on a Mac.

**After the session,** Fayzan removed every email address from the site: `hello@` and `feedback@annotake.app` won't exist, so ImprovMX and its Checkpoint 4 step are gone, the privacy policy and the Terms give no contact, and the link email comes from `noreply@annotake.app` with no reply address. The email link itself stays. Design §12 has it.

**Skipped:** nothing. Every step ran, including the browser download, the font and license downloads, `make site-og`, and the local smoke run. `git status` isn't clean only because of `.vscode/launch.json`: VS Code added two `annotake-appcast` launch entries before the session started, and they were left for you.

**For later plans:**
- `make test` runs 376 tests in 59 suites. `make site-unit` runs 73 `node:test` tests in under a second; `make site-test` runs them and then 312 page tests (Chrome, WebKit, and Firefox) in about 50 s.
- Playwright's clock keeps flowing in real time after `install()`. Timing tests call `pauseClock` (install, then `pauseAt`) before `goto` and move time with `runFor`; CSS transitions still run in real time.
- Node's `AbortSignal.timeout` doesn't keep the event loop alive. A real request holds a socket, so the function is fine, but a fake `fetch` that never answers needs a timer of its own, or Node exits mid-test.
- Specs import `test`, `expect`, and the helpers from `site/tests/pages/support.js`: `openPage`, `openWithScheme`, `useTheme`, `watchErrors`, and `pauseClock`.
- **The folder rename left old paths in `.build`:** `workspace-state.json` and the debug build's module cache still pointed at `flipbook/`, so `make test` failed until Task 2 repointed the one and deleted the other. The release build may need the same before the next `make app`, and the Sparkle checkout's git alternates still point at `flipbook/`, so `git status` there fails (SwiftPM doesn't mind).
- **From the design's open items (§9), for the next app release:** add Sparkle's MIT notice to the app bundle. Send Feedback keeps going to Fayzan's Gmail, since annotake.app receives no mail. The privacy policy must be updated before Stage 2's sign-in ships, and the 20-second video gets a section after How it works once it exists.

Prompt:

```
In ~/Documents/GitHub/annotake, run Session 10: execute Tasks 1–15 of docs/plans/2026-10-01-landing-page-build.md, test-first as its header says. Read docs/plans/2026-10-01-landing-page-design.md, the mockups in docs/plans/mockups/2026-10-01-landing-page/, and the plan before starting. Don't use any superpowers skills. Run the app's tests only with `make test` (never plain `swift test`) and the site's with `make site-test` and `make site-unit`, and commit after each task. Never launch the full app, never deploy, never create accounts or touch DNS, and never send a real email. I'm not here, so never stop to ask me anything: follow the plan header's "No stops until the end" rules, deciding or skipping, recording it, and carrying on. When Task 15 passes, push main and give me the Checkpoint 4 list with your Decisions and Skipped lists first.
```

## The email list build

Plan: [2026-10-15-email-list-build.md](2026-10-15-email-list-build.md), Tasks 1–10. Design: [2026-10-15-email-list-design.md](2026-10-15-email-list-design.md).

1. The unsubscribe link and function
2. The consent wording, the welcome email, and the subscribe function
3. The privacy policy and the Terms
4. `EmailConsent`: the wording, the address check, and the release guard
5. `EmailSignup`: saving, sending, and the backoff
6. The email step in the first run, and `.emailOnly`
7. Recording waits for an email
8. Settings, wiring, and the UI snapshots
9. End to end against the local server
10. Docs

Each task had its own review. After Task 9, an integration review checked the app against the site and the promises against the behaviour, and its fixes went in before Task 10.

Your part is Checkpoint 5, the plan's Task 11: the mailing address, Resend's topics, properties, and segment, Vercel's settings, the deploy and the smoke check, the copy and the design's open questions, the app in a real window, a real sign-up with replies and unsubscribing, and the release.

**Decisions:** in the design's [§13](2026-10-15-email-list-design.md#13-changes-from-planning-and-building), by task, with the open questions for you.

**Skipped:** nothing.

**For later plans:**
- `make test` runs 536 tests in 65 suites (402 before the build). `make site-unit` runs 162 `node:test` tests, and `make site-test` then 363 page tests in Chrome, WebKit, and Firefox, with 6 Chrome-only ones skipped in the others.
- Foundation's `precomposedStringWithCanonicalMapping` isn't JavaScript's NFC: its tables get Hangul and some Tibetan wrong. To match the site, compose with ICU (`applyingTransform(StringTransform("Any-NFC"), reverse: false)`), and lowercase with `Any-Lower`.
- A menu-bar app (`.accessory`) has no main menu, so its text fields get no ⌘V, ⌘C, ⌘X, ⌘A, or ⌘Z until one is installed: `EditMenu.swift`, now `MainMenu.swift`.
- A `@MainActor` class's statics are main-actor-isolated too, so one used as a default closure argument needs `nonisolated`.
- Wiring that a test can't build safely (a real `SessionController` could start a capture) is pinned by tests that read the Swift source.
- Resend, as of 2026-10-15: every request needs a `User-Agent`; a broadcast goes to a segment, and a contact made through the API is in none; Retrieve Contact returns no topics, but `GET /contacts/{id}/topics` does; a 409 `resource_locked` asks for a retry; an Idempotency-Key lasts 24 hours.
- Vercel: a file under a `_` folder in `api/` is never a function. `VERCEL_GIT_PREVIOUS_SHA` reaches the ignore step only when one is set. A function `vercel.json` lists must exist, so a branch whose first commit lists functions it adds later deploys only whole.
- The older glitches found on the way are under Checkpoint 5 in [../checkpoints.md](../checkpoints.md#checkpoint-5-the-email-list).
