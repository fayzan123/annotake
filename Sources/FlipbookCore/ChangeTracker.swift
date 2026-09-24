import Foundation

/// How many tiles differ between two frames, out of the tiles not excluded (spec §5.2's D).
public struct Difference: Sendable, Equatable {
    public let changedTiles: Int
    public let consideredTiles: Int

    public init(changedTiles: Int, consideredTiles: Int) {
        self.changedTiles = changedTiles
        self.consideredTiles = consideredTiles
    }

    public var fraction: Double {
        consideredTiles == 0 ? 0 : Double(changedTiles) / Double(consideredTiles)
    }
}

/// What changed between a frame and the one before it.
public struct FrameChange: Sendable, Equatable {
    public let changedTiles: Set<Int>
    /// At least `motionMinTiles` changed tiles remain after the cursor, caret and busy exclusions.
    public let motion: Bool
}

/// Tracks which tiles change from frame to frame, and which to ignore: tiles under the cursor,
/// a blinking caret, and busy regions such as spinners and video (spec §5.2).
public struct ChangeTracker: Sendable {
    private struct HistoryEntry {
        let time: TimeInterval
        let changed: Set<Int>
    }

    private let geometry: CaptureGeometry
    private let config: PickerConfig

    public private(set) var busyTiles: Set<Int> = []
    public private(set) var everBusyTiles: Set<Int> = []
    public private(set) var caretTiles: Set<Int> = []
    public private(set) var everCaretTiles: Set<Int> = []

    private var lastChangeAt: [Int: TimeInterval] = [:]
    private var caretSeenAt: [Int: TimeInterval] = [:]
    /// Frames within the busy window that count toward busy, oldest first.
    private var history: [HistoryEntry] = []

    public init(geometry: CaptureGeometry, config: PickerConfig) {
        self.geometry = geometry
        self.config = config
    }

    public mutating func observe(_ frame: FrameSample, previous: FrameSample?, countTowardBusy: Bool = true) -> FrameChange {
        advance(to: frame.time)
        guard let previous else { return FrameChange(changedTiles: [], motion: false) }
        let grid = geometry.grid

        let candidates: Set<Int> = frame.dirtyRects.isEmpty
            ? Set(0..<grid.count)
            : Set(frame.dirtyRects.flatMap { grid.tiles(intersecting: $0) })
        let changed = candidates.filter {
            frame.signature.differs(from: previous.signature, tile: $0, threshold: config.tileChangeThreshold)
        }

        // Caret: tiles covered only by thin, tall dirty rects.
        let caretMaxWidth = config.caretMaxWidthPoints * geometry.pixelsPerPoint
        let caretMaxHeight = config.caretMaxHeightPoints * geometry.pixelsPerPoint
        var caretRectTiles = Set<Int>()
        var otherRectTiles = Set<Int>()
        for rect in frame.dirtyRects {
            let isCaretLike = Double(rect.width) <= caretMaxWidth
                && Double(rect.height) <= caretMaxHeight
                && rect.height > rect.width
            if isCaretLike {
                caretRectTiles.formUnion(grid.tiles(intersecting: rect))
            } else {
                otherRectTiles.formUnion(grid.tiles(intersecting: rect))
            }
        }
        let caretOnly = caretRectTiles.subtracting(otherRectTiles)
        for tile in caretOnly.intersection(changed) {
            caretSeenAt[tile] = frame.time
            caretTiles.insert(tile)
            everCaretTiles.insert(tile)
        }

        // Busy: tiles that keep changing. Huge changes and scroll frames don't count.
        for tile in changed {
            lastChangeAt[tile] = frame.time
        }
        if countTowardBusy && Double(changed.count) <= config.busyMaxAreaFraction * Double(grid.count) {
            history.append(HistoryEntry(time: frame.time, changed: changed))
            history.removeAll { $0.time < frame.time - config.busyWindow }
            if history.count >= config.busyMinFrames {
                var counts: [Int: Int] = [:]
                for entry in history {
                    for tile in entry.changed {
                        counts[tile, default: 0] += 1
                    }
                }
                let minimum = config.busyFraction * Double(history.count)
                for (tile, count) in counts where Double(count) >= minimum {
                    busyTiles.insert(tile)
                    everBusyTiles.insert(tile)
                }
            }
        }

        var excluded = busyTiles.union(caretOnly)
        excluded.formUnion(cursorTiles(frame))
        excluded.formUnion(cursorTiles(previous))
        let motion = changed.subtracting(excluded).count >= config.motionMinTiles
        return FrameChange(changedTiles: changed, motion: motion)
    }

    /// Releases busy tiles that have been still for `busyRelease`, and caret tiles not seen for `caretMemory`.
    public mutating func advance(to now: TimeInterval) {
        busyTiles = busyTiles.filter { tile in
            guard let changedAt = lastChangeAt[tile] else { return false }
            return now - changedAt < config.busyRelease
        }
        caretTiles = caretTiles.filter { tile in
            guard let seenAt = caretSeenAt[tile] else { return false }
            return now - seenAt < config.caretMemory
        }
    }

    /// D with the exclusions in force right now.
    public func difference(_ a: FrameSample, _ b: FrameSample) -> Difference {
        difference(a, b, masking: busyTiles.union(caretTiles))
    }

    /// D with every tile that was ever busy or a caret during the recording excluded.
    public func settledDifference(_ a: FrameSample, _ b: FrameSample) -> Difference {
        difference(a, b, masking: everBusyTiles.union(everCaretTiles))
    }

    private func difference(_ a: FrameSample, _ b: FrameSample, masking masked: Set<Int>) -> Difference {
        let grid = geometry.grid
        var excluded = masked
        excluded.formUnion(cursorTiles(a))
        excluded.formUnion(cursorTiles(b))
        var changed = 0
        for tile in 0..<grid.count where !excluded.contains(tile) {
            if a.signature.differs(from: b.signature, tile: tile, threshold: config.tileChangeThreshold) {
                changed += 1
            }
        }
        return Difference(changedTiles: changed, consideredTiles: grid.count - excluded.count)
    }

    private func cursorTiles(_ frame: FrameSample) -> [Int] {
        guard let cursor = frame.cursor else { return [] }
        return geometry.grid.tiles(intersecting: cursor)
    }
}
