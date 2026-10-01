import Foundation

/// One release in the Sparkle feed.
public struct AppcastItem: Equatable, Sendable {
    /// e.g. "0.2.0"
    public var shortVersion: String
    /// e.g. "74": Sparkle compares these to find a newer version.
    public var build: String
    /// The release's Annotake.zip.
    public var url: URL
    /// The zip's size in bytes.
    public var length: Int
    /// The zip's EdDSA signature, from sign_update.
    public var edSignature: String
    /// e.g. "15.0"
    public var minimumSystemVersion: String
    public var date: Date
    /// Plain text; each line becomes a paragraph.
    public var notes: String

    public init(shortVersion: String, build: String, url: URL, length: Int, edSignature: String,
                minimumSystemVersion: String, date: Date, notes: String) {
        self.shortVersion = shortVersion
        self.build = build
        self.url = url
        self.length = length
        self.edSignature = edSignature
        self.minimumSystemVersion = minimumSystemVersion
        self.date = date
        self.notes = notes
    }

    /// "Annotake 0.2.0 (74)"
    public var title: String { "Annotake \(shortVersion) (\(build))" }
}

public enum AppcastError: Error, Equatable {
    case duplicateBuild(String)
    case unreadableFeed
}

/// Sparkle's RSS feed (spec §6.2). A bad feed breaks updates for everyone, so `make release` writes it only
/// through here.
public enum Appcast {
    public static let maxItems = 10
    static let sparkleNamespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"
    static let channelTitle = "Annotake"

    /// A new feed when `existing` is nil; otherwise `existing` with `item` first, trimmed to `maxItems`.
    public static func inserting(_ item: AppcastItem, into existing: String?) throws -> String {
        let document = try existing.map(parse) ?? newFeed()
        guard let channel = document.rootElement()?.elements(forName: "channel").first else {
            throw AppcastError.unreadableFeed
        }
        let items = channel.elements(forName: "item")
        if items.contains(where: { $0.elements(forName: "sparkle:version").first?.stringValue == item.build }) {
            throw AppcastError.duplicateBuild(item.build)
        }
        let newItem = element(for: item)
        if let first = items.first {
            channel.insertChild(newItem, at: first.index)
        } else {
            channel.addChild(newItem)
        }
        for old in channel.elements(forName: "item").dropFirst(maxItems).reversed() {
            channel.removeChild(at: old.index)
        }
        return document.xmlString(options: [.nodePrettyPrint, .nodePreserveCDATA]) + "\n"
    }

    /// RFC 822, as RSS wants: "Wed, 30 Sep 2026 22:00:00 +0000".
    public static func pubDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.string(from: date)
    }

    /// The notes as HTML, one paragraph per line, escaped, and safe inside CDATA.
    static func html(_ notes: String) -> String {
        notes.split(separator: "\n", omittingEmptySubsequences: true)
            .map { line in
                let escaped = line
                    .replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")
                    .replacingOccurrences(of: "\"", with: "&quot;")
                return "<p>\(escaped)</p>"
            }
            .joined()
            // Escaping already removes it; split it anyway so the CDATA section can never end early.
            .replacingOccurrences(of: "]]>", with: "]]]]><![CDATA[>")
    }

    private static func parse(_ feed: String) throws -> XMLDocument {
        guard let document = try? XMLDocument(xmlString: feed, options: [.nodePreserveCDATA]),
              document.rootElement()?.name == "rss"
        else { throw AppcastError.unreadableFeed }
        return document
    }

    private static func newFeed() -> XMLDocument {
        let rss = XMLElement(name: "rss")
        rss.addAttribute(XMLNode.attribute(withName: "version", stringValue: "2.0") as! XMLNode)
        rss.addNamespace(XMLNode.namespace(withName: "sparkle", stringValue: sparkleNamespace) as! XMLNode)
        let channel = XMLElement(name: "channel")
        channel.addChild(XMLElement(name: "title", stringValue: channelTitle))
        rss.addChild(channel)
        let document = XMLDocument(rootElement: rss)
        document.version = "1.0"
        document.characterEncoding = "utf-8"
        return document
    }

    private static func element(for item: AppcastItem) -> XMLElement {
        let element = XMLElement(name: "item")
        element.addChild(XMLElement(name: "title", stringValue: item.title))
        element.addChild(XMLElement(name: "pubDate", stringValue: pubDate(item.date)))
        element.addChild(XMLElement(name: "sparkle:version", stringValue: item.build))
        element.addChild(XMLElement(name: "sparkle:shortVersionString", stringValue: item.shortVersion))
        element.addChild(XMLElement(name: "sparkle:minimumSystemVersion", stringValue: item.minimumSystemVersion))
        let description = XMLElement(name: "description")
        let cdata = XMLNode(kind: .text, options: .nodeIsCDATA)
        cdata.stringValue = html(item.notes)
        description.addChild(cdata)
        element.addChild(description)
        let enclosure = XMLElement(name: "enclosure")
        for (name, value) in [("url", item.url.absoluteString), ("length", String(item.length)),
                              ("type", "application/octet-stream"), ("sparkle:edSignature", item.edSignature)] {
            enclosure.addAttribute(XMLNode.attribute(withName: name, stringValue: value) as! XMLNode)
        }
        element.addChild(enclosure)
        return element
    }
}
