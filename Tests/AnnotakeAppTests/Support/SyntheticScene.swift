import AnnotakeCore
import Foundation

/// Builds synthetic frames on a small screen, like Core's SceneBuilder: 640×384 at 32 px tiles is
/// 20×12 = 240 tiles. Test targets can't share support files, so the app tests keep their own.
struct SyntheticScene {
    let geometry: CaptureGeometry
    /// The running screen state. Every value starts at 200.
    private(set) var signature: FrameSignature
    private(set) var nextIndex = 0

    init(width: Int = 640, height: Int = 384) {
        geometry = CaptureGeometry(outputWidth: width, outputHeight: height, pixelsPerPoint: 1)
        signature = FrameSignature(tileCount: geometry.grid.count)
    }

    /// Applies `changes` to the running signature and returns the next frame. Its dirty rects are the
    /// changed tiles' rects.
    mutating func frame(at time: TimeInterval, set changes: [Int: UInt8], cursor: PixelRect?) -> FrameSample {
        for (tile, value) in changes {
            signature.setTile(tile, to: value)
        }
        let sample = FrameSample(index: nextIndex, time: time, signature: signature,
                                 dirtyRects: changes.keys.sorted().map(rect(ofTile:)), cursor: cursor)
        nextIndex += 1
        return sample
    }

    /// The tile's pixel bounds.
    func rect(ofTile tile: Int) -> PixelRect {
        let grid = geometry.grid
        return PixelRect(x: (tile % grid.columns) * grid.tileSize, y: (tile / grid.columns) * grid.tileSize,
                         width: grid.tileSize, height: grid.tileSize)
    }
}
