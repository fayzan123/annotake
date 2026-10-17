import Foundation

/// "Did you mean …?" under the email field (Checkpoint 5): for an address whose domain is a likely typo of a common
/// provider's, such as gmial.com or gmail.con. A hint, never a block: Continue and Save take the address as typed, since
/// only its person knows it. A wrong hint is worse than none, so a short name such as me.com's is matched only exactly
/// (a letter off, it's usually some other company's domain), and the regional domains are known as themselves.
enum EmailTypo {
    /// Common providers' domains, the regional ones included, so that hotmail.ca isn't taken for a typo of hotmail.com,
    /// nor email.com of gmail.com.
    static let domains = [
        "gmail.com", "googlemail.com", "icloud.com", "me.com", "mac.com", "outlook.com", "hotmail.com", "hotmail.ca",
        "hotmail.co.uk", "live.com", "live.ca", "msn.com", "yahoo.com", "yahoo.ca", "yahoo.co.uk", "ymail.com",
        "aol.com", "proton.me", "protonmail.com", "pm.me", "hey.com", "fastmail.com", "gmx.com", "mail.com",
        "email.com", "zoho.com", "yandex.com",
    ]
    /// "com" mistyped.
    static let comTypos: Set<String> = ["con", "cpm", "cim", "cmo", "ocm", "comm", "coom", "copm", "vom", "xom", "co",
                                        "cm", "om"]

    /// The address with the domain it most likely means, or nil: for an address the site wouldn't take, a known
    /// domain, or one nothing known is close to. Trimmed, the name stays as typed.
    static func suggestion(for input: String) -> String? {
        guard EmailConsent.isPlausible(input) else { return nil }
        let email = EmailConsent.clean(input)
        guard let at = email.lastIndex(of: "@") else { return nil }
        let domain = email[email.index(after: at)...].lowercased()
        guard !domains.contains(domain), let meant = likely(domain) else { return nil }
        return "\(email[..<at])@\(meant)"
    }

    /// The known domain an unknown one most likely means: a known name with "com" mistyped (gmail.con), or a name a
    /// letter off, or two for a long one, with the same ending (gmial.com, hotmal.ca). Two equally close mean neither.
    private static func likely(_ domain: String) -> String? {
        let (name, ending) = parts(domain)
        if comTypos.contains(ending), domains.contains("\(name).com") { return "\(name).com" }
        let close = domains.compactMap { known -> (domain: String, distance: Int)? in
            let (knownName, knownEnding) = parts(known)
            guard knownEnding == ending, knownName.count >= 5 else { return nil }
            let edits = distance(name, knownName)
            return edits <= (knownName.count >= 7 ? 2 : 1) ? (known, edits) : nil
        }
        guard let nearest = close.map(\.distance).min() else { return nil }
        let best = close.filter { $0.distance == nearest }
        return best.count == 1 ? best[0].domain : nil
    }

    /// The name before the first dot, and the ending after it: "hotmail" and "co.uk".
    private static func parts(_ domain: String) -> (name: String, ending: String) {
        guard let dot = domain.firstIndex(of: ".") else { return (domain, "") }
        return (String(domain[..<dot]), String(domain[domain.index(after: dot)...]))
    }

    /// Edits from one to the other: a letter added, dropped, or changed, or two side by side swapped (the optimal
    /// string alignment distance).
    static func distance(_ from: String, _ to: String) -> Int {
        let a = Array(from), b = Array(to)
        guard !a.isEmpty, !b.isEmpty else { return max(a.count, b.count) }
        var d = (0...a.count).map { i in (0...b.count).map { j in i == 0 ? j : (j == 0 ? i : 0) } }
        for i in 1...a.count {
            for j in 1...b.count {
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[a.count][b.count]
    }
}
