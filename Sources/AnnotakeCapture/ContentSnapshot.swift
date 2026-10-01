import CoreGraphics

/// A display, as a value copy of what ScreenCaptureKit and Core Graphics report.
public struct DisplayInfo: Sendable, Equatable {
    public let id: CGDirectDisplayID
    public let uuid: String
    public let name: String
    /// Global points, top-left origin (CGDisplayBounds).
    public let frame: CGRect
    /// The display mode's pixel size.
    public let pixelSize: CGSize

    public init(id: CGDirectDisplayID, uuid: String, name: String, frame: CGRect, pixelSize: CGSize) {
        self.id = id
        self.uuid = uuid
        self.name = name
        self.frame = frame
        self.pixelSize = pixelSize
    }
}

/// A window, as a value copy of an SCWindow.
public struct WindowInfo: Sendable, Equatable {
    public let id: CGWindowID
    /// Global points, top-left origin.
    public let frame: CGRect
    public let title: String?
    public let layer: Int
    public let isOnScreen: Bool
    public let ownerBundleID: String?
    public let ownerName: String

    public init(id: CGWindowID, frame: CGRect, title: String?, layer: Int, isOnScreen: Bool,
                ownerBundleID: String?, ownerName: String) {
        self.id = id
        self.frame = frame
        self.title = title
        self.layer = layer
        self.isOnScreen = isOnScreen
        self.ownerBundleID = ownerBundleID
        self.ownerName = ownerName
    }
}

/// Displays, windows and apps from one shareable-content query.
public struct ContentSnapshot: Sendable, Equatable {
    public var displays: [DisplayInfo]
    public var windows: [WindowInfo]
    public var appBundleIDs: [String]

    public init(displays: [DisplayInfo], windows: [WindowInfo], appBundleIDs: [String]) {
        self.displays = displays
        self.windows = windows
        self.appBundleIDs = appBundleIDs
    }
}

public enum ResolvedTarget: Sendable, Equatable {
    case display(DisplayInfo)
    case window(WindowInfo)
}

/// Turns the Record setting into what to capture (spec §3.3).
public enum TargetResolver {
    public enum Setting: Sendable, Equatable {
        case cursorScreen
        case screen(uuid: String)
        case window(id: CGWindowID)
    }

    public static let windowMissingNote = "Window not found — recording your screen"
    public static let screenMissingNote = "Screen not found — recording your screen"

    /// A chosen screen or window that's gone falls back to the cursor's screen, with a note for the pill.
    /// Windows are matched by ID only, never guessed by title. Nil only when the snapshot has no displays.
    public static func resolve(_ setting: Setting, cursor: CGPoint,
                               in snapshot: ContentSnapshot) -> (target: ResolvedTarget, note: String?)? {
        guard let first = snapshot.displays.first else { return nil }
        let cursorDisplay = snapshot.displays.first { $0.frame.contains(cursor) } ?? first
        switch setting {
        case .cursorScreen:
            return (.display(cursorDisplay), nil)
        case .screen(let uuid):
            if let display = snapshot.displays.first(where: { $0.uuid == uuid }) {
                return (.display(display), nil)
            }
            return (.display(cursorDisplay), screenMissingNote)
        case .window(let id):
            if let window = snapshot.windows.first(where: { $0.id == id }) {
                return (.window(window), nil)
            }
            return (.display(cursorDisplay), windowMissingNote)
        }
    }
}

public enum StatusItemFinding: Sendable, Equatable {
    case notFound
    case ownedByUs
    case ownedBy(bundleID: String)
}

/// What a display filter excludes (spec §6.2): Annotake itself, Notification Center's banners, and
/// on macOS 26 the menu-bar icon, whose window another process may own.
public struct FilterPlan: Sendable, Equatable {
    public static let notificationCenterBundleID = "com.apple.notificationcenterui"
    /// Menu-bar windows sit at this window layer or above.
    public static let statusItemMinimumLayer = 24
    /// How far a window's frame may be from the status item's and still count as it, in points.
    public static let statusItemFrameTolerance: CGFloat = 1

    public var excludedBundleIDs: [String]
    public var exceptingWindowIDs: [CGWindowID]
    public var statusItem: StatusItemFinding

    public init(excludedBundleIDs: [String], exceptingWindowIDs: [CGWindowID], statusItem: StatusItemFinding) {
        self.excludedBundleIDs = excludedBundleIDs
        self.exceptingWindowIDs = exceptingWindowIDs
        self.statusItem = statusItem
    }

    /// Finds the status item's window by number, else by its frame at menu-bar level. When another app
    /// owns it, that app is excluded too and its other windows are listed as exceptions, because a filter
    /// can't exclude one window of another app while also excluding whole apps.
    public static func make(ownBundleID: String, snapshot: ContentSnapshot,
                            statusItemWindowNumber: Int?, statusItemFrame: CGRect?) -> FilterPlan {
        var excluded = [ownBundleID]
        if snapshot.appBundleIDs.contains(notificationCenterBundleID) {
            excluded.append(notificationCenterBundleID)
        }
        let byNumber = statusItemWindowNumber.flatMap { number in
            snapshot.windows.first { Int($0.id) == number }
        }
        let byFrame = statusItemFrame.flatMap { frame in
            snapshot.windows.first { $0.layer >= statusItemMinimumLayer && $0.frame.isClose(to: frame) }
        }
        guard let window = byNumber ?? byFrame, let owner = window.ownerBundleID else {
            return FilterPlan(excludedBundleIDs: excluded, exceptingWindowIDs: [], statusItem: .notFound)
        }
        if owner == ownBundleID {
            return FilterPlan(excludedBundleIDs: excluded, exceptingWindowIDs: [], statusItem: .ownedByUs)
        }
        // Notification Center is excluded whole; its banners must never come back as exceptions.
        guard !excluded.contains(owner) else {
            return FilterPlan(excludedBundleIDs: excluded, exceptingWindowIDs: [], statusItem: .ownedBy(bundleID: owner))
        }
        excluded.append(owner)
        let excepting = snapshot.windows.filter { $0.ownerBundleID == owner && $0.id != window.id }.map(\.id)
        return FilterPlan(excludedBundleIDs: excluded, exceptingWindowIDs: excepting, statusItem: .ownedBy(bundleID: owner))
    }
}

extension CGRect {
    fileprivate func isClose(to other: CGRect) -> Bool {
        let tolerance = FilterPlan.statusItemFrameTolerance
        return abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(maxX - other.maxX) <= tolerance && abs(maxY - other.maxY) <= tolerance
    }
}
