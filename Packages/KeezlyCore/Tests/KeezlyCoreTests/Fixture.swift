import Foundation
@testable import KeezlyCore

/// Builds precise board situations for rule tests.
///
/// Rule tests must not have to deal ten random hands to reach the situation
/// they care about (the same requirement the screenshot fixtures have, §88).
/// Everything here goes through the real `GameState`, so a fixture can never
/// describe a position the engine considers impossible.
enum Fixture {

    /// A hand-built state. Any pawn not listed stays in its waiting area.
    static func state(
        seatCount: Int,
        teamMode: TeamMode? = nil,
        rules: RuleSet = .keezlyClassic,
        pawns: [PawnID: BoardPosition] = [:],
        hands: [Int: [CardRank]] = [:],
        discard: [Card] = [],
        deck: [Card] = [],
        currentSeat: Int = 0,
        dealer: Int? = nil,
        seed: UInt64 = 1
    ) -> GameState {
        let mode = teamMode ?? ((seatCount == 4 || seatCount == 6) ? .teamsOfTwo : .freeForAll)
        let configuration = GameConfiguration(
            seatCount: seatCount,
            teamMode: mode,
            ruleSet: rules,
            initialDealer: Seat(dealer ?? (seatCount - 1))
        )

        var pawnStates = configuration.seats.flatMap { seat in
            (0..<pawnsPerSeat).map { slot in
                PawnState(id: PawnID(seat: seat, slot: slot), position: .waiting(seat: seat, slot: slot))
            }
        }
        for (id, position) in pawns {
            pawnStates[id.seat.index * pawnsPerSeat + id.slot].position = position
        }

        var builtHands = Array(repeating: Hand(), count: seatCount)
        for (seatIndex, ranks) in hands {
            builtHands[seatIndex] = Hand(cards: ranks.map { Card(rank: $0, deckCopy: seatIndex) })
        }

        return GameState(
            configuration: configuration,
            pawns: pawnStates,
            hands: builtHands,
            // Rule tests never draw, so the deck defaults to empty: an
            // accidental deal then fails loudly instead of quietly rewriting
            // the fixture's hands.
            deck: Deck(cards: deck),
            discardPile: discard,
            dealer: Seat(dealer ?? (seatCount - 1)),
            currentSeat: Seat(currentSeat),
            deal: DealState(),
            foldedSeats: [],
            resignedSeats: [],
            rng: SeededGenerator(seed: seed),
            revision: 0,
            result: nil
        )
    }

    static func pawn(_ seat: Int, _ slot: Int) -> PawnID {
        PawnID(seat: Seat(seat), slot: slot)
    }

    static func card(_ rank: CardRank, seat: Int = 0) -> Card {
        Card(rank: rank, deckCopy: seat)
    }
}

extension GameState {
    /// Convenience for assertions: where a pawn currently stands.
    func position(of id: PawnID) -> BoardPosition { pawn(id).position }
}

extension [Move] {
    /// All destinations a set of moves would send `pawn` to.
    func destinations(for pawn: PawnID, in state: GameState) -> Set<BoardPosition> {
        var result = Set<BoardPosition>()
        for move in self {
            guard let transition = try? GameReducer.apply(.play(move), to: state) else { continue }
            if transition.state.position(of: pawn) != state.position(of: pawn) {
                result.insert(transition.state.position(of: pawn))
            }
        }
        return result
    }
}
