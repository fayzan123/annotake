@testable import AnnotakeApp
import Foundation
import Testing

struct RetentionScheduleTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func dueWhenNeverRun() {
        #expect(RetentionSchedule.isDue(lastRun: nil, now: now))
    }

    @Test func notDueWithin24h() {
        #expect(!RetentionSchedule.isDue(lastRun: now.addingTimeInterval(-23 * 3_600), now: now))
    }

    @Test func dueAfter24h() {
        #expect(RetentionSchedule.isDue(lastRun: now.addingTimeInterval(-24 * 3_600), now: now))
    }
}
