import CoreGraphics

/// The size of the frames the stream delivers, in pixels.
public struct OutputSize: Sendable, Equatable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// Picks the stream's output size (spec §4.2).
public enum OutputSizing {
    /// Claude rejects images larger than this on either side once a conversation holds more than 20.
    public static let maxSide = 2000
    /// Keeps a side like 1567.9999… from flooring to 1566.
    private static let flooringSlack = 1e-9

    /// Scales the source so its long edge is at most `longEdge`, never up, and so the finished image,
    /// frame plus the tallest caption strip, fits within `maxSide` on both sides. Sides are even.
    /// - Parameters:
    ///   - sourcePixels: the target's size in points × its backing scale.
    ///   - stripRatio: the tallest caption strip ÷ width (CaptionLayout.maxHeightRatio, or 0 with the strip off).
    public static func fit(sourcePixels: CGSize, longEdge: Int, stripRatio: Double) -> OutputSize {
        let width = Double(sourcePixels.width), height = Double(sourcePixels.height)
        let scale = min(1,
                        Double(longEdge) / max(width, height),
                        Double(maxSide) / width,
                        Double(maxSide) / (height + stripRatio * width))
        func side(_ length: Double) -> Int {
            let pixels = Int((length * scale + flooringSlack).rounded(.down))
            return pixels - pixels % 2
        }
        return OutputSize(width: side(width), height: side(height))
    }
}
