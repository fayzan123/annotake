import AppKit
import Combine
import AnnotakeCore
import SwiftUI

/// Settings text that tests pin.
enum SettingsText {
    /// 0.25 → "250 ms"
    static func milliseconds(_ seconds: TimeInterval) -> String {
        "\(Int((seconds * 1000).rounded())) ms"
    }

    /// Spec §3.6, verbatim.
    static let fnWarnings = [
        #"macOS's "Press 🌐 key to" setting must be "Do Nothing"."#,
        "Dictation apps (Wispr Flow, Handy) often use fn already.",
        "Some third-party keyboards handle fn themselves and never send it to macOS, "
            + "so fn works reliably only on Apple keyboards.",
    ]

    static func target(_ target: Settings.RecordTarget) -> String {
        switch target {
        case .cursorScreen: "Screen with the cursor"
        case .screen: "A specific screen"
        case .window(_, let title): title.isEmpty ? "A window" : "Window: \(title)"
        }
    }

    /// The path with the home folder shown as ~.
    static func path(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }

    /// General's Email row (email list design §3.3), and the title of the sheet its button opens.
    static let emailRow = "Email"
    static let changeEmail = "Change…"
    static let noEmail = "Not set"
    static let changeEmailTitle = "Change your email"

    /// The Email row's text: the saved address, as it was saved, or Not set.
    static func email(_ record: EmailRecord?) -> String {
        record?.address ?? noEmail
    }
}

/// System Settings panes for each permission.
enum PermissionPane {
    static let screenRecording = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
    static let inputMonitoring = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
    static let accessibility = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
}

/// The settings the window shows. Every change goes through SettingsStore, which clamps it.
@MainActor
final class SettingsModel: ObservableObject {
    @Published private(set) var settings: Settings
    private let store: SettingsStore
    /// Called with the old and new settings after each change.
    var onChange: ((Settings, Settings) -> Void)?

    init(store: SettingsStore) {
        self.store = store
        settings = store.settings
    }

    func binding<Value>(_ keyPath: WritableKeyPath<Settings, Value>) -> Binding<Value> {
        Binding(get: { self.settings[keyPath: keyPath] },
                set: { value in self.update { $0[keyPath: keyPath] = value } })
    }

    func update(_ change: (inout Settings) -> Void) {
        let old = settings
        var new = settings
        change(&new)
        store.settings = new
        settings = store.settings
        if settings != old { onChange?(old, settings) }
    }

    /// The settings `tab` shows, back to their defaults.
    func restoreDefaults(_ tab: SettingsTab) {
        update { $0 = tab.restoringDefaults(of: $0) }
    }
}

// MARK: - Tabs

enum SettingsTab: String, CaseIterable {
    case general, record, output, permissions, advanced

    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .record: "record.circle"
        case .output: "photo.on.rectangle"
        case .permissions: "lock.shield"
        case .advanced: "slider.horizontal.3"
        }
    }

    /// Every tab but Permissions has settings, and a Restore Defaults button.
    var hasSettings: Bool { self != .permissions }

    /// `settings` with the ones this tab shows back to their defaults; the other tabs' are kept.
    func restoringDefaults(of settings: Settings) -> Settings {
        var settings = settings
        let defaults = Settings()
        func restore<Value>(_ keyPath: WritableKeyPath<Settings, Value>) {
            settings[keyPath: keyPath] = defaults[keyPath: keyPath]
        }
        switch self {
        case .general:
            restore(\.triggerKey)
            restore(\.sounds)
            restore(\.launchAtLogin)
        case .record:
            restore(\.recordTarget)
        case .output:
            restore(\.maxFrames)
            restore(\.compactFrames)
            restore(\.captionStrip)
            restore(\.clickMarkers)
            restore(\.saveLocation)
            restore(\.retention)
        case .permissions:
            break
        case .advanced:
            restore(\.holdThreshold)
            restore(\.holdReveal)
            restore(\.doubleTapWindow)
            restore(\.saveRawSessions)
        }
        return settings
    }

    func isAtDefaults(_ settings: Settings) -> Bool {
        restoringDefaults(of: settings) == settings
    }
}

