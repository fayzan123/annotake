import FlipbookCore
import Testing

struct FrameSignatureTests {
    /// A 240-tile signature (all 200) whose tile 7 holds the varied values 100…115.
    func variedTile7(plus delta: UInt8 = 0) -> FrameSignature {
        var values = [UInt8](repeating: 200, count: 240 * FrameSignature.valuesPerTile)
        for offset in 0..<FrameSignature.valuesPerTile {
            values[7 * FrameSignature.valuesPerTile + offset] = 100 + UInt8(offset) + delta
        }
        return FrameSignature(tileCount: 240, values: values)
    }

    @Test func identicalTilesDoNotDiffer() {
        let a = FrameSignature(tileCount: 240)
        let b = FrameSignature(tileCount: 240)
        #expect(a.meanAbsoluteDifference(to: b, tile: 3) == 0)
        #expect(!a.differs(from: b, tile: 3, threshold: 3))
    }

    @Test func threshold3IsExclusive() {
        let original = variedTile7()
        let plus3 = variedTile7(plus: 3)
        #expect(original.meanAbsoluteDifference(to: plus3, tile: 7) == 3)
        #expect(!original.differs(from: plus3, tile: 7, threshold: 3))

        let plus4 = variedTile7(plus: 4)
        #expect(original.meanAbsoluteDifference(to: plus4, tile: 7) == 4)
        #expect(original.differs(from: plus4, tile: 7, threshold: 3))
    }

    @Test func setTileChangesOnlyThatTile() {
        let original = FrameSignature(tileCount: 240)
        var changed = original
        changed.setTile(5, to: 40)
        let differing = (0..<240).filter { changed.differs(from: original, tile: $0, threshold: 3) }
        #expect(differing == [5])
        #expect(changed.meanAbsoluteDifference(to: original, tile: 5) == 160)
    }

    @Test func valuesInitRequiresExactCount() {
        let signature = FrameSignature(tileCount: 2, values: [UInt8](repeating: 9, count: 32))
        #expect(signature.tileCount == 2)
        #expect(signature.values.count == 32)
    }
}
