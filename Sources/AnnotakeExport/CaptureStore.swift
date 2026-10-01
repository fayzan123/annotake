import Foundation

public enum CaptureStoreError: Error, Equatable {
    case saveLocationUnavailable(path: String)
    case cannotRemoveAllFrames
    case missingRawFrame(frameIndex: Int)
}

/// A capture folder that has a readable marker.
public struct CaptureFolder: Sendable, Equatable {
    public let url: URL
    /// The capture's date, from its marker.
    public let date: Date
}

/// A capture being written, in the save location's temp folder.
public struct PendingCapture: Sendable {
    /// `<root>/.annotake-tmp/<UUID>`
    public let directory: URL

    public var rawDirectory: URL { directory.appending(path: CaptureStore.rawFolderName) }

    /// `.raw/frame-000017.png`
    public func rawFrameURL(frameIndex: Int) -> URL {
        rawDirectory.appending(path: CaptureStore.rawFrameName(frameIndex: frameIndex))
    }

    /// Removes the directory. Never throws.
    public func discard() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// The save location (spec §4.1). Captures are written to a temp folder inside it and moved into place
/// once complete, a rename on the same volume, so nothing half-written ever lands among the captures.
public struct CaptureStore: Sendable {
    /// Marks a folder as a capture and holds its date; cleanup only ever touches folders that have it.
    public static let markerName = ".annotake"
    public static let legacyMarkerName = ".flipbook"   // read-only: captures made by Flipbook
    public static let tempFolderName = ".annotake-tmp"
    public static let rawFolderName = ".raw"

    /// The save location.
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    private var tempRoot: URL { root.appending(path: Self.tempFolderName) }

    /// An unrendered picked frame's file name inside `.raw`, e.g. `frame-000017.png`.
    static func rawFrameName(frameIndex: Int) -> String {
        String(format: "frame-%06d.png", frameIndex)
    }

    /// e.g. "2026-09-23 at 14.05.12"
    public static func folderName(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: date)
    }

    /// Creates the save location if needed, and a temp capture folder with its `.raw` folder.
    /// Throws `.saveLocationUnavailable` when the save location can't be written, e.g. a read-only
    /// folder, a file in its place, or an unplugged disk.
    public func begin() throws -> PendingCapture {
        let pending = PendingCapture(directory: tempRoot.appending(path: UUID().uuidString))
        do {
            try FileManager.default.createDirectory(at: pending.rawDirectory, withIntermediateDirectories: true)
        } catch {
            throw CaptureStoreError.saveLocationUnavailable(path: root.path)
        }
        guard FileManager.default.isWritableFile(atPath: pending.rawDirectory.path) else {
            pending.discard()
            throw CaptureStoreError.saveLocationUnavailable(path: root.path)
        }
        return pending
    }

    /// Writes the marker (only ever `markerName`), then moves the capture to `<root>/<name>`, or "<name> (2)", "<name> (3)" …
    /// when the name is taken.
    public func commit(_ pending: PendingCapture, name: String, date: Date) throws -> URL {
        try Data(ISO8601DateFormatter().string(from: date).utf8)
            .write(to: pending.directory.appending(path: Self.markerName), options: .atomic)
        var attempt = 1
        while true {
            let destination = root.appending(path: attempt == 1 ? name : "\(name) (\(attempt))")
            if !FileManager.default.fileExists(atPath: destination.path) {
                do {
                    try FileManager.default.moveItem(at: pending.directory, to: destination)
                    return destination
                } catch CocoaError.fileWriteFileExists {
                    // Taken between the check and the move; try the next name.
                }
            }
            attempt += 1
        }
    }

    /// Deletes captures left half-written by a crash.
    public func removeLeftovers() {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    /// Subfolders with a readable marker, newest first.
    public func captures() -> [CaptureFolder] {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
        return folders
            .compactMap { url in Self.readMarker(in: url).map { CaptureFolder(url: url, date: $0) } }
            .sorted { $0.date > $1.date }
    }

    /// The date in the folder's marker (ISO 8601), or nil without a readable one. Without a readable
    /// `markerName`, the legacy marker counts, so captures that migration couldn't reach stay listed and
    /// still expire (spec §3.8).
    public static func readMarker(in folder: URL) -> Date? {
        date(inMarker: folder.appending(path: markerName)) ?? date(inMarker: folder.appending(path: legacyMarkerName))
    }

    private static func date(inMarker url: URL) -> Date? {
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return nil }
        return ISO8601DateFormatter().date(from: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
