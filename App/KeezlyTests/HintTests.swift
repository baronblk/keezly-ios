@testable import Keezly
import KeezlyCore
import Testing

/// §52, DEC-014 — a hint must not know more than the player.
///
/// The obvious way to write a hint is to evaluate the real `GameState`, which
/// would let it see the deck and every hand. It would give better advice and it
/// would be cheating, invisibly, in the one place a player has no way to check.
/// These tests hold the hint to the same boundary as an AI opponent.
@Suite("Hints")
struct HintTests {

    private func played(seed: UInt64, turns: Int) -> GameState {
        var state = GameState.newMatch(configuration: .standard(seatCount: 4), seed: seed)
        var generator = SeededGenerator(seed: seed &+ 17)
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

    // MARK: - The guarantee

    /// **A hint only ever suggests a move the engine calls legal.**
    @Test("a hint is always a legal move in the position it was asked about")
    func hintsAreLegal() async {
        for turns in [0, 12, 40, 90] {
            let state = played(seed: 4242, turns: turns)
            let seat = state.currentSeat
            let observation = PlayerObservation(of: state, for: seat)
            guard let hint = await HintProvider.hint(for: observation) else { continue }

            #expect(observation.legalMoves.contains(hint.move), "the hint suggested a move that is not legal")
            #expect(hint.move.seat == seat)
            #expect(!hint.description.isEmpty)
        }
    }

    /// **And it is built from an observation, so it cannot see a hidden card.**
    ///
    /// Checked the only way it can be: the card it suggests is one the player
    /// is holding. A hint working from the full state could suggest reasoning
    /// about a card in somebody else's hand; this one has no such card to name.
    @Test("a hint only ever names a card the player holds")
    func hintsSeeOnlyTheOwnHand() async {
        for turns in [0, 25, 60] {
            let state = played(seed: 909, turns: turns)
            let observation = PlayerObservation(of: state, for: state.currentSeat)
            guard let hint = await HintProvider.hint(for: observation) else { continue }
            #expect(observation.hand.cards.contains(hint.move.card))
        }
    }

    /// The same position gives the same advice.
    ///
    /// A hint that changed every time it was asked would be untrustworthy in a
    /// way that is hard to name and easy to feel.
    @Test("the same position always gives the same hint")
    func hintsAreStable() async {
        let state = played(seed: 3131, turns: 30)
        let observation = PlayerObservation(of: state, for: state.currentSeat)

        let first = await HintProvider.hint(for: observation)
        let second = await HintProvider.hint(for: observation)
        #expect(first == second)
    }

    /// A seat with no legal move gets no suggestion.
    ///
    /// Found by walking real positions rather than by building one: a seat
    /// that has thrown its hand in, or one whose cards are all blocked, is a
    /// position the game produces on its own. The count at the end is there so
    /// this cannot pass by never finding such a seat.
    @Test("a seat with nothing to play is offered nothing")
    func noMovesNoHint() async {
        var examined = 0
        for seed in [UInt64(11), 404, 2026] {
            var state = GameState.newMatch(configuration: .standard(seatCount: 4), seed: seed)
            var generator = SeededGenerator(seed: seed &+ 5)

            for _ in 0..<160 where state.result == nil {
                for seat in state.configuration.seats {
                    let observation = PlayerObservation(of: state, for: seat)
                    guard observation.legalMoves.isEmpty else { continue }
                    #expect(await HintProvider.hint(for: observation) == nil)
                    examined += 1
                }

                let legal = MoveGenerator.legalMoves(in: state, for: state.currentSeat)
                let action: PlayerAction = legal.isEmpty
                    ? .foldHand(seat: state.currentSeat)
                    : .play(legal[Int.random(in: 0..<legal.count, using: &generator)])
                guard let next = try? GameReducer.apply(action, to: state) else { break }
                state = next.state
            }
        }
        #expect(examined > 0, "the walk never found a seat with no legal move, so nothing was tested")
    }

    /// The suggestion is spoken in the same words as everything else.
    @Test("a hint is described in the app's own vocabulary")
    func hintsAreNarrated() async throws {
        let state = played(seed: 2026, turns: 20)
        let observation = PlayerObservation(of: state, for: state.currentSeat)
        let hint = try #require(await HintProvider.hint(for: observation))

        #expect(hint.description == MoveNarrator.move(hint.move, in: observation))
        #expect(hint.spoken.hasPrefix(hint.description))
        if let consequence = hint.consequence {
            #expect(hint.spoken.contains(consequence))
        }
    }

    // MARK: - Card help

    /// Every rank leads to a section of the rulebook that exists and says
    /// something, so a long press can never open an empty sheet.
    @Test("every card explains itself out of the rulebook")
    func everyCardHasHelp() {
        for rank in CardRank.allCases {
            let help = CardHelp(rank: rank)
            #expect(!help.title.isEmpty)
            #expect(!help.body.hasPrefix("rules."), "\(rank) shows a lookup key")
            #expect(help.body.count > 20, "\(rank) has nothing to say")

            // The section it points at is one the rulebook actually has, so
            // the two cannot drift apart.
            let section = CardHelp.section(for: rank)
            #expect(Rulebook.sections.contains { $0.id == section }, "\(rank) points at a missing section")
        }
    }

    @Test("the cards that behave unusually each get their own section")
    func specialCardsAreNotLumpedTogether() {
        let special: [CardRank: String] = [
            .ace: "ace", .king: "king", .queen: "queen",
            .jack: "jack", .four: "four", .seven: "seven",
        ]
        for (rank, section) in special {
            #expect(CardHelp.section(for: rank) == section)
        }
        // And the plain numbers share the one that describes what they do.
        for rank in [CardRank.two, .three, .five, .six, .eight, .nine, .ten] {
            #expect(CardHelp.section(for: rank) == "moving")
        }
    }
}
