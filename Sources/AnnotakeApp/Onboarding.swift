import AnnotakeCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The first run's words (spec §3.7). Every key name goes through `keyName`.
enum OnboardingCopy {
    static let reassurance = "Annotake sees your screen only while you record. Nothing you record leaves your Mac."
    static let welcomeSubtitle = "Show your coding agent exactly what happened."
    static let agents = "Claude Code, Cursor, or ChatGPT"
    static let nextTime = "Next time, drag it into \(agents)."
    static let dropHint = "Drop the card here"

    /// "Right ⌘", "Right ⌥", "fn"
    static func keyName(_ trigger: TriggerKey) -> String {
        trigger == .fn ? "fn" : "Right \(PillText.glyph(trigger))"
    }

    /// The permission's name in System Settings.
    static func paneName(_ permission: OnboardingModel.Permission) -> String {
        switch permission {
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        case .screenRecording: "Screen Recording"
        }
    }

    static func title(_ step: OnboardingModel.Step) -> String {
        switch step {
        case .welcome: "Annotake"
        case .permission(let permission): "Allow \(paneName(permission))"
        case .reopen: "Reopen Annotake"
        case .practice: "Try it"
        case .dropCard: "Now drag the card here"
        case .done: "You're set"
        }
    }

    /// The step's text, one paragraph per element.
    static func paragraphs(_ step: OnboardingModel.Step, trigger: TriggerKey, mode: OnboardingModel.Mode) -> [String] {
        let key = keyName(trigger)
        switch step {
        case .welcome:
            return ["Press a key, do the thing, and drag the card into \(agents). Each step comes out as a "
                    + "screenshot, captioned with what you clicked."]
        case .permission(let permission):
            let reason = switch permission {
            case .accessibility:
                "So Annotake can name the buttons you click, and keep \(PillText.glyph(trigger)) out of your "
                    + "clicks while you hold the key."
            case .inputMonitoring:
                "So Annotake can notice \(key), and your clicks and keys while you record. It never records "
                    + "what you type."
            case .screenRecording:
                "So Annotake can capture your screen while you record."
            }
            return (mode == .existingUser ? [LegacyFlipbook.askAgainNote] : []) + [reason, reassurance]
        case .reopen:
            return ["macOS turns on Screen Recording and Input Monitoring after Annotake reopens. It comes back to "
                    + "this window."]
        case .practice:
            return ["1. Double-tap \(key). The pill appears at the bottom of the screen.",
                    "2. Click through something in another app. Annotake keeps its own windows out of recordings.",
                    "3. Double-tap \(key) again. A card appears at the bottom right, and this window comes back."]
        case .dropCard:
            return ["The card is at the bottom right of your screen."]
        case .done:
            return ["Hold \(key) for quick recordings, and let go to stop.",
                    "\(key) + Esc cancels.",
                    "Everything else is in the menu-bar icon."]
        }
    }

    static func body(_ step: OnboardingModel.Step, trigger: TriggerKey, mode: OnboardingModel.Mode) -> String {
        paragraphs(step, trigger: trigger, mode: mode).joined(separator: "\n\n")
    }

    /// The three demo tiles on the welcome step.
    static func demo(_ trigger: TriggerKey) -> [String] {
        ["Double-tap \(keyName(trigger))", "Click through it", "Drag the card into your agent"]
    }

    static func settingsCaption(_ permission: OnboardingModel.Permission) -> String {
        "System Settings → Privacy & Security → \(paneName(permission)): turn on Annotake."
    }

    /// "8 frames. That's what your agent gets."
    static func dropResult(frames: Int) -> String {
        "\(frames) \(frames == 1 ? "frame" : "frames"). That's what your agent gets."
    }
}

