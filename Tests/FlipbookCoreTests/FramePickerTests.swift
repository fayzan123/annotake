import FlipbookCore
import Foundation
import Testing

struct FramePickerTests {
    /// Tick times are Double(k) * 0.05, so "at 2.4" can be a hair either side of the literal.
    let eps = 1e-9
    let save = ElementLabel(role: "button", label: "Save")
    let email = ElementLabel(role: "text field", label: "Email")
    let point = PixelPoint(x: 100, y: 100)

    var saveClick: StepAction { .clicked(target: save, at: point, button: .left, clickCount: 1) }

    func mouseDown(_ time: TimeInterval, at point: PixelPoint? = nil, on target: ElementLabel? = nil,
                   clickCount: Int = 1) -> InputEvent {
        InputEvent(time: time, kind: .mouseDown(point: point ?? self.point, target: target ?? save,
                                                button: .left, clickCount: clickCount))
    }

    func mouseUp(_ time: TimeInterval) -> InputEvent {
        InputEvent(time: time, kind: .mouseUp(point: point))
    }

    func event(_ time: TimeInterval, _ kind: InputEventKind) -> InputEvent {
        InputEvent(time: time, kind: kind)
    }

    /// f0 at 0, the static base screen.
    func start() -> (SceneBuilder, PickerHarness) {
        var scene = SceneBuilder()
        var harness = PickerHarness(geometry: scene.geometry)
        harness.frame(scene.frame(at: 0))
        return (scene, harness)
    }

    /// f0; a click on the Email field at 3.0/3.05 (no visible change); keyTyped ×5 at 4.0–4.4;
    /// frames change tiles 150, 151 and 152 at 4.0, 4.2 and 4.4. Returns the frame at 4.4.
    func typeIntoEmail(_ scene: inout SceneBuilder, _ harness: inout PickerHarness) -> FrameSample {
        harness.event(mouseDown(3.0, on: email))
        harness.event(mouseUp(3.05))
        var last = scene.frame(at: 0)   // replaced below
        for (k, time) in [4.0, 4.1, 4.2, 4.3, 4.4].enumerated() {
            if k % 2 == 0 {
                last = scene.frame(at: time, set: .tiles([150 + k / 2]))
                harness.frame(last)
            }
            harness.event(event(time, .keyTyped(field: email)))
        }
        return last
    }

    @Test func startKeepsFirstFrame() {
        let (_, harness) = start()
        #expect(harness.outputs.map(\.output) == [.persist(frameIndex: 0)])
        #expect(harness.picker.keptFrames.map(\.reason) == [.start])
    }

    @Test func actionsBeforeFirstFrameAttachToIt() {
        var scene = SceneBuilder()
        var harness = PickerHarness(geometry: scene.geometry)
        harness.event(mouseDown(0.0))
        harness.frame(scene.frame(at: 0.05))
        #expect(harness.picker.keptFrames.count == 1)
        #expect(harness.picker.keptFrames[0].actions == [saveClick])
    }

    @Test func clickResultKeptAfterSettle() {
        var (scene, harness) = start()
        harness.event(mouseDown(1.0))
        harness.event(mouseUp(1.05))
        harness.frame(scene.frame(at: 1.2, set: .tiles(0..<12)))

        harness.run(until: 1.55)
        #expect(harness.picker.keptFrames.count == 1)

        harness.run(until: 1.65)
        let kept = harness.picker.keptFrames
        #expect(kept.map(\.frameIndex) == [0, 1])
        #expect(kept.last?.reason == .click)
        #expect(kept[0].actions == [saveClick])
    }

    @Test func settleCountsFromTriggerNotOldMotion() throws {
        var (scene, harness) = start()
        harness.event(mouseDown(4.95))
        harness.event(mouseUp(5.0))
        harness.frame(scene.frame(at: 5.2, set: .tiles(0..<12)))
        harness.run(until: 7)

        let kept = harness.picker.keptFrames
        #expect(kept.map(\.frameIndex) == [0, 1])
        #expect(kept.last?.reason == .click)
        let keptAt = try #require(harness.keptTime(ofFrame: 1))
        #expect(keptAt >= 5.6 - eps)
    }

