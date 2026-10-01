import CoreVideo
import AnnotakeCapture
import AnnotakeCore
import Testing

struct SignatureExtractorTests {
    /// BGRA8 bytes, row-major; each pixel is (b, g, r, 255) from `pixel`, and row padding bytes are 255.
    func image(width: Int, height: Int, bytesPerRow: Int? = nil,
               pixel: (Int, Int) -> (b: UInt8, g: UInt8, r: UInt8)) -> (bytes: [UInt8], bytesPerRow: Int) {
        let stride = bytesPerRow ?? width * 4
        var bytes = [UInt8](repeating: 255, count: stride * height)
        for y in 0..<height {
            for x in 0..<width {
                let (b, g, r) = pixel(x, y)
                let offset = y * stride + x * 4
                bytes[offset] = b
                bytes[offset + 1] = g
                bytes[offset + 2] = r
                bytes[offset + 3] = 255
            }
        }
        return (bytes, stride)
    }

    func gray(width: Int, height: Int, bytesPerRow: Int? = nil, _ value: (Int, Int) -> UInt8) -> (bytes: [UInt8], bytesPerRow: Int) {
        image(width: width, height: height, bytesPerRow: bytesPerRow) { x, y in
            let v = value(x, y)
            return (v, v, v)
        }
    }

    func signature(_ image: (bytes: [UInt8], bytesPerRow: Int), width: Int, height: Int) -> FrameSignature {
        let geometry = CaptureGeometry(outputWidth: width, outputHeight: height, pixelsPerPoint: 1)
        return image.bytes.withUnsafeBytes {
            SignatureExtractor.signature(bgra: $0, width: width, height: height, bytesPerRow: image.bytesPerRow,
                                         geometry: geometry)
        }
    }

    @Test func lumaWeights() {
        #expect(SignatureExtractor.luma(r: 255, g: 0, b: 0) == 77)
        #expect(SignatureExtractor.luma(r: 0, g: 255, b: 0) == 149)
        #expect(SignatureExtractor.luma(r: 0, g: 0, b: 255) == 29)
        #expect(SignatureExtractor.luma(r: 255, g: 255, b: 255) == 255)
        #expect(SignatureExtractor.luma(r: 100, g: 100, b: 100) == 100)
    }

    @Test func uniformImage() {
        let values = signature(gray(width: 64, height: 32) { _, _ in 100 }, width: 64, height: 32).values
        #expect(values == [UInt8](repeating: 100, count: 32))
    }

    @Test func cellOrderWithinTile() {
        let fill: (Int, Int) -> UInt8 = { x, y in
            let cell: Int = x / 8 + 4 * (y / 8)
            return UInt8(10 * cell)
        }
        let values = signature(gray(width: 32, height: 32, fill), width: 32, height: 32).values
        let expected: [UInt8] = (0..<16).map { UInt8(10 * $0) }
        #expect(values == expected)
    }

    @Test func tileOrder() {
        let fill: (Int, Int) -> UInt8 = { x, y in
            let tile: Int = x / 32 + 2 * (y / 32)
            return UInt8(50 * (tile + 1))
        }
        let values = signature(gray(width: 64, height: 64, fill), width: 64, height: 64).values
        let expected: [UInt8] = [50, 100, 150, 200].flatMap { [UInt8](repeating: $0, count: 16) }
        #expect(values == expected)
    }

    @Test func rowPaddingIgnored() {
        let pattern: (Int, Int) -> UInt8 = { x, y in UInt8((x * 7 + y * 3) % 256) }
        let padded = signature(gray(width: 32, height: 32, bytesPerRow: 32 * 4 + 64, pattern), width: 32, height: 32)
        let unpadded = signature(gray(width: 32, height: 32, pattern), width: 32, height: 32)
        #expect(padded == unpadded)
    }

    @Test func partialAndMissingCells() {
        let values = signature(gray(width: 36, height: 32) { x, _ in x >= 32 ? 120 : 80 }, width: 36, height: 32).values
        #expect(values.count == 32)
        let tile1 = Array(values[16..<32])
        for row in 0..<4 {
            #expect(Array(tile1[row * 4..<row * 4 + 4]) == [120, 0, 0, 0])
        }
    }

    @Test func pixelBufferMatchesRaw() throws {
        let width = 64, height = 32
        let pattern: (Int, Int) -> (b: UInt8, g: UInt8, r: UInt8) = { x, y in
            (UInt8(x * 3 % 256), UInt8(y * 5 % 256), UInt8((x + y) * 2 % 256))
        }
        var created: CVPixelBuffer?
        #expect(CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &created) == kCVReturnSuccess)
        let buffer = try #require(created)
        CVPixelBufferLockBaseAddress(buffer, [])
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let base = try #require(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let (b, g, r) = pattern(x, y)
                let pixel = base + y * stride + x * 4
                pixel[0] = b
                pixel[1] = g
                pixel[2] = r
                pixel[3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        let geometry = CaptureGeometry(outputWidth: width, outputHeight: height, pixelsPerPoint: 1)
        let fromBuffer = SignatureExtractor.signature(of: buffer, geometry: geometry)
        #expect(fromBuffer == signature(image(width: width, height: height, pixel: pattern), width: width, height: height))
    }
}
