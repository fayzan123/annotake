import Foundation

/// The first run's rules (spec §3.7): which step shows, what its button does, and where it goes next. One
/// step at a time; permissions that are already granted are never asked for, and nothing waits on a grant
/// that can't be confirmed yet. It never sees the saved address, only whether there is one.
struct OnboardingModel: Equatable {
    /// In the order they're asked for: Accessibility applies without a relaunch, so it comes first.
    enum Permission: String, CaseIterable, Codable, Identifiable {
        case accessibility, inputMonitoring, screenRecording

        var id: Self { self }

        /// These apply only after Annotake reopens (M0).
        var needsRelaunch: Bool { self != .accessibility }
    }

    /// Saved by case name, so a new case leaves what older versions saved readable.
    enum Step: Hashable, Codable {
        case welcome, email, permission(Permission), reopen, practice, dropCard, done
    }

    enum Mode: String, Codable {
        /// A new user: the welcome, the email, the permissions, and a practice run.
        case firstRun
        /// From "Fix permissions…".
        case fixPermissions
        /// A copy whose first run is over but that has no address: from before the email step, or the site refused
        /// the address (email list design §3.2).
        case emailOnly
    }

    /// What the step's main button does.
    enum Action: Equatable {
        case next, submitEmail, prompt, openSettings, quitAndReopen, waitForRecording, waitForDrop, finish
    }

    /// What survives Quit & Reopen, so the window reopens where it left off.
    struct Persisted: Codable, Equatable {
        var mode: Mode = .firstRun
        var step: Step = .welcome
        var requested: Set<Permission> = []
        /// A recording was saved while onboarding.
        var recorded = false
        var completed = false
    }

    static let storeKey = "onboarding.v1"

    private(set) var granted: [Permission: Bool]
    private(set) var persisted: Persisted

    /// Starts where `persisted` left off, past any permission that's been granted since. A step the mode doesn't
    /// have means the mode's first step.
    init(granted: [Permission: Bool], persisted: Persisted) {
        self.granted = granted
        self.persisted = persisted
        let steps = Self.steps(for: persisted.mode)
        if !steps.contains(persisted.step), let first = steps.first { self.persisted.step = first }
        if case .permission(let permission) = step, isGranted(permission) { advance() }
    }

    var step: Step { persisted.step }

    var action: Action {
        switch step {
        case .welcome: .next
        case .email: .submitEmail
        case .permission(let permission): persisted.requested.contains(permission) ? .openSettings : .prompt
        case .reopen: .quitAndReopen
        case .practice: .waitForRecording
        case .dropCard: .waitForDrop
        case .done: .finish
        }
    }

    /// Input Monitoring or Screen Recording was requested and isn't granted yet: they apply only after a relaunch.
    var needsReopen: Bool {
        Permission.allCases.contains { $0.needsRelaunch && persisted.requested.contains($0) && !isGranted($0) }
    }

    var showsAtLaunch: Bool { !persisted.completed }

    /// In order. In Stage 2, sign-in takes the email step's place.
    static func steps(for mode: Mode) -> [Step] {
        let permissions = Permission.allCases.map(Step.permission)
        switch mode {
        case .firstRun: return [.welcome, .email] + permissions + [.reopen, .practice, .dropCard, .done]
        case .fixPermissions: return permissions + [.reopen, .done]
        case .emailOnly: return [.email, .done]
        }
    }

    /// "Fix permissions…": its own mode, starting at the first permission that's missing.
    static func fixingPermissions(granted: [Permission: Bool]) -> Persisted {
        let missing = Permission.allCases.first { granted[$0] != true }
        return Persisted(mode: .fixPermissions, step: missing.map(Step.permission) ?? .done)
    }

    /// The email step alone, then You're set.
    static func emailOnly() -> Persisted {
        Persisted(mode: .emailOnly, step: .email)
    }

    /// The main button: `.next` advances, `.prompt` marks the permission requested, `.finish` completes.
    /// Opening System Settings, quitting, and waiting change nothing here, and neither does the email step's
    /// Continue until the address is saved (`emailSaved()`).
    mutating func perform() {
        switch action {
        case .next: advance()
        case .prompt:
            if case .permission(let permission) = step { persisted.requested.insert(permission) }
        case .finish: persisted.completed = true
        case .submitEmail, .openSettings, .quitAndReopen, .waitForRecording, .waitForDrop: break
        }
    }

