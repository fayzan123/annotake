import Foundation

/// SplitMix64: a small, fast, reproducible generator for property tests.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A uniformly distributed value in the range.
    mutating func next(in range: Range<Double>) -> Double {
        let unit = Double(nextUInt64() >> 11) * 0x1.0p-53
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}
