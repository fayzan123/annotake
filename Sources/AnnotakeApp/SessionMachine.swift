import AnnotakeCore
import Foundation

/// The session rules (spec §3.1, §3.2, §7; design §7): what each gesture, timer and engine report does,
/// as a list of effects for SessionController to run. Pure, so every rule is pinned by a test.
struct SessionMachine {
    /// Hands-free recordings shorter than this were accidental and are discarded.
    static let handsFreeMinimum: TimeInterval = 0.5
    /// Hands-free recordings stop and save by themselves after this long.
    static let handsFreeLimit: TimeInterval = 300

    enum StartFailure: Equatable {
        case screenRecordingPermission, contentUnavailable, saveLocationUnavailable
    }

    enum PillMessage: Equatable {
        /// "Screen Recording permission needed", with an Open Settings button.
        case screenRecordingNeeded
        /// "Couldn't start recording — try again"
        case couldNotStart
        /// "Can't save to the captures folder — check the save location"
        case cannotSave
        /// A target fallback note from TargetResolver.
        case note(String)
    }

    enum Input: Equatable {
        case gesture(GestureEvent)
        case menuStart, menuStop
        /// A 1 s timer while recording.
        case elapsed
        case engineStarted(note: String?)
        case engineFailed(StartFailure)
        case streamEnded
        case exported(captureID: Int, success: Bool)
    }

    enum Effect: Equatable {
        case startEngine(RecordingMode), stopEngine, discardEngine
        case showPill(RecordingMode), hidePill, showMessage(PillMessage)
        case playStart, playStop
        case showCard(captureID: Int), completeCard(captureID: Int), failCard(captureID: Int)
        /// InputMonitor.recordingEnded(): the recording ended without a gesture.
        case resetGestures
    }

    enum State: Equatable {
        case idle
        case recording(RecordingMode, revealed: Bool, startedAt: TimeInterval)

        /// A recording, revealed or not.
        var isRecording: Bool {
            if case .recording = self { return true }
            return false
        }
    }

    var sounds: Bool
    private(set) var state = State.idle
    private var nextCaptureID = 1
    /// A fallback note that arrived before a hold's pill appeared.
    private var pendingNote: String?

    init(sounds: Bool) {
        self.sounds = sounds
    }

    /// SessionController calls this before each input, with the Sounds setting. It takes it only while idle, so a
    /// change never touches a hold or a recording under way.
    mutating func prepare(sounds: Bool) {
        guard state == .idle else { return }
        self.sounds = sounds
    }

    /// The effects, in the order they should run. Input that doesn't apply in the current state gives [].
    mutating func handle(_ input: Input, at now: TimeInterval) -> [Effect] {
        if case let .exported(id, success) = input {
            return [success ? .completeCard(captureID: id) : .failCard(captureID: id)]
        }
        switch state {
        case .idle:
            return startIfAsked(by: input, at: now)
        case let .recording(mode, revealed, startedAt):
            return whileRecording(input, mode: mode, revealed: revealed, startedAt: startedAt, at: now)
        }
    }

    private mutating func startIfAsked(by input: Input, at now: TimeInterval) -> [Effect] {
        pendingNote = nil
        switch input {
        case .gesture(.startHold):
            // Silent until the reveal, in case it's a shortcut.
            state = .recording(.hold, revealed: false, startedAt: now)
            return [.startEngine(.hold)]
        case .gesture(.startHandsFree), .menuStart:
            state = .recording(.handsFree, revealed: true, startedAt: now)
            return [.startEngine(.handsFree), .showPill(.handsFree)] + startSound
        default:
            return []
        }
    }

    private mutating func whileRecording(_ input: Input, mode: RecordingMode, revealed: Bool,
                                         startedAt: TimeInterval, at now: TimeInterval) -> [Effect] {
        switch input {
        case .gesture(.revealHold) where mode == .hold && !revealed:
            state = .recording(.hold, revealed: true, startedAt: startedAt)
            let note = pendingNote.map { [Effect.showMessage(.note($0))] } ?? []
            pendingNote = nil
            return [.showPill(.hold)] + startSound + note
        case .gesture(.stopHold) where mode == .hold:
            // A hold released before the reveal saves nothing: the pill never appeared.
            return revealed ? save() : discard(pillShown: false)
        case .gesture(.discardHold) where mode == .hold:
            return discard(pillShown: revealed)
        case .gesture(.cancel):
            return discard(pillShown: revealed)
        case .gesture(.stopHandsFree) where mode == .handsFree:
            return now - startedAt < Self.handsFreeMinimum ? discard(pillShown: true) : save()
        case .menuStop:
            if mode == .handsFree && now - startedAt < Self.handsFreeMinimum || !revealed {
                return discard(pillShown: revealed) + [.resetGestures]
            }
            return save() + [.resetGestures]
        case .elapsed where mode == .handsFree && now - startedAt >= Self.handsFreeLimit:
            return save() + [.resetGestures]
        case .engineStarted(let note?):
            guard revealed else {
                pendingNote = note
                return []
            }
            return [.showMessage(.note(note))]
        case .engineFailed(let failure):
            state = .idle
            pendingNote = nil
            return [.hidePill, .showMessage(Self.message(for: failure)), .resetGestures]
        case .streamEnded:
            // The display slept or the window closed: keep what was captured, if the pill had appeared.
            return (revealed ? save() : discard(pillShown: false)) + [.resetGestures]
        default:
            return []
        }
    }

    private var startSound: [Effect] { sounds ? [.playStart] : [] }

    private mutating func save() -> [Effect] {
        let id = nextCaptureID
        nextCaptureID += 1
        state = .idle
        pendingNote = nil
        return [.stopEngine] + (sounds ? [.playStop] : []) + [.hidePill, .showCard(captureID: id)]
    }

    /// No sound plays when a recording is discarded or cancelled.
    private mutating func discard(pillShown: Bool) -> [Effect] {
        state = .idle
        pendingNote = nil
        return pillShown ? [.discardEngine, .hidePill] : [.discardEngine]
    }

    private static func message(for failure: StartFailure) -> PillMessage {
        switch failure {
        case .screenRecordingPermission: .screenRecordingNeeded
        case .contentUnavailable: .couldNotStart
        case .saveLocationUnavailable: .cannotSave
        }
    }
}
