/// Checks for and installs new versions (spec §6.2). The executable injects a Sparkle-backed one, so Sparkle stays
/// out of the libraries, and tests, --selftest, and --render-ui never check for updates.
@MainActor
public protocol Updater: AnyObject {
    /// "Check for Updates…": checks now and shows the result.
    func checkForUpdates()
}
