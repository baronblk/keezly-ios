@testable import Keezly
import KeezlyCore
import Testing

/// §53 — what the game says out loud.
///
/// Speech is an output channel like the screen, and it is held to the same two
/// rules: it must say enough to play with, and it must not say anything a
/// sighted player could not see.
@Suite("Move narration")
@MainActor
struct MoveNarratorTests {

    private func played(seats: Int = 4, seed: UInt64, turns: Int) -> GameState {
        var state = GameState.newMatch(configuration: .standard(seatCount: seats), seed: seed)
        var generator = SeededGenerator(seed: seed &* 7 &+ 3)
        for _ in 0..<turns where state.result == nil {
            let legal = MoveGenerator.legalMoves(in: state, for: state.currentSeat)
            let action: PlayerAction = legal.isEmpty
                ? .foldHand(seat: state.currentSeat)
                : .play(legal[Int.random(in: 0..<legal.count, using: &generator)])
            guard let next = try? GameReducer.apply(action, to: state) else { break }
            state = next.state
        }
        return state
    }

    // MARK: - Enough to play with

    @Test("every pawn on the board is named distinctly")
    func pawnsAreDistinguishable() {
        let state = played(seed: 515, turns: 40)
        let observation = PlayerObservation(of: state, for: state.currentSeat)
        let names = state.pawns.map { MoveNarrator.pawn($0.id, in: observation) }

        #expect(names.allSatisfy { !$0.isEmpty })
        // Two pieces that sound the same cannot be told apart by a listener,
        // and a Jack swap needs both of them named.
        #expect(Set(names).count == names.count, "two pawns are described identically")
    }

    @Test("a square is described from the listener's own end of the board")
    func squaresAreRelativeToTheListener() {
        let state = GameState.newMatch(configuration: .standard(seatCount: 4), seed: 2026)
        let first = PlayerObservation(of: state, for: Seat(0))
        let second = PlayerObservation(of: state, for: Seat(1))
        // A track square is a different distance for each player, and saying
        // "square 17" to both would be saying nothing to either.
        let square = BoardPosition.track(index: 17)
        #expect(MoveNarrator.square(square, in: first) != MoveNarrator.square(square, in: second))
    }

    @Test("an occupied square says who is standing on it")
    func occupancyIsSpoken() {
        var found = false
        for turns in stride(from: 10, through: 80, by: 10) {
            let state = played(seed: 818, turns: turns)
            let observation = PlayerObservation(of: state, for: state.currentSeat)
            guard let standing = state.pawns.first(where: { !$0.isWaiting }) else { continue }
            let spoken = MoveNarrator.occupant(of: standing.position, in: observation)
            #expect(spoken != nil, "a square with a pawn on it reported nobody")
            #expect(MoveNarrator.occupant(of: .track(index: -1), in: observation) == nil)
            found = true
            break
        }
        #expect(found, "no pawn ever left the start, so nothing was tested")
    }

    @Test("a card is described the same way in the hand and in the list")
    func cardVocabularyIsShared() {
        for rank in CardRank.allCases {
            #expect(CardView.accessibilityLabel(for: rank) == MoveNarrator.card(rank))
            #expect(!MoveNarrator.rankName(rank).isEmpty)
        }
    }

    // MARK: - And nothing more

    /// **The narrator can only talk about cards the listener holds.**
    ///
    /// This does not prove the boundary — the compiler does that, by giving
    /// these functions a `PlayerObservation` and no way to reach a
    /// `GameState` (DEC-014). What it checks is the thing a refactor could
    /// quietly break: that every card *named* in the spoken output is one the
    /// player is holding. A list that started describing an opponent's Seven,
    /// however it came by it, would fail here.
    @Test("every card the list names is one the listener is holding")
    func onlyOwnCardsAreNamed() {
        for turns in [0, 15, 45, 90] {
            let state = played(seed: 626, turns: turns)
            let seat = state.currentSeat
            let observation = PlayerObservation(of: state, for: seat)
            let held = Set(observation.hand.cards)

            for entry in ActionList(observation: observation).entries {
                #expect(held.contains(entry.move.card), "the list offered a card the player is not holding")
            }
        }
    }

    /// The board is described without reference to any card at all.
    ///
    /// Pieces and squares are public information; cards are not. Keeping the
    /// two vocabularies apart is what makes the previous test meaningful.
    @Test("pawns and squares are described without naming a card")
    func boardSpeechMentionsNoCards() {
        let state = played(seed: 313, turns: 50)
        let observation = PlayerObservation(of: state, for: state.currentSeat)
        let rankWords = Set(CardRank.allCases.map { MoveNarrator.rankName($0).lowercased() })

        var spoken: [String] = state.pawns.map { MoveNarrator.pawn($0.id, in: observation) }
        spoken += state.pawns.map { MoveNarrator.square($0.position, in: observation) }

        for phrase in spoken {
            let words = Set(
                phrase.lowercased()
                    .split(whereSeparator: { !$0.isLetter })
                    .map(String.init)
            )
            #expect(words.isDisjoint(with: rankWords), "a board phrase named a card: \(phrase)")
        }
    }
}
