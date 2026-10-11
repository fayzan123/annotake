@testable import AnnotakeApp
import Testing

struct FilmstripSelectionTests {
    @Test func toggleRemovesAndRestores() {
        var selection = FilmstripSelection(frameIndices: [1, 2, 3])
        selection.toggle(2)
        #expect(selection.removed == [2])
        selection.toggle(2)
        #expect(selection.removed == [])
    }

    @Test func noFramesLeavesTheCurrentFrameAlone() {
        var selection = FilmstripSelection(frameIndices: [])
        selection.moveCurrent(by: 1)
        selection.moveCurrent(to: 3)
        selection.toggleCurrent()
        #expect(selection.current == 0)
        #expect(selection.removed == [])
    }

    @Test func lastFrameStays() {
        var selection = FilmstripSelection(frameIndices: [1, 2])
        selection.toggle(1)
        #expect(!selection.canRemove(2))
        selection.toggle(2)
        #expect(selection.removed == [1])
        #expect(selection.canRemove(1) == false)
    }
}
