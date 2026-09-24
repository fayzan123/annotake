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

1. **Session 1: M0 spikes.** You're at the keyboard for every task. The session starts with installing Command Line Tools 26.3.
2. **Session 2: M1 core.** It runs without you. Start it after M0 Task 1 is committed, because M1 needs to know which test framework works.
   - **If Session 1 is still running,** give Session 2 its own worktree. Otherwise one session's commits would pick up the other's half-finished files:

     ```
     cd ~/Documents/GitHub/flipbook && git worktree add ../flipbook-core -b m1-core
     ```

   - **When Session 2 is done,** merge its branch and remove the worktree:

     ```
     cd ~/Documents/GitHub/flipbook && git merge m1-core && git worktree remove ../flipbook-core
     ```

3. **Session 3: write the M2–M4 plan** (capture, input, export, the app UI) from M0's findings.

## Session 1: M0 spikes

Plan: [2026-09-23-m0-spikes.md](2026-09-23-m0-spikes.md)

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

1. Package scaffold
2. Tile grid
3. Frame signatures, plus the test scene builder
4. Data model, settings numbers, caption text
5. Change detection: ignoring the cursor, a blinking caret, and spinners
6. Trimming to the 20-frame limit
7. The frame picker: triggers, settling, which frames to keep, stopping
8. Removing frames from the filmstrip
9. `steps.md`
10. Right ⌘ gesture logic
11. Raw sessions, the replayer, golden tests
12. The `flipbook-replay` command and final checks

At the end, you can run `swift run flipbook-replay Tests/FlipbookCoreTests/Fixtures/synthetic-click-flow` to watch it pick frames from a test recording.

Prompt (use `~/Documents/GitHub/flipbook` if you're not using the worktree):

```
In ~/Documents/GitHub/flipbook-core, execute docs/plans/2026-09-23-m1-core.md task by task, test-first: write the listed tests, run them and watch them fail, implement, watch them pass, commit. Read docs/spec.md and the plan first. Don't use any superpowers skills. If a test expectation in the plan looks wrong, stop and tell me instead of changing it.
```

## Session 3: M2–M4 plan (after M0 is done)

Prompt:

```
In ~/Documents/GitHub/flipbook, M0 is done. Read docs/spikes/findings.md, docs/spec.md, and both plans in docs/plans/, then write the M2–M4 plan (capture, input, export, app UI) to docs/plans/. No superpowers skills; test-first wherever the code is testable.
```
