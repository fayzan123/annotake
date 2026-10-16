@testable import AnnotakeApp
import Foundation
import Testing

/// Saving the address and sending it in the background (design §3.4). SignupHarness stands in for the network and the
/// timers, so nothing here posts for real or sleeps: a test waits on `settle()`, or on a post it holds.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct EmailSignupTests {
    /// What /api/subscribe reads from the body.
    struct Body: Decodable, Equatable {
        var email: String
        var news: Bool
        var consent: String
        var appVersion: String
    }

    /// A request's body, which holds the four fields the site reads and nothing else.
    static func body(of request: URLRequest) throws -> Body {
        let data = try #require(request.httpBody)
        let fields = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(fields.keys) == ["email", "news", "consent", "appVersion"])
        return try JSONDecoder().decode(Body.self, from: data)
    }

    static func emails(_ requests: [URLRequest]) throws -> [String] {
        try requests.map { try body(of: $0).email }
    }

    /// The log's line for each outcome: all three it ever writes.
    static func line(_ outcome: EmailSendOutcome) -> String {
        switch outcome {
        case .sent: "email: sent"
        case .invalid: "email: invalid"
        case .retryLater: "email: retry later"
        }
    }

    static let sam = EmailRecord(address: "sam@example.com", news: true, consent: "consent-2026-10-15",
                                 savedAt: Date(timeIntervalSinceReferenceDate: 813_456_789), sent: false)

    // MARK: - Saving, and what each answer does

    /// Continue saves the cleaned address, the choice, and the consent id, unsent, before anything goes over the
    /// network. Then it posts once, in the background.
    @Test func saveStoresTheRecordThenPostsOnce() async throws {
        let harness = SignupHarness()
        let signup = harness.makeSignup()
        var storedAtChange: [EmailRecord?] = []
        signup.onChange = { storedAtChange.append(harness.stored) }
        harness.answers = [.sent]

        signup.save(address: "  Sam@Example.COM ", news: true)

        let saved = EmailRecord(address: "Sam@Example.COM", news: true, consent: "consent-2026-10-15",
                                savedAt: harness.now, sent: false)
        #expect(harness.stored == saved)
        #expect(signup.record == saved)
        #expect(signup.hasAddress)
        #expect(storedAtChange == [saved], "onChange fires once the record is stored")
        #expect(harness.requests.isEmpty, "save returns before the post")
        // Design §3.4's fields, under these names: a rename would lose every saved address.
        let data = try #require(harness.defaults.data(forKey: "email.v1"))
        let fields = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(fields.keys) == ["address", "news", "consent", "savedAt", "sent"])

        await signup.settle()
        try #require(harness.requests.count == 1)
        #expect(try Self.body(of: harness.requests[0])
                == Body(email: "Sam@Example.COM", news: true, consent: "consent-2026-10-15", appVersion: "0.3.0 (120)"))
        #expect(harness.logged == ["email: sent"])
    }

    /// 200: the record stays, marked sent, and nothing more is scheduled.
    @Test func sentMarksTheRecordSent() async {
        let harness = SignupHarness()
        let signup = harness.makeSignup()
        harness.answers = [.sent]
        signup.save(address: "sam@example.com", news: false)
        await signup.settle()

        let sent = EmailRecord(address: "sam@example.com", news: false, consent: EmailConsent.id, savedAt: harness.now,
                               sent: true)
        #expect(harness.stored == sent)
        #expect(signup.record == sent)
        #expect(harness.requests.count == 1)
        #expect(harness.delays.isEmpty)
        #expect(harness.logged == ["email: sent"])
    }

    /// 400: the site refused the address, so it's cleared, on the Mac and in memory, and the email step asks again.
    @Test func invalidClearsTheAddress() async {
        let harness = SignupHarness()
        let signup = harness.makeSignup()
        var hadAddress: [Bool] = []
        var storedAtChange: [EmailRecord?] = []
        signup.onChange = { [weak signup] in
            hadAddress.append(signup?.hasAddress ?? false)
            storedAtChange.append(harness.stored)
        }
        harness.answers = [.invalid]
        signup.save(address: "sam@example.com", news: true)
        await signup.settle()

        #expect(harness.defaults.object(forKey: "email.v1") == nil)
        #expect(signup.record == nil)
        #expect(!signup.hasAddress)
        #expect(hadAddress == [true, false], "onChange after the save, then after the clear")
        #expect(storedAtChange.map { $0 != nil } == [true, false])
        #expect(harness.delays.isEmpty)
        #expect(harness.logged == ["email: invalid"])
    }

    /// No answer, a 429, or a 5xx: tried again after 1 minute, 5 minutes, 30 minutes, then 6 hours, until it goes.
    @Test func retryLaterBacksOffUntilSent() async {
        #expect(EmailSignup.backoff == [60, 300, 1800, 21_600])
        let harness = SignupHarness()
        let signup = harness.makeSignup()
        var changes = 0
        signup.onChange = { changes += 1 }
        harness.answers = [.retryLater, .retryLater, .retryLater, .retryLater, .sent]
        signup.save(address: "sam@example.com", news: false)
        await signup.settle()
        for retry in 0..<4 {
            #expect(harness.stored?.sent == false)
            harness.fire(retry)
            await signup.settle()
        }

        #expect(harness.delays == [60, 300, 1800, 21_600])
        #expect(harness.requests.count == 5)
        #expect(harness.stored?.sent == true)
        #expect(changes == 1, "only the save: a retry later or a sent changes no address")
        #expect(harness.logged == Array(repeating: "email: retry later", count: 4) + ["email: sent"])
    }

    @Test func afterTheFourthFailureEveryRetryWaitsSixHours() async {
        let harness = SignupHarness()
        let signup = harness.makeSignup()
        harness.answers = Array(repeating: .retryLater, count: 7)
        signup.save(address: "sam@example.com", news: false)
        await signup.settle()
        for retry in 0..<6 {
            harness.fire(retry)
            await signup.settle()
        }

        #expect(harness.delays == [60, 300, 1800, 21_600, 21_600, 21_600, 21_600])
        #expect(harness.requests.count == 7)
        #expect(harness.stored?.sent == false)
        #expect(harness.logged == Array(repeating: "email: retry later", count: 7))
    }

    /// Review Focus 3: offline at Continue, online hours later. The first run went on at once; the next launch sends
    /// the address, and the first launch's retry, firing late, reads the record again, finds it sent, and posts
    /// nothing.
    @Test func offlineAtContinueThenOpenedAgainSendsExactlyOnce() async {
        let harness = SignupHarness()
        let first = harness.makeSignup()
        harness.answers = [.retryLater]
        first.save(address: "sam@example.com", news: true)
        await first.settle()
        #expect(harness.delays == [60])

        let second = harness.makeSignup()
        #expect(second.record == harness.stored, "a launch reads the saved address")
        harness.answers = [.sent]
        second.resume()
        await second.settle()
        #expect(harness.requests.count == 2)
        #expect(harness.stored?.sent == true)

        harness.fire(0)
        await first.settle()
        #expect(harness.requests.count == 2, "the late retry posts nothing")
        #expect(first.record?.sent == true)
        #expect(harness.delays == [60])
        #expect(harness.logged == ["email: retry later", "email: sent"])
    }

    /// A launch posts nothing without a saved address, or once the site has it.
    @Test func resumePostsNothingWithoutAnUnsentRecord() async throws {
        let harness = SignupHarness()
        let empty = harness.makeSignup()
        empty.resume()
        await empty.settle()
        #expect(!empty.hasAddress)

        var sent = Self.sam
        sent.sent = true
        try harness.store(sent)
        let opened = harness.makeSignup()
        opened.resume()
        await opened.settle()
        #expect(opened.record == sent)

        #expect(harness.requests.isEmpty)
        #expect(harness.delays.isEmpty)
        #expect(harness.logged.isEmpty)
    }

    // MARK: - Change… in Settings

    /// A new address keeps the choice made in the first run, and is unsent until the site has it (design §3.3).
    @Test func changeKeepsTheChoiceAndPostsTheNewAddress() async throws {
        let harness = SignupHarness()
        let signup = harness.makeSignup()
        var changes = 0
        signup.onChange = { changes += 1 }
        harness.answers = [.sent, .sent]
        signup.save(address: "sam@example.com", news: true)
        await signup.settle()
        harness.now += 3_600

        signup.change(address: "  Kim@Example.org ")

        let changed = EmailRecord(address: "Kim@Example.org", news: true, consent: "consent-2026-10-15",
                                  savedAt: harness.now, sent: false)
        #expect(harness.stored == changed)
        #expect(signup.record == changed)
        #expect(changes == 2)
        await signup.settle()
        try #require(harness.requests.count == 2)
        #expect(try Self.body(of: harness.requests[1])
                == Body(email: "Kim@Example.org", news: true, consent: "consent-2026-10-15", appVersion: "0.3.0 (120)"))
        #expect(harness.stored?.sent == true)
        #expect(harness.logged == ["email: sent", "email: sent"])
    }

    /// The choice goes with the id of the wording it was made under, so the new contact's consent record names what the
    /// person read, even after an update brings new wording. The site keeps every id it ever had.
    @Test func changeKeepsTheWordingTheChoiceWasMadeUnder() async throws {
        let harness = SignupHarness()
        // An earlier version's wording, as a copy updated since would hold it.
        var earlier = Self.sam
        earlier.consent = "consent-2026-01-01"
        earlier.sent = true
        try harness.store(earlier)
        let signup = harness.makeSignup()
        harness.answers = [.sent]

        signup.change(address: "kim@example.org")
        await signup.settle()

        #expect(harness.stored?.consent == "consent-2026-01-01")
        try #require(harness.requests.count == 1)
        #expect(try Self.body(of: harness.requests[0]).consent == "consent-2026-01-01")
        #expect(harness.logged == ["email: sent"])
    }

    /// With nothing saved, a change changes nothing: no store, no post, no onChange. There's no choice to keep, and a
    /// first address comes from the email step, with its notice and box, so its consent record names wording the person
    /// read. Settings offers Add… then, which opens the email step.
    @Test func changeWithNothingSavedChangesNothing() async {
        let harness = SignupHarness()
        let signup = harness.makeSignup()
        var changes = 0
        signup.onChange = { changes += 1 }

        signup.change(address: "kim@example.org")
        await signup.settle()

        #expect(harness.stored == nil)
        #expect(!signup.hasAddress)
        #expect(changes == 0)
        #expect(harness.requests.isEmpty)
        #expect(harness.logged.isEmpty)
    }

    /// The same address, in any capitals or padding, changes nothing: no store, no post, no onChange. The site keys a
    /// contact by its lowercase and can't tell a stored choice sent again from a fresh tick of the box, so sending it
    /// again could opt someone who has since dropped feedback and news back in. The Greek address is one contact on the
    /// site: JavaScript lowercases a Σ that ends a word to ς (checked with node).
    @Test(arguments: zip(["Sam@example.com", "Sam@example.com", "Sam@example.com", "ΟΔΥΣΣΕΥΣ@example.gr"],
                         ["Sam@example.com", "sam@example.com", "  SAM@EXAMPLE.COM\n", "οδυσσευς@example.gr"]))
    func changeToTheSameAddressDoesNothing(_ saved: String, _ same: String) async throws {
        let harness = SignupHarness()
        let signup = harness.makeSignup()
        harness.answers = [.sent]
        signup.save(address: saved, news: true)
        await signup.settle()
        let before = try #require(harness.stored)
        var changes = 0
        signup.onChange = { changes += 1 }
        harness.now += 3_600

        signup.change(address: same)
        await signup.settle()

        #expect(harness.stored == before)
        #expect(signup.record == before)
        #expect(changes == 0)
        #expect(harness.requests.count == 1)
        #expect(harness.logged == ["email: sent"])
    }

    /// Nor does it touch a send waiting on its backoff: that retry still goes.
    @Test func changeToTheSameAddressLeavesItsRetryAlone() async {
        let harness = SignupHarness()
        let signup = harness.makeSignup()
        harness.answers = [.retryLater]
        signup.save(address: "sam@example.com", news: true)
        await signup.settle()

        signup.change(address: "SAM@example.com")
        await signup.settle()
        #expect(harness.requests.count == 1)
        #expect(harness.delays == [60])

        harness.answers = [.sent]
        harness.fire(0)
        await signup.settle()
        #expect(harness.requests.count == 2)
        #expect(harness.stored?.address == "sam@example.com")
        #expect(harness.stored?.sent == true)
        #expect(harness.logged == ["email: retry later", "email: sent"])
    }

    /// A change back to an address the site has already taken from this Mac is saved as sent, and posts nothing: the
    /// site keeps the contact as the person left it. Posted again, sam's stored choice would opt sam back into feedback
    /// and news if sam had dropped it since, under a consent record dated a moment nobody ticked anything.
    @Test func aChangeBackToAnAddressTheSiteHasPostsNothing() async throws {
        let harness = SignupHarness()
        let signup = harness.makeSignup()
        harness.answers = [.sent, .sent]
        signup.save(address: "sam@example.com", news: true)
        await signup.settle()
        signup.change(address: "kim@example.org")
        await signup.settle()
        var changes = 0
        signup.onChange = { changes += 1 }
        harness.now += 3_600

        signup.change(address: "SAM@example.com")
        await signup.settle()

        let back = EmailRecord(address: "SAM@example.com", news: true, consent: EmailConsent.id, savedAt: harness.now,
                               sent: true)
        #expect(harness.stored == back)
        #expect(signup.record == back)
        #expect(changes == 1, "Settings shows the address it changed back to")
        #expect(try Self.emails(harness.requests) == ["sam@example.com", "kim@example.org"])
        #expect(harness.delays.isEmpty)
        #expect(harness.logged == ["email: sent", "email: sent"])
    }

    /// Without a 200, the site may never have had sam: a change back posts sam, with the choice it was saved with.
    @Test func aChangeBackToAnAddressTheSiteNeverTookPostsIt() async throws {
        let harness = SignupHarness()
        let signup = harness.makeSignup()
        harness.answers = [.retryLater, .sent, .sent]
        signup.save(address: "sam@example.com", news: true)
        await signup.settle()
        signup.change(address: "kim@example.org")
        await signup.settle()

        signup.change(address: "sam@example.com")
        await signup.settle()

        #expect(try harness.requests.map { try Self.body(of: $0) } == [
            Body(email: "sam@example.com", news: true, consent: EmailConsent.id, appVersion: "0.3.0 (120)"),
            Body(email: "kim@example.org", news: true, consent: EmailConsent.id, appVersion: "0.3.0 (120)"),
            Body(email: "sam@example.com", news: true, consent: EmailConsent.id, appVersion: "0.3.0 (120)"),
        ])
        #expect(harness.stored?.address == "sam@example.com")
        #expect(harness.stored?.sent == true)
        #expect(harness.logged == ["email: retry later", "email: sent", "email: sent"])
    }

    /// Continue posts every time, even an address the site has: the box was just ticked, or left unticked, so the
    /// choice is a fresh one.
    @Test func aSavePostsEvenAnAddressTheSiteHas() async throws {
        let harness = SignupHarness()
        let signup = harness.makeSignup()
        harness.answers = [.sent, .sent]
        signup.save(address: "sam@example.com", news: false)
        await signup.settle()

        signup.save(address: "sam@example.com", news: true)
        await signup.settle()

        #expect(try harness.requests.map { try Self.body(of: $0).news } == [false, true])
        #expect(harness.stored?.news == true)
        #expect(harness.stored?.sent == true)
        #expect(harness.logged == ["email: sent", "email: sent"])
    }

    /// A 200 that comes back after its record was replaced still means the site has that address. Here kim's post is
    /// in flight when the person changes back to sam: kim's 200 leaves sam's record as it is and posts nothing, and a
    /// change to kim again posts nothing either.
    @Test func aSentAnswerCountsAfterItsRecordWasReplaced() async throws {
        let harness = SignupHarness()
        let signup = harness.makeSignup()
        harness.answers = [.sent]
        signup.save(address: "sam@example.com", news: true)
        await signup.settle()
        signup.change(address: "kim@example.org")
        await harness.holdPost()
        signup.change(address: "sam@example.com")
        let back = try #require(harness.stored)
        #expect(back.sent, "the site has sam")

        harness.answer(.sent)
        await signup.settle()
        #expect(harness.stored == back)
        signup.change(address: "kim@example.org")
        await signup.settle()

        #expect(try Self.emails(harness.requests) == ["sam@example.com", "kim@example.org"])
        #expect(harness.stored?.address == "kim@example.org")
        #expect(harness.stored?.sent == true)
        #expect(harness.logged == ["email: sent", "email: sent"])
    }

    /// The addresses the site has taken are kept on the Mac as their keys' SHA-256, in lowercase hex, under
    /// email.sentKeys.v1: one per contact on the site, and no old address in the clear. A launch reads them.
    @Test func theAddressesTheSiteHasAreKeptAsHashes() async throws {
        let harness = SignupHarness()
        let signup = harness.makeSignup()
        harness.answers = [.sent, .sent]
        signup.save(address: "  Sam@Example.COM ", news: true)
        await signup.settle()
        signup.change(address: "kim@example.org")
        await signup.settle()

        // printf '%s' sam@example.com | shasum -a 256, and the same for kim@example.org.
        #expect(harness.defaults.stringArray(forKey: "email.sentKeys.v1") == [
            "cd25a6171969f2a3c6e35c7667e3908ef1bd2424241db04411a0eec454ca6c16",
            "1b8d24966640ed8bce3bc38740387ac29ec37f665830fb435e29c31e44f2f4f0",
        ])
        // Nothing else is kept: the old address is gone from the record, the one place an address is in the clear.
        let domain = try #require(harness.defaults.persistentDomain(forName: harness.suite))
        #expect(Set(domain.keys) == ["email.v1", "email.sentKeys.v1"])
        #expect(harness.stored?.address == "kim@example.org")

        // The app opened again: a change back to sam posts nothing.
        let reopened = harness.makeSignup()
        reopened.change(address: "sam@example.com")
        await reopened.settle()
        #expect(harness.requests.count == 2)
        #expect(harness.stored?.address == "sam@example.com")
        #expect(harness.stored?.sent == true)
        #expect(harness.logged == ["email: sent", "email: sent"])
    }

    // MARK: - One send at a time

    /// A second save while a post is in flight waits for it, then goes at once: one post each, the newer after.
    @Test func aSaveDuringAPostWaitsForIt() async throws {
        let harness = SignupHarness()
        let signup = harness.makeSignup()
        signup.save(address: "sam@example.com", news: false)
        await harness.holdPost()
        signup.save(address: "kim@example.org", news: true)
        #expect(harness.requests.count == 1, "the newer save waits")

        harness.answers = [.sent]
        harness.answer(.sent)
        await signup.settle()

        #expect(try harness.requests.map { try Self.body(of: $0) } == [
            Body(email: "sam@example.com", news: false, consent: EmailConsent.id, appVersion: "0.3.0 (120)"),
            Body(email: "kim@example.org", news: true, consent: EmailConsent.id, appVersion: "0.3.0 (120)"),
        ])
        #expect(harness.stored == EmailRecord(address: "kim@example.org", news: true, consent: EmailConsent.id,
                                              savedAt: harness.now, sent: true))
        #expect(harness.logged == ["email: sent", "email: sent"])
    }

    /// What a post comes back with belongs to the record it posted. Once a newer one is saved, an older post's 200
    /// never marks it sent, its 400 never clears it, and its retry later never delays it: the newer one goes at once.
    @Test(arguments: [EmailSendOutcome.sent, .invalid, .retryLater])
    func anOlderPostsAnswerLeavesTheNewerRecordAlone(_ older: EmailSendOutcome) async throws {
        let harness = SignupHarness()
        let signup = harness.makeSignup()
        var changes = 0
        signup.onChange = { changes += 1 }
        signup.save(address: "sam@example.com", news: true)
        await harness.holdPost()
        harness.now += 60
        signup.change(address: "kim@example.org")
        let newer = try #require(harness.stored)

        harness.answer(older)
        await harness.holdPost()

        #expect(harness.stored == newer)
        #expect(signup.record == newer)
        #expect(changes == 2, "the save and the change, and no clear")
        #expect(harness.delays.isEmpty)
        #expect(try Self.emails(harness.requests) == ["sam@example.com", "kim@example.org"])
        harness.answer(.retryLater)
        await signup.settle()
        #expect(harness.delays == [60], "the older post's answer doesn't count toward the newer's backoff")
        harness.answers = [.sent]
        harness.fire(0)
        await signup.settle()
        #expect(harness.stored?.sent == true)
        #expect(harness.logged == [Self.line(older), "email: retry later", "email: sent"])
    }

    /// Records are compared whole, not by address: the same address saved again while the first post was in flight is
    /// a new record, and goes again.
    @Test func theSameAddressSavedAgainIsANewRecord() async throws {
        let harness = SignupHarness()
        let signup = harness.makeSignup()
        signup.save(address: "sam@example.com", news: false)
        await harness.holdPost()
        harness.now += 5
        signup.save(address: "sam@example.com", news: false)
        let newer = try #require(harness.stored)

        harness.answer(.sent)
        await harness.holdPost()
        #expect(harness.stored == newer, "the older post doesn't mark it sent")
        harness.answer(.sent)
        await signup.settle()

        #expect(harness.requests.count == 2)
        #expect(harness.stored?.savedAt == newer.savedAt)
        #expect(harness.stored?.sent == true)
        #expect(harness.logged == ["email: sent", "email: sent"])
    }

    // MARK: - The backoff starts over

    /// A save or a change starts the backoff over, and the retries scheduled before it do nothing when they fire.
    /// Otherwise every address typed while offline would keep its own chain of retries.
    @Test(arguments: ["save", "change"])
    func aNewAddressEndsTheRetriesScheduledBeforeIt(_ how: String) async throws {
        let harness = SignupHarness()
        let signup = harness.makeSignup()
        harness.answers = [.retryLater, .retryLater]
        signup.save(address: "sam@example.com", news: false)
        await signup.settle()
        if how == "save" {
            signup.save(address: "kim@example.org", news: false)
        } else {
            signup.change(address: "kim@example.org")
        }
        await signup.settle()
        #expect(harness.delays == [60, 60], "the newer address starts from the first wait")

        harness.fire(0)
        await signup.settle()
        #expect(harness.requests.count == 2, "the older address's retry does nothing")

        harness.answers = [.sent]
        harness.fire(1)
        await signup.settle()
        #expect(try Self.emails(harness.requests) == ["sam@example.com", "kim@example.org", "kim@example.org"])
        #expect(harness.stored?.sent == true)
        #expect(harness.logged == ["email: retry later", "email: retry later", "email: sent"])
    }

    /// A launch starts it over too, from the first wait, and ends the retries scheduled before it.
    @Test func resumeStartsTheBackoffOver() async {
        let harness = SignupHarness()
        let signup = harness.makeSignup()
        harness.answers = [.retryLater, .retryLater, .retryLater]
        signup.save(address: "sam@example.com", news: false)
        await signup.settle()
        harness.fire(0)
        await signup.settle()
        #expect(harness.delays == [60, 300])

        signup.resume()
        await signup.settle()
        #expect(harness.requests.count == 3, "a launch posts at once")
        #expect(harness.delays == [60, 300, 60])

        harness.fire(1)
        await signup.settle()
        #expect(harness.requests.count == 3, "the retry scheduled before the launch does nothing")
        harness.answers = [.sent]
        harness.fire(2)
        await signup.settle()
        #expect(harness.requests.count == 4)
        #expect(harness.stored?.sent == true)
        #expect(harness.logged == Array(repeating: "email: retry later", count: 3) + ["email: sent"])
    }

    /// A retry firing late reads the record again and acts on it as it is now: cleared since, it posts nothing.
    @Test func aLateRetryAfterTheAddressWasClearedPostsNothing() async {
        let harness = SignupHarness()
        let first = harness.makeSignup()
        harness.answers = [.retryLater]
        first.save(address: "sam@example.com", news: false)
        await first.settle()
        let second = harness.makeSignup()
        harness.answers = [.invalid]
        second.resume()
        await second.settle()
        #expect(harness.stored == nil)

        harness.fire(0)
        await first.settle()
        #expect(harness.requests.count == 2)
        #expect(!first.hasAddress)
        #expect(harness.logged == ["email: retry later", "email: invalid"])
    }

    /// Replaced since by an address not yet sent, it posts that one.
    @Test func aLateRetryAfterTheAddressWasReplacedPostsTheNewOne() async throws {
        let harness = SignupHarness()
        let first = harness.makeSignup()
        harness.answers = [.retryLater]
        first.save(address: "sam@example.com", news: false)
        await first.settle()
        let second = harness.makeSignup()
        harness.answers = [.retryLater]
        second.save(address: "kim@example.org", news: true)
        await second.settle()
        #expect(harness.delays == [60, 60])

        harness.answers = [.sent]
        harness.fire(0)
        await first.settle()
        #expect(try Self.emails(harness.requests) == ["sam@example.com", "kim@example.org", "kim@example.org"])
        #expect(harness.stored?.address == "kim@example.org")
        #expect(harness.stored?.sent == true)
        #expect(first.record == harness.stored)

        harness.fire(1)
        await second.settle()
        #expect(harness.requests.count == 3, "the second's own retry finds it sent")
        #expect(harness.logged == ["email: retry later", "email: retry later", "email: sent"])
    }

    // MARK: - The log

    /// The log says how each post went, in one of three lines, and never which address.
    @Test func noLogLineHoldsTheAddress() async {
        let harness = SignupHarness()
        let signup = harness.makeSignup()
        let addresses = ["first.person@example.com", "Second.Person@Example.org", "third+annotake@example.net"]
        harness.answers = [.invalid, .retryLater, .sent]
        signup.save(address: addresses[0], news: true)
        await signup.settle()
        signup.save(address: addresses[1], news: false)
        await signup.settle()
        signup.change(address: addresses[2])
        await signup.settle()

        #expect(harness.logged == [EmailSendOutcome.invalid, .retryLater, .sent].map(Self.line))
        for line in harness.logged {
            for address in addresses {
                let local = String(address.prefix { $0 != "@" })
                #expect(!line.localizedCaseInsensitiveContains(local), "\(line)")
            }
        }
    }

    // MARK: - The request

    /// A POST of the four fields (design §3.4), and nothing else about the Mac. URLSession's own User-Agent would name
    /// the CFNetwork and Darwin versions, its Accept-Language the region, and a cookie the site set would come back, so
    /// the request sets its own headers and turns cookies off. Every header it sets is pinned here.
    @Test func theRequestSendsTheFourFieldsAndNothingAboutTheMac() throws {
        let request = EmailSignup.request(for: Self.sam, appVersion: "0.3.0 (120)")
        #expect(EmailSignup.endpoint.absoluteString == "https://annotake.app/api/subscribe")
        #expect(request.url == EmailSignup.endpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.timeoutInterval == 10)
        #expect(!request.httpShouldHandleCookies)
        #expect(request.allHTTPHeaderFields == [
            "Content-Type": "application/json", "User-Agent": "Annotake/0.3.0 (120)", "Accept-Language": "en",
        ])
        let json = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(json == #"{"appVersion":"0.3.0 (120)","consent":"consent-2026-10-15","email":"sam@example.com","#
                + #""news":true}"#)
    }

    /// The site can't read a request with an appVersion over 32 UTF-16 code units, so it would never take the address:
    /// a longer version is cut to fit, never through a code point.
    @Test func aVersionTooLongForTheSiteIsCut() throws {
        let long = "1.0.0-beta.2 (" + String(repeating: "9", count: 40) + ")"
        let request = EmailSignup.request(for: Self.sam, appVersion: long)
        let cut = String(long.prefix(32))
        #expect(try Self.body(of: request).appVersion == cut)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Annotake/\(cut)")
        // An emoji is two code units: one that would end past 32 is left out whole.
        let straddling = String(repeating: "1", count: 31) + "\u{1F600}"
        #expect(try Self.body(of: EmailSignup.request(for: Self.sam, appVersion: straddling)).appVersion
                == String(repeating: "1", count: 31))
        let fitting = String(repeating: "1", count: 30) + "\u{1F600}"
        #expect(try Self.body(of: EmailSignup.request(for: Self.sam, appVersion: fitting)).appVersion == fitting)
    }

    /// The limit is subscribe.js's own.
    @Test func theVersionLimitIsTheSites() throws {
        let url = try EmailConsentTests.repositoryRoot().appending(path: "site/api/subscribe.js")
        let source = try String(contentsOf: url, encoding: .utf8)
        #expect(EmailSignup.maxAppVersionLength == 32)
        #expect(source.contains("export const MAX_APP_VERSION_LENGTH = \(EmailSignup.maxAppVersionLength);"))
    }

    /// 200 is sent, and 400, the site's answer to an address it won't take, invalid. Anything else is retry later: the
    /// site's 422 for a request it can't read (a consent id from an app newer than the deployment), its 429 and 502,
    /// Vercel's 504, or no answer.
    @Test func theOutcomeFollowsTheStatus() {
        #expect(EmailSignup.outcome(status: 200) == .sent)
        #expect(EmailSignup.outcome(status: 400) == .invalid)
        for status in [nil, 201, 204, 301, 403, 404, 405, 422, 429, 500, 502, 503, 504] as [Int?] {
            #expect(EmailSignup.outcome(status: status) == .retryLater, "\(String(describing: status))")
        }
    }

    /// A post that throws, for a timeout or no network, is retry later, so an offline Continue keeps the address. The
    /// test hands outcome(of:) its answers: none may reach EmailSignup.post, which goes over the network.
    @Test func aPostThatThrowsIsRetryLater() async throws {
        for code in [URLError.Code.notConnectedToInternet, .timedOut, .cannotFindHost, .networkConnectionLost] {
            #expect(await EmailSignup.outcome { throw URLError(code) } == .retryLater, "\(code.rawValue)")
        }
        let url = EmailSignup.endpoint
        let answers: [(Int, EmailSendOutcome)] = [(200, .sent), (400, .invalid), (429, .retryLater), (504, .retryLater)]
        for (status, outcome) in answers {
            let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                                        headerFields: nil))
            #expect(await EmailSignup.outcome { response } == outcome, "\(status)")
        }
        // An answer that isn't HTTP has no status.
        let plain = URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        #expect(await EmailSignup.outcome { plain } == .retryLater)
    }

    // MARK: - Storage

    /// A post's answer applies only while the saved record is the one it posted, compared as decoded. So a record must
    /// come back from its JSON equal, its date included.
    @Test func aRecordSurvivesItsJSONRoundTrip() throws {
        let dates = [Date(), Date(timeIntervalSinceReferenceDate: 813_456_789.123_456_7),
                     Date(timeIntervalSince1970: 0.1)]
        for savedAt in dates {
            let record = EmailRecord(address: "j\u{FC}rgen@m\u{FC}ller.de", news: true, consent: EmailConsent.id,
                                     savedAt: savedAt, sent: false)
            #expect(try JSONDecoder().decode(EmailRecord.self, from: JSONEncoder().encode(record)) == record)
        }
    }

    /// Unreadable data under email.v1 reads as no address, so the email step asks again.
    @Test func anUnreadableRecordReadsAsNone() async {
        let harness = SignupHarness()
        harness.defaults.set(Data("junk".utf8), forKey: "email.v1")
        let signup = harness.makeSignup()
        #expect(!signup.hasAddress)
        signup.resume()
        await signup.settle()
        #expect(harness.requests.isEmpty)
        #expect(harness.logged.isEmpty)
    }

    // MARK: - The real timer, and tests never post

    /// The real backoff timer: one shot on the main run loop, after its delay. A timer due at half the delay fires
    /// first, however busy the main thread is, since due timers fire in order. A repeating timer would fire again
    /// before a later one does.
    @Test func theDefaultScheduleFiresOnceAfterItsDelay() async {
        let fired = Locked<[String]>([])
        let done = Latch()
        Timer.onMainRunLoop(interval: 0.1, repeats: false) { _ in fired.value.append("half") }
        EmailSignup.schedule(after: 0.2) {
            fired.value.append("retry")
            done.open()
        }
        await done.wait()
        let later = Latch()
        EmailSignup.schedule(after: 0.6) { later.open() }
        await later.wait()
        #expect(fired.value == ["half", "retry"])
    }

    /// EmailSignup.post goes over the network, so every test builds its EmailSignup with SignupHarness, which passes
    /// its own post.
    @Test func onlyTheHarnessBuildsAnEmailSignup() throws {
        let tests = try EmailConsentTests.repositoryRoot().appending(path: "Tests")
        let files = try #require(FileManager.default.enumerator(at: tests, includingPropertiesForKeys: nil))
        var builders: [String] = []
        for case let url as URL in files
        where url.pathExtension == "swift" && url.lastPathComponent != "SignupHarness.swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            // \b, so that this test's own name doesn't count.
            if text.range(of: #"\bEmailSignup\s*(\.init\s*)?\("#, options: .regularExpression) != nil {
                builders.append(url.lastPathComponent)
            }
        }
        #expect(builders.isEmpty, "\(builders)")
    }
}
