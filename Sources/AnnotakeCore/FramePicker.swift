import Foundation

/// Decides which frames to keep while recording (spec §5.3–5.5): triggers, settling, keep decisions,
/// attaching actions to the screen they happened on, and the final fit to the cap.
public struct FramePicker: Sendable {
    private struct Pending {
        var reason: KeepReason
        var since: TimeInterval
    }

    private struct TypingRun {
        var field: ElementLabel?
        var lastKey: TimeInterval
    }

    private struct ScrollRun {
        var accumulated: Double
        var last: TimeInterval
    }

    private let config: PickerConfig
    private let contextSource: ContextSource
    private var tracker: ChangeTracker
    private var kept: [KeptFrame] = []
    private var latest: FrameSample?
    private var lastMotion = -TimeInterval.infinity
    private var pending: Pending?
    private var context: FrameContext
    /// Actions that arrived before the first frame.
    private var buffered: [StepAction] = []
    private var typing: TypingRun?
    private var scroll: ScrollRun?
    /// The frame on screen at the latest input that has a low keep bar: a mouse-down, the first key of
    /// a typing run, a commit, or a switch. A settled frame that differs from it clears the low bar,
    /// which catches a change right under a pointer that stayed put (spec §5.3).
    private var inputBaseline: FrameSample?
    private var stopAt: TimeInterval?
    private var finished = false
    private var candidateCount = 0
    private var stopTime: TimeInterval = 0

    public init(geometry: CaptureGeometry, config: PickerConfig = PickerConfig(), initialContext: FrameContext,
                contextSource: ContextSource = .focus) {
        self.config = config
        self.contextSource = contextSource
        self.tracker = ChangeTracker(geometry: geometry, config: config)
        self.context = initialContext
    }

    public var isFinished: Bool { finished }

    /// Candidates so far.
    public var keptFrames: [KeptFrame] { kept }

    public mutating func ingest(_ frame: FrameSample) -> [PickerOutput] {
        guard !finished else { return [] }
        let change = tracker.observe(frame, previous: latest, countTowardBusy: scroll == nil)
        if change.motion { lastMotion = frame.time }
        latest = frame

        if kept.isEmpty {
            let out = keep(frame, .start)
            kept[0].actions += buffered
            buffered = []
            return out
        }
        if pending == nil && stopAt == nil {
            evaluateVisualTrigger(now: frame.time)
        }
        return []
    }

    public mutating func ingest(_ event: InputEvent) -> [PickerOutput] {
        guard !finished else { return [] }
        let t = event.time
        switch event.kind {
        case let .mouseDown(point, target, button, clickCount):
            typing = nil
            scroll = nil
            let out = attach(.clicked(target: target, at: point, button: button, clickCount: clickCount))
            inputBaseline = latest
            return out
        case .mouseUp:
            setPending(.click, t)
            return []
        case .keyTyped(let field):
            scroll = nil
            var out: [PickerOutput] = []
            if typing == nil || typing?.field != field {
                out = attach(.typed(field: field))
                inputBaseline = latest
            }
            typing = TypingRun(field: field, lastKey: t)
            return out
        case .keyReturn:
            return commit(.pressedReturn, t)
        case .keyEscape:
            return commit(.pressedEscape, t)
        case .shortcut(let shortcut):
            return commit(.pressedShortcut(shortcut), t)
        case .scroll(let fraction):
            typing = nil
            return scrolled(by: fraction, t)
        case .switched(let newContext):
            typing = nil
            scroll = nil
            let out = attach(.switched(to: newContext))
            inputBaseline = latest
            if contextSource == .focus { context = newContext }
            setPending(.switchApp, t)
            return out
        case .titleChanged(let window):
            context.window = window
            return []
        }
    }

    /// Call every 50 ms while recording and while finishing.
    public mutating func tick(now: TimeInterval) -> [PickerOutput] {
        guard !finished else { return [] }
        tracker.advance(to: now)
        var out: [PickerOutput] = []

        if let run = typing, now - run.lastKey >= config.typingPause {
            typing = nil
            setPending(.typing, now)
        }
        if let run = scroll, now - run.last >= config.scrollEndDelay {
            scroll = nil
            setPending(.scroll, now)
        }
        // Catches small changes on a static screen that sends no new frames.
        if pending == nil && stopAt == nil {
            evaluateVisualTrigger(now: now)
        }

        if let trigger = pending, let latest {
            let quiet = now - max(lastMotion, trigger.since)
            if quiet >= config.settleQuiet || now - trigger.since >= config.settleTimeout {
                if isNew(latest) && meetsBar(latest, reason: trigger.reason) {
                    out += keep(latest, trigger.reason)
                }
                pending = nil
            }
        }

        if let stopAt {
            let quiet = now - max(lastMotion, stopAt)
            if quiet >= config.settleQuiet || now - stopAt >= config.stopSettleTimeout {
                if let latest, isNew(latest), meetsBar(latest, reason: pending?.reason ?? .stop) {
                    out += keep(latest, .stop)
                }
                pending = nil
                finished = true
            }
        }
        return out
    }

    /// Starts finishing: the picker keeps ticking until the screen settles, then `isFinished` turns true.
    public mutating func stop(at t: TimeInterval) {
        guard stopAt == nil else { return }
        stopAt = t
        stopTime = t
        // An open typing or scroll run becomes a trigger, so its final state gets the low bar.
        if typing != nil {
            typing = nil
            setPending(.typing, t)
        }
        if scroll != nil {
            scroll = nil
            setPending(.scroll, t)
        }
        if kept.isEmpty { finished = true }
    }

