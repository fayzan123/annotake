import AnnotakeCore
import Foundation
import Testing

struct RawSessionWriterTests {
    @Test func writerRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "annotake-tests-\(UUID().uuidString)")
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

    @Test func writerRecordsContextSource() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "annotake-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let scene = Scenes.windowRecording()

        let writer = try RawSessionWriter(directory: directory, geometry: scene.geometry,
                                          initialContext: scene.initialContext, contextSource: .recordedWindow)
        for item in scene.mergedItems {
            switch item {
            case .frame(let frame): try writer.append(frame)
            case .event(let event): writer.append(event)
            }
        }
        try writer.finish(stopTime: scene.stopTime)

        #expect(try RawSessionIO.read(from: directory) == scene)
    }
}
