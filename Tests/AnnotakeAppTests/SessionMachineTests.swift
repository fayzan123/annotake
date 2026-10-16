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

    // MARK: - Without an email address (email list design §3.2)

    /// No address is saved yet, so nothing starts recording.
    func withoutEmail() -> SessionMachine {
        SessionMachine(sounds: true, emailNeeded: true)
    }

    /// A hold started at 0.25 while no address is saved.
    func refusedHold() -> SessionMachine {
        var machine = withoutEmail()
        _ = machine.handle(.gesture(.startHold), at: 0.25)
        return machine
    }

    /// Every test above runs with this default, so every recording rule stands unchanged while an address is saved.
    @Test func emailIsNotNeededByDefault() {
        #expect(!SessionMachine(sounds: true).emailNeeded)
    }

    /// The message waits for the reveal, as the pill does. Letting go hides nothing: the message stays its own time, so
    /// its Open can still be clicked.
    @Test func holdWithoutEmailShowsTheMessageAtTheReveal() {
        var machine = withoutEmail()
        #expect(machine.handle(.gesture(.startHold), at: 0.25) == [])
        #expect(machine.state == .refusedHold)
        #expect(machine.handle(.gesture(.revealHold), at: 0.8) == [.showMessage(.emailNeeded)])
        #expect(machine.state == .refusedHold)
        #expect(machine.handle(.gesture(.stopHold), at: 3) == [])
        #expect(machine.state == .idle)
    }

    /// Review Focus 2: a Right ⌘ shortcut such as ⌘C shows no message and starts nothing. The ⌘C itself reaches the
    /// app, as in any hold.
    @Test func shortcutWithoutEmailShowsNothing() {
        var machine = withoutEmail()
        #expect(machine.handle(.gesture(.startHold), at: 0.25) == [])
        #expect(machine.handle(.gesture(.discardHold), at: 0.5) == [])
        #expect(machine.state == .idle)
    }

    /// A hold let go before the reveal shows nothing, as it saves nothing while an address is saved.
    @Test func shortHoldWithoutEmailShowsNothing() {
        var machine = refusedHold()
        #expect(machine.handle(.gesture(.stopHold), at: 0.7) == [])
        #expect(machine.state == .idle)
    }

    @Test func cancelEndsARefusedHold() {
        var unrevealed = refusedHold()
        #expect(unrevealed.handle(.gesture(.cancel), at: 0.5) == [])
        #expect(unrevealed.state == .idle)
        var revealed = refusedHold()
        _ = revealed.handle(.gesture(.revealHold), at: 0.8)
        #expect(revealed.handle(.gesture(.cancel), at: 2) == [])
        #expect(revealed.state == .idle)
    }

    /// A double-tap is never a shortcut, so the message shows at once, and the gestures reset, ending the hands-free
    /// recording InputMonitor began.
    @Test func handsFreeWithoutEmailShowsTheMessageAtOnce() {
        var machine = withoutEmail()
        #expect(machine.handle(.gesture(.startHandsFree), at: 0) == [.showMessage(.emailNeeded), .resetGestures])
        #expect(machine.state == .idle)
    }

    /// The menu's Start, the same way.
    @Test func menuStartWithoutEmailShowsTheMessageAtOnce() {
        var machine = withoutEmail()
        #expect(machine.handle(.menuStart, at: 0) == [.showMessage(.emailNeeded), .resetGestures])
        #expect(machine.state == .idle)
    }

    /// A hold never sends a double-tap, but the menu can be clicked mid-hold, and it offers Start Recording, since
    /// nothing records. Either start is refused as when idle, and ends the refused hold with the gestures reset, so
    /// nothing waits on a hold InputMonitor no longer has. Stop, which the menu doesn't offer then, changes nothing.
    @Test func startsDuringARefusedHoldAreRefusedAsWhenIdle() {
        var menu = refusedHold()
        #expect(menu.handle(.menuStart, at: 0.5) == [.showMessage(.emailNeeded), .resetGestures])
        #expect(menu.state == .idle)
        var revealed = refusedHold()
        _ = revealed.handle(.gesture(.revealHold), at: 0.8)
        #expect(revealed.handle(.menuStart, at: 1) == [.showMessage(.emailNeeded), .resetGestures])
        #expect(revealed.state == .idle)
        var tapped = refusedHold()
        #expect(tapped.handle(.gesture(.startHandsFree), at: 0.5) == [.showMessage(.emailNeeded), .resetGestures])
        #expect(tapped.state == .idle)
        var stop = refusedHold()
        #expect(stop.handle(.menuStop, at: 0.5) == [])
        #expect(stop.state == .refusedHold)
    }

    /// Nothing records in a refused hold, so nothing else applies, and a stray engine report leaves no note for the
    /// reveal.
    @Test func refusedHoldIgnoresEverythingElse() {
        var machine = refusedHold()
        let note = "Window not found — recording your screen"
        let inputs: [SessionMachine.Input] = [
            .gesture(.startHold), .gesture(.stopHandsFree), .elapsed, .engineStarted(note: nil),
            .engineStarted(note: note), .engineFailed(.screenRecordingPermission), .streamEnded, .menuStop,
        ]
        for input in inputs {
            #expect(machine.handle(input, at: 0.5) == [], "\(input)")
            #expect(machine.state == .refusedHold, "\(input)")
        }
        #expect(machine.handle(.gesture(.revealHold), at: 0.8) == [.showMessage(.emailNeeded)])
    }

    /// The site refused the address while a capture was saving: the next hold is refused, and the capture's card still
    /// finishes.
    @Test func cardsFinishDuringARefusedHold() {
        var machine = revealedHold()
        #expect(machine.handle(.gesture(.stopHold), at: 3) == save(1))
        machine.emailNeeded = true
        #expect(machine.handle(.gesture(.startHold), at: 3.3) == [])
        #expect(machine.handle(.exported(captureID: 1, success: true), at: 3.4) == [.completeCard(captureID: 1)])
        #expect(machine.state == .refusedHold)
        #expect(machine.handle(.gesture(.revealHold), at: 3.85) == [.showMessage(.emailNeeded)])
    }

    /// SessionController.isRecording, which names the menu's Start or Stop Recording and decides what clicking it
    /// sends: false all through a refused hold, so the menu offers Start, and Start is refused.
    @Test func refusedHoldIsNotRecording() {
        var machine = withoutEmail()
        #expect(!machine.state.isRecording)
        _ = machine.handle(.gesture(.startHold), at: 0.25)
        #expect(!machine.state.isRecording)
        _ = machine.handle(.gesture(.revealHold), at: 0.8)
        #expect(!machine.state.isRecording)
        _ = machine.handle(.gesture(.stopHold), at: 3)
        #expect(!machine.state.isRecording)
        _ = machine.handle(.menuStart, at: 4)
        #expect(!machine.state.isRecording)
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

    /// Design §3.2: the check comes before a recording starts, so an address cleared mid-recording (the site refused
    /// it) cuts nothing off. The next start is refused.
    @Test func noRecordingIsCutOff() {
        var hold = revealedHold()
        hold.emailNeeded = true
        #expect(hold.handle(.gesture(.stopHold), at: 3) == save(1))
        var free = handsFree()
        free.emailNeeded = true
        #expect(free.handle(.elapsed, at: 1) == [])
        #expect(free.handle(.menuStop, at: 5) == save(1) + [.resetGestures])
        #expect(free.handle(.gesture(.startHold), at: 6) == [])
        #expect(free.state == .refusedHold)
    }

    /// Once an address is saved, the next hold records, and the refused ones took no capture number.
    @Test func savedAddressLetsTheNextHoldRecord() {
        var machine = refusedHold()
        _ = machine.handle(.gesture(.revealHold), at: 0.8)
        _ = machine.handle(.gesture(.stopHold), at: 2)
        machine.emailNeeded = false
        #expect(machine.handle(.gesture(.startHold), at: 3.25) == [.startEngine(.hold)])
        #expect(machine.handle(.gesture(.revealHold), at: 3.8) == [.showPill(.hold), .playStart])
        #expect(machine.handle(.gesture(.stopHold), at: 5) == save(1))
    }

    // MARK: - Before each input

    /// SessionController prepares the machine before every input. While idle, a saved address lets a hold record.
    @Test func preparedWithAnAddressAHoldRecords() {
        var machine = withoutEmail()
        machine.prepare(sounds: true, hasAddress: true)
        #expect(machine.handle(.gesture(.startHold), at: 0.25) == [.startEngine(.hold)])
        #expect(machine.handle(.gesture(.revealHold), at: 0.8) == [.showPill(.hold), .playStart])
    }

    /// With no address saved, the hold is refused.
    @Test func preparedWithoutAnAddressAHoldIsRefused() {
        var machine = SessionMachine(sounds: true)
        machine.prepare(sounds: true, hasAddress: false)
        #expect(machine.handle(.gesture(.startHold), at: 0.25) == [])
        #expect(machine.state == .refusedHold)
    }

    /// The Sounds setting comes the same way.
    @Test func preparedWithSoundsOffNothingPlays() {
        var machine = SessionMachine(sounds: true)
        machine.prepare(sounds: false, hasAddress: true)
        _ = machine.handle(.gesture(.startHold), at: 0.25)
        #expect(machine.handle(.gesture(.revealHold), at: 0.8) == [.showPill(.hold)])
        #expect(machine.handle(.gesture(.stopHold), at: 3) == [.stopEngine, .hidePill, .showCard(captureID: 1)])
    }

    /// Nothing under way changes: a recording whose address is cleared (the site refused it) still saves, with its
    /// sounds.
    @Test func preparingChangesNoRecordingUnderWay() {
        var hold = revealedHold()
        hold.prepare(sounds: false, hasAddress: false)
        #expect(hold.handle(.gesture(.stopHold), at: 3) == save(1))
        var free = handsFree()
        free.prepare(sounds: false, hasAddress: false)
        #expect(free.handle(.menuStop, at: 5) == save(1) + [.resetGestures])
    }

    /// A refused hold is under way too: an address saved meanwhile waits for it to end, and the next hold records.
    @Test func anAddressSavedDuringARefusedHoldLetsTheNextHoldRecord() {
        var machine = refusedHold()
        machine.prepare(sounds: true, hasAddress: true)
        #expect(machine.emailNeeded)
        #expect(machine.state == .refusedHold)
        #expect(machine.handle(.gesture(.stopHold), at: 0.7) == [])
        machine.prepare(sounds: true, hasAddress: true)
        #expect(machine.handle(.gesture(.startHold), at: 1.25) == [.startEngine(.hold)])
    }

    /// Only SessionController's line prepares the machine, and no test builds the controller: a hold there would start
    /// the screen recording engine. Without the line, an address saved after launch, as in the first run, would never
    /// let a recording start, and every other test would still pass.
    @Test func theControllerPreparesEachInput() throws {
        let lines = try PillTextTests.sourceLines("Sources/AnnotakeApp/SessionController.swift")
        let handle = lines.firstIndex { $0.hasPrefix("func handle(_ input: SessionMachine.Input") }
        let start = try #require(handle, "SessionController declares handle(_:at:)")
        let call = "machine.prepare(sounds: settingsStore.settings.sounds, hasAddress: signup.hasAddress)"
        let prepare = lines[start...].firstIndex(of: call)
        let effects = lines[start...].firstIndex(of: "for effect in machine.handle(input, at: time) {")
        let prepared = try #require(prepare, "handle(_:at:) prepares the machine")
        let handled = try #require(effects, "handle(_:at:) hands the input to the machine")
        #expect(prepared < handled, "the machine is prepared before it handles the input")
    }
}
