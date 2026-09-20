import Foundation

/// The strong opponent (§24).
///
/// Hard starts from the Medium evaluation and then asks a question Medium
/// cannot: *how does this tend to turn out?* It samples plausible worlds from
/// the cards it has not seen, plays each one forward with a cheap policy, and
/// prefers the candidate whose futures look best on average.
///
/// It never knows a real opponent card. Every sampled hand is its own guess,
/// drawn only from `observation.unseenCards` — which is why card counting makes
/// it sharper: as cards are played, the space of plausible worlds narrows.
///
/// Time-boxed and cancellable: the search stops at the budget or when the task
/// is cancelled, and returns the best candidate found so far. It never blocks
/// the main actor, because it is only ever awaited from a detached task.
public struct HardAgent: AIAgent, Sendable {
    public let difficulty = AIDifficulty.hard
    public let seed: UInt64
    public let budget: AIBudget
    public let weights: HeuristicWeights

    /// How many of the heuristically best moves get simulated. Rolling out
    /// every legal move would spend the budget on obvious mistakes; a Seven
    /// alone can offer dozens of splits.
    public let candidateLimit: Int
    /// Worlds sampled per candidate.
    public let samplesPerCandidate: Int
    /// How far each sampled world is played forward.
    public let rolloutPlies: Int
    /// How heavily the rollout average counts against the static evaluation.
    public let rolloutWeight: Double

    public init(
        seed: UInt64 = 0xDEC0_0000_0000_0003,
        budget: AIBudget = .interactive,
        weights: HeuristicWeights = .hard,
        candidateLimit: Int = 6,
        samplesPerCandidate: Int = 8,
        rolloutPlies: Int = 8,
        rolloutWeight: Double = 0.45
    ) {
        self.seed = seed
        self.budget = budget
        self.weights = weights
        self.candidateLimit = candidateLimit
        self.samplesPerCandidate = samplesPerCandidate
        self.rolloutPlies = rolloutPlies
        self.rolloutWeight = rolloutWeight
    }

    public func chooseAction(for observation: PlayerObservation) async -> PlayerAction {
        guard !observation.legalMoves.isEmpty else { return forcedFold(for: observation) }

        var generator = SeededGenerator(seed: seed ^ observation.stableKey)
        let clock = ContinuousClock()
        let deadline = clock.now + budget.maximumDuration

        // Static pass: score everything, keep the plausible candidates.
        let scored = observation.previewAll()
            .map { candidate in
                (
                    move: candidate.move,
                    preview: candidate.preview,
                    staticScore: PositionEvaluator.score(
                        move: candidate.move, preview: candidate.preview,
                        in: observation, weights: weights
                    )
                )
            }
            .sorted { $0.staticScore > $1.staticScore }

        guard let front = scored.first else { return .play(observation.legalMoves[0]) }
        let candidates = Array(scored.prefix(candidateLimit))
        guard candidates.count > 1 else { return .play(front.move) }

        // Sampling pass: play each candidate out in several plausible worlds.
        var best = (move: front.move, score: -Double.infinity)
        for candidate in candidates {
            if Task.isCancelled { break }

            var rolloutTotal = 0.0
            var samples = 0
            for _ in 0..<samplesPerCandidate {
                if clock.now >= deadline || Task.isCancelled { break }

                let world = Determinization.sample(from: observation, using: &generator)
                // The candidate is legal in the real position, and a sampled
                // world shares its pawns and the agent's own hand, so it is
                // legal here too. If that ever stops holding, stop sampling
                // rather than guessing.
                guard let afterMove = try? GameReducer.apply(.play(candidate.move), to: world).state else { break }

                rolloutTotal += RolloutPolicy.playOut(
                    afterMove, for: observation.seat, plies: rolloutPlies, using: &generator
                )
                samples += 1
                // A rollout cut short by cancellation is not evidence; stop
                // rather than averaging in a truncated result.
                if Task.isCancelled { break }
            }

            // With no samples, the static score stands on its own.
            let combined = samples == 0
                ? candidate.staticScore
                : candidate.staticScore + rolloutWeight * (rolloutTotal / Double(samples))

            if combined > best.score { best = (candidate.move, combined) }

            // Give cancellation a chance between candidates.
            await Task.yield()
        }

        return .play(best.move)
    }
}
