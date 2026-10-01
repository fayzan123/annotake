import Foundation

/// The only way frames and input reach the frame picker, live and in replay (spec §6.1).
///
/// Every item is stamped when it arrives, and stamps only increase, so arrival order is time order.
/// Items wait in one first-in-first-out queue. An event that needs an Accessibility label reserves a
/// slot; items behind an unfilled slot wait for it, for at most `slotTimeout`. Ticks fall on a fixed
/// 50 ms grid and run in time order with the items, so a raw session of what the picker took replays
/// exactly as it ran live.
public struct LiveSession: Sendable {
    public static let tickInterval: TimeInterval = 0.05
    public static let slotTimeout: TimeInterval = 0.5
    public static let stampBump: TimeInterval = 0.000_001

    /// A reserved place in the queue for an event whose label is still being looked up.
    public struct Slot: Hashable, Sendable {
        fileprivate let id: Int
    }

    public enum Output: Sendable, Equatable {
        case persist(frameIndex: Int, reason: KeepReason, at: TimeInterval)
        case discard(frameIndices: [Int], at: TimeInterval)
        /// The picker ingested this frame; its time is the effective stamp.
        case tookFrame(FrameSample)
        /// The picker ingested this event; a slot's event carries its final kind.
        case tookEvent(InputEvent)
    }

    private enum Item: Sendable {
        case frame(FrameSample)
        case event(InputEvent)
        case slot(id: Int, placeholder: InputEvent, filled: InputEventKind?)
        case stop(TimeInterval)

        var time: TimeInterval {
            switch self {
            case .frame(let frame): frame.time
            case .event(let event): event.time
            case .slot(_, let placeholder, _): placeholder.time
            case .stop(let time): time
            }
        }

        var isUnfilledSlot: Bool {
            if case .slot(_, _, nil) = self { return true }
            return false
        }
    }

    private var picker: FramePicker
    private var queue: [Item] = []
    private var nextSlotID = 0
    private var nextTick = 0
    private var persisted = 0
    /// The latest stamp given, and the unbumped stamp it was bumped from, with the bump count. A bumped
    /// stamp is computed from the anchor rather than from the previous stamp, so n bumps past t land
    /// exactly on t + n · stampBump instead of drifting by rounding.
    private var lastStamp = -TimeInterval.infinity
    private var stampAnchor = -TimeInterval.infinity
    private var bumps = 0

    public private(set) var stopTime: TimeInterval?
    /// The last tick or item processed; -infinity before any.
    public private(set) var logicalTime = -TimeInterval.infinity

    public init(geometry: CaptureGeometry, config: PickerConfig = PickerConfig(), initialContext: FrameContext,
                contextSource: ContextSource = .focus) {
        picker = FramePicker(geometry: geometry, config: config, initialContext: initialContext,
                             contextSource: contextSource)
    }

    public var isFinished: Bool { picker.isFinished }

    /// Frames kept so far, for the pill.
    public var candidateCount: Int { persisted }

    /// The time of the next tick not yet run.
    public var nextTickTime: TimeInterval { Double(nextTick) * Self.tickInterval }

    public func result() -> PickResult {
        precondition(isFinished, "result() needs a finished session")
        return picker.result()
    }

    public mutating func receive(_ frame: FrameSample) -> [Output] {
        guard !isFinished else { return [] }
        let time = stamp(frame.time)
        let stamped = time == frame.time ? frame : FrameSample(
            index: frame.index, time: time, signature: frame.signature,
            dirtyRects: frame.dirtyRects, cursor: frame.cursor)
        queue.append(.frame(stamped))
        return drain(horizon: time)
    }

    public mutating func receive(_ event: InputEvent) -> [Output] {
        guard !isFinished else { return [] }
        let time = stamp(event.time)
        queue.append(.event(InputEvent(time: time, kind: event.kind)))
        return drain(horizon: time)
    }

    /// Queues the unlabeled version of an event; `fill` replaces it with the labeled one.
    public mutating func reserve(_ placeholder: InputEvent) -> (slot: Slot, outputs: [Output]) {
        let slot = Slot(id: nextSlotID)
        nextSlotID += 1
        guard !isFinished else { return (slot, []) }
        let time = stamp(placeholder.time)
        queue.append(.slot(id: slot.id, placeholder: InputEvent(time: time, kind: placeholder.kind), filled: nil))
        return (slot, drain(horizon: time))
    }

