// Draws Annotake's app icon set. `make icon` compiles this with Sources/AnnotakeApp/BrandMark.swift, which holds the
// mark's shapes, runs it as `make-icon <out.iconset>`, and then `iconutil` makes the .icns. The master is drawn at
// 1024 px and scaled down for each size.
//
// A dark body like the caption strip, and the mark on it: the camera and its A in white, the front reel in the click
// marker's red.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@main
struct MakeIcon {
    static let canvas: CGFloat = 1024
    static let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    static let bodyRadius: CGFloat = 186
    /// The mark's height, as a share of the body's.
    static let markShare: CGFloat = 0.62
    /// Each size, also drawn at @2x.
    static let sizes = [16, 32, 128, 256, 512]

    static func main() {
        guard CommandLine.arguments.count == 2 else {
            FileHandle.standardError.write(Data("usage: make-icon <out.iconset>\n".utf8))
            exit(2)
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("can't create \(output.path): \(error)\n".utf8))
            exit(1)
        }
        let master = drawMaster()
        for size in sizes {
            for (pixels, name) in [(size, "icon_\(size)x\(size).png"), (size * 2, "icon_\(size)x\(size)@2x.png")] {
                writePNG(scaled(master, to: pixels), to: output.appending(path: name))
            }
        }
        print("wrote \(sizes.count * 2) icons to \(output.path)")
    }

    static func drawMaster() -> CGImage {
        let context = makeContext(Int(canvas))
        // Top-left origin, like the mark's own coordinates.
        context.translateBy(x: 0, y: canvas)
        context.scaleBy(x: 1, y: -1)

        // The body: a vertical gradient from #2C2C2E at the top to #1C1C1E at the bottom.
        context.saveGState()
        context.addPath(CGPath(roundedRect: body, cornerWidth: bodyRadius, cornerHeight: bodyRadius, transform: nil))
        context.clip()
        let gradient = CGGradient(colorsSpace: sRGB, colors: [color(0x2C2C2E), color(0x1C1C1E)] as CFArray,
                                  locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: body.midX, y: body.minY),
                                   end: CGPoint(x: body.midX, y: body.maxY), options: [])
        context.restoreGState()

        let height = body.height * markShare
        let width = height * BrandMark.bounds.width / BrandMark.bounds.height
        let mark = CGRect(x: body.midX - width / 2, y: body.midY - height / 2, width: width, height: height)
        BrandMark.draw(in: context, rect: mark, ink: color(0xFFFFFF), frontReel: color(BrandMark.red))
        return context.makeImage()!
    }

    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    static func color(_ hex: UInt32) -> CGColor {
        CGColor(colorSpace: sRGB, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
                                               CGFloat(hex & 0xFF) / 255, 1])!
    }

    static func makeContext(_ pixels: Int) -> CGContext {
        CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    static func scaled(_ image: CGImage, to pixels: Int) -> CGImage {
        let context = makeContext(pixels)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        return context.makeImage()!
    }

    static func writePNG(_ image: CGImage, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { fatalError("can't write \(url.path)") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("can't write \(url.path)") }
    }
}
