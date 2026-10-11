import AppKit
@testable import AnnotakeApp
import Carbon.HIToolbox
import Testing

@MainActor
struct FrameViewerTests {
    /// Frames 1–5, 3:2, in a filmstrip, and its full-screen view on a 1440 × 900 screen.
    private func viewer() -> (filmstrip: FilmstripView, viewer: FrameViewerView) {
        let filmstrip = FilmstripView(frame: CGRect(x: 0, y: 0, width: 600, height: FilmstripView.height))
        filmstrip.strip.tiles = (1...5).map {
            FilmstripTile(frameIndex: $0, url: URL(fileURLWithPath: "/"), caption: "\($0)/5", image: nil, aspect: 1.5)
        }
        filmstrip.strip.selection = FilmstripSelection(frameIndices: Array(1...5))
        filmstrip.layoutSubtreeIfNeeded()
        let viewer = FrameViewerView(strip: filmstrip.strip)
        viewer.frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        return (filmstrip, viewer)
    }

    private func press(_ keyCode: Int, on responder: NSResponder) {
        responder.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                 windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                                                 isARepeat: false, keyCode: UInt16(keyCode))!)
    }

    private func click(_ view: NSView, at point: CGPoint) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [],
                                           timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1,
                                           pressure: 1)!
            type == .leftMouseDown ? view.mouseDown(with: event) : view.mouseUp(with: event)
        }
    }

    private func middle(_ rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX, y: rect.midY)
    }

    @Test func arrowsFlipThroughTheFramesAndTheRingFollows() {
        let (filmstrip, viewer) = viewer()
        press(kVK_RightArrow, on: viewer)
        press(kVK_RightArrow, on: viewer)
        #expect(filmstrip.strip.selection.current == 2)
        press(kVK_LeftArrow, on: viewer)
        #expect(filmstrip.strip.selection.current == 1)
    }

    @Test func deleteRemovesTheFrameOnScreenAndRestoresIt() {
        let (filmstrip, viewer) = viewer()
        press(kVK_RightArrow, on: viewer)
        press(kVK_Delete, on: viewer)
        #expect(filmstrip.strip.selection.removed == [2])
        press(kVK_Delete, on: viewer)
        #expect(filmstrip.strip.selection.removed == [])
    }

    @Test(arguments: [kVK_Escape, kVK_Space])
    func escapeAndSpaceGoBack(key: Int) {
        let (_, viewer) = viewer()
        var back = 0
        var done = 0
        viewer.onBack = { back += 1 }
        viewer.onDone = { done += 1 }
        press(key, on: viewer)
        #expect(back == 1)
        #expect(done == 0)
    }

    @Test(arguments: [kVK_Return, kVK_ANSI_KeypadEnter])
    func returnAppliesTheRemovals(key: Int) {
        let (_, viewer) = viewer()
        var back = 0
        var done = 0
        viewer.onBack = { back += 1 }
        viewer.onDone = { done += 1 }
        press(key, on: viewer)
        #expect(done == 1)
        #expect(back == 0)
    }

    @Test func theSideButtonsFlip() {
        let (filmstrip, viewer) = viewer()
        click(viewer, at: middle(viewer.nextRect))
        click(viewer, at: middle(viewer.nextRect))
        #expect(filmstrip.strip.selection.current == 2)
        click(viewer, at: middle(viewer.previousRect))
        #expect(filmstrip.strip.selection.current == 1)
    }

    @Test func theCrossAndTheBackdropGoBack() {
        let (_, viewer) = viewer()
        var back = 0
        viewer.onBack = { back += 1 }
        click(viewer, at: middle(viewer.closeRect))
        #expect(back == 1)
        click(viewer, at: CGPoint(x: viewer.bounds.midX, y: viewer.bounds.maxY - 8))
        #expect(back == 2)
    }

    @Test func aClickOnTheFrameItselfDoesNothing() {
        let (filmstrip, viewer) = viewer()
        var back = 0
        var done = 0
        viewer.onBack = { back += 1 }
        viewer.onDone = { done += 1 }
        click(viewer, at: CGPoint(x: viewer.imageRect.minX + 20, y: viewer.imageRect.minY + 20))
        #expect(back == 0)
        #expect(done == 0)
        #expect(filmstrip.strip.selection.current == 0)
        #expect(filmstrip.strip.selection.removed == [])
    }

    @Test func aRemovedFrameComesBackFromRestore() {
        let (filmstrip, viewer) = viewer()
        press(kVK_Delete, on: viewer)
        click(viewer, at: middle(viewer.restoreRect))
        #expect(filmstrip.strip.selection.removed == [])
    }

    @Test func theFrameIsAsLargeAsFitsAtItsShape() {
        let (_, viewer) = viewer()
        let rect = viewer.imageRect
        #expect(abs(rect.width / rect.height - 1.5) < 0.01)
        #expect(rect.minX >= FrameViewerView.sideRoom && rect.maxX <= viewer.bounds.maxX - FrameViewerView.sideRoom)
        #expect(rect.minY >= FrameViewerView.topRoom && rect.maxY <= viewer.bounds.maxY - FrameViewerView.bottomRoom)
        // Height is the limit on a 1440 × 900 screen, so the frame fills it.
        #expect(rect.height == viewer.bounds.height - FrameViewerView.topRoom - FrameViewerView.bottomRoom)
    }

    @Test func theViewerTakesTheKeysAboveTheFilmstrip() {
        let (filmstrip, viewer) = viewer()
        let panel = FilmstripController.makeViewerPanel(viewer, frame: viewer.frame)
        #expect(panel.firstResponder === viewer)
        let filmstripPanel = FilmstripController.makePanel(filmstrip, frame: filmstrip.frame)
        #expect(panel.level.rawValue > filmstripPanel.level.rawValue)
    }
}
