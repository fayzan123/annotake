import Foundation

/// Everything the picker saw during one recording, for replay and golden tests (spec §8).
public struct RawSession: Sendable, Equatable {
    public var geometry: CaptureGeometry
    public var initialContext: FrameContext
    public var frames: [FrameSample]
    public var events: [InputEvent]
    public var stopTime: TimeInterval

    public init(geometry: CaptureGeometry, initialContext: FrameContext, frames: [FrameSample],
                events: [InputEvent], stopTime: TimeInterval) {
        self.geometry = geometry
        self.initialContext = initialContext
        self.frames = frames
        self.events = events
        self.stopTime = stopTime
    }
}

public enum RawSessionError: Error, Equatable {
    case unsupportedVersion(Int)
    case corruptTiles(expectedBytes: Int, actualBytes: Int)
}

/// Reads and writes a raw session directory: `session.json` holds everything but the signatures,
/// and `tiles.bin` holds every frame's signature values, concatenated in frame order.
public enum RawSessionIO {
    public static let formatVersion = 1

    private struct Header: Decodable {
        var version: Int
    }

    private struct SessionFile: Codable {
        struct Frame: Codable {
            var index: Int
            var time: TimeInterval
            var dirtyRects: [PixelRect]
            var cursor: PixelRect?
        }

        var version: Int
        var geometry: CaptureGeometry
        var initialContext: FrameContext
        var frames: [Frame]
        var events: [InputEvent]
        var stopTime: TimeInterval
        var bytesPerFrame: Int
    }

    /// Creates the directory if needed.
    public static func write(_ session: RawSession, to directory: URL) throws {
        let bytesPerFrame = session.geometry.grid.count * FrameSignature.valuesPerTile
        var tiles = Data(capacity: session.frames.count * bytesPerFrame)
        for frame in session.frames {
            precondition(frame.signature.values.count == bytesPerFrame, "frame \(frame.index) doesn't match the geometry")
            tiles.append(contentsOf: frame.signature.values)
        }
        let file = SessionFile(
            version: formatVersion,
            geometry: session.geometry,
            initialContext: session.initialContext,
            frames: session.frames.map {
                SessionFile.Frame(index: $0.index, time: $0.time, dirtyRects: $0.dirtyRects, cursor: $0.cursor)
            },
            events: session.events,
            stopTime: session.stopTime,
            bytesPerFrame: bytesPerFrame)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(file).write(to: directory.appending(path: "session.json"), options: .atomic)
        try tiles.write(to: directory.appending(path: "tiles.bin"), options: .atomic)
    }

    public static func read(from directory: URL) throws -> RawSession {
        let json = try Data(contentsOf: directory.appending(path: "session.json"))
        let decoder = JSONDecoder()
        let version = try decoder.decode(Header.self, from: json).version
        guard version == formatVersion else { throw RawSessionError.unsupportedVersion(version) }
        let file = try decoder.decode(SessionFile.self, from: json)

        let tileCount = file.geometry.grid.count
        let bytesPerFrame = tileCount * FrameSignature.valuesPerTile
        let tiles = [UInt8](try Data(contentsOf: directory.appending(path: "tiles.bin")))
        guard file.bytesPerFrame == bytesPerFrame, tiles.count == file.frames.count * bytesPerFrame else {
            throw RawSessionError.corruptTiles(expectedBytes: file.frames.count * file.bytesPerFrame,
                                               actualBytes: tiles.count)
        }

        let frames = file.frames.enumerated().map { offset, frame in
            let start = offset * bytesPerFrame
            return FrameSample(
                index: frame.index, time: frame.time,
                signature: FrameSignature(tileCount: tileCount, values: Array(tiles[start..<start + bytesPerFrame])),
                dirtyRects: frame.dirtyRects, cursor: frame.cursor)
        }
        return RawSession(geometry: file.geometry, initialContext: file.initialContext, frames: frames,
                          events: file.events, stopTime: file.stopTime)
    }
}