/// What a drop on the practice drop box holds.
enum OnboardingDrop {
    /// The PNGs, sorted by file name; empty means it wasn't a card.
    static func frames(from urls: [URL]) -> [URL] {
        urls.filter { $0.pathExtension.lowercased() == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

// MARK: - The live state

/// The first run's live state: permissions polled every second, saved under `OnboardingModel.storeKey` after
/// every change, so Quit & Reopen comes back to the same step.
@MainActor
final class OnboardingViewModel: ObservableObject {
    static let pollInterval: TimeInterval = 1
    static let thumbnailCount = 3

    @Published private(set) var model: OnboardingModel
    /// How many frames were dropped on the drop box, and the first few as thumbnails.
    @Published private(set) var droppedFrames = 0
    @Published private(set) var thumbnails: [NSImage] = []
    let trigger: TriggerKey
    let retiredFlipbook: Bool
    /// Called when the Done button finishes the first run.
    var onFinish: (() -> Void)?
    /// Called when something outside the window moves the first run on: a grant found by polling, or the practice
    /// recording saved. By then the window is usually behind System Settings or the app recorded, and with no Dock
    /// icon there's no way back to it.
    var onAdvancedElsewhere: (() -> Void)?
    private let defaults: UserDefaults?
    private let status: () -> Permissions.Status
    private let report: (String) -> Void
    private var timer: Timer?

    /// With no defaults (UI snapshots), nothing is saved. `report` is the log unless a test passes its own.
    init(trigger: TriggerKey, defaults: UserDefaults?, persisted: OnboardingModel.Persisted, retiredFlipbook: Bool,
         status: @escaping () -> Permissions.Status = Permissions.status,
         report: @escaping (String) -> Void = { log($0) }) {
        self.trigger = trigger
        self.defaults = defaults
        self.status = status
        self.report = report
        self.retiredFlipbook = retiredFlipbook
        model = OnboardingModel(granted: status().byPermission, persisted: persisted)
    }

    static func load(from defaults: UserDefaults) -> OnboardingModel.Persisted? {
        defaults.data(forKey: OnboardingModel.storeKey)
            .flatMap { try? JSONDecoder().decode(OnboardingModel.Persisted.self, from: $0) }
    }

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
        let step = model.step
        let granted = status().byPermission
        change { $0.update(granted: granted) }
        if model.step != step { onAdvancedElsewhere?() }
    }

    /// The step's main button.
    func primary() {
        let step = model.step
        let action = model.action
        switch action {
        case .prompt:
            if case .permission(let permission) = step { Permissions.request(permission) }
        case .openSettings:
            if case .permission(let permission) = step { NSWorkspace.shared.open(Self.pane(for: permission)) }
        case .quitAndReopen:
            quitAndReopen()
            return
        case .next, .waitForRecording, .waitForDrop, .finish:
            break
        }
        change { $0.perform() }
        if action == .finish {
            onFinish?()
        } else {
            refresh()
        }
    }

    /// "Continue" on a permission step, before macOS confirms the grant.
    func proceed() { change { $0.proceed() } }
    func skip() { change { $0.skip() } }
    func recordingSaved() {
        let step = model.step
        change { $0.recordingSaved() }
        if model.step != step { onAdvancedElsewhere?() }
    }
    func relaunched() { change { $0.relaunched() } }
    func closed() { change { $0.closed() } }

    /// "Continue" after a drop.
    func continueAfterDrop() { change { $0.cardDropped() } }

    /// Fix permissions…, once the first run is over: its own pass over the permissions.
    func startFixingPermissions() {
        let granted = status().byPermission
        change { $0 = OnboardingModel(granted: granted, persisted: OnboardingModel.fixingPermissions(granted: granted)) }
    }

    /// What landed on the drop box.
    func dropped(_ urls: [URL]) {
        let frames = OnboardingDrop.frames(from: urls)
        guard !frames.isEmpty else { return }
        showDrop(frames: frames.count,
                 thumbnails: frames.prefix(Self.thumbnailCount).compactMap { NSImage(contentsOf: $0) })
        report("onboarding: a card with \(frames.count) frame(s) was dropped")
    }

    func showDrop(frames: Int, thumbnails: [NSImage]) {
        droppedFrames = frames
        self.thumbnails = thumbnails
    }

    /// Saves where the first run is, quits, and reopens Annotake a second later.
    func quitAndReopen() {
        save()
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        do {
            try relaunch.run()
        } catch {
            report("couldn't schedule the reopen: \(error)")
        }
        NSApp.terminate(nil)
    }

    private func change(_ body: (inout OnboardingModel) -> Void) {
        var next = model
        body(&next)
        guard next != model else { return }
        if next.step != model.step { report("onboarding: \(Self.logName(next.step))") }
        model = next
        save()
    }

    func save() {
        guard let defaults, let data = try? JSONEncoder().encode(model.persisted) else { return }
        defaults.set(data, forKey: OnboardingModel.storeKey)
    }

    static func pane(for permission: OnboardingModel.Permission) -> URL {
        switch permission {
        case .accessibility: PermissionPane.accessibility
        case .inputMonitoring: PermissionPane.inputMonitoring
        case .screenRecording: PermissionPane.screenRecording
        }
    }

    /// The log's name for a step; never anything the user typed or recorded.
    static func logName(_ step: OnboardingModel.Step) -> String {
        switch step {
        case .welcome: "welcome"
        case .permission(let permission): permission.rawValue
        case .reopen: "reopen"
        case .practice: "practice"
        case .dropCard: "drop the card"
        case .done: "done"
        }
    }
}

// MARK: - The window's views

/// One step at a time, in a fixed 560 × 440 pt window.
struct OnboardingView: View {
    static let width: CGFloat = 560
    static let height: CGFloat = 440
    static let padding: CGFloat = 28
    @ObservedObject var viewModel: OnboardingViewModel
    /// UI snapshots measure the content at its own height, to catch anything the window would clip.
    var fitsContent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
            Spacer(minLength: 20)
            buttons
        }
        .padding(Self.padding)
        .frame(width: Self.width, height: fitsContent ? nil : Self.height, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var model: OnboardingModel { viewModel.model }

    private var paragraphs: [String] {
        OnboardingCopy.paragraphs(model.step, trigger: viewModel.trigger, mode: model.persisted.mode)
    }

    @ViewBuilder private var content: some View {
        switch model.step {
        case .welcome:
            WelcomeStep(trigger: viewModel.trigger, paragraphs: paragraphs, retiredFlipbook: viewModel.retiredFlipbook)
        case .permission(let permission):
            PermissionStep(permission: permission, paragraphs: paragraphs, granted: model.granted)
        case .reopen:
            SimpleStep(step: .reopen, symbol: "arrow.clockwise.circle.fill", tint: .accentColor, paragraphs: paragraphs)
        case .practice:
            SimpleStep(step: .practice, symbol: "record.circle", tint: .red, paragraphs: paragraphs)
        case .dropCard:
            DropStep(viewModel: viewModel, paragraphs: paragraphs)
        case .done:
            SimpleStep(step: .done, symbol: "checkmark.circle.fill", tint: .green, paragraphs: paragraphs)
        }
    }

    @ViewBuilder private var buttons: some View {
        HStack(spacing: 12) {
            Spacer()
            switch model.step {
            case .welcome:
                primary("Get Started")
            case .permission:
                if model.action == .prompt {
                    primary("Allow…")
                } else {
                    Button("Continue") { viewModel.proceed() }
                    primary("Open System Settings")
                }
            case .reopen:
                primary("Quit & Reopen")
            case .practice:
                Button("Skip") { viewModel.skip() }
            case .dropCard:
                if viewModel.droppedFrames > 0 {
                    Button("Continue") { viewModel.continueAfterDrop() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Skip") { viewModel.skip() }
                }
            case .done:
                primary("Done")
            }
        }
        .controlSize(.large)
    }

    private func primary(_ title: String) -> some View {
        Button(title) { viewModel.primary() }.keyboardShortcut(.defaultAction)
    }
}

/// A step's title, the same on every step.
private struct StepTitle: View {
    let text: String

    var body: some View {
        Text(text).font(.system(size: 22, weight: .bold)).fixedSize(horizontal: false, vertical: true)
    }
}

private struct Paragraph: View {
    let text: String

    var body: some View {
        Text(text).fixedSize(horizontal: false, vertical: true)
    }
}

/// What Annotake does, with a demo: three tiles highlighted in turn.
private struct WelcomeStep: View {
    /// The logo's height in points, from the reels to the baseline: about 26 pt to the cap line.
    static let logoHeight: CGFloat = 60
    static let demoInterval: TimeInterval = 1.6
    static let symbols = ["keyboard", "cursorarrow.click.2", "photo.stack"]
    let trigger: TriggerKey
    let paragraphs: [String]
    let retiredFlipbook: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                WordmarkView(label: OnboardingCopy.title(.welcome)).frame(height: Self.logoHeight)
                Text(OnboardingCopy.welcomeSubtitle).font(.title3).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(paragraphs, id: \.self) { Paragraph(text: $0) }
            TimelineView(.periodic(from: .now, by: Self.demoInterval)) { context in
                let active = Int(context.date.timeIntervalSinceReferenceDate / Self.demoInterval) % Self.symbols.count
                HStack(spacing: 12) {
                    ForEach(Array(OnboardingCopy.demo(trigger).enumerated()), id: \.offset) { index, caption in
                        DemoTile(number: index + 1, symbol: Self.symbols[index], caption: caption,
                                 active: index == active)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: active)
            }
            if retiredFlipbook {
                Label(LegacyFlipbook.replacedNote, systemImage: "trash")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

private struct DemoTile: View {
    let number: Int
    let symbol: String
    let caption: String
    let active: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(active ? Color.accentColor : .secondary)
            Text("\(number). \(caption)").font(.callout).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 104)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(active ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(active ? Color.accentColor : .clear, lineWidth: 2))
    }
}

/// One permission: why, the promise, and where to click in System Settings.
private struct PermissionStep: View {
    let permission: OnboardingModel.Permission
    let paragraphs: [String]
    let granted: [OnboardingModel.Permission: Bool]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PermissionProgress(current: permission, granted: granted)
            StepTitle(text: OnboardingCopy.title(.permission(permission)))
            ForEach(paragraphs, id: \.self) { paragraph in
                switch paragraph {
                case LegacyFlipbook.askAgainNote:
                    Label(paragraph, systemImage: "info.circle")
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.12)))
                case OnboardingCopy.reassurance:
                    Label(paragraph, systemImage: "lock.shield")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                default:
                    Paragraph(text: paragraph)
                }
            }
            SettingsRowMock(permission: permission)
        }
    }
}

