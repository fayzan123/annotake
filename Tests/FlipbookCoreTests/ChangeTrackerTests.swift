import FlipbookCore
import Foundation
import Testing

struct ChangeTrackerTests {
    func makeTracker(_ scene: SceneBuilder) -> ChangeTracker {
        ChangeTracker(geometry: scene.geometry, config: PickerConfig())
    }

    /// Toggles tiles 20 and 21 every 0.1 s from 0.1 to `last`, like a spinner.
    /// Returns the last frame; `check` sees each frame's change and the tracker after it.
    @discardableResult
    func spin(_ scene: inout SceneBuilder, _ tracker: inout ChangeTracker, after first: FrameSample,
              through last: Int = 20, countTowardBusy: Bool = true,
              check: (Int, FrameChange, ChangeTracker) -> Void = { _, _, _ in }) -> FrameSample {
        var previous = first
        for k in 1...last {
            let value: UInt8 = k % 2 == 1 ? 40 : 200
            let frame = scene.frame(at: Double(k) / 10, set: [20: value, 21: value])
            let change = tracker.observe(frame, previous: previous, countTowardBusy: countTowardBusy)
            check(k, change, tracker)
            previous = frame
        }
        return previous
    }

    @Test func firstFrameHasNoChange() {
        var scene = SceneBuilder()
        var tracker = makeTracker(scene)
        let change = tracker.observe(scene.frame(at: 0), previous: nil)
        #expect(change.changedTiles.isEmpty)
        #expect(!change.motion)
    }

    @Test func changedTilesWithinDirtyRects() {
        var scene = SceneBuilder()
        var tracker = makeTracker(scene)
        let f0 = scene.frame(at: 0)
        _ = tracker.observe(f0, previous: nil)
        let f1 = scene.frame(at: 0.1, set: .tiles([5, 6]))
        let change = tracker.observe(f1, previous: f0)
        #expect(change.changedTiles == [5, 6])
        #expect(change.motion)

        // A change outside the dirty rects isn't compared.
        let f2 = scene.frame(at: 0.2, set: .tiles([9]), dirty: [scene.rect(ofTile: 5)])
        #expect(tracker.observe(f2, previous: f1).changedTiles.isEmpty)
    }

    @Test func emptyDirtyRectsComparesAllTiles() {
        var scene = SceneBuilder()
        var tracker = makeTracker(scene)
        let f0 = scene.frame(at: 0)
        _ = tracker.observe(f0, previous: nil)
        let f1 = scene.frame(at: 0.1, set: .tiles([7, 8, 9]), dirty: [])
        #expect(tracker.observe(f1, previous: f0).changedTiles == [7, 8, 9])
    }

    @Test func singleTileIsNotMotion() {
        var scene = SceneBuilder()
        var tracker = makeTracker(scene)
        let f0 = scene.frame(at: 0)
        _ = tracker.observe(f0, previous: nil)
        let change = tracker.observe(scene.frame(at: 0.1, set: .tiles([42])), previous: f0)
        #expect(change.changedTiles == [42])
        #expect(!change.motion)
    }

    @Test func cursorOnlyChangesAreIgnored() {
        var scene = SceneBuilder()
        var tracker = makeTracker(scene)
        let f0 = scene.frame(at: 0, cursor: PixelRect(x: 8, y: 8, width: 12, height: 18))       // tile 0
        _ = tracker.observe(f0, previous: nil)
        let f1 = scene.frame(at: 0.1, set: .tiles([0, 2]), cursor: PixelRect(x: 72, y: 8, width: 12, height: 18)) // tile 2
        let change = tracker.observe(f1, previous: f0)
        #expect(change.changedTiles == [0, 2])
        #expect(!change.motion)
        #expect(tracker.difference(f0, f1).changedTiles == 0)
    }

