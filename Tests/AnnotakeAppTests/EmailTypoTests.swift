@testable import AnnotakeApp
import Testing

/// "Did you mean …?" under the email field (Checkpoint 5): likely typos of common providers' domains, and nothing else,
/// since a wrong hint is worse than none.
struct EmailTypoTests {
    @Test(arguments: [
        ("sam@gmial.com", "sam@gmail.com"),
        ("sam@gamil.com", "sam@gmail.com"),
        ("sam@gmai.com", "sam@gmail.com"),
        ("sam@gmaill.com", "sam@gmail.com"),
        ("sam@gmail.con", "sam@gmail.com"),
        ("sam@gmail.co", "sam@gmail.com"),
        ("sam@gmail.cm", "sam@gmail.com"),
        ("sam@hotmial.com", "sam@hotmail.com"),
        ("sam@hotmal.ca", "sam@hotmail.ca"),
        ("sam@outlok.com", "sam@outlook.com"),
        ("sam@iclod.com", "sam@icloud.com"),
        ("sam@icloud.cmo", "sam@icloud.com"),
        ("sam@yaho.com", "sam@yahoo.com"),
        ("sam@protn.me", "sam@proton.me"),
    ])
    func aLikelyTypoGetsTheDomainItMeans(_ typed: String, _ meant: String) {
        #expect(EmailTypo.suggestion(for: typed) == meant)
    }

    /// Trimmed, and otherwise as typed: the name and its capitals are the person's own.
    @Test func theNameStaysAsTyped() {
        #expect(EmailTypo.suggestion(for: "  Sam.Lee+notes@GMIAL.COM ") == "Sam.Lee+notes@gmail.com")
    }

    /// A provider's own domain in any capitals, its regional ones, the domains a letter from gmail.com, a short name a
    /// letter off (usually some other company's), and every other domain.
    @Test(arguments: [
        "sam@gmail.com", "Sam@Gmail.COM", "sam@hotmail.ca", "sam@hotmail.co.uk", "sam@yahoo.ca", "sam@me.com",
        "sam@mail.com", "sam@email.com", "sam@ymail.com", "sam@protonmail.ch", "sam@mc.com", "sam@liv.com",
        "sam@acme.com", "sam@uwaterloo.ca", "sam@gmail.co.uk",
    ])
    func aKnownOrUnrelatedDomainGetsNone(_ typed: String) {
        #expect(EmailTypo.suggestion(for: typed) == nil)
    }

    /// What the site wouldn't take gets no hint: Continue, greyed out, says enough.
    @Test(arguments: ["", "sam", "sam@", "sam@gmail", "sam@@gmial.com", "@gmial.com"])
    func anAddressTheSiteWouldntTakeGetsNone(_ typed: String) {
        #expect(EmailTypo.suggestion(for: typed) == nil)
    }

    /// Only the two fields' own lines show the hint, and no test types in them. Without these lines, no one would see
    /// it, and every other test would still pass.
    @Test func theEmailStepAndChangeSuggest() throws {
        let step = try PillTextTests.sourceLines("Sources/AnnotakeApp/Onboarding.swift")
        let sheet = try PillTextTests.sourceLines("Sources/AnnotakeApp/SettingsWindow.swift")
        #expect(step.contains("SuggestingEmailField(draft: $viewModel.emailDraft) {"), "the email step")
        #expect(sheet.contains("SuggestingEmailField(draft: $change.draft) {"), "Change…")
    }

    @Test func distanceCountsEachEditAndASwapAsOne() {
        #expect(EmailTypo.distance("gmail", "gmail") == 0)
        #expect(EmailTypo.distance("gmial", "gmail") == 1)
        #expect(EmailTypo.distance("hotmal", "hotmail") == 1)
        #expect(EmailTypo.distance("gmaill", "gmail") == 1)
        #expect(EmailTypo.distance("gnail", "gmail") == 1)
        #expect(EmailTypo.distance("email", "gmail") == 1)
        #expect(EmailTypo.distance("", "abc") == 3)
        #expect(EmailTypo.distance("ab", "") == 2)
    }
}
