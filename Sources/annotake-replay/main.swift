import AnnotakeCore
import Foundation

// Replays a saved raw session through AnnotakeCore and prints the picker's decisions, for tuning (spec §8).

let usage = "usage: annotake-replay <session-dir> [--cap N]"

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func describe(_ error: Error) -> String {
    switch error {
    case RawSessionError.unsupportedVersion(let version):
        "unsupported session format version \(version) (this build reads version \(RawSessionIO.formatVersion))"
    case let RawSessionError.corruptTiles(expectedBytes, actualBytes):
        "tiles.bin holds \(actualBytes) bytes, expected \(expectedBytes)"
    default:
        error.localizedDescription
    }
}

var directory: String?
var cap: Int?
var arguments = CommandLine.arguments.dropFirst()
while let argument = arguments.popFirst() {
    if argument == "--cap" {
        guard let value = arguments.popFirst().flatMap({ Int($0) }) else { fail(usage, code: 2) }
        cap = value
    } else if argument.hasPrefix("-") || directory != nil {
        fail(usage, code: 2)
    } else {
        directory = argument
    }
}
guard let directory else { fail(usage, code: 2) }

let session: RawSession
do {
    session = try RawSessionIO.read(from: URL(fileURLWithPath: directory))
} catch {
    fail("error: \(describe(error))", code: 1)
}

var config = PickerConfig()
if let cap { config.maxFrames = cap }
print(ReplayReport.render(SessionReplayer.run(session, config: config), session: session), terminator: "")
