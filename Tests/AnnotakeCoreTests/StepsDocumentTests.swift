import AnnotakeCore
import Foundation
import Testing

struct StepsDocumentTests {
    let chrome = FrameContext(app: "Google Chrome", window: "Dayforce · Timesheets")

    func frame(at time: TimeInterval, _ actions: [StepAction] = []) -> PickedFrame {
        PickedFrame(frameIndex: Int(time * 10), time: time, context: chrome, actions: actions, reason: .visual)
    }

    @Test func rendersSpecExample() {
        let country = StepAction.clicked(target: ElementLabel(role: "pop-up button", label: "Country"),
                                         at: PixelPoint(x: 400, y: 300), button: .left, clickCount: 1)
        let result = PickResult(frames: [frame(at: 0.0), frame(at: 3.4, [country]), frame(at: 21.2)],
                                candidateCount: 12, duration: 21.2)
        let expected = """
            # Annotake capture — 2026-09-23 at 14.05.12
            Screen: Built-in Retina Display · 0:21 · 3 frames (from 12 candidates)

            1. 0:00 · Google Chrome — Dayforce · Timesheets · Start
            2. 0:03 · Google Chrome — Dayforce · Timesheets · Clicked pop-up button "Country"
            3. 0:21 · Google Chrome — Dayforce · Timesheets · End

            """
        let rendered = StepsDocument.render(result, captureName: "2026-09-23 at 14.05.12",
                                            target: "Screen: Built-in Retina Display")
        #expect(rendered == expected)
    }

    @Test func singularCounts() {
        let result = PickResult(frames: [frame(at: 0)], candidateCount: 1, duration: 0.6)
        let rendered = StepsDocument.render(result, captureName: "2026-09-23 at 14.05.12", target: "Window: Finder")
        #expect(rendered.contains("Window: Finder · 0:00 · 1 frame (from 1 candidate)\n"))
        #expect(rendered.hasSuffix("1. 0:00 · Google Chrome — Dayforce · Timesheets · Start\n"))
    }
}
