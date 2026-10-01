import CoreGraphics
import AnnotakeCore
import AnnotakeExport
import Foundation

/// Small raw frames and pick results for export tests.
enum ExportFixtures {
    static let width = 64
    static let height = 48
    static let context = FrameContext(app: "TestApp", window: "Main")
    static let options = RenderOptions(captionStrip: true, clickMarkers: true)

    /// A fresh root folder; the caller removes it.
    static func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "annotake-export-tests-\(UUID().uuidString)")
    }

    static func solidImage(value: UInt8) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let level = CGFloat(value) / 255
        context.setFillColor(CGColor(colorSpace: space, components: [level, level, level, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// Writes `.raw/frame-<i>.png` for each index.
    static func writeRawFrames(_ indices: [Int], into pending: PendingCapture) throws {
        for index in indices {
            try PNGFile.write(solidImage(value: UInt8(30 * index % 256)), to: pending.rawFrameURL(frameIndex: index))
        }
    }

    /// One frame per index, at `index` seconds, each carrying a click on `button "B<index>"`.
    static func result(frameIndices: [Int], candidateCount: Int) -> PickResult {
        let frames = frameIndices.map { index in
            PickedFrame(frameIndex: index, time: Double(index), context: context,
                        actions: [click(index)], reason: index == frameIndices.first ? .start : .click)
        }
        return PickResult(frames: frames, candidateCount: candidateCount,
                          duration: Double((frameIndices.last ?? 0) + 1))
    }

    static func click(_ index: Int) -> StepAction {
        .clicked(target: ElementLabel(role: "button", label: "B\(index)"), at: PixelPoint(x: 10, y: 10),
                 button: .left, clickCount: 1)
    }

    /// Every path under the folder, relative, sorted.
    static func tree(_ folder: URL) -> [String] {
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        var paths: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            paths.append(String(url.standardizedFileURL.path.dropFirst(folder.standardizedFileURL.path.count)))
        }
        return paths.sorted()
    }

    /// The non-hidden file names in the folder, sorted.
    static func visibleFiles(_ folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { !$0.hasPrefix(".") }
            .sorted()
    }
}
