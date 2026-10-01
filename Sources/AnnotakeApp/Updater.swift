/// Checks for and installs new versions (spec §6.2). The executable injects a Sparkle-backed one, so the
/// libraries and their tests link no network code.
@MainActor
public protocol Updater: AnyObject {
    /// "Check for Updates…": checks now and shows the result.
    func checkForUpdates()
}
