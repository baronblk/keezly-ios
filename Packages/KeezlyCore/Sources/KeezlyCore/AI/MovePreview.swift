import Foundation

/// What a move would do to the board, computed from public information alone.
///
/// A human player can see this: the board is open, the rules are known, and
/// working out "if I play the Seven like that, I land there and knock his pawn
/// out" is ordinary play rather than privileged knowledge. Agents therefore get
/// it too (§21 — see `DECISIONS.md` → DEC-015 for why this widens the boundary
/// deliberately rather than by accident).
///
/// A preview says nothing about cards in anyone's hand, nor about what happens
/// after the move: it is the board transition and nothing more.
public struct MovePreview: Hashable, Sendable {
    /// Every pawn's position after the move.
    public let pawns: [PawnState]
    /// Pawns sent back to their waiting area by this move.
    public let captured: [PawnID]
    /// Pawns that entered a home lane as part of this move.
    public let reachedHome: [PawnID]
    /// Seats that completed all four pawns as part of this move.
    public let finishedSeats: [Seat]

    public func pawn(_ id: PawnID) -> PawnState {
        pawns[id.seat.index * pawnsPerSeat + id.slot]
    }
}

public extension PlayerObservation {

    /// The board effect of one legal move.
    ///
    /// Returns `nil` for a move that is not legal in this position; agents
    /// should only ever ask about members of `legalMoves`.
    func preview(_ move: Move) -> MovePreview? {
        var shadow = publicShadowState()
        return Self.preview(move, applyingTo: &shadow)
    }

    /// Previews every legal move, building the shadow board only once.
    ///
    /// This is what agents use: the per-move cost is then one array copy rather
    /// than a full reconstruction.
    func previewAll() -> [(move: Move, preview: MovePreview)] {
        let shadow = publicShadowState()
        return legalMoves.compactMap { move in
            var scratch = shadow
            guard let preview = Self.preview(move, applyingTo: &scratch) else { return nil }
            return (move, preview)
        }
    }

    // MARK: - Internals

    /// A game state containing *only* what this observation already knows.
    ///
    /// Deliberately not exposed. It exists so move mechanics can be reused
    /// rather than reimplemented, and it is constructed from observation
    /// fields alone — every other seat's hand is empty and the draw pile does
    /// not exist, so there is nothing hidden in it to leak.
    private func publicShadowState() -> GameState {
        var hands = Array(repeating: Hand(), count: configuration.seatCount)
        hands[seat.index] = hand
        return GameState(
            configuration: configuration,
            pawns: pawns,
            hands: hands,
            deck: Deck(cards: []),
            discardPile: discardPile,
            dealer: dealer,
            currentSeat: currentSeat,
            deal: deal,
            foldedSeats: foldedSeats,
            resignedSeats: resignedSeats,
            rng: SeededGenerator(seed: 1),
            revision: 0,
            result: nil
        )
    }

    private static func preview(_ move: Move, applyingTo shadow: inout GameState) -> MovePreview? {
        // Only the board part of the action is applied: no card is consumed, no
        // turn is passed, no victory is evaluated. A preview is a what-if, not
        // a move.
        let events = GameReducer.performAction(move.action, in: &shadow)
        guard !events.isEmpty else { return nil }

        var captured: [PawnID] = []
        var reachedHome: [PawnID] = []
        var finished: [Seat] = []
        for event in events {
            switch event {
            case .pawnCaptured(let pawn, _, _, _): captured.append(pawn)
            case .pawnReachedHome(let pawn, _): reachedHome.append(pawn)
            case .seatFinished(let seat): finished.append(seat)
            default: break
            }
        }
        return MovePreview(
            pawns: shadow.pawns,
            captured: captured,
            reachedHome: reachedHome,
            finishedSeats: finished
        )
    }
}
