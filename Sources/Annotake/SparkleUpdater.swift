import AnnotakeApp
import Sparkle

/// Sparkle 2's standard updater. It checks the feed once a day, sending only the app's version, and asks
/// before installing (spec §6.2). Its settings are in Info.plist (SUFeedURL, SUPublicEDKey, …).
@MainActor
final class SparkleUpdater: Updater {
    private let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil,
                                                          userDriverDelegate: nil)

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
