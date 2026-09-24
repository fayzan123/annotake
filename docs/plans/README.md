# Flipbook plans: how to run them

Each plan runs in its own fresh Claude Code session. Paste the prompt for that session below; the plan file holds the details.

Rules for every session:
- **No superpowers skills.** The superpowers plugin loads its skills at the start of every session, but the prompts below override it. To stop it loading at all, disable it with `/plugin`.
- **Test-first wherever the code is testable:**
  1. Write the tests.
  2. Watch them fail.
  3. Implement.
  4. Watch the tests pass.
  5. Commit.
- **Build only on the personal MacBook,** using your own Claude membership.

## Order

1. **Session 1: M0 spikes. Done 2026-09-24.** Results and decisions are in [../spikes/findings.md](../spikes/findings.md); the spec and the M1 plan are already updated with them. The repo is pushed to the private GitHub repo `fayzan123/flipbook`.
2. **Session 2: M1 core. Next.** It runs without you, directly in `~/Documents/GitHub/flipbook` on `main` (no worktree needed now that Session 1 is finished).
3. **Session 3: write the M2–M4 plan** (capture, input, export, the app UI) from M0's findings. It only writes docs, so it can run during Session 2. If it does, give it a worktree so the two sessions' commits don't mix:

   ```
   cd ~/Documents/GitHub/flipbook && git worktree add ../flipbook-plans -b m2-m4-plan
   ```

   When it's done: `cd ~/Documents/GitHub/flipbook && git merge m2-m4-plan && git worktree remove ../flipbook-plans`.

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

## Session 2: M1 core

Plan: [2026-09-23-m1-core.md](2026-09-23-m1-core.md). Every task is test-first. Nothing is needed from you until the end.

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

At the end, you can run `swift run flipbook-replay Tests/FlipbookCoreTests/Fixtures/synthetic-click-flow` to watch it pick frames from a test recording.

Prompt:

```
In ~/Documents/GitHub/flipbook, execute docs/plans/2026-09-23-m1-core.md task by task, test-first: write the listed tests, run them with `make test FILTER=<suite>` and watch them fail, implement, watch them pass, commit after each task. Never use plain `swift test`; it can't find Swift Testing without Xcode. M0 is done: read docs/spec.md, the Decisions section of docs/spikes/findings.md, and the plan before starting. Leave spikes/ and the M0 scripts alone. Don't use any superpowers skills. If a test expectation in the plan looks wrong, stop and tell me instead of changing it. When all tasks pass, push main to origin.
```

## Session 3: M2–M4 plan

Prompt (use `~/Documents/GitHub/flipbook-plans` if it runs during Session 2):

```
In ~/Documents/GitHub/flipbook, M0 is done. Read docs/spikes/findings.md, docs/spec.md, and both plans in docs/plans/, then write the M2–M4 plan (capture, input, export, app UI) to docs/plans/. No superpowers skills; test-first wherever the code is testable.
```
