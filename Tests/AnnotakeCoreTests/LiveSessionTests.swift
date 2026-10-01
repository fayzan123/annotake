import AnnotakeCore
import Foundation
import Testing

struct LiveSessionTests {
    let save = ElementLabel(role: "button", label: "Save")
    let point = PixelPoint(x: 100, y: 100)
    let context = FrameContext(app: "TestApp", window: "Main")

    func mouseDown(_ time: TimeInterval, on target: ElementLabel?) -> InputEvent {
        InputEvent(time: time, kind: .mouseDown(point: point, target: target, button: .left, clickCount: 1))
    }

    func mouseUp(_ time: TimeInterval) -> InputEvent {
        InputEvent(time: time, kind: .mouseUp(point: point))
    }

    /// Advances one tick at a time until the session finishes; false after `limit` calls.
    @discardableResult
    func finish(_ live: inout LiveSession, limit: Int = 100, outputs: inout [LiveSession.Output]) -> Bool {
        var calls = 0
        while !live.isFinished {
            guard calls < limit else { return false }
            outputs += live.advance(to: live.nextTickTime)
            calls += 1
        }
        return true
    }

    /// The session run through a PickerHarness, as in ReplayTests.replayMatchesHarness.
    func harnessResult(_ session: RawSession) -> PickResult {
        var harness = PickerHarness(geometry: session.geometry, context: session.initialContext)
        var frames = session.frames[...]
        for event in session.events {
            while let frame = frames.first, frame.time <= event.time {
                harness.frame(frame)
                frames = frames.dropFirst()
            }
            harness.event(event)
        }
        for frame in frames {
            harness.frame(frame)
        }
        harness.stop(at: session.stopTime)
        return harness.picker.result()
    }

    @Test func matchesHarnessOnClickFlow() {
        let session = Scenes.clickFlow()
        var live = LiveSession(geometry: session.geometry, initialContext: session.initialContext)
        for item in session.mergedItems {
            switch item {
            case .frame(let frame): _ = live.receive(frame)
            case .event(let event): _ = live.receive(event)
            }
        }
        var outputs = live.stop(at: 8.0)
        #expect(finish(&live, outputs: &outputs))

        let result = live.result()
        #expect(result == harnessResult(session))
        #expect(result.frames.map(\.frameIndex) == [0, 1, 2, 5, 6])
    }

    @Test func slotHoldsLaterItems() {
        var scene = SceneBuilder()
        var live = LiveSession(geometry: scene.geometry, initialContext: context)
        _ = live.receive(scene.frame(at: 0.0))
        var (slot, outputs) = live.reserve(mouseDown(1.0, on: nil))
        outputs += live.receive(mouseUp(1.05))
        let f1 = scene.frame(at: 1.2, set: .tiles(0..<12))
        outputs += live.receive(f1)
        outputs += live.advance(to: 1.3)
        #expect(outputs.tookEvents.isEmpty)
        #expect(!outputs.contains(.tookFrame(f1)))
        #expect(live.logicalTime < 1.0)

        let filled = live.fill(slot, with: mouseDown(1.0, on: save).kind, now: 1.3)
        #expect(filled.took == [.tookEvent(mouseDown(1.0, on: save)), .tookEvent(mouseUp(1.05)), .tookFrame(f1)])
    }

    @Test func unfilledSlotTimesOut() {
        var live = LiveSession(geometry: SceneBuilder().geometry, initialContext: context)
        let placeholder = mouseDown(1.0, on: nil)
        let (slot, reserved) = live.reserve(placeholder)
        #expect(reserved.tookEvents.isEmpty)
        #expect(live.advance(to: 1.49).tookEvents.isEmpty)
        #expect(live.advance(to: 1.5).tookEvents == [placeholder])
        #expect(live.fill(slot, with: mouseDown(1.0, on: save).kind, now: 1.6) == [])
    }

    @Test func stampsStrictlyIncrease() {
        var scene = SceneBuilder()
        var live = LiveSession(geometry: scene.geometry, initialContext: context)
        let bump = LiveSession.stampBump

        #expect(live.receive(scene.frame(at: 1.0)).tookFrames.map(\.time) == [1.0])
        #expect(live.receive(InputEvent(time: 1.0, kind: .keyReturn)).tookEvents.map(\.time) == [1.0 + bump])
        #expect(live.receive(scene.frame(at: 0.9)).tookFrames.map(\.time) == [1.0 + 2 * bump])
    }

    @Test func stopWaitsForEarlierSlot() {
        var scene = SceneBuilder()
        var live = LiveSession(geometry: scene.geometry, initialContext: context)
        _ = live.receive(scene.frame(at: 0))
        var (slot, outputs) = live.reserve(mouseDown(2.0, on: nil))
        outputs += live.stop(at: 2.1)
        #expect(!live.isFinished)
        #expect(live.stopTime == 2.1)
        outputs += live.advance(to: 2.4)
        #expect(!live.isFinished)

        outputs += live.fill(slot, with: mouseDown(2.0, on: save).kind, now: 2.45)
        #expect(finish(&live, limit: 30, outputs: &outputs))
        let saveClick = StepAction.clicked(target: save, at: point, button: .left, clickCount: 1)
        #expect(live.result().frames.first?.actions.contains(saveClick) == true)
    }

