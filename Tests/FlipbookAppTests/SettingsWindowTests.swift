@testable import FlipbookApp
import Foundation
import Testing

struct SettingsWindowTests {
    @Test func millisecondsFormatting() {
        #expect(SettingsText.milliseconds(0.25) == "250 ms")
        #expect(SettingsText.milliseconds(0.8) == "800 ms")
    }

    @Test func fnWarningsVerbatim() {
        #expect(SettingsText.fnWarnings == [
            #"macOS's "Press 🌐 key to" setting must be "Do Nothing"."#,
            "Dictation apps (Wispr Flow, Handy) often use fn already.",
            "Some third-party keyboards handle fn themselves and never send it to macOS, "
                + "so fn works reliably only on Apple keyboards.",
        ])
    }

    @Test func permissionPaneURLs() {
        #expect(PermissionPane.screenRecording.absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        #expect(PermissionPane.inputMonitoring.absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        #expect(PermissionPane.accessibility.absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }
}