    @Test func caretBlinkIsIgnored() {
        var scene = SceneBuilder()
        var tracker = makeTracker(scene)
        let caret = PixelRect(x: 10 * 32 + 10, y: 2 * 32 + 4, width: 3, height: 20)   // inside tile 50 only
        let f0 = scene.frame(at: 0)
        _ = tracker.observe(f0, previous: nil)
        var previous = f0
        var caretShown = f0
        for k in 1...6 {
            let value: UInt8 = k % 2 == 1 ? 40 : 200
            let frame = scene.frame(at: Double(k) * 0.5, set: [50: value], dirty: [caret])
            let change = tracker.observe(frame, previous: previous)
            #expect(change.changedTiles == [50])
            #expect(!change.motion)
            if value == 40 { caretShown = frame }
            previous = frame
        }
        #expect(tracker.caretTiles == [50])
        #expect(tracker.difference(f0, caretShown) == Difference(changedTiles: 0, consideredTiles: 239))

        tracker.advance(to: previous.time + 2.0)
        #expect(tracker.caretTiles.isEmpty)
        #expect(tracker.everCaretTiles == [50])
    }

    @Test func spinnerBecomesBusyThenReleases() {
        var scene = SceneBuilder()
        var tracker = makeTracker(scene)
        let f0 = scene.frame(at: 0)
        _ = tracker.observe(f0, previous: nil)
        var busyAtOneSecond: Set<Int> = []
        spin(&scene, &tracker, after: f0) { k, change, tracker in
            if k == 10 { busyAtOneSecond = tracker.busyTiles }
            if k >= 10 { #expect(!change.motion, "frame \(k)") }
        }
        #expect(busyAtOneSecond == [20, 21])

        tracker.advance(to: 4.1)
        #expect(tracker.busyTiles.isEmpty)
        #expect(tracker.everBusyTiles.isSuperset(of: [20, 21]))
    }

    @Test func largeChangesDoNotCountTowardBusy() {
        var scene = SceneBuilder()
        var tracker = makeTracker(scene)
        var previous = scene.frame(at: 0)
        _ = tracker.observe(previous, previous: nil)
        for k in 1...20 {
            let frame = scene.frame(at: Double(k) / 10, set: .tiles(0..<240, value: UInt8(20 + 10 * k)))
            let change = tracker.observe(frame, previous: previous)
            #expect(change.motion, "frame \(k)")
            #expect(tracker.busyTiles.isEmpty, "frame \(k)")
            previous = frame
        }
    }

    @Test func scrollFramesDoNotCountTowardBusy() {
        var scene = SceneBuilder()
        var tracker = makeTracker(scene)
        let f0 = scene.frame(at: 0)
        _ = tracker.observe(f0, previous: nil)
        spin(&scene, &tracker, after: f0, countTowardBusy: false) { k, _, tracker in
            #expect(tracker.busyTiles.isEmpty, "frame \(k)")
        }
        #expect(tracker.everBusyTiles.isEmpty)
    }

    @Test func differenceUsesConsideredTiles() {
        var scene = SceneBuilder()
        var tracker = makeTracker(scene)
        let f0 = scene.frame(at: 0)
        _ = tracker.observe(f0, previous: nil)
        let a = spin(&scene, &tracker, after: f0, through: 10)
        #expect(tracker.busyTiles == [20, 21])

        // b also flips the busy tiles; only 30, 31 and 32 count.
        let b = scene.frame(at: 1.05, set: [20: 40, 21: 40, 30: 40, 31: 40, 32: 40])
        #expect(tracker.difference(a, b) == Difference(changedTiles: 3, consideredTiles: 238))
    }

    @Test func settledDifferenceUsesEverSets() {
        var scene = SceneBuilder()
        var tracker = makeTracker(scene)
        let f0 = scene.frame(at: 0)
        _ = tracker.observe(f0, previous: nil)
        let spun = spin(&scene, &tracker, after: f0, through: 19)   // ends with 20 and 21 at 40
        tracker.advance(to: 4.1)
        #expect(tracker.busyTiles.isEmpty)

        #expect(tracker.difference(f0, spun) == Difference(changedTiles: 2, consideredTiles: 240))
        #expect(tracker.settledDifference(f0, spun) == Difference(changedTiles: 0, consideredTiles: 238))
    }
}
