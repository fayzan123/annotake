import CoreGraphics

/// Annotake's mark: a two-reel movie camera standing on a capital A, its tripod. The app icon
/// (`scripts/make-icon.swift` compiles this file too, so keep it to CoreGraphics), the menu-bar icon, and the
/// welcome step's logo all draw these shapes.
///
/// Logo units, as in the brand SVGs: the cap height is 100, the A's feet sit on the baseline at y = 0, and y grows
/// downward. The legs are as thick as the stems of Jost SemiBold, the wordmark's font, so the A belongs to the word.
enum BrandMark {
    enum Part { case ink, frontReel }

    struct Shape {
        let path: CGPath
        /// Rings fill even-odd, which punches their holes.
        let evenOdd: Bool
        let part: Part
    }

    /// The brand's colors: charcoal for the mark (white on dark backgrounds), and the click marker's red, which the
    /// front reel takes.
    static let charcoal: UInt32 = 0x1C1C1E
    static let red: UInt32 = 0xFF3B30

    static let capHeight: CGFloat = 100
    /// The A: its feet span 1.21 cap heights, and its legs splay 26° from vertical.
    static let footSpan: CGFloat = 121
    static let splay: CGFloat = 26 * .pi / 180
    /// Jost SemiBold's stem at this cap height.
    static let stem: CGFloat = 20.71
    /// How far up the legs run: past the cap height, hidden in the camera body.
    static let legTop: CGFloat = -112
    /// The crossbar, the tripod's leg brace, centered 0.38 cap heights up.
    static let crossbarY: CGFloat = -38
    /// How thick the legs and the brace are, square to their length. The site's footer animation
    /// (scripts/make-site-brand.swift) reads them too.
    static let legThickness = 0.95 * stem
    static let braceThickness = 0.85 * stem

    /// The camera is as wide as the A's feet, and its body sits just below the cap line so the apex disappears.
    static let cameraWidth = footSpan
    static let bodyBottom = -capHeight + 4
    static let bodyHeight = 0.56 * cameraWidth
    static let reelRadius = 0.23 * cameraWidth
    static let reelHoleRadius = reelRadius - 0.125 * cameraWidth
    static let frontReelCenter = CGPoint(x: cameraWidth - reelRadius,
                                         y: bodyBottom - bodyHeight - 0.06 * cameraWidth - reelRadius)
    static let lensLength = 0.25 * cameraWidth

    /// From the A's left foot to the lens's mouth, and from the top of the reels to the baseline.
    static let bounds = CGRect(x: 0, y: frontReelCenter.y - reelRadius, width: cameraWidth + lensLength,
                               height: reelRadius - frontReelCenter.y)

    static var shapes: [Shape] {
        let t = tan(splay)
        let leg = legThickness / cos(splay)  // across, horizontally
        let leftOuter = { (y: CGFloat) in -y * t }
        let rightOuter = { (y: CGFloat) in footSpan + y * t }
        let bar = braceThickness
        let bodyTop = bodyBottom - bodyHeight
        let lensY = bodyBottom - bodyHeight / 2
        let lensStart = cameraWidth - 0.01 * cameraWidth
        let lensEnd = cameraWidth + lensLength
        let ink = { (path: CGPath) in Shape(path: path, evenOdd: false, part: .ink) }
        return [
            ink(polygon([(leftOuter(0), 0), (leftOuter(0) + leg, 0), (leftOuter(legTop) + leg, legTop),
                         (leftOuter(legTop), legTop)])),
            ink(polygon([(rightOuter(0), 0), (rightOuter(0) - leg, 0), (rightOuter(legTop) - leg, legTop),
                         (rightOuter(legTop), legTop)])),
            ink(polygon([(leftOuter(crossbarY) + leg / 2, crossbarY - bar / 2),
                         (rightOuter(crossbarY) - leg / 2, crossbarY - bar / 2),
                         (rightOuter(crossbarY) - leg / 2, crossbarY + bar / 2),
                         (leftOuter(crossbarY) + leg / 2, crossbarY + bar / 2)])),
            ink(CGPath(roundedRect: CGRect(x: 0, y: bodyTop, width: cameraWidth, height: bodyHeight),
                       cornerWidth: 0.09 * cameraWidth, cornerHeight: 0.09 * cameraWidth, transform: nil)),
            ink(polygon([(lensStart, lensY - 0.13 * cameraWidth), (lensEnd, lensY - 0.245 * cameraWidth),
                         (lensEnd, lensY + 0.245 * cameraWidth), (lensStart, lensY + 0.13 * cameraWidth)])),
            Shape(path: ring(at: CGPoint(x: reelRadius, y: frontReelCenter.y)), evenOdd: true, part: .ink),
            Shape(path: ring(at: frontReelCenter), evenOdd: true, part: .frontReel),
        ]
    }

    /// Scales `rect` to fit `target`, keeping its proportions, and centers it there.
    static func fitting(_ rect: CGRect, into target: CGRect) -> CGAffineTransform {
        let scale = min(target.width / rect.width, target.height / rect.height)
        let x = target.minX + (target.width - rect.width * scale) / 2
        let y = target.minY + (target.height - rect.height * scale) / 2
        return CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: x - rect.minX * scale, ty: y - rect.minY * scale)
    }

    /// Draws the mark fitted and centered in `rect`, in a context whose origin is at the top left.
    static func draw(in context: CGContext, rect: CGRect, ink: CGColor, frontReel: CGColor) {
        context.saveGState()
        context.concatenate(fitting(bounds, into: rect))
        for shape in shapes {
            context.addPath(shape.path)
            context.setFillColor(shape.part == .frontReel ? frontReel : ink)
            context.fillPath(using: shape.evenOdd ? .evenOdd : .winding)
        }
        context.restoreGState()
    }

    private static func polygon(_ points: [(CGFloat, CGFloat)]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points.map { CGPoint(x: $0.0, y: $0.1) })
        path.closeSubpath()
        return path
    }

    private static func ring(at center: CGPoint) -> CGPath {
        let path = CGMutablePath()
        for radius in [reelRadius, reelHoleRadius] {
            path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
        }
        return path
    }
}
