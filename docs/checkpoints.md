# Checkpoint results

## Checkpoint 1 (2026-09-24)

Personal Mac, macOS 15.7. Items follow the plan's Task 20 list. Fayzan's summary: "Pretty much everything passed." The failures below are fixed in Session 5 (Task 21).

0. **Install and permissions: pass.** `make install`, then the three prompts. After granting and reopening, the log shows all three permissions, and every recording created the click-cleanup tap and a 1920×1246 screen stream.
1. **Gestures: pass.**
2. **Plain clicks in a hold: pass.**
3. **Labels: fail, one case; the rest pass.**
   - **A click on empty space in a Chrome window's tab strip is labeled with the whole window title.** In capture `2026-09-24 at 16.46.58`, 9 of the 10 captions read like `Clicked group "Inbox (…) - … - Gmail - Google Chrome - Fayzan"`, and frame 1's marker sits on Chrome's tab strip. Chrome exposes that spot as an `AXGroup` whose title is the window's title. This is M0's "a label that's really the window title" problem in a new place: the label rules stop at `AXWindow`, but here the title comes from a group inside the window. Fix: a container whose label equals its window's title counts as no label, so the caption reads `Clicked at (x, y)`.
4. **Output: pass.** Caption strips and markers look right.
5. **Card: pass.** Captures were ready 0.5–1.1 s after stop (the log's timings for all 8). Claude Code in VS Code's integrated terminal received 1 of 10 frames, as a plain path, as M0 found for VS Code.
6. **Filmstrip: pass.**
7. **Password field: not tested, by choice.** Flipbook is fully local; unit tests pin that a secure field's value is never read and that typed characters never leave the event tap.
8. **Design §12 questions:**
   - Cursor ⌘-click during a hold: passed with item 2 (no jump to the definition).
   - Finder drag to another volume, copy or move: not reported.
   - Clearing the AX flags at stop: Chrome and Cursor behaved normally (passed with item 3).
   - How soon Chrome exposes web content: labels passed; the first click's timing wasn't reported separately, so the flag stays as it is.
   - Claude Code in Terminal.app and iTerm: not reported. VS Code's terminal keeps only the first frame.
