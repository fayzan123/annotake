// Draws the disk image's background: `swift scripts/make-dmg-background.swift <dir>` writes background.tiff
// (600 × 400) and background@2x.tiff, which `make dmg-background` combines into Resources/dmg-background.tiff
// with tiffutil. A light window, an arrow from the app to Applications, and one line of text.
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The Finder window, in points.
let size = CGSize(width: 600, height: 400)
/// From the app's icon at x 150 to Applications at x 450, both at y 190 from the top.
let arrowStart: CGFloat = 215
let arrowEnd: CGFloat = 385
let arrowY: CGFloat = 190
let arrowWidth: CGFloat = 6
let arrowHead: CGFloat = 16
let text = "Drag Annotake to Applications"
let textSize: CGFloat = 15
let textY: CGFloat = 330

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32) -> CGColor {
    CGColor(colorSpace: sRGB, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
                                           CGFloat(hex & 0xFF) / 255, 1])!
}

func draw(scale: CGFloat) -> CGImage {
    let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                            bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: scale, y: scale)
    context.setFillColor(color(0xF5F5F7))
    context.fill(CGRect(origin: .zero, size: size))

    // The bitmap's y points up; the layout's y is from the top, as Finder positions icons.
    let y = size.height - arrowY
    context.setStrokeColor(color(0x8E8E93))
    context.setLineWidth(arrowWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: CGPoint(x: arrowStart, y: y))
    context.addLine(to: CGPoint(x: arrowEnd, y: y))
    context.move(to: CGPoint(x: arrowEnd - arrowHead, y: y + arrowHead))
    context.addLine(to: CGPoint(x: arrowEnd, y: y))
    context.addLine(to: CGPoint(x: arrowEnd - arrowHead, y: y - arrowHead))
    context.strokePath()

    let font = CTFontCreateUIFontForLanguage(.system, textSize, nil)!
    let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): font,
                      NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(0x6E6E73)] as [NSAttributedString.Key: Any]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
    let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
    // Centered on the line's middle at textY from the top.
    context.textPosition = CGPoint(x: (size.width - width) / 2, y: size.height - textY - (ascent - descent) / 2)
    CTLineDraw(line, context)
    return context.makeImage()!
}

func writeTIFF(_ image: CGImage, dpi: CGFloat, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil)
    else { fatalError("can't write \(url.path)") }
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { fatalError("can't write \(url.path)") }
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift scripts/make-dmg-background.swift <dir>\n".utf8))
    exit(2)
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
writeTIFF(draw(scale: 1), dpi: 72, to: directory.appending(path: "background.tiff"))
writeTIFF(draw(scale: 2), dpi: 144, to: directory.appending(path: "background@2x.tiff"))
print("wrote background.tiff and background@2x.tiff to \(directory.path)")
