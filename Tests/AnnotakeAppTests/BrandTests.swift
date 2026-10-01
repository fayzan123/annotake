@testable import AnnotakeApp
import AppKit
import SwiftUI
import Testing

struct BrandTests {
    @Test func markBoundsMatchItsShapes() {
        let union = BrandMark.shapes.map(\.path.boundingBoxOfPath).reduce(CGRect.null) { $0.union($1) }
        #expect(close(union, BrandMark.bounds))
        // The A's feet sit on the baseline; the reels' tops are the top of the mark.
        #expect(abs(BrandMark.bounds.maxY) < 0.01)
    }

    @Test func onlyTheFrontReelIsAccentedAndItIsARing() {
        let reels = BrandMark.shapes.filter { $0.part == .frontReel }
        #expect(reels.count == 1)
        let reel = reels[0]
        let center = BrandMark.frontReelCenter
        #expect(!reel.path.contains(center, using: reel.evenOdd ? .evenOdd : .winding))
        let onRing = CGPoint(x: center.x + (BrandMark.reelRadius + BrandMark.reelHoleRadius) / 2, y: center.y)
        #expect(reel.path.contains(onRing, using: reel.evenOdd ? .evenOdd : .winding))
    }

    @Test func fittingKeepsProportionsAndCenters() {
        let fit = BrandMark.fitting(CGRect(x: 0, y: -200, width: 100, height: 200),
                                    into: CGRect(x: 0, y: 0, width: 400, height: 100))
        let mapped = CGRect(x: 0, y: -200, width: 100, height: 200).applying(fit)
        #expect(close(mapped, CGRect(x: 175, y: 0, width: 50, height: 100)))
    }

    @Test func svgPathReadsWhatTheBrandFilesUse() throws {
        let square = try SVGPath.parse("M0 0 L10 0 V10 H0 Z")
        #expect(close(square.boundingBoxOfPath, CGRect(x: 0, y: 0, width: 10, height: 10)))
        let arch = try SVGPath.parse("M0 0Q5 10 10 0Z")
        #expect(close(arch.boundingBoxOfPath, CGRect(x: 0, y: 0, width: 10, height: 5)))
        let negatives = try SVGPath.parse("M-1.5 -2L3-4Z")
        #expect(close(negatives.boundingBoxOfPath, CGRect(x: -1.5, y: -4, width: 4.5, height: 2)))
    }

    @Test func svgPathRejectsWhatItCannotRead() {
        #expect(throws: SVGPath.ParseError.self) { try SVGPath.parse("M0 0 A1 1 0 0 1 2 2") }
        #expect(throws: SVGPath.ParseError.self) { try SVGPath.parse("M0") }
        #expect(throws: SVGPath.ParseError.self) { try SVGPath.parse("5 5") }
    }

    @Test func wordmarkLettersFollowTheTripodOnItsBaseline() throws {
        let letters = try Wordmark.letters()
        // "nnotake" starts 6 units past the A's right foot (x 121); the k's ascender is its top, and the round letters
        // overshoot the baseline a little.
        #expect(close(letters.boundingBoxOfPath, CGRect(x: 127, y: -111.43, width: 505.06, height: 112.86), by: 0.05))
        #expect(close(try Wordmark.bounds(), CGRect(x: 0, y: -226.68, width: 632.06, height: 228.11), by: 0.05))
    }

    @MainActor @Test func everySettingsPageEndsInTheFooterAtTheTabsWidth() {
        let page = NSHostingView(rootView: SettingsPage { Color.clear.frame(width: 540, height: 100) })
        #expect(page.fittingSize.width == 540)
        // The bar, plus its divider.
        #expect(page.fittingSize.height >= 100 + SettingsFooter.barHeight)
        #expect(page.fittingSize.height <= 100 + SettingsFooter.barHeight + 1)
    }

    @Test func settingsFooterShowsTheVersion() {
        #expect(SettingsFooter.versionText(AppVersion(short: "0.2.0", build: "74")) == "Version 0.2.0 (74)")
    }

    @MainActor @Test func menuBarIconIsATemplateUntilRecording() {
        let idle = MenuBarIcon.image(recording: false)
        let recording = MenuBarIcon.image(recording: true)
        #expect(idle.isTemplate)
        #expect(!recording.isTemplate)
        #expect(idle.size == recording.size)
        #expect(idle.size.height == MenuBarIcon.height)
    }

    @MainActor @Test func recordingTurnsOnlyTheFrontReelRed() {
        let ring = CGPoint(x: BrandMark.frontReelCenter.x + (BrandMark.reelRadius + BrandMark.reelHoleRadius) / 2,
                           y: BrandMark.frontReelCenter.y)
        let body = CGPoint(x: BrandMark.bounds.minX + 60.5, y: -129.88)
        for (name, light) in [(NSAppearance.Name.darkAqua, false), (.aqua, true)] {
            let appearance = NSAppearance(named: name)!
            let recording = pixels(of: MenuBarIcon.image(recording: true), in: appearance)
            let reel = recording.color(at: ring), ink = recording.color(at: body)
            #expect(reel.red > 0.8 && reel.green < 0.5 && reel.blue < 0.5, "\(name): the reel is red")
            #expect(ink.alpha > 0.6 && abs(ink.red - ink.green) < 0.05, "\(name): the rest isn't tinted")
            #expect(light ? ink.red < 0.3 : ink.red > 0.6, "\(name): the rest takes the menu bar's color")
            let idle = pixels(of: MenuBarIcon.image(recording: false), in: appearance).color(at: ring)
            #expect(idle.alpha > 0.6 && abs(idle.red - idle.green) < 0.05, "\(name): idle, the reel is plain")
        }
    }
}

private func close(_ a: CGRect, _ b: CGRect, by tolerance: CGFloat = 0.01) -> Bool {
    abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance && abs(a.width - b.width) <= tolerance
        && abs(a.height - b.height) <= tolerance
}

/// An image drawn at 8× in an appearance, read back by logo coordinates.
private struct Pixels {
    let rep: NSBitmapImageRep
    let fit: CGAffineTransform
    let scale: CGFloat

    func color(at point: CGPoint) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let p = point.applying(fit)
        let color = rep.colorAt(x: Int(p.x * scale), y: Int(p.y * scale))?.usingColorSpace(.deviceRGB) ?? .clear
        return (color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent)
    }
}

@MainActor
private func pixels(of image: NSImage, in appearance: NSAppearance) -> Pixels {
    let scale: CGFloat = 8
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * scale),
                               pixelsHigh: Int(image.size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                               bitsPerPixel: 0)!
    rep.size = image.size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    appearance.performAsCurrentDrawingAppearance {
        image.draw(in: NSRect(origin: .zero, size: image.size))
    }
    NSGraphicsContext.restoreGraphicsState()
    let fit = BrandMark.fitting(BrandMark.bounds, into: CGRect(origin: .zero, size: image.size))
    return Pixels(rep: rep, fit: fit, scale: scale)
}
