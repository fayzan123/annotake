// Draws Annotake's app icon set: `swift scripts/make-icon.swift <out.iconset>`, then `iconutil` makes the
// .icns (`make icon`). The master is drawn at 1024 px and scaled down for each size.
//
// A dark body like the caption strip, three fanned frames, and on the front one the click marker: the red
// ring every capture puts where you clicked.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvas: CGFloat = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyRadius: CGFloat = 186
let frameSize = CGSize(width: 560, height: 430)
let frameRadius: CGFloat = 28
/// The frames' center: 30 px above the canvas's middle.
let frameCenter = CGPoint(x: canvas / 2, y: canvas / 2 - 30)
/// The back frames: color and rotation in degrees, back to front.
let backFrames: [(color: UInt32, degrees: CGFloat)] = [(0xC7C7CC, -8), (0xE5E5EA, 6)]
let shadowBlur: CGFloat = 24
let shadowDrop: CGFloat = 10
let shadowAlpha: CGFloat = 0.25
let captionStripFraction: CGFloat = 0.17
let captionBarFraction: CGFloat = 0.45
let ringRadius: CGFloat = 44
let ringWidth: CGFloat = 14
let haloWidth: CGFloat = 26
/// Each size, also drawn at @2x.
let sizes = [16, 32, 128, 256, 512]
/// Images this small come from a simplified master: no content lines, and a ring bold enough to stay red at
/// 32 px, where the full one blurs into the button.
let simplifiedUpTo = 64
let simplifiedRing = (radius: CGFloat(92), width: CGFloat(44), halo: CGFloat(72))

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
                                           CGFloat(hex & 0xFF) / 255, alpha])!
}

func makeContext(_ pixels: Int) -> CGContext {
    CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// A frame centered on the origin, in a top-left coordinate space.
func frameRect() -> CGRect {
    CGRect(x: -frameSize.width / 2, y: -frameSize.height / 2, width: frameSize.width, height: frameSize.height)
}

func withShadow(_ context: CGContext, _ draw: () -> Void) {
    context.saveGState()
    // Shadow offsets are in the bitmap's own space, where y points up.
    context.setShadow(offset: CGSize(width: 0, height: -shadowDrop), blur: shadowBlur,
                      color: color(0x000000, alpha: shadowAlpha))
    draw()
    context.restoreGState()
}

/// The front frame's content: a toolbar, two lines of content, a button with the click marker on it, and a
/// caption strip with a line of text.
func drawScreenshot(_ context: CGContext, in frame: CGRect, simplified: Bool) {
    context.saveGState()
    context.addPath(roundedRect(frame, frameRadius))
    context.clip()
    context.setFillColor(color(0xFFFFFF))
    context.fill(frame)

    let toolbar = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: 56)
    context.setFillColor(color(0xE5E5EA))
    context.fill(toolbar)

    context.setFillColor(color(0xD1D1D6))
    for (offset, width) in simplified ? [] : [(92.0, 300.0), (134.0, 220.0)] {
        context.addPath(roundedRect(CGRect(x: frame.minX + 40, y: frame.minY + offset, width: width, height: 24), 12))
        context.fillPath()
    }

    let button = CGRect(x: frame.minX + 40, y: frame.minY + 196, width: 200, height: 64)
    context.setFillColor(color(0x0A84FF))
    context.addPath(roundedRect(button, 16))
    context.fillPath()

    let stripHeight = frame.height * captionStripFraction
    let strip = CGRect(x: frame.minX, y: frame.maxY - stripHeight, width: frame.width, height: stripHeight)
    context.setFillColor(color(0x1C1C1E))
    context.fill(strip)
    let barHeight: CGFloat = 18
    let bar = CGRect(x: strip.minX + 32, y: strip.midY - barHeight / 2, width: frame.width * captionBarFraction,
                     height: barHeight)
    context.setFillColor(color(0xFFFFFF))
    context.addPath(roundedRect(bar, barHeight / 2))
    context.fillPath()
    context.restoreGState()

    // The click marker, over everything: a white halo under a red ring.
    let (radius, width, halo) = simplified ? simplifiedRing : (ringRadius, ringWidth, haloWidth)
    let ring = CGRect(x: button.midX + 20 - radius, y: button.midY - radius, width: radius * 2, height: radius * 2)
    for (stroke, width) in [(color(0xFFFFFF), halo), (color(0xFF3B30), width)] {
        context.setStrokeColor(stroke)
        context.setLineWidth(width)
        context.strokeEllipse(in: ring)
    }
}

func drawMaster(simplified: Bool) -> CGImage {
    let context = makeContext(Int(canvas))
    // Top-left origin, like the plan's coordinates.
    context.translateBy(x: 0, y: canvas)
    context.scaleBy(x: 1, y: -1)

    // The body: a vertical gradient from #2C2C2E at the top to #1C1C1E at the bottom.
    context.saveGState()
    context.addPath(roundedRect(body, bodyRadius))
    context.clip()
    let gradient = CGGradient(colorsSpace: sRGB, colors: [color(0x2C2C2E), color(0x1C1C1E)] as CFArray,
                              locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: body.midX, y: body.minY),
                               end: CGPoint(x: body.midX, y: body.maxY), options: [])
    context.restoreGState()

    for back in backFrames {
        context.saveGState()
        context.translateBy(x: frameCenter.x, y: frameCenter.y)
        // The space is flipped, so a positive angle here turns clockwise; negate it to keep the usual sense.
        context.rotate(by: -back.degrees * .pi / 180)
        withShadow(context) {
            context.setFillColor(color(back.color))
            context.addPath(roundedRect(frameRect(), frameRadius))
            context.fillPath()
        }
        context.restoreGState()
    }

    context.saveGState()
    context.translateBy(x: frameCenter.x, y: frameCenter.y)
    withShadow(context) {
        context.setFillColor(color(0xFFFFFF))
        context.addPath(roundedRect(frameRect(), frameRadius))
        context.fillPath()
    }
    drawScreenshot(context, in: frameRect(), simplified: simplified)
    context.restoreGState()
    return context.makeImage()!
}

func scaled(_ image: CGImage, to pixels: Int) -> CGImage {
    let context = makeContext(pixels)
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("can't write \(url.path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("can't write \(url.path)") }
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift scripts/make-icon.swift <out.iconset>\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let master = drawMaster(simplified: false)
let simplifiedMaster = drawMaster(simplified: true)
for size in sizes {
    for (pixels, name) in [(size, "icon_\(size)x\(size).png"), (size * 2, "icon_\(size)x\(size)@2x.png")] {
        writePNG(scaled(pixels <= simplifiedUpTo ? simplifiedMaster : master, to: pixels), to: output.appending(path: name))
    }
}
print("wrote \(sizes.count * 2) icons to \(output.path)")
