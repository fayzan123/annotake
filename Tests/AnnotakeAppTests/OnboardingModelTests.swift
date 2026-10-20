@testable import AnnotakeApp
import AppKit
import Foundation
import SwiftUI
import Testing

struct OnboardingModelTests {
    typealias Model = OnboardingModel
    typealias Permission = OnboardingModel.Permission

    let noneGranted: [Permission: Bool] = [.accessibility: false, .inputMonitoring: false, .screenRecording: false]
    let allGranted: [Permission: Bool] = [.accessibility: true, .inputMonitoring: true, .screenRecording: true]
    let accessibilityGranted: [Permission: Bool] = [.accessibility: true, .inputMonitoring: false,
                                                    .screenRecording: false]

    func model(at step: Model.Step, mode: Model.Mode = .firstRun, granted: [Permission: Bool]? = nil,
               requested: Set<Permission> = [], recorded: Bool = false) -> Model {
        Model(granted: granted ?? noneGranted,
              persisted: .init(mode: mode, step: step, requested: requested, recorded: recorded))
    }

    @Test func newUserStepsInOrder() {
        #expect(Model.steps(for: .firstRun) == [
            .welcome, .email, .permission(.accessibility), .permission(.inputMonitoring), .permission(.screenRecording),
            .reopen, .practice, .dropCard, .done,
        ])
    }

    @Test func fixPermissionsSkipsWelcomeAndPractice() {
        #expect(Model.steps(for: .fixPermissions) == [
            .permission(.accessibility), .permission(.inputMonitoring), .permission(.screenRecording), .reopen, .done,
        ])
        #expect(!Model.steps(for: .fixPermissions).contains(.email))
    }

    /// An existing copy with no address: the email step, then You're set (design §3.2).
    @Test func emailOnlyIsTheEmailThenDone() {
        #expect(Model.steps(for: .emailOnly) == [.email, .done])
        #expect(Model.emailOnly() == Model.Persisted(mode: .emailOnly, step: .email))
        #expect(Model.Mode.emailOnly.rawValue == "emailOnly")
    }

    @Test func grantedPermissionsAreSkipped() {
        var model = model(at: .welcome, granted: accessibilityGranted)
        #expect(model.action == .next)
        model.perform()
        #expect(model.step == .email)
        model.emailSaved()
        #expect(model.step == .permission(.inputMonitoring))

        // Granted before the window opened, from System Settings directly: never asked for again.
        let resumed = Model(granted: allGranted, persisted: .init(step: .permission(.accessibility)))
        #expect(resumed.step == .practice)
    }

    /// The email step is never skipped, even with every permission granted and the practice run recorded.
    @Test func theWelcomeAlwaysGoesToTheEmailStep() {
        var model = model(at: .welcome, granted: allGranted, recorded: true)
        model.perform()
        #expect(model.step == .email)
    }

    /// Continue saves the address first (design §3.1), so the step's own button moves nothing: only emailSaved()
    /// does, to the first permission not yet granted, or on past the ones that are, as advance() decides.
    @Test func onlyASavedEmailLeavesTheEmailStep() {
        var model = model(at: .email)
        #expect(model.action == .submitEmail)
        model.perform()
        model.proceed()
        model.skip()
        model.relaunched()
        model.cardDropped()
        model.update(granted: accessibilityGranted)
        #expect(model.step == .email)
        model.emailSaved()
        #expect(model.step == .permission(.inputMonitoring))

        var none = self.model(at: .email)
        none.emailSaved()
        #expect(none.step == .permission(.accessibility))

        var all = self.model(at: .email, granted: allGranted)
        all.emailSaved()
        #expect(all.step == .practice)

        var recorded = self.model(at: .email, granted: allGranted, recorded: true)
        recorded.emailSaved()
        #expect(recorded.step == .dropCard)
    }

    /// Skip leaves the email step as a saved address does: on past what's done.
    @Test func skippingTheEmailMovesOnLikeASavedOne() {
        var model = model(at: .email, granted: accessibilityGranted)
        model.emailSkipped()
        #expect(model.step == .permission(.inputMonitoring))
        var emailOnly = Model(granted: noneGranted, persisted: Model.emailOnly())
        emailOnly.emailSkipped()
        #expect(emailOnly.step == .done)
        var welcome = self.model(at: .welcome)
        welcome.emailSkipped()
        #expect(welcome.step == .welcome)
    }

    @Test func emailSavedMovesOnlyFromTheEmailStep() {
        for step: Model.Step in [.welcome, .permission(.accessibility), .reopen, .practice, .dropCard, .done] {
            var model = model(at: step, requested: [.screenRecording])
            model.emailSaved()
            #expect(model.step == step)
        }
    }

    @Test func emailOnlyFinishesAtYoureSet() {
        var model = Model(granted: noneGranted, persisted: Model.emailOnly())
        #expect(model.step == .email)
        #expect(model.action == .submitEmail)
        #expect(model.showsAtLaunch)
        model.perform()
        #expect(model.step == .email)
        model.emailSaved()
        #expect(model.step == .done)
        #expect(model.action == .finish)
        #expect(model.showsAtLaunch)
        model.perform()
        #expect(model.persisted.completed)
        #expect(!model.showsAtLaunch)
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

        var fixing = model(at: .reopen, mode: .fixPermissions, requested: [.screenRecording])
        fixing.relaunched()
        #expect(fixing.step == .done)

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

    /// Closing the window: the email step and missing permissions come back at the next launch; the practice run, the
    /// drop box, and Fix permissions… don't.
    @Test func closingLeavesOnlyPermissionsToComeBack() {
        for step: Model.Step in [.welcome, .email, .permission(.inputMonitoring), .reopen] {
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

    /// The .emailOnly pass closed at any step is done: the email is optional, so closing it at the step is a skip.
    @Test func closingTheEmailOnlyPassFinishesIt() {
        var model = Model(granted: noneGranted, persisted: Model.emailOnly())
        model.closed()
        #expect(!model.showsAtLaunch)
        var saved = Model(granted: noneGranted, persisted: Model.emailOnly())
        saved.emailSaved()
        saved.closed()
        #expect(!saved.showsAtLaunch)
    }

    /// A step the mode doesn't have means the mode's first step, past any permission already granted.
    @Test func aStepTheModeLacksMeansItsFirstStep() {
        #expect(Model(granted: noneGranted, persisted: .init(mode: .fixPermissions, step: .practice)).step
                == .permission(.accessibility))
        #expect(Model(granted: accessibilityGranted, persisted: .init(mode: .fixPermissions, step: .welcome)).step
                == .permission(.inputMonitoring))
        #expect(Model(granted: allGranted, persisted: .init(mode: .fixPermissions, step: .welcome)).step == .done)
        #expect(Model(granted: noneGranted, persisted: .init(mode: .fixPermissions, step: .email)).step
                == .permission(.accessibility))
        #expect(Model(granted: allGranted, persisted: .init(mode: .emailOnly, step: .practice)).step == .email)
    }

    @Test func fixPermissionsStartsAtFirstMissing() {
        let persisted = Model.fixingPermissions(granted: [.accessibility: true, .inputMonitoring: true,
                                                          .screenRecording: false])
        #expect(persisted.mode == .fixPermissions)
        #expect(persisted.step == .permission(.screenRecording))
        #expect(Model.fixingPermissions(granted: allGranted).step == .done)
    }

    @Test func persistedRoundTrips() throws {
        for persisted in [Model.Persisted(mode: .fixPermissions, step: .permission(.inputMonitoring),
                                          requested: [.accessibility, .inputMonitoring], recorded: true),
                          Model.emailOnly(), Model.Persisted(step: .email, recorded: true)] {
            let decoded = try JSONDecoder().decode(Model.Persisted.self, from: JSONEncoder().encode(persisted))
            #expect(decoded == persisted)
        }
        #expect(Model.storeKey == "onboarding.v1")
    }

    // MARK: - Copies from before the email step

    /// What the version before the email step saved under onboarding.v1, exactly as its JSONEncoder wrote it: a
    /// finished first run, one left at a permission, Fix permissions… left at Reopen, and a first run at You're set
    /// that was never closed.
    static let savedBeforeTheEmailStep: [(json: String, persisted: Model.Persisted)] = [
        (#"{"step":{"welcome":{}},"requested":[],"mode":"firstRun","recorded":false,"completed":true}"#,
         .init(step: .welcome, completed: true)),
        (#"{"step":{"permission":{"_0":"inputMonitoring"}},"requested":["inputMonitoring"],"mode":"firstRun","#
            + #""recorded":false,"completed":false}"#,
         .init(step: .permission(.inputMonitoring), requested: [.inputMonitoring])),
        (#"{"step":{"reopen":{}},"requested":["screenRecording"],"mode":"fixPermissions","recorded":true,"#
            + #""completed":false}"#,
         .init(mode: .fixPermissions, step: .reopen, requested: [.screenRecording], recorded: true)),
        (#"{"step":{"done":{}},"requested":[],"mode":"firstRun","recorded":true,"completed":false}"#,
         .init(step: .done, recorded: true)),
    ]

    /// Step and Mode stay Codable with the new cases added, so every copy's saved state still reads after the update,
    /// and a finished first run with no address gets the email step once.
    @Test func whatTheOldVersionSavedStillDecodes() throws {
        for saved in Self.savedBeforeTheEmailStep {
            #expect(try JSONDecoder().decode(Model.Persisted.self, from: Data(saved.json.utf8)) == saved.persisted)
        }
        let finished = try JSONDecoder().decode(Model.Persisted.self,
                                                from: Data(Self.savedBeforeTheEmailStep[0].json.utf8))
        var model = Model(granted: allGranted, persisted: finished)
        #expect(!model.showsAtLaunch)
        model.launched(hasAddress: false)
        #expect(model.persisted == Model.emailOnly())
        #expect(model.showsAtLaunch)
    }

    // MARK: - Asking for the address (design §3.2)

    /// An update can arrive mid-first-run, past where the email step now goes. With no address saved, the first run
    /// goes back to it, so the practice run isn't left unable to record, and after it the first run picks up where it
    /// was: granted permissions, a reopen that isn't needed, and a recorded practice run are skipped again.
    @Test func aFirstRunPastTheEmailStepGoesBackToIt() {
        let screenRecordingMissing: [Permission: Bool] = [.accessibility: true, .inputMonitoring: true,
                                                          .screenRecording: false]
        let cases: [(step: Model.Step, granted: [Permission: Bool], requested: Set<Permission>, recorded: Bool,
                     after: Model.Step)] = [
            (.permission(.accessibility), noneGranted, [.accessibility], false, .permission(.accessibility)),
            (.permission(.inputMonitoring), accessibilityGranted, [], false, .permission(.inputMonitoring)),
            (.permission(.screenRecording), screenRecordingMissing, [.screenRecording], false,
             .permission(.screenRecording)),
            (.reopen, allGranted, [.inputMonitoring, .screenRecording], false, .practice),
            (.practice, allGranted, [], false, .practice),
            (.dropCard, allGranted, [.screenRecording], true, .dropCard),
        ]
        for item in cases {
            var model = Model(granted: item.granted,
                              persisted: .init(step: item.step, requested: item.requested, recorded: item.recorded))
            model.askForEmail()
            #expect(model.step == .email, "from \(item.step)")
            #expect(model.persisted.mode == .firstRun)
            #expect(model.persisted.requested == item.requested)
            #expect(model.persisted.recorded == item.recorded)
            model.emailSaved()
            #expect(model.step == item.after, "from \(item.step)")
        }
    }

    /// A first run at You're set, never closed, has done everything but the email: the .emailOnly pass asks for it,
    /// then You're set again, without the drop box or a skipped practice run a second time.
    @Test func aFirstRunAtYoureSetAsksOnlyForTheEmail() {
        var model = model(at: .done, granted: allGranted, requested: [.screenRecording])
        model.askForEmail()
        #expect(model.persisted == Model.emailOnly())
        model.emailSaved()
        #expect(model.step == .done)
    }

    @Test func askingForTheEmailLeavesEverythingElse() {
        for step: Model.Step in [.welcome, .email] {
            var model = model(at: step)
            model.askForEmail()
            #expect(model.step == step)
        }
        // Fix permissions… has no email step.
        let fixing = model(at: .reopen, mode: .fixPermissions, requested: [.screenRecording])
        var asked = fixing
        asked.askForEmail()
        #expect(asked == fixing)
        // A finished pass isn't moved: launched(hasAddress:) gives it the .emailOnly pass instead.
        let finished = Model(granted: allGranted, persisted: .init(step: .practice, completed: true))
        var askedFinished = finished
        askedFinished.askForEmail()
        #expect(askedFinished == finished)
        // .emailOnly at You're set, its address cleared since: back to the email step.
        var emailOnly = Model(granted: noneGranted, persisted: .init(mode: .emailOnly, step: .done))
        emailOnly.askForEmail()
        #expect(emailOnly.persisted == Model.emailOnly())
    }

    /// At launch: a finished copy with no address gets the .emailOnly pass, whichever pass finished last. One with an
    /// address shows nothing.
    @Test func atLaunchAFinishedCopyWithoutAnAddressAsksOnce() {
        let finished: [Model.Persisted] = [
            .init(step: .done, completed: true), .init(step: .practice, recorded: true, completed: true),
            .init(mode: .fixPermissions, step: .done, completed: true),
            .init(mode: .emailOnly, step: .done, completed: true),
        ]
        for persisted in finished {
            var model = Model(granted: allGranted, persisted: persisted)
            model.launched(hasAddress: false)
            #expect(model.persisted == Model.emailOnly())
            #expect(model.showsAtLaunch)

            var withAddress = Model(granted: allGranted, persisted: persisted)
            withAddress.launched(hasAddress: true)
            #expect(withAddress.persisted == persisted)
            #expect(!withAddress.showsAtLaunch)
        }
    }

    /// At launch, a first run in progress shows. Without an address it goes back to the email step if it had passed it;
    /// with one (saved in Settings mid-first-run) it moves past the email step, never asking again.
    @Test func atLaunchAFirstRunInProgressShows() {
        var noAddress = model(at: .practice, granted: allGranted)
        noAddress.launched(hasAddress: false)
        #expect(noAddress.step == .email)
        #expect(noAddress.showsAtLaunch)

        for step: Model.Step in [.welcome, .email] {
            var before = model(at: step)
            before.launched(hasAddress: false)
            #expect(before.step == step)
            #expect(before.showsAtLaunch)
        }

        var saved = model(at: .email, granted: accessibilityGranted)
        saved.launched(hasAddress: true)
        #expect(saved.step == .permission(.inputMonitoring))
        #expect(saved.showsAtLaunch)

        var past = model(at: .practice, granted: allGranted)
        past.launched(hasAddress: true)
        #expect(past.step == .practice)
        #expect(past.showsAtLaunch)
    }

    /// At launch, an .emailOnly pass shows until an address is saved. Once one is, the pass finishes with no window.
    @Test func atLaunchAnEmailOnlyPassShowsUntilThereIsAnAddress() {
        var pending = Model(granted: noneGranted, persisted: Model.emailOnly())
        pending.launched(hasAddress: false)
        #expect(pending.persisted == Model.emailOnly())
        #expect(pending.showsAtLaunch)

        var saved = Model(granted: noneGranted, persisted: Model.emailOnly())
        saved.launched(hasAddress: true)
        #expect(saved.persisted.mode == .emailOnly)
        #expect(!saved.showsAtLaunch)

        // Left at You're set, the address cleared since: the email step again.
        var cleared = Model(granted: noneGranted, persisted: .init(mode: .emailOnly, step: .done))
        cleared.launched(hasAddress: false)
        #expect(cleared.persisted == Model.emailOnly())
    }

    /// At launch, Fix permissions… left at Quit & Reopen shows as it always has, address or not.
    @Test func atLaunchAFixPermissionsPassInProgressShowsAsBefore() {
        for hasAddress in [false, true] {
            let fixing = model(at: .permission(.screenRecording), mode: .fixPermissions, requested: [.screenRecording])
            var model = fixing
            model.launched(hasAddress: hasAddress)
            #expect(model == fixing)
            #expect(model.showsAtLaunch)
        }
    }

    /// Settings' Add… always leads to the field: as at launch, and a Fix permissions… pass in progress gives
    /// way to the .emailOnly pass, since the person asked for the email.
    @Test func openingForTheEmailLeadsToTheField() {
        var fixing = Model(granted: noneGranted, persisted: Model.fixingPermissions(granted: noneGranted))
        fixing.openedForEmail(hasAddress: false)
        #expect(fixing.persisted == Model.emailOnly())
        #expect(fixing.showsAtLaunch)

        var firstRun = model(at: .dropCard, granted: allGranted, recorded: true)
        firstRun.openedForEmail(hasAddress: false)
        #expect(firstRun.step == .email)
        #expect(firstRun.persisted.mode == .firstRun)

        var welcome = model(at: .welcome)
        welcome.openedForEmail(hasAddress: false)
        #expect(welcome.step == .welcome, "the email step is the welcome's next")

        var pending = Model(granted: noneGranted, persisted: Model.emailOnly())
        pending.openedForEmail(hasAddress: false)
        #expect(pending.persisted == Model.emailOnly())

        var finished = Model(granted: allGranted, persisted: .init(step: .done, completed: true))
        finished.openedForEmail(hasAddress: false)
        #expect(finished.persisted == Model.emailOnly())
        #expect(finished.showsAtLaunch)

        // With an address saved by then, a Fix permissions… pass carries on.
        let carriesOn = Model(granted: noneGranted, persisted: Model.fixingPermissions(granted: noneGranted))
        var withAddress = carriesOn
        withAddress.openedForEmail(hasAddress: true)
        #expect(withAddress == carriesOn)
    }

    /// Fix permissions…: a first run or a Fix permissions… pass in progress shows where it is. Anything else, an
    /// .emailOnly pass in progress included, gives way to a pass over the missing permissions; the email step comes
    /// back with Settings' Add…, or at the next launch, since there's still no address.
    @Test func fixPermissionsStartsItsPassUnlessOneIsInProgress() {
        let firstRun = model(at: .email, granted: accessibilityGranted)
        var keptFirstRun = firstRun
        keptFirstRun.fixPermissions(granted: accessibilityGranted)
        #expect(keptFirstRun == firstRun)

        let fixing = model(at: .permission(.inputMonitoring), mode: .fixPermissions,
                           requested: [.accessibility, .inputMonitoring])
        var keptFixing = fixing
        keptFixing.fixPermissions(granted: noneGranted)
        #expect(keptFixing == fixing)

        let others: [Model.Persisted] = [
            Model.emailOnly(), .init(mode: .emailOnly, step: .done), .init(step: .done, completed: true),
            .init(mode: .fixPermissions, step: .done, completed: true),
        ]
        for persisted in others {
            var model = Model(granted: noneGranted, persisted: persisted)
            model.fixPermissions(granted: accessibilityGranted)
            #expect(model.persisted == Model.fixingPermissions(granted: accessibilityGranted))
            #expect(model.step == .permission(.inputMonitoring))
            #expect(model.granted == accessibilityGranted)
            #expect(model.showsAtLaunch)
        }
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
/// window has usually fallen behind System Settings by then (Checkpoint 3). The email step saves through a
/// SignupHarness, so nothing here posts for real.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct OnboardingViewModelTests {
    final class Granted: @unchecked Sendable {
        var status = Permissions.Status(screenRecording: false, inputMonitoring: false, accessibility: false)
    }

    static let none = Permissions.Status(screenRecording: false, inputMonitoring: false, accessibility: false)
    static let accessibilityOnly = Permissions.Status(screenRecording: false, inputMonitoring: false,
                                                      accessibility: true)
    static let all = Permissions.Status(screenRecording: true, inputMonitoring: true, accessibility: true)

    /// A view model that sees fixed permissions. Its signup comes from a SignupHarness, or there's none, as in the UI
    /// snapshots.
    static func viewModel(_ persisted: OnboardingModel.Persisted, signup: EmailSignup?, defaults: UserDefaults? = nil,
                          status: Permissions.Status = none,
                          report: @escaping (String) -> Void = { _ in }) -> OnboardingViewModel {
        OnboardingViewModel(trigger: .rightCommand, defaults: defaults, signup: signup, persisted: persisted,
                            status: { status }, report: report)
    }

    @Test func grantBringsTheWindowForward() {
        let granted = Granted()
        let viewModel = OnboardingViewModel(trigger: .rightCommand, defaults: nil, signup: nil,
                                            persisted: .init(step: .permission(.accessibility)),
                                            status: { granted.status }, report: { _ in })
        var forward = 0
        viewModel.onAdvancedElsewhere = { forward += 1 }

        viewModel.refresh()
        #expect(forward == 0)
        granted.status.accessibility = true
        viewModel.refresh()
        #expect(forward == 1)
        #expect(viewModel.model.step == .permission(.inputMonitoring))
        viewModel.refresh()
        #expect(forward == 1)
    }

    /// The practice recording is made in another app, since Annotake keeps its own windows out of recordings,
    /// so once it's saved the window comes back with the drop box (Checkpoint 3).
    @Test func savedRecordingBringsTheDropBoxForward() {
        let all = Permissions.Status(screenRecording: true, inputMonitoring: true, accessibility: true)
        let viewModel = OnboardingViewModel(trigger: .rightCommand, defaults: nil, signup: nil,
                                            persisted: .init(step: .practice), status: { all }, report: { _ in })
        var forward = 0
        viewModel.onAdvancedElsewhere = { forward += 1 }
        viewModel.recordingSaved()
        #expect(viewModel.model.step == .dropCard)
        #expect(forward == 1)
        viewModel.recordingSaved()
        #expect(forward == 1)
    }

    // MARK: - The email step

    /// Continue is greyed out until the address is one the site takes: EmailConsent's check, on what's typed.
    @Test func continueWaitsForAPlausibleAddress() {
        let viewModel = Self.viewModel(.init(step: .email), signup: nil)
        #expect(viewModel.emailDraft.isEmpty)
        #expect(!viewModel.canSubmitEmail)
        let drafts: [(String, Bool)] = [
            ("", false), ("sam", false), ("sam@", false), ("sam@example", false), ("sam@example.", false),
            ("sam @example.com", false), ("sam@example.com\nbcc@example.com", false), ("sam@example.com", true),
            ("  Sam@Example.COM ", true),
        ]
        for (draft, plausible) in drafts {
            viewModel.emailDraft = draft
            #expect(viewModel.canSubmitEmail == plausible, "\(draft)")
            #expect(viewModel.canSubmitEmail == EmailConsent.isPlausible(draft))
        }
    }

    /// Continue (and Return, which calls the same) saves the cleaned address on the Mac, with no Feedback and news since
    /// the step has no box (design §13), then moves straight on: the post goes in the background (design §3.1). The
    /// log names the step, never the address.
    @Test func continueSavesTheAddressThenMovesOnWithoutWaiting() async {
        let harness = SignupHarness()
        let signup = harness.makeSignup()
        var lines: [String] = []
        let viewModel = Self.viewModel(.init(step: .email), signup: signup, defaults: harness.defaults,
                                       status: Self.accessibilityOnly, report: { lines.append($0) })
        harness.answers = [.sent]
        viewModel.emailDraft = "  Sam@Example.COM "
        viewModel.submitDraft()

        #expect(harness.stored == EmailRecord(address: "Sam@Example.COM", news: false, consent: EmailConsent.id,
                                              savedAt: harness.now, sent: false))
        #expect(harness.requests.isEmpty, "the first run doesn't wait for the post")
        #expect(viewModel.model.step == .permission(.inputMonitoring))
        #expect(OnboardingViewModel.load(from: harness.defaults)?.step == .permission(.inputMonitoring))

        await signup.settle()
        #expect(harness.requests.count == 1)
        #expect(harness.stored?.sent == true)
        #expect(lines == ["onboarding: inputMonitoring"])
        #expect(!(lines + harness.logged).contains { $0.localizedCaseInsensitiveContains("sam@example.com") })
    }

    /// Continue does nothing for an address the site wouldn't take, without a signup (the UI snapshots), or away from
    /// the email step.
    @Test func continueSavesNothingItShouldnt() async {
        let harness = SignupHarness()
        let signup = harness.makeSignup()
        let implausible = Self.viewModel(.init(step: .email), signup: signup)
        implausible.submitEmail(address: "sam@example")
        #expect(implausible.model.step == .email)

        let welcome = Self.viewModel(.init(), signup: signup)
        welcome.submitEmail(address: "sam@example.com")
        #expect(welcome.model.step == .welcome)

        await signup.settle()
        #expect(harness.stored == nil)
        #expect(harness.requests.isEmpty)

        let noSignup = Self.viewModel(.init(step: .email), signup: nil)
        noSignup.submitEmail(address: "sam@example.com")
        #expect(noSignup.model.step == .email)
    }

    /// The field starts empty each time the step shows (design §3.1): what's typed is a draft, never saved, and gone
    /// once the window closes. Add… with the step already showing keeps it.
    @Test func theDraftStartsEmptyEachTimeTheStepShows() throws {
        let harness = SignupHarness()
        let viewModel = Self.viewModel(.init(step: .practice), signup: harness.makeSignup(), defaults: harness.defaults,
                                       status: Self.all)
        // Left from an earlier showing of the step, before its address was cleared.
        viewModel.emailDraft = "sam@example.com"
        viewModel.openedForEmail()
        #expect(viewModel.model.step == .email)
        #expect(viewModel.emailDraft.isEmpty)

        viewModel.emailDraft = "sam@example.com"
        viewModel.openedForEmail()
        #expect(viewModel.emailDraft == "sam@example.com")

        viewModel.closed()
        #expect(viewModel.model.showsAtLaunch)
        #expect(viewModel.emailDraft.isEmpty)

        let data = try #require(harness.defaults.data(forKey: OnboardingModel.storeKey))
        let fields = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(fields.keys) == ["mode", "step", "requested", "recorded", "completed"])
        #expect(!String(decoding: data, as: UTF8.self).contains("sam@"))
    }

    /// Skip saves no address and posts nothing, remembers the skip, and moves on; the next launch doesn't ask again.
    @Test func skipMovesOnWithoutAnAddress() async throws {
        let harness = SignupHarness()
        let signup = harness.makeSignup()
        var lines: [String] = []
        let viewModel = Self.viewModel(.init(step: .email), signup: signup, defaults: harness.defaults,
                                       status: Self.accessibilityOnly, report: { lines.append($0) })
        viewModel.emailDraft = "sam@example.com"
        viewModel.skipEmail()
        #expect(viewModel.model.step == .permission(.inputMonitoring))
        #expect(viewModel.emailDraft.isEmpty)
        #expect(signup.skipped)
        await signup.settle()
        #expect(harness.stored == nil)
        #expect(harness.requests.isEmpty)
        #expect(lines == ["onboarding: inputMonitoring"])

        let next = Self.viewModel(try #require(OnboardingViewModel.load(from: harness.defaults)),
                                  signup: harness.makeSignup(), defaults: harness.defaults,
                                  status: Self.accessibilityOnly)
        next.launched()
        #expect(next.model.step == .permission(.inputMonitoring))

        let away = Self.viewModel(.init(step: .practice), signup: harness.makeSignup())
        away.skipEmail()
        #expect(away.model.step == .practice)
    }

    /// An existing copy skips the email step it gets once after the update: You're set, and never asked again.
    @Test func anExistingCopySkipsTheEmailOnce() throws {
        let harness = SignupHarness()
        let viewModel = Self.viewModel(OnboardingModel.emailOnly(), signup: harness.makeSignup(),
                                       defaults: harness.defaults)
        viewModel.skipEmail()
        #expect(viewModel.model.step == .done)
        viewModel.primary()
        #expect(!viewModel.model.showsAtLaunch)

        let next = Self.viewModel(try #require(OnboardingViewModel.load(from: harness.defaults)),
                                  signup: harness.makeSignup(), defaults: harness.defaults)
        next.launched()
        #expect(!next.model.showsAtLaunch)
    }

    /// Closing the window at the email step skips it, in either mode: a first run comes back past it at the next
    /// launch, and the .emailOnly pass doesn't come back.
    @Test func closedAtTheEmailStepItIsSkipped() throws {
        for persisted in [OnboardingModel.Persisted(step: .email), OnboardingModel.emailOnly()] {
            let harness = SignupHarness()
            let viewModel = Self.viewModel(persisted, signup: harness.makeSignup(), defaults: harness.defaults)
            viewModel.closed()
            viewModel.save()
            #expect(harness.makeSignup().skipped)

            let next = Self.viewModel(try #require(OnboardingViewModel.load(from: harness.defaults)),
                                      signup: harness.makeSignup(), defaults: harness.defaults)
            next.launched()
            if persisted.mode == .firstRun {
                #expect(next.model.showsAtLaunch)
                #expect(next.model.step == .permission(.accessibility))
            } else {
                #expect(!next.model.showsAtLaunch)
            }
        }
    }

    /// Settings' Add… after a skip still brings the email step back: the person asked for it.
    @Test func addAfterASkipShowsTheEmailStep() {
        let harness = SignupHarness()
        let signup = harness.makeSignup()
        signup.skip()
        let viewModel = Self.viewModel(.init(step: .done, completed: true), signup: signup)
        viewModel.openedForEmail()
        #expect(viewModel.model.persisted == OnboardingModel.emailOnly())
        #expect(viewModel.model.showsAtLaunch)
    }

    /// An existing copy, finished before the update, asks for the email at its first launch after it, and only then.
    @Test func anExistingCopyAsksForTheEmailOnceAfterTheUpdate() async throws {
        let harness = SignupHarness()
        let before = OnboardingModelTests.savedBeforeTheEmailStep[0].json
        harness.defaults.set(Data(before.utf8), forKey: OnboardingModel.storeKey)
        let signup = harness.makeSignup()
        var lines: [String] = []
        let viewModel = Self.viewModel(try #require(OnboardingViewModel.load(from: harness.defaults)), signup: signup,
                                       defaults: harness.defaults, status: Self.all, report: { lines.append($0) })
        viewModel.launched()
        #expect(viewModel.model.persisted == OnboardingModel.emailOnly())
        #expect(viewModel.model.showsAtLaunch)
        #expect(OnboardingViewModel.load(from: harness.defaults) == OnboardingModel.emailOnly())

        harness.answers = [.sent]
        viewModel.emailDraft = "sam@example.com"
        viewModel.submitDraft()
        #expect(harness.stored?.address == "sam@example.com")
        #expect(harness.stored?.news == false)
        #expect(viewModel.model.step == .done)
        var finished = 0
        viewModel.onFinish = { finished += 1 }
        viewModel.primary()
        #expect(finished == 1)
        #expect(!viewModel.model.showsAtLaunch)
        await signup.settle()
        #expect(lines == ["onboarding: email", "onboarding: done"])

        let next = Self.viewModel(try #require(OnboardingViewModel.load(from: harness.defaults)),
                                  signup: harness.makeSignup(), defaults: harness.defaults)
        next.launched()
        #expect(!next.model.showsAtLaunch)
    }

    /// At launch, the saved address decides: an .emailOnly pass with one by now finishes with no window.
    @Test func atLaunchTheSavedAddressDecides() throws {
        let harness = SignupHarness()
        let pending = Self.viewModel(OnboardingModel.emailOnly(), signup: harness.makeSignup())
        pending.launched()
        #expect(pending.model.showsAtLaunch)

        try harness.store(EmailRecord(address: "sam@example.com", news: false, consent: EmailConsent.id,
                                      savedAt: harness.now, sent: true))
        let saved = Self.viewModel(OnboardingModel.emailOnly(), signup: harness.makeSignup())
        saved.launched()
        #expect(!saved.model.showsAtLaunch)
    }

    /// Fix permissions… while the email is pending starts its own pass; Settings' Add… then brings the email step
    /// back. A first run in progress shows where it is.
    @Test func fixPermissionsWhileTheEmailIsPending() {
        let harness = SignupHarness()
        let viewModel = Self.viewModel(OnboardingModel.emailOnly(), signup: harness.makeSignup(),
                                       status: Self.accessibilityOnly)
        viewModel.fixPermissions()
        #expect(viewModel.model.persisted.mode == .fixPermissions)
        #expect(viewModel.model.step == .permission(.inputMonitoring))
        viewModel.openedForEmail()
        #expect(viewModel.model.persisted == OnboardingModel.emailOnly())

        let firstRun = Self.viewModel(.init(step: .email), signup: harness.makeSignup(), status: Self.accessibilityOnly)
        firstRun.fixPermissions()
        #expect(firstRun.model.persisted == OnboardingModel.Persisted(step: .email))
    }

    /// The window is a fixed 560 × 440 pt: the email step, empty or filled in, fits it at its own height, as the UI
    /// snapshots measure it.
    @Test func theEmailStepFitsTheWindow() {
        for persisted in [OnboardingModel.Persisted(step: .email), OnboardingModel.emailOnly()] {
            let viewModel = Self.viewModel(persisted, signup: nil)
            for draft in ["", "sam.example-person@subdomain.example.com"] {
                viewModel.emailDraft = draft
                let view = NSHostingView(rootView: OnboardingView(viewModel: viewModel, fitsContent: true))
                let natural = view.fittingSize
                #expect(natural.width == OnboardingView.width)
                #expect(natural.height <= OnboardingView.height, "the email step needs \(natural.height) pt")
            }
        }
    }
}

