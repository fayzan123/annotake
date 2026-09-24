import FlipbookCore
import Foundation
import Testing

struct RawSessionWriterTests {
    @Test func writerRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "flipbook-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let scene = Scenes.clickFlow()

        let writer = try RawSessionWriter(directory: directory, geometry: scene.geometry,
                                          initialContext: scene.initialContext)
        for item in scene.mergedItems {
            switch item {
            case .frame(let frame): try writer.append(frame)
            case .event(let event): writer.append(event)
            }
        }
        try writer.finish(stopTime: 8.0)

        #expect(try RawSessionIO.read(from: directory) == scene)
    }
}
