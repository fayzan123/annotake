# Annotake Stage 1 Implementation Plan

> **How to execute:** one session (Session 8), run long and unattended, then one checkpoint. Work through the tasks in order. For each task:
> 1. Write the listed tests.
> 2. Run them with `make test FILTER=<suite>` and watch them fail.
> 3. Implement until they pass.
> 4. Run the task's **Verify** step: always `make test`, plus whatever else the task lists.
> 5. Commit.
>
> Tasks marked **Glue** wrap macOS APIs, scripts, or tools that unit tests can't reach. They're verified by building, by the self-test, by UI snapshots, by the log, and by the dry-run release. They still get unit tests for any pure logic they contain.
>
> **No stops until the end.** Fayzan isn't there, so the session never waits for an answer:
> - **A test expectation in this plan looks wrong:** decide what's right, implement it with a test that pins it, and record the decision and why under "Decisions" in the Session 8 notes (Task 15). Don't stop to ask.
> - **A step can't finish without someone present** (a macOS or keychain prompt, or a command that hangs): give it at most 10 minutes, then end it and skip only that step. Record it under "Skipped" with what it needs, and carry on with everything that doesn't depend on it.
> - **The network fails** (Sparkle's download, pip, GitHub): retry up to three times, a few minutes apart. Meanwhile carry on with tasks that don't need it, and come back to it.
> - **The self-test can't capture**, because the Mac went to sleep or locked: carry on, and run it again in Task 15.
>
> The session verifies everything else itself. The checkpoint at the end is the only stop, and it lists every decision and skipped step.
>
> **Never launch the full app during the session**, because it requests permissions at launch and now also moves data on first launch. Use `make selftest`, `make selftest-intel`, `make ui-snapshots`, and `make release DRY_RUN=1` instead. None of them launches the normal app.
>
> Steps use checkbox (`- [ ]`) syntax for tracking. Don't use any superpowers skills to execute this plan.

**Goal:** Turn the app into Annotake and make it shippable to people who aren't Fayzan:
- the rename, internals included, with migration from Flipbook;
- Developer ID signing and notarization, a disk image, an icon, version numbers, and Sparkle updates;
- one app for Intel and Apple silicon;
- a Wispr-style first run;
- Send Feedback;
- `make release`.

**Architecture:**
- The libraries keep their roles and take the Annotake names: `AnnotakeCore`, `AnnotakeCapture`, `AnnotakeInput`, `AnnotakeExport`, and `AnnotakeApp`.
- Sparkle is linked only into the `Annotake` executable. `AnnotakeApp` defines an `Updater` protocol and gets an updater injected, so the libraries and their tests keep no network code and don't link Sparkle.
- A new Foundation-only `AnnotakeRelease` library holds the appcast writer, which is unit-tested. The `annotake-appcast` command line tool calls it.
- Shell scripts do the bundling, signing, the disk image, notarization, and publishing. `make release DRY_RUN=1` runs the whole pipeline locally, so the session can check it without credentials.

**Tech Stack:**
- Swift 6.2 (Command Line Tools 26.3), SwiftPM, Swift Testing, AppKit, SwiftUI, ScreenCaptureKit.
- Sparkle 2.10.0.
- `codesign`, `notarytool`, `stapler`, `lipo`, `iconutil`, `hdiutil`, `tiffutil`.
- dmgbuild 1.6.5 in a Python 3.9 virtual environment.
- The `gh` CLI.

**Spec:** read these before starting:
- `docs/plans/2026-09-30-distribution-design.md`, the design ("design §n"). This plan builds its §5.2.
- `docs/spec.md`, what the app does.
- `docs/plans/README.md`, the session rules.
- For history: `docs/plans/2026-09-24-m2-m4-design.md` and `docs/checkpoints.md`.

**Changes from the design:** small, and decided while planning. The design doc gets them in Task 3.
1. **Old markers stay readable.** `CaptureStore` reads a capture's old `.flipbook` marker when it has no `.annotake` one. Migration still renames markers where it can reach them. Captures on a drive that's unplugged at first launch keep working when the drive comes back.
2. **Existing Flipbook users skip the welcome and the practice run.** They go straight to the permissions, which macOS asks for again because of the new signature and bundle ID.
3. **The old app is retired.** Annotake's first launch quits an installed Flipbook and moves it to the Trash. Otherwise, after a disk-image install, both apps would start a recording on Right ⌘.
4. **Permissions come in this order:** Accessibility first, because it applies without a relaunch, then Input Monitoring, then Screen Recording, then a single Quit & Reopen.
5. **The release repo's rename and the first real release happen at the checkpoint,** because they need Fayzan's Developer ID and notarization credentials.

**Global Constraints** (every task inherits these):
- **Names:**
  - The app is `Annotake`, with bundle id `com.fayzanmalik.annotake` and `LSUIElement`.
  - Queue and thread labels start with `com.fayzanmalik.annotake.`.
  - The local signing identity is `Annotake Local Signing`, in `.signing/annotake-signing.keychain-db`, with password `annotake-local`.
  - The Developer ID identity matches `Developer ID Application: Fayzan Malik (<team id>)` and lives in the same keychain.
- **"Flipbook" may appear only in:**
  - `Sources/AnnotakeApp/LegacyFlipbook.swift`, which also holds the two user-facing lines that name the old app, `Tests/AnnotakeAppTests/MigrationTests.swift`, `CaptureStore.legacyMarkerName`, and `CaptureStoreTests`' legacy-marker test;
  - `scripts/install.sh`, which removes the old app;
  - docs, where they describe the past.

  `grep -rni flipbook Sources Tests scripts Makefile Package.swift .vscode` must list nothing else.
- **Network:** the only network code is Sparkle, in the `Annotake` executable target. `AnnotakeCore` imports Foundation only. No library has network code, and there's no AI.
- **Privacy:**
  - Typed characters never leave the event-tap callback.
  - A secure text field's value is never read.
  - `~/Library/Logs/Annotake.log` never contains labels, window titles, or keys.
  - Send Feedback only prepares a draft; the user sends it.
- **Secrets never enter the repo.** These stay in `.signing/` (gitignored) or in the keychain:
  - the Developer ID private key and certificate;
  - the notarization credentials (keychain profile `annotake-notary`);
  - the Sparkle private key (`.signing/sparkle-private-key`, plus its keychain copy).

  `Resources/sparkle-public-key.txt` is public and committed.
- **Versions:**
  - `VERSION` holds the marketing version, `0.2.0`.
  - The build number is `git rev-list --count HEAD`.
  - They become `CFBundleShortVersionString` and `CFBundleVersion`.
- **Architectures:**
  - Two release builds, `--triple arm64-apple-macosx15.0` and `--triple x86_64-apple-macosx15.0`, merged with `lipo`.
  - Two `--arch` flags need Xcode's XCBuild, which the Command Line Tools don't have (checked 2026-09-30).
- **Sparkle settings:**
  - `SUFeedURL`: `https://raw.githubusercontent.com/fayzan123/annotake-releases/main/appcast.xml`;
  - `SUEnableAutomaticChecks`: true;
  - `SUScheduledCheckInterval`: 86400;
  - `SUEnableSystemProfiling`: false;
  - `SUPublicEDKey`: from `Resources/sparkle-public-key.txt`.
- **Signing:**
  - `scripts/bundle-app.sh` always signs, with the hardened runtime, nested code first and no `--deep`.
  - It uses the Developer ID identity when the keychain has one, and the local identity otherwise.
  - `RELEASE=1` requires the Developer ID identity and adds `--timestamp`. Every other build uses `--timestamp=none`.
  - It strips extended attributes before signing and retries up to 3 times (iCloud Drive re-tags bundles).
- **Feedback address:** `feedback@annotake.app`, defined once as `Feedback.address`.
- **Tests:**
  - `make test` runs everything; `make test FILTER=<regex>` runs matching suites.
  - Never run plain `swift test`: without Xcode it can't find Swift Testing.
  - New test targets need the Makefile's flags, including `-disable-cross-import-overlays`.
  - App tests use `@testable import AnnotakeApp`.
  - Test targets can't share support files.
- **Numbers:** define each as a named constant where it's used.
  - **Onboarding:** the window is 560 pt wide; permissions are polled every 1 s; the demo advances every 1.6 s.
  - **Feedback:** the last 400 log lines; crash reports at most 7 days old and at most 200,000 bytes; a mailto body of at most 1,500 characters.
  - **Appcast:** keep at most 10 items; minimum system version `15.0`.
  - **Disk image:** a 600 × 400 pt window; icons 128 pt at (150, 190) for the app and (450, 190) for Applications.
  - **Icon:** a 1024 px canvas and an 824 px body with a corner radius of 186 px.
- **Commits:** commit after every task. The message ends with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- **Build only on the personal MacBook.**

**Review Focus.** Five things a person installing Annotake will hit that no feature test naturally covers. Each one's pinning test is listed in its owning task:
1. **The default mail app isn't Apple Mail** (Gmail in a browser, or no account set up). Send Feedback must still produce something sendable: a mailto draft with the facts, and the full report shown in Finder. Task 9: `fallsBackWithoutMailApp`.
2. **Flipbook is still installed when Annotake is installed from the disk image.** Only Annotake may answer Right ⌘: the installed Flipbook is quit and moved to the Trash at first launch, while development builds elsewhere are left alone. Task 3: `retiresOnlyInstalledCopies`.
3. **Permissions denied, granted in a different order, or granted from System Settings directly.** The first run never gets stuck and never asks for something already granted. Task 10: `continueWithoutConfirmation`, `grantedPermissionsAreSkipped`, `grantWhileShowingAdvances`.
4. **Opened straight from the disk image or Downloads,** so it runs from a translocated, quarantined copy. The move offer must appear, and the copy in Applications runs afterwards. Task 12: `detectsTranslocation`, `offersUserApplicationsOtherwise`.
5. **Flipbook captures that migration can't reach,** for example on a drive unplugged at first launch. They still show in Recent Captures and still get cleaned up when the drive comes back. Task 3: `legacyMarkerStillCounts`.

## File map

| Path | Responsibility |
|---|---|
| `Package.swift` | Package `Annotake`; targets renamed (Task 1); Sparkle in the executable (Task 8); `AnnotakeRelease`, `annotake-appcast`, `AnnotakeReleaseTests` (Task 13) |
| `Makefile` | Universal `app`, `selftest-intel`, `icon`, `devid-csr`, `devid-import`, `sparkle-keys`, `release`; the clean `zip` |
| `VERSION` | The marketing version (Task 4) |
| `.gitattributes` | Adds `*.icns binary` and `*.tiff binary` |
| `.vscode/launch.json` | The Annotake targets, using `${workspaceFolder}` (Task 1) |
| `Resources/AppIcon.icns` | The app and volume icon (Task 6) |
| `Resources/dmg-background.tiff` | The disk image's background, at 1× and 2× (Task 14) |
| `Resources/sparkle-public-key.txt` | Sparkle's public EdDSA key (Task 8) |
| `scripts/bundle-app.sh` | Bundle, Info.plist, frameworks, icon, signing (Tasks 1, 4, 6, 7, 8) |
| `scripts/make-cert.sh` | The local signing identity, under its new name (Task 1) |
| `scripts/devid.sh` | `csr` and `import` for the Developer ID certificate (Task 7) |
| `scripts/sparkle-keys.sh` | Generates the update-signing key, writes the public half, exports the private half to `.signing/` (Task 8) |
| `scripts/make-icon.swift` | Draws the icon set (Task 6) |
| `scripts/make-dmg-background.swift` | Draws the disk image background (Task 14) |
| `scripts/dmg-settings.py` | dmgbuild's layout (Task 14) |
| `scripts/release.sh` | Build, notarize, staple, disk image, Sparkle signature, publish; `DRY_RUN=1` (Task 14) |
| `scripts/install.sh` | The one-line installer, now for Annotake; the source of truth that releases publish (Task 14) |
| `scripts/releases-README.md` | The releases repo's README, published with each release (Task 14) |
| `Sources/Annotake{Core,Capture,Input,Export,App}/` | Renamed from `Flipbook…` (Task 1) |
| `Sources/Annotake/main.swift`, `Sources/Annotake/SparkleUpdater.swift` | The executable; the Sparkle-backed `Updater` (Task 8) |
| `Sources/annotake-replay/main.swift` | Renamed from `flipbook-replay` (Task 1) |
| `Sources/AnnotakeExport/CaptureStore.swift` | `.annotake` marker; reads the legacy marker (Tasks 1, 3) |
| `Sources/AnnotakeApp/LegacyFlipbook.swift` | `LegacyFlipbook`, `Migration`, `LegacyApp` (Task 3) |
| `Sources/AnnotakeApp/AppVersion.swift` | `AppVersion` (Task 4) |
| `Sources/AnnotakeApp/Updater.swift` | The `Updater` protocol (Task 8) |
| `Sources/AnnotakeApp/Feedback.swift` | `Feedback` and the menu action (Task 9) |
| `Sources/AnnotakeApp/OnboardingModel.swift` | `OnboardingModel` (Task 10) |
| `Sources/AnnotakeApp/Onboarding.swift` | Views, view model, controller, `OnboardingCopy`, `OnboardingDrop` (Task 11) |
| `Sources/AnnotakeApp/LoginItem.swift` | `LoginItemPolicy` and `LoginItem`, moved out of `FirstLaunch.swift` (Task 10) |
| `Sources/AnnotakeApp/MoveToApplications.swift` | The decision and the prompt (Task 12) |
| `Sources/AnnotakeApp/FirstLaunch.swift` | Deleted in Task 11 |
| `Sources/AnnotakeApp/AppMain.swift` | Migration, the move prompt, onboarding, the updater (Tasks 3, 8, 11, 12) |
| `Sources/AnnotakeApp/StatusMenu.swift` | Send Feedback… and Check for Updates… (Tasks 8, 9) |
| `Sources/AnnotakeApp/Permissions.swift` | Requests take `OnboardingModel.Permission` (Task 10) |
| `Sources/AnnotakeApp/UISnapshots.swift` | The onboarding snapshots replace the checklist's (Task 11) |
| `Sources/AnnotakeRelease/Appcast.swift`, `Sources/annotake-appcast/main.swift` | The appcast writer and its command line tool (Task 13) |
| `Tests/Annotake…Tests/` | Renamed (Task 1); new suites: `MigrationTests`, `AppVersionTests`, `FeedbackTests`, `OnboardingModelTests`, `OnboardingCopyTests`, `MoveToApplicationsTests`, `AppcastTests` |
| `docs/…` | The rename (Task 2); each task updates the spec sections it changes |

---

# Session 8: the Stage 1 build

### Task 1: The rename to Annotake

Design §3.1. Mechanical, but it touches every target. After it, the tree builds and tests as Annotake.

**Files:**
- Move (`git mv`):
  - `Sources/Flipbook{Core,Capture,Input,Export,App}` → `Sources/Annotake{…}`;
  - `Sources/Flipbook` → `Sources/Annotake`;
  - `Sources/flipbook-replay` → `Sources/annotake-replay`;
  - `Tests/Flipbook{Core,Capture,Input,Export,App}Tests` → `Tests/Annotake{…}Tests`.
- Modify: `Package.swift`, `Makefile`, `scripts/bundle-app.sh`, `scripts/make-cert.sh`, `.vscode/launch.json`, and every source and test file the grep in the constraints lists.

**What changes:**
- **Package:** name `Annotake`. Products: `AnnotakeCore` (library), `Annotake` and `annotake-replay` (executables). Every target and test target is renamed, with the same dependencies.
- **Imports:** every `import Flipbook…` and `@testable import Flipbook…`.
- **Strings:**
  - `SessionController.bundleID` → `com.fayzanmalik.annotake`;
  - the queue and thread labels;
  - `LogFile.shared` → `Library/Logs/Annotake.log`;
  - `Settings.defaultSaveLocation` → `Pictures/Annotake`;
  - `CaptureStore.markerName` → `.annotake`, and `tempFolderName` → `.annotake-tmp`;
  - the `StepsDocument` header → `# Annotake capture — <name>`;
  - `SelfTestLayout.title` → `Annotake Self-Test`, and `savedTitle` → `Annotake Self-Test — Saved`, so `SelfTest.expectedContexts` become `Annotake — Annotake Self-Test` (four) and `Annotake — Annotake Self-Test — Saved` (two);
  - the usage strings `Annotake --selftest <directory>` and `annotake-replay <session-dir> [--cap N]`;
  - every UI string: "Annotake Settings", "Welcome to Annotake", "Quit Annotake", the menu icon's accessibility description, and the Settings notes;
  - the UI snapshot suite `com.fayzanmalik.annotake.ui-snapshots`, and the sample window `main.swift — annotake`;
  - the environment variables `ANNOTAKE_LOCAL_FIXTURES`, `ANNOTAKE_REGENERATE_FIXTURES`, `ANNOTAKE_WRITE_SAMPLES`;
  - temp-folder prefixes in tests (`annotake-…`);
  - test data `main.swift — annotake` in `Scenes.swift`, with `ReplayTests` expecting `Switched to Code — main.swift — annotake`.
- **Doc comments** that name the app or a module, for example `AppEntry`'s note about not being named `AnnotakeApp`.
- **Makefile:**
  - `KC := $(CURDIR)/.signing/annotake-signing.keychain-db`;
  - `--product Annotake`;
  - `build/Annotake.app` everywhere;
  - `install` removes `/Applications/Annotake.app` and `~/Applications/Annotake.app` before copying;
  - `replay` runs `annotake-replay`.
- **Scripts:** `make-cert.sh` uses `NAME="Annotake Local Signing"`, `PASS=annotake-local`, and `KC=$PWD/.signing/annotake-signing.keychain-db`. `bundle-app.sh` unlocks and signs with those.
- **`.vscode/launch.json`:** targets `Annotake` and `annotake-replay`, with `"cwd": "${workspaceFolder}"`. No folder name, so it survives the folder rename at the checkpoint.

**The fixtures don't change.** `Tests/AnnotakeCoreTests/Fixtures/synthetic-click-flow` contains no app name. `goldenFixturesMatch` must pass unchanged. If it doesn't, the rename changed behavior somewhere: fix the code, never the fixtures.

- [ ] **Step 1: Clean and move.** Run `make clean`, then the `git mv` commands.
- [ ] **Step 2: Rename in code.** `Package.swift`, imports, strings, scripts, Makefile, `.vscode`. Update the tests that assert the old strings:
  - `StepsDocumentTests`: the header;
  - `SettingsTests`: `<home>/Pictures/Annotake`;
  - `CaptureExporterTests`: `.annotake`;
  - `CaptureStoreTests`: `.annotake-tmp`;
  - `SelfTestExpectationTests`;
  - `WindowListFilterTests` and `ContentSnapshotTests`: own bundle id `com.fayzanmalik.annotake`;
  - `ChecklistModelTests`' login-item paths: `/Applications/Annotake.app`, `<home>/Applications/Annotake.app`, and `<home>/Documents/GitHub/annotake/build/Annotake.app` → false;
  - `LogTests`: `Annotake.log`, `Annotake.log.1`.
- [ ] **Step 3: The new local identity.** Run `make cert`, which creates `Annotake Local Signing` in `.signing/annotake-signing.keychain-db`. Then remove the old keychain from the search list and disk with `security delete-keychain .signing/flipbook-signing.keychain-db`.
- [ ] **Step 4: Verify.**
  - `make test` passes, including `goldenFixturesMatch` unchanged.
  - `make selftest` prints `PASSED`, and its `line 2:` shows `Annotake — Annotake Self-Test`.
  - `make ui-snapshots`: look at `settings-general.png` and `checklist-fresh.png`.
  - `codesign -dvv build/Annotake.app` shows `Authority=Annotake Local Signing` and `Identifier=com.fayzanmalik.annotake`.
  - The grep from the constraints prints nothing.
- [ ] **Step 5: Commit.** `rename: Flipbook becomes Annotake`

---

### Task 2: The rename in the docs

Design §3.1. No code.

**Files:** `docs/spec.md`, `docs/v2-backlog.md`, `docs/research-notes.md`, `docs/plans/README.md`, `docs/checkpoints.md`, `docs/spikes/findings.md`, and the dated plans `docs/plans/2026-09-23-*.md`, `2026-09-24-*.md`.

**Living docs: the spec, backlog, and research notes.** The app's name becomes Annotake everywhere it means the app:
- the title;
- paths: `~/Pictures/Annotake/`, `.annotake`, `.annotake-tmp`, `Annotake.log`;
- target names in spec §6, and `annotake-replay`;
- the bundle id;
- `Annotake Local Signing`.

The spec's "Name" line becomes: `**Name:** Annotake, called Flipbook until 2026-09-30 ([distribution design §3](…))`.

Leave alone:
- facts about the old name, such as the naming checks in the research notes;
- the early-install command in spec §9. Task 14 changes it.

**The session guide (`docs/plans/README.md`):**
- The rules and the "Order" list name the app Annotake.
- The historical session sections stay as written.
- Add one line under the title: "Sessions 1–7 were written when the app was called Flipbook."

**Dated docs** (the M0, M1, and M2–M4 plans and designs, `checkpoints.md`, `spikes/findings.md`): add one line under each title, and leave the rest untouched:

`> Written when the app was called Flipbook; it's Annotake since 2026-09-30 ([distribution design §3](…)).`

Use the relative path that works from each file.

- [ ] **Step 1: Edit.**
- [ ] **Step 2: Verify.** `grep -n -i flipbook docs/spec.md docs/v2-backlog.md` shows only:
  - the Name line;
  - the §9 early-install command;
  - spec §13's rename row;
  - the backlog's dated history.

  Each one describes the old name or the early install. `make test` still passes, though nothing in it changed.
- [ ] **Step 3: Commit.** `docs: the app is Annotake`

---

### Task 3: Migrating from Flipbook (App, Export)

Design §3.1, plus the plan's changes 1–3. **Pure planner, with glue.**

**Files:**
- Create: `Sources/AnnotakeApp/LegacyFlipbook.swift`, `Tests/AnnotakeAppTests/MigrationTests.swift`
- Modify:
  - `Sources/AnnotakeExport/CaptureStore.swift` (the legacy marker), `Tests/AnnotakeExportTests/CaptureStoreTests.swift`;
  - `Sources/AnnotakeApp/AppMain.swift`;
  - `docs/spec.md`: §4.1, and a new §3.8 "Coming from Flipbook";
  - `docs/plans/2026-09-30-distribution-design.md` §3.1: add the plan's changes 1–3.

**Interfaces (Produces):**

```swift
// AnnotakeExport
extension CaptureStore {
    public static let legacyMarkerName = ".flipbook"   // read-only: captures made by Flipbook
}
// readMarker(in:) reads `.annotake`; without one, the legacy marker. commit() writes only `.annotake`.

// AnnotakeApp
/// The old app's names, used only to bring its data over (design §3.1).
enum LegacyFlipbook {
    static let bundleID = "com.fayzanmalik.flipbook"
    static let folderName = "Flipbook"                 // under ~/Pictures
    static let tempFolderName = ".flipbook-tmp"
    static let settingsKey = "settings.v1"             // the only key that's copied
    /// The first run's two lines about the old app (Task 11).
    static let replacedNote = "Flipbook was moved to the Trash. Annotake replaces it."
    static let askAgainNote = "Annotake replaces Flipbook, so macOS asks for these again."
}

struct FolderMove: Equatable { var from: URL; var to: URL }

struct MigrationPlan: Equatable {
    var settings: Settings?        // written to the new domain; nil = nothing to import
    var move: FolderMove?          // ~/Pictures/Flipbook → ~/Pictures/Annotake
    var markerRoot: URL?           // where legacy markers get renamed: the effective save location
    var existingUser: Bool         // Flipbook was used on this Mac
}

enum Migration {
    static let doneKey = "migration.flipbook.v1"
    /// Pure. Nil when it has already run.
    static func plan(oldDomain: [String: Any]?, alreadyDone: Bool, home: URL,
                     exists: (URL) -> Bool) -> MigrationPlan?
    /// Glue: reads `UserDefaults.standard.persistentDomain(forName: LegacyFlipbook.bundleID)`, runs the plan,
    /// sets `doneKey`, and logs counts only. Returns the plan it ran.
    @discardableResult
    static func run(defaults: UserDefaults, home: URL) -> MigrationPlan?
    /// Renames `.flipbook` to `.annotake` (same contents) in each direct subfolder that has no `.annotake`
    /// yet, and deletes `<root>/.flipbook-tmp`. Returns how many it renamed.
    static func renameMarkers(in root: URL) -> Int
}

enum LegacyApp {
    /// Pure: an installed copy of the old app (inside /Applications or ~/Applications) that isn't this app.
    static func shouldRetire(appURL: URL, ownBundleURL: URL, home: URL) -> Bool
    /// Glue: quits a running Flipbook (terminate, then forceTerminate after 2 s), then moves each copy that
    /// `shouldRetire` accepts to the Trash. True if it retired one.
    @MainActor static func retire() -> Bool
}
```

**`plan` rules** (`old` = `<home>/Pictures/Flipbook`, `new` = `<home>/Pictures/Annotake`):
1. `alreadyDone` → nil.
2. **Settings.** `oldDomain[settingsKey]` as `Data`, decoded with `Settings`' tolerant decoder and clamped, becomes `settings`. Unreadable data counts as none.
3. **The old save location** is `settings?.saveLocation ?? old`. It was the default when it equals `old` (standardized).
4. **Default location:**
   - if `exists(old) && !exists(new)` → `move = old → new`, and `markerRoot = new`;
   - if both exist → no move, and `markerRoot = nil`. The old folder stays as it is, and it's logged;
   - either way, `settings?.saveLocation = new`.
5. **Custom location:** no move, `markerRoot = that location` when it exists, and the location is kept.
6. **`existingUser`** = settings were found, or `exists(old)`, or `oldDomain` has any key.

**`run` order:**
1. move the folder (`FileManager.moveItem`);
2. write the settings (`SettingsStore(defaults:).settings = …`);
3. `renameMarkers(in: markerRoot)`;
4. set `doneKey`;
5. log, for example `migration: settings imported, folder moved, 12 marker(s) renamed`.

A failed move is logged, and the old folder is left where it is. The legacy-marker fallback keeps those captures readable anyway.

**`AppDelegate` changes:** before it reads settings:
- `let migration = Migration.run(defaults: .standard, home: FileManager.default.homeDirectoryForCurrentUser)`
- `let retiredFlipbook = LegacyApp.retire()`

It keeps both for onboarding (Task 11). Neither runs in `--selftest` or `--render-ui`.

- [ ] **Step 1: Write the tests.**

| Suite / test | Assertion |
|---|---|
| `CaptureStoreTests.legacyMarkerStillCounts` | A folder with only `.flipbook` (a date in ISO 8601) is in `captures()` with that date. A folder with both uses `.annotake`'s date. `commit` writes `.annotake` and never `.flipbook` |
| `MigrationTests.importsSettingsButNotFirstRunState` | The old domain has `settings.v1` (trigger `.rightOption`, `sounds` false), `firstLaunch.v1`, and `loginItem.initialized`. The plan's settings have `.rightOption` and sounds off. After `run` into a fresh suite, `firstLaunch.v1` and `loginItem.initialized` are absent |
| `MigrationTests.defaultSaveLocationMovesWithTheFolder` | Temp home with `Pictures/Flipbook/2026-09-24 at 10.00.00/.flipbook`, and settings at the default. After `run`: the capture is under `Pictures/Annotake` with `.annotake` and the same date; `Pictures/Flipbook` is gone; `saveLocation` is `Pictures/Annotake` |
| `MigrationTests.customSaveLocationStays` | `saveLocation` is `<temp>/Elsewhere`, which holds a capture. No move, the location is unchanged, and the capture's marker is renamed |
| `MigrationTests.existingAnnotakeFolderBlocksTheMove` | Both `Pictures/Flipbook` and `Pictures/Annotake` exist. `move` is nil, `markerRoot` is nil, and the old folder is untouched after `run` |
| `MigrationTests.runsOnce` | A second `run` on the same defaults returns nil and changes nothing |
| `MigrationTests.freshMacIsNotAnExistingUser` | A nil domain and no folder: `existingUser` is false and `move` is nil. After `run`, `doneKey` is set |
| `MigrationTests.retiresOnlyInstalledCopies` | `/Applications/Flipbook.app` → true; `<home>/Applications/Flipbook.app` → true; `<home>/Documents/GitHub/annotake/build/Flipbook.app` → false; the app's own bundle URL → false |

- [ ] **Step 2:** `make test FILTER='MigrationTests|CaptureStoreTests'`. It fails.
- [ ] **Step 3: Implement.** Update spec §4.1 (folder layout and the legacy marker) and add spec §3.8 with the rules above in plain words. Update design §3.1.
- [ ] **Step 4: Verify.** `make test`, `make selftest`.
- [ ] **Step 5: Commit.** `app: bring settings and captures over from Flipbook`

---

### Task 4: Version numbers (App)

Design §5.2, item 5. **Glue** with a pure part.

**Files:**
- Create: `VERSION` (contents `0.2.0` and a newline), `Sources/AnnotakeApp/AppVersion.swift`, `Tests/AnnotakeAppTests/AppVersionTests.swift`
- Modify: `Makefile`, `scripts/bundle-app.sh`, `AppMain.swift` (the launch log line)

**Interfaces (Produces):**

```swift
struct AppVersion: Equatable, CustomStringConvertible {
    var short: String          // CFBundleShortVersionString, e.g. "0.2.0"
    var build: String          // CFBundleVersion, e.g. "74"
    var description: String    // "0.2.0 (74)"
    static func from(infoDictionary: [String: Any]?) -> AppVersion   // missing keys → "0.0.0" and "0"
    static var current: AppVersion { get }                            // from Bundle.main
}
```

- **Makefile:** `VERSION := $(shell cat VERSION)`, `BUILD := $(shell git rev-list --count HEAD)`, and `RELEASE ?= 0`. The bundler gets them explicitly as environment variables on its own line, for example `RELEASE=$(RELEASE) VERSION=$(VERSION) BUILD=$(BUILD) FRAMEWORKS_DIR=… scripts/bundle-app.sh …`. `FRAMEWORKS_DIR` arrives in Task 8.
- **`bundle-app.sh`:** writes them into `CFBundleShortVersionString` and `CFBundleVersion`. Without them it fails with a usage message.
- **The launch log line** becomes `launched Annotake 0.2.0 (74)`.

- [ ] **Step 1: Write the tests.** `readsBothKeys` (`["CFBundleShortVersionString": "0.2.0", "CFBundleVersion": "74"]` → `"0.2.0 (74)"`), `missingKeysFallBack` (nil → `"0.0.0 (0)"`).
- [ ] **Step 2:** `make test FILTER=AppVersionTests`. It fails.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Verify.** `make test`, `make app`, then `plutil -extract CFBundleVersion raw build/Annotake.app/Contents/Info.plist` equals `git rev-list --count HEAD`, and `CFBundleShortVersionString` is `0.2.0`.
- [ ] **Step 5: Commit.** `build: version numbers from VERSION and the commit count`

---

### Task 5: Intel and Apple silicon in one app

Design §5.2, item 7. **Glue.**

**Files:** `Makefile`.

- **`app`:**
  1. Build `--product Annotake` twice, with `--triple arm64-apple-macosx15.0` and `--triple x86_64-apple-macosx15.0`.
  2. Merge with `lipo -create -output .build/universal/Annotake <arm bin>/Annotake <x86 bin>/Annotake`, where each bin path comes from `swift build -c release --triple … --show-bin-path`.
  3. Bundle that.
- **`selftest-intel`:** runs `open --arch x86_64 -W -n build/Annotake.app --args --selftest "$(CURDIR)/build/selftest-intel"` (Rosetta is installed on this Mac), then prints the report and `grep -q '^PASSED'`.
- **`make test`** stays a native debug build.

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Verify.**
  - `make app`, then `lipo -archs build/Annotake.app/Contents/MacOS/Annotake` prints `x86_64 arm64`.
  - `make selftest` passes.
  - `make selftest-intel` passes. Look at one of its frames.
  - `make test`.
- [ ] **Step 3: Commit.** `build: one app for Intel and Apple silicon`

---

### Task 6: The app icon

Design §5.2, item 4. **Glue.** Fayzan judges it at the checkpoint.

**Files:**
- Create: `scripts/make-icon.swift`, `Resources/AppIcon.icns`
- Modify: `Makefile` (`icon`), `scripts/bundle-app.sh`, `.gitattributes`

**The drawing.** `scripts/make-icon.swift <out.iconset>`, run with `swift`. It uses CoreGraphics at 1024 × 1024, then scales down for each iconset size: 16, 32, 128, 256, and 512, each with its @2x.
- **Body:** an 824 × 824 rounded rectangle at (100, 100) with a corner radius of 186. The fill is a vertical gradient from `#2C2C2E` at the top to `#1C1C1E` at the bottom, which is the caption strip's color.
- **Three frames, fanned:** the back two are `#C7C7CC` and `#E5E5EA`, rotated −8° and +6°. The front one is white and upright, 560 × 430 with corner radius 28, centered 30 px above the middle. Each has a soft shadow: black at 25%, blur 24, 10 px down.
- **The front frame's content:**
  - a toolbar band, `#E5E5EA`;
  - two content bars, `#D1D1D6`;
  - a blue button, `#0A84FF`;
  - a caption strip at its bottom, 17% of its height in `#1C1C1E`, with a white bar 45% wide.
- **The click marker,** the app's signature: a ring of radius 44 on the blue button, drawn as a 14 px `#FF3B30` stroke over a 26 px white halo.
- **At 32 px,** the white frame and the red ring must still be visible. Check the `icon_16x16@2x.png`.

**Wiring:**
- `make icon` runs the script into `build/AppIcon.iconset`, then `iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns`.
- The bundler copies `Resources/AppIcon.icns` into `Contents/Resources/` and sets `CFBundleIconFile` to `AppIcon`.
- Commit the `.icns` (binary) and the script.

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Verify.**
  - `make icon`, then look at `build/AppIcon.iconset/icon_512x512@2x.png` and `icon_16x16@2x.png`.
  - `make app`, then `plutil -extract CFBundleIconFile raw build/Annotake.app/Contents/Info.plist` is `AppIcon`.
  - `make ui-snapshots`.
  - `make test`.
- [ ] **Step 3: Commit.** `app: the Annotake icon`

---

### Task 7: Developer ID signing

Design §5.2, item 2 (signing; notarization is Task 14). **Glue.** The Developer ID doesn't exist yet, so this task prepares for it and keeps the local fallback.

**Files:**
- Create: `scripts/devid.sh`
- Modify: `scripts/bundle-app.sh`, `Makefile` (`devid-csr`, `devid-import`), `docs/spec.md` §9

- **`scripts/devid.sh csr`:**
  - Runs `/usr/bin/openssl req -new -newkey rsa:2048 -nodes -keyout .signing/devid.key -out .signing/devid.csr -subj "/CN=Annotake Developer ID/C=CA"`.
  - Then prints where the CSR is, and the upload steps (Certificates, IDs & Profiles → Certificates → + → Developer ID Application → G2 Sub-CA).
  - It refuses to overwrite an existing `devid.key`.
- **`scripts/devid.sh import <cer>`:**
  1. Converts the DER certificate with `openssl x509 -inform DER`.
  2. Builds a `.p12` with the key using `/usr/bin/openssl pkcs12 -export`. The system LibreSSL is what `make-cert.sh` already uses, and `security import` accepts its output.
  3. Downloads Apple's intermediate, `https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer`, into `.signing/`. Without it, `codesign` can't build the chain on a Mac with no Xcode.
  4. Imports both into `.signing/annotake-signing.keychain-db` with `-T /usr/bin/codesign`, then sets the partition list, exactly as `make-cert.sh` does, so signing never prompts.
  5. Writes the team id (the certificate's OU) to `.signing/team-id`.
  6. Deletes `devid.key`, the PEM, and the `.p12`.
  7. Runs `security find-identity -v -p codesigning <keychain>`.
- **`bundle-app.sh`, identity:**
  - Use `SIGN_IDENTITY` if it's set.
  - Otherwise, the first `Developer ID Application: …` in the keychain.
  - Otherwise, `Annotake Local Signing`.
- **`bundle-app.sh`, timestamp:** `RELEASE=1` makes the Developer ID mandatory (it fails with a clear message without one) and uses `--timestamp`. Everything else uses `--timestamp=none`.
- **Spec §9:** how releases are signed, and that development builds use the Developer ID once it's imported, so permissions are the same for development and release builds.

- [ ] **Step 1: Implement.** Then run `make devid-csr` once, so the CSR is waiting for Fayzan at the checkpoint.
- [ ] **Step 2: Verify.**
  - `openssl req -in .signing/devid.csr -noout -subject` shows `CN=Annotake Developer ID`.
  - `make app`, then `codesign -dvv build/Annotake.app` shows `Authority=Annotake Local Signing`.
  - `RELEASE=1 make app` fails with the "needs a Developer ID" message.
  - `make test`.
- [ ] **Step 3: Commit.** `build: Developer ID signing, with the local identity as fallback`

---

### Task 8: Sparkle updates (executable, App)

Design §5.2, item 6. **Glue** with a pure part: the menu.

**Files:**
- Create:
  - `Sources/AnnotakeApp/Updater.swift`;
  - `Sources/Annotake/SparkleUpdater.swift`;
  - `scripts/sparkle-keys.sh`;
  - `Resources/sparkle-public-key.txt`, written by the script.
- Modify:
  - `Package.swift`;
  - `Sources/Annotake/main.swift`;
  - `AppMain.swift`;
  - `StatusMenu.swift`, `Tests/AnnotakeAppTests/MenuModelTests.swift`;
  - `scripts/bundle-app.sh`, `Makefile` (`sparkle-keys`);
  - `docs/spec.md`: §2 (the update check), §3.5 (the menu), §6, and §6.2 (a row for updates).

**Interfaces (Produces):**

```swift
// AnnotakeApp
@MainActor public protocol Updater: AnyObject {
    func checkForUpdates()
}
extension AppEntry {
    /// The normal app calls `makeUpdater` once; --selftest and --render-ui never do.
    @MainActor public static func main(makeUpdater: @escaping @MainActor () -> any Updater)
}
enum MenuModel {
    enum Item: Equatable { case fixPermissions, startRecording, stopRecording, recent([String]), openFolder,
                           settings, checkForUpdates, quit }
}

// Annotake (executable)
@MainActor final class SparkleUpdater: Updater   // SPUStandardUpdaterController(startingUpdater: true, …)
```

**Package:**
- `.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")`.
- The `Annotake` executable target depends on `.product(name: "Sparkle", package: "Sparkle")`, with `linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]`.
- No other target depends on Sparkle.
- The first resolve clones Sparkle's repository and downloads `Sparkle-for-Swift-Package-Manager.zip`. On 2026-09-30 the download alone took about 19 minutes, so start it early: run `swift package resolve` first thing in this task.

**Keys (`scripts/sparkle-keys.sh`):**
1. Finds Sparkle's tools. After a resolve they're in `.build/artifacts/sparkle/Sparkle/bin/` (`generate_keys`, `sign_update`, `generate_appcast`), as checked on 2026-09-30. Look them up with `find .build/artifacts -type f -name generate_keys -print -quit` rather than hard-coding the path. If they aren't found, the script fails and says to run `swift package resolve`.
2. Runs `generate_keys`, which stores the private key in the login keychain.
3. Writes `generate_keys -p` to `Resources/sparkle-public-key.txt`.
4. Exports the private key with `generate_keys -x .signing/sparkle-private-key`.
5. Is idempotent: an existing key is reused.

Signing updates always uses `sign_update --ed-key-file .signing/sparkle-private-key`, so it never prompts for keychain access.

**If `generate_keys` waits on a keychain prompt,** end it and skip `make sparkle-keys` (record it under "Skipped"). The rest of the task still lands:
- the bundler leaves `SUPublicEDKey` out, with a warning, while `Resources/sparkle-public-key.txt` is missing; `RELEASE=1` fails without it;
- the dry run in Task 14 skips `sign_update` with a warning;
- Checkpoint 3 starts with `make sparkle-keys`, then a commit of the public key.

**Bundling:**
- The Makefile passes `FRAMEWORKS_DIR=<arm bin>`, the arm64 release bin path. SwiftPM puts the binary target's `Sparkle.framework` there next to the executable, and the xcframework's macOS slice is universal. The bundler copies `$FRAMEWORKS_DIR/Sparkle.framework` into `Contents/Frameworks/` with `ditto`, and fails if it's missing.
- Sign Sparkle's nested code inside out, with the same identity, `-o runtime`, and timestamp flag:
  1. `XPCServices/Installer.xpc`;
  2. `XPCServices/Downloader.xpc` with `--preserve-metadata=entitlements`;
  3. `Autoupdate`;
  4. `Updater.app`;
  5. the framework (all under `Versions/B/`);
  6. then the app.
- Add the Sparkle keys from the constraints to `Info.plist`.

**The menu:** `MenuModel.items` puts `.checkForUpdates` just before `.quit`. `StatusMenu` shows it as "Check for Updates…", which calls `actions.checkForUpdates`, wired to the injected updater.

- [ ] **Step 1: Write the tests.** `MenuModelTests.orderIsFixed` now expects `[.fixPermissions, .startRecording, .recent(titles), .openFolder, .settings, .checkForUpdates, .quit]`. Add `checkForUpdatesAlwaysListed`, covering both recording states.
- [ ] **Step 2:** `make test FILTER=MenuModelTests`. It fails.
- [ ] **Step 3: Implement.** Run `make sparkle-keys` once, and commit the public key.
- [ ] **Step 4: Verify.**
  - `make test`. The app tests must not link Sparkle; `otool -L` on the test bundle has no Sparkle.
  - `make app`, then on `build/Annotake.app`:
    - `otool -L Contents/MacOS/Annotake | grep Sparkle` shows `@rpath/Sparkle.framework/…`;
    - `otool -l Contents/MacOS/Annotake | grep -A2 LC_RPATH` includes `@executable_path/../Frameworks`;
    - `codesign --verify --strict --deep` passes;
    - `plutil -extract` on each Sparkle key matches the constraints.
  - `make selftest` and `make selftest-intel` pass.
  - `make ui-snapshots`.
- [ ] **Step 5: Commit.** `app: Sparkle updates and Check for Updates…`

---

### Task 9: Send Feedback (App)

Design §5.2, item 9. Pure report and mail logic, with glue.

**Files:**
- Create: `Sources/AnnotakeApp/Feedback.swift`, `Tests/AnnotakeAppTests/FeedbackTests.swift`
- Modify: `StatusMenu.swift`, `MenuModelTests.swift`, `AppMain.swift`, `docs/spec.md` §3.5 and §8

**Interfaces (Produces):**

```swift
enum Feedback {
    static let address = "feedback@annotake.app"
    static let logLines = 400
    static let crashReportMaxAge: TimeInterval = 7 * 86_400
    static let crashReportMaxBytes = 200_000
    static let mailtoBodyLimit = 1_500

    struct Facts: Equatable {
        var version: AppVersion
        var macOS: String            // e.g. "15.7.9"
        var model: String            // sysctl hw.model, e.g. "Mac16,1"
        var permissions: Permissions.Status
    }
    enum Delivery: Equatable { case composeWithAttachment, mailtoAndReveal }

    static func subject(_ version: AppVersion) -> String        // "Annotake feedback — 0.2.0 (74)"
    static func summary(_ facts: Facts) -> String               // the three fact lines
    static func report(_ facts: Facts, log: String?, crash: (name: String, text: String)?) -> String
    static func tail(_ text: String, lines: Int) -> String
    static func latestCrashReport(in directory: URL, now: Date) -> URL?   // newest Annotake-*.ips ≤ 7 days old
    static func mailtoURL(subject: String, body: String) -> URL           // to `address`; body capped
    static func delivery(canComposeWithAttachment: Bool) -> Delivery
}
enum MenuModel { … case sendFeedback … }   // just before .checkForUpdates
```

**The summary** is three lines:

```
Annotake 0.2.0 (74)
macOS 15.7.9 · Mac16,1
Permissions: screen recording yes, input monitoring yes, accessibility no
```

**The report** is the summary, then:
- `--- Recent log (last 400 lines) ---` and the tail;
- `--- Crash report: <name> ---` and its text, capped at 200,000 bytes with a final `… (truncated)` line.

With no crash report, it says `No crash report in the last 7 days.` instead. A nil log says `No log yet.`

**The menu action "Send Feedback…":**
1. Flushes the log.
2. Writes the report to `<temp>/Annotake-report-<yyyyMMdd-HHmmss>.txt`.
3. Uses `NSSharingService(named: .composeEmail)` with the recipient, the subject, and the items `["What happened?\n\n\n" + summary, reportURL]`.
4. When `canPerform(withItems:)` is false, opens `mailtoURL` (the same body, plus "The full report is in Finder; please attach it.") and reveals the file with `NSWorkspace.activateFileViewerSelecting`.

It logs `feedback report prepared`, never the contents.

- [ ] **Step 1: Write the tests.**

| Test | Assertion |
|---|---|
| `summaryHasVersionMacAndPermissions` | The three lines above, exactly, for those facts |
| `tailKeepsTheLastLines` | 1,000 numbered lines → 400 lines, ending in line 1000. 10 lines → unchanged |
| `latestCrashReportIsNewestRecentAnnotake` | A directory with `Annotake-2026-10-01-101112.ips` (2 days old), `Annotake-2026-09-20-090000.ips` (12 days), `Finder-2026-10-02-080000.ips`, and `Other-2026-10-02-080000.ips`, with dates set via `setAttributes`. Returns the 2-day-old file. Without it → nil |
| `crashReportIsCapped` | A 500 kB crash text → the report's crash section is ≤ 200,000 bytes and ends with `… (truncated)` |
| `noCrashReportSaysSo` | `crash: nil` → the report contains `No crash report in the last 7 days.` |
| `mailtoIsEncodedAndCapped` | The scheme is `mailto`, the path is `feedback@annotake.app`, and the subject's spaces and em dash are percent-encoded. A 5,000-character body is decoded to ≤ 1,500 characters |
| `fallsBackWithoutMailApp` | `delivery(canComposeWithAttachment: false)` → `.mailtoAndReveal`; true → `.composeWithAttachment` |
| `MenuModelTests.orderIsFixed` | `[…, .settings, .sendFeedback, .checkForUpdates, .quit]` |

- [ ] **Step 2:** `make test FILTER='FeedbackTests|MenuModelTests'`. It fails.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Verify.** `make test`, `make app`, `make ui-snapshots`.
- [ ] **Step 5: Commit.** `app: Send Feedback`

---

### Task 10: The first run's rules (App)

Design §5.2, item 8, and the plan's changes 2 and 4. **Pure.** This replaces `ChecklistModel`.

**Files:**
- Create: `Sources/AnnotakeApp/OnboardingModel.swift`, `Sources/AnnotakeApp/LoginItem.swift` (`LoginItemPolicy` and `LoginItem`, moved unchanged), `Tests/AnnotakeAppTests/OnboardingModelTests.swift`
- Modify: `Permissions.swift` (it takes `OnboardingModel.Permission`)
- Delete: `Tests/AnnotakeAppTests/ChecklistModelTests.swift`. Its login-item test moves into `OnboardingModelTests` as `loginItemOnlyFromApplications`, with the Task 1 paths.
- `FirstLaunch.swift` stays until Task 11. Keep it compiling by pointing it at the new `Permission` type.

**Interfaces (Produces):**

```swift
struct OnboardingModel: Equatable {
    enum Permission: String, CaseIterable, Codable, Identifiable { case accessibility, inputMonitoring, screenRecording }
    enum Step: Hashable, Codable { case welcome, permission(Permission), reopen, practice, dropCard, done }
    enum Mode: String, Codable { case firstRun, existingUser, fixPermissions }
    enum Action: Equatable { case next, prompt, openSettings, quitAndReopen, waitForRecording, waitForDrop, finish }
    struct Persisted: Codable, Equatable {
        var mode: Mode = .firstRun
        var step: Step = .welcome
        var requested: Set<Permission> = []
        var recorded = false            // a recording was saved while onboarding
        var completed = false
    }
    static let storeKey = "onboarding.v1"

    init(granted: [Permission: Bool], persisted: Persisted)   // then skips granted permission steps
    private(set) var granted: [Permission: Bool]
    private(set) var persisted: Persisted
    var step: Step { get }
    var action: Action { get }
    var needsReopen: Bool { get }     // inputMonitoring or screenRecording requested and not granted
    var showsAtLaunch: Bool { get }   // !persisted.completed

    /// In order. In Stage 2, a sign-in step goes after .welcome.
    static func steps(for mode: Mode) -> [Step]
    static func fixingPermissions(granted: [Permission: Bool]) -> Persisted   // .fixPermissions, at the first missing one

    mutating func perform()           // .next: advance; .prompt: mark requested; .finish: completed = true
    mutating func proceed()           // on a permission step: advance even if it can't be confirmed yet
    mutating func skip()              // on .practice or .dropCard: advance
    mutating func update(granted: [Permission: Bool])   // a now-granted current permission step advances
    mutating func recordingSaved()    // recorded = true; on .practice: advance
    mutating func cardDropped()       // on .dropCard: advance
    mutating func relaunched()        // on .reopen: advance
}
```

**Steps:**
- `.firstRun`: `[.welcome, .permission(.accessibility), .permission(.inputMonitoring), .permission(.screenRecording), .reopen, .practice, .dropCard, .done]`.
- `.existingUser` and `.fixPermissions`: `[.permission(.accessibility), .permission(.inputMonitoring), .permission(.screenRecording), .reopen, .done]`.

**Advancing** moves to the next step for the mode, skipping:
- a `.permission(p)` that's granted;
- `.reopen` when `!needsReopen`;
- `.practice` when `recorded`.

**Actions:**

| Step | Action |
|---|---|
| `.welcome` | `.next` |
| `.permission(p)`, not yet requested | `.prompt` |
| `.permission(p)`, requested | `.openSettings` |
| `.reopen` | `.quitAndReopen` |
| `.practice` | `.waitForRecording` |
| `.dropCard` | `.waitForDrop` |
| `.done` | `.finish` |

- [ ] **Step 1: Write the tests.**

| Test | Assertion |
|---|---|
| `newUserStepsInOrder` | `steps(for: .firstRun)` equals the list above |
| `existingUserSkipsWelcomeAndPractice` | `steps(for: .existingUser)` equals the list above |
| `grantedPermissionsAreSkipped` | Accessibility granted; at `.welcome`, `perform()` → `.permission(.inputMonitoring)` |
| `firstPressPromptsThenOpensSettings` | At `.permission(.accessibility)`: `action == .prompt`; after `perform()`, `.openSettings`, still on the same step |
| `continueWithoutConfirmation` | At `.permission(.screenRecording)`, requested and not granted: `proceed()` → `.reopen` |
| `reopenOnlyWhenNeeded` | Everything granted before the last permission → advancing skips `.reopen` to `.practice`. Input Monitoring requested and not granted → `.reopen` |
| `grantWhileShowingAdvances` | At `.permission(.accessibility)`, `update(granted: [.accessibility: true])` → `.permission(.inputMonitoring)` |
| `relaunchResumesAfterReopen` | Persisted at `.reopen`: `.firstRun` → `relaunched()` → `.practice`; `.existingUser` → `.done` |
| `recordingAndDropFinish` | At `.practice`, `.waitForRecording`; `recordingSaved()` → `.dropCard`; `cardDropped()` → `.done`; `perform()` → `completed` and `!showsAtLaunch` |
| `earlyRecordingSkipsPractice` | `recordingSaved()` at `.permission(.accessibility)`; `proceed()` through the rest (none granted, reopen needed); `relaunched()` → `.dropCard` |
| `fixPermissionsStartsAtFirstMissing` | Accessibility and Input Monitoring granted → `fixingPermissions` has mode `.fixPermissions` and step `.permission(.screenRecording)` |
| `persistedRoundTrips` | A `Persisted` at `.permission(.inputMonitoring)`, with requests, survives a JSON encode and decode |
| `loginItemOnlyFromApplications` | As in the old suite, with Annotake paths |

- [ ] **Step 2:** `make test FILTER=OnboardingModelTests`. It fails.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Verify.** `make test`.
- [ ] **Step 5: Commit.** `app: the first run's rules`

---

### Task 11: The first-run window (App)

Design §5.2, item 8. **Glue** with a pure part: copy and drops. It replaces the checklist.

**Files:**
- Create: `Sources/AnnotakeApp/Onboarding.swift`, `Tests/AnnotakeAppTests/OnboardingCopyTests.swift`
- Delete: `Sources/AnnotakeApp/FirstLaunch.swift`
- Modify:
  - `AppMain.swift`: `OnboardingController` replaces `FirstLaunchController`; "Fix permissions…" calls `show(fixingPermissions: true)`; the first mode is `.existingUser` when `migration?.existingUser`;
  - `UISnapshots.swift`;
  - `docs/spec.md` §3.7, rewritten.

**Interfaces (Produces):**

```swift
enum OnboardingCopy {
    static let reassurance = "Annotake sees your screen only while you record. Nothing you record leaves your Mac."
    static func keyName(_ trigger: TriggerKey) -> String          // "Right ⌘", "Right ⌥", "fn"
    static func title(_ step: OnboardingModel.Step) -> String
    static func body(_ step: OnboardingModel.Step, trigger: TriggerKey, mode: OnboardingModel.Mode) -> String
}
enum OnboardingDrop {
    static func frames(from urls: [URL]) -> [URL]   // .png only, sorted by file name; empty means not a card
}
@MainActor final class OnboardingController: NSObject, NSWindowDelegate {
    init(trigger: TriggerKey, defaults: UserDefaults, existingUser: Bool, retiredFlipbook: Bool)
    func showIfNeeded()
    func show(fixingPermissions: Bool)
    func recordingSaved()
}
```

**The window:**
- Titled "Welcome to Annotake", 560 pt wide, not resizable.
- One step at a time, from `OnboardingModel`, saved under `onboarding.v1` after every change.
- Permissions are polled every 1 s while it's open.
- **Quit & Reopen:**
  - saves first;
  - then runs `/bin/sh -c 'sleep 1; /usr/bin/open "$0"' <bundle path>` and terminates, as the checklist did;
  - at the next launch, `relaunched()` runs before the window shows.

**The copy:**

| Step | Title | Body and controls |
|---|---|---|
| Welcome | "Annotake" | Subtitle: "Show your coding agent exactly what happened."<br>Body: "Press a key, do the thing, and drag the card into Claude Code, Cursor, or ChatGPT. Each step comes out as a screenshot, captioned with what you clicked."<br>The demo: three tiles ("Double-tap Right ⌘", "Click through it", "Drag the card into your agent"), highlighted in turn every 1.6 s with `TimelineView`.<br>When the old app was retired: `LegacyFlipbook.replacedNote`.<br>Button: "Get Started". |
| Accessibility | "Allow Accessibility" | "So Annotake can name the buttons you click, and keep ⌘ out of your clicks while you hold the key." |
| Input Monitoring | "Allow Input Monitoring" | "So Annotake can notice Right ⌘, and your clicks and keys while you record. It never records what you type." |
| Screen Recording | "Allow Screen Recording" | "So Annotake can capture your screen while you record." |
| Reopen | "Reopen Annotake" | "macOS turns on Screen Recording and Input Monitoring after Annotake reopens. It comes back to this window."<br>Button: "Quit & Reopen". |
| Practice | "Try it" | "1. Double-tap Right ⌘. The pill appears at the bottom of the screen." / "2. Click Open, then tick Remember me." / "3. Double-tap Right ⌘ again."<br>A real SwiftUI `Button("Open")` and `Toggle("Remember me")`, so Accessibility names them.<br>Button: "Skip". |
| Drop | "Now drag the card here" | "The card is at the bottom right of your screen."<br>A drop box (`.onDrop(of: [.fileURL])` → `OnboardingDrop.frames`). After a drop: "<N> frames. That's what your agent gets." with the first three thumbnails, then "Next time, drag it into Claude Code, Cursor, or ChatGPT."<br>Buttons: "Skip" / "Continue". |
| Done | "You're set" | "Hold Right ⌘ for quick recordings, and let go to stop." / "Right ⌘ + Esc cancels." / "Everything else is in the menu-bar icon."<br>Button: "Done". |

Rules for the table:
- Every key name goes through `keyName`; the table shows Right ⌘.
- **Every permission step** shows:
  - its body, then `OnboardingCopy.reassurance`;
  - a picture: a SwiftUI mock of the System Settings row, with the app icon, "Annotake", and a toggle that's on and ringed in the accent color. It's captioned "System Settings → Privacy & Security → <pane>: turn on Annotake."
  - "Allow…" (prompt), or "Open System Settings" plus "Continue" after the first press;
  - a ✓ once granted.
- **In `.existingUser`,** permission steps add `LegacyFlipbook.askAgainNote` above the body.

**Snapshots** replace `checklist-*.png` with:
- `onboarding-welcome.png`;
- `onboarding-accessibility.png`;
- `onboarding-screen-recording-requested.png`;
- `onboarding-existing-user.png` (the existing-user line on the Accessibility step);
- `onboarding-reopen.png`;
- `onboarding-practice.png`;
- `onboarding-drop.png` (empty);
- `onboarding-drop-done.png`, with the sample thumbnails;
- `onboarding-done.png`.

- [ ] **Step 1: Write the tests.**

| Test | Assertion |
|---|---|
| `reassuranceOnEveryPermission` | For each `Permission`, `body(.permission(p), …)` contains `reassurance` exactly |
| `keyNameFollowsTrigger` | `.rightCommand` → "Right ⌘", `.rightOption` → "Right ⌥", `.fn` → "fn"; the practice body under `.rightOption` names "Right ⌥" |
| `existingUserLineOnlyForExistingUsers` | `LegacyFlipbook.askAgainNote` is in the Accessibility body under `.existingUser`, and not under `.firstRun`. Use the constant, not the literal, so the test file never names the old app |
| `dropKeepsPNGsInNameOrder` | `[03_0m07s.png, notes.md, 01_0m00s.png, 02_0m03s.png]` → the three PNGs in order 01, 02, 03; `[notes.md]` → empty |

- [ ] **Step 2:** `make test FILTER=OnboardingCopyTests`. It fails.
- [ ] **Step 3: Implement.** Delete `FirstLaunch.swift` and the checklist snapshots.
- [ ] **Step 4: Verify.**
  - `make test`.
  - `make ui-snapshots`: look at every `onboarding-*.png`. Nothing may be clipped, every key name must be right, and the existing-user line must show only in its snapshot.
  - `make selftest`.
- [ ] **Step 5: Commit.** `app: the Wispr-style first run`

---

### Task 12: Move to Applications (App)

Design §5.2, item 8 (the move offer). Pure decision, with glue.

**Files:**
- Create: `Sources/AnnotakeApp/MoveToApplications.swift`, `Tests/AnnotakeAppTests/MoveToApplicationsTests.swift`
- Modify: `AppMain.swift`: runs before migration and onboarding, in normal mode only. `docs/spec.md` §3.7.

**Interfaces (Produces):**

```swift
enum MoveToApplications {
    enum Decision: Equatable { case stay, offer(destination: URL) }
    static let declinedKey = "moveToApplications.declined"
    static func decision(bundleURL: URL, home: URL, systemApplicationsWritable: Bool) -> Decision
    static func isTranslocated(_ url: URL) -> Bool        // the path contains "/AppTranslocation/"
    @MainActor static func offerIfNeeded(defaults: UserDefaults)   // glue
}
```

**The decision:**
- `.stay` when `LoginItemPolicy.canRegister(bundleURL:home:)`.
- Otherwise `.offer`, with `/Applications/Annotake.app` when it's writable, else `<home>/Applications/Annotake.app`.

**The glue:**
1. If the decision is `.offer` and `declinedKey` isn't set, show an `NSAlert`: "Move Annotake to Applications?" / "Annotake needs to be in Applications to start when you log in.", with the buttons "Move to Applications" (default) and "Not Now".
2. "Not Now" sets `declinedKey`.
3. "Move" does this:
   1. Resolves the original location. When the app is translocated, it uses `SecTranslocateCreateOriginalPathForURL`, loaded with `dlsym` from `Security.framework`, falling back to the bundle URL.
   2. Replaces any existing copy at the destination, then copies.
   3. Relaunches the destination with the same `sleep 1; open` pattern, and terminates.
   4. Moves the original to the Trash, unless it's on a read-only volume such as the disk image.

Every failure is logged and shown in a plain alert ("Couldn't move Annotake: <reason>"), and the app keeps running where it is.

- [ ] **Step 1: Write the tests.**

| Test | Assertion |
|---|---|
| `staysInApplications` | `/Applications/Annotake.app` and `<home>/Applications/Annotake.app` → `.stay` |
| `offersSystemApplicationsWhenWritable` | `<home>/Downloads/Annotake.app` with writable → `.offer(/Applications/Annotake.app)` |
| `offersUserApplicationsOtherwise` | The same, not writable → `.offer(<home>/Applications/Annotake.app)` |
| `detectsTranslocation` | `/private/var/folders/x/AppTranslocation/ABC/d/Annotake.app` → true; `/Volumes/Annotake/Annotake.app` → false |

- [ ] **Step 2:** `make test FILTER=MoveToApplicationsTests`. It fails.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Verify.** `make test`, `make app`.
- [ ] **Step 5: Commit.** `app: offer to move to Applications`

---

### Task 13: The appcast (Release)

Design §5.2, items 6 and 10. **Pure.** A bad appcast breaks updates for everyone, so its writer is tested.

**Files:**
- Create:
  - `Sources/AnnotakeRelease/Appcast.swift`;
  - `Sources/annotake-appcast/main.swift`;
  - `Tests/AnnotakeReleaseTests/AppcastTests.swift`.
- Modify: `Package.swift`, adding the library `AnnotakeRelease` (Foundation only), the executable `annotake-appcast`, and the test target `AnnotakeReleaseTests`.

**Interfaces (Produces):**

```swift
public struct AppcastItem: Equatable, Sendable {
    public var shortVersion: String          // "0.2.0"
    public var build: String                 // "74"
    public var url: URL                      // the tag's Annotake.zip
    public var length: Int                   // bytes
    public var edSignature: String           // from sign_update
    public var minimumSystemVersion: String  // "15.0"
    public var date: Date
    public var notes: String                 // plain text
}
public enum AppcastError: Error, Equatable { case duplicateBuild(String), unreadableFeed }
public enum Appcast {
    public static let maxItems = 10
    /// A new feed when `existing` is nil; otherwise `existing` with `item` first, trimmed to `maxItems`.
    public static func inserting(_ item: AppcastItem, into existing: String?) throws -> String
}
```

**The feed.** Sparkle's RSS, built with `XMLDocument`: an `<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">` whose `<channel><title>Annotake</title>` holds the items, newest first. Each item:

```xml
<item>
  <title>Annotake 0.2.0 (74)</title>
  <pubDate>Wed, 30 Sep 2026 22:00:00 +0000</pubDate>
  <sparkle:version>74</sparkle:version>
  <sparkle:shortVersionString>0.2.0</sparkle:shortVersionString>
  <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
  <description><![CDATA[<p>…notes, HTML-escaped, one <p> per line…</p>]]></description>
  <enclosure url="…/Annotake.zip" length="123456" type="application/octet-stream" sparkle:edSignature="…"/>
</item>
```

- `pubDate` uses `en_US_POSIX` and UTC.
- In the notes, `]]>` is split so the CDATA stays valid.

**`annotake-appcast`:** `--feed <path> --version <v> --build <n> --url <url> --length <n> --signature <sig> --notes <text> [--min-system 15.0]`. It reads the feed if it exists, writes the result, and prints the item's title. Bad arguments print usage and exit 2.

- [ ] **Step 1: Write the tests.**

| Test | Assertion |
|---|---|
| `newFeedHasOneItem` | `inserting(item, into: nil)` parses with `XMLDocument`: one `item`, `sparkle:version` 74, and the enclosure's `url`, `length`, `type`, and `sparkle:edSignature` exactly |
| `newestItemFirst` | Inserting build 75 into a feed with 74 → the items in the order 75, 74 |
| `duplicateBuildThrows` | Inserting 74 again → `.duplicateBuild("74")` |
| `keepsAtMostTenItems` | 11 inserts → 10 items, and the oldest is gone |
| `escapesNotes` | The notes `Fix <b> & "quotes"` and `a]]>b` round-trip as text inside the description |
| `pubDateIsRFC822` | 2026-09-30 22:00:00 UTC → `Wed, 30 Sep 2026 22:00:00 +0000` |
| `unreadableFeedThrows` | `"not xml"` → `.unreadableFeed` |

- [ ] **Step 2:** `make test FILTER=AppcastTests`. It fails.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Verify.** `make test`, then `swift run annotake-appcast --feed build/test-appcast.xml …` twice with builds 1 and 2, then `xmllint --noout build/test-appcast.xml`.
- [ ] **Step 5: Commit.** `release: the appcast writer`

---

### Task 14: Disk image, release script, and install script

Design §5.1 and §5.2, items 2, 3, and 10. **Glue.**

**Files:**
- Create:
  - `scripts/make-dmg-background.swift`, `Resources/dmg-background.tiff`;
  - `scripts/dmg-settings.py`;
  - `scripts/release.sh`;
  - `scripts/install.sh`;
  - `scripts/releases-README.md`.
- Modify: `Makefile` (`release`, `dmg-venv`, and the clean `zip`), `.gitattributes`, `docs/spec.md` §9.

**The disk image background** (`scripts/make-dmg-background.swift`):
- 600 × 400, written at 1× and 2× and combined with `tiffutil -cathidpicheck`.
- `#F5F5F7` background.
- A rounded arrow (`#8E8E93`, 6 pt) from x 215 to x 385 at y 190, between the two icon spots.
- "Drag Annotake to Applications", 15 pt `#6E6E73`, centered at y 330.

**`scripts/dmg-settings.py`** (dmgbuild):
- Format `UDZO`.
- Files: the app (`-D app=…`).
- Symlink `Applications` → `/Applications`.
- The volume icon `-D icon=Resources/AppIcon.icns`.
- The background `-D background=Resources/dmg-background.tiff`.
- `window_rect = ((200, 120), (600, 400))`, `icon_size = 128`, `text_size = 13`.
- Icon locations: the app at (150, 190) and `Applications` at (450, 190).
- `show_icon_preview = False`.

`make dmg-venv` creates `.build/dmgbuild-venv` with `/usr/bin/python3 -m venv` and installs `dmgbuild==1.6.5`.

**`scripts/release.sh`** (`make release NOTES="…" [DRY_RUN=1]`). It runs with `set -euo pipefail`, and publishing comes last, so any failure leaves the releases repo and the appcast untouched.
1. **Preconditions.** `NOTES` must be non-empty. Unless `DRY_RUN=1`, also:
   - the git tree is clean;
   - on `main`, and `HEAD` equals `origin/main` after a fetch;
   - a Developer ID identity is in the keychain;
   - `xcrun notarytool history --keychain-profile annotake-notary` succeeds;
   - `.signing/sparkle-private-key` exists;
   - `gh auth status` succeeds;
   - the tag `v<VERSION>-<BUILD>` doesn't exist in `fayzan123/annotake-releases`.
2. **Build.** `make app`, with `RELEASE=1` unless it's a dry run, then copy it to `build/release/Annotake.app`.
3. **Notarize the app.** Skipped in a dry run.
   1. Zip it with `ditto -c -k --keepParent`.
   2. `xcrun notarytool submit … --keychain-profile annotake-notary --wait --timeout 30m`. On any status but `Accepted`, print `notarytool log <id>` and exit 1.
   3. `xcrun stapler staple`, then `xcrun stapler validate`.
   4. `spctl -a -t exec -vv` must say `source=Notarized Developer ID`.
4. **The zip.** `ditto -c -k --keepParent --norsrc --noextattr --noacl` → `build/release/Annotake.zip`. It's both the Sparkle archive and what `install.sh` downloads.
5. **The disk image.**
   1. `dmgbuild` → `build/release/Annotake.dmg`.
   2. Sign it with the same identity, plus `--timestamp` unless it's a dry run.
   3. Unless it's a dry run: notarize it, staple it, and check it with `spctl -a -t open --context context:primary-signature -vv`.
6. **The Sparkle signature.** `sign_update --ed-key-file .signing/sparkle-private-key build/release/Annotake.zip`. Parse `sparkle:edSignature` and `length`. A dry run without the key file skips this with a warning and writes a placeholder signature, so the rest still runs; a real release fails without it.
7. **Publish.** In a dry run, instead write `build/release/appcast.xml` with `annotake-appcast` (a fresh feed), and stop.
   1. `gh repo clone fayzan123/annotake-releases build/release/repo -- --depth 1`.
   2. `gh release create v<VERSION>-<BUILD> build/release/Annotake.zip build/release/Annotake.dmg --repo fayzan123/annotake-releases --title "Annotake <VERSION> (<BUILD>)" --notes "$NOTES" --latest`.
   3. Then update `build/release/repo/appcast.xml` with `annotake-appcast`, using the URL `https://github.com/fayzan123/annotake-releases/releases/download/v<VERSION>-<BUILD>/Annotake.zip`.
   4. Copy in `scripts/install.sh` and `scripts/releases-README.md` (as `README.md`).
   5. Commit `Annotake <VERSION> (<BUILD>)` and push.
8. **Print** the disk image link (`…/releases/latest/download/Annotake.dmg`), the install command, and the SHA-256 of both files.

**`scripts/install.sh`:** the early-install script from design §5.1, changed:
- the zip is `https://github.com/fayzan123/annotake-releases/releases/latest/download/Annotake.zip`, overridable with `ANNOTAKE_ZIP_URL`, for tests with `file://`;
- the app is `Annotake.app`;
- no Apple-silicon check (the app is universal), but macOS 15 or later is still required;
- it quits a running `Flipbook` or `Annotake`;
- it removes `Flipbook.app` from both Applications folders;
- it runs `tccutil reset All com.fayzanmalik.flipbook` quietly, so the old rows leave System Settings;
- the test variable is `ANNOTAKE_INSTALL_DIR` (in a test run, nothing is quit, opened, or removed);
- the final message names Annotake.

**`scripts/releases-README.md`:** the releases repo's README, written for Annotake:
- the disk image download link;
- the Terminal command;
- first run;
- privacy: nothing you record leaves your Mac, and the app checks for updates once a day, sending only its version;
- Send Feedback and the feedback address;
- uninstall, with `tccutil reset All com.fayzanmalik.annotake`.

**Spec §9:** releases come from `make release`, from a disk image on GitHub, and update with Sparkle. The install command becomes the `annotake-releases` URL, which works once the checkpoint renames the repo.

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Verify** with a dry run: `make release DRY_RUN=1 NOTES="Dry run."`. Then:
  - `hdiutil attach -nobrowse -readonly -mountpoint build/release/mnt build/release/Annotake.dmg`. Check that it lists `Annotake.app`, `Applications` (a symlink to `/Applications`), and `.background`. Run `codesign --verify --strict --deep build/release/mnt/Annotake.app`, then `hdiutil detach build/release/mnt`.
  - `xmllint --noout build/release/appcast.xml`. The item's length equals the zip's size.
  - `ANNOTAKE_ZIP_URL=file://$PWD/build/release/Annotake.zip ANNOTAKE_INSTALL_DIR=$PWD/build/install-test sh scripts/install.sh` installs a copy that passes `codesign --verify --strict --deep` and has no `com.apple.quarantine`.
  - `sh -n scripts/install.sh scripts/release.sh`.
  - `make test`.
- [ ] **Step 3: Commit.** `release: disk image, release script, and the Annotake installer`

---

### Task 15: Final checks, push, the repo rename, and the checkpoint

- [ ] **Step 1: Checks.**
  - `make test` passes in full.
  - The grep in the constraints lists nothing outside the allowed files.
  - `grep -rn "URLSession\|NWConnection\|CFNetwork" Sources` lists nothing.
  - `make selftest` and `make selftest-intel` pass.
  - `make ui-snapshots` renders every panel; look at each once.
  - `make release DRY_RUN=1 NOTES="Dry run."` passes.
- [ ] **Step 2: Docs.**
  - **`docs/plans/README.md`:** mark Session 8 done with a one-line summary, then add two lists to its section:
    - **Decisions:** every place the session chose differently from this plan, and why;
    - **Skipped:** every step it couldn't finish unattended, and what it needs.

    Also note anything later plans need, such as anything that behaved differently from this plan.
  - **Design §5.2:** mark the build done.
  - **The spec:** each task updated its own sections. Read the spec once end to end for leftovers.
  - Commit with `docs: session 8 done`.
- [ ] **Step 3: Push and rename the private repo.**
  1. `git push origin main`.
  2. `gh repo rename annotake --repo fayzan123/flipbook --yes`.
  3. `git remote set-url origin https://github.com/fayzan123/annotake.git`.
  4. `git fetch origin` succeeds.
- [ ] **Step 4: The checkpoint. Stop here, and give Fayzan this list.** Put the session's Decisions and Skipped lists first, each skipped step with its own instructions. The results go into `docs/checkpoints.md` in the next session.

**Checkpoint 3** (both Macs):
0. **Before starting.**
   - The Apple Developer membership is active: developer.apple.com/account shows a Team ID.
   - annotake.app is bought on Vercel, and `feedback@annotake.app` forwards to Fayzan through ImprovMX (its MX and TXT records added in Vercel's DNS). A test email arrives.
1. **The Developer ID certificate.**
   1. At developer.apple.com/account → Certificates, IDs & Profiles → Certificates → + → Developer ID Application → G2 Sub-CA, upload `.signing/devid.csr`.
   2. Download the certificate, then run `make devid-import CER=~/Downloads/developerID_application.cer`.
   3. It lists `Developer ID Application: Fayzan Malik (…)`.
2. **The notarization key.**
   1. At appstoreconnect.apple.com → Users and Access → Integrations → App Store Connect API → Team Keys, generate a key with the Developer role.
   2. Download the `.p8` (it can only be downloaded once), and note the Key ID and Issuer ID.
   3. Run `xcrun notarytool store-credentials annotake-notary --key ~/Downloads/AuthKey_<KEYID>.p8 --key-id <KEYID> --issuer <ISSUER-ID>`.
   4. Move the `.p8` somewhere safe.
3. **Back up the two secrets** in a password manager:
   - `.signing/sparkle-private-key`. Losing it means existing installs can never be updated.
   - The Developer ID identity: `security export -k .signing/annotake-signing.keychain-db -t identities -f pkcs12 -o ~/Desktop/annotake-devid.p12`, which asks for a passphrase. Store the file, then delete it from the Desktop.
4. **Rename the releases repo.** `gh repo rename annotake-releases --repo fayzan123/flipbook-releases --yes`.
5. **The first release.** `make release NOTES="Annotake: the new name, a new first run, and signed, notarized downloads."`. It prints the links.
6. **The old command.**
   - `curl -fsSL https://raw.githubusercontent.com/fayzan123/flipbook-releases/main/install.sh | head -3` should show the new script.
   - If it doesn't, create a public `fayzan123/flipbook-releases` holding one `install.sh` whose body is `curl -fsSL https://raw.githubusercontent.com/fayzan123/annotake-releases/main/install.sh | sh`.
7. **Install like a stranger (personal Mac).**
   1. In Safari, download `Annotake.dmg` from the printed link. Open it, drag the app to Applications, and eject.
   2. Open Annotake from Launchpad or Finder. Expected:
      - no Gatekeeper warning at all;
      - Flipbook is quit and in the Trash, and the welcome step doesn't show, because this Mac is an existing user;
      - the permission steps run;
      - Quit & Reopen brings the window back;
      - the captures from `~/Pictures/Flipbook` are under `~/Pictures/Annotake` and in Recent Captures;
      - settings carried over.
   3. Try the move offer once: open a second copy straight from the disk image. The offer appears; "Not Now" is fine.
8. **Updates.**
   1. Make any small commit (a docs line), push, then run `make release NOTES="Test update."`.
   2. In Annotake, choose Check for Updates…. It finds the new version, installs it, and relaunches.
   3. All three permissions are still granted afterwards.
9. **Send Feedback.** The menu item opens a draft to `feedback@annotake.app` with the report attached, or with the report shown in Finder if the default mail app isn't Mail.
10. **First run as a new user.** On the personal Mac:
    1. Quit Annotake.
    2. Run `tccutil reset All com.fayzanmalik.annotake`, then `defaults delete com.fayzanmalik.annotake onboarding.v1`. Delete only that key: migration has already run, so the first run starts in its new-user mode, and settings stay.
    3. Open Annotake. You should see:
       - the welcome step and its demo;
       - each permission one at a time, each with the reassurance line and the System Settings picture;
       - the practice run;
       - the drop box.
    4. Judge the icon and the first run.
11. **Work Mac (macOS 26).** Run the install command from the new README. Annotake is installed, Flipbook is gone, and its old rows have left System Settings. Grant the permissions, and drag a card into Cursor.
12. **After closing this session, rename the local folder and move Claude's memory for it:**

    ```
    mv ~/Documents/GitHub/flipbook ~/Documents/GitHub/annotake
    mv ~/.claude/projects/-Users-fayzanmalik-Documents-GitHub-flipbook ~/.claude/projects/-Users-fayzanmalik-Documents-GitHub-annotake
    ```

    Then reopen the folder in VS Code.
