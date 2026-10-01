import AppKit
import AnnotakeCapture
@preconcurrency import ScreenCaptureKit
import SwiftUI

/// Which windows the picker offers (spec §3.3).
enum WindowListFilter {
    static let excludedBundleIDs: Set<String> = ["com.apple.dock", "com.apple.WindowManager", "com.apple.controlcenter",
                                                 "com.apple.notificationcenterui", "com.apple.systemuiserver"]
    static let minimumSide: CGFloat = 100

    /// On-screen, layer 0, both sides ≥ 100 pt, not Annotake's own, not in `excludedBundleIDs`;
    /// sorted by owner name, then title.
    static func pickable(_ windows: [WindowInfo], ownBundleID: String) -> [WindowInfo] {
        windows
            .filter { window in
                guard window.isOnScreen, window.layer == 0,
                      window.frame.width >= minimumSide, window.frame.height >= minimumSide else { return false }
                guard let owner = window.ownerBundleID else { return true }
                return owner != ownBundleID && !excludedBundleIDs.contains(owner)
            }
            .sorted {
                let owners = $0.ownerName.localizedStandardCompare($1.ownerName)
                if owners != .orderedSame { return owners == .orderedAscending }
                return ($0.title ?? "").localizedStandardCompare($1.title ?? "") == .orderedAscending
            }
    }
}

/// The picker's tiles, loaded when the Record tab opens.
@MainActor
final class RecordPickerModel: ObservableObject {
    nonisolated static let thumbnailWidth = 320

    enum Mode: String, CaseIterable, Identifiable {
        case screen = "Entire screen"
        case window = "Window"

        var id: Self { self }
    }

    struct Tile: Identifiable {
        let target: Settings.RecordTarget
        let title: String
        var icon: NSImage?
        var thumbnail: NSImage?

        var id: String {
            switch target {
            case .cursorScreen: "cursor"
            case .screen(let uuid): "screen-\(uuid)"
            case .window(let id, _): "window-\(id)"
            }
        }
    }

    typealias ContentLoader = @MainActor () async throws -> (snapshot: ContentSnapshot, content: SCShareableContent)

    @Published var screens: [Tile] = [RecordPickerModel.cursorTile]
    @Published var windows: [Tile] = []
    @Published var canCapture = true
    private let loader: ContentLoader?
    private let ownBundleID: String

    static let cursorTile = Tile(target: .cursorScreen, title: "Screen with the cursor")

    /// With no loader (UI snapshots), the tiles stay as set.
    init(loader: ContentLoader?, ownBundleID: String = SessionController.bundleID) {
        self.loader = loader
        self.ownBundleID = ownBundleID
    }

    func load() async {
        guard let loader else { return }
        guard CGPreflightScreenCaptureAccess() else {
            canCapture = false
            return
        }
        let snapshot: ContentSnapshot, content: SCShareableContent
        do {
            (snapshot, content) = try await loader()
        } catch {
            canCapture = (error as? CaptureError) != .permissionDenied
            return
        }
        canCapture = true
        screens = [Self.cursorTile] + snapshot.displays.map {
            Tile(target: .screen(displayUUID: $0.uuid), title: $0.name)
        }
        let pickable = WindowListFilter.pickable(snapshot.windows, ownBundleID: ownBundleID)
        windows = pickable.map { window in
            let pid = content.windows.first { $0.windowID == window.id }?.owningApplication?.processID
            let title = window.title.flatMap { $0.isEmpty ? nil : $0 } ?? window.ownerName
            return Tile(target: .window(windowID: window.id, title: title), title: title,
                        icon: pid.flatMap { NSRunningApplication(processIdentifier: $0)?.icon })
        }
        await loadThumbnails(snapshot: snapshot, content: content, windows: pickable)
    }

    /// A filter handed to a child task; SCContentFilter is safe to read from any task.
    private struct Capture: @unchecked Sendable {
        let id: String
        let filter: SCContentFilter
        let aspect: CGFloat
    }

