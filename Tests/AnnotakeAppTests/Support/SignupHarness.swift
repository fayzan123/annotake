@testable import AnnotakeApp
import Foundation
import Synchronization
import Testing

/// An EmailSignup for tests: a throwaway UserDefaults suite, a fake post that records each request and answers from a
/// queue, and a fake schedule that keeps each retry for the test to fire. Every test builds its EmailSignup here, the
/// onboarding's, the session controller's, and Settings' too: EmailSignup.post is the app's one network call besides
/// Sparkle's, and no test may make it. EmailSignupTests checks that no other test file builds one.
@MainActor
final class SignupHarness {
    let suite = "annotake-tests-\(UUID())"
    let defaults: UserDefaults
    /// The clock every save reads.
    var now = Date(timeIntervalSinceReferenceDate: 813_456_789.123_456)
    /// What the next posts answer, first to last. A post that finds none left fails the test, unless `holdPost()` holds
    /// it, and is answered sent, so a broken signup can't post again and again.
    var answers: [EmailSendOutcome] = []
    /// Every request posted, first to last.
    private(set) var requests: [URLRequest] = []
    /// Each retry's delay, in the order they were scheduled.
    private(set) var delays: [TimeInterval] = []
    /// Every line logged.
    private(set) var logged: [String] = []
    private var retries: [@MainActor () -> Void] = []
    private var holding = false
    private var held: CheckedContinuation<EmailSendOutcome, Never>?
    private var arrival: Latch?

    init() {
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    deinit {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    /// An EmailSignup on the suite. A second one stands in for the app opened again.
    func makeSignup(appVersion: String = "0.3.0 (120)") -> EmailSignup {
        EmailSignup(defaults: defaults, appVersion: appVersion,
                    post: { [weak self] request in await self?.post(request) ?? .retryLater },
                    schedule: { [weak self] delay, retry in
                        self?.delays.append(delay)
                        self?.retries.append(retry)
                    },
                    now: { [weak self] in self?.now ?? .distantPast },
                    report: { [weak self] line in self?.logged.append(line) })
    }

    /// The record saved under email.v1.
    var stored: EmailRecord? {
        defaults.data(forKey: EmailRecord.storeKey).flatMap { try? JSONDecoder().decode(EmailRecord.self, from: $0) }
    }

    /// Saves `record` under email.v1, as an earlier launch would have.
    func store(_ record: EmailRecord) throws {
        defaults.set(try JSONEncoder().encode(record), forKey: EmailRecord.storeKey)
    }

    /// Runs the retry scheduled `index`th, as its timer would.
    func fire(_ index: Int) {
        guard retries.indices.contains(index) else {
            Issue.record("no retry \(index) was scheduled")
            return
        }
        retries[index]()
    }

    /// Holds the next post that finds no answer queued, and waits for it to arrive. It stays in flight until
    /// `answer(_:)`. If none arrives, the suite's time limit ends the wait, and the test fails.
    func holdPost() async {
        holding = true
        let latch = Latch()
        arrival = latch
        await latch.wait()
        arrival = nil
        if held == nil {
            holding = false
            Issue.record("no post arrived to hold")
        }
    }

    /// Answers the post that's held.
    func answer(_ outcome: EmailSendOutcome) {
        holding = false
        guard let post = held else {
            Issue.record("no post is held")
            return
        }
        held = nil
        post.resume(returning: outcome)
    }

    private func post(_ request: URLRequest) async -> EmailSendOutcome {
        requests.append(request)
        // No test posts anywhere near this often. A signup that does is posting in a loop, whatever it's answered, and
        // awaiting it would never end, so the run stops here, loudly.
        if requests.count > 100 { fatalError("EmailSignup posted \(requests.count) times in one test: a loop") }
        if !answers.isEmpty { return answers.removeFirst() }
        guard holding else {
            Issue.record("a post found no answer queued")
            return .sent
        }
        holding = false
        return await withCheckedContinuation { continuation in
            held = continuation
            arrival?.open()
        }
    }
}

/// A wait that ends once: when `open()` is called, or when the waiting task is cancelled, as a time limit cancels it.
/// A continuation alone would wait forever, and hang the test run.
final class Latch: Sendable {
    private let state = Mutex<(isOpen: Bool, waiter: CheckedContinuation<Void, Never>?)>((false, nil))

    func wait() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let isOpen = state.withLock { state in
                    if !state.isOpen { state.waiter = continuation }
                    return state.isOpen
                }
                if isOpen { continuation.resume() }
            }
        } onCancel: {
            open()
        }
    }

    func open() {
        let waiter = state.withLock { state in
            state.isOpen = true
            defer { state.waiter = nil }
            return state.waiter
        }
        waiter?.resume()
    }
}