/// A tab's Restore Defaults button, at the tab's bottom right, greyed out while the tab is at its defaults.
struct RestoreDefaultsButton: View {
    let tab: SettingsTab
    @ObservedObject var model: SettingsModel
    var onRestore: () -> Void = {}

    var body: some View {
        Button("Restore Defaults") {
            model.restoreDefaults(tab)
            onRestore()
        }
        .disabled(tab.isAtDefaults(model.settings))
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// A section footer, left-aligned and secondary, as in System Settings.
private struct Note: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A grouped form at the settings window's width, as tall as its content, with the tab's Restore Defaults
/// button under it.
private struct SettingsForm<Content: View>: View {
    static var width: CGFloat { 540 }
    var restore: RestoreDefaultsButton? = nil
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            content
            if let restore {
                Section {} footer: { restore }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: Self.width)
    }
}

struct GeneralTab: View {
    @ObservedObject var model: SettingsModel
    /// Observed, so the Email row follows the saved address while the window is open, even one a 400 clears.
    @ObservedObject var signup: EmailSignup
    var loginItem: () -> LoginItem.Availability
    @State private var changingEmail = false

    init(model: SettingsModel, signup: EmailSignup,
         loginItem: @escaping () -> LoginItem.Availability = { LoginItem.availability }) {
        self.model = model
        self.signup = signup
        self.loginItem = loginItem
    }

    var body: some View {
        let availability = loginItem()
        SettingsForm(restore: RestoreDefaultsButton(tab: .general, model: model)) {
            Section {
                Picker("Trigger key", selection: model.binding(\.triggerKey)) {
                    Text("Right ⌘").tag(TriggerKey.rightCommand)
                    Text("Right ⌥").tag(TriggerKey.rightOption)
                    Text("fn / Globe").tag(TriggerKey.fn)
                }
                if model.settings.triggerKey == .fn {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(SettingsText.fnWarnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Note("Hold the key to record, or double-tap it to record hands-free.")
            }
            Section {
                Toggle("Sounds", isOn: model.binding(\.sounds))
                Toggle("Launch at login", isOn: model.binding(\.launchAtLogin))
                    .disabled(availability == .notInApplications)
            } footer: {
                switch availability {
                case .notInApplications: Note("Move Annotake to Applications to launch at login.")
                case .requiresApproval: Note("Approve Annotake in System Settings → General → Login Items.")
                case .available: EmptyView()
                }
            }
            // The address the email step saved (email list design §3.3). It isn't a setting, so Restore Defaults
            // leaves it.
            Section {
                LabeledContent(SettingsText.emailRow) {
                    HStack {
                        Text(SettingsText.email(signup.record))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button(SettingsText.changeEmail) { changingEmail = true }
                    }
                }
            }
        }
        .sheet(isPresented: $changingEmail) { EmailChangeSheet(signup: signup) }
    }
}

/// The Change… sheet's field (email list design §3.3): the email step's, without the box, since the choice made there
/// goes with the new address. It opens with the saved address in it, so a typo can be fixed in place.
struct EmailChange {
    var draft: String

    init(record: EmailRecord?) {
        draft = record?.address ?? ""
    }

    /// Save is enabled once what's typed is an address /api/subscribe takes, as the email step's Continue is.
    var canSave: Bool { EmailConsent.isPlausible(draft) }

    /// Saves the cleaned address, which EmailSignup sends in the background: the same address changes nothing, and one
    /// the site already has from this Mac is saved as sent. Returns whether the sheet closes: not for an address the
    /// site wouldn't take, which Return in the field can send while Save is greyed out.
    @MainActor func save(to signup: EmailSignup) -> Bool {
        guard canSave else { return false }
        signup.change(address: EmailConsent.clean(draft))
        return true
    }
}

/// Change… from the Email row: the field, the privacy policy the email step links to, and Cancel and Save.
struct EmailChangeSheet: View {
    static let width: CGFloat = 400
    let signup: EmailSignup
    @State private var change: EmailChange
    @FocusState private var fieldFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(signup: EmailSignup) {
        self.signup = signup
        _change = State(initialValue: EmailChange(record: signup.record))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(SettingsText.changeEmailTitle).font(.headline)
            TextField("Email address", text: $change.draft, prompt: Text(OnboardingCopy.emailPlaceholder))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .autocorrectionDisabled()
                .focused($fieldFocused)
                // Return: save() turns away what Save, greyed out, would.
                .onSubmit(save)
            HStack {
                Link("Privacy policy", destination: EmailConsent.privacyURL)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!change.canSave)
            }
        }
        .padding(20)
        .frame(width: Self.width)
        // The field has focus when the sheet opens, as the email step's does.
        .defaultFocus($fieldFocused, true)
        .onAppear { fieldFocused = true }
    }

