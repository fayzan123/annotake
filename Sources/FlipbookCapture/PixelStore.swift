/// Pixel buffers held until LiveSession takes their frame: those it hasn't taken yet, plus the latest
/// one it took, so a persist can still copy its pixels. Used on the recording queue only.
public struct PixelStore<Buffer> {
    private var buffers: [Int: Buffer] = [:]

    public init() {}

    public mutating func put(_ buffer: Buffer, frameIndex: Int) {
        buffers[frameIndex] = buffer
    }

    public func buffer(frameIndex: Int) -> Buffer? {
        buffers[frameIndex]
    }

    /// Releases every buffer with a lower frame index.
    public mutating func evict(below frameIndex: Int) {
        buffers = buffers.filter { $0.key >= frameIndex }
    }

    public var count: Int { buffers.count }
}
