import Foundation

/// The cheap policy that plays out a sampled world (§24).
///
/// Deliberately not the Medium agent: a rollout runs hundreds of times per
/// decision, so it drops the expensive risk term and scores only the resulting
/// position plus captures. Rollouts are there to reveal which candidate tends
/// to end well, not to play beautifully.
///
/// **This operates on a sampled `GameState`, never on the real one.** Agents
/// receive a `PlayerObservation`; the only states reaching this code are the
/// determinizations an agent built for itself out of public information.
enum RolloutPolicy {

    /// Weights used inside rollouts — the position terms only.
    static let weights = HeuristicWeights(exposureRisk: 0, jitter: 0)

    /// Picks a move greedily, with a little noise so rollouts explore.
    static func choose(
        in state: GameState,
        for seat: Seat,
        using generator: inout SeededGenerator
    ) -> PlayerAction {
        let moves = MoveGenerator.legalMoves(in: state, for: seat)
        guard !moves.isEmpty else { return .foldHand(seat: seat) }

        var best: (move: Move, score: Double)?
        for move in moves {
            var scratch = state
            let events = GameReducer.performAction(move.action, in: &scratch)
            guard !events.isEmpty else { continue }

            var score = score(pawns: scratch.pawns, for: seat, in: state)
            for event in events {
                if case .pawnCaptured(let pawn, _, _, _) = event {
                    let friendly = pawn.seat == seat || state.configuration.areAllied(pawn.seat, seat)
                    score += friendly ? weights.captureFriendly : weights.captureOpponent
                }
                if case .pawnReachedHome = event { score += weights.reachHome }
            }
            // A small spread keeps rollouts from being perfectly correlated.
            score += Double(generator.next() % 2_001) / 1_000 - 1.0

            if score > (best?.score ?? -.infinity) { best = (move, score) }
        }
        return best.map { .play($0.move) } ?? .play(moves[0])
    }

    /// Position value from one seat's side. Mirrors `PositionEvaluator`'s
    /// position term without the risk model.
    static func score(pawns: [PawnState], for seat: Seat, in state: GameState) -> Double {
        let board = state.board
        let configuration = state.configuration
        var total = 0.0

        for pawn in pawns {
            let mine = pawn.id.seat == seat || configuration.areAllied(pawn.id.seat, seat)
            var value = 0.0
            switch pawn.position {
            case .home:
                value = weights.pawnHome
            case .waiting:
                value = weights.pawnWaiting
            case .track(let index):
                value = Double(board.progress(ofTrackIndex: index, for: pawn.id.seat)) * weights.progressPerSquare
                if index == board.startIndex(for: pawn.id.seat) { value += weights.blockade }
            }
            total += mine ? value : -value * weights.opponentFactor
        }
        return total
    }

    /// Plays a sampled world forward and returns its value to `seat`.
    ///
    /// Stops at `plies`, at the end of the match, or when the task is
    /// cancelled — whichever comes first. The cancellation check belongs
    /// *inside* this loop, not only around it: a deep rollout is the longest
    /// uninterruptible stretch of work an agent does, and without the check a
    /// cancelled search keeps running to the end of the current playout.
    static func playOut(
        _ state: GameState,
        for seat: Seat,
        plies: Int,
        using generator: inout SeededGenerator
    ) -> Double {
        var current = state
        var played = 0

        while !current.isFinished && played < plies {
            if Task.isCancelled { break }
            let action = choose(in: current, for: current.currentSeat, using: &generator)
            guard let next = try? GameReducer.apply(action, to: current).state else { break }
            current = next
            played += 1
        }

        if let result = current.result {
            // A decided match dominates any positional consideration.
            let won = result.winningTeam == current.configuration.team(of: seat)
            return won ? 10_000 : -10_000
        }
        return score(pawns: current.pawns, for: seat, in: current)
    }
}
