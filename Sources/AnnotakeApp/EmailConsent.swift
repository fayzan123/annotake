import Foundation

/// The email step's wording, the consent id sent with every address, and the address check (design §3.1). The site
/// keeps the same wording under the same id in site/api/_lib/consent.json, and EmailConsentTests checks the two match.
/// A wording change adds a new id there and moves `id` here; a shipped version is never edited.
enum EmailConsent {
    static let id = "consent-2026-10-15"
    static let title = "Stay in the loop"
    static let notice = "We'll email you about security fixes and important changes to Annotake. "
        + "Every email has an unsubscribe link."
    static let box = "Also email me feedback requests and news"
    /// The CASL mailing address in the step's footer. make release greps for this declaration while it holds the
    /// sentinel, so it stays on one line, spelled as it is.
    static let mailingAddress = "[mailing address]"  // Fayzan replaces this at the checkpoint
    static let unsetMailingAddress = "[mailing address]"
    /// The step's footer, which the Privacy policy link follows.
    static var footer: String { "From Fayzan Malik · \(mailingAddress) · annotake.app ·" }
    static let privacyURL = URL(string: "https://annotake.app/privacy")!

    // MARK: - The address check: the site's email.js, as /api/subscribe applies it

    /// What JavaScript's trim() takes off the ends and its \s matches: ECMAScript's WhiteSpace and LineTerminator.
    /// Not Foundation's .whitespacesAndNewlines or Character.isWhitespace, which lack U+FEFF and have U+0085.
    private static let whitespace = Set<UInt32>([0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x2028, 0x2029,
                                                 0x202F, 0x205F, 0x3000, 0xFEFF]).union(0x2000...0x200A)
    /// What email.js turns away anywhere in an address: that whitespace, and the controls U+0000–U+001F and U+007F.
    private static let rejected = whitespace.union(0x00...0x1F).union([0x7F])

    /// The address as the person meant it, as email.js's cleanEmail has it: trimmed, then composed (NFC).
    static func clean(_ input: String) -> String {
        let scalars = input.unicodeScalars
        guard let first = scalars.firstIndex(where: { !whitespace.contains($0.value) }),
              let last = scalars.lastIndex(where: { !whitespace.contains($0.value) })
        else { return "" }
        return composed(String(scalars[first...last]))
    }

    /// Whether /api/subscribe will take the address: email.js's isPlausibleEmail on the cleaned address, and on its
    /// key. The key can be longer: İ lowercases to i and a dot.
    static func isPlausible(_ input: String) -> Bool {
        let email = clean(input)
        return passes(email) && passes(key(email))
    }

    /// The address as /api/subscribe keys its contact, email.js's emailKey: cleaned, lowercased, then composed again,
    /// so any capitals, padding, or encoding of the accents give one key. ICU lowercases and composes it, as it does in
    /// JavaScript. The only skew left is capitals newer than the Mac's ICU (Unicode 17's, on macOS 15), which stay as
    /// they are: the same length as their small letters, so isPlausible still agrees with the site.
    static func key(_ input: String) -> String {
        composed(lowercased(clean(input)))
    }

    /// Lowercase as ICU has it, and so as JavaScript's toLowerCase() does: a Σ that ends a word becomes ς. Not
    /// lowercased(), which writes σ for every Σ: a Greek address in capitals would get a key the site doesn't use, and
    /// the same address retyped in small letters would look like another one.
    private static func lowercased(_ text: String) -> String {
        text.applyingTransform(StringTransform("Any-Lower"), reverse: false) ?? text.lowercased()
    }

    /// NFC as ICU composes, and so as JavaScript's normalize() does. Not precomposedStringWithCanonicalMapping, whose
    /// own tables differ: U+1100 U+1176 comes out as 까 (U+AE4C), another letter, so the app would save another address.
    private static func composed(_ text: String) -> String {
        text.applyingTransform(StringTransform("Any-NFC"), reverse: false) ?? text.precomposedStringWithCanonicalMapping
    }

    /// isPlausibleEmail's checks on a cleaned address, measured as JavaScript measures: lengths in UTF-16 code units,
    /// and "@" and "." found among code points. Never Characters: an emoji is one Character and two code units, and a
    /// combining mark after "@" makes a Character that isn't "@".
    private static func passes(_ email: String) -> Bool {
        guard (3...254).contains(email.utf16.count),
              !email.unicodeScalars.contains(where: { rejected.contains($0.value) })
        else { return false }
        let parts = email.unicodeScalars.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, (1...64).contains(String(parts[0]).utf16.count) else { return false }
        let domain = Array(parts[1])
        return domain.contains(".") && domain.first != "." && domain.last != "."
            && !zip(domain, domain.dropFirst()).contains { $0 == "." && $1 == "." }
    }
}
