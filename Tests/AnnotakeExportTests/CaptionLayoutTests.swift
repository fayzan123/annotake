import AnnotakeExport
import Testing

struct CaptionLayoutTests {
    static let longAction = #"Clicked button "Something rather long""#
    static let tenLongActions = Array(repeating: longAction, count: 10).joined(separator: " → ")

    @Test func metricsAt1920() {
        let metrics = CaptionLayout.metrics(forWidth: 1920)
        #expect(metrics.fontSize1 == 30)
        #expect(metrics.fontSize2 == 25.5)
        #expect(metrics.lineHeight1 == 39)
        #expect(metrics.lineHeight2 == 33)
        #expect(metrics.padding == 24)
        #expect(metrics.gap == 9)
        #expect(CaptionLayout.stripHeight(lineCount1: 1, width: 1920) == 129)
        #expect(CaptionLayout.maxStripHeight(forWidth: 1920) == 207)
    }

    @Test func metricsAt640() {
        let metrics = CaptionLayout.metrics(forWidth: 640)
        #expect(metrics.fontSize1 == 10)
        #expect(metrics.fontSize2 == 8.5)
        #expect(metrics.lineHeight1 == 13)
        #expect(metrics.lineHeight2 == 11)
        #expect(metrics.padding == 8)
        #expect(metrics.gap == 3)
        #expect(CaptionLayout.stripHeight(lineCount1: 1, width: 640) == 43)
        #expect(CaptionLayout.maxStripHeight(forWidth: 640) == 69)
    }

    @Test func maxRatioHoldsForAllWidths() {
        for width in 400...2000 {
            #expect(Double(CaptionLayout.maxStripHeight(forWidth: width)) <= CaptionLayout.maxHeightRatio * Double(width),
                    "width \(width)")
        }
    }

    @Test func wrapShortLine() {
        #expect(CaptionLayout.wrap(#"3/8 · 0:07 · Clicked button "Save""#, width: 1920).count == 1)
    }

    @Test func wrapLongLineCapsAtThree() {
        let lines = CaptionLayout.wrap(Self.tenLongActions, width: 640)
        #expect(lines.count == 3)
        #expect(lines.last?.hasSuffix("…") == true)
    }
}