    /// Does nothing when the slot has already been released, filled or timed out.
    public mutating func fill(_ slot: Slot, with kind: InputEventKind, now: TimeInterval) -> [Output] {
        guard !isFinished,
              let position = queue.firstIndex(where: {
                  if case .slot(slot.id, _, nil) = $0 { return true }
                  return false
              }),
              case let .slot(id, placeholder, _) = queue[position]
        else { return [] }
        queue[position] = .slot(id: id, placeholder: placeholder, filled: kind)
        return drain(horizon: now)
    }

    /// Runs ticks up to `now`, and any items that were waiting on a slot that has now timed out.
    public mutating func advance(to now: TimeInterval) -> [Output] {
        guard !isFinished else { return [] }
        return drain(horizon: now)
    }

    /// Queues the stop. When it's reached, ticks up to and including its time run, then the picker
    /// starts finishing; frames that arrive after it still count until the picker settles.
    public mutating func stop(at time: TimeInterval) -> [Output] {
        guard !isFinished, stopTime == nil else { return [] }
        let stamped = stamp(time)
        stopTime = stamped
        queue.append(.stop(stamped))
        return drain(horizon: stamped)
    }

    // MARK: - Queue

    /// A time later than every earlier stamp.
    private mutating func stamp(_ time: TimeInterval) -> TimeInterval {
        if time <= lastStamp {
            bumps += 1
            lastStamp = stampAnchor + Double(bumps) * Self.stampBump
        } else {
            stampAnchor = time
            bumps = 0
            lastStamp = time
        }
        return lastStamp
    }

    private mutating func drain(horizon: TimeInterval) -> [Output] {
        var out: [Output] = []
        while !isFinished {
            guard let head = queue.first else {
                runTicks(through: horizon, into: &out)
                return out
            }
            if head.isUnfilledSlot && horizon - head.time < Self.slotTimeout {
                runTicks(before: head.time, into: &out)
                return out
            }
            runTicks(before: head.time, into: &out)
            guard !isFinished else { break }
            queue.removeFirst()
            process(head, into: &out)
        }
        queue.removeAll()
        return out
    }

    private mutating func process(_ item: Item, into out: inout [Output]) {
        switch item {
        case .frame(let frame):
            out.append(.tookFrame(frame))
            let produced = picker.ingest(frame)
            logicalTime = frame.time
            map(produced, at: frame.time, into: &out)
        case .event(let event):
            ingest(event, into: &out)
        case let .slot(_, placeholder, filled):
            ingest(InputEvent(time: placeholder.time, kind: filled ?? placeholder.kind), into: &out)
        case .stop(let time):
            runTicks(through: time, into: &out)
            picker.stop(at: time)
            logicalTime = time
        }
    }

    private mutating func ingest(_ event: InputEvent, into out: inout [Output]) {
        out.append(.tookEvent(event))
        let produced = picker.ingest(event)
        logicalTime = event.time
        map(produced, at: event.time, into: &out)
    }

    /// Runs every tick with a time strictly before `time`.
    private mutating func runTicks(before time: TimeInterval, into out: inout [Output]) {
        while !isFinished && nextTickTime < time {
            tick(into: &out)
        }
    }

    /// Runs every tick with a time at or before `time`.
    private mutating func runTicks(through time: TimeInterval, into out: inout [Output]) {
        while !isFinished && nextTickTime <= time {
            tick(into: &out)
        }
    }

    private mutating func tick(into out: inout [Output]) {
        let now = nextTickTime
        nextTick += 1
        let produced = picker.tick(now: now)
        logicalTime = now
        map(produced, at: now, into: &out)
    }

    /// Picker outputs as session outputs; a persist carries the reason of the frame it just kept.
    private mutating func map(_ produced: [PickerOutput], at time: TimeInterval, into out: inout [Output]) {
        for output in produced {
            switch output {
            case .persist(let frameIndex):
                persisted += 1
                out.append(.persist(frameIndex: frameIndex, reason: picker.keptFrames.last!.reason, at: time))
            case .discard(let frameIndices):
                out.append(.discard(frameIndices: frameIndices, at: time))
            }
        }
    }
}
