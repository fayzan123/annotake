import Foundation

/// A point in output pixels, top-left origin.
public struct PixelPoint: Sendable, Hashable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A rectangle in output pixels, top-left origin.
public struct PixelRect: Sendable, Hashable, Codable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var isEmpty: Bool { width <= 0 || height <= 0 }
}

/// The capture split into square tiles, numbered row-major from the top left.
public struct TileGrid: Sendable, Hashable, Codable {
    public let columns: Int
    public let rows: Int
    /// Tile edge in output pixels.
    public let tileSize: Int

    public init(columns: Int, rows: Int, tileSize: Int) {
        precondition(tileSize > 0, "tileSize must be positive")
        self.columns = columns
        self.rows = rows
        self.tileSize = tileSize
    }

    public var count: Int { columns * rows }

    /// Tiles the rect touches, ascending. The rect is clamped to the grid first.
    public func tiles(intersecting rect: PixelRect) -> [Int] {
        guard !rect.isEmpty else { return [] }
        let minX = max(rect.x, 0)
        let minY = max(rect.y, 0)
        let maxX = min(rect.x + rect.width - 1, columns * tileSize - 1)
        let maxY = min(rect.y + rect.height - 1, rows * tileSize - 1)
        guard minX <= maxX, minY <= maxY else { return [] }

        let firstColumn = minX / tileSize, lastColumn = maxX / tileSize
        let firstRow = minY / tileSize, lastRow = maxY / tileSize
        var tiles: [Int] = []
        tiles.reserveCapacity((lastColumn - firstColumn + 1) * (lastRow - firstRow + 1))
        for row in firstRow...lastRow {
            for column in firstColumn...lastColumn {
                tiles.append(row * columns + column)
            }
        }
        return tiles
    }

    /// The tile under the point, or nil when the point lies outside the grid.
    public func tile(containing point: PixelPoint) -> Int? {
        let column = (point.x / Double(tileSize)).rounded(.down)
        let row = (point.y / Double(tileSize)).rounded(.down)
        guard column >= 0, row >= 0, column < Double(columns), row < Double(rows) else { return nil }
        return Int(row) * columns + Int(column)
    }
}

/// The size of the delivered frames and the tile grid laid over them.
public struct CaptureGeometry: Sendable, Hashable, Codable {
    public let outputWidth: Int
    public let outputHeight: Int
    /// Output pixels per screen point.
    public let pixelsPerPoint: Double
    public let grid: TileGrid

    public init(outputWidth: Int, outputHeight: Int, pixelsPerPoint: Double, tileSize: Int = 32) {
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        self.pixelsPerPoint = pixelsPerPoint
        self.grid = TileGrid(
            columns: (outputWidth + tileSize - 1) / tileSize,
            rows: (outputHeight + tileSize - 1) / tileSize,
            tileSize: tileSize)
    }
}
