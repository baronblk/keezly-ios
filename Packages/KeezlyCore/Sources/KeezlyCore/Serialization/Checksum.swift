import Foundation

/// A stable 64-bit checksum.
///
/// Swift's `Hasher` is seeded randomly per process, so `hashValue` differs
/// between two launches of the same build. That makes it useless for detecting
/// a corrupted saved match or a mismatched online state, which is exactly what
/// §28 asks for. FNV-1a is small, dependency-free and produces the same number
/// on every device and every run.
public enum Checksum {
    private static let offsetBasis: UInt64 = 0xCBF2_9CE4_8422_2325
    private static let prime: UInt64 = 0x0000_0100_0000_01B3

    /// `Data` satisfies `Sequence<UInt8>`, so this one entry point covers both
    /// encoded payloads and raw byte buffers.
    public static func fnv1a(_ bytes: some Sequence<UInt8>) -> UInt64 {
        var hash = offsetBasis
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }
}
