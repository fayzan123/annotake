import AnnotakeCore
import Foundation

/// Builds synthetic frames on a small screen: 640×384 at 32 px tiles is 20×12 = 240 tiles.
struct SceneBuilder {
    let geometry: CaptureGeometry
    /// The running screen state. Every value starts at 200.
    private(set) var signature: FrameSignature
    private(set) var nextIndex = 0

    init(width: Int = 640, height: Int = 384, pixelsPerPoint: Double = 1) {
        geometry = CaptureGeometry(outputWidth: width, outputHeight: height, pixelsPerPoint: pixelsPerPoint)
        signature = FrameSignature(tileCount: geometry.grid.count)
    }

    /// Applies `set` to the running signature and returns the next FrameSample.
    /// dirtyRects defaults to one rect per changed tile (rect(ofTile:)); cursor defaults to nil.
    mutating func frame(at time: TimeInterval, set changes: [Int: UInt8] = [:],
                        dirty: [PixelRect]? = nil, cursor: PixelRect? = nil) -> FrameSample {
        for (tile, value) in changes {
            signature.setTile(tile, to: value)
        }
        let sample = FrameSample(
            index: nextIndex, time: time, signature: signature,
            dirtyRects: dirty ?? changes.keys.sorted().map(rect(ofTile:)),
            cursor: cursor)
        nextIndex += 1
        return sample
    }

    /// A kept frame on a blank 240-tile screen, for tests that only care about indices, times and actions.
    static func keptStub(index: Int, time: TimeInterval, actions: [StepAction] = [],
                         reason: KeepReason = .visual) -> KeptFrame {
        let sample = FrameSample(index: index, time: time, signature: FrameSignature(tileCount: 240),
                                 dirtyRects: [], cursor: nil)
        return KeptFrame(sample: sample, context: FrameContext(app: "TestApp", window: "Main"),
                         actions: actions, reason: reason)
    }

    /// The tile's pixel bounds.
    func rect(ofTile tile: Int) -> PixelRect {
        let grid = geometry.grid
        return PixelRect(
            x: (tile % grid.columns) * grid.tileSize,
            y: (tile / grid.columns) * grid.tileSize,
            width: grid.tileSize,
            height: grid.tileSize)
    }
}

extension Dictionary where Key == Int, Value == UInt8 {
    /// Sets every listed tile to `value`, e.g. `.tiles(0..<12)`.
    static func tiles<S: Sequence>(_ ids: S, value: UInt8 = 40) -> [Int: UInt8] where S.Element == Int {
        Dictionary(uniqueKeysWithValues: ids.map { ($0, value) })
    }
}