    @Test func settleWaitsOutMotion() throws {
        var (scene, harness) = start()
        harness.event(mouseDown(1.0))
        harness.event(mouseUp(1.05))
        var last = scene.frame(at: 0)
        for k in 0..<10 {
            last = scene.frame(at: Double(11 + k) / 10, set: .tiles(k * 12..<(k + 1) * 12))
            harness.frame(last)
        }
        harness.run(until: 3)

        let kept = harness.picker.keptFrames
        #expect(kept.count == 2)
        #expect(kept.last?.frameIndex == last.index)
        #expect(kept.last?.time == 2.0)
        #expect(kept.last?.reason == .click)
        let keptAt = try #require(harness.keptTime(ofFrame: last.index))
        #expect(keptAt >= 2.4 - eps)
    }

    @Test func settleTimesOutAfter3s() throws {
        var (scene, harness) = start()
        harness.event(mouseDown(1.0))
        harness.event(mouseUp(1.05))
        var frames: [FrameSample] = []
        for k in 0..<50 {
            // Rotating 12-tile blocks, flipping value each lap, so every frame is motion and no tile gets busy.
            let first = k * 12 % 240
            let value: UInt8 = (k / 20) % 2 == 0 ? 40 : 200
            let frame = scene.frame(at: Double(11 + k) / 10, set: .tiles(first..<first + 12, value: value))
            frames.append(frame)
            harness.frame(frame)
        }
        harness.run(until: 6.0)

        let firstKeep = try #require(harness.outputs.first { $0.output != .persist(frameIndex: 0) })
        #expect(firstKeep.time >= 4.05 - eps && firstKeep.time <= 4.15 + eps)
        let latestAtTick = try #require(frames.last { $0.time <= firstKeep.time })
        #expect(firstKeep.output == .persist(frameIndex: latestAtTick.index))
        #expect(harness.picker.keptFrames[1].reason == .click)
    }

    @Test func checkboxClickKeptWithOneTile() {
        var (scene, harness) = start()
        harness.event(mouseDown(1.0))
        harness.event(mouseUp(1.05))
        harness.frame(scene.frame(at: 1.2, set: .tiles([100])))
        harness.run(until: 2)

        let kept = harness.picker.keptFrames
        #expect(kept.map(\.frameIndex) == [0, 1])
        #expect(kept.last?.reason == .click)
    }

    @Test func clickWithNoVisibleResultKeepsNothing() {
        var (_, harness) = start()
        harness.event(mouseDown(1.0))
        harness.event(mouseUp(1.05))
        harness.run(until: 5)

        let kept = harness.picker.keptFrames
        #expect(kept.count == 1)
        #expect(kept[0].actions == [saveClick])
    }

    @Test func visualToastKeptWithoutInput() throws {
        var (scene, harness) = start()
        harness.frame(scene.frame(at: 2.0, set: .tiles(0..<12)))
        harness.run(until: 3)

        let kept = harness.picker.keptFrames
        #expect(kept.map(\.frameIndex) == [0, 1])
        #expect(kept.last?.reason == .visual)
        let keptAt = try #require(harness.keptTime(ofFrame: 1))
        #expect(keptAt >= 2.4 - eps)
    }

    @Test func smallChangeWaitsForQuietInterval() {
        var (scene, harness) = start()
        harness.frame(scene.frame(at: 1.0, set: .tiles(0..<3)))

        harness.run(until: 9.9)
        #expect(harness.picker.keptFrames.count == 1)

        harness.run(until: 10.5)
        let kept = harness.picker.keptFrames
        #expect(kept.map(\.frameIndex) == [0, 1])
        #expect(kept.last?.reason == .visual)
    }

    @Test func singleTileWithoutInputIgnored() {
        var (scene, harness) = start()
        harness.frame(scene.frame(at: 1.0, set: .tiles([77])))
        harness.run(until: 15)
        #expect(harness.picker.keptFrames.count == 1)
    }

    @Test func cursorOnlyMovementIgnored() {
        var scene = SceneBuilder()
        var harness = PickerHarness(geometry: scene.geometry)
        func cursor(inTile tile: Int) -> PixelRect {
            let rect = scene.rect(ofTile: tile)
            return PixelRect(x: rect.x + 8, y: rect.y + 8, width: 12, height: 18)
        }
        // The cursor is drawn into the tile under it, and each move restores the tile it left.
        harness.frame(scene.frame(at: 0, set: [0: 40], cursor: cursor(inTile: 0)))
        for k in 1...30 {
            harness.frame(scene.frame(at: Double(k) / 10, set: [k - 1: 200, k: 40], cursor: cursor(inTile: k)))
        }
        harness.event(mouseDown(3.5))
        harness.event(mouseUp(3.55))
        harness.run(until: 5)

        let kept = harness.picker.keptFrames
        #expect(kept.count == 1)
        #expect(kept[0].actions == [saveClick])
    }

