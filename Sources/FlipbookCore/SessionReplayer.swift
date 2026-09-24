import Foundation

/// One picker decision during a replay.
public struct ReplayLogEntry: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case keep(frameIndex: Int, reason: KeepReason)
        case discard(frameIndices: [Int])
    }

    public let time: TimeInterval
    public let kind: Kind
}

public struct ReplayOutcome: Sendable, Equatable {
    public let result: PickResult
    public let log: [ReplayLogEntry]
}

/// Runs a raw session through a LiveSession exactly as the app does, so a recording replays the way it
/// ran live: the same items in the same order, with a tick every 50 ms.
public enum SessionReplayer {
    public static let tickInterval: TimeInterval = LiveSession.tickInterval

    private enum Item {
        case frame(FrameSample)
        case event(InputEvent)
    }

    public static func run(_ session: RawSession, config: PickerConfig = PickerConfig()) -> ReplayOutcome {
        // Stable by time; at the same time, frames go before events.
        let frames = session.frames.enumerated().map { (time: $1.time, order: $0, item: Item.frame($1)) }
        let events = session.events.enumerated().map {
            (time: $1.time, order: session.frames.count + $0, item: Item.event($1))
        }
        let items = (frames + events).sorted { ($0.time, $0.order) < ($1.time, $1.order) }

        var live = LiveSession(geometry: session.geometry, config: config, initialContext: session.initialContext)
        var log: [ReplayLogEntry] = []
        func record(_ outputs: [LiveSession.Output]) {
            for output in outputs {
                switch output {
                case let .persist(frameIndex, reason, time):
                    log.append(ReplayLogEntry(time: time, kind: .keep(frameIndex: frameIndex, reason: reason)))
                case let .discard(frameIndices, time):
                    log.append(ReplayLogEntry(time: time, kind: .discard(frameIndices: frameIndices)))
                case .tookFrame, .tookEvent:
                    break
                }
            }
        }
        func receive(_ item: Item) {
            switch item {
            case .frame(let frame): record(live.receive(frame))
            case .event(let event): record(live.receive(event))
            }
        }

        for (time, _, item) in items where time <= session.stopTime {
            receive(item)
        }
        record(live.stop(at: session.stopTime))
        for (time, _, item) in items where time > session.stopTime {
            receive(item)
        }

        let limit = Int((config.stopSettleTimeout / tickInterval).rounded(.up)) + 4
        var calls = 0
        while !live.isFinished {
            calls += 1
            if calls > limit {
                preconditionFailure("the picker didn't finish within \(limit) ticks of stopping")
            }
            record(live.advance(to: live.nextTickTime))
        }
        return ReplayOutcome(result: live.result(), log: log)
    }
}

/// The replay as text, for `flipbook-replay`.
public enum ReplayReport {
    public static func render(_ outcome: ReplayOutcome, session: RawSession) -> String {
        var lines = ["frames \(session.frames.count) · events \(session.events.count) · stop \(Captions.timestamp(session.stopTime))"]
        for entry in outcome.log {
            switch entry.kind {
            case let .keep(frameIndex, reason):
                lines.append("\(clock(entry.time))  keep     #\(frameIndex)  \(reason.rawValue)")
            case .discard(let frameIndices):
                lines.append("\(clock(entry.time))  discard  " + frameIndices.map { "#\($0)" }.joined(separator: " "))
            }
        }
        let frames = outcome.result.frames
        lines.append("picked \(frames.count) of \(outcome.result.candidateCount) candidates")
        for (offset, frame) in frames.enumerated() {
            lines.append(Captions.line1(for: frame, number: offset + 1, total: frames.count))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// e.g. `0:03.41`. Rounded to the centisecond first, so 59.999 s reads 1:00.00, not 0:60.00.
    private static func clock(_ time: TimeInterval) -> String {
        let centiseconds = Int((max(time, 0) * 100).rounded())
        return String(format: "%d:%05.2f", centiseconds / 6000, Double(centiseconds % 6000) / 100)
    }
}
