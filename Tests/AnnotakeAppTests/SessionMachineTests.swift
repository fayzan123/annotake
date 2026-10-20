@testable import AnnotakeApp
import AnnotakeCore
import Foundation
import Testing

struct SessionMachineTests {
    typealias Effect = SessionMachine.Effect

    func save(_ id: Int) -> [Effect] {
        [.stopEngine, .playStop, .hidePill, .showCard(captureID: id)]
    }

    /// A hold started at 0.25 and revealed at 0.8.
    func revealedHold(sounds: Bool = true) -> SessionMachine {
        var machine = SessionMachine(sounds: sounds)
        _ = machine.handle(.gesture(.startHold), at: 0.25)
        _ = machine.handle(.gesture(.revealHold), at: 0.8)
        return machine
    }

    func handsFree(at time: TimeInterval = 0) -> SessionMachine {
        var machine = SessionMachine(sounds: true)
        _ = machine.handle(.gesture(.startHandsFree), at: time)
        return machine
    }

    @Test func holdStartsSilently() {
        var machine = SessionMachine(sounds: true)
        #expect(machine.handle(.gesture(.startHold), at: 0.25) == [.startEngine(.hold)])
        #expect(machine.state == .recording(.hold, revealed: false, startedAt: 0.25))
    }

    @Test func revealShowsPill() {
        var machine = SessionMachine(sounds: true)
        _ = machine.handle(.gesture(.startHold), at: 0.25)
        #expect(machine.handle(.gesture(.revealHold), at: 0.8) == [.showPill(.hold), .playStart])
        #expect(machine.state == .recording(.hold, revealed: true, startedAt: 0.25))
    }

    @Test func releaseBeforeRevealDiscards() {
        var machine = SessionMachine(sounds: true)
        _ = machine.handle(.gesture(.startHold), at: 0.25)
        #expect(machine.handle(.gesture(.stopHold), at: 0.7) == [.discardEngine])
        #expect(machine.state == .idle)
    }

    @Test func releaseAfterRevealSaves() {
        var machine = revealedHold()
        #expect(machine.handle(.gesture(.stopHold), at: 3.0) == save(1))
        #expect(machine.state == .idle)
    }

    @Test func shortcutDiscards() {
        var machine = SessionMachine(sounds: true)
        _ = machine.handle(.gesture(.startHold), at: 0.25)
        #expect(machine.handle(.gesture(.discardHold), at: 0.5) == [.discardEngine])
        #expect(machine.state == .idle)
    }

    @Test func cancelDiscards() {
        var hold = revealedHold()
        #expect(hold.handle(.gesture(.cancel), at: 2) == [.discardEngine, .hidePill])
        #expect(hold.state == .idle)
        var free = handsFree()
        #expect(free.handle(.gesture(.cancel), at: 2) == [.discardEngine, .hidePill])
        #expect(free.state == .idle)
    }

    @Test func handsFreeShowsPillAtOnce() {
        var machine = SessionMachine(sounds: true)
        #expect(machine.handle(.gesture(.startHandsFree), at: 0) == [.startEngine(.handsFree), .showPill(.handsFree), .playStart])
        #expect(machine.state == .recording(.handsFree, revealed: true, startedAt: 0))
    }

    @Test func shortHandsFreeDiscarded() {
        var short = handsFree()
        #expect(short.handle(.gesture(.stopHandsFree), at: 0.4) == [.discardEngine, .hidePill])
        #expect(short.state == .idle)
        var long = handsFree()
        #expect(long.handle(.gesture(.stopHandsFree), at: 0.6) == save(1))
        #expect(long.state == .idle)
    }

    @Test func menuStartIsHandsFree() {
        var machine = SessionMachine(sounds: true)
        #expect(machine.handle(.menuStart, at: 0) == [.startEngine(.handsFree), .showPill(.handsFree), .playStart])
        #expect(machine.handle(.menuStop, at: 5) == save(1) + [.resetGestures])
        #expect(machine.state == .idle)
    }

    @Test func handsFreeAutoStopsWithoutFrames() {
        var machine = handsFree()
        #expect(machine.handle(.elapsed, at: 299) == [])
        #expect(machine.handle(.elapsed, at: 300) == save(1) + [.resetGestures])
        #expect(machine.state == .idle)
    }

    @Test func soundsOff() {
        var machine = SessionMachine(sounds: false)
        _ = machine.handle(.gesture(.startHold), at: 0.25)
        #expect(machine.handle(.gesture(.revealHold), at: 0.8) == [.showPill(.hold)])
        #expect(machine.handle(.gesture(.stopHold), at: 3) == [.stopEngine, .hidePill, .showCard(captureID: 1)])
    }

