// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Annotake",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AnnotakeCore", targets: ["AnnotakeCore"]),
        .executable(name: "Annotake", targets: ["Annotake"]),
        .executable(name: "annotake-replay", targets: ["annotake-replay"]),
        .executable(name: "annotake-appcast", targets: ["annotake-appcast"]),
    ],
    dependencies: [
        // Updates, linked only into the executable. The libraries' one network call is EmailSignup.post, which only the
        // app itself makes: tests, --selftest, and --render-ui make no network calls.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(name: "AnnotakeCore"),
        .target(name: "AnnotakeCapture", dependencies: ["AnnotakeCore"]),
        .target(name: "AnnotakeInput", dependencies: ["AnnotakeCore"]),
        .target(name: "AnnotakeExport", dependencies: ["AnnotakeCore"]),
        .target(name: "AnnotakeApp",
                dependencies: ["AnnotakeCore", "AnnotakeCapture", "AnnotakeInput", "AnnotakeExport"]),
        .executableTarget(name: "Annotake",
                          dependencies: ["AnnotakeApp", .product(name: "Sparkle", package: "Sparkle")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "annotake-replay", dependencies: ["AnnotakeCore"]),
        // Release tooling, Foundation only: the Sparkle feed that make release updates.
        .target(name: "AnnotakeRelease"),
        .executableTarget(name: "annotake-appcast", dependencies: ["AnnotakeRelease"]),
        .testTarget(name: "AnnotakeCoreTests", dependencies: ["AnnotakeCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "AnnotakeCaptureTests", dependencies: ["AnnotakeCapture", "AnnotakeCore"]),
        .testTarget(name: "AnnotakeInputTests", dependencies: ["AnnotakeInput", "AnnotakeCore"]),
        .testTarget(name: "AnnotakeExportTests", dependencies: ["AnnotakeExport", "AnnotakeCore"]),
        .testTarget(name: "AnnotakeReleaseTests", dependencies: ["AnnotakeRelease"]),
        .testTarget(name: "AnnotakeAppTests",
                    dependencies: ["AnnotakeApp", "AnnotakeCore", "AnnotakeCapture", "AnnotakeInput", "AnnotakeExport"]),
    ]
)
