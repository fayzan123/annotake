import AnnotakeInput
import Foundation
import Testing

struct WebAccessibilityFlagsTests {
    @Test func chromeDetected() {
        #expect(WebAccessibilityFlags.kind(bundleID: "com.google.Chrome", bundleURL: nil, fileExists: { _ in false })
                == .chrome)
    }

    @Test func electronDetected() {
        let slack = URL(fileURLWithPath: "/Applications/Slack.app")
        let framework = slack.appending(path: "Contents/Frameworks/Electron Framework.framework").path
        #expect(WebAccessibilityFlags.kind(bundleID: "com.tinyspeck.slackmacgap", bundleURL: slack,
                                           fileExists: { $0 == framework }) == .electron)
    }

    @Test func othersIgnored() {
        #expect(WebAccessibilityFlags.kind(bundleID: "com.apple.Safari",
                                           bundleURL: URL(fileURLWithPath: "/Applications/Safari.app"),
                                           fileExists: { _ in false }) == nil)
    }
}
