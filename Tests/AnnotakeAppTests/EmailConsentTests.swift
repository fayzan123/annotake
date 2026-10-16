@testable import AnnotakeApp
import Foundation
import Testing

/// The email step's wording, checked against the site's consent.json, and its address check, case for case against the
/// site's email.js (site/tests/unit/email.test.js). The app must accept exactly what /api/subscribe accepts: an address
/// the site turns away would be cleared, asked for again, and turned away again.
struct EmailConsentTests {
    /// site/api/_lib/consent.json: the consent id in use, and each version's wording. Only a version that asks for
    /// consent has a box.
    struct SiteConsent: Decodable {
        struct Version: Decodable {
            var title, notice, footer: String
            var box: String?
        }
        var current: String
        var versions: [String: Version]
    }

    /// The repository's root: the nearest folder above this file that holds Package.swift.
    static func repositoryRoot() throws -> URL {
        let folders = sequence(first: URL(fileURLWithPath: #filePath).deletingLastPathComponent()) { folder in
            folder.pathComponents.count > 1 ? folder.deletingLastPathComponent() : nil
        }
        let root = folders.first { FileManager.default.fileExists(atPath: $0.appending(path: "Package.swift").path) }
        return try #require(root, "no Package.swift above \(#filePath)")
    }

    @Test func wordingMatchesTheSite() throws {
        let url = try Self.repositoryRoot().appending(path: "site/api/_lib/consent.json")
        let site = try JSONDecoder().decode(SiteConsent.self, from: Data(contentsOf: url))
        #expect(site.current == EmailConsent.id)
        let version = try #require(site.versions[EmailConsent.id])
        // The site writes ’, the app a straight '.
        func straight(_ text: String) -> String { text.replacingOccurrences(of: "’", with: "'") }
        #expect(straight(version.title) == EmailConsent.title)
        #expect(straight(version.notice) == EmailConsent.notice)
        // The step has no box: until the list has a mailing address, it asks for no consent (design §13).
        #expect(version.box == nil)
        // The site's footer ends with the link's words; the app shows them as a Link after its footer.
        #expect(version.footer == EmailConsent.footer + " Privacy policy")
        #expect(EmailConsent.privacyURL.absoluteString == "https://annotake.app/privacy")
    }

    // MARK: - The address check, case for case from site/tests/unit/email.test.js

    @Test(arguments: [
        "sam@example.com", "  Sam@Example.COM ", "sam+annotake@gmail.com", "j\u{FC}rgen@m\u{FC}ller.de", "用户@例子.广告",
        "a@b.co",
    ])
    func realAddressesAreAccepted(_ address: String) {
        #expect(EmailConsent.isPlausible(address))
    }

    // email.test.js also rejects null and undefined, which have no Swift counterpart: isPlausible takes a String.
    @Test(arguments: [
        "", "sam", "sam@", "@example.com",
        "sam@example", "sam@@example.com", "sam@exa mple.com",
        "sam@example.com\r\nBcc: x@y.z",
        "sam@.example.com", "sam@example.", "sam@example..com",
        "\(repeated("a", 64))@\(repeated("b", 186)).com",
        "\(repeated("a", 65))@example.com",
        "sam@exam\u{0}ple.com", "sam@example.com\u{7F}",
        "sam\u{A0}@example.com",  // a no-break space
    ])
    func whatIsNotAnAddressIsRejected(_ address: String) {
        #expect(!EmailConsent.isPlausible(address))
    }

    @Test func lengthLimitsSitAt254AndA64CharacterLocalPart() {
        let at254 = "\(repeated("a", 64))@\(repeated("b", 185)).com"
        #expect(at254.utf16.count == 254)
        #expect(EmailConsent.isPlausible(at254))
        #expect(!EmailConsent.isPlausible("\(repeated("a", 64))@\(repeated("b", 186)).com"), "255 characters")
        #expect(EmailConsent.isPlausible("\(repeated("a", 64))@example.com"), "a 64-character local part")
    }

    // email.test.js also cleans null and undefined to "", which have no Swift counterpart.
    @Test func cleanTrimsAndComposesAccentsIntoOneForm() {
        #expect(EmailConsent.clean("  sam@example.com\n") == "sam@example.com")
        #expect(scalars(EmailConsent.clean("ju\u{308}rgen@mu\u{308}ller.de")) == scalars("j\u{FC}rgen@m\u{FC}ller.de"))
        #expect(EmailConsent.clean(" \n\u{3000}") == "")
    }

    /// The addresses of email.test.js's emailKey tests. /api/subscribe checks each address's key as well as the
    /// address, and every one of these passes both.
    @Test(arguments: [
        "  Sam@Example.COM ", "J\u{DC}RGEN@M\u{DC}LLER.DE", "ju\u{308}rgen@mu\u{308}ller.de",
        "j\u{FC}rgen@m\u{FC}ller.de", "用户@例子.广告",
        // Capitals with a mark that composes only once they're small, and İ with a mark below.
        "J\u{30C}ohn@example.com", "H\u{331}ana@example.com", "T\u{308}om@example.com", "W\u{30A}ill@example.com",
        "Y\u{30A}ara@example.com", "\u{130}\u{331}sa@example.com",
    ])
    func emailKeyAddressesAreAccepted(_ address: String) {
        #expect(EmailConsent.isPlausible(address))
    }

    // MARK: - The key, case for case from email.test.js's emailKey tests

    /// /api/subscribe keeps a contact under the address's key, so EmailSignup compares keys to tell a changed address
    /// from the same one retyped.
    @Test func keyMakesOneKeyPerAddressWhateverTheCapitalsOrTheAccentsEncoding() {
        #expect(EmailConsent.key("  Sam@Example.COM ") == "sam@example.com")
        #expect(scalars(EmailConsent.key("J\u{DC}RGEN@M\u{DC}LLER.DE"))
                == scalars(EmailConsent.key("ju\u{308}rgen@mu\u{308}ller.de")))
    }

