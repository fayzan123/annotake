import CoreGraphics
@testable import AnnotakeApp
import AnnotakeCapture
import AnnotakeCore
import AnnotakeInput
import Foundation
import Synchronization
import Testing

/// Records what reaches the pipeline.
final class FakePipeline: PipelineInputs {
    enum Call: Equatable {
        case submit(InputEventKind)
        case reserve(Int, InputEventKind)
        case fill(Int, InputEventKind)
    }

    private let state = Mutex<(calls: [Call], nextToken: Int)>(([], 1))

    var calls: [Call] { state.withLock { $0.calls } }

    func submit(_ kind: InputEventKind) {
        state.withLock { $0.calls.append(.submit(kind)) }
    }

    func reserve(_ placeholder: InputEventKind) -> Int {
        state.withLock { state in
            let token = state.nextToken
            state.nextToken += 1
            state.calls.append(.reserve(token, placeholder))
            return token
        }
    }

    func fill(_ token: Int, with kind: InputEventKind) {
        state.withLock { $0.calls.append(.fill(token, kind)) }
    }
}

/// Answers every click with `button "Save"`, and each field lookup with the next of `fields`.
final class FakeLabels: LabelProvider {
    static let save = ElementLabel(role: "button", label: "Save")
    private let fields: [ElementLabel]
    private let lookups = Mutex(0)

    init(fields: [ElementLabel] = []) {
        self.fields = fields
    }

    var fieldLookups: Int { lookups.withLock { $0 } }

    func label(at globalPoint: CGPoint) async -> ElementLabel? {
        Self.save
    }

    func focusedFieldLabel() async -> ElementLabel? {
        let index = lookups.withLock { count in
            defer { count += 1 }
            return count
        }
        return index < fields.count ? fields[index] : nil
    }
}

struct InputBridgeTests {
    static let email = ElementLabel(role: "text field", label: "Email")
    static let password = ElementLabel(role: "secure text field", label: "Password")
    /// A 100 × 100 pt area at the origin, recorded at 1 px per point.
    let mapping = TargetMapping(screenRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                                output: OutputSize(width: 100, height: 100))

    func bridge(_ pipeline: FakePipeline, _ labels: FakeLabels) -> InputBridge {
        let mapping = self.mapping
        return InputBridge(mapping: { mapping }, pipeline: pipeline, labels: labels)
    }

    @Test func outsideClickDropsItsUp() async {
        let pipeline = FakePipeline()
        let bridge = bridge(pipeline, FakeLabels())
        bridge.recorded(.mouseDown(globalPoint: CGPoint(x: 150, y: 50), button: .left, clickCount: 1), at: 1)
        bridge.recorded(.mouseUp(globalPoint: CGPoint(x: 150, y: 50)), at: 1.05)
        await bridge.settle()
        #expect(pipeline.calls.isEmpty)
    }

    @Test func insideClickReservesAndFills() async {
        let pipeline = FakePipeline()
        let bridge = bridge(pipeline, FakeLabels())
        bridge.recorded(.mouseDown(globalPoint: CGPoint(x: 10, y: 20), button: .left, clickCount: 1), at: 1)
        bridge.recorded(.mouseUp(globalPoint: CGPoint(x: 10, y: 20)), at: 1.05)
        await bridge.settle()

        let point = PixelPoint(x: 10, y: 20)
        let calls = pipeline.calls
        #expect(calls.count == 3)
        #expect(calls.first == .reserve(1, .mouseDown(point: point, target: nil, button: .left, clickCount: 1)))
        #expect(calls.contains(.fill(1, .mouseDown(point: point, target: FakeLabels.save, button: .left, clickCount: 1))))
        #expect(calls.contains(.submit(.mouseUp(point: point))))
    }

    @Test func typingRunSharesOneLookup() async {
        let pipeline = FakePipeline()
        let labels = FakeLabels(fields: [Self.email, Self.password])
        let bridge = bridge(pipeline, labels)
        for (offset, time) in [1.0, 1.3, 1.8].enumerated() {
            bridge.recorded(.key(.keyTyped(field: nil), keycode: UInt16(offset)), at: time)
        }
        await bridge.settle()

        #expect(labels.fieldLookups == 1)
        let calls = pipeline.calls
        #expect(calls.filter { if case .reserve(_, .keyTyped(field: nil)) = $0 { true } else { false } }.count == 3)
        #expect(calls.filter { if case .fill(_, .keyTyped(field: Self.email)) = $0 { true } else { false } }.count == 3)
        #expect(Set(calls.compactMap { if case .fill(let token, _) = $0 { token } else { nil } }) == [1, 2, 3])
    }

    @Test func tabStartsNewLookup() async {
        let pipeline = FakePipeline()
        let labels = FakeLabels(fields: [Self.email, Self.password])
        let bridge = bridge(pipeline, labels)
        bridge.recorded(.key(.keyTyped(field: nil), keycode: 0), at: 1.0)
        bridge.recorded(.key(.keyTyped(field: nil), keycode: 48), at: 1.1)
        bridge.recorded(.key(.keyTyped(field: nil), keycode: 11), at: 1.2)
        await bridge.settle()

        #expect(labels.fieldLookups == 2)
        let calls = pipeline.calls
        #expect(calls.contains(.fill(1, .keyTyped(field: Self.email))))
        #expect(calls.contains(.fill(2, .keyTyped(field: Self.email))))
        #expect(calls.contains(.fill(3, .keyTyped(field: Self.password))))
    }

    @Test func scrollOutsideDropped() async {
        let pipeline = FakePipeline()
        let bridge = bridge(pipeline, FakeLabels())
        bridge.recorded(.scroll(globalPoint: CGPoint(x: 150, y: 50), pointDeltaX: 0, pointDeltaY: 50), at: 1)
        #expect(pipeline.calls.isEmpty)
        bridge.recorded(.scroll(globalPoint: CGPoint(x: 50, y: 50), pointDeltaX: 0, pointDeltaY: 50), at: 1.1)
        #expect(pipeline.calls == [.submit(.scroll(fractionOfViewport: 0.5))])
    }
}
