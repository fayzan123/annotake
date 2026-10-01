import Foundation

/// Every tunable number in frame picking (spec §5), with its spec default.
public struct PickerConfig: Sendable, Equatable, Codable {
    /// A tile changed when the MAD of its 16 signature values exceeds this (0–255 scale).
    public var tileChangeThreshold: Double = 3

    /// A dirty rect at most this size (and taller than wide) is a caret.
    public var caretMaxWidthPoints: Double = 4
    public var caretMaxHeightPoints: Double = 48
    /// Caret tiles stay ignored this long after the caret was last seen.
    public var caretMemory: TimeInterval = 2

    /// Busy tiles: changed in at least `busyFraction` of the frames in the last `busyWindow`,
    /// counting only when there are at least `busyMinFrames` frames.
    public var busyWindow: TimeInterval = 1.5
    public var busyFraction: Double = 0.6
    public var busyMinFrames: Int = 5
    /// A busy tile is released after being still this long.
    public var busyRelease: TimeInterval = 2
    /// Frames changing more than this fraction of tiles don't count toward busy.
    public var busyMaxAreaFraction: Double = 0.5

    /// Motion needs at least this many changed tiles after exclusions.
    public var motionMinTiles: Int = 2

    /// Visual trigger: D ≥ this, or ≥ `keepFraction` once `quietKeepInterval` has passed since the last keep.
    public var visualTriggerFraction: Double = 0.02
    /// A settled frame is kept when D ≥ this.
    public var keepFraction: Double = 0.005
    public var quietKeepInterval: TimeInterval = 10
    /// After click, commit, switch and typing triggers, this many changed tiles are enough to keep.
    public var minChangedTilesAfterInput: Int = 1

    /// A trigger settles after this much quiet, measured from the later of the last motion and the trigger.
    public var settleQuiet: TimeInterval = 0.4
    public var settleTimeout: TimeInterval = 3
    public var stopSettleTimeout: TimeInterval = 1

    public var typingPause: TimeInterval = 1.2
    public var scrollEndDelay: TimeInterval = 0.3
    /// While scrolling, the latest frame is kept each time scrolling moves this many viewports.
    public var scrollKeepFraction: Double = 0.8

    /// A second click within this many pixels of the first counts as the same double-click.
    public var doubleClickRadius: Double = 5

    /// The cap on the final frame count, clamped to 2–50.
    public var maxFrames: Int = 20
    /// When the candidate pool grows past `candidatePoolLimit`, it is trimmed to `candidatePoolTrimTo`.
    public var candidatePoolLimit: Int = 300
    public var candidatePoolTrimTo: Int = 150

    /// Cap-fitting cost terms (spec §5.5).
    public var bonusClick: Double = 0.15
    public var bonusCommit: Double = 0.15
    public var bonusSwitch: Double = 0.30
    public var bonusScroll: Double = 0.05
    public var timeGapWeight: Double = 0.05

    public init() {}
}
