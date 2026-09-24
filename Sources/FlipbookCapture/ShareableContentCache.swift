import AppKit
@preconcurrency import ScreenCaptureKit

/// The screen/window list for starting a capture (spec §6.2, §7). Each start makes one fresh query with a
/// timeout, and falls back to the last good answer, which is refreshed at launch and on display changes.
/// Used on the main thread.
public final class ShareableContentCache: @unchecked Sendable {
    public static let timeout: TimeInterval = 2
    static let permissionDeniedCode = SCStreamError.Code.userDeclined.rawValue

    private var cached: (snapshot: ContentSnapshot, content: SCShareableContent)?

    public init() {}

    /// One query that includes off-screen windows (it finds Notification Center on macOS 15) and leaves
    /// out desktop windows. Falls back to the cache on timeout or failure. Throws `.permissionDenied` on
    /// SCStreamErrorDomain −3801, and `.contentUnavailable` with neither an answer nor a cache.
    @MainActor
    public func current() async throws -> (snapshot: ContentSnapshot, content: SCShareableContent) {
        do {
            let content = try await Self.withTimeout(Self.timeout) {
                try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            }
            let entry = (snapshot: ContentSnapshot(content), content: content)
            cached = entry
            return entry
        } catch let error as NSError where error.domain == SCStreamErrorDomain && error.code == Self.permissionDeniedCode {
            throw CaptureError.permissionDenied
        } catch {
            if let cached { return cached }
            throw CaptureError.contentUnavailable
        }
    }

    /// Refreshes the cache in the background: at launch, and when the displays change.
    @MainActor
    public func refresh() {
        Task { @MainActor in
            _ = try? await self.current()
        }
    }

    /// The content of this process alone, which needs no Screen Recording permission (macOS 14.4+).
    /// The self-test records its own window this way.
    @MainActor
    public static func ownProcess() async throws -> (snapshot: ContentSnapshot, content: SCShareableContent) {
        let content = try await withTimeout(timeout) { try await SCShareableContent.currentProcess }
        return (ContentSnapshot(content), content)
    }

    /// The operation's result, or `.contentUnavailable` once `seconds` pass. A hung query is abandoned,
    /// not waited for.
    static func withTimeout<T>(_ seconds: TimeInterval,
                               _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let gate = ResumeOnce(continuation)
            let timer = Task {
                try? await Task.sleep(for: .seconds(seconds))
                if !Task.isCancelled { gate.resume(.failure(CaptureError.contentUnavailable)) }
            }
            Task {
                do {
                    gate.resume(.success(try await operation()))
                } catch {
                    gate.resume(.failure(error))
                }
                timer.cancel()
            }
        }
    }
}

/// Resumes a continuation the first time only. Its state is guarded by `lock`.
private final class ResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: sending Result<T, Error>) {
        let pending = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(with: result)
    }
}

extension ContentSnapshot {
    /// Value copies of the query's displays, windows and apps. Display names come from NSScreen.
    @MainActor
    public init(_ content: SCShareableContent) {
        let screens = NSScreen.screens
        let displays = content.displays.map { display in
            let id = display.displayID
            let screen = screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
            }
            let uuid = CGDisplayCreateUUIDFromDisplayID(id).map {
                CFUUIDCreateString(nil, $0.takeRetainedValue()) as String
            } ?? "\(id)"
            let pixelSize = CGDisplayCopyDisplayMode(id).map { CGSize(width: $0.pixelWidth, height: $0.pixelHeight) }
                ?? CGSize(width: display.width, height: display.height)
            return DisplayInfo(id: id, uuid: uuid, name: screen?.localizedName ?? "Display \(id)",
                               frame: CGDisplayBounds(id), pixelSize: pixelSize)
        }
        let windows = content.windows.map { window in
            WindowInfo(id: window.windowID, frame: window.frame, title: window.title, layer: window.windowLayer,
                       isOnScreen: window.isOnScreen, ownerBundleID: window.owningApplication?.bundleIdentifier,
                       ownerName: window.owningApplication?.applicationName ?? "")
        }
        self.init(displays: displays, windows: windows,
                  appBundleIDs: content.applications.map(\.bundleIdentifier))
    }
}
