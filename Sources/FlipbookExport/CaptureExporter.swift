import FlipbookCore
import Foundation
import Synchronization

/// A capture folder with its rendered frames.
public struct FinishedCapture: Sendable, Equatable {
    public let folder: URL
    public let manifest: CaptureManifest

    public init(folder: URL, manifest: CaptureManifest) {
        self.folder = folder
        self.manifest = manifest
    }

    /// The rendered PNGs in step order.
    public var frameURLs: [URL] {
        CaptureExporter.fileNames(for: manifest.result).map { folder.appending(path: $0) }
    }
}

/// Turns picked frames into a finished capture folder, and applies filmstrip trims (spec §3.4, §4.1).
public enum CaptureExporter {
    public static let concurrentRenders = 4
    static let stepsFileName = "steps.md"
    static let manifestFileName = "capture.json"
    static let removedFolderName = "removed"
    static let stagingFolderName = "staging"

    /// Deletes the candidates that weren't picked, renders the picked frames, writes `steps.md`,
    /// `capture.json` and the marker, and moves the folder into place. On any error, the pending
    /// capture is discarded, so nothing half-written reaches the captures folder.
    public static func finish(_ pending: PendingCapture, in store: CaptureStore, result: PickResult, name: String,
                              target: String, created: Date, options: RenderOptions) throws -> FinishedCapture {
        do {
            let picked = Set(result.frames.map(\.frameIndex))
            for url in rawFrameFiles(in: pending.rawDirectory) where !picked.contains(url.frameIndex ?? -1) {
                try FileManager.default.removeItem(at: url)
            }
            try render(result, options: options, rawFrame: pending.rawFrameURL(frameIndex:), into: pending.directory)
            let manifest = CaptureManifest(name: name, target: target, created: created, render: options,
                                           result: result, removed: [])
            try writeDocuments(manifest, folder: pending.directory)
            let folder = try store.commit(pending, name: name, date: created)
            return FinishedCapture(folder: folder, manifest: manifest)
        } catch {
            pending.discard()
            throw error
        }
    }

    /// Removes frames from a finished capture: their actions merge into the previous frame, their raw
    /// frames move to `.raw/removed/`, and the rest are re-rendered and renumbered with no gaps.
    /// The re-renders are staged first, so a failure leaves the capture as it was.
    public static func remove(frameIndices: Set<Int>, from folder: URL) throws -> FinishedCapture {
        let old = try load(folder)
        let frames = old.manifest.result.frames
        guard frames.contains(where: { !frameIndices.contains($0.frameIndex) }) else {
            throw CaptureStoreError.cannotRemoveAllFrames
        }
        var manifest = old.manifest
        manifest.result = PickResult(frames: FrameEditing.removing(frameIndices: frameIndices, from: frames),
                                     candidateCount: old.manifest.result.candidateCount,
                                     duration: old.manifest.result.duration)
        manifest.removed += frames.filter { frameIndices.contains($0.frameIndex) }

        let raw = folder.appending(path: CaptureStore.rawFolderName)
        let staging = raw.appending(path: stagingFolderName)
        let files = FileManager.default
        try? files.removeItem(at: staging)
        try files.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: staging) }
        try render(manifest.result, options: manifest.render, rawFrame: { rawFrameURL(in: raw, frameIndex: $0) },
                   into: staging)

        let removed = raw.appending(path: removedFolderName)
        try files.createDirectory(at: removed, withIntermediateDirectories: true)
        for frame in frames where frameIndices.contains(frame.frameIndex) {
            let source = rawFrameURL(in: raw, frameIndex: frame.frameIndex)
            let destination = removed.appending(path: source.lastPathComponent)
            try? files.removeItem(at: destination)
            try files.moveItem(at: source, to: destination)
        }
        for url in old.frameURLs {
            try? files.removeItem(at: url)
        }
        for name in fileNames(for: manifest.result) {
            try files.moveItem(at: staging.appending(path: name), to: folder.appending(path: name))
        }
        try writeDocuments(manifest, folder: folder)
        return FinishedCapture(folder: folder, manifest: manifest)
    }

    public static func load(_ folder: URL) throws -> FinishedCapture {
        let data = try Data(contentsOf: folder.appending(path: CaptureStore.rawFolderName).appending(path: manifestFileName))
        return FinishedCapture(folder: folder, manifest: try JSONDecoder().decode(CaptureManifest.self, from: data))
    }

    static func fileNames(for result: PickResult) -> [String] {
        result.frames.enumerated().map { Captions.fileName(number: $0 + 1, time: $1.time) }
    }

    // MARK: - Private

    private static func rawFrameURL(in raw: URL, frameIndex: Int) -> URL {
        raw.appending(path: CaptureStore.rawFrameName(frameIndex: frameIndex))
    }

    private static func rawFrameFiles(in raw: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: raw, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.frameIndex != nil }
    }

    /// Renders each frame from its raw PNG into `folder`, at most `concurrentRenders` at a time.
    private static func render(_ result: PickResult, options: RenderOptions, rawFrame: (Int) -> URL,
                               into folder: URL) throws {
        let frames = result.frames
        let names = fileNames(for: result)
        let sources = frames.map { rawFrame($0.frameIndex) }
        let firstError = Mutex<Error?>(nil)
        let workers = min(concurrentRenders, frames.count)
        DispatchQueue.concurrentPerform(iterations: workers) { worker in
            for position in stride(from: worker, to: frames.count, by: workers) {
                do {
                    let frame = frames[position]
                    guard FileManager.default.fileExists(atPath: sources[position].path) else {
                        throw CaptureStoreError.missingRawFrame(frameIndex: frame.frameIndex)
                    }
                    let image = FrameRenderer.render(
                        frame: try PNGFile.read(sources[position]),
                        line1: Captions.line1(for: frame, number: position + 1, total: frames.count),
                        line2: Captions.line2(for: frame.context),
                        clickPoints: options.clickMarkers ? frame.clickPoints : [],
                        options: options)
                    try PNGFile.write(image, to: folder.appending(path: names[position]))
                } catch {
                    firstError.withLock { first in
                        if first == nil { first = error }
                    }
                    return
                }
            }
        }
        if let error = firstError.withLock({ $0 }) { throw error }
    }

    private static func writeDocuments(_ manifest: CaptureManifest, folder: URL) throws {
        let steps = StepsDocument.render(manifest.result, captureName: manifest.name, target: manifest.target)
        try Data(steps.utf8).write(to: folder.appending(path: stepsFileName), options: .atomic)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(
            to: folder.appending(path: CaptureStore.rawFolderName).appending(path: manifestFileName), options: .atomic)
    }
}

private extension URL {
    /// The index in a `frame-000017.png` name, or nil for any other file.
    var frameIndex: Int? {
        let name = lastPathComponent
        guard name.hasPrefix("frame-"), name.hasSuffix(".png") else { return nil }
        return Int(name.dropFirst("frame-".count).dropLast(".png".count))
    }
}
