import FlipbookCore
import Foundation
import Testing

struct RawSessionTests {
    /// A fresh directory under the temp folder, removed by the caller.
    func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "flipbook-tests-\(UUID().uuidString)")
    }

    @Test func roundTripPreservesSession() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = Scenes.clickFlow()

        try RawSessionIO.write(session, to: directory)
        #expect(try RawSessionIO.read(from: directory) == session)
    }

    @Test func roundTripPreservesContextSource() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = Scenes.windowRecording()

        try RawSessionIO.write(session, to: directory)
        let json = try String(contentsOf: directory.appending(path: "session.json"), encoding: .utf8)
        #expect(json.contains(#""contextSource" : "recordedWindow""#))
        #expect(try RawSessionIO.read(from: directory) == session)
    }

    /// Sessions saved before window recordings named their window follow focus, and focus sessions are
    /// still written the same way.
    @Test func olderSessionsFollowFocus() throws {
        let fixture = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
            .appending(path: "synthetic-click-flow")
        #expect(try RawSessionIO.read(from: fixture).contextSource == .focus)

        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try RawSessionIO.write(Scenes.clickFlow(), to: directory)
        let json = try String(contentsOf: directory.appending(path: "session.json"), encoding: .utf8)
        #expect(!json.contains("contextSource"))
    }

    @Test func corruptTilesThrows() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try RawSessionIO.write(Scenes.clickFlow(), to: directory)

        let tiles = directory.appending(path: "tiles.bin")
        try Data(contentsOf: tiles).dropLast().write(to: tiles)
        let bytes = 7 * 240 * FrameSignature.valuesPerTile
        #expect(throws: RawSessionError.corruptTiles(expectedBytes: bytes, actualBytes: bytes - 1)) {
            try RawSessionIO.read(from: directory)
        }
    }

    @Test func unsupportedVersionThrows() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try RawSessionIO.write(Scenes.clickFlow(), to: directory)

        let sessionFile = directory.appending(path: "session.json")
        let json = try String(contentsOf: sessionFile, encoding: .utf8)
        #expect(json.contains(#""version" : 1"#))
        try json.replacingOccurrences(of: #""version" : 1"#, with: #""version" : 99"#)
            .write(to: sessionFile, atomically: true, encoding: .utf8)
        #expect(throws: RawSessionError.unsupportedVersion(99)) {
            try RawSessionIO.read(from: directory)
        }
    }
}
