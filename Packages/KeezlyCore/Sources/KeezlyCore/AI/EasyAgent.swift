import Foundation

/// The beginner opponent (§22).
///
/// Easy is deliberately weak, but not broken. It picks among the legal moves
/// with a *weighted* random draw rather than a uniform one, using a handful of
/// obvious features — take a capture, get a pawn out, go home — and a strong
/// aversion to knocking out its own side. Everything subtler than that is left
/// out on purpose: a beginner who never blunders is not a beginner.
///
/// The feature set is intentionally tiny and the jitter wide, which is what
/// produces the "plausible but clearly improvable" feel the difficulty is
/// supposed to have.
///
/// Reproducible: the generator is seeded from the agent's seed combined with
/// the position's `stableKey`, so the same agent in the same position always
/// plays the same move — across runs and across devices.
public struct EasyAgent: AIAgent, Sendable {
    public let difficulty = AIDifficulty.easy

    /// Distinguishes one Easy opponent from another at the same table, so four
    /// Easy agents do not all think identically.
    public let seed: UInt64

    public init(seed: UInt64 = 0xEA51_0000_0000_0001) {
        self.seed = seed
    }

    // MARK: - Weights
    //
    // Relative multipliers on a base weight of 1. Documented here rather than
    // scattered through the code so a change is visible in review (§146).

    /// Landing on an opponent and sending it home.
    static let captureOpponent = 2.0
    /// Bringing a fresh pawn onto the board.
    static let bringPawnOut = 1.2
    /// Reaching the home lane.
    static let reachHome = 3.0
    /// Knocking out your own or your partner's pawn. Large enough that Easy
    /// effectively only does it when the forced-move rule leaves no choice,
    /// but not disqualifying — in Classic Keezen that situation is real (§14).
    static let captureFriendly = -6.0
    /// Giving up the blockade on your own start square while pawns still wait
    /// behind it.
    static let abandonOwnStart = -0.6
    /// Random spread applied to every candidate, as a multiplier range.
    static let jitter: ClosedRange<Double> = 0.7...1.3
    /// No candidate ever reaches zero weight: a move the rules force must stay
    /// reachable.
    static let minimumWeight = 0.02

    // MARK: - Decision

    public func chooseAction(for observation: PlayerObservation) async -> PlayerAction {
        guard !observation.legalMoves.isEmpty else { return forcedFold(for: observation) }

        var generator = SeededGenerator(seed: seed ^ observation.stableKey)
        let candidates = observation.previewAll()
        guard !candidates.isEmpty else {
            // Every legal move should preview; if one somehow does not, fall
            // back to a legal move rather than to nothing.
            return .play(observation.legalMoves[0])
        }

        let weights = candidates.map { candidate in
            max(
                Self.minimumWeight,
                Self.weight(of: candidate.move, preview: candidate.preview, in: observation)
                    * Self.randomJitter(using: &generator)
            )
        }
        let index = Self.pick(weights: weights, using: &generator)
        return .play(candidates[index].move)
    }

    // MARK: - Scoring

    static func weight(of move: Move, preview: MovePreview, in observation: PlayerObservation) -> Double {
        var weight = 1.0

        for captured in preview.captured {
            let friendly = captured.seat == observation.seat
                || observation.isAlly(captured.seat)
            weight += friendly ? captureFriendly : captureOpponent
        }

        if case .enterFromWaiting = move.action {
            weight += bringPawnOut
        }

        weight += reachHome * Double(preview.reachedHome.count)

        if abandonsOwnStart(move, preview: preview, in: observation) {
            weight += abandonOwnStart
        }

        return weight
    }

    /// True when the move vacates a protected start square that was still
    /// useful — that is, the seat has pawns waiting to come out behind it.
    private static func abandonsOwnStart(
        _ move: Move,
        preview: MovePreview,
        in observation: PlayerObservation
    ) -> Bool {
        for id in move.involvedPawns {
            let startSquare = BoardPosition.track(index: observation.board.startIndex(for: id.seat))
            let wasOnStart = observation.pawns[id.seat.index * pawnsPerSeat + id.slot].position == startSquare
            guard wasOnStart, preview.pawn(id).position != startSquare else { continue }
            let stillWaiting = observation.pawns(of: id.seat).contains(where: \.isWaiting)
            if stillWaiting { return true }
        }
        return false
    }

    // MARK: - Weighted draw

    static func randomJitter(using generator: inout SeededGenerator) -> Double {
        let unit = Double(generator.next() % 1_000_001) / 1_000_000
        return jitter.lowerBound + unit * (jitter.upperBound - jitter.lowerBound)
    }

    /// Picks an index with probability proportional to its weight.
    static func pick(weights: [Double], using generator: inout SeededGenerator) -> Int {
        let total = weights.reduce(0, +)
        guard total > 0 else { return 0 }
        let threshold = Double(generator.next() % 1_000_001) / 1_000_000 * total
        var running = 0.0
        for (index, weight) in weights.enumerated() {
            running += weight
            if running >= threshold { return index }
        }
        return weights.count - 1
    }
}
