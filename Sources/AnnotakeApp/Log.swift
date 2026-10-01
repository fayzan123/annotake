import Foundation

/// An append-only text log capped at `cap` bytes, with one rotation (spec §8).
/// It never receives labels, window titles, or keys.
/// All file work happens on `queue`, a private serial queue.
public final class LogFile: @unchecked Sendable {
    public static let shared = LogFile(
        url: FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Annotake.log"),
        cap: 5 * 1024 * 1024)

    let url: URL
    private let cap: Int
    private let queue = DispatchQueue(label: "com.fayzanmalik.annotake.log")
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    public init(url: URL, cap: Int) {
        self.url = url
        self.cap = cap
    }

    /// Appends `<timestamp> <line>` and returns at once; the write happens on the log's queue.
    public func write(_ line: String) {
        let now = Date()
        queue.async {
            self.append(Data("\(self.formatter.string(from: now)) \(line)\n".utf8))
        }
    }

    /// Waits for every earlier write to reach the file.
    func flush() {
        queue.sync {}
    }

    private func append(_ data: Data) {
        let files = FileManager.default
        let size = (try? files.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if size > 0 && size + data.count > cap {
            let rotated = url.appendingPathExtension("1")
            try? files.removeItem(at: rotated)
            try? files.moveItem(at: url, to: rotated)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url)
        }
    }
}

/// Writes one line to the shared log.
func log(_ line: String) {
    LogFile.shared.write(line)
}