    public func result() -> PickResult {
        precondition(finished, "result() needs a finished picker")
        let cap = min(max(config.maxFrames, 2), 50)
        let fitted = CapFitter.fit(kept, cap: cap, config: config, difference: tracker.settledDifference)
        return PickResult(frames: fitted.kept.map(PickedFrame.init), candidateCount: candidateCount, duration: stopTime)
    }

    // MARK: - Triggers

    private mutating func evaluateVisualTrigger(now: TimeInterval) {
        guard let latest, let last = kept.last, latest.index != last.frameIndex else { return }
        let d = tracker.difference(last.sample, latest).fraction
        if d >= config.visualTriggerFraction
            || (d >= config.keepFraction && now - last.time >= config.quietKeepInterval) {
            pending = Pending(reason: .visual, since: now)
        }
    }

    /// Merges into any pending trigger, keeping the stronger reason (the newer one on a tie).
    private mutating func setPending(_ reason: KeepReason, _ t: TimeInterval) {
        if let current = pending, Self.strength(current.reason) > Self.strength(reason) {
            pending = Pending(reason: current.reason, since: t)
        } else {
            pending = Pending(reason: reason, since: t)
        }
    }

    private static func strength(_ reason: KeepReason) -> Int {
        switch reason {
        case .switchApp: 4
        case .click, .commit: 3
        case .typing: 2
        case .scroll: 1
        case .visual, .start, .beforeAction, .stop: 0
        }
    }

    /// Reasons where a single changed tile is enough to keep the settled frame.
    private static func hasLowBar(_ reason: KeepReason) -> Bool {
        switch reason {
        case .click, .commit, .switchApp, .typing: true
        case .start, .beforeAction, .scroll, .visual, .stop: false
        }
    }

    private func meetsBar(_ frame: FrameSample, reason: KeepReason) -> Bool {
        guard let last = kept.last else { return true }
        let d = tracker.difference(last.sample, frame)
        if d.fraction >= config.keepFraction { return true }
        guard Self.hasLowBar(reason) else { return false }
        if d.changedTiles >= config.minChangedTilesAfterInput { return true }
        // The pointer sat in the same place at the input, so this sees a change right under it.
        guard let inputBaseline, inputBaseline.index != frame.index else { return false }
        return tracker.difference(inputBaseline, frame).changedTiles >= config.minChangedTilesAfterInput
    }

    /// True when the frame isn't already the last kept one.
    private func isNew(_ frame: FrameSample) -> Bool {
        guard let last = kept.last else { return true }
        return frame.index != last.frameIndex
    }

    // MARK: - Actions

    private mutating func commit(_ action: StepAction, _ t: TimeInterval) -> [PickerOutput] {
        typing = nil
        scroll = nil
        let out = attach(action)
        inputBaseline = latest
        setPending(.commit, t)
        return out
    }

    private mutating func scrolled(by fraction: Double, _ t: TimeInterval) -> [PickerOutput] {
        var out: [PickerOutput] = []
        var run = scroll ?? ScrollRun(accumulated: 0, last: t)
        if scroll == nil {
            out += attach(.scrolled)
        }
        run.accumulated += abs(fraction)
        run.last = t
        if run.accumulated >= config.scrollKeepFraction {
            run.accumulated = 0
            if let latest, let last = kept.last, latest.index != last.frameIndex,
               tracker.difference(last.sample, latest).fraction >= config.keepFraction {
                out += keep(latest, .scroll)
            }
        }
        scroll = run
        return out
    }

    /// Attaches the action to the screen it happened on (spec §5.4). If the screen changed since
    /// the last kept frame, the latest frame is kept first and the action goes on it.
    private mutating func attach(_ action: StepAction) -> [PickerOutput] {
        guard let latest, let last = kept.last else {
            buffered.append(action)
            return []
        }
        if latest.index == last.frameIndex || tracker.difference(last.sample, latest).fraction < config.keepFraction {
            addToLastKept(action)
            return []
        }
        let out = keep(latest, .beforeAction)
        kept[kept.count - 1].actions.append(action)
        pending = nil
        return out
    }

    /// Appends the action, except that a double-click replaces the single click it grew from.
    private mutating func addToLastKept(_ action: StepAction) {
        let last = kept.count - 1
        if case let .clicked(_, point, button, clickCount) = action, clickCount >= 2,
           case let .clicked(_, previousPoint, previousButton, _)? = kept[last].actions.last,
           previousButton == button {
            let dx = point.x - previousPoint.x, dy = point.y - previousPoint.y
            if (dx * dx + dy * dy).squareRoot() <= config.doubleClickRadius {
                kept[last].actions[kept[last].actions.count - 1] = action
                return
            }
        }
        kept[last].actions.append(action)
    }

    // MARK: - Keeping

    private mutating func keep(_ frame: FrameSample, _ reason: KeepReason) -> [PickerOutput] {
        kept.append(KeptFrame(sample: frame, context: context, actions: [], reason: reason))
        candidateCount += 1
        var out: [PickerOutput] = [.persist(frameIndex: frame.index)]
        if kept.count > config.candidatePoolLimit {
            let fitted = CapFitter.fit(kept, cap: config.candidatePoolTrimTo, config: config,
                                       difference: tracker.settledDifference)
            kept = fitted.kept
            if !fitted.removed.isEmpty {
                out.append(.discard(frameIndices: fitted.removed))
            }
        }
        return out
    }
}
