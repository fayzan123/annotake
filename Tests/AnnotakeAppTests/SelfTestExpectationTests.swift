import CoreGraphics
@testable import AnnotakeApp
import AnnotakeCore
import Foundation
import Testing

/// Pins the self-test's script against Core before real capture is involved: a synthetic version of the
/// scene, replayed with the script's inputs, must pick the captions the live self-test expects.
struct SelfTestExpectationTests {
    /// The self-test window's points, scaled onto the synthetic 640×384 screen.
    static let scaleX = 640.0 / SelfTestLayout.size.width
    static let scaleY = 384.0 / SelfTestLayout.size.height

    static func pixel(_ point: CGPoint) -> PixelPoint {
        PixelPoint(x: point.x * scaleX, y: point.y * scaleY)
    }

    /// The synthetic screen: what each tile shows, with the pointer drawn over one tile. The pointer
    /// darkens its tile without hiding it, so a change under the pointer still shows.
    struct Model {
        let geometry: CaptureGeometry
        var content: [Int: UInt8] = [:]
        var pointerTile: Int?
        var textChanges = 0

        func tile(_ point: CGPoint) -> Int {
            geometry.grid.tile(containing: SelfTestExpectationTests.pixel(point))!
        }

        func tiles(_ rect: CGRect) -> [Int] {
            let origin = SelfTestExpectationTests.pixel(rect.origin)
            let size = SelfTestExpectationTests.pixel(CGPoint(x: rect.width, y: rect.height))
            return geometry.grid.tiles(intersecting: PixelRect(x: Int(origin.x), y: Int(origin.y),
                                                               width: Int(size.x), height: Int(size.y)))
        }

        func shown(_ tile: Int) -> UInt8 {
            let value = content[tile] ?? 200
            return tile == pointerTile ? value / 2 : value
        }

        mutating func apply(_ change: SelfTestStep.Change) {
            switch change {
            case .pointer(let point):
                pointerTile = tile(point)
            case .showDialog:
                for tile in tiles(SelfTestLayout.dialog) { content[tile] = 240 }
            case .tickCheckbox:
                content[tile(SelfTestLayout.checkboxCenter)] = 90
            case .typeText:
                let field = SelfTestLayout.emailField
                content[tile(CGPoint(x: field.minX + 20 + 40 * Double(textChanges), y: field.midY))] = 60
                textChanges += 1
            case .closeDialogShowBanner:
                for tile in tiles(SelfTestLayout.dialog) { content[tile] = 200 }
                for tile in tiles(SelfTestLayout.banner) { content[tile] = 30 }
            case .shiftList:
                for tile in tiles(SelfTestLayout.list) { content[tile] = 150 }
            case .retitle:
                // Only the title bar changes, and the synthetic screen is the content view alone.
                break
            }
        }
    }

    func syntheticSession() -> RawSession {
        var scene = SyntheticScene()
        var model = Model(geometry: scene.geometry)
        var frames: [FrameSample] = []
        var events: [InputEvent] = []
        var stopTime = 0.0
        for step in SelfTest.script {
            if let change = step.change {
                let before = (0..<scene.geometry.grid.count).map(model.shown)
                model.apply(change)
                let changed = (0..<scene.geometry.grid.count).filter { model.shown($0) != before[$0] }
                let values = Dictionary(uniqueKeysWithValues: changed.map { ($0, model.shown($0)) })
                frames.append(scene.frame(at: step.time, set: values, cursor: model.pointerTile.map(scene.rect(ofTile:))))
                // The pipeline reads the recorded window's new title with the next frame.
                if case .retitle(let title) = change {
                    events.append(InputEvent(time: step.time, kind: .titleChanged(window: title)))
                }
            }
            switch step.input {
            case let .reserveThenFill(kind, _, _)?, let .submit(kind)?:
                events.append(InputEvent(time: step.time, kind: SelfTest.mapped(kind, Self.pixel)))
            case .stop?:
                stopTime = step.time
            case nil:
                break
            }
        }
        return RawSession(geometry: scene.geometry, initialContext: SelfTest.initialContext,
                          contextSource: .recordedWindow, frames: frames, events: events, stopTime: stopTime)
    }

    @Test func expectationMatchesSyntheticReplay() {
        let session = syntheticSession()
        #expect(session.frames.count == SelfTest.script.filter { $0.change != nil }.count)
        let result = SessionReplayer.run(session).result
        let captions = result.frames.enumerated().map { offset, frame in
            Captions.summary(for: frame, number: offset + 1, total: result.frames.count)
        }
        #expect(captions == SelfTest.expectedCaptions)
        #expect(result.frames.map { Captions.line2(for: $0.context) } == SelfTest.expectedContexts)
    }

    /// `make selftest-intel` runs under Rosetta, where signature timings measure translation, not a Mac.
    @Test func signatureLimitLoosensOnlyUnderTranslation() {
        #expect(SelfTest.signatureLimit(translated: false) == SelfTest.signatureMillisecondsLimit)
        #expect(SelfTest.signatureLimit(translated: true) == 2 * SelfTest.signatureMillisecondsLimit)
        #expect(SelfTest.architectureName(arm64: true, translated: false) == "arm64")
        #expect(SelfTest.architectureName(arm64: false, translated: true) == "x86_64 (Rosetta)")
        #expect(SelfTest.architectureName(arm64: false, translated: false) == "x86_64")
    }
}
