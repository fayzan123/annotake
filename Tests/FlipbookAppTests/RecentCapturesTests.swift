import CoreGraphics
@testable import FlipbookApp
import FlipbookCore
import FlipbookExport
import Foundation
import Testing

struct RecentCapturesTests {
    static let base = Date(timeIntervalSince1970: 1_790_000_000)

    /// A 64×48 gray frame; this suite writes its own, since test targets can't share support files.
    static func tinyFrame() -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(colorSpace: space, components: [0.5, 0.5, 0.5, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        return context.makeImage()!
    }

    /// Seven one-frame captures, a day apart; the last is the newest.
    func makeCaptures(in store: CaptureStore) throws -> [FinishedCapture] {
        try (0..<7).map { day in
            let pending = try store.begin()
            try PNGFile.write(Self.tinyFrame(), to: pending.rawFrameURL(frameIndex: 0))
            let frame = PickedFrame(frameIndex: 0, time: 0, context: FrameContext(app: "TestApp", window: nil),
                                    actions: [], reason: .start)
            let created = Self.base.addingTimeInterval(Double(day) * 86_400)
            return try CaptureExporter.finish(
                pending, in: store, result: PickResult(frames: [frame], candidateCount: 1, duration: 1),
                name: CaptureStore.folderName(for: created), target: "Screen: Test", created: created,
                options: RenderOptions(captionStrip: true, clickMarkers: true))
        }
    }

    @Test func latestFive() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "flipbook-recent-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CaptureStore(root: root)
        let captures = try makeCaptures(in: store)

        let latest = RecentCaptures.latest(in: store)
        #expect(latest.map(\.folder.lastPathComponent) == captures.reversed().prefix(5).map(\.folder.lastPathComponent))
    }

    @Test func unreadableSkipped() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "flipbook-recent-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CaptureStore(root: root)
        let captures = try makeCaptures(in: store)
        let newest = try #require(captures.last)
        try Data("not json".utf8).write(to: newest.folder.appending(path: ".raw/capture.json"))

        let latest = RecentCaptures.latest(in: store)
        #expect(latest.map(\.folder.lastPathComponent)
                == captures.reversed().dropFirst().prefix(5).map(\.folder.lastPathComponent))
    }
}