/// The three permissions in order: ✓ once granted, the current one highlighted.
private struct PermissionProgress: View {
    let current: OnboardingModel.Permission
    let granted: [OnboardingModel.Permission: Bool]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(OnboardingModel.Permission.allCases) { permission in
                let isGranted = granted[permission] == true
                HStack(spacing: 5) {
                    Image(systemName: isGranted ? "checkmark.circle.fill"
                          : permission == current ? "circle.inset.filled" : "circle")
                        .foregroundStyle(isGranted ? Color.green : permission == current ? Color.accentColor : .secondary)
                    Text(OnboardingCopy.paneName(permission))
                        .foregroundStyle(permission == current ? .primary : .secondary)
                }
                .font(.callout)
            }
        }
    }
}

/// A picture of the row to turn on in System Settings: the app, its name, and the switch, ringed.
private struct SettingsRowMock: View {
    let permission: OnboardingModel.Permission

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 26, height: 26)
                Text("Annotake")
                Spacer()
                // Drawn, not a real Toggle: a picture's switch looks on even while the window isn't key.
                Capsule().fill(Color.accentColor)
                    .frame(width: 38, height: 22)
                    .overlay(alignment: .trailing) {
                        Circle().fill(.white).padding(2).shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                    }
                    .padding(4)
                    .overlay(Capsule().stroke(Color.accentColor, lineWidth: 2.5))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.25)))
            Text(OnboardingCopy.settingsCaption(permission)).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A big symbol, the title, and the text: Reopen, the practice run, and Done.
