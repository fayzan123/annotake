import FlipbookCore
import Foundation

/// Everything the user can set (spec §3.6), with its default. A change applies to the next recording.
public struct Settings: Codable, Equatable, Sendable {
    public enum RecordTarget: Codable, Equatable, Sendable {
        case cursorScreen
        /// Stored by display UUID, so it survives reboots.
        case screen(displayUUID: String)
        /// Matched by ID only; the title is only for display in Settings.
        case window(windowID: UInt32, title: String)
    }

    public enum Retention: String, Codable, Sendable, CaseIterable {
        case days7, days30, forever

        public var days: Int? {
            switch self {
            case .days7: 7
            case .days30: 30
            case .forever: nil
            }
        }
    }

    public static let maxFramesRange = 2...50
    public static let holdThresholdRange: ClosedRange<TimeInterval> = 0.15...0.5
    /// The reveal comes at least this long after the hold threshold.
    public static let minimumRevealAfterThreshold: TimeInterval = 0.2
    public static let maximumHoldReveal: TimeInterval = 1.5
    public static let doubleTapWindowRange: ClosedRange<TimeInterval> = 0.2...0.5
    public static let fullLongEdge = 1920
    public static let compactLongEdge = 1568
    public static var defaultSaveLocation: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Pictures/Flipbook")
    }

    public var triggerKey: TriggerKey = .rightCommand
    public var sounds = true
    public var launchAtLogin = true
    public var recordTarget: RecordTarget = .cursorScreen
    public var maxFrames = 20
    /// Long edge 1568 px instead of 1920.
    public var compactFrames = false
    public var captionStrip = true
    public var clickMarkers = true
    public var saveLocation: URL = Settings.defaultSaveLocation
    public var retention: Retention = .days30
    public var holdThreshold: TimeInterval = 0.25
    public var holdReveal: TimeInterval = 0.8
    public var doubleTapWindow: TimeInterval = 0.3
    public var saveRawSessions = false

    public init() {}

    /// Every value within its range. The reveal follows the clamped hold threshold.
    public func clamped() -> Settings {
        var settings = self
        settings.maxFrames = maxFrames.clamped(to: Self.maxFramesRange)
        settings.holdThreshold = holdThreshold.clamped(to: Self.holdThresholdRange)
        settings.holdReveal = holdReveal.clamped(
            to: settings.holdThreshold + Self.minimumRevealAfterThreshold...Self.maximumHoldReveal)
        settings.doubleTapWindow = doubleTapWindow.clamped(to: Self.doubleTapWindowRange)
        return settings
    }

    public var gestureConfig: GestureConfig {
        var config = GestureConfig()
        config.holdThreshold = holdThreshold
        config.holdReveal = holdReveal
        config.doubleTapWindow = doubleTapWindow
        return config
    }

    public var longEdge: Int { compactFrames ? Self.compactLongEdge : Self.fullLongEdge }

    /// Missing or unreadable values fall back to their defaults one by one, so a settings file from
    /// another version keeps everything it can.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Settings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        triggerKey = value(.triggerKey, defaults.triggerKey)
        sounds = value(.sounds, defaults.sounds)
        launchAtLogin = value(.launchAtLogin, defaults.launchAtLogin)
        recordTarget = value(.recordTarget, defaults.recordTarget)
        maxFrames = value(.maxFrames, defaults.maxFrames)
        compactFrames = value(.compactFrames, defaults.compactFrames)
        captionStrip = value(.captionStrip, defaults.captionStrip)
        clickMarkers = value(.clickMarkers, defaults.clickMarkers)
        saveLocation = value(.saveLocation, defaults.saveLocation)
        retention = value(.retention, defaults.retention)
        holdThreshold = value(.holdThreshold, defaults.holdThreshold)
        holdReveal = value(.holdReveal, defaults.holdReveal)
        doubleTapWindow = value(.doubleTapWindow, defaults.doubleTapWindow)
        saveRawSessions = value(.saveRawSessions, defaults.saveRawSessions)
    }
}

/// Settings persisted as one JSON blob in UserDefaults, clamped on the way in and out.
/// Used on the main thread.
public final class SettingsStore: @unchecked Sendable {
    public static let key = "settings.v1"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Unreadable data reads as the defaults.
    public var settings: Settings {
        get {
            guard let data = defaults.data(forKey: Self.key),
                  let settings = try? JSONDecoder().decode(Settings.self, from: data)
            else { return Settings() }
            return settings.clamped()
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue.clamped()) else { return }
            defaults.set(data, forKey: Self.key)
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
