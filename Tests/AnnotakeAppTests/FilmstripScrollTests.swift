import AppKit
@testable import AnnotakeApp
import Testing

@MainActor
struct FilmstripScrollTests {
    /// A strip wider than the panel, laid out.
    private func view() -> FilmstripView {
        let view = FilmstripView(frame: CGRect(x: 0, y: 0, width: 600, height: FilmstripView.height))
        view.strip.tiles = (1...10).map {
            FilmstripTile(frameIndex: $0, url: URL(fileURLWithPath: "/"), caption: "", image: nil, aspect: 1.32)
        }
        view.layoutSubtreeIfNeeded()
        return view
    }

    private func wheel(lines: Int32) -> NSEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)!
        return NSEvent(cgEvent: event)!
    }

    @Test func mouseWheelScrollsSideways() {
        let view = view()
        view.scrollView.scrollWheel(with: wheel(lines: -3))
        #expect(view.scrollView.contentView.bounds.minX > 0)
        view.scrollView.scrollWheel(with: wheel(lines: 30))
        #expect(view.scrollView.contentView.bounds.minX == 0)
    }

    @Test func mouseWheelStopsAtTheEnd() {
        let view = view()
        view.scrollView.scrollWheel(with: wheel(lines: -1000))
        let end = view.strip.frame.width - view.scrollView.contentView.bounds.width
        #expect(view.scrollView.contentView.bounds.minX == end)
    }

    @Test(arguments: [NSScroller.Style.legacy, .overlay])
    func framesAndCaptionsFitAboveTheScroller(style: NSScroller.Style) {
        let view = view()
        view.scrollView.scrollerStyle = style
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        #expect(view.scrollView.hasHorizontalScroller)
        #expect(view.scrollView.contentView.bounds.height >= view.strip.frame.height)
        #expect(view.strip.frame.minY == 0)
        #expect(!view.scrollView.contentView.drawsBackground)
    }
}
