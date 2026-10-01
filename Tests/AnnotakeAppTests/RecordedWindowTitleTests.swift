@testable import AnnotakeApp
import AnnotakeCore
import Testing

struct RecordedWindowTitleTests {
    @Test func sameTitleIsNoChange() {
        var title = RecordedWindowTitle("Downloads")
        #expect(title.change(read: "Downloads") == nil)
    }

    @Test func newTitleChangesOnce() {
        var title = RecordedWindowTitle("Downloads")
        #expect(title.change(read: "Documents") == .titleChanged(window: "Documents"))
        #expect(title.change(read: "Documents") == nil)
    }

    /// Titles are normalized like the ones Accessibility reads.
    @Test func titlesAreNormalized() {
        var title = RecordedWindowTitle("Downloads")
        #expect(title.change(read: "  Downloads\n") == nil)
        #expect(title.change(read: "main.swift —\n  annotake") == .titleChanged(window: "main.swift — annotake"))
    }

    @Test func emptyTitleIsNoTitle() {
        var title = RecordedWindowTitle("Downloads")
        #expect(title.change(read: "") == .titleChanged(window: nil))
        #expect(title.change(read: " ") == nil)
    }

    /// A window that's gone keeps its last title.
    @Test func goneWindowKeepsTitle() {
        var title = RecordedWindowTitle("Downloads")
        #expect(title.change(read: nil) == nil)
        #expect(title.change(read: "Downloads") == nil)
    }
}
