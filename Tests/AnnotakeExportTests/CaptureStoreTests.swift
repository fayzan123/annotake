import AnnotakeCore
import AnnotakeExport
import Foundation
import Testing

struct CaptureStoreTests {
    /// A fresh root folder; the caller removes it.
    func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "annotake-store-tests-\(UUID().uuidString)")
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func utcDate(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string)!
    }

    @Test func folderNameFormat() {
        let date = utcDate("2026-09-23T14:05:12Z")
        #expect(CaptureStore.folderName(for: date, timeZone: TimeZone(identifier: "UTC")!) == "2026-09-23 at 14.05.12")
    }

    @Test func beginCreatesTempRaw() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let pending = try CaptureStore(root: root).begin()

        #expect(pending.directory.deletingLastPathComponent().lastPathComponent == ".annotake-tmp")
        #expect(pending.directory.deletingLastPathComponent().deletingLastPathComponent().path == root.path)
        #expect(exists(pending.rawDirectory))
        #expect(pending.rawFrameURL(frameIndex: 17).lastPathComponent == "frame-000017.png")
        #expect(pending.rawFrameURL(frameIndex: 17).deletingLastPathComponent().path == pending.rawDirectory.path)
    }

    @Test func commitMovesAndMarks() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CaptureStore(root: root)
        let pending = try store.begin()
        let date = Date()

        let folder = try store.commit(pending, name: "capture", date: date)

        #expect(folder.path == root.appending(path: "capture").path)
        #expect(exists(folder))
        let marker = try #require(CaptureStore.readMarker(in: folder))
        #expect(abs(marker.timeIntervalSince(date)) < 1)
        #expect(!exists(pending.directory))
    }

    @Test func collisionsGetSuffix() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CaptureStore(root: root)
        let names = try (0..<3).map { _ in
            try store.commit(try store.begin(), name: "name", date: Date()).lastPathComponent
        }
        #expect(names == ["name", "name (2)", "name (3)"])
    }

    @Test func leftoversRemoved() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CaptureStore(root: root)
        let uncommitted = try store.begin()
        let committed = try store.commit(try store.begin(), name: "kept", date: Date())

        store.removeLeftovers()

        #expect(!exists(uncommitted.directory))
        #expect(!exists(root.appending(path: ".annotake-tmp")))
        #expect(exists(committed))
    }

    @Test func capturesListsMarkedNewestFirst() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CaptureStore(root: root)
        let day1 = utcDate("2026-09-01T10:00:00Z")
        let day2 = utcDate("2026-09-02T10:00:00Z")
        let day3 = utcDate("2026-09-03T10:00:00Z")
        _ = try store.commit(try store.begin(), name: "one", date: day1)
        _ = try store.commit(try store.begin(), name: "three", date: day3)
        _ = try store.commit(try store.begin(), name: "two", date: day2)
        try FileManager.default.createDirectory(at: root.appending(path: "no marker"), withIntermediateDirectories: true)
        _ = try store.begin()

        let captures = store.captures()
        #expect(captures.map(\.url.lastPathComponent) == ["three", "two", "one"])
        #expect(captures.map(\.date) == [day3, day2, day1])
    }

    /// Only Annotake's own marker makes a folder a capture: one with any other file, such as a `.flipbook`, is never
    /// listed or cleaned up.
    @Test func onlyAnnotakesMarkerCounts() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CaptureStore(root: root)
        let date = utcDate("2026-09-01T10:00:00Z")
        for (name, marker) in [("someone else's", ".flipbook"), ("ours", CaptureStore.markerName)] {
            let folder = root.appending(path: name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(ISO8601DateFormatter().string(from: date).utf8).write(to: folder.appending(path: marker))
        }

        #expect(store.captures().map(\.url.lastPathComponent) == ["ours"])
        let expired = Retention.expired(in: store, days: 7, now: utcDate("2026-09-09T10:00:00Z"))
        #expect(expired.map(\.lastPathComponent) == ["ours"])
    }

    @Test func unwritableSaveLocationThrows() throws {
        let base = temporaryRoot()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: base.appending(path: "ro").path)
            try? FileManager.default.removeItem(at: base)
        }
        let readOnly = base.appending(path: "ro")
        try FileManager.default.createDirectory(at: readOnly, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnly.path)

        let insideReadOnly = CaptureStore(root: readOnly.appending(path: "Annotake"))
        #expect(throws: CaptureStoreError.saveLocationUnavailable(path: readOnly.appending(path: "Annotake").path)) {
            try insideReadOnly.begin()
        }

        let file = base.appending(path: "a file")
        try Data("not a folder".utf8).write(to: file)
        #expect(throws: CaptureStoreError.saveLocationUnavailable(path: file.path)) {
            try CaptureStore(root: file).begin()
        }
    }

    @Test func manifestRoundTrips() throws {
        let context = FrameContext(app: "Safari", window: "Apple")
        let frames = [
            PickedFrame(frameIndex: 0, time: 0, context: context, actions: [
                .clicked(target: ElementLabel(role: "button", label: "Save"), at: PixelPoint(x: 10, y: 20),
                         button: .left, clickCount: 1),
            ], reason: .start),
            PickedFrame(frameIndex: 4, time: 2.5, context: context, actions: [.pressedReturn], reason: .commit),
        ]
        let manifest = CaptureManifest(
            name: "2026-09-23 at 14.05.12", target: "Screen: Built-in Retina Display", created: Date(),
            render: RenderOptions(captionStrip: true, clickMarkers: false),
            result: PickResult(frames: frames, candidateCount: 7, duration: 3.2), removed: [])

        let decoded = try JSONDecoder().decode(CaptureManifest.self, from: JSONEncoder().encode(manifest))
        #expect(decoded == manifest)
        #expect(decoded.version == CaptureManifest.currentVersion)
    }
}
