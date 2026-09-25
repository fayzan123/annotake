import FlipbookInput
import Foundation
import Testing

struct ConfigurationLogRuleTests {
    @Test func firstChangeGetsLine() {
        var rule = ConfigurationLogRule()
        let first = rule.needsLine(forChangeAt: 1.0)
        #expect(first)
    }

    /// A slider drag: a new value every 20 ms for 3 s, with a 1 s hesitation halfway, gets one line.
    @Test func dragGetsOneLine() {
        var rule = ConfigurationLogRule()
        let steps: [TimeInterval] = (0..<75).map { Double($0) * 0.02 }
        let times = steps.map { 1.0 + $0 } + steps.map { 3.5 + $0 }
        let lines = times.filter { rule.needsLine(forChangeAt: $0) }
        #expect(lines == [1.0])
    }

    /// Restore Defaults well after a drag gets its own line.
    @Test func changeAfterPauseGetsLine() {
        var rule = ConfigurationLogRule()
        for time in [1.0, 1.02, 1.04] { _ = rule.needsLine(forChangeAt: time) }
        let afterPause = rule.needsLine(forChangeAt: 1.04 + ConfigurationLogRule.pause)
        #expect(afterPause)
    }
}
