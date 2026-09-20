import KeezlyCore

/// What tapping a highlighted square does.
enum TargetAction: Hashable {
    /// Completes the move; the session can apply it.
    case play(Move)
    /// Commits one leg of a Seven. More of the seven remains to be spent.
    case commitLeg(SplitStep)
}

/// Works out what the player may tap next.
///
/// Everything here is derived from the engine's **complete** legal moves. That
/// is what makes the Seven safe: the player can only ever commit a first leg
/// that some complete, legal sequence starts with, so there is no way to spend
/// three steps and discover the remaining four are unplayable (§38).
///
/// A value type, recomputed from the session on each render. It holds no state
/// of its own beyond the selection it is handed.
struct PlayPlanner {
    let observation: PlayerObservation
    /// The card the player has picked, if any.
    var card: Card?
    /// Legs of a Seven already committed, in order.
    var committedLegs: [SplitStep] = []
    /// The pawn picked for the leg being chosen.
    var pawn: PawnID?

    // MARK: - Candidates

    /// Legal moves still consistent with everything chosen so far.
    var candidates: [Move] {
        guard let card else { return observation.legalMoves }
        return observation.legalMoves.filter { move in
            guard move.card == card else { return false }
            guard !committedLegs.isEmpty else { return true }
            guard case .split(let steps) = move.action else { return false }
            return steps.count > committedLegs.count && Array(steps.prefix(committedLegs.count)) == committedLegs
        }
    }

    /// Cards the player can actually play. A card with no legal move is shown
    /// but not offered, rather than hidden — a player needs to see why they are
    /// stuck (§36).
    var playableCards: Set<Card> {
        Set(observation.legalMoves.map(\.card))
    }

    /// Pawns that can take the leg currently being chosen.
    var selectablePawns: Set<PawnID> {
        guard card != nil else { return [] }
        return Set(candidates.compactMap(nextLegPawn))
    }

    /// Where the chosen pawn can go, and what tapping there does.
    var targets: [BoardPosition: TargetAction] {
        guard card != nil, let pawn else { return [:] }
        var result: [BoardPosition: TargetAction] = [:]

        for move in candidates where nextLegPawn(of: move) == pawn {
            guard let preview = observation.preview(move) else { continue }

            if case .split(let steps) = move.action, steps.count > committedLegs.count + 1 {
                // More legs follow: tapping here commits this one.
                let leg = steps[committedLegs.count]
                let destination = destination(of: leg, in: move, preview: preview)
                result[destination] = .commitLeg(leg)
            } else {
                let destination = preview.pawn(pawn).position
                // A completing tap always wins over a leg-committing one, so a
                // player can finish rather than being forced deeper.
                result[destination] = .play(move)
            }
        }
        return result
    }

    /// Steps of a Seven still to spend, for the HUD. `nil` when no Seven is in
    /// progress.
    var remainingSevenSteps: Int? {
        guard card?.rank == .seven else { return nil }
        return 7 - committedLegs.reduce(0) { $0 + $1.steps }
    }

    /// Every square worth highlighting right now.
    var highlightedTargets: Set<BoardPosition> {
        Set(targets.keys)
    }

    /// The squares where tapping commits a leg of a Seven rather than
    /// finishing the move. The board names these differently so a test or a
    /// screenshot can land mid-split deliberately instead of by luck.
    var legTargets: Set<BoardPosition> {
        Set(targets.compactMap { position, action in
            if case .commitLeg = action { position } else { nil }
        })
    }

    // MARK: - Helpers

    /// The pawn that takes the next undecided leg of `move`.
    private func nextLegPawn(of move: Move) -> PawnID? {
        switch move.action {
        case .enterFromWaiting(let pawn), .advance(let pawn, _, _), .moveBackward(let pawn, _):
            pawn
        case .swap(let own, _):
            own
        case .split(let steps):
            steps.count > committedLegs.count ? steps[committedLegs.count].pawn : nil
        }
    }

    /// Where a leg's pawn ends up. Legs use distinct pawns, so the pawn's final
    /// position in the completed move is also its position after its own leg.
    private func destination(of leg: SplitStep, in move: Move, preview: MovePreview) -> BoardPosition {
        preview.pawn(leg.pawn).position
    }
}

extension PlayPlanner {
    /// The selection after tapping a card.
    func selecting(card: Card) -> PlayPlanner {
        var copy = self
        copy.card = card
        copy.committedLegs = []
        copy.pawn = nil
        return copy
    }

    /// The selection after tapping a pawn.
    func selecting(pawn: PawnID) -> PlayPlanner {
        var copy = self
        copy.pawn = pawn
        return copy
    }

    /// The selection after committing a leg of a Seven.
    func committing(leg: SplitStep) -> PlayPlanner {
        var copy = self
        copy.committedLegs.append(leg)
        copy.pawn = nil
        return copy
    }

    /// Back to nothing chosen. Cancelling must always be possible before the
    /// move is final (§37).
    func cleared() -> PlayPlanner {
        PlayPlanner(observation: observation)
    }
}
