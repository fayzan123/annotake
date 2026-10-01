import Foundation

/// The first run's rules (spec §3.7): which step shows, what its button does, and where it goes next. One
/// step at a time; permissions that are already granted are never asked for, and nothing waits on a grant
/// that can't be confirmed yet.
struct OnboardingModel: Equatable {
    /// In the order they're asked for: Accessibility applies without a relaunch, so it comes first.
    enum Permission: String, CaseIterable, Codable, Identifiable {
        case accessibility, inputMonitoring, screenRecording

        var id: Self { self }

        /// These apply only after Annotake reopens (M0).
        var needsRelaunch: Bool { self != .accessibility }
    }

    enum Step: Hashable, Codable {
        case welcome, permission(Permission), reopen, practice, dropCard, done
    }

    enum Mode: String, Codable {
        /// A new user: the welcome, the permissions, and a practice run.
        case firstRun
        /// From "Fix permissions…".
        case fixPermissions
    }

    /// What the step's main button does.
    enum Action: Equatable {
        case next, prompt, openSettings, quitAndReopen, waitForRecording, waitForDrop, finish
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

    /// In order. In Stage 2, a sign-in step goes after .welcome.
    static func steps(for mode: Mode) -> [Step] {
        let permissions = Permission.allCases.map(Step.permission)
        switch mode {
        case .firstRun: return [.welcome] + permissions + [.reopen, .practice, .dropCard, .done]
        case .fixPermissions: return permissions + [.reopen, .done]
        }
    }

    /// "Fix permissions…": its own mode, starting at the first permission that's missing.
    static func fixingPermissions(granted: [Permission: Bool]) -> Persisted {
        let missing = Permission.allCases.first { granted[$0] != true }
        return Persisted(mode: .fixPermissions, step: missing.map(Step.permission) ?? .done)
    }

    /// The main button: `.next` advances, `.prompt` marks the permission requested, `.finish` completes.
    /// Opening System Settings, quitting, and waiting change nothing here.
    mutating func perform() {
        switch action {
        case .next: advance()
        case .prompt:
            if case .permission(let permission) = step { persisted.requested.insert(permission) }
        case .finish: persisted.completed = true
        case .openSettings, .quitAndReopen, .waitForRecording, .waitForDrop: break
        }
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

    /// The window was closed. Missing permissions come back at the next launch; the practice run, the drop
    /// box, and Fix permissions… don't.
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
        case .welcome, .dropCard, .done: false
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
