import AppKit
import AnnotakeCore
import AnnotakeExport
import SwiftUI

/// `Annotake --render-ui <dir>`: draws every panel and window state offscreen to PNGs, so a session can
/// look at the UI it builds. Needs no permissions.
enum UISnapshots {
    /// Snapshots are drawn at Retina scale.
    static let scale: CGFloat = 2

    @MainActor
    static func render(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        write(pill(PillText.recording(mode: .hold, elapsed: 4, frames: 3, maxFrames: 20, trigger: .rightCommand)),
              to: directory, as: "pill-hold.png")
        write(pill(PillText.recording(mode: .handsFree, elapsed: 12, frames: 5, maxFrames: 20, trigger: .rightCommand)),
              to: directory, as: "pill-handsfree.png")
        write(pill(PillText.message(.screenRecordingNeeded), button: "Open Settings"),
              to: directory, as: "pill-message.png")

        write(CardView(state: .saving(duration: 21)), to: directory, as: "card-saving.png")
        let ready = CardView(state: .ready(sampleCapture(frames: 8, duration: 21), thumbnails: sampleThumbnails()))
        write(ready, to: directory, as: "card-ready.png")
        ready.hovering = true
        write(ready, to: directory, as: "card-ready-hover.png")
        write(CardView(state: .failed(folder: URL(fileURLWithPath: NSHomeDirectory()))), to: directory, as: "card-error.png")

        write(filmstrip(), to: directory, as: "filmstrip.png")
        write(menuBarIcon(), to: directory, as: "menubar.png")

        var problems: [String] = []
        renderSettings(to: directory, problems: &problems)
        // `make ui-snapshots` fails when this file isn't empty.
        try? Data(problems.map { $0 + "\n" }.joined().utf8).write(to: directory.appending(path: Self.problemsFile))
    }

    /// What the snapshots found wrong, one line each; the app's stdout goes nowhere under `open`.
    static let problemsFile = "problems.txt"

    /// One snapshot per Settings tab, from a throwaway store with the defaults.
    @MainActor
    private static func renderSettings(to directory: URL, problems: inout [String]) {
        let suite = "com.fayzanmalik.annotake.ui-snapshots"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = SettingsModel(store: SettingsStore(defaults: defaults))
        // Each tab on its page, with the footer bar, as the window shows it.
        func tab(_ view: some View, as name: String) { writeSwiftUI(SettingsPage { view }, to: directory, as: name) }

        tab(GeneralTab(model: model, loginItem: { .available }), as: "settings-general.png")
        tab(GeneralTab(model: model, loginItem: { .notInApplications }), as: "settings-general-not-in-applications.png")
        let picker = samplePicker()
        tab(RecordTab(model: model, picker: picker), as: "settings-record.png")
        model.update { $0.recordTarget = .window(windowID: 12, title: "Checkout — Safari") }
        tab(RecordTab(model: model, picker: picker), as: "settings-record-windows.png")
        model.update { $0.recordTarget = .cursorScreen }
        tab(OutputTab(model: model), as: "settings-output.png")
        tab(PermissionsTab(status: {
            Permissions.Status(screenRecording: true, inputMonitoring: true, accessibility: false)
        }), as: "settings-permissions.png")
        tab(AdvancedTab(model: model), as: "settings-advanced.png")
        model.update { $0.triggerKey = .fn }
        tab(GeneralTab(model: model, loginItem: { .available }), as: "settings-general-fn.png")

        renderOnboarding(to: directory, problems: &problems)
    }

