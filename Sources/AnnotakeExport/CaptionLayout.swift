import CoreGraphics
import CoreText
import Foundation

/// The caption strip's metrics and line wrapping (spec §4.2). Every size follows the frame width.
public enum CaptionLayout {
    /// The tallest strip is at most this fraction of the width (at most 0.1121 for widths 400–2000),
    /// so capture sizing can reserve room for it.
    public static let maxHeightRatio: Double = 0.115
    /// Line 1 wraps to at most this many lines.
    public static let maxLines1 = 3
    /// Line 1's font size is the width divided by this: 30 px at 1920.
    static let widthPerFontSize1: CGFloat = 64
    static let fontSize2Ratio: CGFloat = 0.85
    static let lineHeightRatio: CGFloat = 1.3
    static let paddingRatio: CGFloat = 0.8
    static let gapRatio: CGFloat = 0.3
    static let ellipsis = "…"

    public struct Metrics: Equatable, Sendable {
        public let fontSize1: CGFloat, fontSize2: CGFloat
        public let lineHeight1: Int, lineHeight2: Int, padding: Int, gap: Int
    }

    public static func metrics(forWidth width: Int) -> Metrics {
        let fontSize1 = CGFloat(width) / widthPerFontSize1
        let fontSize2 = fontSize2Ratio * fontSize1
        return Metrics(fontSize1: fontSize1, fontSize2: fontSize2,
                       lineHeight1: Int((lineHeightRatio * fontSize1).rounded()),
                       lineHeight2: Int((lineHeightRatio * fontSize2).rounded()),
                       padding: Int((paddingRatio * fontSize1).rounded()),
                       gap: Int((gapRatio * fontSize1).rounded()))
    }

    /// 2·padding + n·lineHeight1 + gap + lineHeight2.
    public static func stripHeight(lineCount1: Int, width: Int) -> Int {
        let metrics = metrics(forWidth: width)
        return 2 * metrics.padding + lineCount1 * metrics.lineHeight1 + metrics.gap + metrics.lineHeight2
    }

    public static func maxStripHeight(forWidth width: Int) -> Int {
        stripHeight(lineCount1: maxLines1, width: width)
    }

    /// Line 1 broken into 1…3 lines that each fit within width − 2·padding. When the text needs more,
    /// the third line is cut and ends with "…".
    public static func wrap(_ line1: String, width: Int) -> [String] {
        let metrics = metrics(forWidth: width)
        let available = Double(width - 2 * metrics.padding)
        let text = line1 as NSString
        let typesetter = CTTypesetterCreateWithAttributedString(
            attributed(line1, font: CaptionFonts.line1(size: metrics.fontSize1), color: nil))
        var lines: [String] = []
        var start = 0
        while start < text.length {
            let count = max(1, CTTypesetterSuggestLineBreak(typesetter, start, available))
            if lines.count == maxLines1 - 1 && start + count < text.length {
                // The last line allowed, and more text follows: cut it where "…" still fits.
                let ellipsisWidth = typographicWidth(of: ellipsis, font: CaptionFonts.line1(size: metrics.fontSize1))
                let fitting = CTTypesetterSuggestClusterBreak(typesetter, start, max(0, available - ellipsisWidth))
                lines.append(trimmed(text.substring(with: NSRange(location: start, length: fitting))) + ellipsis)
                return lines
            }
            lines.append(trimmed(text.substring(with: NSRange(location: start, length: count))))
            start += count
        }
        return lines.isEmpty ? [""] : lines
    }

    static func attributed(_ string: String, font: CTFont, color: CGColor?) -> CFAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
        if let color {
            attributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = color
        }
        return NSAttributedString(string: string, attributes: attributes)
    }

    static func typographicWidth(of string: String, font: CTFont) -> Double {
        CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed(string, font: font, color: nil)),
                                   nil, nil, nil)
    }

    private static func trimmed(_ line: String) -> String {
        var line = line
        while let last = line.last, last.isWhitespace || last.isNewline {
            line.removeLast()
        }
        return line
    }
}

/// The system font at the caption weights, from CoreText alone.
enum CaptionFonts {
    static func line1(size: CGFloat) -> CTFont { system(size: size, weight: semibold) }
    static func line2(size: CGFloat) -> CTFont { system(size: size, weight: regular) }
    static func badge(size: CGFloat) -> CTFont { system(size: size, weight: bold) }

    // NSFont.Weight's values.
    private static let regular: CGFloat = 0
    private static let semibold: CGFloat = 0.3
    private static let bold: CGFloat = 0.4

    private static func system(size: CGFloat, weight: CGFloat) -> CTFont {
        let base = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let traits = [kCTFontWeightTrait: weight] as CFDictionary
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(
            CTFontCopyFontDescriptor(base), [kCTFontTraitsAttribute: traits] as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }
}
