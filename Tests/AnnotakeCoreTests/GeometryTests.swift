import AnnotakeCore
import Testing

struct GeometryTests {
    /// 640×384 at 32 px tiles: 20 columns × 12 rows.
    let grid = TileGrid(columns: 20, rows: 12, tileSize: 32)

    @Test func retinaGeometryBuildsGrid() {
        let grid = CaptureGeometry(outputWidth: 1920, outputHeight: 1247, pixelsPerPoint: 1.27).grid
        #expect(grid.columns == 60)
        #expect(grid.rows == 39)
        #expect(grid.count == 2340)
    }

    @Test func rectInsideOneTile() {
        #expect(grid.tiles(intersecting: PixelRect(x: 40, y: 40, width: 10, height: 10)) == [21])
    }

    @Test func rectSpanningFourTiles() {
        #expect(grid.tiles(intersecting: PixelRect(x: 20, y: 20, width: 30, height: 30)) == [0, 1, 20, 21])
    }

    @Test func rectPartlyOutsideIsClamped() {
        #expect(grid.tiles(intersecting: PixelRect(x: -10, y: -10, width: 20, height: 20)) == [0])
    }

    @Test func rectFullyOutsideIsEmpty() {
        #expect(grid.tiles(intersecting: PixelRect(x: -50, y: 0, width: 40, height: 10)) == [])
        #expect(grid.tiles(intersecting: PixelRect(x: 700, y: 0, width: 5, height: 5)) == [])
    }

    @Test func emptyRectIsEmpty() {
        #expect(grid.tiles(intersecting: PixelRect(x: 10, y: 10, width: 0, height: 10)) == [])
    }

    @Test func tileContainingPoint() {
        #expect(grid.tile(containing: PixelPoint(x: 0, y: 0)) == 0)
        #expect(grid.tile(containing: PixelPoint(x: 639.9, y: 383.9)) == 239)
        #expect(grid.tile(containing: PixelPoint(x: 640, y: 0)) == nil)
        #expect(grid.tile(containing: PixelPoint(x: -1, y: 5)) == nil)
    }
}
