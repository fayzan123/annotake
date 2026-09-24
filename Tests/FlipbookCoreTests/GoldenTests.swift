import FlipbookCore
import Foundation
import Testing

/// Raw sessions paired with the frames they should pick (spec §8). Each fixture is a directory
/// holding `session.json`, `tiles.bin` and `expected.json`.
struct GoldenTests {
    struct Expectation: Codable, Equatable {
        var frameIndices: [Int]
        var summaries: [String]

        init(_ result: PickResult) {
            frameIndices = result.frames.map(\.frameIndex)
            summaries = result.summaries
        }
    }

    static let localFixtures = ProcessInfo.processInfo.environment["FLIPBOOK_LOCAL_FIXTURES"]
    static let regenerating = ProcessInfo.processInfo.environment["FLIPBOOK_REGENERATE_FIXTURES"] == "1"

    /// Replays every fixture directory under `root` and compares it with its `expected.json`.
    func checkFixtures(in root: URL) throws {
        let fixtures = try FileManager.default
            .contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(!fixtures.isEmpty, "no fixtures in \(root.path)")

        for fixture in fixtures {
            let session = try RawSessionIO.read(from: fixture)
            let expected = try JSONDecoder().decode(Expectation.self,
                                                    from: Data(contentsOf: fixture.appending(path: "expected.json")))
            #expect(Expectation(SessionReplayer.run(session).result) == expected, "\(fixture.lastPathComponent)")
        }
    }

    @Test func goldenFixturesMatch() throws {
        let root = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        try checkFixtures(in: root)
    }

    /// Work-Mac sessions that must never be committed (spec §8).
    @Test(.enabled(if: localFixtures != nil, "set FLIPBOOK_LOCAL_FIXTURES to a folder of fixtures"))
    func localGoldenFixturesMatch() throws {
        try checkFixtures(in: URL(fileURLWithPath: try #require(Self.localFixtures)))
    }

    @Test(.enabled(if: regenerating, "set FLIPBOOK_REGENERATE_FIXTURES=1 to rewrite the synthetic fixtures"))
    func regenerateSyntheticFixtures() throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/synthetic-click-flow")
        let session = Scenes.clickFlow()
        try RawSessionIO.write(session, to: directory)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Expectation(SessionReplayer.run(session).result))
            .write(to: directory.appending(path: "expected.json"), options: .atomic)
    }
}
