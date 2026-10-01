import CoreGraphics
import SwiftUI

/// Annotake's wordmark: the mark (BrandMark) as the first letter, then "nnotake" in Jost SemiBold with its
/// single-story a, outlined so the app needs no font. In BrandMark's logo units.
enum Wordmark {
    /// "nnotake" from the brand SVG, its first n 6 units past the A's right foot.
    static let letterPaths = """
        M169.45 -40V0H188.53V-42.04Q188.53 -53.84 182.8 -60.52Q177.06 -67.2 165.35 -67.2Q158.37 -67.2 153.44
        -64.26Q148.51 -61.31 145.47 -55.73V-65.71H127V0H145.47V-40Q145.47 -44.18 147.08 -47.19Q148.69 -50.2 151.65
        -51.82Q154.61 -53.43 158.51 -53.43Q164.27 -53.43 166.86 -49.99Q169.45 -46.55 169.45 -40Z M248.59
        -40V0H267.67V-42.04Q267.67 -53.84 261.94 -60.52Q256.2 -67.2 244.49 -67.2Q237.51 -67.2 232.58 -64.26Q227.65
        -61.31 224.61 -55.73V-65.71H206.14V0H224.61V-40Q224.61 -44.18 226.22 -47.19Q227.84 -50.2 230.8 -51.82Q233.76
        -53.43 237.65 -53.43Q243.41 -53.43 246 -49.99Q248.59 -46.55 248.59 -40Z M280.8 -32.86Q280.8 -22.69 285.57
        -14.94Q290.35 -7.18 298.61 -2.88Q306.88 1.43 317.25 1.43Q327.69 1.43 335.92 -2.88Q344.14 -7.18 348.92
        -14.94Q353.69 -22.69 353.69 -32.86Q353.69 -43.16 348.92 -50.88Q344.14 -58.59 335.92 -62.9Q327.69 -67.2 317.25
        -67.2Q306.88 -67.2 298.61 -62.9Q290.35 -58.59 285.57 -50.88Q280.8 -43.16 280.8 -32.86ZM299.71 -32.86Q299.71
        -38.49 302.06 -42.71Q304.41 -46.94 308.38 -49.27Q312.35 -51.59 317.25 -51.59Q322.14 -51.59 326.11 -49.27Q330.08
        -46.94 332.43 -42.71Q334.78 -38.49 334.78 -32.86Q334.78 -27.22 332.43 -23.04Q330.08 -18.86 326.11 -16.52Q322.14
        -14.18 317.25 -14.18Q312.35 -14.18 308.38 -16.52Q304.41 -18.86 302.06 -23.04Q299.71 -27.22 299.71 -32.86Z
        M358.39 -65.71V-50.1H398.9V-65.71H358.39ZM369.71 -88.57V0H387.57V-88.57H369.71Z M458.14
        -65.71V0H476.2V-65.71H458.14ZM403.65 -32.86Q403.65 -21.98 408.11 -14.3Q412.57 -6.61 419.82 -2.59Q427.06 1.43
        435.31 1.43Q443.59 1.43 449.89 -2.71Q456.18 -6.86 459.84 -14.57Q463.49 -22.29 463.49 -32.86Q463.49 -43.57 459.84
        -51.21Q456.18 -58.86 449.89 -63Q443.59 -67.14 435.31 -67.14Q427.06 -67.14 419.82 -63.12Q412.57 -59.1 408.11
        -51.49Q403.65 -43.88 403.65 -32.86ZM422.88 -32.86Q422.88 -38.78 425.31 -43.02Q427.74 -47.27 431.84 -49.55Q435.94
        -51.84 440.71 -51.84Q444.8 -51.84 448.73 -49.61Q452.67 -47.39 455.2 -43.14Q457.73 -38.9 457.73 -32.86Q457.73
        -26.82 455.2 -22.57Q452.67 -18.33 448.73 -16.1Q444.8 -13.88 440.71 -13.88Q435.94 -13.88 431.84 -16.16Q427.74
        -18.45 425.31 -22.72Q422.88 -27 422.88 -32.86Z M493.02 -111.43V0H510.88V-111.43H493.02ZM534.92 -65.71 506.65
        -38.57 538.02 0H559.96L528.84 -38.57L557.1 -65.71H534.92Z M597.8 1.43Q609.71 1.43 618.17 -3.21Q626.63 -7.86
        631.84 -17.12L615.63 -22.18Q612.86 -17.41 608.45 -15.03Q604.04 -12.65 598 -12.65Q592.51 -12.65 588.68
        -15.08Q584.86 -17.51 582.89 -22.11Q580.92 -26.71 580.98 -33.27Q581.06 -40.16 582.98 -44.77Q584.9 -49.37 588.59
        -51.72Q592.29 -54.08 597.69 -54.08Q602.1 -54.08 605.36 -52.14Q608.61 -50.2 610.45 -46.71Q612.29 -43.22 612.29
        -38.41Q612.29 -37.41 611.8 -35.94Q611.31 -34.47 610.69 -33.51L615.63 -40.08H573.02V-28.78H631.86Q631.98 -29.61
        632.02 -30.99Q632.06 -32.37 632.06 -33.73Q632.06 -44.29 628.07 -51.77Q624.08 -59.24 616.48 -63.19Q608.88 -67.14
        598 -67.14Q587.06 -67.14 579.06 -62.95Q571.06 -58.76 566.71 -51.07Q562.37 -43.39 562.37 -32.86Q562.37 -22.47
        566.72 -14.79Q571.08 -7.1 579.07 -2.84Q587.06 1.43 597.8 1.43Z
        """

