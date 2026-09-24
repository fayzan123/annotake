import FlipbookCore
import Foundation
import Testing

struct ReplayTests {
    @Test func clickFlowPicksExpectedFrames() {
        let result = SessionReplayer.run(Scenes.clickFlow()).result
        #expect(result.frames.map(\.frameIndex) == [0, 1, 2, 5, 6])
        #expect(result.summaries == [
            #"Clicked button "Open""#,
            #"Clicked checkbox "Remember me""#,
            #"Typed in field "Email""#,
            "Pressed Return",
            "End",
        ])
        #expect(result.candidateCount == 5)
    }

    @Test func replayMatchesHarness() {
        let session = Scenes.clickFlow()
        var harness = PickerHarness(geometry: session.geometry, context: session.initialContext)
        // Both lists are in time order; frames go before events at equal times.
        var frames = session.frames[...]
        for event in session.events {
            while let frame = frames.first, frame.time <= event.time {
                harness.frame(frame)
                frames = frames.dropFirst()
            }
            harness.event(event)
        }
        for frame in frames {
            harness.frame(frame)
        }
        harness.stop(at: session.stopTime)

        #expect(harness.picker.result() == SessionReplayer.run(session).result)
    }

    @Test func reportListsKeepsAndPicks() {
        let session = Scenes.clickFlow()
        let report = ReplayReport.render(SessionReplayer.run(session), session: session)
        #expect(report.contains("keep     #1  click"))
        #expect(report.contains("picked 5 of 5 candidates"))
        #expect(report.contains("5/5 · 0:06 · End"))
    }
}
