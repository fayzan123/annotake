// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Annotake",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AnnotakeCore", targets: ["AnnotakeCore"]),
        .executable(name: "Annotake", targets: ["Annotake"]),
        .executable(name: "annotake-replay", targets: ["annotake-replay"]),
    ],
    targets: [
        .target(name: "AnnotakeCore"),
        .target(name: "AnnotakeCapture", dependencies: ["AnnotakeCore"]),
        .target(name: "AnnotakeInput", dependencies: ["AnnotakeCore"]),
        .target(name: "AnnotakeExport", dependencies: ["AnnotakeCore"]),
        .target(name: "AnnotakeApp",
                dependencies: ["AnnotakeCore", "AnnotakeCapture", "AnnotakeInput", "AnnotakeExport"]),
        .executableTarget(name: "Annotake", dependencies: ["AnnotakeApp"]),
        .executableTarget(name: "annotake-replay", dependencies: ["AnnotakeCore"]),
        .testTarget(name: "AnnotakeCoreTests", dependencies: ["AnnotakeCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "AnnotakeCaptureTests", dependencies: ["AnnotakeCapture", "AnnotakeCore"]),
        .testTarget(name: "AnnotakeInputTests", dependencies: ["AnnotakeInput", "AnnotakeCore"]),
        .testTarget(name: "AnnotakeExportTests", dependencies: ["AnnotakeExport", "AnnotakeCore"]),
        .testTarget(name: "AnnotakeAppTests",
                    dependencies: ["AnnotakeApp", "AnnotakeCore", "AnnotakeCapture", "AnnotakeInput", "AnnotakeExport"]),
    ]
)
