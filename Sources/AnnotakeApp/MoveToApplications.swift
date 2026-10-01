import AppKit

/// Opened from the disk image or Downloads, Annotake offers to move itself to Applications, where it can
/// start at login (spec §3.7). A copy opened from a quarantined download runs translocated, from a random
/// read-only path, so the move starts from the original location.
enum MoveToApplications {
    enum Decision: Equatable {
        case stay
        case offer(destination: URL)
    }

    static let declinedKey = "moveToApplications.declined"
    static let appName = "Annotake.app"
    static let systemApplications = URL(fileURLWithPath: "/Applications")

    /// Pure: stay where launch at login works; otherwise offer /Applications when it's writable, else
    /// ~/Applications.
    static func decision(bundleURL: URL, home: URL, systemApplicationsWritable: Bool) -> Decision {
        if LoginItemPolicy.canRegister(bundleURL: bundleURL, home: home) { return .stay }
        let folder = systemApplicationsWritable ? systemApplications : home.appending(path: "Applications")
        return .offer(destination: folder.appending(path: appName))
    }

    /// Gatekeeper runs a quarantined app opened from a disk image or Downloads from a copy under
    /// /AppTranslocation/.
    static func isTranslocated(_ url: URL) -> Bool {
        url.path.contains("/AppTranslocation/")
    }

    /// Glue: asks once, and on "Move to Applications" copies Annotake there, relaunches the copy, and quits.
    /// Every failure is logged and shown, and Annotake keeps running where it is.
    @MainActor
    static func offerIfNeeded(defaults: UserDefaults) {
        let bundle = Bundle.main.bundleURL
        let decision = decision(bundleURL: bundle, home: FileManager.default.homeDirectoryForCurrentUser,
                                systemApplicationsWritable: FileManager.default.isWritableFile(atPath: systemApplications.path))
        guard case .offer(let destination) = decision, !defaults.bool(forKey: declinedKey) else { return }

        let alert = NSAlert()
        alert.messageText = "Move Annotake to Applications?"
        alert.informativeText = "Annotake needs to be in Applications to start when you log in."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else {
            defaults.set(true, forKey: declinedKey)
            log("move to Applications: not now")
            return
        }
        do {
            try move(from: originalLocation(of: bundle), to: destination)
        } catch {
            log("move to Applications failed (error \((error as NSError).code))")
            let failure = NSAlert()
            failure.messageText = "Couldn't move Annotake: \(error.localizedDescription)"
            failure.runModal()
        }
    }

    /// Where the user's copy really is: for a translocated app, the original path, from Security.framework's
    /// SecTranslocateCreateOriginalPathForURL, which has no public header; otherwise the bundle itself.
    static func originalLocation(of bundle: URL) -> URL {
        guard isTranslocated(bundle),
              let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let symbol = dlsym(security, "SecTranslocateCreateOriginalPathForURL")
        else { return bundle }
        typealias OriginalPath = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        let originalPath = unsafeBitCast(symbol, to: OriginalPath.self)
        return originalPath(bundle as CFURL, nil).map { $0.takeRetainedValue() as URL } ?? bundle
    }

    /// Replaces any copy at `destination`, copies `source` there, moves `source` to the Trash unless it's on a
    /// read-only volume (the disk image), then relaunches from `destination` and quits.
    @MainActor
    private static func move(from source: URL, to destination: URL) throws {
        let files = FileManager.default
        try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if files.fileExists(atPath: destination.path) {
            try files.trashItem(at: destination, resultingItemURL: nil)
        }
        try files.copyItem(at: source, to: destination)
        // The user chose to run this copy, and Gatekeeper already checked it at this launch.
        let unquarantine = Process()
        unquarantine.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        unquarantine.arguments = ["-dr", "com.apple.quarantine", destination.path]
        try? unquarantine.run()
        unquarantine.waitUntilExit()

        let readOnly = (try? source.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) ?? true
        if !readOnly {
            do {
                try files.trashItem(at: source, resultingItemURL: nil)
            } catch {
                log("move to Applications: the original stays (error \((error as NSError).code))")
            }
        }
        log("move to Applications: moved, relaunching")
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", destination.path]
        try relaunch.run()
        NSApp.terminate(nil)
    }
}