    @Test(arguments: [
        "  Sam@Example.COM ", "j\u{FC}rgen@m\u{FC}ller.de", "J\u{DC}RGEN@M\u{DC}LLER.DE", "用户@例子.广告",
        // Capitals with a mark that composes only once they're small: ǰ, ẖ, ẗ, ẘ, and ẙ.
        "J\u{30C}ohn@example.com", "H\u{331}ana@example.com", "T\u{308}om@example.com", "W\u{30A}ill@example.com",
        "Y\u{30A}ara@example.com",
        // İ lowercases to i and a dot above, which then belongs after a mark below.
        "\u{130}\u{331}sa@example.com",
    ])
    func aKeysKeyIsItself(_ address: String) {
        let key = EmailConsent.key(address)
        #expect(scalars(EmailConsent.key(key)) == scalars(key))
        #expect(scalars(key) == scalars(nfc(key)), "keys to NFC")
    }

    /// J and a combining caron have no composed capital, but small they compose to ǰ (U+01F0). İ lowercases to i and a
    /// dot above, as JavaScript's toLowerCase has it (checked with node).
    @Test func keyComposesAfterLowercasing() {
        #expect(scalars(EmailConsent.key("J\u{30C}ohn@example.com")) == scalars("\u{1F0}ohn@example.com"))
        #expect(scalars(EmailConsent.key("\u{130}sa@example.com")) == scalars("i\u{307}sa@example.com"))
    }

    /// JavaScript lowercases a Σ that ends a word to ς, and any other to σ; Swift's lowercased() writes σ for both. The
    /// key lowercases as JavaScript does, so a Greek address in capitals and in small letters is one contact, as on the
    /// site (each checked with node).
    @Test func keyLowercasesAFinalSigmaAsJavaScriptDoes() {
        #expect(scalars(EmailConsent.key("ΟΔΥΣΣΕΥΣ@example.gr")) == scalars("οδυσσευς@example.gr"))
        #expect(scalars(EmailConsent.key("οδυσσευς@example.gr")) == scalars("οδυσσευς@example.gr"))
        // Accents and dots are looked past: ΑΣ́ still ends a word, and ΣΑΜΟΣ goes on through the dot to Π.
        #expect(scalars(EmailConsent.key("ΑΣ\u{301}@example.gr")) == scalars("ας\u{301}@example.gr"))
        #expect(scalars(EmailConsent.key("ΣΑΜΟΣ.Π@example.gr")) == scalars("σαμοσ.π@example.gr"))
        // A Σ with no letter before it isn't a word's end.
        #expect(scalars(EmailConsent.key("Σ@example.gr")) == scalars("σ@example.gr"))
    }

    // MARK: - Where Swift's defaults differ from JavaScript's (every answer here checked against email.js with node)

    /// What JavaScript's trim() takes off the ends and its \s matches, as Node 22 lists them: ECMAScript's WhiteSpace
    /// and LineTerminator. Foundation's .whitespacesAndNewlines and Character.isWhitespace differ: both lack U+FEFF and
    /// have U+0085.
    static let javaScriptWhitespace: [UInt32] = [0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680]
        + Array(0x2000...0x200A) + [0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF]