    private func save() {
        if change.save(to: signup) { dismiss() }
    }
}

struct OutputTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        SettingsForm(restore: RestoreDefaultsButton(tab: .output, model: model)) {
            Section {
                LabeledContent("Max frames") {
                    HStack {
                        Text(verbatim: "\(model.settings.maxFrames)").monospacedDigit()
                        Stepper("Max frames", value: model.binding(\.maxFrames), in: Settings.maxFramesRange)
                            .labelsHidden()
                    }
                }
                Picker("Frame size", selection: model.binding(\.compactFrames)) {
                    Text(verbatim: "\(Settings.fullLongEdge) px").tag(false)
                    Text(verbatim: "\(Settings.compactLongEdge) px (compact)").tag(true)
                }
                Toggle("Caption strip", isOn: model.binding(\.captionStrip))
                Toggle("Click markers", isOn: model.binding(\.clickMarkers))
            }
            Section {
                LabeledContent("Save location") {
                    HStack {
                        Text(SettingsText.path(model.settings.saveLocation))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…", action: chooseFolder)
                        Button("Show in Finder") {
                            let folder = model.settings.saveLocation
                            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                            NSWorkspace.shared.activateFileViewerSelecting([folder])
                        }
                    }
                }
                Picker("Keep captures", selection: model.binding(\.retention)) {
                    Text("7 days").tag(Settings.Retention.days7)
                    Text("30 days").tag(Settings.Retention.days30)
                    Text("Forever").tag(Settings.Retention.forever)
                }
            } footer: {
                Note("Older captures move to the Trash.")
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = model.settings.saveLocation.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.update { $0.saveLocation = url }
    }
}

struct PermissionsTab: View {
    static let refreshInterval: TimeInterval = 1
    let status: () -> Permissions.Status
    @State private var current: Permissions.Status
    private let timer = Timer.publish(every: refreshInterval, on: .main, in: .common).autoconnect()

    init(status: @escaping () -> Permissions.Status = Permissions.status) {
        self.status = status
        _current = State(initialValue: status())
    }

    var body: some View {
        SettingsForm {
            Section {
                PermissionRow(name: "Screen Recording", reason: "Required to record.",
                              granted: current.screenRecording, pane: PermissionPane.screenRecording)
                PermissionRow(name: "Input Monitoring", reason: "Needed to see the trigger key, clicks, and keys.",
                              granted: current.inputMonitoring, pane: PermissionPane.inputMonitoring)
                PermissionRow(name: "Accessibility", reason: "Needed for click cleanup and button names.",
                              granted: current.accessibility, pane: PermissionPane.accessibility)
            } footer: {
                Note("Screen Recording and Input Monitoring take effect after Annotake is reopened.")
            }
        }
        .onReceive(timer) { _ in current = status() }
    }
}

struct PermissionRow: View {
    let name: String
    let reason: String
    let granted: Bool
    let pane: URL

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(reason).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open System Settings") { NSWorkspace.shared.open(pane) }
        }
    }
}

