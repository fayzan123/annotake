import Carbon.HIToolbox
import CoreGraphics
import FlipbookCapture
import FlipbookCore
import FlipbookInput
import Synchronization

/// Where recorded input goes. RecordingPipeline conforms.
protocol PipelineInputs: AnyObject, Sendable {
    func submit(_ kind: InputEventKind)
    func reserve(_ placeholder: InputEventKind) -> Int
    func fill(_ token: Int, with kind: InputEventKind)
}

extension RecordingPipeline: PipelineInputs {}

/// Where labels come from. AXClient conforms.
protocol LabelProvider: Sendable {
    func label(at globalPoint: CGPoint) async -> ElementLabel?
    func focusedFieldLabel() async -> ElementLabel?
}

extension AXClient: LabelProvider {}

/// Turns one recording's raw input into picker events (design §5): maps points into the recorded area,
/// drops clicks and scrolls outside it, and reserves a slot for each event whose label the AX thread
/// still has to look up. `recorded` runs on the input thread and returns at once; lookups finish on
/// other threads, so the typing runs they fill are guarded by `runs`.
final class InputBridge: @unchecked Sendable {
    static let tabKeycode = UInt16(kVK_Tab)

    private struct TypingRun {
        var resolved = false
        var label: ElementLabel?
        var waiting: [Int] = []
    }

    private let mapping: @Sendable () -> TargetMapping
    private let pipeline: PipelineInputs
    private let labels: LabelProvider
    private let runs = Mutex<[Int: TypingRun]>([:])
    private let lookups = Mutex<[Task<Void, Never>]>([])

    // Input thread only.
    private var fieldRule = FieldLookupRule()
    private var currentRun = 0
    private var pressKept = false
    private var lastPressPoint: PixelPoint?

    init(mapping: @escaping @Sendable () -> TargetMapping, pipeline: PipelineInputs, labels: LabelProvider) {
        self.mapping = mapping
        self.pipeline = pipeline
        self.labels = labels
    }

    func recorded(_ input: RecordedInput, at time: TimeInterval) {
        switch input {
        case let .mouseDown(globalPoint, button, clickCount):
            let mapping = mapping()
            guard let point = mapping.outputPoint(globalPoint) else {
                // The frames can't show it, so neither the press nor its release is logged.
                pressKept = false
                return
            }
            pressKept = true
            lastPressPoint = point
            fieldRule.invalidate()
            let token = pipeline.reserve(.mouseDown(point: point, target: nil, button: button, clickCount: clickCount))
            lookUp { [labels, pipeline] in
                let label = await labels.label(at: globalPoint)
                pipeline.fill(token, with: .mouseDown(point: point, target: label, button: button, clickCount: clickCount))
            }
        case .mouseUp(let globalPoint):
            guard pressKept else { return }
            pressKept = false
            guard let point = mapping().outputPoint(globalPoint) ?? lastPressPoint else { return }
            pipeline.submit(.mouseUp(point: point))
        case let .key(kind, keycode):
            if case .keyTyped = kind {
                typed(at: time)
                if keycode == Self.tabKeycode { fieldRule.invalidate() }
            } else {
                pipeline.submit(kind)
                fieldRule.invalidate()
            }
        case let .scroll(globalPoint, pointDeltaX, pointDeltaY):
            let mapping = mapping()
            guard mapping.contains(globalPoint) else { return }
            let fraction = PointerClassifier.scrollFraction(pointDeltaX: pointDeltaX, pointDeltaY: pointDeltaY,
                                                            targetHeightPoints: mapping.screenRect.height)
            pipeline.submit(.scroll(fractionOfViewport: fraction))
        }
    }

    /// Every key of a typing run waits for that run's one field lookup, so no key in a run can reach the
    /// picker with a different field.
    private func typed(at time: TimeInterval) {
        if fieldRule.needsLookup(forKeyAt: time) {
            currentRun += 1
            let run = currentRun
            runs.withLock { $0[run] = TypingRun() }
            lookUp { [self] in
                let label = await labels.focusedFieldLabel()
                let waiting = runs.withLock { runs -> [Int] in
                    runs[run]?.resolved = true
                    runs[run]?.label = label
                    defer { runs[run]?.waiting = [] }
                    return runs[run]?.waiting ?? []
                }
                for token in waiting {
                    pipeline.fill(token, with: .keyTyped(field: label))
                }
            }
        }
        let run = currentRun
        let token = pipeline.reserve(.keyTyped(field: nil))
        let resolved = runs.withLock { runs -> ElementLabel?? in
            guard runs[run]?.resolved == true else {
                runs[run]?.waiting.append(token)
                return .none
            }
            return .some(runs[run]?.label)
        }
        if case .some(let label) = resolved {
            pipeline.fill(token, with: .keyTyped(field: label))
        }
    }

    private func lookUp(_ work: @escaping @Sendable () async -> Void) {
        let task = Task { await work() }
        lookups.withLock { $0.append(task) }
    }

    /// Waits for every lookup started so far.
    func settle() async {
        for task in lookups.withLock({ $0 }) {
            await task.value
        }
    }
}
