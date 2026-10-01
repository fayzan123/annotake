@testable import AnnotakeApp
import AnnotakeCore
import Testing

struct LogWindowTests {
    let blank = FrameSignature(tileCount: 4)

    /// The line says where the second's redraws were: the box around its dirty rects, in capture pixels
    /// (Checkpoint 2). Empty rects don't count.
    @Test func lineHasDirtyBox() {
        var window = LogWindow()
        window.note(blank, dirtyRects: [PixelRect(x: 100, y: 200, width: 50, height: 20),
                                        PixelRect(x: 400, y: 180, width: 10, height: 10),
                                        PixelRect(x: 0, y: 0, width: 0, height: 0)])
        window.note(blank, dirtyRects: [PixelRect(x: 90, y: 300, width: 5, height: 5)])

        #expect(window.flush(at: 1, idleFrames: 3)
                == "stream 0–1 s: 2 complete, 3 idle, dirty 1125 px in 320×125 at (90, 180), 0 changed")
    }

    /// Each second starts afresh; one with nothing dirty has no box.
    @Test func eachSecondStartsAfresh() {
        var window = LogWindow()
        window.note(blank, dirtyRects: [PixelRect(x: 0, y: 0, width: 8, height: 8)])
        _ = window.flush(at: 1, idleFrames: 3)
        window.note(blank, dirtyRects: [])

        #expect(window.start == 1)
        #expect(window.flush(at: 2, idleFrames: 5) == "stream 1–2 s: 1 complete, 2 idle, dirty 0 px, 0 changed")
    }
}
