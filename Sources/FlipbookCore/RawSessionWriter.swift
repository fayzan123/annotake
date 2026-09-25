import Foundation

/// Writes a raw session while it's being recorded: each frame's signature streams to `tiles.bin` as it
/// arrives, and `session.json` is written at the end, in RawSessionIO's format.
/// Not Sendable: confine it to one queue.
public final class RawSessionWriter {
    private let directory: URL
    private let geometry: CaptureGeometry
    private let initialContext: FrameContext
    private let contextSource: ContextSource
    private let bytesPerFrame: Int
    private let tiles: FileHandle
    private var frames: [RawSessionIO.SessionFile.Frame] = []
    private var events: [InputEvent] = []
    private var closed = false

    /// Creates the directory and an empty `tiles.bin`.
    public init(directory: URL, geometry: CaptureGeometry, initialContext: FrameContext,
                contextSource: ContextSource = .focus) throws {
        self.directory = directory
        self.geometry = geometry
        self.initialContext = initialContext
        self.contextSource = contextSource
        bytesPerFrame = geometry.grid.count * FrameSignature.valuesPerTile
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let tilesURL = directory.appending(path: "tiles.bin")
        try Data().write(to: tilesURL)
        tiles = try FileHandle(forWritingTo: tilesURL)
    }

    deinit {
        if !closed { try? tiles.close() }
    }

    public func append(_ frame: FrameSample) throws {
        precondition(frame.signature.values.count == bytesPerFrame, "frame \(frame.index) doesn't match the geometry")
        try tiles.write(contentsOf: frame.signature.values)
        frames.append(RawSessionIO.SessionFile.Frame(index: frame.index, time: frame.time,
                                                     dirtyRects: frame.dirtyRects, cursor: frame.cursor))
    }

    public func append(_ event: InputEvent) {
        events.append(event)
    }

    /// Closes `tiles.bin` and writes `session.json`.
    public func finish(stopTime: TimeInterval) throws {
        try tiles.synchronize()
        try tiles.close()
        closed = true
        let file = RawSessionIO.SessionFile(
            version: RawSessionIO.formatVersion,
            geometry: geometry,
            initialContext: initialContext,
            contextSource: contextSource,
            frames: frames,
            events: events,
            stopTime: stopTime,
            bytesPerFrame: bytesPerFrame)
        try RawSessionIO.writeSessionFile(file, to: directory)
    }
}
