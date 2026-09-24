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

## Accessibility labels

## Capture

## Drag card

## Decisions
