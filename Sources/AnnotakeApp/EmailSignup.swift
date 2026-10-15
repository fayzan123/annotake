import Combine
import CryptoKit
import Foundation

/// The address the email step saved and the choice made with it (design §3.4), kept as JSON in UserDefaults under
/// `storeKey`. `consent` is the id of the wording the choice was made under; `sent` turns true once the site has it.
struct EmailRecord: Codable, Equatable {
    var address: String
    var news: Bool
    var consent: String
    var savedAt: Date
    var sent: Bool
    static let storeKey = "email.v1"
}

/// How one post to /api/subscribe went.
enum EmailSendOutcome: Equatable {
    case sent, invalid, retryLater
}

/// Saves the email step's address on the Mac, then sends it to /api/subscribe in the background (design §3.4), so the
/// app never waits on the network. Until the site takes the address (200) or refuses it (400), it's posted again on a
/// backoff and at each launch, one post at a time. This is the app's one network call besides Sparkle's update check,
/// and only the app itself makes it: tests pass their own `post`, and --selftest and --render-ui never post.
@MainActor
final class EmailSignup: ObservableObject {
    nonisolated static let endpoint = URL(string: "https://annotake.app/api/subscribe")!
    /// The waits after the 1st, 2nd, 3rd, and 4th failure in a row. Every later one waits the last.
    static let backoff: [TimeInterval] = [60, 300, 1800, 21_600]
    /// subscribe.js's MAX_APP_VERSION_LENGTH, in UTF-16 code units. The site answers 400 for a longer version, and a
    /// 400 clears the address, so the request cuts it to fit.
    nonisolated static let maxAppVersionLength = 32
    /// Where the addresses the site has taken from this Mac are kept, each as its key's SHA-256 in lowercase hex.
    static let sentStoreKey = "email.sentKeys.v1"

    /// The record as last saved or read.
    @Published private(set) var record: EmailRecord?
    var hasAddress: Bool { record != nil }
    /// Fired after a save or a change is stored, and after the site refuses an address and it's cleared: for the
    /// controller and the onboarding.
    var onChange: (() -> Void)?

    private let defaults: UserDefaults
    private let appVersion: String
    private let post: (URLRequest) async -> EmailSendOutcome
    private let schedule: (TimeInterval, @escaping @MainActor () -> Void) -> Void
    private let now: () -> Date
    private let report: (String) -> Void
    /// The post in flight. There's never more than one: a newer record waits for it.
    private var sending: Task<Void, Never>?
    /// Posts in a row that came back retry later, counted from the last save, change, or launch.
    private var failures = 0
    /// Moved on by every save, change, and launch, so the retries scheduled before it do nothing when they fire.
    private var generation = 0

    init(defaults: UserDefaults, appVersion: String = AppVersion.current.description,
         post: @escaping (URLRequest) async -> EmailSendOutcome = EmailSignup.post,
         schedule: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void = EmailSignup.schedule,
         now: @escaping () -> Date = Date.init, report: @escaping (String) -> Void = { log($0) }) {
        self.defaults = defaults
        self.appVersion = appVersion
        self.post = post
        self.schedule = schedule
        self.now = now
        self.report = report
        record = stored
    }

    /// Continue in the email step: saves the cleaned address and the box's choice under today's wording, then sends,
    /// even an address the site has: the box was just ticked, or left unticked, again.
    func save(address: String, news: Bool) {
        replace(with: EmailRecord(address: EmailConsent.clean(address), news: news, consent: EmailConsent.id,
                                  savedAt: now(), sent: false))
    }

    /// Change… in Settings: a new address, sent with the choice already made and the id of the wording it was made
    /// under (design §3.3). The site can't tell a stored choice sent again from a fresh tick of the box, so it must
    /// never get one for an address it has: it would opt someone who has since dropped feedback and news back in. So
    /// the same address, in any capitals or padding, changes nothing, and one the site has taken from this Mac before,
    /// as when someone changes back, is saved as sent and never posted.
    func change(address: String) {
        let current = stored
        if let current, EmailConsent.key(current.address) == EmailConsent.key(address) { return }
        replace(with: EmailRecord(address: EmailConsent.clean(address), news: current?.news ?? false,
                                  consent: current?.consent ?? EmailConsent.id, savedAt: now(),
                                  sent: sentHashes.contains(Self.sentHash(address))))
    }

    /// At launch: sends a saved address the site doesn't have yet.
    func resume() {
        restart()
    }

    /// Waits for the post in flight, and any it starts as it returns. Tests use it in place of sleeping.
    func settle() async {
        while let sending {
            await sending.value
        }
    }

    // MARK: - Sending

    private func replace(with record: EmailRecord) {
        store(record)
        onChange?()
        restart()
    }

    /// Starts the backoff over, then sends.
    private func restart() {
        generation += 1
        failures = 0
        send()
    }

    /// Posts the record as saved, unless it's sent or a post is in flight: that one reads the record again when it
    /// returns. Every decision reads UserDefaults again, since another EmailSignup on them, the app opened again, may
    /// have sent, cleared, or replaced the record.
    private func send() {
        let current = stored
        if record != current { record = current }
        guard sending == nil, let current, !current.sent else { return }
        let request = Self.request(for: current, appVersion: appVersion)
        sending = Task {
            let outcome = await post(request)
            finish(current, outcome)
        }
    }

