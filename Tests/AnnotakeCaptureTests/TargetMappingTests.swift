import CoreGraphics
import AnnotakeCapture
import AnnotakeCore
import Testing

struct TargetMappingTests {
    let builtIn = TargetMapping(screenRect: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                output: OutputSize(width: 1920, height: 1246))

    func isClose(_ point: PixelPoint?, _ x: Double, _ y: Double) -> Bool {
        guard let point else { return false }
        return abs(point.x - x) <= 0.01 && abs(point.y - y) <= 0.01
    }

    @Test func builtInDisplayMaps() {
        #expect(isClose(builtIn.outputPoint(CGPoint(x: 756, y: 491)), 960, 623))
    }

    @Test func negativeOriginDisplayMaps() {
        let left = TargetMapping(screenRect: CGRect(x: -2560, y: 0, width: 2560, height: 1080),
                                 output: OutputSize(width: 1920, height: 810))
        #expect(isClose(left.outputPoint(CGPoint(x: -1280, y: 540)), 960, 405))
        #expect(left.outputPoint(CGPoint(x: 10, y: 10)) == nil)
        #expect(left.contains(CGPoint(x: -1, y: 0)))
        #expect(!left.contains(CGPoint(x: 0, y: 0)))
    }

    @Test func displayAboveMainMaps() {
        let above = TargetMapping(screenRect: CGRect(x: 0, y: -1080, width: 1920, height: 1080),
                                  output: OutputSize(width: 1920, height: 1080))
        #expect(isClose(above.outputPoint(CGPoint(x: 100, y: -1000)), 100, 80))
    }

    @Test func windowMaps() {
        let window = TargetMapping(screenRect: CGRect(x: 200, y: 150, width: 800, height: 600),
                                   output: OutputSize(width: 1600, height: 1200))
        #expect(isClose(window.outputPoint(CGPoint(x: 600, y: 450)), 800, 600))
        #expect(window.outputPoint(CGPoint(x: 199, y: 150)) == nil)
    }

    @Test func cursorBoxScales() {
        let hotspot = CGPoint(x: 756, y: 491)
        #expect(builtIn.cursorRect(hotspot: hotspot, cursorScale: 1) == PixelRect(x: 944, y: 607, width: 56, height: 56))
        #expect(builtIn.cursorRect(hotspot: hotspot, cursorScale: 2) == PixelRect(x: 929, y: 592, width: 112, height: 112))
        #expect(builtIn.cursorRect(hotspot: CGPoint(x: 2000, y: 10), cursorScale: 1) == nil)
    }
}
