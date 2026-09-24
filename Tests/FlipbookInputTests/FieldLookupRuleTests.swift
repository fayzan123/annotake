import FlipbookInput
import Testing

struct FieldLookupRuleTests {
    @Test func firstKeyNeedsLookup() {
        var rule = FieldLookupRule()
        let first = rule.needsLookup(forKeyAt: 1.0)
        #expect(first)
    }

    @Test func runReusesLabel() {
        var rule = FieldLookupRule()
        _ = rule.needsLookup(forKeyAt: 1.0)
        let second = rule.needsLookup(forKeyAt: 1.3)
        let third = rule.needsLookup(forKeyAt: 2.0)
        #expect(!second)
        #expect(!third)
    }

    @Test func pauseNeedsLookup() {
        var rule = FieldLookupRule()
        for time in [1.0, 1.3, 2.0] { _ = rule.needsLookup(forKeyAt: time) }
        let afterPause = rule.needsLookup(forKeyAt: 3.3)
        #expect(afterPause)
    }

    @Test func invalidateNeedsLookup() {
        var rule = FieldLookupRule()
        _ = rule.needsLookup(forKeyAt: 1.0)
        rule.invalidate()
        let next = rule.needsLookup(forKeyAt: 1.1)
        #expect(next)
    }
}
