import FlipbookCore
import Foundation
import Testing

struct GestureRecognizerTests {
    func config(holdThreshold: TimeInterval? = nil, holdReveal: TimeInterval? = nil,
                doubleTapWindow: TimeInterval? = nil) -> GestureConfig {
        var config = GestureConfig()
        if let holdThreshold { config.holdThreshold = holdThreshold }
        if let holdReveal { config.holdReveal = holdReveal }
        if let doubleTapWindow { config.doubleTapWindow = doubleTapWindow }
        return config
    }

    /// Double-tap at 0 / 0.1 / 0.3, released at 0.35: recording hands-free.
    func startedHandsFree() -> GestureRecognizer {
        var recognizer = GestureRecognizer()
        var events = recognizer.handle(.triggerDown(at: 0))
        events += recognizer.handle(.triggerUp(at: 0.1))
        events += recognizer.handle(.triggerDown(at: 0.3))
        events += recognizer.handle(.triggerUp(at: 0.35))
        #expect(events == [.startHandsFree])
        #expect(recognizer.recording == .handsFree)
        return recognizer
    }

    @Test func holdStartsAndStops() {
        var r = GestureRecognizer()
        #expect(r.handle(.triggerDown(at: 0)) == [])
        #expect(r.tick(now: 0.249) == [])
        #expect(r.tick(now: 0.25) == [.startHold])
        #expect(r.recording == .hold)
        #expect(r.tick(now: 0.79) == [])
        #expect(r.tick(now: 0.8) == [.revealHold])
        #expect(r.handle(.triggerUp(at: 2.0)) == [.stopHold])
        #expect(r.recording == nil)
    }

    @Test func lateReleaseStillStartsHold() {
        var r = GestureRecognizer()
        var events = r.handle(.triggerDown(at: 0))
        events += r.handle(.triggerUp(at: 0.4))
        #expect(events == [.startHold, .stopHold])
        #expect(r.recording == nil)
    }

    @Test func singleTapDoesNothing() {
        var r = GestureRecognizer()
        #expect(r.handle(.triggerDown(at: 0)) == [])
        #expect(r.handle(.triggerUp(at: 0.1)) == [])
        #expect(r.tick(now: 0.5) == [])
        #expect(r.recording == nil)
    }

    @Test func doubleTapStartsHandsFree() {
        var r = GestureRecognizer()
        #expect(r.handle(.triggerDown(at: 0)) == [])
        #expect(r.handle(.triggerUp(at: 0.1)) == [])
        #expect(r.handle(.triggerDown(at: 0.3)) == [.startHandsFree])
        #expect(r.handle(.triggerUp(at: 0.35)) == [])
        #expect(r.recording == .handsFree)
    }

    @Test func doubleTapWindowIsInclusive() {
        var r = GestureRecognizer(config: config(doubleTapWindow: 0.25))
        #expect(r.handle(.triggerDown(at: 0)) == [])
        #expect(r.handle(.triggerUp(at: 0.125)) == [])
        #expect(r.handle(.triggerDown(at: 0.375)) == [.startHandsFree])
    }

    @Test func slowSecondPressIsNotDoubleTap() {
        var r = GestureRecognizer(config: config(doubleTapWindow: 0.25))
        #expect(r.handle(.triggerDown(at: 0)) == [])
        #expect(r.handle(.triggerUp(at: 0.125)) == [])
        #expect(r.handle(.triggerDown(at: 0.5)) == [])
        #expect(r.tick(now: 0.75) == [.startHold])
    }

    @Test func doubleTapStopsHandsFree() {
        var r = startedHandsFree()
        #expect(r.handle(.triggerDown(at: 5.0)) == [])
        #expect(r.handle(.triggerUp(at: 5.1)) == [])
        #expect(r.handle(.triggerDown(at: 5.3)) == [.stopHandsFree])
        #expect(r.recording == nil)
        #expect(r.handle(.triggerUp(at: 5.35)) == [])
    }