    /// The email step's Continue, once the address is saved: on to the first permission not yet granted, past what's
    /// done, as `advance()` decides.
    mutating func emailSaved() {
        if step == .email { advance() }
    }

    /// No address is saved, and the pass in progress is past its email step: an update added the step after this copy
    /// passed where it goes, or the site refused the address. Back to it, since recording waits for an address; after
    /// it, `advance()` skips what's done again. A first run at You're set has nothing else left, so it becomes the
    /// .emailOnly pass rather than show the drop box again.
    mutating func askForEmail() {
        let steps = Self.steps(for: persisted.mode)
        guard !persisted.completed, let email = steps.firstIndex(of: .email), let current = steps.firstIndex(of: step),
              current > email else { return }
        if persisted.mode == .firstRun && step == .done {
            persisted = Self.emailOnly()
        } else {
            persisted.step = .email
        }
    }

    /// At launch, once it's known whether an address is saved (email list design §3.2). A finished copy without one
    /// gets the .emailOnly pass. A first run in progress goes back to the email step without one, and on past it with
    /// one, saved in Settings meanwhile; an .emailOnly pass with one by now is done. Fix permissions… stays as it is.
    mutating func launched(hasAddress: Bool) {
        if persisted.completed {
            if !hasAddress { persisted = Self.emailOnly() }
        } else if !hasAddress {
            askForEmail()
        } else {
            emailSaved()
            if persisted.mode == .emailOnly { persisted.completed = true }
        }
    }

    /// The pill's Open, while recording waits for an address: as at launch, except that a Fix permissions… pass in
    /// progress gives way to the .emailOnly pass, since the person asked for the email.
    mutating func openedForEmail(hasAddress: Bool) {
        if !hasAddress && persisted.mode == .fixPermissions && !persisted.completed {
            persisted = Self.emailOnly()
        } else {
            launched(hasAddress: hasAddress)
        }
    }

    /// "Fix permissions…": a first run or a pass over the permissions in progress stays where it is. Anything else,
    /// an .emailOnly pass in progress included, gives way to a pass over the missing permissions; the email step comes
    /// back with the pill's Open, or at the next launch.
    mutating func fixPermissions(granted: [Permission: Bool]) {
        guard persisted.completed || persisted.mode == .emailOnly else { return }
        self = OnboardingModel(granted: granted, persisted: Self.fixingPermissions(granted: granted))
    }

    /// "Continue" on a permission step: moves on even when the grant can't be confirmed yet.
    mutating func proceed() {
        if case .permission = step { advance() }
    }

    /// "Skip" on the practice run or the drop box.
    mutating func skip() {
        if step == .practice || step == .dropCard { advance() }
    }

    /// Polled permissions. The step showing moves on once its permission is granted, wherever it was granted.
    mutating func update(granted: [Permission: Bool]) {
        self.granted = granted
        if case .permission(let permission) = step, isGranted(permission) { advance() }
    }

    /// A recording was saved: the practice run is done, now or whenever it would have come.
    mutating func recordingSaved() {
        persisted.recorded = true
        if step == .practice { advance() }
    }

    mutating func cardDropped() {
        if step == .dropCard { advance() }
    }

    /// The first launch after Quit & Reopen.
    mutating func relaunched() {
        if step == .reopen { advance() }
    }

    /// The window was closed. The email step and missing permissions come back at the next launch; the practice run,
    /// the drop box, You're set, and Fix permissions… don't.
    mutating func closed() {
        if persisted.mode == .fixPermissions || [.practice, .dropCard, .done].contains(step) {
            persisted.completed = true
        }
    }

    private func isGranted(_ permission: Permission) -> Bool {
        granted[permission] == true
    }

    private func skips(_ step: Step) -> Bool {
        switch step {
        case .permission(let permission): isGranted(permission)
        case .reopen: !needsReopen
        case .practice: persisted.recorded
        case .welcome, .email, .dropCard, .done: false
        }
    }

    /// The next step for the mode that isn't skipped; `.done` is last.
    private mutating func advance() {
        let steps = Self.steps(for: persisted.mode)
        guard let current = steps.firstIndex(of: step) else {
            persisted.step = .done
            return
        }
        persisted.step = steps[(current + 1)...].first { !skips($0) } ?? .done
    }
}