    @Test func typingRunProducesOneActionAndResultFrame() throws {
        var (scene, harness) = start()
        let typed = typeIntoEmail(&scene, &harness)
        harness.run(until: 7)

        let kept = harness.picker.keptFrames
        let emailClick = StepAction.clicked(target: email, at: point, button: .left, clickCount: 1)
        #expect(kept[0].actions == [emailClick, .typed(field: email)])
        #expect(kept.map(\.frameIndex) == [0, typed.index])
        #expect(kept.last?.reason == .typing)
        let keptAt = try #require(harness.keptTime(ofFrame: typed.index))
        #expect(abs(keptAt - 6.0) <= 0.1 + eps)
    }

    @Test func returnKeepsFilledFormBeforeSubmit() {
        var (scene, harness) = start()
        let filled = typeIntoEmail(&scene, &harness)
        harness.event(event(5.0, .keyReturn))
        let submitted = scene.frame(at: 5.2, set: .tiles(200..<212))
        harness.frame(submitted)
        harness.run(until: 7)

        let kept = harness.picker.keptFrames
        #expect(kept.map(\.frameIndex) == [0, filled.index, submitted.index])
        #expect(kept[1].reason == .beforeAction)
        #expect(kept[1].actions == [.pressedReturn])
        #expect(kept[2].reason == .commit)
    }

    @Test func dialogOpenCloseKeepsThreeFrames() {
        var (scene, harness) = start()
        harness.event(mouseDown(1.0))
        harness.event(mouseUp(1.05))
        harness.frame(scene.frame(at: 1.2, set: .tiles(0..<12)))
        harness.event(mouseDown(2.0))
        harness.event(mouseUp(2.05))
        harness.frame(scene.frame(at: 2.2, set: .tiles(0..<12, value: 200)))
        harness.run(until: 3)

        let kept = harness.picker.keptFrames
        #expect(kept.count == 3)
        let tracker = ChangeTracker(geometry: scene.geometry, config: PickerConfig())
        #expect(tracker.difference(kept[0].sample, kept[2].sample).fraction == 0)
    }

    @Test func scrollKeepsEvery80Percent() {
        // As the plan describes it, the scroll starts with the first frame: no earlier base frame,
        // so the first `.scrolled` attaches to the start frame.
        var scene = SceneBuilder()
        var harness = PickerHarness(geometry: scene.geometry)
        var last = scene.frame(at: 0)
        for k in 0..<20 {
            let time = Double(20 + k) / 20
            last = scene.frame(at: time, set: .tiles(0..<240, value: UInt8(20 + 10 * (k % 20))))
            harness.frame(last)
            harness.event(event(time, .scroll(fractionOfViewport: 0.2)))
        }
        harness.run(until: 4)

        let kept = harness.picker.keptFrames
        #expect(kept.filter { $0.reason == .scroll }.count == 5)
        #expect(kept[0].actions == [.scrolled])
        #expect(kept.last?.frameIndex == last.index)
        #expect(harness.outputs.allSatisfy { $0.time <= last.time })
    }

    @Test func switchAttachesAndUpdatesContext() {
        var (scene, harness) = start()
        let finder = FrameContext(app: "Finder", window: "Downloads")
        harness.event(event(1.0, .switched(finder)))
        harness.frame(scene.frame(at: 1.2, set: .tiles(0..<12)))
        harness.run(until: 2)

        let kept = harness.picker.keptFrames
        #expect(kept[0].actions == [.switched(to: finder)])
        #expect(kept[0].context == FrameContext(app: "TestApp", window: "Main"))
        #expect(kept.map(\.frameIndex) == [0, 1])
        #expect(kept[1].reason == .switchApp)
        #expect(kept[1].context == finder)
    }

    @Test func titleChangedUpdatesContextSilently() {
        var (scene, harness) = start()
        harness.event(event(1.0, .titleChanged(window: "New")))
        harness.frame(scene.frame(at: 2.0, set: .tiles(0..<12)))
        harness.run(until: 3)

        let kept = harness.picker.keptFrames
        #expect(kept.count == 2)
        #expect(kept.allSatisfy { $0.actions.isEmpty })
        #expect(kept[0].context.window == "Main")
        #expect(kept[1].context == FrameContext(app: "TestApp", window: "New"))
    }

    @Test func actionOnChangedScreenKeepsBeforeFrame() {
        var (scene, harness) = start()
        harness.frame(scene.frame(at: 1.0, set: .tiles(0..<3)))
        harness.event(mouseDown(2.0))

        #expect(harness.outputs.map(\.output).contains(.persist(frameIndex: 1)))
        let kept = harness.picker.keptFrames
        #expect(kept.map(\.frameIndex) == [0, 1])
        #expect(kept[1].reason == .beforeAction)
        #expect(kept[1].actions == [saveClick])
    }

