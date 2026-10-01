@testable import AnnotakeApp
import AnnotakeCore
import Foundation
import Testing

struct OnboardingCopyTests {
    @Test func reassuranceOnEveryPermission() {
        for permission in OnboardingModel.Permission.allCases {
            let body = OnboardingCopy.body(.permission(permission), trigger: .rightCommand)
            #expect(body.contains(OnboardingCopy.reassurance))
        }
        #expect(OnboardingCopy.reassurance
                == "Annotake sees your screen only while you record. Nothing you record leaves your Mac.")
    }

    @Test func keyNameFollowsTrigger() {
        #expect(OnboardingCopy.keyName(.rightCommand) == "Right ⌘")
        #expect(OnboardingCopy.keyName(.rightOption) == "Right ⌥")
        #expect(OnboardingCopy.keyName(.fn) == "fn")
        let practice = OnboardingCopy.body(.practice, trigger: .rightOption)
        #expect(practice.contains("Double-tap Right ⌥"))
        #expect(!practice.contains("⌘"))
        let done = OnboardingCopy.body(.done, trigger: .fn)
        #expect(done.contains("Hold fn") && done.contains("fn + Esc"))
    }

    /// Annotake keeps its own windows out of recordings, so the practice run happens in another app (Checkpoint 3:
    /// the old Open button and Remember me box were in the first run's own window, and never in the frames).
    @Test func practiceRecordsAnotherApp() {
        let practice = OnboardingCopy.body(.practice, trigger: .rightCommand)
        #expect(practice.contains("another app"))
        #expect(!practice.contains("Remember me"))
        #expect(practice.contains("Double-tap Right ⌘ again"))
    }

    @Test func titlesMatchTheSteps() {
        #expect(OnboardingCopy.title(.welcome) == "Annotake")
        #expect(OnboardingCopy.title(.permission(.inputMonitoring)) == "Allow Input Monitoring")
        #expect(OnboardingCopy.title(.reopen) == "Reopen Annotake")
        #expect(OnboardingCopy.title(.dropCard) == "Now drag the card here")
        #expect(OnboardingCopy.title(.done) == "You're set")
    }

    @Test func dropKeepsPNGsInNameOrder() {
        let folder = URL(fileURLWithPath: "/tmp/2026-09-24 at 14.05.12")
        let dropped = ["03_0m07s.png", "notes.md", "01_0m00s.png", "02_0m03s.png"].map { folder.appending(path: $0) }
        #expect(OnboardingDrop.frames(from: dropped).map(\.lastPathComponent)
                == ["01_0m00s.png", "02_0m03s.png", "03_0m07s.png"])
        #expect(OnboardingDrop.frames(from: [folder.appending(path: "notes.md")]).isEmpty)
    }
}
