@testable import AnnotakeApp
import Foundation
import Testing

struct FeedbackTests {
    let facts = Feedback.Facts(
        version: AppVersion(short: "0.2.0", build: "74"), macOS: "15.7.9", model: "Mac16,1",
        permissions: Permissions.Status(screenRecording: true, inputMonitoring: true, accessibility: false))

    @Test func summaryHasVersionMacAndPermissions() {
        #expect(Feedback.summary(facts) == """
            Annotake 0.2.0 (74)
            macOS 15.7.9 · Mac16,1
            Permissions: screen recording yes, input monitoring yes, accessibility no
            """)
        #expect(Feedback.subject(facts.version) == "Annotake feedback — 0.2.0 (74)")
    }

    @Test func tailKeepsTheLastLines() {
        let long = (1...1000).map { "line \($0)" }.joined(separator: "\n") + "\n"
        let tail = Feedback.tail(long, lines: Feedback.logLines)
        let lines = tail.split(separator: "\n")
        #expect(lines.count == 400)
        #expect(lines.first == "line 601")
        #expect(lines.last == "line 1000")
        let short = (1...10).map { "line \($0)" }.joined(separator: "\n") + "\n"
        #expect(Feedback.tail(short, lines: Feedback.logLines) == short)
    }

    @Test func latestCrashReportIsNewestRecentAnnotake() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "annotake-crash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        func report(_ name: String, daysOld: Double) throws -> URL {
            let url = directory.appending(path: name)
            try Data("{}".utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-daysOld * 86_400)],
                                                  ofItemAtPath: url.path)
            return url
        }
        let recent = try report("Annotake-2026-10-01-101112.ips", daysOld: 2)
        _ = try report("Annotake-2026-09-20-090000.ips", daysOld: 12)
        _ = try report("Finder-2026-10-02-080000.ips", daysOld: 1)
        _ = try report("Other-2026-10-02-080000.ips", daysOld: 1)

        #expect(Feedback.latestCrashReport(in: directory, now: now)?.lastPathComponent == recent.lastPathComponent)
        try FileManager.default.removeItem(at: recent)
        #expect(Feedback.latestCrashReport(in: directory, now: now) == nil)
        #expect(Feedback.latestCrashReport(in: directory.appending(path: "missing"), now: now) == nil)
    }

    @Test func crashReportIsCapped() throws {
        let crash = String(repeating: "0123456789abcdef\n", count: 500_000 / 17)
        let report = Feedback.report(facts, log: "launched\n", crash: (name: "Annotake-2026-10-01-101112.ips", text: crash))
        let start = try #require(report.range(of: "--- Crash report: Annotake-2026-10-01-101112.ips ---"))
        let section = String(report[start.lowerBound...])
        #expect(section.utf8.count <= Feedback.crashReportMaxBytes)
        #expect(section.trimmingCharacters(in: .newlines).hasSuffix("\n… (truncated)"))
        #expect(report.hasPrefix(Feedback.summary(facts)))
        #expect(report.contains("--- Recent log (last 400 lines) ---\nlaunched"))
    }

    @Test func noCrashReportSaysSo() {
        let report = Feedback.report(facts, log: nil, crash: nil)
        #expect(report.contains("No crash report in the last 7 days."))
        #expect(report.contains("No log yet."))
        #expect(!report.contains("--- Crash report"))
    }

    @Test func mailtoIsEncodedAndCapped() throws {
        let url = Feedback.mailtoURL(subject: Feedback.subject(facts.version),
                                     body: String(repeating: "é and more", count: 500))
        #expect(url.scheme == "mailto")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "fayzanm786@gmail.com")
        #expect(!url.absoluteString.contains(" "))
        #expect(!url.absoluteString.contains("—"))
        #expect(url.absoluteString.contains("Annotake%20feedback%20%E2%80%94%200.2.0"))
        let items = components.queryItems ?? []
        #expect(items.first { $0.name == "subject" }?.value == "Annotake feedback — 0.2.0 (74)")
        let body = try #require(items.first { $0.name == "body" }?.value)
        #expect(body.count <= Feedback.mailtoBodyLimit)
        #expect(body.hasPrefix("é and more"))
    }

    @Test func fallsBackWithoutMailApp() {
        #expect(Feedback.delivery(canComposeWithAttachment: false) == .mailtoAndReveal)
        #expect(Feedback.delivery(canComposeWithAttachment: true) == .composeWithAttachment)
    }
}
