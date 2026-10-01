import CoreVideo
import AnnotakeCore

/// Reduces a BGRA frame to its tile signature (spec §5.1): each 8 × 8-pixel cell's mean brightness,
/// 4 × 4 cells per 32 px tile. Tiles are row-major, and so are the cells within each tile.
public enum SignatureExtractor {
    /// A cell's edge in output pixels.
    public static let cellSize = 8
    /// Cells per tile edge.
    public static let cellsPerTileSide = 4
    private static let bytesPerPixel = 4

    /// Integer luma: (77·R + 150·G + 29·B + 128) >> 8.
    public static func luma(r: UInt8, g: UInt8, b: UInt8) -> UInt8 {
        UInt8(truncatingIfNeeded: luma(r: UInt32(r), g: UInt32(g), b: UInt32(b)))
    }

    @inline(__always)
    private static func luma(r: UInt32, g: UInt32, b: UInt32) -> UInt32 {
        (77 &* r &+ 150 &* g &+ 29 &* b &+ 128) >> 8
    }

    /// BGRA8, row-major; bytesPerRow ≥ width·4. width and height equal the geometry's output size.
    /// A cell averages only the pixels it covers; a cell entirely beyond the image is 0.
    public static func signature(bgra: UnsafeRawBufferPointer, width: Int, height: Int, bytesPerRow: Int,
                                 geometry: CaptureGeometry) -> FrameSignature {
        let grid = geometry.grid
        let valuesPerTile = FrameSignature.valuesPerTile
        let cellColumns = grid.columns * cellsPerTileSide
        let cellRows = grid.rows * cellsPerTileSide
        let usedWidth = min(width, cellColumns * cellSize)
        let usedHeight = min(height, cellRows * cellSize)
        var values = [UInt8](repeating: 0, count: grid.count * valuesPerTile)
        guard let base = bgra.baseAddress?.assumingMemoryBound(to: UInt8.self), usedWidth > 0, usedHeight > 0 else {
            return FrameSignature(tileCount: grid.count, values: values)
        }
        var sums = [UInt32](repeating: 0, count: cellColumns)

        values.withUnsafeMutableBufferPointer { out in
            sums.withUnsafeMutableBufferPointer { sums in
                var cellY = 0
                while cellY * cellSize < usedHeight {
                    let firstRow = cellY * cellSize
                    let rowsInCell = min(cellSize, usedHeight - firstRow)
                    for index in 0..<cellColumns { sums[index] = 0 }

                    for y in firstRow..<firstRow + rowsInCell {
                        var pixel = base + y * bytesPerRow
                        var x = 0
                        var cellX = 0
                        while x < usedWidth {
                            let end = min(x + cellSize, usedWidth)
                            var total: UInt32 = 0
                            for _ in x..<end {
                                total &+= luma(r: UInt32(pixel[2]), g: UInt32(pixel[1]), b: UInt32(pixel[0]))
                                pixel += bytesPerPixel
                            }
                            sums[cellX] &+= total
                            x = end
                            cellX += 1
                        }
                    }

                    let tileRow = cellY / cellsPerTileSide
                    let rowInTile = cellY % cellsPerTileSide
                    for cellX in 0..<cellColumns {
                        let columnsInCell = max(0, min(cellSize, usedWidth - cellX * cellSize))
                        let count = UInt32(columnsInCell * rowsInCell)
                        let tile = tileRow * grid.columns + cellX / cellsPerTileSide
                        let slot = tile * valuesPerTile + rowInTile * cellsPerTileSide + cellX % cellsPerTileSide
                        out[slot] = count == 0 ? 0 : UInt8(truncatingIfNeeded: (sums[cellX] + count / 2) / count)
                    }
                    cellY += 1
                }
            }
        }
        return FrameSignature(tileCount: grid.count, values: values)
    }

    /// Locks the buffer read-only for the duration of the call.
    public static func signature(of pixelBuffer: CVPixelBuffer, geometry: CaptureGeometry) -> FrameSignature {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = UnsafeRawBufferPointer(start: CVPixelBufferGetBaseAddress(pixelBuffer), count: bytesPerRow * height)
        return signature(bgra: bytes, width: CVPixelBufferGetWidth(pixelBuffer), height: height,
                         bytesPerRow: bytesPerRow, geometry: geometry)
    }
}
