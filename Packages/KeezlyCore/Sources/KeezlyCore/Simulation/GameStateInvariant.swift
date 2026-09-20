import Foundation

/// Structural checks that must hold for every reachable game state (§65).
///
/// These live in the library rather than in the test target because the
/// headless simulator runs them on every action of every simulated match
/// (§112), and the DEBUG developer menu uses them too. They are diagnostics,
/// not rules: a violation means the engine is broken, never that a player did
/// something wrong.
public enum GameStateInvariant {

    /// Every violation found, as human-readable strings. Empty means healthy.
    ///
    /// - Parameter previous: the state before the last action, when available.
    ///   Supplying it enables the checks that compare two states — a pawn
    ///   leaving home, or the revision counter going backwards.
    public static func violations(in state: GameState, previous: GameState? = nil) -> [String] {
        var problems: [String] = []
        let configuration = state.configuration
        let expectedPawns = configuration.seatCount * pawnsPerSeat

        // Pawns exist, exactly once each.
        if state.pawns.count != expectedPawns {
            problems.append("pawn count is \(state.pawns.count), expected \(expectedPawns)")
        }
        if Set(state.pawns.map(\.id)).count != state.pawns.count {
            problems.append("duplicate pawn id")
        }

        // No square holds two pawns. Waiting slots are per-seat, so the whole
        // position value is the right key.
        let positions = state.pawns.map(\.position)
        if Set(positions).count != positions.count {
            problems.append("two pawns occupy the same position")
        }

        // Pawns stay inside their own private areas and on the real track.
        for pawn in state.pawns {
            if let owner = pawn.position.owningSeat, owner != pawn.id.seat {
                problems.append("\(pawn.id) stands in \(owner)'s private area")
            }
            if let index = pawn.position.trackIndex,
               !(0..<state.board.mainTrackCount).contains(index) {
                problems.append("\(pawn.id) is on track index \(index), out of range")
            }
            if case .home(_, let slot) = pawn.position, !(0..<pawnsPerSeat).contains(slot) {
                problems.append("\(pawn.id) is in home slot \(slot), out of range")
            }
        }

        // Cards are conserved and unique.
        let inHands = configuration.seats.flatMap { state.hand(of: $0).cards }
        let all = inHands + state.discardPile + state.deck.cards
        let expectedCards = configuration.seatCount * DealState.cardsPerCycle
        if all.count != expectedCards {
            problems.append("\(all.count) cards in play, expected \(expectedCards)")
        }
        if Set(all).count != all.count {
            problems.append("a card exists more than once")
        }

        // A finished match is sealed.
        if state.isFinished, !MoveGenerator.legalMoves(in: state, for: state.currentSeat).isEmpty {
            problems.append("finished match still offers legal moves")
        }

        // Turn integrity.
        if !(0..<configuration.seatCount).contains(state.currentSeat.index) {
            problems.append("current seat \(state.currentSeat) is not at this table")
        }

        guard let previous else { return problems }

        // A pawn that reached home never comes back out (§16).
        let wasHome = Set(previous.pawns.filter(\.isHome).map(\.id))
        let isHome = Set(state.pawns.filter(\.isHome).map(\.id))
        for id in wasHome.subtracting(isHome).sorted() {
            problems.append("\(id) left its home lane")
        }

        // Revisions only ever move forward.
        if state.revision <= previous.revision {
            problems.append("revision went from \(previous.revision) to \(state.revision)")
        }

        // A decided match never changes its mind.
        if let before = previous.result, before != state.result {
            problems.append("result changed after the match was already decided")
        }

        return problems
    }
}
