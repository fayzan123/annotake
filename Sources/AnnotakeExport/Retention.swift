import Foundation

/// Moves captures older than the retention period to the Trash (spec §4.1). Only folders with a capture
/// marker (`.annotake`) are ever touched, and their age comes from the marker's date.
public enum Retention {
    static let secondsPerDay: TimeInterval = 86_400

    /// The captures whose marker is older than `days`; nil means keep forever.
    public static func expired(in store: CaptureStore, days: Int?, now: Date) -> [URL] {
        guard let days else { return [] }
        let cutoff = now.addingTimeInterval(-Double(days) * secondsPerDay)
        return store.captures().filter { $0.date < cutoff }.map(\.url)
    }

    /// Trashes each expired capture, carrying on past failures. Returns what it trashed.
    @discardableResult
    public static func run(in store: CaptureStore, days: Int?, now: Date, trash: (URL) throws -> Void) -> [URL] {
        expired(in: store, days: days, now: now).filter { url in
            (try? trash(url)) != nil
        }
    }
}
