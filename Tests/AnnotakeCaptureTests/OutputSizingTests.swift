import CoreGraphics
import AnnotakeCapture
import Testing

struct OutputSizingTests {
    func fit(_ width: Double, _ height: Double, longEdge: Int = 1920, stripRatio: Double = 0.115) -> OutputSize {
        OutputSizing.fit(sourcePixels: CGSize(width: width, height: height), longEdge: longEdge, stripRatio: stripRatio)
    }

    @Test func retinaDisplay() {
        #expect(fit(3024, 1964) == OutputSize(width: 1920, height: 1246))
    }

    @Test func ultrawideAtOneX() {
        #expect(fit(2560, 1080) == OutputSize(width: 1920, height: 810))
    }

    @Test func compact() {
        #expect(fit(3024, 1964, longEdge: 1568) == OutputSize(width: 1568, height: 1018))
    }

    @Test func portraitWindowReservesStrip() {
        #expect(fit(1800, 2800, stripRatio: 0.1) == OutputSize(width: 1208, height: 1878))
        #expect(fit(1800, 2800, stripRatio: 0) == OutputSize(width: 1234, height: 1920))
    }

    @Test func neverUpscales() {
        #expect(fit(600, 400) == OutputSize(width: 600, height: 400))
    }

    @Test func roundsDownToEven() {
        #expect(fit(801, 601) == OutputSize(width: 800, height: 600))
    }
}
