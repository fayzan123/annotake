import CoreGraphics
import Foundation

/// A window's current title, straight from the window server by window ID. Window recordings follow it
/// for caption line 2 (spec §4.2). Other apps' titles need Screen Recording, which recording needs anyway.
public enum WindowTitle {
    /// The title, "" when the window has none, or nil when the window is gone.
    public static func read(windowID: CGWindowID) -> String? {
        guard let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[CFString: Any]],
              let window = windows.first
        else { return nil }
        return window[kCGWindowName] as? String ?? ""
    }
}
