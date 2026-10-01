import AppKit
import AnnotakeCore
import ServiceManagement
import SwiftUI

/// The first-launch checklist's rules (spec §3.7).
struct ChecklistModel: Equatable {
    enum Permission: String, CaseIterable, Codable, Identifiable {
        case screenRecording, inputMonitoring, accessibility

        var id: Self { self }
    }

    enum RowState: Equatable {
        case granted, notRequested, requested
    }

    enum ButtonAction: Equatable {
        case prompt, openSettings
    }

    /// What survives Quit & Reopen, so the window reopens where it left off.
    struct Persisted: Codable, Equatable {
        var requested: Set<Permission> = []
        var completed = false
    }

    private(set) var granted: [Permission: Bool]
    private(set) var persisted: Persisted

    init(granted: [Permission: Bool], persisted: Persisted) {
        self.granted = granted
        self.persisted = persisted
    }

    func state(of permission: Permission) -> RowState {
        if granted[permission] == true { return .granted }
        return persisted.requested.contains(permission) ? .requested : .notRequested
    }

    /// Screen Recording and Input Monitoring only apply after a relaunch (M0).
    var showsQuitAndReopen: Bool {
        [Permission.screenRecording, .inputMonitoring].contains { state(of: $0) == .requested }
    }

    var allGranted: Bool {
        Permission.allCases.allSatisfy { granted[$0] == true }
    }

    /// The first press shows the system prompt; later presses open System Settings.
    mutating func buttonPressed(_ permission: Permission) -> ButtonAction {
        guard !persisted.requested.contains(permission) else { return .openSettings }
        persisted.requested.insert(permission)
        return .prompt
    }

    mutating func update(granted: [Permission: Bool]) {
        self.granted = granted
    }

    mutating func complete() {
        persisted.completed = true
    }
}

extension Permissions.Status {
    var byPermission: [ChecklistModel.Permission: Bool] {
        [.screenRecording: screenRecording, .inputMonitoring: inputMonitoring, .accessibility: accessibility]
    }
}

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

// MARK: - The checklist window

/// The checklist's live state: permissions polled every second, requests remembered across relaunches.
@MainActor
final class ChecklistViewModel: ObservableObject {
    static let storeKey = "firstLaunch.v1"
    static let pollInterval: TimeInterval = 1

    @Published private(set) var model: ChecklistModel
    let trigger: TriggerKey
    private let defaults: UserDefaults?
    private let status: () -> Permissions.Status
    private var timer: Timer?

    /// With no defaults (UI snapshots), nothing is saved.
    init(trigger: TriggerKey, defaults: UserDefaults?, status: @escaping () -> Permissions.Status = Permissions.status,
         persisted: ChecklistModel.Persisted? = nil) {
        self.trigger = trigger
        self.defaults = defaults
        self.status = status
        let saved = persisted ?? defaults.flatMap(Self.load) ?? ChecklistModel.Persisted()
        model = ChecklistModel(granted: status().byPermission, persisted: saved)
    }

    static func load(from defaults: UserDefaults) -> ChecklistModel.Persisted? {
        defaults.data(forKey: storeKey).flatMap { try? JSONDecoder().decode(ChecklistModel.Persisted.self, from: $0) }
    }

    var completed: Bool { model.persisted.completed }

    func startPolling() {
        timer?.invalidate()
        timer = Timer.onMainRunLoop(interval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        model.update(granted: status().byPermission)
    }

    func press(_ permission: ChecklistModel.Permission) {
        switch model.buttonPressed(permission) {
        case .prompt: Permissions.request(permission)
        case .openSettings: NSWorkspace.shared.open(Self.pane(for: permission))
        }
        save()
        refresh()
    }

    /// Saves where the checklist is, quits, and reopens Annotake a second later.
    func quitAndReopen() {
        save()
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        do {
            try relaunch.run()
        } catch {
            log("couldn't schedule the reopen: \(error)")
        }
        NSApp.terminate(nil)
    }

    func complete() {
        model.complete()
        save()
    }

    private func save() {
        guard let defaults, let data = try? JSONEncoder().encode(model.persisted) else { return }
        defaults.set(data, forKey: Self.storeKey)
    }

    static func pane(for permission: ChecklistModel.Permission) -> URL {
        switch permission {
        case .screenRecording: PermissionPane.screenRecording
        case .inputMonitoring: PermissionPane.inputMonitoring
        case .accessibility: PermissionPane.accessibility
        }
    }
}

struct ChecklistView: View {
    static let width: CGFloat = 520
    @ObservedObject var viewModel: ChecklistViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Set up Annotake").font(.title2).bold()
                Text("Annotake needs three permissions. Each button asks macOS; after that it opens the right page in System Settings.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                ForEach(ChecklistModel.Permission.allCases) { permission in
                    row(permission)
                    if permission != ChecklistModel.Permission.allCases.last { Divider() }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.1)))

            if viewModel.model.showsQuitAndReopen {
                HStack(spacing: 12) {
                    Text("Screen Recording and Input Monitoring start working after Annotake reopens.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Quit & Reopen") { viewModel.quitAndReopen() }
                        .keyboardShortcut(.defaultAction)
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "hand.tap").font(.title3).foregroundStyle(Color.accentColor)
                Text("Double-tap \(Self.keyName(viewModel.trigger)) to try it.").font(.headline)
            }
        }
        .padding(24)
        .frame(width: Self.width)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    static func keyName(_ trigger: TriggerKey) -> String {
        trigger == .fn ? "fn" : "Right \(PillText.glyph(trigger))"
    }

    static func name(_ permission: ChecklistModel.Permission) -> String {
        switch permission {
        case .screenRecording: "Screen Recording"
        case .inputMonitoring: "Input Monitoring"
        case .accessibility: "Accessibility"
        }
    }

    static func reason(_ permission: ChecklistModel.Permission) -> String {
        switch permission {
        case .screenRecording: "Required to record."
        case .inputMonitoring: "Needed to see the trigger key, clicks, and keys."
        case .accessibility: "Needed for click cleanup and button names."
        }
    }

    private func row(_ permission: ChecklistModel.Permission) -> some View {
        let state = viewModel.model.state(of: permission)
        return HStack(spacing: 12) {
            Image(systemName: state == .granted ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(state == .granted ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.name(permission))
                Text(Self.reason(permission)).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            switch state {
            case .granted:
                Text("Granted").foregroundStyle(.secondary)
            case .notRequested:
                Button("Allow…") { viewModel.press(permission) }
            case .requested:
                Button("Open System Settings") { viewModel.press(permission) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

/// Shows the checklist at launch until the first recording, and from "Fix permissions…".
@MainActor
final class FirstLaunchController: NSObject, NSWindowDelegate {
    private let viewModel: ChecklistViewModel
    private var window: NSWindow?

    init(trigger: TriggerKey, defaults: UserDefaults) {
        viewModel = ChecklistViewModel(trigger: trigger, defaults: defaults)
    }

    func showIfNeeded() {
        if !viewModel.completed { show() }
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: ChecklistView(viewModel: viewModel)))
            window.title = "Welcome to Annotake"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        viewModel.refresh()
        viewModel.startPolling()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// The first recording closes the checklist for good.
    func recordingSaved() {
        guard !viewModel.completed else { return }
        viewModel.complete()
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        viewModel.stopPolling()
    }
}
