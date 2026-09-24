import FlipbookExport

/// The last captures, found on disk by their markers, so the list survives a relaunch (spec §3.4).
enum RecentCaptures {
    static let limit = 5

    /// Newest first. Captures whose capture.json can't be read are skipped.
    static func latest(in store: CaptureStore, limit: Int = limit) -> [FinishedCapture] {
        var found: [FinishedCapture] = []
        for folder in store.captures() where found.count < limit {
            if let capture = try? CaptureExporter.load(folder.url) {
                found.append(capture)
            }
        }
        return found
    }

    /// e.g. `2026-09-23 at 14.05.12 · 8 frames`
    static func title(for capture: FinishedCapture) -> String {
        let count = capture.manifest.result.frames.count
        return "\(capture.manifest.name) · \(count == 1 ? "1 frame" : "\(count) frames")"
    }
}