private struct SimpleStep: View {
    let step: OnboardingModel.Step
    let symbol: String
    let tint: Color
    let paragraphs: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: symbol).font(.system(size: 44)).foregroundStyle(tint)
            StepTitle(text: OnboardingCopy.title(step))
            ForEach(paragraphs, id: \.self) { Paragraph(text: $0) }
        }
    }
}

/// The drop box: the card dropped here shows what an agent gets.
private struct DropStep: View {
    static let boxHeight: CGFloat = 196
    static let thumbnailHeight: CGFloat = 92
    @ObservedObject var viewModel: OnboardingViewModel
    let paragraphs: [String]
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepTitle(text: OnboardingCopy.title(.dropCard))
            ForEach(paragraphs, id: \.self) { Paragraph(text: $0) }
            box
                .frame(maxWidth: .infinity, minHeight: Self.boxHeight)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(targeted ? 0.14 : 0.06)))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.5),
                                  style: StrokeStyle(lineWidth: 2, dash: viewModel.droppedFrames > 0 ? [] : [7, 5])))
                .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                    load(providers)
                    return true
                }
        }
    }

    @ViewBuilder private var box: some View {
        if viewModel.droppedFrames > 0 {
            VStack(spacing: 12) {
                Text(OnboardingCopy.dropResult(frames: viewModel.droppedFrames)).font(.headline)
                HStack(spacing: 10) {
                    ForEach(Array(viewModel.thumbnails.enumerated()), id: \.offset) { _, image in
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                            .frame(height: Self.thumbnailHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .shadow(radius: 2, y: 1)
                    }
                }
                Text(OnboardingCopy.nextTime).foregroundStyle(.secondary)
            }
            .padding(16)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "tray.and.arrow.down").font(.system(size: 34)).foregroundStyle(.secondary)
                Text(OnboardingCopy.dropHint).foregroundStyle(.secondary)
            }
        }
    }

    /// Each dragged frame arrives as its own item; the URLs come back on other queues, one by one.
    private func load(_ providers: [NSItemProvider]) {
        let collector = DropCollector(expected: providers.count) { [viewModel] urls in viewModel.dropped(urls) }
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { collector.add(url) } }
            }
        }
    }
}

