import AnnotakeCore
import Foundation

/// Whether rendered frames get the caption strip and click markers. Stored with the capture, so a
/// re-render after a filmstrip trim matches the original.
public struct RenderOptions: Codable, Equatable, Sendable {
    public var captionStrip: Bool
    public var clickMarkers: Bool

    public init(captionStrip: Bool, clickMarkers: Bool) {
        self.captionStrip = captionStrip
        self.clickMarkers = clickMarkers
    }
}

/// `.raw/capture.json`: what re-rendering needs, so the filmstrip and Recent Captures work after a
/// relaunch. Internal, not a public machine-readable format.
public struct CaptureManifest: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    /// e.g. "2026-09-23 at 14.05.12"
    public var name: String
    /// e.g. "Screen: Built-in Retina Display" or "Window: Google Chrome — Title"
    public var target: String
    public var created: Date
    public var render: RenderOptions
    /// The current frames, after trims.
    public var result: PickResult
    /// Frames removed in the filmstrip, in removal order.
    public var removed: [PickedFrame]

    public init(name: String, target: String, created: Date, render: RenderOptions, result: PickResult,
                removed: [PickedFrame]) {
        version = Self.currentVersion
        self.name = name
        self.target = target
        self.created = created
        self.render = render
        self.result = result
        self.removed = removed
    }
}
