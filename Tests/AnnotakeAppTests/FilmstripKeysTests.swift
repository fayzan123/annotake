import AppKit
@testable import AnnotakeApp
import Carbon.HIToolbox
import Testing

@MainActor
struct FilmstripKeysTests {
    static let title = "2026-10-11 at 09.30.00 · 10 frames"

    /// Frames 1–10, in a filmstrip narrower than they are, laid out.
    private func filmstrip(frames: Int = 10) -> FilmstripView {
        let view = FilmstripView(frame: CGRect(x: 0, y: 0, width: 600, height: FilmstripView.height))
        view.title = Self.title
        view.strip.tiles = (1...frames).map {
            FilmstripTile(frameIndex: $0, url: URL(fileURLWithPath: "/"), caption: "", image: nil, aspect: 1.32)
        }
        view.strip.selection = FilmstripSelection(frameIndices: Array(1...frames))
        view.layoutSubtreeIfNeeded()
        return view
    }

    private func press(_ keyCode: Int, on responder: NSResponder, repeat isARepeat: Bool = false) {
        responder.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                 windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                                                 isARepeat: isARepeat, keyCode: UInt16(keyCode))!)
    }

    private func click(_ strip: FilmstripStripView, at point: CGPoint) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: strip.convert(point, to: nil), modifierFlags: [],
                                           timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1,
                                           pressure: 1)!
            type == .leftMouseDown ? strip.mouseDown(with: event) : strip.mouseUp(with: event)
        }
    }

    @Test func arrowsMoveTheRingAndStopAtTheEnds() {
        let strip = filmstrip().strip
        #expect(strip.selection.current == 0)
        press(kVK_LeftArrow, on: strip)
        #expect(strip.selection.current == 0)
        for _ in 0..<12 { press(kVK_RightArrow, on: strip) }
        #expect(strip.selection.current == 9)
        press(kVK_LeftArrow, on: strip)
        #expect(strip.selection.current == 8)
    }

    @Test(arguments: [kVK_Delete, kVK_ForwardDelete])
    func deleteRemovesTheCurrentFrameAndRestoresIt(key: Int) {
        let strip = filmstrip().strip
        press(kVK_RightArrow, on: strip)
        press(key, on: strip)
        #expect(strip.selection.removed == [2])
        press(key, on: strip)
        #expect(strip.selection.removed == [])
    }

    @Test func holdingDeleteDoesNotFlipTheFrameBack() {
        let strip = filmstrip().strip
        press(kVK_Delete, on: strip)
        press(kVK_Delete, on: strip, repeat: true)
        #expect(strip.selection.removed == [1])
    }

    @Test func deleteKeepsTheLastFrame() {
        let strip = filmstrip(frames: 2).strip
        press(kVK_Delete, on: strip)
        press(kVK_RightArrow, on: strip)
        press(kVK_Delete, on: strip)
        #expect(strip.selection.removed == [1])
    }

    @Test func aClickMovesTheRingWithoutRemoving() {
        let strip = filmstrip().strip
        let third = strip.tileRects()[2]
        click(strip, at: CGPoint(x: third.midX, y: third.midY))
        #expect(strip.selection.current == 2)
        #expect(strip.selection.removed == [])
    }

    @Test func theStripScrollsToKeepTheRingInView() {
        let view = filmstrip()
        for _ in 0..<6 { press(kVK_RightArrow, on: view.strip) }
        #expect(view.scrollView.contentView.bounds.minX > 0)
        #expect(view.scrollView.contentView.bounds.contains(view.strip.tileRects()[6]))
        for _ in 0..<6 { press(kVK_LeftArrow, on: view.strip) }
        #expect(view.scrollView.contentView.bounds.minX == 0)
    }

    @Test func theHeaderCountsTheFramesToRemove() {
        let view = filmstrip()
        #expect(view.heading == Self.title)
        press(kVK_Delete, on: view.strip)
        press(kVK_RightArrow, on: view.strip)
        press(kVK_Delete, on: view.strip)
        #expect(view.heading == "2026-10-11 at 09.30.00 · 10 frames · 2 to remove")
    }

    @Test func keysGoToTheStripWhenTheFilmstripOpens() {
        let view = filmstrip()
        let panel = FilmstripController.makePanel(view, frame: view.frame)
        #expect(panel.firstResponder === view.strip)
    }

    @Test(arguments: [kVK_Return, kVK_ANSI_KeypadEnter, kVK_Escape])
    func returnAndEscapeCloseTheFilmstrip(key: Int) {
        let view = filmstrip()
        let panel = FilmstripController.makePanel(view, frame: view.frame)
        var closed = 0
        panel.onClose = { closed += 1 }
        press(key, on: view.strip)
        #expect(closed == 1)
    }
}
