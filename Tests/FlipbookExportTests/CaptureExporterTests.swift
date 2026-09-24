import FlipbookCore
import FlipbookExport
import Foundation
import Testing

struct CaptureExporterTests {
    let name = "2026-09-23 at 14.05.12"
    let target = "Screen: Test Display"
    let created = Date(timeIntervalSince1970: 1_790_000_000)

    /// Raw frames 0, 1, 2 and 5 written; 0, 2 and 5 picked.
    func finishThreeFrames(in store: CaptureStore, candidateCount: Int = 4) throws -> FinishedCapture {
        let pending = try store.begin()
        try ExportFixtures.writeRawFrames([0, 1, 2, 5], into: pending)
        return try CaptureExporter.finish(pending, in: store, result: ExportFixtures.result(frameIndices: [0, 2, 5], candidateCount: candidateCount),
                                          name: name, target: target, created: created, options: ExportFixtures.options)
    }

    @Test func finishWritesEverything() throws {
        let root = ExportFixtures.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CaptureStore(root: root)
        let pending = try store.begin()
        try ExportFixtures.writeRawFrames([0, 1, 2, 5], into: pending)
        let result = ExportFixtures.result(frameIndices: [0, 2, 5], candidateCount: 4)

        let finished = try CaptureExporter.finish(pending, in: store, result: result, name: name, target: target,
                                                  created: created, options: ExportFixtures.options)

        let folder = finished.folder
        #expect(folder.path == root.appending(path: name).path)
        let pngs = result.frames.enumerated().map { Captions.fileName(number: $0 + 1, time: $1.time) }
        #expect(pngs == ["01_0m00s.png", "02_0m02s.png", "03_0m05s.png"])
        #expect(ExportFixtures.visibleFiles(folder) == pngs + ["steps.md"])
        #expect(finished.frameURLs.map(\.lastPathComponent) == pngs)
        #expect(try String(contentsOf: folder.appending(path: "steps.md"), encoding: .utf8)
                == StepsDocument.render(result, captureName: name, target: target))
        let manifest = try JSONDecoder().decode(CaptureManifest.self,
                                                from: Data(contentsOf: folder.appending(path: ".raw/capture.json")))
        #expect(manifest == finished.manifest)
        #expect(manifest == CaptureManifest(name: name, target: target, created: created, render: ExportFixtures.options,
                                            result: result, removed: []))
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: ".flipbook").path))
        let raw = try FileManager.default.contentsOfDirectory(atPath: folder.appending(path: ".raw").path)
        #expect(raw.filter { $0.hasPrefix("frame-") }.sorted()
                == ["frame-000000.png", "frame-000002.png", "frame-000005.png"])
        #expect(!FileManager.default.fileExists(atPath: pending.directory.path))
    }

    @Test func finishRendersCaptions() throws {
        let root = ExportFixtures.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let finished = try finishThreeFrames(in: CaptureStore(root: root))

        let first = try PNGFile.read(try #require(finished.frameURLs.first))
        #expect(first.width == ExportFixtures.width)
        #expect(first.height == ExportFixtures.height + CaptionLayout.stripHeight(lineCount1: 1, width: ExportFixtures.width))
    }

    @Test func finishFailureLeavesNothing() throws {
        let root = ExportFixtures.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CaptureStore(root: root)
        let pending = try store.begin()
        try ExportFixtures.writeRawFrames([0, 5], into: pending)

        #expect(throws: CaptureStoreError.missingRawFrame(frameIndex: 2)) {
            try CaptureExporter.finish(pending, in: store, result: ExportFixtures.result(frameIndices: [0, 2, 5], candidateCount: 3),
                                       name: name, target: target, created: created, options: ExportFixtures.options)
        }
        #expect(store.captures().isEmpty)
        #expect(ExportFixtures.visibleFiles(root).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: pending.directory.path))
    }

    @Test func removeRenumbers() throws {
        let root = ExportFixtures.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let finished = try finishThreeFrames(in: CaptureStore(root: root), candidateCount: 5)
        let oldThird = try #require(finished.frameURLs.last)

        let trimmed = try CaptureExporter.remove(frameIndices: [2], from: finished.folder)

        #expect(trimmed.manifest.result.frames.map(\.frameIndex) == [0, 5])
        let pngs = ExportFixtures.visibleFiles(finished.folder).filter { $0.hasSuffix(".png") }
        #expect(pngs == ["01_0m00s.png", "02_0m05s.png"])
        #expect(trimmed.frameURLs.map(\.lastPathComponent) == pngs)
        #expect(!FileManager.default.fileExists(atPath: oldThird.path))
        let steps = try String(contentsOf: finished.folder.appending(path: "steps.md"), encoding: .utf8)
        #expect(steps.contains("2 frames (from 5 candidates)"))
        #expect(steps == StepsDocument.render(trimmed.manifest.result, captureName: name, target: target))
        #expect(trimmed.manifest.result.frames[0].actions.last == ExportFixtures.click(2))
        #expect(trimmed.manifest.result.candidateCount == 5)
        #expect(trimmed.manifest.result.duration == finished.manifest.result.duration)
        #expect(trimmed.manifest.removed.map(\.frameIndex) == [2])
        #expect(FileManager.default.fileExists(atPath: finished.folder.appending(path: ".raw/removed/frame-000002.png").path))
        #expect(!FileManager.default.fileExists(atPath: finished.folder.appending(path: ".raw/frame-000002.png").path))
        #expect(try CaptureExporter.load(finished.folder) == trimmed)
    }

    @Test func removeAllThrows() throws {
        let root = ExportFixtures.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let finished = try finishThreeFrames(in: CaptureStore(root: root))
        let before = ExportFixtures.tree(finished.folder)
        let stepsBefore = try Data(contentsOf: finished.folder.appending(path: "steps.md"))

        #expect(throws: CaptureStoreError.cannotRemoveAllFrames) {
            try CaptureExporter.remove(frameIndices: [0, 2, 5], from: finished.folder)
        }
        #expect(ExportFixtures.tree(finished.folder) == before)
        #expect(try Data(contentsOf: finished.folder.appending(path: "steps.md")) == stepsBefore)
    }

    @Test func loadMatchesFinish() throws {
        let root = ExportFixtures.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let finished = try finishThreeFrames(in: CaptureStore(root: root))
        #expect(try CaptureExporter.load(finished.folder) == finished)
    }
}
