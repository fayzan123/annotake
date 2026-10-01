@testable import AnnotakeApp
import Foundation
import Testing

struct ChecklistModelTests {
    typealias Permission = ChecklistModel.Permission

    let noneGranted: [Permission: Bool] = [.screenRecording: false, .inputMonitoring: false, .accessibility: false]

    @Test func firstPressPromptsThenOpensSettings() {
        var model = ChecklistModel(granted: noneGranted, persisted: .init())
        #expect(model.buttonPressed(.accessibility) == .prompt)
        #expect(model.buttonPressed(.accessibility) == .openSettings)
    }

    @Test func quitAndReopenAfterRelaunchPermissions() {
        var screen = ChecklistModel(granted: noneGranted, persisted: .init())
        _ = screen.buttonPressed(.screenRecording)
        #expect(screen.showsQuitAndReopen)

        var accessibility = ChecklistModel(granted: noneGranted, persisted: .init())
        _ = accessibility.buttonPressed(.accessibility)
        #expect(!accessibility.showsQuitAndReopen)
    }

    @Test func grantedNeedsNothing() {
        let allGranted: [Permission: Bool] = [.screenRecording: true, .inputMonitoring: true, .accessibility: true]
        var model = ChecklistModel(granted: allGranted, persisted: .init())
        #expect(model.allGranted)
        for permission in Permission.allCases {
            _ = model.buttonPressed(permission)
        }
        #expect(!model.showsQuitAndReopen)
        #expect(Permission.allCases.allSatisfy { model.state(of: $0) == .granted })
    }

    @Test func resumesFromPersisted() {
        let model = ChecklistModel(granted: noneGranted, persisted: .init(requested: [.screenRecording]))
        #expect(model.state(of: .screenRecording) == .requested)
        #expect(model.state(of: .accessibility) == .notRequested)
        #expect(model.showsQuitAndReopen)
    }

    @Test func loginItemOnlyFromApplications() {
        let home = URL(fileURLWithPath: "/Users/someone")
        #expect(LoginItemPolicy.canRegister(bundleURL: URL(fileURLWithPath: "/Applications/Annotake.app"), home: home))
        #expect(LoginItemPolicy.canRegister(bundleURL: home.appending(path: "Applications/Annotake.app"), home: home))
        #expect(!LoginItemPolicy.canRegister(
            bundleURL: home.appending(path: "Documents/GitHub/annotake/build/Annotake.app"), home: home))
    }
}
