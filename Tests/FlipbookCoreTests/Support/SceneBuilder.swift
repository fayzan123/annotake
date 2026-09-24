import FlipbookCore
import Foundation

/// Builds synthetic frames on a small screen: 640×384 at 32 px tiles is 20×12 = 240 tiles.
struct SceneBuilder {
    let geometry: CaptureGeometry
    /// The running screen state. Every value starts at 200.
    private(set) var signature: FrameSignature

    init(width: Int = 640, height: Int = 384, pixelsPerPoint: Double = 1) {
        geometry = CaptureGeometry(outputWidth: width, outputHeight: height, pixelsPerPoint: pixelsPerPoint)
        signature = FrameSignature(tileCount: geometry.grid.count)
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