    @Test func doubleClickMerges() {
        var (_, harness) = start()
        let file = ElementLabel(role: "file", label: "a.txt")
        let second = PixelPoint(x: 102, y: 101)
        harness.event(mouseDown(1.0, at: point, on: file, clickCount: 1))
        harness.event(mouseUp(1.05))
        harness.event(mouseDown(1.15, at: second, on: file, clickCount: 2))
        harness.event(mouseUp(1.2))
        harness.run(until: 2)

        #expect(harness.picker.keptFrames[0].actions == [.clicked(target: file, at: second, button: .left, clickCount: 2)])
    }

    @Test func stopWaitsForPendingClickResult() throws {
        var (scene, harness) = start()
        harness.event(mouseDown(2.9))
        harness.event(mouseUp(2.95))
        harness.frame(scene.frame(at: 3.0, set: .tiles([100])))
        harness.stop(at: 3.1)

        #expect(harness.picker.isFinished)
        let finishedAt = try #require(harness.finishedAt)
        #expect(finishedAt <= 3.55 + eps)
        let kept = harness.picker.keptFrames
        #expect(kept.last?.frameIndex == 1)
        #expect(kept.last?.reason == .click)
    }

    @Test func stopOnStaticScreenFinishesQuickly() throws {
        var (_, harness) = start()
        harness.stop(at: 5)

        let finishedAt = try #require(harness.finishedAt)
        #expect(finishedAt <= 5.45 + eps)
        #expect(harness.picker.keptFrames.count == 1)
    }

    @Test func stopDuringTypingKeepsTypedState() {
        var (scene, harness) = start()
        let typed = scene.frame(at: 4.0, set: .tiles([150]))
        harness.frame(typed)
        harness.event(event(4.0, .keyTyped(field: email)))
        harness.stop(at: 4.2)

        #expect(harness.picker.isFinished)
        let kept = harness.picker.keptFrames
        #expect(kept.last?.frameIndex == typed.index)
        #expect(kept.last?.reason == .typing)
    }

    @Test func nothingChangedGivesOneFrame() {
        var (_, harness) = start()
        harness.stop(at: 3)

        let result = harness.picker.result()
        #expect(result.frames.count == 1)
        #expect(result.candidateCount == 1)
    }

    @Test func poolTrimDiscards() throws {
        var config = PickerConfig()
        config.candidatePoolLimit = 10
        config.candidatePoolTrimTo = 5
        var scene = SceneBuilder()
        var harness = PickerHarness(geometry: scene.geometry, config: config)
        harness.frame(scene.frame(at: 0))
        var toasts: [FrameSample] = []
        for i in 1...10 {
            let toast = scene.frame(at: Double(i), set: .tiles((i - 1) * 12..<i * 12))
            toasts.append(toast)
            harness.frame(toast)
        }
        harness.run(until: 11)

        // The 11th kept frame is the last toast; the same tick trims the pool.
        let eleventh = try #require(toasts.last)
        let keptAt = try #require(harness.keptTime(ofFrame: eleventh.index))
        let discards = harness.outputs.compactMap { entry -> (TimeInterval, [Int])? in
            if case .discard(let indices) = entry.output { return (entry.time, indices) }
            return nil
        }
        #expect(discards.count == 1)
        let (discardedAt, discarded) = try #require(discards.first)
        #expect(discardedAt == keptAt)
        #expect(discarded.count == 6)
        #expect(!discarded.contains(0) && !discarded.contains(eleventh.index))
        #expect(harness.picker.keptFrames.count == 5)
    }

    @Test func resultAppliesCap() {
        var config = PickerConfig()
        config.maxFrames = 3
        var scene = SceneBuilder()
        var harness = PickerHarness(geometry: scene.geometry, config: config)
        harness.frame(scene.frame(at: 0))
        for i in 1...5 {
            harness.frame(scene.frame(at: Double(i), set: .tiles((i - 1) * 12..<i * 12)))
        }
        harness.stop(at: 6)
        #expect(harness.picker.keptFrames.count == 6)

        let result = harness.picker.result()
        #expect(result.frames.count == 3)
        #expect(result.frames.first?.frameIndex == 0)
        #expect(result.frames.last?.frameIndex == 5)
        #expect(result.candidateCount == 6)
    }
}