    static func letters() throws -> CGPath { try SVGPath.parse(letterPaths) }

    /// The mark and the letters together.
    static func bounds() throws -> CGRect { BrandMark.bounds.union(try letters().boundingBoxOfPath) }
}

/// The logo, for the welcome step: in charcoal, or white in Dark Mode, with the red front reel.
struct WordmarkView: View {
    /// Read aloud in place of the logo.
    let label: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let bounds = (try? Wordmark.bounds()) ?? BrandMark.bounds
        Canvas { context, size in
            let fit = BrandMark.fitting(bounds, into: CGRect(origin: .zero, size: size))
            let ink = colorScheme == .dark ? Color.white : Color(hex: BrandMark.charcoal)
            for shape in BrandMark.shapes {
                context.fill(Path(shape.path).applying(fit),
                             with: .color(shape.part == .frontReel ? Color(hex: BrandMark.red) : ink),
                             style: FillStyle(eoFill: shape.evenOdd))
            }
            if let letters = try? Wordmark.letters() {
                context.fill(Path(letters).applying(fit), with: .color(ink))
            }
        }
        .aspectRatio(bounds.width / bounds.height, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isHeader)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Reads the path data the brand files use: absolute M, L, H, V, Q, C, and Z, which is what fontTools' SVGPathPen
/// writes for outlined lettering.
enum SVGPath {
    struct ParseError: Error, CustomStringConvertible {
        let description: String
    }

    static func parse(_ data: String) throws -> CGPath {
        let tokens = try tokenize(data)
        let path = CGMutablePath()
        var index = 0
        var command: Character?
        var start = CGPoint.zero, current = CGPoint.zero
        func number() throws -> CGFloat {
            guard index < tokens.count, case .number(let value) = tokens[index] else {
                throw ParseError(description: "\(command.map(String.init) ?? "?") needs more numbers")
            }
            index += 1
            return value
        }
        func point() throws -> CGPoint { CGPoint(x: try number(), y: try number()) }
        while index < tokens.count {
            if case .command(let letter) = tokens[index] {
                command = letter
                index += 1
            }
            switch command {
            case "M":
                current = try point()
                start = current
                path.move(to: current)
                command = "L"  // further pairs are lines
            case "L":
                current = try point()
                path.addLine(to: current)
            case "H":
                current.x = try number()
                path.addLine(to: current)
            case "V":
                current.y = try number()
                path.addLine(to: current)
            case "Q":
                let control = try point()
                current = try point()
                path.addQuadCurve(to: current, control: control)
            case "C":
                let first = try point(), second = try point()
                current = try point()
                path.addCurve(to: current, control1: first, control2: second)
            case "Z":
                path.closeSubpath()
                current = start
                command = nil
            case nil:
                throw ParseError(description: "path data has a number where a command should be")
            case let other?:
                throw ParseError(description: "\(other) isn't supported")
            }
        }
        return path
    }

    private enum Token { case command(Character), number(CGFloat) }

    private static func tokenize(_ data: String) throws -> [Token] {
        let chars = Array(data)
        let isDigit = { (c: Character) in c.isASCII && c.isNumber }
        var tokens: [Token] = []
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace || c == "," {
                i += 1
            } else if c.isLetter {
                tokens.append(.command(c))
                i += 1
            } else {
                var j = i
                if chars[j] == "-" || chars[j] == "+" { j += 1 }
                while j < chars.count, isDigit(chars[j]) || chars[j] == "." { j += 1 }
                if j < chars.count, chars[j] == "e" || chars[j] == "E" {
                    var k = j + 1
                    if k < chars.count, chars[k] == "-" || chars[k] == "+" { k += 1 }
                    if k < chars.count, isDigit(chars[k]) {
                        j = k
                        while j < chars.count, isDigit(chars[j]) { j += 1 }
                    }
                }
                guard j > i, let value = Double(String(chars[i..<j])) else {
                    throw ParseError(description: "unreadable number at character \(i)")
                }
                tokens.append(.number(CGFloat(value)))
                i = j
            }
        }
        return tokens
    }
}