/// The window's controller: when the window shows at launch, from Settings' Add…, and from Fix permissions…. A test's
/// `present` stands in for the window, so nothing is drawn or activated, and the view model sees the permissions the
/// test gives it.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct OnboardingControllerTests {
    typealias Persisted = OnboardingModel.Persisted

    /// What `harness` holds under onboarding.v1, or a new first run, as the app reads it at launch.
    static func viewModel(_ harness: SignupHarness, status: Permissions.Status = OnboardingViewModelTests.all)
        -> OnboardingViewModel {
        OnboardingViewModelTests.viewModel(OnboardingViewModel.load(from: harness.defaults) ?? Persisted(),
                                           signup: harness.makeSignup(), defaults: harness.defaults, status: status)
    }

    static func save(_ persisted: Persisted, in harness: SignupHarness) throws {
        harness.defaults.set(try JSONEncoder().encode(persisted), forKey: OnboardingModel.storeKey)
    }

    static func saveAddress(in harness: SignupHarness) throws {
        try harness.store(EmailRecord(address: "sam@example.com", news: false, consent: EmailConsent.id,
                                      savedAt: harness.now, sent: true))
    }

    /// The email step an existing copy gets once after its update isn't titled as a welcome: its person already uses
    /// Annotake (design §13). A first run keeps the welcome.
    @Test func theEmailOnlyPassIsTitledAnnotake() {
        let harness = SignupHarness()
        harness.defaults.set(Data(OnboardingModelTests.savedBeforeTheEmailStep[0].json.utf8),
                             forKey: OnboardingModel.storeKey)
        let viewModel = Self.viewModel(harness)
        let controller = OnboardingController(viewModel: viewModel, present: {})
        controller.showIfNeeded()
        #expect(viewModel.model.persisted == OnboardingModel.emailOnly())
        #expect(controller.windowTitle == "Annotake")

        let firstRun = OnboardingController(viewModel: Self.viewModel(SignupHarness()), present: {})
        firstRun.showIfNeeded()
        #expect(firstRun.windowTitle == "Welcome to Annotake")
    }

    /// The first launch after the update: a copy that finished its first run before the email step, with no address,
    /// gets the email step alone (design §3.2). With an address, nothing shows.
    @Test func atLaunchAFinishedCopyWithoutAnAddressGetsTheEmailStep() throws {
        let harness = SignupHarness()
        harness.defaults.set(Data(OnboardingModelTests.savedBeforeTheEmailStep[0].json.utf8),
                             forKey: OnboardingModel.storeKey)
        let viewModel = Self.viewModel(harness)
        var shown = 0
        let controller = OnboardingController(viewModel: viewModel, present: { shown += 1 })
        controller.showIfNeeded()
        #expect(shown == 1)
        #expect(viewModel.model.persisted == OnboardingModel.emailOnly())
        #expect(OnboardingViewModel.load(from: harness.defaults) == OnboardingModel.emailOnly())

        let saved = SignupHarness()
        saved.defaults.set(Data(OnboardingModelTests.savedBeforeTheEmailStep[0].json.utf8),
                           forKey: OnboardingModel.storeKey)
        try Self.saveAddress(in: saved)
        let savedViewModel = Self.viewModel(saved)
        var savedShown = 0
        OnboardingController(viewModel: savedViewModel, present: { savedShown += 1 }).showIfNeeded()
        #expect(savedShown == 0)
        #expect(savedViewModel.model.persisted == OnboardingModelTests.savedBeforeTheEmailStep[0].persisted)
    }

    /// A first run in progress shows at launch: after Quit & Reopen, with the address given at the email step, it
    /// moves on past Reopen; one that an update reached past the email step, with no address, goes back to it.
    @Test func atLaunchAFirstRunInProgressShows() throws {
        let reopened = SignupHarness()
        try Self.save(Persisted(step: .reopen, requested: [.inputMonitoring, .screenRecording]), in: reopened)
        try Self.saveAddress(in: reopened)
        let viewModel = Self.viewModel(reopened)
        var shown = 0
        let controller = OnboardingController(viewModel: viewModel, present: { shown += 1 })
        controller.showIfNeeded()
        #expect(shown == 1)
        #expect(viewModel.model.step == .practice)

        let updated = SignupHarness()
        try Self.save(Persisted(step: .practice), in: updated)
        let updatedViewModel = Self.viewModel(updated)
        var updatedShown = 0
        OnboardingController(viewModel: updatedViewModel, present: { updatedShown += 1 }).showIfNeeded()
        #expect(updatedShown == 1)
        #expect(updatedViewModel.model.step == .email)
    }

    /// Settings' Add…, with no address saved: the window, at the email step. The .emailOnly pass that finished before
    /// the site refused its address comes back, and Fix permissions… in progress gives way.
    @Test func addShowsTheEmailStep() throws {
        for persisted in [Persisted(mode: .emailOnly, step: .done, completed: true),
                          OnboardingModel.fixingPermissions(granted: [:])] {
            let harness = SignupHarness()
            try Self.save(persisted, in: harness)
            let viewModel = Self.viewModel(harness, status: OnboardingViewModelTests.none)
            var shown = 0
            let controller = OnboardingController(viewModel: viewModel, present: { shown += 1 })
            controller.showForEmail()
            #expect(shown == 1, "from \(persisted)")
            #expect(viewModel.model.persisted == OnboardingModel.emailOnly(), "from \(persisted)")
        }

        // An address saved by then (Settings' Change…): nothing to ask for.
        let saved = SignupHarness()
        try Self.save(Persisted(step: .done, completed: true), in: saved)
        try Self.saveAddress(in: saved)
        let savedViewModel = Self.viewModel(saved)
        var savedShown = 0
        OnboardingController(viewModel: savedViewModel, present: { savedShown += 1 }).showForEmail()
        #expect(savedShown == 0)
        #expect(savedViewModel.model.persisted == Persisted(step: .done, completed: true))
    }

    /// Fix permissions… from the menu: a pass over the missing permissions, shown, even while the email is pending.
    @Test func fixPermissionsShowsItsPass() throws {
        for persisted in [Persisted(step: .done, completed: true), OnboardingModel.emailOnly()] {
            let harness = SignupHarness()
            try Self.save(persisted, in: harness)
            let viewModel = Self.viewModel(harness, status: OnboardingViewModelTests.accessibilityOnly)
            var shown = 0
            let controller = OnboardingController(viewModel: viewModel, present: { shown += 1 })
            controller.show(fixingPermissions: true)
            #expect(shown == 1, "from \(persisted)")
            #expect(viewModel.model.persisted.mode == .fixPermissions, "from \(persisted)")
            #expect(viewModel.model.step == .permission(.inputMonitoring), "from \(persisted)")
        }
    }

    /// Nothing polls while the window is closed, so showing it again reads the permissions first, test or not: a first
    /// run left at Accessibility, granted meanwhile, comes back from Fix permissions… at Input Monitoring.
    @Test func shownAgainItStartsPastWhatWasGrantedMeanwhile() throws {
        let harness = SignupHarness()
        try Self.save(Persisted(step: .permission(.accessibility)), in: harness)
        try Self.saveAddress(in: harness)
        let granted = OnboardingViewModelTests.Granted()
        let viewModel = OnboardingViewModel(
            trigger: .rightCommand, defaults: harness.defaults, signup: harness.makeSignup(),
            persisted: try #require(OnboardingViewModel.load(from: harness.defaults)), status: { granted.status },
            report: { _ in })
        var shown = 0
        let controller = OnboardingController(viewModel: viewModel, present: { shown += 1 })
        controller.showIfNeeded()
        #expect(shown == 1)
        #expect(viewModel.model.step == .permission(.accessibility))

        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        granted.status = OnboardingViewModelTests.accessibilityOnly
        controller.show(fixingPermissions: true)
        #expect(shown == 2)
        #expect(viewModel.model.persisted.mode == .firstRun)
        #expect(viewModel.model.step == .permission(.inputMonitoring))
    }
}
