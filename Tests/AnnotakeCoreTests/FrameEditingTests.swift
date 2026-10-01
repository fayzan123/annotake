import AnnotakeCore
import Foundation
import Testing

struct FrameEditingTests {
    func frame(_ index: Int, _ actions: [StepAction] = []) -> PickedFrame {
        PickedFrame(frameIndex: index, time: Double(index), context: FrameContext(app: "TestApp", window: "Main"),
                    actions: actions, reason: .visual)
    }

    let a1 = StepAction.pressedShortcut("⌘A")
    let b1 = StepAction.pressedShortcut("⌘B")
    let c1 = StepAction.pressedShortcut("⌘C")

    @Test func removeMiddleMergesIntoPrevious() {
        let result = FrameEditing.removing(frameIndices: [1], from: [frame(0, [a1]), frame(1, [b1]), frame(2)])
        #expect(result == [frame(0, [a1, b1]), frame(2)])
    }

    @Test func removeFirstPrependsToNext() {
        let result = FrameEditing.removing(frameIndices: [0], from: [frame(0, [a1]), frame(1, [b1])])
        #expect(result == [frame(1, [a1, b1])])
    }

    @Test func removeLeadingRunPrependsInOrder() {
        let result = FrameEditing.removing(frameIndices: [0, 1], from: [frame(0, [a1]), frame(1, [b1]), frame(2, [c1])])
        #expect(result == [frame(2, [a1, b1, c1])])
    }

    @Test func removeConsecutiveKeepsOrder() {
        let input = [frame(0, [a1]), frame(1, [b1]), frame(2, [c1]), frame(3)]
        let result = FrameEditing.removing(frameIndices: [1, 2], from: input)
        #expect(result == [frame(0, [a1, b1, c1]), frame(3)])
    }

    @Test func removeAllIsEmpty() {
        #expect(FrameEditing.removing(frameIndices: [0, 1], from: [frame(0, [a1]), frame(1, [b1])]) == [])
    }

    @Test func removeNothingIsIdentity() {
        let input = [frame(0, [a1]), frame(1, [b1]), frame(2)]
        #expect(FrameEditing.removing(frameIndices: [], from: input) == input)
    }
}
