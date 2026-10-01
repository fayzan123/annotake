import AnnotakeCore
import Foundation
import Testing

struct CapFitterTests {
    let config = PickerConfig()

    /// D from a table of changed tiles (out of 100) keyed by frame-index pairs in either order; missing pairs are 0.
    func lookup(_ table: [[Int]: Int]) -> (FrameSample, FrameSample) -> Difference {
        { a, b in
            let key = [min(a.index, b.index), max(a.index, b.index)]
            return Difference(changedTiles: table[key] ?? 0, consideredTiles: 100)
        }
    }

    /// Frames with index i at the given times.
    func frames(at times: [TimeInterval], actions: [Int: [StepAction]] = [:]) -> [KeptFrame] {
        times.enumerated().map { index, time in
            SceneBuilder.keptStub(index: index, time: time, actions: actions[index] ?? [])
        }
    }

    func click(_ x: Double) -> StepAction {
        .clicked(target: nil, at: PixelPoint(x: x, y: 0), button: .left, clickCount: 1)
    }

    @Test func underCapIsUnchanged() {
        let input = frames(at: [0, 1, 2])
        let (kept, removed) = CapFitter.fit(input, cap: 5, config: config, difference: lookup([:]))
        #expect(kept == input)
        #expect(removed == [])
    }

    @Test func firstAndLastArePinned() {
        let table: [[Int]: Int] = [[0, 1]: 40, [1, 2]: 40, [2, 3]: 40, [3, 4]: 40, [0, 4]: 1]
        let (kept, removed) = CapFitter.fit(frames(at: [0, 1, 2, 3, 4]), cap: 2, config: config, difference: lookup(table))
        #expect(kept.map(\.frameIndex) == [0, 4])
        #expect(removed.sorted() == [1, 2, 3])
    }

    @Test func removesLeastInformativeFirst() {
        // Frame 2 adds almost nothing over its neighbors; frame 1 adds a lot.
        let table: [[Int]: Int] = [[0, 1]: 50, [0, 2]: 30, [0, 3]: 30, [1, 2]: 1, [1, 3]: 1, [2, 3]: 1]
        let (kept, removed) = CapFitter.fit(frames(at: [0, 1, 2, 3]), cap: 3, config: config, difference: lookup(table))
        #expect(removed == [2])
        #expect(kept.map(\.frameIndex) == [0, 1, 3])
    }

    @Test func clickBonusProtectsFrame() {
        // Equal geometric cost (all D are 0) and equal time gaps; the tie would remove frame 1, but it holds a click.
        let input = frames(at: [0, 1, 2, 3], actions: [1: [click(5)]])
        let (kept, removed) = CapFitter.fit(input, cap: 3, config: config, difference: lookup([:]))
        #expect(removed == [2])
        #expect(kept.map(\.frameIndex) == [0, 1, 3])
        #expect(kept[1].actions == [click(5)])
    }

    @Test func timeGapTermProtectsIsolatedFrames() {
        // Removing frame 1 would leave a 9 s gap (0 → 9); removing frame 2 only a 2 s gap (8 → 10).
        let (kept, removed) = CapFitter.fit(frames(at: [0, 8, 9, 10]), cap: 3, config: config, difference: lookup([:]))
        #expect(removed == [2])
        #expect(kept.map(\.frameIndex) == [0, 1, 3])
    }

    @Test func removedActionsMergeIntoPrevious() {
        // Frames 2 and 3 are near-duplicates of their neighbors; frame 1 is distinct.
        let table: [[Int]: Int] = [[0, 1]: 60, [0, 2]: 30, [1, 2]: 1, [1, 3]: 1, [1, 4]: 1, [2, 3]: 1, [2, 4]: 1, [3, 4]: 1]
        let typedA = StepAction.typed(field: ElementLabel(role: "text field", label: "A"))
        let typedB = StepAction.typed(field: ElementLabel(role: "text field", label: "B"))
        let typedC = StepAction.typed(field: ElementLabel(role: "text field", label: "C"))
        let input = frames(at: [0, 1, 2, 3, 4], actions: [1: [typedA], 2: [typedB, .typed(field: nil)], 3: [typedC]])
        let (kept, removed) = CapFitter.fit(input, cap: 3, config: config, difference: lookup(table))
        #expect(removed.sorted() == [2, 3])
        #expect(kept.map(\.frameIndex) == [0, 1, 4])
        #expect(kept[1].actions == [typedA, typedB, .typed(field: nil), typedC])
    }

    @Test func tiesRemoveEarliest() {
        var config = PickerConfig()
        config.timeGapWeight = 0
        let (kept, removed) = CapFitter.fit(frames(at: [0, 1, 2, 3, 4, 5]), cap: 2, config: config, difference: lookup([:]))
        #expect(removed == [1, 2, 3, 4])
        #expect(kept.map(\.frameIndex) == [0, 5])
    }

    @Test func removalIsNested() {
        var table: [[Int]: Int] = [:]
        for a in 0..<8 {
            for b in a + 1..<8 {
                table[[a, b]] = (a * 7 + b * 13) % 17 + (b - a) * 3
            }
        }
        let input = frames(
            at: [0, 0.5, 1.7, 2.0, 3.1, 4.4, 4.6, 6.0],
            actions: [2: [.typed(field: nil)], 3: [click(3)], 4: [.pressedReturn], 5: [.scrolled], 6: [click(6), .typed(field: nil)]])
        let d = lookup(table)

        let direct = CapFitter.fit(input, cap: 3, config: config, difference: d)
        let firstStep = CapFitter.fit(input, cap: 5, config: config, difference: d)
        let secondStep = CapFitter.fit(firstStep.kept, cap: 3, config: config, difference: d)
        #expect(firstStep.kept.count == 5)
        #expect(secondStep.kept.map(\.frameIndex) == direct.kept.map(\.frameIndex))
        #expect(secondStep.kept.map(\.actions) == direct.kept.map(\.actions))
        #expect(firstStep.removed + secondStep.removed == direct.removed)
    }

    @Test func capBelowTwoIsTreatedAsTwo() {
        let (kept, removed) = CapFitter.fit(frames(at: [0, 1, 2, 3]), cap: 0, config: config, difference: lookup([:]))
        #expect(kept.map(\.frameIndex) == [0, 3])
        #expect(removed.count == 2)
    }

    @Test func bonusIsTheLargestOfReasonAndActions() {
        #expect(CapFitter.bonus(for: SceneBuilder.keptStub(index: 0, time: 0), config: config) == 0)
        #expect(CapFitter.bonus(for: SceneBuilder.keptStub(index: 0, time: 0, reason: .click), config: config) == 0.15)
        #expect(CapFitter.bonus(for: SceneBuilder.keptStub(index: 0, time: 0, actions: [.scrolled]), config: config) == 0.05)
        let switched = StepAction.switched(to: FrameContext(app: "Finder", window: nil))
        let both = SceneBuilder.keptStub(index: 0, time: 0, actions: [.pressedShortcut("⌘S"), switched], reason: .scroll)
        #expect(CapFitter.bonus(for: both, config: config) == 0.30)
    }
}