/// Gathers a drop's URLs and hands them over once every item has answered.
@MainActor
private final class DropCollector {
    private var remaining: Int
    private var urls: [URL] = []
    private let done: ([URL]) -> Void

    init(expected: Int, done: @escaping ([URL]) -> Void) {
        remaining = expected
        self.done = done
    }

    func add(_ url: URL?) {
        if let url { urls.append(url) }
        remaining -= 1
        if remaining == 0 { done(urls) }
    }
}

// MARK: - The window

/// Shows the first run at launch until it's done, and "Fix permissions…" from the menu (spec §3.7).
@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    static let title = "Welcome to Annotake"
    private let viewModel: OnboardingViewModel
    private var window: NSWindow?

    init(trigger: TriggerKey, defaults: UserDefaults, existingUser: Bool, retiredFlipbook: Bool) {
        let saved = OnboardingViewModel.load(from: defaults)
        viewModel = OnboardingViewModel(
            trigger: trigger, defaults: defaults,
            persisted: saved ?? OnboardingModel.Persisted(mode: existingUser ? .existingUser : .firstRun),
            retiredFlipbook: retiredFlipbook)
        super.init()
        // Saved at once (Checkpoint 3): macOS can quit Annotake for a permission before any step changes, and
        // the relaunch, where migration has already run, mustn't forget that this is an existing user.
        if saved == nil { viewModel.save() }
        // Every launch is a relaunch for permissions that wait for one, so a first run left at Reopen moves on.
        viewModel.relaunched()
        viewModel.onFinish = { [weak self] in self?.window?.close() }
        viewModel.onAdvancedElsewhere = { [weak self] in self?.bringForward() }
    }

    /// Back in front, at the next step.
    private func bringForward() {
        guard let window, window.isVisible else { return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func showIfNeeded() {
        if viewModel.model.showsAtLaunch { show() }
    }

    /// From the menu: the first run where it is, or once it's over, a pass over the missing permissions.
    func show(fixingPermissions: Bool) {
        if fixingPermissions && !viewModel.model.showsAtLaunch { viewModel.startFixingPermissions() }
        show()
    }

    func recordingSaved() {
        viewModel.recordingSaved()
    }

    private func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView(viewModel: viewModel)))
            window.title = Self.title
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

    func windowWillClose(_ notification: Notification) {
        viewModel.stopPolling()
        viewModel.closed()
    }
}
