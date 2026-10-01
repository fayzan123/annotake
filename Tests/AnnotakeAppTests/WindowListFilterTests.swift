import CoreGraphics
@testable import AnnotakeApp
import AnnotakeCapture
import Testing

struct WindowListFilterTests {
    static let own = "com.fayzanmalik.annotake"

    func window(_ id: CGWindowID, _ owner: String, bundleID: String?, title: String? = "Window",
                size: CGSize = CGSize(width: 800, height: 600), layer: Int = 0, onScreen: Bool = true) -> WindowInfo {
        WindowInfo(id: id, frame: CGRect(origin: .zero, size: size), title: title, layer: layer, isOnScreen: onScreen,
                   ownerBundleID: bundleID, ownerName: owner)
    }

    @Test func filtersSystemAndSmallWindows() {
        let keep = window(1, "Safari", bundleID: "com.apple.Safari", title: "Apple")
        let windows = [
            keep,
            window(2, "Dock", bundleID: "com.apple.dock"),
            window(3, "Annotake", bundleID: Self.own, title: "Annotake Settings"),
            window(4, "Notes", bundleID: "com.apple.Notes", size: CGSize(width: 50, height: 50)),
            window(5, "Mail", bundleID: "com.apple.mail", onScreen: false),
            window(6, "Control Center", bundleID: "com.apple.Notes", layer: 25),
        ]
        #expect(WindowListFilter.pickable(windows, ownBundleID: Self.own) == [keep])
    }

    @Test func sortsByOwnerThenTitle() {
        let windows = [
            window(1, "Safari", bundleID: "com.apple.Safari", title: "b"),
            window(2, "Finder", bundleID: "com.apple.finder", title: "Downloads"),
            window(3, "Safari", bundleID: "com.apple.Safari", title: "a"),
            window(4, "Cursor", bundleID: "com.todesktop.cursor", title: "main.swift"),
        ]
        #expect(WindowListFilter.pickable(windows, ownBundleID: Self.own).map(\.id) == [4, 2, 3, 1])
    }
}
