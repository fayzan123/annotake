@testable import FlipbookApp
import Testing

struct MenuModelTests {
    @Test func fixPermissionsOnlyWhenMissing() {
        #expect(MenuModel.items(missingPermission: true, recording: false, recentTitles: []).first == .fixPermissions)
        #expect(!MenuModel.items(missingPermission: false, recording: false, recentTitles: []).contains(.fixPermissions))
    }

    @Test func startOrStopByState() {
        let idle = MenuModel.items(missingPermission: false, recording: false, recentTitles: [])
        #expect(idle.contains(.startRecording) && !idle.contains(.stopRecording))
        let recording = MenuModel.items(missingPermission: false, recording: true, recentTitles: [])
        #expect(recording.contains(.stopRecording) && !recording.contains(.startRecording))
    }

    @Test func orderIsFixed() {
        let titles = ["2026-09-24 at 16.46.58 · 10 frames", "2026-09-24 at 16.46.03 · 4 frames"]
        #expect(MenuModel.items(missingPermission: true, recording: false, recentTitles: titles) == [
            .fixPermissions, .startRecording, .recent(titles), .openFolder, .settings, .quit,
        ])
    }
}
