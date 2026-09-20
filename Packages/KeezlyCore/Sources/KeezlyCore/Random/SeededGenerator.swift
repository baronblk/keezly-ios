import Foundation

/// Deterministic, portable pseudo-random generator (SplitMix64).
///
/// The engine must never touch `SystemRandomNumberGenerator` directly: every
/// source of randomness is funnelled through a value type whose full state is
/// a single `UInt64`. That makes shuffles reproducible across devices, app
/// versions and platforms, which is what §20 (Determinismus) requires for
/// tests, replay, Game Center sync and AI simulation.
///
/// SplitMix64 is chosen over `arc4random` / `Mersenne Twister` because it has
/// a tiny serialisable state, no warm-up requirement, and a fixed, documented
/// output sequence.
public struct SeededGenerator: RandomNumberGenerator, Sendable, Hashable, Codable {
    /// The complete generator state. Serialising this value is sufficient to
    /// resume an identical random stream.
    public private(set) var state: UInt64

    public init(seed: UInt64) {
        // Avoid the all-zero state, which produces a degenerate first output.
        self.state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    public init(rawState: UInt64) {
        self.state = rawState
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Creates a generator seeded from the system CSPRNG.
    ///
    /// Used for real matches (§12: "kryptografisch bzw. systemseitig korrekt
    /// randomisieren"). The resulting seed is still recorded in the game state,
    /// so any real match remains replayable after the fact.
    public static func systemSeeded() -> SeededGenerator {
        var system = SystemRandomNumberGenerator()
        return SeededGenerator(seed: system.next())
    }
}

extension Array {
    /// Fisher–Yates shuffle driven by a `SeededGenerator`.
    ///
    /// Deliberately implemented here rather than using `shuffled(using:)`:
    /// the standard library does not document its algorithm, so relying on it
    /// would make our "same seed ⇒ same deck" guarantee depend on an
    /// implementation detail of the Swift runtime.
    func keezlyShuffled(using generator: inout SeededGenerator) -> [Element] {
        var result = self
        guard result.count > 1 else { return result }
        for i in stride(from: result.count - 1, to: 0, by: -1) {
            let j = Int(generator.next() % UInt64(i + 1))
            result.swapAt(i, j)
        }
        return result
    }
}
