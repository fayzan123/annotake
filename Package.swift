// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Flipbook",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FlipbookCore", targets: ["FlipbookCore"]),
        .executable(name: "flipbook-replay", targets: ["flipbook-replay"]),
    ],
    targets: [
        .target(name: "FlipbookCore"),
        .executableTarget(name: "flipbook-replay", dependencies: ["FlipbookCore"]),
        .testTarget(name: "FlipbookCoreTests", dependencies: ["FlipbookCore"]),
    ]
)