    @Test func singleTapDuringHandsFreeIgnored() {
        var r = startedHandsFree()
        #expect(r.handle(.triggerDown(at: 5.0)) == [])
        #expect(r.handle(.triggerUp(at: 5.1)) == [])
        #expect(r.tick(now: 5.6) == [])
        #expect(r.recording == .handsFree)
    }

    @Test func chordInIdleNeverStarts() {
        var r = GestureRecognizer()
        #expect(r.handle(.triggerDown(at: 0)) == [])
        #expect(r.handle(.otherKeyDown(at: 0.1, isEscape: false)) == [])
        #expect(r.tick(now: 1.0) == [])
        #expect(r.handle(.triggerUp(at: 1.1)) == [])
        #expect(r.recording == nil)
    }

    @Test func commandClickInIdleNeverStarts() {
        var r = GestureRecognizer()
        #expect(r.handle(.triggerDown(at: 0)) == [])
        #expect(r.handle(.mouseDown(at: 0.1)) == [])
        #expect(r.tick(now: 1.0) == [])
        #expect(r.recording == nil)
    }

    @Test func shortcutDuringHandsFreeIsNotATap() {
        var r = startedHandsFree()
        var events = r.handle(.triggerDown(at: 5.0))
        events += r.handle(.otherKeyDown(at: 5.05, isEscape: false))
        events += r.handle(.triggerUp(at: 5.1))
        events += r.handle(.triggerDown(at: 5.2))
        events += r.handle(.triggerUp(at: 5.25))
        events += r.tick(now: 6)
        #expect(events == [])
        #expect(r.recording == .handsFree)
    }

    @Test func escWhileHoldingCancels() {
        var r = GestureRecognizer()
        #expect(r.handle(.triggerDown(at: 0)) == [])
        #expect(r.tick(now: 0.3) == [.startHold])
        #expect(r.handle(.otherKeyDown(at: 1.0, isEscape: true)) == [.revealHold, .cancel])
        #expect(r.recording == nil)
        #expect(r.handle(.triggerUp(at: 1.2)) == [])
    }

    @Test func escWithTriggerDuringHandsFreeCancels() {
        var r = startedHandsFree()
        #expect(r.handle(.triggerDown(at: 5.0)) == [])
        #expect(r.handle(.otherKeyDown(at: 5.1, isEscape: true)) == [.cancel])
        #expect(r.recording == nil)
    }

    @Test func plainEscDuringHandsFreePassesThrough() {
        var r = startedHandsFree()
        #expect(r.handle(.otherKeyDown(at: 5.0, isEscape: true)) == [])
        #expect(r.recording == .handsFree)
    }

    @Test func startingPressHeldLongDoesNotStop() {
        var r = GestureRecognizer()
        #expect(r.handle(.triggerDown(at: 0)) == [])
        #expect(r.handle(.triggerUp(at: 0.1)) == [])
        #expect(r.handle(.triggerDown(at: 0.3)) == [.startHandsFree])
        #expect(r.handle(.triggerUp(at: 2.0)) == [])
        #expect(r.recording == .handsFree)
    }

    @Test func tapThenOtherKeyIsNotDoubleTap() {
        var r = GestureRecognizer()
        var events = r.handle(.triggerDown(at: 0))
        events += r.handle(.triggerUp(at: 0.1))
        events += r.handle(.otherKeyDown(at: 0.15, isEscape: false))
        events += r.handle(.triggerDown(at: 0.25))
        #expect(events == [])
        #expect(r.recording == nil)
    }

    @Test func resetReturnsToIdle() {
        var r = GestureRecognizer()
        #expect(r.handle(.triggerDown(at: 0)) == [])
        #expect(r.tick(now: 0.3) == [.startHold])
        r.reset()
        #expect(r.recording == nil)
        #expect(r.handle(.triggerUp(at: 1.0)) == [])
        #expect(r.recording == nil)
    }

    @Test func configurableThresholds() {
        var r = GestureRecognizer(config: config(holdThreshold: 0.4))
        #expect(r.handle(.triggerDown(at: 0)) == [])
        #expect(r.tick(now: 0.3) == [])
        #expect(r.tick(now: 0.4) == [.startHold])
    }

