# Flipbook plans: how to run them

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

1. **Session 1: M0 spikes. Done 2026-09-24.** Results and decisions are in [../spikes/findings.md](../spikes/findings.md); the spec and the M1 plan are already updated with them. The repo is pushed to the private GitHub repo `fayzan123/flipbook`.
2. **Session 2: M1 core. Done 2026-09-24.** `FlipbookCore` (the frame picker, gesture recognizer, cap fitting, and caption and `steps.md` text), its tests, and `flipbook-replay` are on `main`. What it found for later plans is under Session 2 below.
3. **Session 3: the M2–M4 plan. Done 2026-09-24.** The design is [2026-09-24-m2-m4-design.md](2026-09-24-m2-m4-design.md) and the plan is [2026-09-24-m2-m4-app.md](2026-09-24-m2-m4-app.md); `docs/spec.md` has the changes the design made.
4. **Session 4: M2 + M3, the recording loop. Next.** Tasks 1–20 of the plan, then Checkpoint 1 on the personal Mac. From then on you can use Flipbook.
5. **Session 5: M4, the rest of the app.** It starts with your Checkpoint 1 results. Tasks 21–27, then Checkpoint 2 on both Macs.
6. After Checkpoint 2: a short fix session if needed, then M5 (a week of real use; no plan).

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

## Session 5: M4, the rest of the app

Plan: [2026-09-24-m2-m4-app.md](2026-09-24-m2-m4-app.md), Tasks 21–27.

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
