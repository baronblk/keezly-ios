import Foundation

/// The heuristic opponent (§23).
///
/// Medium previews every legal move, scores the resulting position with
/// `PositionEvaluator`, and plays the best one. It plans exactly one move
/// ahead: it does not search, and it does not model what opponents will do
/// beyond the static risk term. That is the honest ceiling of a heuristic
/// agent, and the gap it leaves is what Hard fills with rollouts.
///
/// Deterministic for a given seed and position, like every Keezly agent.
public struct MediumAgent: AIAgent, Sendable {
    public let difficulty = AIDifficulty.medium
    public let weights: HeuristicWeights
    public let seed: UInt64

    public init(seed: UInt64 = 0xED10_0000_0000_0001, weights: HeuristicWeights = .medium) {
        self.seed = seed
        self.weights = weights
    }

    public func chooseAction(for observation: PlayerObservation) async -> PlayerAction {
        guard !observation.legalMoves.isEmpty else { return forcedFold(for: observation) }

        var generator = SeededGenerator(seed: seed ^ observation.stableKey)
        var best: (move: Move, score: Double)?

        for candidate in observation.previewAll() {
            var score = PositionEvaluator.score(
                move: candidate.move,
                preview: candidate.preview,
                in: observation,
                weights: weights
            )
            // A little noise, applied to the score rather than to the choice,
            // so near-equal options vary while clearly better ones do not.
            if weights.jitter > 0 {
                let unit = Double(generator.next() % 2_000_001) / 1_000_000 - 1.0
                score += unit * weights.jitter
            }
            if best == nil || score > best!.score {
                best = (candidate.move, score)
            }
        }

        guard let best else { return .play(observation.legalMoves[0]) }
        return .play(best.move)
    }
}
