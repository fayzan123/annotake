import AnnotakeCore
import Foundation
import Testing

/// Drives a FramePicker the way the app will: frames and events as they arrive, and a tick every 50 ms.
/// Tick times are `Double(k) * 0.05` from an integer counter, never accumulated.
struct PickerHarness {
    static let tickInterval: TimeInterval = 0.05

    var picker: FramePicker
    private(set) var outputs: [(time: TimeInterval, output: PickerOutput)] = []
    /// The tick time at which the picker finished, if it has.
    private(set) var finishedAt: TimeInterval?
    private var nextTick = 0

    init(geometry: CaptureGeometry, config: PickerConfig = PickerConfig(),
         context: FrameContext = FrameContext(app: "TestApp", window: "Main"), contextSource: ContextSource = .focus) {
        picker = FramePicker(geometry: geometry, config: config, initialContext: context, contextSource: contextSource)
    }

    /// Ticks at k*0.05 for all k*0.05 < f.time, then ingests the frame.
    mutating func frame(_ f: FrameSample) {
        tick(before: f.time)
        record(f.time, picker.ingest(f))
    }

    /// Ticks at k*0.05 for all k*0.05 < e.time, then ingests the event.
    mutating func event(_ e: InputEvent) {
        tick(before: e.time)
        record(e.time, picker.ingest(e))
    }

    /// Ticks at k*0.05 for all k*0.05 <= t.
    mutating func run(until t: TimeInterval) {
        while nextTickTime <= t {
            tickOnce()
        }
    }

    /// run(until: t), picker.stop(at: t), then ticks until the picker finishes; more than 2 s is a failure.
    mutating func stop(at t: TimeInterval) {
        run(until: t)
        picker.stop(at: t)
        if picker.isFinished && finishedAt == nil { finishedAt = t }
        while !picker.isFinished {
            guard nextTickTime <= t + 2 else {
                Issue.record("picker didn't finish within 2 s of stop(at: \(t))")
                return
            }
            tickOnce()
        }
    }

    /// When the frame was kept, from its `.persist` output.
    func keptTime(ofFrame index: Int) -> TimeInterval? {
        outputs.first { $0.output == .persist(frameIndex: index) }?.time
    }

    private var nextTickTime: TimeInterval { Double(nextTick) * Self.tickInterval }

    private mutating func tick(before t: TimeInterval) {
        while nextTickTime < t {
            tickOnce()
        }
    }

    private mutating func tickOnce() {
        let now = nextTickTime
        nextTick += 1
        record(now, picker.tick(now: now))
        if picker.isFinished && finishedAt == nil { finishedAt = now }
    }

    private mutating func record(_ time: TimeInterval, _ produced: [PickerOutput]) {
        outputs += produced.map { (time: time, output: $0) }
    }
}
