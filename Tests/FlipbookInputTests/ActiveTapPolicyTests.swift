import CoreGraphics
import FlipbookCore
import FlipbookInput
import Testing

struct ActiveTapPolicyTests {
    func decide(_ type: CGEventType, keycode: Int64 = 0, flags: CGEventFlags = [], mode: RecordingMode = .hold,
                triggerDown: Bool = true, trigger: TriggerKey = .rightCommand) -> ActiveTapPolicy.Decision {
        ActiveTapPolicy.decide(type: type, keycode: keycode, flags: flags, mode: mode, triggerDown: triggerDown,
                               trigger: trigger)
    }

    @Test func holdClickStripsCommand() {
        #expect(decide(.leftMouseDown, flags: .maskCommand) == .stripModifier(.maskCommand))
    }

    @Test func holdScrollStripsCommand() {
        #expect(decide(.scrollWheel, flags: .maskCommand) == .stripModifier(.maskCommand))
    }

    @Test func rightOptionTriggerStripsOption() {
        #expect(decide(.leftMouseDown, flags: .maskAlternate, trigger: .rightOption) == .stripModifier(.maskAlternate))
    }

    @Test func handsFreeLeavesClicks() {
        #expect(decide(.leftMouseDown, flags: .maskCommand, mode: .handsFree) == .pass)
    }

    @Test func triggerEscCancels() {
        #expect(decide(.keyDown, keycode: 53, flags: .maskCommand, mode: .hold) == .consumeAsCancel)
        #expect(decide(.keyDown, keycode: 53, flags: .maskCommand, mode: .handsFree) == .consumeAsCancel)
    }

    @Test func plainEscPasses() {
        #expect(decide(.keyDown, keycode: 53, triggerDown: false) == .pass)
    }

    @Test func keysAreNeverStripped() {
        #expect(decide(.keyDown, keycode: 8, flags: .maskCommand) == .pass)
    }

    @Test func plainClickPasses() {
        #expect(decide(.leftMouseDown) == .pass)
    }

    @Test func ticksWhileNeeded() {
        #expect(GestureTicking.needsTicks(triggerDown: true, recording: false, lastRelease: nil, now: 10))
        #expect(GestureTicking.needsTicks(triggerDown: false, recording: true, lastRelease: nil, now: 10))
        #expect(GestureTicking.needsTicks(triggerDown: false, recording: false, lastRelease: 9.5, now: 10))
        #expect(!GestureTicking.needsTicks(triggerDown: false, recording: false, lastRelease: 9.0, now: 10))
        #expect(!GestureTicking.needsTicks(triggerDown: false, recording: false, lastRelease: nil, now: 10))
    }
}
