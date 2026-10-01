import AppKit
import ApplicationServices

/// Chrome's web content and Electron apps (Cursor, Slack) expose nothing to Accessibility until an app
/// flag is set (M0). Annotake sets it only while recording.
public enum WebAccessibilityFlags {
    public enum Kind: Sendable, Equatable {
        case chrome, electron
    }

    public static let chromeBundleIDs: Set<String> = ["com.google.Chrome"]
    static let electronFramework = "Contents/Frameworks/Electron Framework.framework"

    public static func kind(bundleID: String?, bundleURL: URL?, fileExists: (String) -> Bool) -> Kind? {
        if let bundleID, chromeBundleIDs.contains(bundleID) { return .chrome }
        if let bundleURL, fileExists(bundleURL.appending(path: electronFramework).path) { return .electron }
        return nil
    }

    /// The attribute each kind needs.
    static func attribute(for kind: Kind) -> String {
        switch kind {
        case .chrome: "AXEnhancedUserInterface"
        case .electron: "AXManualAccessibility"
        }
    }
}

/// Sets and clears the Chrome/Electron flags on the AX thread, and remembers which apps it set them
/// on, so it clears only those. Its state is confined to AXClient's thread.
public final class WebAccessibilityFlagSetter: @unchecked Sendable {
    /// Chrome answers kAXErrorNotImplemented when the flag is set, but the flag takes effect (M0).
    static let chromeIgnoredError = AXError.notImplemented

    private struct App: Sendable {
        let pid: pid_t
        let bundleID: String?
        let bundleURL: URL?
    }

    private let ax: AXClient
    private var flagged: [pid_t: String] = [:]

    public init(ax: AXClient) {
        self.ax = ax
    }

    /// At recording start: every running regular app that needs a flag.
    public func enableForRunningApps() {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map { App(pid: $0.processIdentifier, bundleID: $0.bundleIdentifier, bundleURL: $0.bundleURL) }
        ax.perform { [self] in
            let set = apps.filter(enable).count
            if set > 0 { InputLog.write("accessibility flags set on \(set) app(s)") }
        }
    }

    /// An app launched or activated during a recording.
    public func enable(for app: NSRunningApplication) {
        let app = App(pid: app.processIdentifier, bundleID: app.bundleIdentifier, bundleURL: app.bundleURL)
        ax.perform { [self] in
            if enable(app) { InputLog.write("accessibility flag set on a newly active app") }
        }
    }

    /// At stop: clears the flags Annotake set, unless VoiceOver is running and may rely on them.
    public func clearAll() {
        let voiceOver = NSWorkspace.shared.isVoiceOverEnabled
        ax.perform { [self] in
            defer { flagged = [:] }
            guard !flagged.isEmpty else { return }
            guard !voiceOver else {
                InputLog.write("VoiceOver is running; accessibility flags left set")
                return
            }
            for (pid, attribute) in flagged {
                AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), attribute as CFString, kCFBooleanFalse)
            }
            InputLog.write("accessibility flags cleared on \(flagged.count) app(s)")
        }
    }

    /// Sets the app's flag unless it's already set or the app needs none. True when Annotake set it.
    private func enable(_ app: App) -> Bool {
        guard flagged[app.pid] == nil,
              let kind = WebAccessibilityFlags.kind(bundleID: app.bundleID, bundleURL: app.bundleURL,
                                                    fileExists: FileManager.default.fileExists(atPath:))
        else { return false }
        let attribute = WebAccessibilityFlags.attribute(for: kind)
        let element = AXUIElementCreateApplication(app.pid)
        var current: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, attribute as CFString, &current) == .success,
           (current as? Bool) == true {
            return false
        }
        let result = AXUIElementSetAttributeValue(element, attribute as CFString, kCFBooleanTrue)
        guard result == .success || (kind == .chrome && result == Self.chromeIgnoredError) else { return false }
        flagged[app.pid] = attribute
        return true
    }
}
