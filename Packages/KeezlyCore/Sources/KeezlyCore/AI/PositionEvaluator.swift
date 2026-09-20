import Foundation

/// Scores a board position from one seat's point of view (§23).
///
/// The design rule: **score the resulting state**, do not pattern-match the
/// move. A Jack that swaps a pawn 30 squares forward and a Ten that advances it
/// ten are the same kind of thing — progress — and both fall out of the
/// position score without a special case. Only effects that are genuinely not
/// visible in the resulting position (a capture, which removes information
/// about where the victim came from) get their own term.
public enum PositionEvaluator {

    /// Score of a candidate move: the resulting position, plus the terms for
    /// what the move itself did, minus the risk it leaves behind.
    public static func score(
        move: Move,
        preview: MovePreview,
        in observation: PlayerObservation,
        weights: HeuristicWeights = .medium
    ) -> Double {
        var score = positionScore(pawns: preview.pawns, in: observation, weights: weights)

        // Captures. The value of sending a pawn home scales with how far it had
        // come — knocking an opponent out one square from home is the strongest
        // single move in Keezen.
        for captured in preview.captured {
            let lost = observation.pawns[captured.seat.index * pawnsPerSeat + captured.slot]
            let lostProgress = Double(observation.progress(of: lost) ?? 0)
            if captured.seat == observation.seat || observation.isAlly(captured.seat) {
                score += weights.captureFriendly - lostProgress * weights.capturedProgressBonus
            } else {
                score += weights.captureOpponent + lostProgress * weights.capturedProgressBonus
            }
        }

        score += weights.reachHome * Double(preview.reachedHome.count)
        if case .enterFromWaiting = move.action { score += weights.bringPawnOut }

        score -= weights.exposureRisk * exposure(after: preview, in: observation, weights: weights)

        return score
    }

    // MARK: - Static position

    /// Value of a set of pawn positions, from `observation.seat`'s side.
    public static func positionScore(
        pawns: [PawnState],
        in observation: PlayerObservation,
        weights: HeuristicWeights = .medium
    ) -> Double {
        let board = observation.board
        var score = 0.0

        for pawn in pawns {
            let mine = pawn.id.seat == observation.seat || observation.isAlly(pawn.id.seat)
            var value = 0.0

            switch pawn.position {
            case .home:
                value = weights.pawnHome
            case .waiting:
                value = weights.pawnWaiting
            case .track(let index):
                let progress = board.progress(ofTrackIndex: index, for: pawn.id.seat)
                value = Double(progress) * weights.progressPerSquare
                if index == board.startIndex(for: pawn.id.seat) {
                    value += weights.blockade
                }
                if !mine {
                    // A pawn in the last quarter of its lap is a live threat.
                    let fraction = Double(progress) / Double(max(1, board.lapLength))
                    if fraction > 0.75 {
                        value += Double(progress) * weights.opponentNearHome * (fraction - 0.75) * 4
                    }
                }
            }

            score += mine ? value : -value * weights.opponentFactor
        }

        return score
    }

    // MARK: - Risk

    /// Estimated capture risk left on the agent's own pawns after a move.
    ///
    /// This is where card counting earns its keep. For each opponent pawn, the
    /// evaluator asks: how far behind one of my pawns is it, and how likely is
    /// it that this opponent still holds a card covering exactly that distance?
    /// "Likely" comes from `unseenCards` — the cards neither in the agent's
    /// hand nor already played — so an agent that has seen all four Queens go
    /// stops fearing a twelve.
    static func exposure(
        after preview: MovePreview,
        in observation: PlayerObservation,
        weights: HeuristicWeights
    ) -> Double {
        let board = observation.board
        let availability = rankAvailability(in: observation)
        var total = 0.0

        for pawn in preview.pawns {
            guard pawn.id.seat == observation.seat || observation.isAlly(pawn.id.seat),
                  let index = pawn.position.trackIndex
            else { continue }
            // A pawn on its own start square cannot be taken (§15).
            if index == board.startIndex(for: pawn.id.seat) { continue }

            let progress = board.progress(ofTrackIndex: index, for: pawn.id.seat)
            // Little travelled, little to lose.
            let stake = pow(Double(progress) / Double(max(1, board.lapLength)), weights.exposureProgressFactor)

            var threat = 0.0
            for hunter in preview.pawns {
                guard hunter.id.seat != observation.seat,
                      !observation.isAlly(hunter.id.seat),
                      let hunterIndex = hunter.position.trackIndex
                else { continue }

                let distance = (index - hunterIndex + board.mainTrackCount) % board.mainTrackCount
                let cards = Double(observation.handCounts[hunter.id.seat.index])
                guard cards > 0 else { continue }

                // Forward reach.
                if (1...13).contains(distance) {
                    threat += min(1.0, availability[distance] ?? 0) * min(1.0, cards / 4.0)
                }
                // A Four moves backward, so a hunter four squares *ahead* is
                // also dangerous (§11).
                let behind = (hunterIndex - index + board.mainTrackCount) % board.mainTrackCount
                if behind == 4 {
                    threat += min(1.0, availability[-4] ?? 0) * min(1.0, cards / 4.0)
                }
            }

            total += stake * min(1.0, threat)
        }

        return total
    }

    /// For each reachable distance, the share of still-unseen cards that could
    /// produce it. Negative keys mean backward distances.
    static func rankAvailability(in observation: PlayerObservation) -> [Int: Double] {
        let unseen = observation.unseenCards
        guard !unseen.isEmpty else { return [:] }
        let total = Double(unseen.count)

        var counts: [Int: Double] = [:]
        for card in unseen {
            for distance in forwardDistances(of: card.rank, rules: observation.ruleSet) {
                counts[distance, default: 0] += 1
            }
            if card.rank == .four { counts[-4, default: 0] += 1 }
        }
        return counts.mapValues { $0 / total }
    }

    /// Which forward distances a rank can produce.
    ///
    /// The Seven is credited with every distance from one to seven, because a
    /// split can spend any part of it on one pawn (§11). The Four is absent:
    /// it only moves backward. The Jack is absent: a swap is not a capture.
    static func forwardDistances(of rank: CardRank, rules: RuleSet) -> [Int] {
        switch rank {
        case .ace: [1]
        case .seven: [1, 2, 3, 4, 5, 6, 7]
        case .queen: [12]
        case .king: rules.king == .enterOrAdvance13 ? [13] : []
        case .jack, .four: []
        default: [rank.rawValue]
        }
    }
}
