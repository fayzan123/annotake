import AnnotakeCore
import Foundation
import Testing

struct CaptionsTests {
    let save = ElementLabel(role: "button", label: "Save")
    let chrome = FrameContext(app: "Google Chrome", window: "Dayforce · Timesheets")

    func click(_ target: ElementLabel?, at point: PixelPoint = PixelPoint(x: 10, y: 20),
               button: MouseButton = .left, count: Int = 1) -> StepAction {
        .clicked(target: target, at: point, button: button, clickCount: count)
    }

    func frame(at time: TimeInterval = 0, actions: [StepAction] = []) -> PickedFrame {
        PickedFrame(frameIndex: 0, time: time, context: chrome, actions: actions, reason: .visual)
    }

    @Test func clickWithLabel() {
        #expect(Captions.text(for: click(save)) == #"Clicked button "Save""#)
    }

    @Test func rightClick() {
        let docs = ElementLabel(role: "link", label: "Docs")
        #expect(Captions.text(for: click(docs, button: .right)) == #"Right-clicked link "Docs""#)
    }

    @Test func doubleClick() {
        let file = ElementLabel(role: "file", label: "a.txt")
        #expect(Captions.text(for: click(file, count: 2)) == #"Double-clicked file "a.txt""#)
    }

    @Test func clickWithoutLabelUsesRoundedPoint() {
        #expect(Captions.text(for: click(nil, at: PixelPoint(x: 811.6, y: 440.2))) == "Clicked at (812, 440)")
    }

    @Test func clickWithEmptyRole() {
        #expect(Captions.text(for: click(ElementLabel(role: "", label: "Save"))) == #"Clicked "Save""#)
    }

    @Test func clickWithEmptyLabelOrBoth() {
        #expect(Captions.text(for: click(ElementLabel(role: "button", label: ""))) == "Clicked button")
        let blank = ElementLabel(role: "", label: "")
        #expect(Captions.text(for: click(blank, at: PixelPoint(x: 3.4, y: 4.5))) == "Clicked at (3, 5)")
    }

    @Test func typedWithAndWithoutField() {
        #expect(Captions.text(for: .typed(field: ElementLabel(role: "text field", label: "Email"))) == #"Typed in field "Email""#)
        #expect(Captions.text(for: .typed(field: nil)) == "Typed")
    }

    @Test func keysAndShortcut() {
        #expect(Captions.text(for: .pressedReturn) == "Pressed Return")
        #expect(Captions.text(for: .pressedEscape) == "Pressed Esc")
        #expect(Captions.text(for: .pressedShortcut("⌘S")) == "Pressed ⌘S")
    }

    @Test func switchedWithAndWithoutWindow() {
        #expect(Captions.text(for: .switched(to: chrome)) == "Switched to Google Chrome — Dayforce · Timesheets")
        #expect(Captions.text(for: .switched(to: FrameContext(app: "Finder", window: nil))) == "Switched to Finder")
    }

    @Test func summaryJoinsActions() {
        let picked = frame(actions: [click(save), .pressedReturn])
        #expect(Captions.summary(for: picked, number: 2, total: 3) == #"Clicked button "Save" → Pressed Return"#)
    }

    @Test func summaryFallbacks() {
        let picked = frame()
        #expect(Captions.summary(for: picked, number: 1, total: 3) == "Start")
        #expect(Captions.summary(for: picked, number: 3, total: 3) == "End")
        #expect(Captions.summary(for: picked, number: 2, total: 3) == "Screen changed")
        #expect(Captions.summary(for: picked, number: 1, total: 1) == "Start")
    }

    @Test func line1Format() {
        let picked = frame(at: 7.9, actions: [click(save)])
        #expect(Captions.line1(for: picked, number: 3, total: 8) == #"3/8 · 0:07 · Clicked button "Save""#)
    }

    @Test func timestamps() {
        #expect(Captions.timestamp(0) == "0:00")
        #expect(Captions.timestamp(7.9) == "0:07")
        #expect(Captions.timestamp(65) == "1:05")
        #expect(Captions.timestamp(600) == "10:00")
    }

    @Test func fileNames() {
        #expect(Captions.fileName(number: 3, time: 7.9) == "03_0m07s.png")
        #expect(Captions.fileName(number: 12, time: 125.2) == "12_2m05s.png")
    }

    @Test func clickPointsInOrder() {
        let first = PixelPoint(x: 1, y: 2), second = PixelPoint(x: 30, y: 40)
        let picked = frame(actions: [click(save, at: first), .typed(field: nil), click(nil, at: second)])
        #expect(picked.clickPoints == [first, second])
    }
}
