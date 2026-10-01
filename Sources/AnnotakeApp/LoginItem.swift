import AppKit
import ServiceManagement

/// Launch at login is registered only from an Applications folder, so a development build never
/// leaves a stale login item (spec §3.7).
enum LoginItemPolicy {
    static func canRegister(bundleURL: URL, home: URL) -> Bool {
        let path = bundleURL.standardizedFileURL.path
        return path.hasPrefix("/Applications/") || path.hasPrefix(home.standardizedFileURL.path + "/Applications/")
    }
}

/// The login item, through SMAppService.
@MainActor
enum LoginItem {
    enum Availability: Equatable {
        case available, requiresApproval, notInApplications
    }

    static let initializedKey = "loginItem.initialized"

    static var availability: Availability {
        guard LoginItemPolicy.canRegister(bundleURL: Bundle.main.bundleURL,
                                          home: FileManager.default.homeDirectoryForCurrentUser) else {
            return .notInApplications
        }
        return SMAppService.mainApp.status == .requiresApproval ? .requiresApproval : .available
    }

    static func set(_ enabled: Bool) {
        guard availability != .notInApplications else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            log("launch at login \(enabled ? "on" : "off")")
        } catch {
            log("launch at login couldn't be changed: \(error)")
        }
    }

    /// Registers once, on the first launch from an Applications folder, if the setting is on. Later
    /// launches leave it alone, so turning it off in System Settings sticks.
    static func registerOnFirstLaunch(enabled: Bool, defaults: UserDefaults) {
        guard availability != .notInApplications, !defaults.bool(forKey: initializedKey) else { return }
        defaults.set(true, forKey: initializedKey)
        if enabled { set(true) }
    }
}