    @Test func trimsAndRejectsJavaScriptsWhitespaceExactly() throws {
        for value in Self.javaScriptWhitespace {
            let space = String(try #require(Unicode.Scalar(value)))
            let around = "\(space)sam@example.com\(space)"
            #expect(EmailConsent.clean(around) == "sam@example.com", "U+\(hex(value)) around")
            #expect(EmailConsent.isPlausible(around), "U+\(hex(value)) around")
            #expect(!EmailConsent.isPlausible("sam@exam\(space)ple.com"), "U+\(hex(value)) inside")
        }
        let controls: [UInt32] = Array(0x00...0x1F) + [0x7F]
        for value in controls {
            let control = String(try #require(Unicode.Scalar(value)))
            #expect(!EmailConsent.isPlausible("sam@exam\(control)ple.com"), "U+\(hex(value)) inside")
        }
        // U+0085 is neither trimmed nor rejected: it stays, and counts toward the 254.
        #expect(scalars(EmailConsent.clean("sam@example.com\u{85}")).last == 0x85)
        #expect(EmailConsent.isPlausible("\(repeated("a", 64))@\(repeated("b", 184)).com\u{85}"), "254 with U+0085")
        #expect(!EmailConsent.isPlausible("\(repeated("a", 64))@\(repeated("b", 185)).com\u{85}"), "255 with U+0085")
    }

    /// JavaScript's .length counts UTF-16 code units, not Characters: an emoji counts twice, and a flag four times.
    @Test func countsLengthsInUTF16CodeUnits() {
        let grinning = "\u{1F600}", canada = "\u{1F1E8}\u{1F1E6}"
        #expect(EmailConsent.isPlausible("\(repeated("a", 62))\(grinning)@example.com"), "a 64-unit local part")
        #expect(!EmailConsent.isPlausible("\(repeated("a", 63))\(grinning)@example.com"), "a 65-unit local part")
        #expect(EmailConsent.isPlausible("\(repeated("a", 60))\(canada)@example.com"), "a 64-unit local part")
        #expect(!EmailConsent.isPlausible("\(repeated("a", 61))\(canada)@example.com"), "a 65-unit local part")
        #expect(EmailConsent.isPlausible("\(repeated("a", 64))@\(repeated("b", 183))\(grinning).com"), "254 units")
        #expect(!EmailConsent.isPlausible("\(repeated("a", 64))@\(repeated("b", 184))\(grinning).com"), "255 units")
    }

    /// JavaScript finds "@" and "." among code points. A combining mark after one joins it into a Character that
    /// Swift's Character-based searches don't see as "@" or ".", and JavaScript still does.
    @Test func findsTheAtAndTheDotsAmongScalars() {
        #expect(EmailConsent.isPlausible("sam@\u{301}example.com"))
        #expect(!EmailConsent.isPlausible("sam@.\u{301}example.com"))
        #expect(!EmailConsent.isPlausible("sam@example..\u{301}com"))
        // CR LF is one Character, and two code points to trim.
        #expect(EmailConsent.isPlausible("sam@example.com\r\n"))
    }

    /// email.js composes before it counts: e and a combining acute become é, one code unit.
    @Test func composesBeforeCounting() {
        #expect(EmailConsent.isPlausible("\(repeated("a", 63))e\u{301}@example.com"), "a 64-unit local part")
        #expect(!EmailConsent.isPlausible("\(repeated("a", 64))e\u{301}@example.com"), "a 65-unit local part")
    }

    /// clean composes as ICU does, as JavaScript's normalize does. Foundation's precomposedStringWithCanonicalMapping
    /// differs: it turned U+1100 U+1176 into 까 (U+AE4C), another letter, dropped U+11A7, never joined a syllable to a
    /// final consonant, and left some Tibetan uncomposed.
    @Test func composesAsJavaScriptDoes() {
        #expect(scalars(EmailConsent.clean("\u{1100}\u{1176}")) == [0x1100, 0x1176])
        #expect(scalars(EmailConsent.clean("\u{1113}\u{1167}")) == [0x1113, 0x1167])
        #expect(scalars(EmailConsent.clean("\u{1100}\u{1161}\u{11A7}")) == [0xAC00, 0x11A7])
        #expect(scalars(EmailConsent.clean("\u{AC00}\u{11A8}")) == [0xAC01])
        #expect(scalars(EmailConsent.clean("\u{AC00}\u{11C2}")) == [0xAC1B])
        #expect(scalars(EmailConsent.clean("\u{AC00}\u{11C3}")) == [0xAC00, 0x11C3])
        #expect(scalars(EmailConsent.clean("\u{1112}\u{1175}\u{11C2}")) == [0xD7A3])
        #expect(scalars(EmailConsent.clean("a\u{F73}\u{301}")) == [0xE1, 0xF71, 0xF72])
        // So the limits fall where the site's do.
        #expect(EmailConsent.isPlausible("\(repeated("a", 62))\u{1100}\u{1176}@example.com"), "a 64-unit local part")
        #expect(!EmailConsent.isPlausible("\(repeated("a", 63))\u{1100}\u{1176}@example.com"), "a 65-unit local part")
        #expect(EmailConsent.isPlausible("\(repeated("a", 63))\u{AC00}\u{11A8}@example.com"), "a 64-unit local part")
        #expect(!EmailConsent.isPlausible("\(repeated("a", 64))\u{AC00}\u{11A8}@example.com"), "a 65-unit local part")
        #expect(EmailConsent.isPlausible("\(repeated("a", 62))\u{F73}\u{301}@example.com"), "a 64-unit local part")
        #expect(!EmailConsent.isPlausible("\(repeated("a", 63))\u{F73}\u{301}@example.com"), "a 65-unit local part")
        // The key is composed the same way: İ makes it 65 units, which Foundation's 까 would have cut to 64.
        #expect(EmailConsent.isPlausible("\u{130}\(repeated("a", 60))\u{1100}\u{1176}@example.com"), "a 64-unit key")
        #expect(!EmailConsent.isPlausible("\u{130}\(repeated("a", 61))\u{1100}\u{1176}@example.com"), "a 65-unit key")
    }

    /// What email.js checks, and no more: exactly one "@", and dots placed freely in the local part.
    @Test func checksNoMoreThanTheSite() {
        #expect(!EmailConsent.isPlausible("sam@example.com@example.com"))
        #expect(EmailConsent.isPlausible("sam..x@example.com"))
        #expect(EmailConsent.isPlausible(".sam@example.com"))
        #expect(EmailConsent.isPlausible("sam.@example.com"))
    }

    /// /api/subscribe checks the address's lowercase key too, and İ lowercases to i and a combining dot: one code unit
    /// longer. The site would turn such an address away every time, so the app does too.
    @Test func checksTheLowercaseKeyAsTheSiteDoes() {
        #expect(EmailConsent.isPlausible("\u{130}sa@example.com"))
        #expect(EmailConsent.isPlausible("\u{130}\(repeated("a", 62))@example.com"), "a 64-unit local part in the key")
        #expect(!EmailConsent.isPlausible("\u{130}\(repeated("a", 63))@example.com"), "a 65-unit local part in the key")
        #expect(EmailConsent.isPlausible("\u{130}@\(repeated("b", 247)).com"), "a 254-unit key")
        #expect(!EmailConsent.isPlausible("\u{130}@\(repeated("b", 248)).com"), "a 255-unit key")
        // J and a caron compose only once small, to ǰ: both the address and its key must fit.
        #expect(!EmailConsent.isPlausible("\(repeated("a", 63))J\u{30C}@example.com"), "65 units, and a 64-unit key")
        #expect(EmailConsent.isPlausible("\u{130}J\u{30C}\(repeated("a", 61))@example.com"),
                "64 units, and a key of 64 once composed")
        // A Σ that ends a word lowercases to ς, as in JavaScript: one code unit, as Σ is.
        #expect(EmailConsent.isPlausible("\u{3A3}\u{391}\u{3A3}@example.com"))
        #expect(EmailConsent.isPlausible("\(repeated("a", 63))\u{3A3}@example.com"))
    }
}

/// `text`, `count` times: JavaScript's 'a'.repeat(64).
private func repeated(_ text: String, _ count: Int) -> String {
    String(repeating: text, count: count)
}

/// The string's code points. Swift's == treats a composed and a decomposed accent as equal; email.js doesn't.
private func scalars(_ text: String) -> [UInt32] {
    text.unicodeScalars.map(\.value)
}

private func hex(_ value: UInt32) -> String {
    String(format: "%04X", value)
}

/// The string composed (NFC) as ICU composes, and so as JavaScript's normalize() does.
private func nfc(_ text: String) -> String {
    text.applyingTransform(StringTransform("Any-NFC"), reverse: false) ?? text
}
