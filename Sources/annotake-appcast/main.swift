import AnnotakeRelease
import Foundation

// Adds a release to Sparkle's feed (spec §9): reads the feed if it exists, puts the new item first, keeps the
// newest ten, and writes it back. `make release` runs it.

let usage = """
    usage: annotake-appcast --feed <path> --version <v> --build <n> --url <url> --length <bytes> \
    --signature <ed25519> --notes <text> [--min-system 15.0]
    """
let required = ["--feed", "--version", "--build", "--url", "--length", "--signature", "--notes"]
let optional = ["--min-system"]

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

var options: [String: String] = [:]
var arguments = CommandLine.arguments.dropFirst()
while let name = arguments.popFirst() {
    guard required.contains(name) || optional.contains(name), let value = arguments.popFirst(), options[name] == nil
    else { fail(usage, code: 2) }
    options[name] = value
}
guard required.allSatisfy({ options[$0] != nil }),
      let length = Int(options["--length"]!), length > 0,
      let url = URL(string: options["--url"]!), url.scheme != nil,
      !options["--signature"]!.isEmpty, !options["--notes"]!.isEmpty
else { fail(usage, code: 2) }

let feed = URL(fileURLWithPath: options["--feed"]!)
let item = AppcastItem(shortVersion: options["--version"]!, build: options["--build"]!, url: url, length: length,
                       edSignature: options["--signature"]!, minimumSystemVersion: options["--min-system"] ?? "15.0",
                       date: Date(), notes: options["--notes"]!)
do {
    let existing = FileManager.default.fileExists(atPath: feed.path) ? try String(contentsOf: feed, encoding: .utf8) : nil
    try Appcast.inserting(item, into: existing).write(to: feed, atomically: true, encoding: .utf8)
    print(item.title)
} catch AppcastError.duplicateBuild(let build) {
    fail("\(feed.path) already has build \(build)", code: 1)
} catch AppcastError.unreadableFeed {
    fail("\(feed.path) isn't a readable Sparkle feed", code: 1)
} catch {
    fail("couldn't update \(feed.path): \(error.localizedDescription)", code: 1)
}
