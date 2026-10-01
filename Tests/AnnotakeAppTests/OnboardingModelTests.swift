@testable import AnnotakeApp
import Foundation
import Testing

struct OnboardingModelTests {
    typealias Model = OnboardingModel
    typealias Permission = OnboardingModel.Permission

    let noneGranted: [Permission: Bool] = [.accessibility: false, .inputMonitoring: false, .screenRecording: false]
    let allGranted: [Permission: Bool] = [.accessibility: true, .inputMonitoring: true, .screenRecording: true]

    func model(at step: Model.Step, mode: Model.Mode = .firstRun, granted: [Permission: Bool]? = nil,
               requested: Set<Permission> = []) -> Model {
        Model(granted: granted ?? noneGranted, persisted: .init(mode: mode, step: step, requested: requested))
    }

    @Test func newUserStepsInOrder() {
        #expect(Model.steps(for: .firstRun) == [
            .welcome, .permission(.accessibility), .permission(.inputMonitoring), .permission(.screenRecording),
            .reopen, .practice, .dropCard, .done,
        ])
    }

    @Test func existingUserSkipsWelcomeAndPractice() {
        let steps: [Model.Step] = [
            .permission(.accessibility), .permission(.inputMonitoring), .permission(.screenRecording), .reopen, .done,
        ]
        #expect(Model.steps(for: .existingUser) == steps)
        #expect(Model.steps(for: .fixPermissions) == steps)
    }

    @Test func grantedPermissionsAreSkipped() {
        var model = model(at: .welcome, granted: [.accessibility: true, .inputMonitoring: false, .screenRecording: false])
        #expect(model.action == .next)
        model.perform()
        #expect(model.step == .permission(.inputMonitoring))

        // Granted before the window opened, from System Settings directly: never asked for again.
        let resumed = Model(granted: allGranted, persisted: .init(step: .permission(.accessibility)))
        #expect(resumed.step == .practice)
    }

    @Test func firstPressPromptsThenOpensSettings() {
        var model = model(at: .permission(.accessibility))
        #expect(model.action == .prompt)
        model.perform()
        #expect(model.action == .openSettings)
        #expect(model.step == .permission(.accessibility))
        #expect(model.persisted.requested == [.accessibility])
        model.perform()
        #expect(model.step == .permission(.accessibility))
    }

    @Test func continueWithoutConfirmation() {
        var model = model(at: .permission(.screenRecording), requested: [.screenRecording])
        #expect(model.action == .openSettings)
        model.proceed()
        #expect(model.step == .reopen)
        #expect(model.action == .quitAndReopen)

        // Denied outright: the first run still moves on.
        var denied = self.model(at: .permission(.accessibility))
        denied.perform()
        denied.proceed()
        #expect(denied.step == .permission(.inputMonitoring))
    }

    @Test func reopenOnlyWhenNeeded() {
        var model = model(at: .permission(.screenRecording),
                          granted: [.accessibility: true, .inputMonitoring: true, .screenRecording: false])
        model.update(granted: allGranted)
        #expect(model.step == .practice)
        #expect(!model.needsReopen)

        var needed = self.model(at: .permission(.screenRecording),
                                granted: [.accessibility: true, .inputMonitoring: false, .screenRecording: false],
                                requested: [.inputMonitoring])
        #expect(needed.needsReopen)
        needed.update(granted: [.accessibility: true, .inputMonitoring: false, .screenRecording: true])
        #expect(needed.step == .reopen)
    }

    @Test func grantWhileShowingAdvances() {
        var model = model(at: .permission(.accessibility))
        model.update(granted: [.accessibility: true])
        #expect(model.step == .permission(.inputMonitoring))
        #expect(model.granted[.accessibility] == true)

        // Other permissions changing don't move the current step.
        model.update(granted: [.accessibility: true, .screenRecording: true])
        #expect(model.step == .permission(.inputMonitoring))
    }

    @Test func relaunchResumesAfterReopen() {
        var firstRun = model(at: .reopen, requested: [.screenRecording])
        firstRun.relaunched()
        #expect(firstRun.step == .practice)

        var existing = model(at: .reopen, mode: .existingUser, requested: [.screenRecording])
        existing.relaunched()
        #expect(existing.step == .done)

        // Relaunching anywhere else changes nothing.
        var elsewhere = model(at: .practice)
        elsewhere.relaunched()
        #expect(elsewhere.step == .practice)
    }

    @Test func recordingAndDropFinish() {
        var model = model(at: .practice, granted: allGranted)
        #expect(model.action == .waitForRecording)
        model.recordingSaved()
        #expect(model.step == .dropCard)
        #expect(model.action == .waitForDrop)
        model.cardDropped()
        #expect(model.step == .done)
        #expect(model.action == .finish)
        #expect(model.showsAtLaunch)
        model.perform()
        #expect(model.persisted.completed)
        #expect(!model.showsAtLaunch)
    }

    @Test func skipLeavesPracticeAndDrop() {
        var model = model(at: .practice, granted: allGranted)
        model.skip()
        #expect(model.step == .dropCard)
        model.skip()
        #expect(model.step == .done)
        var permission = self.model(at: .permission(.accessibility))
        permission.skip()
        #expect(permission.step == .permission(.accessibility))
    }

    @Test func earlyRecordingSkipsPractice() {
        var model = model(at: .permission(.accessibility))
        model.recordingSaved()
        #expect(model.step == .permission(.accessibility))
        for _ in 0..<3 {
            model.perform()
            model.proceed()
        }
        #expect(model.step == .reopen)
        model.relaunched()
        #expect(model.step == .dropCard)
    }

    /// Closing the window: missing permissions come back at the next launch; the practice run, the drop box,
    /// and Fix permissions… don't.
    @Test func closingLeavesOnlyPermissionsToComeBack() {
        for step: Model.Step in [.welcome, .permission(.inputMonitoring), .reopen] {
            var model = model(at: step, requested: [.inputMonitoring])
            model.closed()
            #expect(model.showsAtLaunch)
        }
        for step: Model.Step in [.practice, .dropCard, .done] {
            var model = model(at: step, granted: allGranted)
            model.closed()
            #expect(!model.showsAtLaunch)
        }
        var fixing = Model(granted: noneGranted, persisted: Model.fixingPermissions(granted: noneGranted))
        fixing.closed()
        #expect(!fixing.showsAtLaunch)
    }

    @Test func fixPermissionsStartsAtFirstMissing() {
        let persisted = Model.fixingPermissions(granted: [.accessibility: true, .inputMonitoring: true,
                                                          .screenRecording: false])
        #expect(persisted.mode == .fixPermissions)
        #expect(persisted.step == .permission(.screenRecording))
        #expect(Model.fixingPermissions(granted: allGranted).step == .done)
    }

    @Test func persistedRoundTrips() throws {
        let persisted = Model.Persisted(mode: .existingUser, step: .permission(.inputMonitoring),
                                        requested: [.accessibility, .inputMonitoring], recorded: true)
        let decoded = try JSONDecoder().decode(Model.Persisted.self, from: JSONEncoder().encode(persisted))
        #expect(decoded == persisted)
        #expect(Model.storeKey == "onboarding.v1")
    }

    @Test func loginItemOnlyFromApplications() {
        let home = URL(fileURLWithPath: "/Users/someone")
        #expect(LoginItemPolicy.canRegister(bundleURL: URL(fileURLWithPath: "/Applications/Annotake.app"), home: home))
        #expect(LoginItemPolicy.canRegister(bundleURL: home.appending(path: "Applications/Annotake.app"), home: home))
        #expect(!LoginItemPolicy.canRegister(
            bundleURL: home.appending(path: "Documents/GitHub/annotake/build/Annotake.app"), home: home))
    }
}

/// The live view model: a grant noticed by polling brings the window forward with the next step, since the
/// window has usually fallen behind System Settings by then (Checkpoint 3).
@MainActor
struct OnboardingViewModelTests {
    final class Granted: @unchecked Sendable {
        var status = Permissions.Status(screenRecording: false, inputMonitoring: false, accessibility: false)
    }

    @Test func grantBringsTheWindowForward() {
        let granted = Granted()
        let viewModel = OnboardingViewModel(trigger: .rightCommand, defaults: nil,
                                            persisted: .init(step: .permission(.accessibility)),
                                            retiredFlipbook: false, status: { granted.status })
        var forward = 0
        viewModel.onGrantAdvanced = { forward += 1 }

        viewModel.refresh()
        #expect(forward == 0)
        granted.status.accessibility = true
        viewModel.refresh()
        #expect(forward == 1)
        #expect(viewModel.model.step == .permission(.inputMonitoring))
        viewModel.refresh()
        #expect(forward == 1)
    }
}