    private func loadThumbnails(snapshot: ContentSnapshot, content: SCShareableContent, windows: [WindowInfo]) async {
        let own = content.applications.filter { $0.bundleIdentifier == ownBundleID }
        var captures: [Capture] = []
        for display in snapshot.displays {
            guard let scDisplay = content.displays.first(where: { $0.displayID == display.id }) else { continue }
            captures.append(Capture(
                id: "screen-\(display.uuid)",
                filter: SCContentFilter(display: scDisplay, excludingApplications: own, exceptingWindows: []),
                aspect: display.frame.width / max(display.frame.height, 1)))
        }
        for window in windows {
            guard let scWindow = content.windows.first(where: { $0.windowID == window.id }) else { continue }
            captures.append(Capture(id: "window-\(window.id)", filter: SCContentFilter(desktopIndependentWindow: scWindow),
                                    aspect: window.frame.width / max(window.frame.height, 1)))
        }
        await withTaskGroup(of: (String, NSImage?).self) { group in
            for capture in captures {
                group.addTask {
                    (capture.id, await Self.thumbnail(capture.filter, aspect: capture.aspect))
                }
            }
            for await (id, image) in group {
                setThumbnail(image, id: id)
            }
        }
    }

    private func setThumbnail(_ image: NSImage?, id: String) {
        if let index = screens.firstIndex(where: { $0.id == id }) { screens[index].thumbnail = image }
        if let index = windows.firstIndex(where: { $0.id == id }) { windows[index].thumbnail = image }
    }

    nonisolated private static func thumbnail(_ filter: SCContentFilter, aspect: CGFloat) async -> NSImage? {
        let configuration = SCStreamConfiguration()
        configuration.width = thumbnailWidth
        configuration.height = max(1, Int((CGFloat(thumbnailWidth) / aspect).rounded()))
        configuration.showsCursor = false
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        else { return nil }
        return NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
    }
}

/// The Record tab (spec §3.3, §3.6): a Meet-style picker of screens and windows.
struct RecordTab: View {
    static let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]
    static let windowGridHeight: CGFloat = 330
    @ObservedObject var model: SettingsModel
    @ObservedObject var picker: RecordPickerModel
    @State private var mode: RecordPickerModel.Mode

    init(model: SettingsModel, picker: RecordPickerModel) {
        self.model = model
        self.picker = picker
        if case .window = model.settings.recordTarget {
            _mode = State(initialValue: .window)
        } else {
            _mode = State(initialValue: .screen)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Record", selection: $mode) {
                ForEach(RecordPickerModel.Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if picker.canCapture {
                switch mode {
                case .screen:
                    grid(picker.screens)
                case .window:
                    if picker.windows.isEmpty {
                        Text("No windows to record.").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    } else {
                        ScrollView { grid(picker.windows) }
                            .frame(height: Self.windowGridHeight)
                    }
                }
            } else {
                PermissionRow(name: "Screen Recording", reason: "Needed to show your screens and windows here.",
                              granted: false, pane: PermissionPane.screenRecording)
            }

            Text("If a chosen screen or window is gone, Annotake records the screen with the cursor.")
                .font(.callout)
                .foregroundStyle(.secondary)

            RestoreDefaultsButton(tab: .record, model: model) { mode = .screen }
        }
        .padding(20)
        .frame(width: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await picker.load() }
    }

    private func grid(_ tiles: [RecordPickerModel.Tile]) -> some View {
        LazyVGrid(columns: Self.columns, spacing: 14) {
            ForEach(tiles) { tile in
                TileView(tile: tile, selected: tile.target == selectedTarget)
                    .onTapGesture { model.update { $0.recordTarget = tile.target } }
            }
        }
    }

    /// A window choice is matched by ID; its stored title doesn't matter.
    private var selectedTarget: Settings.RecordTarget {
        guard case let .window(id, _) = model.settings.recordTarget,
              let tile = picker.windows.first(where: { if case .window(id, _) = $0.target { true } else { false } })
        else { return model.settings.recordTarget }
        return tile.target
    }
}

private struct TileView: View {
    static let thumbnailHeight: CGFloat = 92
    let tile: RecordPickerModel.Tile
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.18))
                if let thumbnail = tile.thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6)).padding(4)
                } else if case .cursorScreen = tile.target {
                    Image(systemName: "cursorarrow.rays").font(.system(size: 30)).foregroundStyle(.secondary)
                }
            }
            .frame(height: Self.thumbnailHeight)
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 3))
            HStack(spacing: 6) {
                if let icon = tile.icon {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                }
                Text(tile.title).lineLimit(1).truncationMode(.middle)
                    .fontWeight(selected ? .semibold : .regular)
            }
            .font(.callout)
        }
        .contentShape(Rectangle())
    }
}