    /// One snapshot per first-run step, from view models that save nothing and see fixed permissions.
    @MainActor
    private static func renderOnboarding(to directory: URL, problems: inout [String]) {
        let none = Permissions.Status(screenRecording: false, inputMonitoring: false, accessibility: false)
        let two = Permissions.Status(screenRecording: false, inputMonitoring: true, accessibility: true)
        let all = Permissions.Status(screenRecording: true, inputMonitoring: true, accessibility: true)
        var heights: [String] = []
        func onboarding(_ name: String, _ persisted: OnboardingModel.Persisted, status: Permissions.Status,
                        retiredFlipbook: Bool = false, change: (OnboardingViewModel) -> Void = { _ in }) {
            let viewModel = OnboardingViewModel(trigger: .rightCommand, defaults: nil, persisted: persisted,
                                                retiredFlipbook: retiredFlipbook, status: { status })
            change(viewModel)
            writeSwiftUI(OnboardingView(viewModel: viewModel), to: directory, as: name)
            // The window has a fixed height: the content at its own height must fit in it.
            let natural = NSHostingView(rootView: OnboardingView(viewModel: viewModel, fitsContent: true)).fittingSize
            heights.append("\(name): \(Int(natural.height.rounded(.up))) of \(Int(OnboardingView.height)) pt")
            if natural.height > OnboardingView.height {
                problems.append("\(name) is clipped: its content needs \(Int(natural.height.rounded(.up))) pt, "
                                + "and the window is \(Int(OnboardingView.height))")
            }
        }
        defer {
            try? Data((heights.joined(separator: "\n") + "\n").utf8)
                .write(to: directory.appending(path: "onboarding-heights.txt"))
        }
        onboarding("onboarding-welcome.png", .init(), status: none, retiredFlipbook: true)
        onboarding("onboarding-accessibility.png", .init(step: .permission(.accessibility)), status: none)
        onboarding("onboarding-screen-recording-requested.png",
                   .init(step: .permission(.screenRecording), requested: [.accessibility, .inputMonitoring, .screenRecording]),
                   status: two)
        // A fresh existing user, as the first launch makes one: it must open at the permissions (Checkpoint 3).
        onboarding("onboarding-existing-user.png", .init(mode: .existingUser), status: none)
        onboarding("onboarding-reopen.png", .init(step: .reopen, requested: [.screenRecording]), status: two)
        onboarding("onboarding-practice.png", .init(step: .practice), status: all)
        onboarding("onboarding-drop.png", .init(step: .dropCard), status: all)
        onboarding("onboarding-drop-done.png", .init(step: .dropCard), status: all) {
            $0.showDrop(frames: 6, thumbnails: sampleThumbnails(count: 3))
        }
        onboarding("onboarding-done.png", .init(step: .done), status: all)
    }

    /// Screens and windows with placeholder thumbnails; it never queries the real screen.
    @MainActor
    private static func samplePicker() -> RecordPickerModel {
        let picker = RecordPickerModel(loader: nil)
        let thumbnails = sampleThumbnails(count: 5)
        picker.screens = [
            RecordPickerModel.cursorTile,
            .init(target: .screen(displayUUID: "BUILT-IN"), title: "Built-in Retina Display", thumbnail: thumbnails[0]),
            .init(target: .screen(displayUUID: "E29W"), title: "E29w-20", thumbnail: thumbnails[1]),
        ]
        let apps: [(String, String, String)] = [
            ("Checkout — Safari", "/Applications/Safari.app", "Safari"),
            ("main.swift — annotake", "/System/Applications/TextEdit.app", "TextEdit"),
            ("Downloads", "/System/Library/CoreServices/Finder.app", "Finder"),
        ]
        picker.windows = apps.enumerated().map { index, app in
            .init(target: .window(windowID: UInt32(12 + index), title: app.0), title: app.0,
                  icon: NSWorkspace.shared.icon(forFile: app.1), thumbnail: thumbnails[2 + index])
        }
        return picker
    }

