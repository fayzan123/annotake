import CoreGraphics
import AnnotakeCore

/// Maps global screen points onto the recorded area's output pixels.
public struct TargetMapping: Sendable, Equatable {
    /// The cursor box reaches this far above and left of the hotspot, in points at cursor size 1…
    public static let cursorBoxBefore: Double = 12
    /// …and this far below and right of it.
    public static let cursorBoxAfter: Double = 32

    /// The recorded area in global points, top-left origin (Quartz, as CGEvent.location).
    public var screenRect: CGRect
    public var output: OutputSize

    public init(screenRect: CGRect, output: OutputSize) {
        self.screenRect = screenRect
        self.output = output
    }

    public var pixelsPerPoint: Double { Double(output.width) / screenRect.width }

    private var scaleX: Double { Double(output.width) / screenRect.width }
    private var scaleY: Double { Double(output.height) / screenRect.height }

    /// minX ≤ x < maxX and minY ≤ y < maxY.
    public func contains(_ global: CGPoint) -> Bool {
        global.x >= screenRect.minX && global.x < screenRect.maxX
            && global.y >= screenRect.minY && global.y < screenRect.maxY
    }

    /// The point in output pixels, or nil when it's outside the recorded area.
    public func outputPoint(_ global: CGPoint) -> PixelPoint? {
        guard contains(global) else { return nil }
        return PixelPoint(x: (global.x - screenRect.minX) * scaleX, y: (global.y - screenRect.minY) * scaleY)
    }

    /// The box the pointer can cover, in output pixels, scaled by the Accessibility cursor size.
    /// Nil when the hotspot is outside the recorded area.
    public func cursorRect(hotspot: CGPoint, cursorScale: Double) -> PixelRect? {
        guard contains(hotspot) else { return nil }
        let before = Self.cursorBoxBefore * cursorScale
        let span = (Self.cursorBoxBefore + Self.cursorBoxAfter) * cursorScale
        return PixelRect(
            x: Int(((hotspot.x - before - screenRect.minX) * scaleX).rounded(.down)),
            y: Int(((hotspot.y - before - screenRect.minY) * scaleY).rounded(.down)),
            width: Int((span * scaleX).rounded(.up)),
            height: Int((span * scaleY).rounded(.up)))
    }
}
