@testable import AnnotakeApp
import Foundation
import Testing

struct LogTests {
    /// A log file inside a fresh temp folder that doesn't exist yet; the caller removes the folder.
    func temporaryLog() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "annotake-log-tests-\(UUID().uuidString)")
            .appending(path: "Annotake.log")
    }

    func lines(of url: URL) throws -> [String] {
        try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
    }

    @Test func appendsTimestampedLines() throws {
        let url = temporaryLog()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = LogFile(url: url, cap: 1_000_000)

        log.write("first line")
        log.write("second line")
        log.flush()

        let written = try lines(of: url)
        #expect(written.count == 2)
        #expect(written[0].wholeMatch(of: /\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} first line/) != nil)
        #expect(written[1].wholeMatch(of: /\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} second line/) != nil)
    }

    @Test func rotatesAtCap() throws {
        let url = temporaryLog()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = LogFile(url: url, cap: 100)

        for letter in ["a", "b", "c"] {
            log.write(String(repeating: letter, count: 60))
        }
        log.flush()

        let rotated = url.deletingLastPathComponent().appending(path: "Annotake.log.1")
        #expect(FileManager.default.fileExists(atPath: rotated.path))
        let current = try lines(of: url)
        #expect(current.count == 1)
        #expect(current.first?.hasSuffix(String(repeating: "c", count: 60)) == true)
    }
}