    /// A SwiftUI view through NSHostingView, at its own size.
    @MainActor
    static func writeSwiftUI(_ view: some View, to directory: URL, as name: String) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        write(hosting, to: directory, as: name)
    }

    /// The menu-bar icon, idle then recording, on a light and a dark menu bar. The idle icon is a template, so it's
    /// tinted the way the menu bar draws it.
    @MainActor
    private static func menuBarIcon() -> NSView {
        let bar = NSSize(width: 110, height: 24)
        let image = NSImage(size: NSSize(width: bar.width, height: bar.height * 2), flipped: true) { _ in
            let bars: [(NSAppearance.Name, NSColor)] = [(.aqua, NSColor(white: 0.93, alpha: 1)),
                                                        (.darkAqua, NSColor(white: 0.16, alpha: 1))]
            for (row, (name, background)) in bars.enumerated() {
                let y = CGFloat(row) * bar.height
                background.setFill()
                NSRect(x: 0, y: y, width: bar.width, height: bar.height).fill()
                NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
                    for (column, recording) in [false, true].enumerated() {
                        let icon = MenuBarIcon.image(recording: recording)
                        let rect = NSRect(x: 30 + CGFloat(column) * 40, y: y + (bar.height - icon.size.height) / 2,
                                          width: icon.size.width, height: icon.size.height)
                        let drawn = icon.isTemplate ? NSImage(size: icon.size, flipped: false) { bounds in
                            icon.draw(in: bounds)
                            NSColor.labelColor.set()
                            bounds.fill(using: .sourceAtop)
                            return true
                        } : icon
                        drawn.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                                   hints: nil)
                    }
                }
            }
            return true
        }
        let view = NSImageView(frame: NSRect(origin: .zero, size: image.size))
        view.image = image
        return view
    }

    /// Four frames, the second removed, the third hovered.
    @MainActor
    private static func filmstrip() -> NSView {
        let capture = sampleCapture(frames: 4, duration: 12)
        let view = FilmstripView(frame: CGRect(x: 0, y: 0, width: 1200, height: FilmstripView.height))
        view.title = RecentCaptures.title(for: capture)
        let frames = capture.manifest.result.frames
        let captions = [#"Clicked button "Checkout""#, #"Typed in field "Card number""#, "Pressed Return", "End"]
        view.strip.tiles = zip(frames, sampleThumbnails(count: 4)).enumerated().map { position, pair in
            var frame = pair.0
            frame.actions = position < 3 ? [.pressedReturn] : []
            let caption = "\(position + 1)/\(frames.count) · \(Captions.timestamp(frame.time)) · \(captions[position])"
            return FilmstripTile(frameIndex: frame.frameIndex, url: capture.folder, caption: caption, image: pair.1,
                                 aspect: pair.1.size.width / pair.1.size.height)
        }
        view.strip.selection = FilmstripSelection(frameIndices: frames.map(\.frameIndex))
        view.strip.selection.toggle(frames[1].frameIndex)
        view.strip.hovered = 2
        view.layoutSubtreeIfNeeded()
        return view
    }

    /// A finished capture that exists only in memory, for drawing.
    static func sampleCapture(frames: Int, duration: TimeInterval) -> FinishedCapture {
        let context = FrameContext(app: "Safari", window: "Checkout")
        let picked = (0..<frames).map {
            PickedFrame(frameIndex: $0, time: Double($0) * duration / Double(frames), context: context, actions: [],
                        reason: .visual)
        }
        let manifest = CaptureManifest(name: "2026-09-24 at 14.05.12", target: "Screen: Built-in Retina Display",
                                       created: Date(), render: RenderOptions(captionStrip: true, clickMarkers: true),
                                       result: PickResult(frames: picked, candidateCount: frames, duration: duration),
                                       removed: [])
        return FinishedCapture(folder: URL(fileURLWithPath: NSTemporaryDirectory()), manifest: manifest)
    }

    /// Mock screenshots: a window with a toolbar, some content, and a caption strip.
    static func sampleThumbnails(count: Int = 3) -> [NSImage] {
        let accents: [NSColor] = [.systemBlue, .systemOrange, .systemGreen, .systemPurple, .systemPink, .systemTeal]
        return (0..<count).map { index in
            NSImage(size: CGSize(width: 416, height: 315), flipped: true) { rect in
                NSColor(white: 0.96, alpha: 1).setFill()
                rect.fill()
                NSColor(white: 0.86, alpha: 1).setFill()
                CGRect(x: 0, y: 0, width: rect.width, height: 30).fill()
                accents[index % accents.count].setFill()
                NSBezierPath(roundedRect: CGRect(x: 24, y: 56, width: 150, height: 34), xRadius: 6, yRadius: 6).fill()
                NSColor(white: 0.8, alpha: 1).setFill()
                for row in 0..<5 {
                    CGRect(x: 24, y: 110 + CGFloat(row) * 24, width: 260 - CGFloat((row + index) % 3) * 50, height: 10).fill()
                }
                NSColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1).setFill()
                CGRect(x: 0, y: rect.height - 34, width: rect.width, height: 34).fill()
                NSColor.white.setFill()
                CGRect(x: 12, y: rect.height - 25, width: 180, height: 6).fill()
                return true
            }
        }
    }

    @MainActor
    private static func pill(_ text: String, button: String? = nil) -> NSView {
        let view = PillView(frame: .zero)
        view.text = text
        if let button { view.setButton(title: button, action: nil, target: nil) }
        view.frame = NSRect(origin: .zero, size: view.fittingSizeForContent)
        view.layoutSubtreeIfNeeded()
        return view
    }

    /// The view's pixels as a PNG, at `scale`.
    @MainActor
    static func png(of view: NSView) -> Data? {
        let size = view.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    @MainActor
    static func write(_ view: NSView, to directory: URL, as name: String) {
        guard let data = png(of: view) else { return }
        try? data.write(to: directory.appending(path: name), options: .atomic)
    }
}