    @Test func permissionFailureShowsMessage() {
        var machine = SessionMachine(sounds: true)
        _ = machine.handle(.gesture(.startHold), at: 0.25)
        #expect(machine.handle(.engineFailed(.screenRecordingPermission), at: 0.3)
                == [.hidePill, .showMessage(.screenRecordingNeeded), .resetGestures])
        #expect(machine.state == .idle)
    }

    @Test func saveLocationFailureShowsMessage() {
        var machine = handsFree()
        #expect(machine.handle(.engineFailed(.saveLocationUnavailable), at: 0.1)
                == [.hidePill, .showMessage(.cannotSave), .resetGestures])
        #expect(machine.state == .idle)
    }

    @Test func fallbackNoteShownWithPill() {
        let note = "Window not found — recording your screen"
        var free = handsFree()
        #expect(free.handle(.engineStarted(note: note), at: 0.1) == [.showMessage(.note(note))])

        var hold = SessionMachine(sounds: true)
        _ = hold.handle(.gesture(.startHold), at: 0.25)
        #expect(hold.handle(.engineStarted(note: note), at: 0.3) == [])
        #expect(hold.handle(.gesture(.revealHold), at: 0.8) == [.showPill(.hold), .playStart, .showMessage(.note(note))])
    }

    @Test func streamEndSavesWhatWasCaptured() {
        var revealed = revealedHold()
        #expect(revealed.handle(.streamEnded, at: 2) == save(1) + [.resetGestures])
        #expect(revealed.state == .idle)

        var unrevealed = SessionMachine(sounds: true)
        _ = unrevealed.handle(.gesture(.startHold), at: 0.25)
        #expect(unrevealed.handle(.streamEnded, at: 0.5) == [.discardEngine, .resetGestures])
        #expect(unrevealed.state == .idle)
    }

    @Test func newRecordingWhileSaving() {
        var machine = revealedHold()
        #expect(machine.handle(.gesture(.stopHold), at: 3) == save(1))
        #expect(machine.handle(.gesture(.startHold), at: 3.3) == [.startEngine(.hold)])
        _ = machine.handle(.gesture(.revealHold), at: 3.9)
        #expect(machine.handle(.gesture(.stopHold), at: 5) == save(2))
        #expect(machine.handle(.exported(captureID: 1, success: true), at: 5.1) == [.completeCard(captureID: 1)])
        #expect(machine.handle(.exported(captureID: 2, success: false), at: 5.2) == [.failCard(captureID: 2)])
    }

    @Test func idleIgnoresStops() {
        var machine = SessionMachine(sounds: true)
        #expect(machine.handle(.gesture(.stopHold), at: 1) == [])
        #expect(machine.state == .idle)
    }

    /// A recording is one from its start, before a hold's reveal too, as the menu's Stop Recording has always shown.
    @Test func recordingIsRecordingFromItsStart() {
        var hold = SessionMachine(sounds: true)
        _ = hold.handle(.gesture(.startHold), at: 0.25)
        #expect(hold.state.isRecording)
        _ = hold.handle(.gesture(.revealHold), at: 0.8)
        #expect(hold.state.isRecording)
        #expect(handsFree().state.isRecording)
        _ = hold.handle(.gesture(.stopHold), at: 3)
        #expect(!hold.state.isRecording)
    }

    // MARK: - Before each input

    /// SessionController prepares the machine before every input with the Sounds setting.
    @Test func preparedWithSoundsOffNothingPlays() {
        var machine = SessionMachine(sounds: true)
        machine.prepare(sounds: false)
        _ = machine.handle(.gesture(.startHold), at: 0.25)
        #expect(machine.handle(.gesture(.revealHold), at: 0.8) == [.showPill(.hold)])
        #expect(machine.handle(.gesture(.stopHold), at: 3) == [.stopEngine, .hidePill, .showCard(captureID: 1)])
    }

    /// Nothing under way changes: a recording keeps the sounds it started with.
    @Test func preparingChangesNoRecordingUnderWay() {
        var hold = revealedHold()
        hold.prepare(sounds: false)
        #expect(hold.handle(.gesture(.stopHold), at: 3) == save(1))
        var free = handsFree()
        free.prepare(sounds: false)
        #expect(free.handle(.menuStop, at: 5) == save(1) + [.resetGestures])
    }

    /// The email is optional: with or without an address, a hold records (email list design §13).
    @Test func aHoldRecordsWithoutAnAddress() {
        var machine = SessionMachine(sounds: true)
        #expect(machine.handle(.gesture(.startHold), at: 0.25) == [.startEngine(.hold)])
        #expect(machine.handle(.gesture(.revealHold), at: 0.8) == [.showPill(.hold), .playStart])
    }

    /// Only SessionController's line prepares the machine, and no test builds the controller: a hold there would start
    /// the screen recording engine. Without the line, a Sounds change made while idle would never reach the machine.
    @Test func theControllerPreparesEachInput() throws {
        let lines = try PillTextTests.sourceLines("Sources/AnnotakeApp/SessionController.swift")
        let handle = lines.firstIndex { $0.hasPrefix("func handle(_ input: SessionMachine.Input") }
        let start = try #require(handle, "SessionController declares handle(_:at:)")
        let call = "machine.prepare(sounds: settingsStore.settings.sounds)"
        let prepare = lines[start...].firstIndex(of: call)
        let effects = lines[start...].firstIndex(of: "for effect in machine.handle(input, at: time) {")
        let prepared = try #require(prepare, "handle(_:at:) prepares the machine")
        let handled = try #require(effects, "handle(_:at:) hands the input to the machine")
        #expect(prepared < handled, "the machine is prepared before it handles the input")
    }
}
