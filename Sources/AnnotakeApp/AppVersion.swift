import Foundation

/// The app's version: `VERSION` and the commit count, written into Info.plist by the bundler (spec §9).
struct AppVersion: Equatable, CustomStringConvertible {
    static let fallbackShort = "0.0.0"
    static let fallbackBuild = "0"

    /// CFBundleShortVersionString, e.g. "0.2.0".
    var short: String
    /// CFBundleVersion, e.g. "74".
    var build: String

    /// "0.2.0 (74)"
    var description: String { "\(short) (\(build))" }

    /// Missing keys read as "0.0.0" and "0".
    static func from(infoDictionary: [String: Any]?) -> AppVersion {
        AppVersion(short: infoDictionary?["CFBundleShortVersionString"] as? String ?? fallbackShort,
                   build: infoDictionary?["CFBundleVersion"] as? String ?? fallbackBuild)
    }

    static var current: AppVersion { from(infoDictionary: Bundle.main.infoDictionary) }
}
