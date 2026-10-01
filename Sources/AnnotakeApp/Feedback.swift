import AppKit

/// Send Feedback… (spec §3.5, §8): a draft to `address` with the facts, the recent log, and the latest crash
/// report. It only prepares the draft; the user sends it. The log never holds labels, window titles, or keys.
enum Feedback {
    /// The one place the address is defined: Fayzan's own inbox, until feedback@annotake.app receives mail.
    static let address = "fayzanm786@gmail.com"
    static let logLines = 400
    static let crashReportMaxAge: TimeInterval = 7 * 86_400
    static let crashReportMaxBytes = 200_000
    static let mailtoBodyLimit = 1_500
    static let crashReportPrefix = "Annotake-"
    static let crashReportExtension = "ips"
    static let truncatedLine = "… (truncated)"
    static let prompt = "What happened?\n\n\n"
    static let attachPlea = "The full report is in Finder; please attach it."

    struct Facts: Equatable {
        var version: AppVersion
        /// e.g. "15.7.9"
        var macOS: String
        /// sysctl hw.model, e.g. "Mac16,1"
        var model: String
        var permissions: Permissions.Status
    }

    enum Delivery: Equatable {
        /// Mail's compose window, with the report attached.
        case composeWithAttachment
        /// The default mail app gets a mailto draft, and Finder shows the report to attach.
        case mailtoAndReveal
    }

    /// "Annotake feedback — 0.2.0 (74)"
    static func subject(_ version: AppVersion) -> String {
        "Annotake feedback — \(version)"
    }

    /// The three fact lines.
    static func summary(_ facts: Facts) -> String {
        func yesNo(_ granted: Bool) -> String { granted ? "yes" : "no" }
        let permissions = facts.permissions
        return """
            Annotake \(facts.version)
            macOS \(facts.macOS) · \(facts.model)
            Permissions: screen recording \(yesNo(permissions.screenRecording)), \
            input monitoring \(yesNo(permissions.inputMonitoring)), accessibility \(yesNo(permissions.accessibility))
            """
    }

    /// The summary, the last `logLines` of the log, and the crash report, capped at `crashReportMaxBytes`.
    static func report(_ facts: Facts, log: String?, crash: (name: String, text: String)?) -> String {
        var sections = [summary(facts)]
        let logText = log.map { tail($0, lines: logLines) }.flatMap { $0.isEmpty ? nil : $0 } ?? "No log yet."
        sections.append("--- Recent log (last \(logLines) lines) ---\n" + logText.trimmingCharacters(in: .newlines))
        if let crash {
            sections.append(cappedCrashSection(name: crash.name, text: crash.text))
        } else {
            sections.append("No crash report in the last \(Int(crashReportMaxAge / 86_400)) days.")
        }
        return sections.joined(separator: "\n\n") + "\n"
    }

    /// The header and the crash text, at most `crashReportMaxBytes` in all, cut at a line when it's too long.
    private static func cappedCrashSection(name: String, text: String) -> String {
        let header = "--- Crash report: \(name) ---\n"
        let whole = header + text.trimmingCharacters(in: .newlines)
        guard whole.utf8.count > crashReportMaxBytes else { return whole }
        let budget = crashReportMaxBytes - header.utf8.count - ("\n" + truncatedLine).utf8.count
        var kept = ""
        var used = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let cost = line.utf8.count + 1
            guard used + cost <= budget else { break }
            kept += line + "\n"
            used += cost
        }
        return header + kept + truncatedLine
    }

    /// The last `lines` lines, keeping a final newline; shorter text comes back unchanged.
    static func tail(_ text: String, lines: Int) -> String {
        let endsWithNewline = text.hasSuffix("\n")
        var all = text.split(separator: "\n", omittingEmptySubsequences: false)
        if endsWithNewline { all.removeLast() }
        guard all.count > lines else { return text }
        return all.suffix(lines).joined(separator: "\n") + (endsWithNewline ? "\n" : "")
    }

    /// The newest `Annotake-*.ips` in `directory`, by modification date, at most `crashReportMaxAge` old.
    static func latestCrashReport(in directory: URL, now: Date) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix(crashReportPrefix) && $0.pathExtension == crashReportExtension }
            .compactMap { url -> (URL, Date)? in
                guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      now.timeIntervalSince(date) <= crashReportMaxAge
                else { return nil }
                return (url, date)
            }
            .max { $0.1 < $1.1 }?.0
    }

    /// A mailto draft to `address`. The body is cut to `mailtoBodyLimit` characters, because mail apps and
    /// browsers truncate long mailto URLs unpredictably.
    static func mailtoURL(subject: String, body: String) -> URL {
        let capped = body.count > mailtoBodyLimit ? String(body.prefix(mailtoBodyLimit - 1)) + "…" : body
        // Only RFC 3986's unreserved characters stay as they are; everything else is percent-encoded.
        let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        func encode(_ text: String) -> String {
            text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
        }
        return URL(string: "mailto:\(address)?subject=\(encode(subject))&body=\(encode(capped))")!
    }

    static func delivery(canComposeWithAttachment: Bool) -> Delivery {
        canComposeWithAttachment ? .composeWithAttachment : .mailtoAndReveal
    }
}

// MARK: - The menu action

extension Feedback {
    static var diagnosticReports: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/DiagnosticReports")
    }

    static func currentFacts() -> Facts {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return Facts(version: .current, macOS: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                     model: hardwareModel(), permissions: Permissions.status())
    }

    /// sysctl hw.model, e.g. "Mac16,1".
    static func hardwareModel() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "unknown Mac" }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "unknown Mac" }
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }

    /// Writes the report to a temporary file, then opens a draft with it: Mail's compose window when it can
    /// take the attachment, otherwise a mailto draft, with the report shown in Finder.
    @MainActor
    static func send() {
        LogFile.shared.flush()
        let facts = currentFacts()
        let logText = try? String(contentsOf: LogFile.shared.url, encoding: .utf8)
        let crash = latestCrashReport(in: diagnosticReports, now: Date()).flatMap { url in
            (try? String(contentsOf: url, encoding: .utf8)).map { (name: url.lastPathComponent, text: $0) }
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let reportURL = FileManager.default.temporaryDirectory
            .appending(path: "Annotake-report-\(formatter.string(from: Date())).txt")
        do {
            try report(facts, log: logText, crash: crash).write(to: reportURL, atomically: true, encoding: .utf8)
        } catch {
            log("feedback report couldn't be written (error \((error as NSError).code))")
            return
        }

        let body = prompt + summary(facts)
        let service = NSSharingService(named: .composeEmail)
        service?.recipients = [address]
        service?.subject = subject(facts.version)
        let items: [Any] = [body, reportURL]
        switch delivery(canComposeWithAttachment: service?.canPerform(withItems: items) ?? false) {
        case .composeWithAttachment:
            service?.perform(withItems: items)
        case .mailtoAndReveal:
            NSWorkspace.shared.open(mailtoURL(subject: subject(facts.version), body: body + "\n\n" + attachPlea))
            NSWorkspace.shared.activateFileViewerSelecting([reportURL])
        }
        log("feedback report prepared")
    }
}
