// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FlipbookSpike",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "FlipbookSpike")
    ],
    swiftLanguageModes: [.v5]
)