    @Test func shortcutBeforeRevealDiscards() {
        var r = GestureRecognizer()
        #expect(r.handle(.triggerDown(at: 0)) == [])
        #expect(r.tick(now: 0.3) == [.startHold])
        #expect(r.handle(.otherKeyDown(at: 0.4, isEscape: false)) == [.discardHold])
        #expect(r.recording == nil)
        #expect(r.handle(.triggerUp(at: 0.5)) == [])
        #expect(r.tick(now: 1.0) == [])
    }

    @Test func shortcutWithoutTicksDiscards() {
        var r = GestureRecognizer()
        var events = r.handle(.triggerDown(at: 0))
        events += r.handle(.otherKeyDown(at: 0.4, isEscape: false))
        #expect(events == [.startHold, .discardHold])
        #expect(r.recording == nil)
    }

    @Test func repeatedShortcutAfterDiscardStaysQuiet() {
        var r = GestureRecognizer()
        #expect(r.handle(.triggerDown(at: 0)) == [])
        #expect(r.tick(now: 0.3) == [.startHold])
        #expect(r.handle(.otherKeyDown(at: 0.4, isEscape: false)) == [.discardHold])
        #expect(r.handle(.otherKeyDown(at: 0.9, isEscape: false)) == [])
        #expect(r.tick(now: 1.5) == [])
        #expect(r.handle(.triggerUp(at: 1.6)) == [])
        #expect(r.recording == nil)
    }

    @Test func shortcutAfterRevealIsPartOfRecording() {
        var r = GestureRecognizer()
        #expect(r.handle(.triggerDown(at: 0)) == [])
        #expect(r.tick(now: 1.0) == [.startHold, .revealHold])
        #expect(r.handle(.otherKeyDown(at: 1.2, isEscape: false)) == [])
        #expect(r.recording == .hold)
        #expect(r.handle(.triggerUp(at: 2.0)) == [.stopHold])
    }

    @Test func clickBeforeRevealKeepsRecording() {
        var r = GestureRecognizer()
        #expect(r.handle(.triggerDown(at: 0)) == [])
        #expect(r.tick(now: 0.3) == [.startHold])
        #expect(r.handle(.mouseDown(at: 0.4)) == [])
        #expect(r.handle(.otherKeyDown(at: 0.5, isEscape: false)) == [])
        #expect(r.recording == .hold)
        #expect(r.tick(now: 1.0) == [.revealHold])
        #expect(r.handle(.triggerUp(at: 2.0)) == [.stopHold])
    }

    @Test func releaseBeforeRevealStops() {
        var r = GestureRecognizer()
        #expect(r.handle(.triggerDown(at: 0)) == [])
        #expect(r.tick(now: 0.3) == [.startHold])
        #expect(r.handle(.triggerUp(at: 0.6)) == [.stopHold])
        #expect(r.recording == nil)
    }

    @Test func escBeforeRevealCancels() {
        var r = GestureRecognizer()
        #expect(r.handle(.triggerDown(at: 0)) == [])
        #expect(r.tick(now: 0.3) == [.startHold])
        #expect(r.handle(.otherKeyDown(at: 0.5, isEscape: true)) == [.cancel])
        #expect(r.recording == nil)
    }

    @Test func revealThresholdIsInclusive() {
        var r = GestureRecognizer(config: config(holdReveal: 0.75))
        #expect(r.handle(.triggerDown(at: 0)) == [])
        #expect(r.tick(now: 0.25) == [.startHold])
        #expect(r.handle(.otherKeyDown(at: 0.75, isEscape: false)) == [.revealHold])
        #expect(r.recording == .hold)
    }

    @Test func handsFreeHasNoReveal() {
        var r = GestureRecognizer()
        #expect(r.handle(.triggerDown(at: 0)) == [])
        #expect(r.handle(.triggerUp(at: 0.1)) == [])
        #expect(r.handle(.triggerDown(at: 0.3)) == [.startHandsFree])
        #expect(r.tick(now: 2.0) == [])
        #expect(r.handle(.otherKeyDown(at: 2.1, isEscape: false)) == [])
        #expect(r.recording == .handsFree)
    }
}
