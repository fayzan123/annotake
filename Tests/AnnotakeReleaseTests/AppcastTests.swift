import AnnotakeRelease
import Foundation
import Testing

struct AppcastTests {
    static let sparkle = "http://www.andymatuschak.org/xml-namespaces/sparkle"

    func item(build: Int, notes: String = "Fixes.") -> AppcastItem {
        AppcastItem(shortVersion: "0.2.0", build: "\(build)",
                    url: URL(string: "https://github.com/fayzan123/annotake-releases/releases/download/v0.2.0-\(build)/Annotake.zip")!,
                    length: 123_456, edSignature: "sig\(build)==", minimumSystemVersion: "15.0",
                    date: Date(timeIntervalSince1970: 1_790_000_000 + Double(build)), notes: notes)
    }

    func document(_ feed: String) throws -> XMLDocument {
        try XMLDocument(xmlString: feed, options: [.nodePreserveCDATA])
    }

    func items(_ feed: String) throws -> [XMLElement] {
        try document(feed).nodes(forXPath: "/rss/channel/item").compactMap { $0 as? XMLElement }
    }

    func builds(_ feed: String) throws -> [String] {
        try items(feed).map { $0.elements(forName: "sparkle:version").first?.stringValue ?? "" }
    }

    @Test func newFeedHasOneItem() throws {
        let feed = try Appcast.inserting(item(build: 74), into: nil)
        let document = try document(feed)
        let root = try #require(document.rootElement())
        #expect(root.name == "rss")
        #expect(root.attribute(forName: "version")?.stringValue == "2.0")
        #expect(root.namespace(forPrefix: "sparkle")?.stringValue == Self.sparkle)
        #expect(try document.nodes(forXPath: "/rss/channel/title").first?.stringValue == "Annotake")

        let entries = try items(feed)
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.elements(forName: "title").first?.stringValue == "Annotake 0.2.0 (74)")
        #expect(entry.elements(forName: "sparkle:version").first?.stringValue == "74")
        #expect(entry.elements(forName: "sparkle:shortVersionString").first?.stringValue == "0.2.0")
        #expect(entry.elements(forName: "sparkle:minimumSystemVersion").first?.stringValue == "15.0")
        let enclosure = try #require(entry.elements(forName: "enclosure").first)
        #expect(enclosure.attribute(forName: "url")?.stringValue
                == "https://github.com/fayzan123/annotake-releases/releases/download/v0.2.0-74/Annotake.zip")
        #expect(enclosure.attribute(forName: "length")?.stringValue == "123456")
        #expect(enclosure.attribute(forName: "type")?.stringValue == "application/octet-stream")
        #expect(enclosure.attribute(forName: "sparkle:edSignature")?.stringValue == "sig74==")
    }

    @Test func newestItemFirst() throws {
        let first = try Appcast.inserting(item(build: 74), into: nil)
        let second = try Appcast.inserting(item(build: 75), into: first)
        #expect(try builds(second) == ["75", "74"])
        #expect(try document(second).nodes(forXPath: "/rss/channel/title").count == 1)
    }

    @Test func duplicateBuildThrows() throws {
        let feed = try Appcast.inserting(item(build: 74), into: nil)
        #expect(throws: AppcastError.duplicateBuild("74")) {
            try Appcast.inserting(item(build: 74), into: feed)
        }
    }

    @Test func keepsAtMostTenItems() throws {
        var feed: String?
        for build in 1...11 {
            feed = try Appcast.inserting(item(build: build), into: feed)
        }
        let builds = try builds(try #require(feed))
        #expect(builds.count == Appcast.maxItems)
        #expect(builds.first == "11")
        #expect(!builds.contains("1"))
    }

    @Test func escapesNotes() throws {
        let notes = "Fix <b> & \"quotes\"\na]]>b"
        let feed = try Appcast.inserting(item(build: 74, notes: notes), into: nil)
        let entry = try #require(try items(feed).first)
        let html = try #require(entry.elements(forName: "description").first?.stringValue)
        // The description holds HTML, one paragraph per line, which reads back as the notes.
        let paragraphs = try XMLDocument(xmlString: "<root>\(html)</root>").rootElement()?.elements(forName: "p")
        #expect(paragraphs?.map { $0.stringValue ?? "" } == ["Fix <b> & \"quotes\"", "a]]>b"])
    }

    @Test func pubDateIsRFC822() throws {
        var entry = item(build: 74)
        entry.date = ISO8601DateFormatter().date(from: "2026-09-30T22:00:00Z")!
        let feed = try Appcast.inserting(entry, into: nil)
        #expect(try items(feed).first?.elements(forName: "pubDate").first?.stringValue == "Wed, 30 Sep 2026 22:00:00 +0000")
        #expect(Appcast.pubDate(entry.date) == "Wed, 30 Sep 2026 22:00:00 +0000")
    }

    @Test func unreadableFeedThrows() {
        #expect(throws: AppcastError.unreadableFeed) {
            try Appcast.inserting(item(build: 74), into: "not xml")
        }
        #expect(throws: AppcastError.unreadableFeed) {
            try Appcast.inserting(item(build: 74), into: "<html><body/></html>")
        }
    }
}
