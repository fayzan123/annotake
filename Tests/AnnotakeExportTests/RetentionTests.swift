import AnnotakeExport
import Foundation
import Testing

struct RetentionTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    func daysAgo(_ days: Double) -> Date {
        now.addingTimeInterval(-days * 86_400)
    }

    /// Marked captures 31 and 29 days old, an unmarked folder 100 days old, and a temp folder.
    func makeCaptures(in store: CaptureStore) throws -> (old: URL, recent: URL, unmarked: URL) {
        let old = try store.commit(try store.begin(), name: "old", date: daysAgo(31))
        let recent = try store.commit(try store.begin(), name: "recent", date: daysAgo(29))
        let unmarked = store.root.appending(path: "unmarked")
        try FileManager.default.createDirectory(at: unmarked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: daysAgo(100), .creationDate: daysAgo(100)],
                                              ofItemAtPath: unmarked.path)
        _ = try store.begin()
        return (old, recent, unmarked)
    }

    @Test func retentionTrashesOnlyExpiredMarked() throws {
        let root = ExportFixtures.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CaptureStore(root: root)
        let (old, _, _) = try makeCaptures(in: store)

        var trashed: [String] = []
        let result = Retention.run(in: store, days: 30, now: now) { trashed.append($0.lastPathComponent) }
        #expect(trashed == [old.lastPathComponent])
        #expect(result.map(\.lastPathComponent) == [old.lastPathComponent])
        #expect(Retention.expired(in: store, days: 30, now: now).map(\.lastPathComponent) == ["old"])

        var foreverTrashed: [URL] = []
        #expect(Retention.run(in: store, days: nil, now: now) { foreverTrashed.append($0) }.isEmpty)
        #expect(foreverTrashed.isEmpty)
    }

    @Test func retentionContinuesAfterTrashError() throws {
        struct TrashFailed: Error {}
        let root = ExportFixtures.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CaptureStore(root: root)
        let first = try store.commit(try store.begin(), name: "first", date: daysAgo(40))
        let second = try store.commit(try store.begin(), name: "second", date: daysAgo(35))

        var attempts: [String] = []
        let result = Retention.run(in: store, days: 30, now: now) { url in
            attempts.append(url.lastPathComponent)
            if url.lastPathComponent == attempts.first { throw TrashFailed() }
        }
        #expect(attempts.count == 2)
        #expect(Set(attempts) == [first.lastPathComponent, second.lastPathComponent])
        #expect(result.map(\.lastPathComponent) == [attempts[1]])
    }
}
