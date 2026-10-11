import AppKit
@testable import AnnotakeApp
import Testing

struct CardTests {
    let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)
    let cardSize = CGSize(width: 240, height: 150)

    @Test func newestSitsInCorner() {
        var stack = CardStack()
        _ = stack.push(1)
        _ = stack.push(2)
        let frames = stack.frames(in: visible, cardSize: cardSize)
        #expect(frames[2] == CGRect(x: 1252, y: 20, width: 240, height: 150))
        #expect(frames[1] == CGRect(x: 1252, y: 180, width: 240, height: 150))
    }

    @Test func fifthPushesOldestOut() {
        var stack = CardStack()
        for id in 1...4 {
            #expect(stack.push(id) == [])
        }
        #expect(stack.push(5) == [1])
        #expect(stack.ids == [5, 4, 3, 2])
    }

    @Test func removeClosesGap() {
        var stack = CardStack()
        for id in 1...5 { _ = stack.push(id) }
        stack.remove(4)
        let frames = stack.frames(in: visible, cardSize: cardSize)
        #expect(frames[5]?.minY == 20)
        #expect(frames[3]?.minY == 180)
        #expect(frames[2]?.minY == 340)
        #expect(frames[4] == nil)
    }

    @Test func fadeAfterDrop() {
        var fade = CardFade()
        fade.dropped(at: 0)
        #expect(fade.opacity(at: 2.5) == 0.5)
        #expect(!fade.isDone(at: 4.9))
        #expect(fade.isDone(at: 5))
    }

    @Test func hoverPausesFade() {
        var fade = CardFade()
        fade.dropped(at: 0)
        fade.hover(true, at: 2)
        #expect(fade.opacity(at: 3) == 1)
        fade.hover(false, at: 3)
        #expect(fade.opacity(at: 5.5) == 0.5)
        #expect(!fade.isDone(at: 7.9))
        #expect(fade.isDone(at: 8))
    }

    @Test func noFadeWithoutDrop() {
        var fade = CardFade()
        fade.hover(true, at: 1)
        fade.hover(false, at: 2)
        #expect(fade.opacity(at: 100) == 1)
        #expect(!fade.isDone(at: 100))
    }

    @Test func clickVersusDrag() {
        #expect(ClickOrDrag.isClick(from: .zero, to: CGPoint(x: 3, y: 0)))
        #expect(!ClickOrDrag.isClick(from: .zero, to: CGPoint(x: 4, y: 0)))
        #expect(!ClickOrDrag.isClick(from: .zero, to: CGPoint(x: 2.9, y: 2.9)))
    }

    /// AppKit lays out a drag of 17 or more items on worker threads, which read the card's `isFlipped`. When only
    /// the main thread could read it, that trapped: dragging a 20-frame card quit Annotake.
    @Test func cardCanBeReadOffTheMainThread() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                nonisolated(unsafe) let card = CardView(state: .saving(duration: 0))
                let done = DispatchSemaphore(value: 0)
                DispatchQueue.global().async {
                    _ = card.value(forKey: "flipped")
                    done.signal()
                }
                done.wait()
            }
        }
    }
}