    @Test func framesAfterStopStillSettle() {
        var scene = SceneBuilder()
        var live = LiveSession(geometry: scene.geometry, initialContext: context)
        _ = live.receive(scene.frame(at: 0.0))
        _ = live.receive(mouseDown(2.9, on: save))
        _ = live.receive(mouseUp(2.95))
        _ = live.stop(at: 3.0)
        _ = live.receive(scene.frame(at: 3.1, set: .tiles(0..<12)))
        _ = live.advance(to: 3.6)

        #expect(live.isFinished)
        guard live.isFinished else { return }
        let last = live.result().frames.last
        #expect(last?.frameIndex == 1)
        #expect(last?.reason == .click)
    }

    @Test(arguments: 1...20)
    func recordingReplaysIdentically(seed: Int) throws {
        enum Call {
            case frame(FrameSample)
            case event(InputEvent)
            case reserve(Int, InputEvent)
            case fill(Int, InputEventKind)
            case stop(TimeInterval)
            case advance
        }
        let scene = Scenes.clickFlow()
        var random = SeededRandom(seed: UInt64(seed))
        var calls: [(wall: TimeInterval, call: Call)] = []
        var slotCount = 0
        var previousEvent: InputEvent?

        func reserveWithoutLabel(_ event: InputEvent, placeholder: InputEventKind) {
            let id = slotCount
            slotCount += 1
            calls.append((event.time, .reserve(id, InputEvent(time: event.time, kind: placeholder))))
            calls.append((event.time + random.next(in: 0..<0.4), .fill(id, event.kind)))
        }

        for item in scene.mergedItems {
            switch item {
            case .frame(let frame):
                calls.append((frame.time, .frame(frame)))
            case .event(let event):
                switch event.kind {
                case let .mouseDown(point, _, button, clickCount):
                    reserveWithoutLabel(event, placeholder: .mouseDown(point: point, target: nil, button: button,
                                                                      clickCount: clickCount))
                case .keyTyped(let field):
                    let continuesRun = previousEvent.map {
                        $0.kind == .keyTyped(field: field) && event.time - $0.time < PickerConfig().typingPause
                    } ?? false
                    if continuesRun {
                        calls.append((event.time, .event(event)))
                    } else {
                        reserveWithoutLabel(event, placeholder: .keyTyped(field: nil))
                    }
                default:
                    calls.append((event.time, .event(event)))
                }
                previousEvent = event
            }
        }
        calls.append((scene.stopTime, .stop(scene.stopTime)))
        var wall = 0.0
        while true {
            wall += random.next(in: 0.02..<0.08)
            guard wall < scene.stopTime else { break }
            calls.append((wall, .advance))
        }
        let ordered = calls.enumerated()
            .sorted { ($0.element.wall, $0.offset) < ($1.element.wall, $1.offset) }
            .map(\.element)

        var live = LiveSession(geometry: scene.geometry, initialContext: scene.initialContext)
        var slots: [Int: LiveSession.Slot] = [:]
        var outputs: [LiveSession.Output] = []
        for (wall, call) in ordered {
            switch call {
            case .frame(let frame): outputs += live.receive(frame)
            case .event(let event): outputs += live.receive(event)
            case let .reserve(id, placeholder):
                let (slot, produced) = live.reserve(placeholder)
                slots[id] = slot
                outputs += produced
            case let .fill(id, kind): outputs += live.fill(try #require(slots[id]), with: kind, now: wall)
            case .stop(let time): outputs += live.stop(at: time)
            case .advance: outputs += live.advance(to: wall)
            }
        }
        try #require(finish(&live, outputs: &outputs))

        let recorded = RawSession(geometry: scene.geometry, initialContext: scene.initialContext,
                                  frames: outputs.tookFrames, events: outputs.tookEvents,
                                  stopTime: try #require(live.stopTime))
        #expect(SessionReplayer.run(recorded).result == live.result())
        #expect(live.result() == SessionReplayer.run(scene).result)
    }
}

extension [LiveSession.Output] {
    var tookFrames: [FrameSample] {
        compactMap { if case .tookFrame(let frame) = $0 { frame } else { nil } }
    }

    var tookEvents: [InputEvent] {
        compactMap { if case .tookEvent(let event) = $0 { event } else { nil } }
    }

    /// Only the took-frame and took-event outputs, in order.
    var took: [LiveSession.Output] {
        filter {
            switch $0 {
            case .tookFrame, .tookEvent: true
            case .persist, .discard: false
            }
        }
    }
}
