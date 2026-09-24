// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Flipbook",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FlipbookCore", targets: ["FlipbookCore"]),
        .executable(name: "Flipbook", targets: ["Flipbook"]),
        .executable(name: "flipbook-replay", targets: ["flipbook-replay"]),
    ],
    targets: [
        .target(name: "FlipbookCore"),
        .target(name: "FlipbookCapture", dependencies: ["FlipbookCore"]),
        .target(name: "FlipbookInput", dependencies: ["FlipbookCore"]),
        .target(name: "FlipbookExport", dependencies: ["FlipbookCore"]),
        .target(name: "FlipbookApp",
                dependencies: ["FlipbookCore", "FlipbookCapture", "FlipbookInput", "FlipbookExport"]),
        .executableTarget(name: "Flipbook", dependencies: ["FlipbookApp"]),
        .executableTarget(name: "flipbook-replay", dependencies: ["FlipbookCore"]),
        .testTarget(name: "FlipbookCoreTests", dependencies: ["FlipbookCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "FlipbookCaptureTests", dependencies: ["FlipbookCapture", "FlipbookCore"]),
        .testTarget(name: "FlipbookInputTests", dependencies: ["FlipbookInput", "FlipbookCore"]),
        .testTarget(name: "FlipbookExportTests", dependencies: ["FlipbookExport", "FlipbookCore"]),
        .testTarget(name: "FlipbookAppTests",
                    dependencies: ["FlipbookApp", "FlipbookCore", "FlipbookCapture", "FlipbookInput", "FlipbookExport"]),
    ]
)
