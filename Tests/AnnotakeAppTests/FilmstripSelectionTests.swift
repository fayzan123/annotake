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

    @Test func lastFrameStays() {
        var selection = FilmstripSelection(frameIndices: [1, 2])
        selection.toggle(1)
        #expect(!selection.canRemove(2))
        selection.toggle(2)
        #expect(selection.removed == [1])
        #expect(selection.canRemove(1) == false)
    }
}