    /// Applies a post's outcome only while the record it posted is still the one saved, compared whole, as decoded: the
    /// same address saved again is a new record. Otherwise the outcome belongs to an older record, and the newer one
    /// goes at once.
    private func finish(_ posted: EmailRecord, _ outcome: EmailSendOutcome) {
        sending = nil
        report("email: \(Self.logName(outcome))")
        // The site has the address, even when a newer record has replaced the one posted.
        if outcome == .sent { remember(posted.address) }
        guard stored == posted else {
            send()
            return
        }
        switch outcome {
        case .sent:
            var record = posted
            record.sent = true
            store(record)
        case .invalid:
            store(nil)
            onChange?()
        case .retryLater:
            failures += 1
            let scheduled = generation
            schedule(Self.backoff[min(failures, Self.backoff.count) - 1]) { [weak self] in
                guard let self, generation == scheduled else { return }
                send()
            }
        }
    }

    /// The log's words for an outcome. The log never holds the address.
    private static func logName(_ outcome: EmailSendOutcome) -> String {
        switch outcome {
        case .sent: "sent"
        case .invalid: "invalid"
        case .retryLater: "retry later"
        }
    }

    // MARK: - Storage

    /// The record in UserDefaults. Unreadable data reads as none, so the email step asks again.
    private var stored: EmailRecord? {
        defaults.data(forKey: EmailRecord.storeKey).flatMap { try? JSONDecoder().decode(EmailRecord.self, from: $0) }
    }

    /// Saves `record`, or clears it with nil, and keeps `record` to what was saved, as decoded.
    private func store(_ record: EmailRecord?) {
        if let record {
            guard let data = try? JSONEncoder().encode(record) else { return }
            defaults.set(data, forKey: EmailRecord.storeKey)
        } else {
            defaults.removeObject(forKey: EmailRecord.storeKey)
        }
        self.record = stored
    }

    /// The addresses the site has taken from this Mac, as `sentHash`es. Unreadable data reads as none.
    private var sentHashes: [String] {
        defaults.stringArray(forKey: Self.sentStoreKey) ?? []
    }

    /// Adds the address's `sentHash` to `sentHashes`.
    private func remember(_ address: String) {
        let hashes = sentHashes, hash = Self.sentHash(address)
        if !hashes.contains(hash) { defaults.set(hashes + [hash], forKey: Self.sentStoreKey) }
    }

    /// The address's key as SHA-256, in lowercase hex: one per contact on the site, and no old address in the clear.
    private static func sentHash(_ address: String) -> String {
        SHA256.hash(data: Data(EmailConsent.key(address).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - The request

    /// The POST to /api/subscribe: the address, the choice, the consent id, and the app's version, and nothing else
    /// about the Mac (design §3.4). URLSession's own User-Agent would name the CFNetwork and Darwin versions and its
    /// Accept-Language the region, so the request sets both, and it neither sends nor keeps cookies.
    nonisolated static func request(for record: EmailRecord, appVersion: String) -> URLRequest {
        let version = fitted(appVersion)
        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Annotake/\(version)", forHTTPHeaderField: "User-Agent")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        request.httpBody = try? encoder.encode(SubscribeBody(email: record.address, news: record.news,
                                                            consent: record.consent, appVersion: version))
        return request
    }

    /// The version cut to `maxAppVersionLength` code units, as JavaScript counts them, never through a code point.
    private nonisolated static func fitted(_ appVersion: String) -> String {
        var fitted = String.UnicodeScalarView()
        var units = 0
        for scalar in appVersion.unicodeScalars {
            units += scalar.utf16.count
            guard units <= maxAppVersionLength else { break }
            fitted.append(scalar)
        }
        return String(fitted)
    }

    /// The post itself, over URLSession.
    nonisolated static func post(_ request: URLRequest) async -> EmailSendOutcome {
        await outcome { try await URLSession.shared.data(for: request).1 }
    }

    /// What a post's answer comes to. A thrown error, a timeout or no network, is retry later, so an offline Continue
    /// keeps the address. Tests hand it their own answers, since none may reach `post`.
    nonisolated static func outcome(of answer: @Sendable () async throws -> URLResponse) async -> EmailSendOutcome {
        do {
            let response = try await answer()
            return outcome(status: (response as? HTTPURLResponse)?.statusCode)
        } catch {
            return .retryLater
        }
    }

    /// 200 is sent and 400 invalid. Anything else (the site's 429 and 502, Vercel's 504, or no status) is retry later.
    nonisolated static func outcome(status: Int?) -> EmailSendOutcome {
        switch status {
        case 200: .sent
        case 400: .invalid
        default: .retryLater
        }
    }

    /// A one-shot timer on the main run loop, as the pill's messages use.
    nonisolated static func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        Timer.onMainRunLoop(interval: delay, repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
    }
}

/// The request's body: what /api/subscribe reads, and nothing more.
private struct SubscribeBody: Encodable {
    var email: String
    var news: Bool
    var consent: String
    var appVersion: String
}