struct AdvancedTab: View {
    static let step: TimeInterval = 0.01
    @ObservedObject var model: SettingsModel

    var body: some View {
        let settings = model.settings
        SettingsForm(restore: RestoreDefaultsButton(tab: .advanced, model: model)) {
            Section {
                slider("Hold threshold", \.holdThreshold, Settings.holdThresholdRange)
                slider("Hold reveal", \.holdReveal,
                       settings.holdThreshold + Settings.minimumRevealAfterThreshold...Settings.maximumHoldReveal)
                slider("Double-tap window", \.doubleTapWindow, Settings.doubleTapWindowRange)
            } footer: {
                Note("New timings apply as soon as Annotake isn't recording.")
            }
            Section {
                Toggle("Save raw sessions", isOn: model.binding(\.saveRawSessions))
            } footer: {
                Note("Keeps what the frame picker saw in each capture's .raw/session folder, for tuning.")
            }
        }
    }

    private func slider(_ title: String, _ keyPath: WritableKeyPath<Settings, TimeInterval>,
                        _ range: ClosedRange<TimeInterval>) -> some View {
        let rounded = Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { value in model.update { $0[keyPath: keyPath] = (value / Self.step).rounded() * Self.step } })
        return LabeledContent {
            HStack {
                Slider(value: rounded, in: range)
                Text(SettingsText.milliseconds(model.settings[keyPath: keyPath]))
                    .monospacedDigit()
                    .frame(width: 60, alignment: .trailing)
            }
        } label: {
            Text(title)
        }
    }
}

// MARK: - The window

/// Every Settings tab's page: the tab, then the footer bar.
struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
            SettingsFooter()
        }
    }
}

/// The bar along the bottom of every Settings tab: the Annotake logo, and the version for bug reports.
struct SettingsFooter: View {
    static let barHeight: CGFloat = 48
    /// From the reels to the baseline.
    static let logoHeight: CGFloat = 24
    var version = AppVersion.current

    nonisolated static func versionText(_ version: AppVersion) -> String { "Version \(version)" }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                WordmarkView(label: "Annotake").frame(height: Self.logoHeight)
                Spacer()
                Text(Self.versionText(version))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 20)
            .frame(height: Self.barHeight)
        }
        // The grouped forms' own background, which is the window's.
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// The Settings window (spec §3.6): toolbar tabs, each a SwiftUI form over the footer bar. Annotake stays
/// menu-bar-only while it's open.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: SettingsModel
    private let picker: RecordPickerModel
    private let signup: EmailSignup
    private var window: NSWindow?

    init(model: SettingsModel, picker: RecordPickerModel, signup: EmailSignup) {
        self.model = model
        self.picker = picker
        self.signup = signup
    }

    func show() {
        if window == nil { window = makeWindow() }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        for tab in SettingsTab.allCases {
            let item = NSTabViewItem(viewController: Self.hosting(tab, model: model, picker: picker, signup: signup))
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.title = "Annotake Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    static func hosting(_ tab: SettingsTab, model: SettingsModel, picker: RecordPickerModel,
                        signup: EmailSignup) -> NSViewController {
        let controller = switch tab {
        case .general: host(GeneralTab(model: model, signup: signup))
        case .record: host(RecordTab(model: model, picker: picker))
        case .output: host(OutputTab(model: model))
        case .permissions: host(PermissionsTab())
        case .advanced: host(AdvancedTab(model: model))
        }
        controller.title = tab.title
        return controller
    }

    /// The window takes each tab's size, footer included.
    private static func host(_ view: some View) -> NSViewController {
        let controller = NSHostingController(rootView: SettingsPage { view })
        controller.sizingOptions = .preferredContentSize
        return controller
    }
}
