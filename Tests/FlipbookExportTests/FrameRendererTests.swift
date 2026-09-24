import CoreGraphics
import FlipbookCore
import FlipbookExport
import Foundation
import Testing

struct FrameRendererTests {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// A solid-gray sRGB frame.
    func grayFrame(width: Int, height: Int, value: UInt8 = 128) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: Self.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let level = CGFloat(value) / 255
        context.setFillColor(CGColor(colorSpace: Self.sRGB, components: [level, level, level, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// The image's pixels as RGBA8 in sRGB, row 0 at the top.
    struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        init(_ image: CGImage) {
            width = image.width
            height = image.height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            bytes.withUnsafeMutableBytes { buffer in
                let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                        bitsPerComponent: 8, bytesPerRow: image.width * 4, space: FrameRendererTests.sRGB,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            self.bytes = bytes
        }

        subscript(x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
            let offset = (y * width + x) * 4
            return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
        }
    }

    func isClose(_ pixel: (r: Int, g: Int, b: Int), _ r: Int, _ g: Int, _ b: Int) -> Bool {
        abs(pixel.r - r) <= 3 && abs(pixel.g - g) <= 3 && abs(pixel.b - b) <= 3
    }

    let both = RenderOptions(captionStrip: true, clickMarkers: true)
    let neither = RenderOptions(captionStrip: false, clickMarkers: false)
    let markersOnly = RenderOptions(captionStrip: false, clickMarkers: true)

    @Test func renderAddsStrip() {
        let image = FrameRenderer.render(frame: grayFrame(width: 640, height: 384), line1: #"1/3 · 0:00 · Clicked button "Save""#,
                                         line2: "Safari — Apple", clickPoints: [], options: both)
        #expect(image.width == 640)
        #expect(image.height == 427)
        let pixels = Pixels(image)
        #expect(isClose(pixels[5, 386], 0x1C, 0x1C, 0x1E))
        #expect(isClose(pixels[5, 5], 128, 128, 128))
    }

    @Test func renderWithoutStripIsUnchanged() {
        let frame = grayFrame(width: 640, height: 384)
        let image = FrameRenderer.render(frame: frame, line1: "1/1 · 0:00 · Start", line2: "Safari",
                                         clickPoints: [PixelPoint(x: 100, y: 100)], options: neither)
        #expect(image.width == 640)
        #expect(image.height == 384)
        let rendered = Pixels(image), original = Pixels(frame)
        #expect(zip(rendered.bytes, original.bytes).allSatisfy { abs(Int($0) - Int($1)) <= 3 })
    }

    @Test func markerRingAndHalo() {
        let image = FrameRenderer.render(frame: grayFrame(width: 640, height: 384), line1: "", line2: "",
                                         clickPoints: [PixelPoint(x: 320, y: 192)], options: markersOnly)
        let pixels = Pixels(image)
        let ring = pixels[328, 192]
        #expect(ring.r > 200 && ring.g < 110 && ring.b < 110)
        let halo = pixels[330, 192]
        #expect(halo.r > 200 && halo.g > 200 && halo.b > 200)
        #expect(isClose(pixels[320, 192], 128, 128, 128))
    }

    @Test func markerLayout() {
        let layouts = FrameRenderer.markerLayout(
            clickPoints: [PixelPoint(x: 200, y: 100), PixelPoint(x: 400, y: 300), PixelPoint(x: -50, y: 10)],
            width: 640, height: 384)
        #expect(layouts.map(\.center) == [PixelPoint(x: 200, y: 100), PixelPoint(x: 400, y: 300)])
        #expect(layouts.map(\.radius) == [8, 8])
        #expect(layouts.map(\.badge) == [
            MarkerLayout.Badge(center: PixelPoint(x: 208, y: 92), radius: 3.6, number: 1),
            MarkerLayout.Badge(center: PixelPoint(x: 408, y: 292), radius: 3.6, number: 2),
        ])

        let single = FrameRenderer.markerLayout(clickPoints: [PixelPoint(x: 200, y: 100)], width: 640, height: 384)
        #expect(single.count == 1)
        #expect(single.first?.badge == nil)
    }

    @Test func longCaptionsStayInBudget() {
        let image = FrameRenderer.render(frame: grayFrame(width: 1920, height: 1246),
                                         line1: CaptionLayoutTests.tenLongActions,
                                         line2: String(repeating: "x", count: 300), clickPoints: [], options: both)
        #expect(image.width == 1920)
        #expect(image.height == 1246 + 207)
        #expect(image.width <= 2000 && image.height <= 2000)
    }

    @Test func pngRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "flipbook-png-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "frame.png")
        let image = FrameRenderer.render(frame: grayFrame(width: 640, height: 384), line1: "1/1 · 0:00 · Start",
                                         line2: "Safari", clickPoints: [], options: both)

        try PNGFile.write(image, to: url)
        let read = try PNGFile.read(url)

        #expect(read.width == image.width)
        #expect(read.height == image.height)
        #expect(read.colorSpace?.name == CGColorSpace.sRGB)
    }

    /// Writes build/samples/render.png for a person to look at.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FLIPBOOK_WRITE_SAMPLES"] == "1"))
    func writeSampleRender() throws {
        let line1 = #"3/8 · 0:07 · Clicked button "Save" → Clicked checkbox "Remember me""#
        let image = FrameRenderer.render(frame: grayFrame(width: 1920, height: 1246), line1: line1,
                                         line2: "Google Chrome — Dayforce · Timesheets",
                                         clickPoints: [PixelPoint(x: 700, y: 500), PixelPoint(x: 1100, y: 640)],
                                         options: both)
        let samples = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "../../build/samples").standardized
        try FileManager.default.createDirectory(at: samples, withIntermediateDirectories: true)
        try PNGFile.write(image, to: samples.appending(path: "render.png"))
    }
}
