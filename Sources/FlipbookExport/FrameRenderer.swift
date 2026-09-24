import CoreGraphics
import CoreText
import FlipbookCore
import Foundation
import ImageIO

/// Where a click marker goes, in output pixels (top-left origin).
public struct MarkerLayout: Equatable, Sendable {
    /// The number shown when a frame has more than one click.
    public struct Badge: Equatable, Sendable {
        public let center: PixelPoint
        public let radius: CGFloat
        public let number: Int

        public init(center: PixelPoint, radius: CGFloat, number: Int) {
            self.center = center
            self.radius = radius
            self.number = number
        }
    }

    public let center: PixelPoint
    public let radius: CGFloat
    public let badge: Badge?
}

/// Draws a frame with its caption strip under it and a marker at each click (spec §4.2).
public enum FrameRenderer {
    /// A marker's radius is the width divided by this: 24 px at 1920.
    static let widthPerMarkerRadius: CGFloat = 80
    static let haloWidth: CGFloat = 6
    static let ringWidth: CGFloat = 3
    static let badgeRadiusRatio: CGFloat = 0.45
    /// The badge number's font size, relative to the badge radius.
    static let badgeFontRatio: CGFloat = 1.3
    /// The strip's background, #1C1C1E.
    static let stripColor = CGColor(srgbRed: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)
    /// Line 2's color, #A1A1A6.
    static let line2Color = CGColor(srgbRed: 0xA1 / 255, green: 0xA1 / 255, blue: 0xA6 / 255, alpha: 1)
    /// The marker ring and badge, #FF3B30.
    static let markerColor = CGColor(srgbRed: 1, green: 0x3B / 255, blue: 0x30 / 255, alpha: 1)
    static let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// A marker for each click inside the frame. Numbered badges appear only when there are two or more.
    public static func markerLayout(clickPoints: [PixelPoint], width: Int, height: Int) -> [MarkerLayout] {
        let radius = CGFloat(width) / widthPerMarkerRadius
        let inside = clickPoints.filter { $0.x >= 0 && $0.y >= 0 && $0.x < Double(width) && $0.y < Double(height) }
        return inside.enumerated().map { offset, point in
            let badge = inside.count < 2 ? nil : MarkerLayout.Badge(
                center: PixelPoint(x: point.x + Double(radius), y: point.y - Double(radius)),
                radius: badgeRadiusRatio * radius, number: offset + 1)
            return MarkerLayout(center: point, radius: radius, badge: badge)
        }
    }

    /// The frame on top, the caption strip under it, markers over the frame. RGBA8, sRGB.
    public static func render(frame: CGImage, line1: String, line2: String,
                              clickPoints: [PixelPoint], options: RenderOptions) -> CGImage {
        let width = frame.width
        let lines = options.captionStrip ? CaptionLayout.wrap(line1, width: width) : []
        let stripHeight = options.captionStrip ? CaptionLayout.stripHeight(lineCount1: lines.count, width: width) : 0
        let height = frame.height + stripHeight
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .none
        // Core Graphics puts the origin at the bottom left; layouts use the top left.
        func flipped(_ point: PixelPoint) -> CGPoint { CGPoint(x: point.x, y: Double(height) - point.y) }

        context.draw(frame, in: CGRect(x: 0, y: stripHeight, width: width, height: frame.height))

        if options.clickMarkers {
            context.saveGState()
            context.clip(to: CGRect(x: 0, y: stripHeight, width: width, height: frame.height))
            for marker in markerLayout(clickPoints: clickPoints, width: width, height: frame.height) {
                drawMarker(marker, in: context, flipped: flipped)
            }
            context.restoreGState()
        }

        if options.captionStrip {
            context.setFillColor(stripColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: stripHeight))
            let metrics = CaptionLayout.metrics(forWidth: width)
            let available = Double(width - 2 * metrics.padding)
            var top = Double(frame.height + metrics.padding)
            let font1 = CaptionFonts.line1(size: metrics.fontSize1)
            for line in lines {
                let ctLine = CTLineCreateWithAttributedString(CaptionLayout.attributed(line, font: font1, color: white))
                draw(ctLine, font: font1, x: Double(metrics.padding), boxTop: top, boxHeight: metrics.lineHeight1,
                     in: context, imageHeight: height)
                top += Double(metrics.lineHeight1)
            }
            top += Double(metrics.gap)
            let font2 = CaptionFonts.line2(size: metrics.fontSize2)
            let full = CTLineCreateWithAttributedString(CaptionLayout.attributed(line2, font: font2, color: line2Color))
            let ellipsis = CTLineCreateWithAttributedString(
                CaptionLayout.attributed(CaptionLayout.ellipsis, font: font2, color: line2Color))
            let truncated = CTLineCreateTruncatedLine(full, available, .end, ellipsis) ?? full
            draw(truncated, font: font2, x: Double(metrics.padding), boxTop: top, boxHeight: metrics.lineHeight2,
                 in: context, imageHeight: height)
        }
        return context.makeImage()!
    }

    private static func drawMarker(_ marker: MarkerLayout, in context: CGContext, flipped: (PixelPoint) -> CGPoint) {
        let center = flipped(marker.center)
        let ring = CGRect(x: center.x - marker.radius, y: center.y - marker.radius,
                          width: 2 * marker.radius, height: 2 * marker.radius)
        context.setStrokeColor(white)
        context.setLineWidth(haloWidth)
        context.strokeEllipse(in: ring)
        context.setStrokeColor(markerColor)
        context.setLineWidth(ringWidth)
        context.strokeEllipse(in: ring)

        guard let badge = marker.badge else { return }
        let badgeCenter = flipped(badge.center)
        context.setFillColor(markerColor)
        context.fillEllipse(in: CGRect(x: badgeCenter.x - badge.radius, y: badgeCenter.y - badge.radius,
                                       width: 2 * badge.radius, height: 2 * badge.radius))
        let font = CaptionFonts.badge(size: badgeFontRatio * badge.radius)
        let number = CTLineCreateWithAttributedString(CaptionLayout.attributed("\(badge.number)", font: font, color: white))
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CTLineGetTypographicBounds(number, &ascent, &descent, nil)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: badgeCenter.x - width / 2, y: badgeCenter.y - (ascent - descent) / 2)
        CTLineDraw(number, context)
    }

    /// Draws the line with its glyphs centered vertically in a box given in top-left coordinates.
    private static func draw(_ line: CTLine, font: CTFont, x: Double, boxTop: Double, boxHeight: Int,
                             in context: CGContext, imageHeight: Int) {
        let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)
        let baselineFromTop = boxTop + (Double(boxHeight) - (ascent + descent)) / 2 + ascent
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: x, y: Double(imageHeight) - baselineFromTop)
        CTLineDraw(line, context)
    }
}

public enum PNGFileError: Error, Equatable {
    case cannotEncode
    case cannotDecode(path: String)
}

/// sRGB PNGs through ImageIO.
public enum PNGFile {
    private static let pngType = "public.png"

    /// Writes atomically, so a reader never sees a half-written file.
    public static func write(_ image: CGImage, to url: URL) throws {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, pngType as CFString, 1, nil) else {
            throw PNGFileError.cannotEncode
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw PNGFileError.cannotEncode }
        try (data as Data).write(to: url, options: .atomic)
    }

    public static func read(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw PNGFileError.cannotDecode(path: url.path) }
        return image
    }
}
