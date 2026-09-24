import Foundation

/// Fits kept frames to the cap by greedy Visvalingam–Whyatt-style removal (spec §5.5).
public enum CapFitter {
    /// Removes the lowest-cost interior frame until at most max(2, cap) remain.
    /// A removed frame's actions are appended to the previous remaining frame.
    /// Returns the remaining frames in time order, and the removed frame indices in removal order.
    public static func fit(_ frames: [KeptFrame], cap: Int, config: PickerConfig,
                           difference: (FrameSample, FrameSample) -> Difference) -> (kept: [KeptFrame], removed: [Int]) {
        let cap = max(2, cap)
        guard frames.count > cap else { return (frames, []) }

        var frames = frames
        let last = frames.count - 1
        let duration = max(frames[last].time - frames[0].time, 0.001)
        // The remaining frames as a linked list over positions; position `last + 1` is the end.
        var previous = Array(-1..<last)
        var next = Array(1...last + 1)

        func cost(_ i: Int) -> Double {
            let p = previous[i], n = next[i]
            func d(_ a: Int, _ b: Int) -> Double { difference(frames[a].sample, frames[b].sample).fraction }
            return d(p, i) + d(i, n) - d(p, n)
                + bonus(for: frames[i], config: config)
                + config.timeGapWeight * (frames[n].time - frames[p].time) / duration
        }

        var costs = [Double](repeating: 0, count: frames.count)
        for i in 1..<last {
            costs[i] = cost(i)
        }

        var remaining = frames.count
        var removed: [Int] = []
        while remaining > cap {
            // Cheapest interior frame; on ties, the earliest.
            var cheapest = next[0]
            var i = next[cheapest]
            while i < last {
                if costs[i] < costs[cheapest] { cheapest = i }
                i = next[i]
            }

            let p = previous[cheapest], n = next[cheapest]
            frames[p].actions.append(contentsOf: frames[cheapest].actions)
            next[p] = n
            previous[n] = p
            removed.append(frames[cheapest].frameIndex)
            remaining -= 1

            // Only the two new neighbors changed; the left one may also have gained actions.
            if p > 0 { costs[p] = cost(p) }
            if n < last { costs[n] = cost(n) }
        }

        var kept: [KeptFrame] = []
        kept.reserveCapacity(remaining)
        var position = 0
        while position <= last {
            kept.append(frames[position])
            position = next[position]
        }
        return (kept, removed)
    }

    /// The largest bonus that the frame's keep reason or any of its actions earns, or 0.
    public static func bonus(for frame: KeptFrame, config: PickerConfig) -> Double {
        var best: Double
        switch frame.reason {
        case .click: best = config.bonusClick
        case .commit: best = config.bonusCommit
        case .switchApp: best = config.bonusSwitch
        case .scroll: best = config.bonusScroll
        case .start, .beforeAction, .typing, .visual, .stop: best = 0
        }
        for action in frame.actions {
            switch action {
            case .clicked: best = max(best, config.bonusClick)
            case .pressedReturn, .pressedEscape, .pressedShortcut: best = max(best, config.bonusCommit)
            case .switched: best = max(best, config.bonusSwitch)
            case .scrolled: best = max(best, config.bonusScroll)
            case .typed: break
            }
        }
        return best
    }
}
