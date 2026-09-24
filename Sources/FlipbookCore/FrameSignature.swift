import Foundation

/// A frame reduced to per-tile brightness: each tile is a 4×4 grid of mean brightness values
/// (0–255), row-major, and tiles follow the grid's row-major order.
public struct FrameSignature: Sendable, Hashable {
    public static let valuesPerTile = 16

    public let tileCount: Int
    public private(set) var values: [UInt8]

    public init(tileCount: Int, fill: UInt8 = 200) {
        self.tileCount = tileCount
        self.values = [UInt8](repeating: fill, count: tileCount * Self.valuesPerTile)
    }

    public init(tileCount: Int, values: [UInt8]) {
        precondition(values.count == tileCount * Self.valuesPerTile,
                     "expected \(tileCount * Self.valuesPerTile) values, got \(values.count)")
        self.tileCount = tileCount
        self.values = values
    }

    /// Mean absolute difference between the tile's 16 values in the two signatures, 0...255.
    public func meanAbsoluteDifference(to other: FrameSignature, tile: Int) -> Double {
        let start = tile * Self.valuesPerTile
        var total = 0
        for offset in start..<start + Self.valuesPerTile {
            total += abs(Int(values[offset]) - Int(other.values[offset]))
        }
        return Double(total) / Double(Self.valuesPerTile)
    }

    /// True when the tile's mean absolute difference exceeds the threshold.
    public func differs(from other: FrameSignature, tile: Int, threshold: Double) -> Bool {
        meanAbsoluteDifference(to: other, tile: tile) > threshold
    }

    /// Sets all 16 values of the tile.
    public mutating func setTile(_ tile: Int, to value: UInt8) {
        let start = tile * Self.valuesPerTile
        for offset in start..<start + Self.valuesPerTile {
            values[offset] = value
        }
    }
}
