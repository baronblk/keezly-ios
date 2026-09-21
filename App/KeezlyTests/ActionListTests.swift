@testable import Keezly
import KeezlyCore
import Testing

/// §53 — the accessible way to play must be a *complete* way to play.
///
/// The guarantee under test is not "the list is helpful". It is that the set of
/// moves reachable through the list is **equal** to the set the engine calls
/// legal — not a subset, not the common cases, not everything except the
/// awkward Seven splits. A player who cannot use the board is entitled to the
/// same game, and a list missing one move in a hundred positions is a list that
/// silently takes a move away from exactly the people who have no second route
/// to it.
@Suite("Accessible action list")
@MainActor
struct ActionListTests {

    /// Walks a match, stopping at each position where a given seat is on turn.
    ///
    /// Positions are reached by *playing*, so the ones this visits are real
    /// ones: openings with nothing but Aces and Kings, midgames full of Seven
    /// splits, endgames where most pawns are home and almost nothing is legal.
    private func positions(
        seats: Int,
        seed: UInt64,
        stopAfter: Int
    ) -> [GameState] {
        var state = GameState.newMatch(configuration: .standard(seatCount: seats), seed: seed)
        var generator = SeededGenerator(seed: seed &* 31 &+ 7)
        var visited: [GameState] = []

        while visited.count < stopAfter, state.result == nil {
            let seat = state.currentSeat
            let legal = MoveGenerator.legalMoves(in: state, for: seat)
            visited.append(state)

            let action: PlayerAction
            if legal.isEmpty {
                action = .foldHand(seat: seat)
            } else {
                // Chosen at random rather than "the first one": always taking
                // the first legal move walks one narrow corridor through the
                // game and never reaches a crowded midboard.
                action = .play(legal[Int.random(in: 0..<legal.count, using: &generator)])
            }
            guard let next = try? GameReducer.apply(action, to: state) else { break }
            state = next.state
        }
        return visited
    }

    // MARK: - The guarantee

    @Test(
        "every legal move is reachable through the list, and nothing else is",
        arguments: [
            (seats: 2, seed: UInt64(11)),
            (seats: 4, seed: UInt64(2026)),
            (seats: 4, seed: UInt64(77)),
            (seats: 6, seed: UInt64(404)),
        ]
    )
    func listIsExactlyTheEngine(seats: Int, seed: UInt64) throws {
        let visited = positions(seats: seats, seed: seed, stopAfter: 120)
        #expect(!visited.isEmpty, "the walk reached no position at all")

        var positionsWithMoves = 0
        for state in visited {
            let seat = state.currentSeat
            let engine = Set(MoveGenerator.legalMoves(in: state, for: seat))
            let list = ActionList(observation: PlayerObservation(of: state, for: seat))

            #expect(
                list.reachableMoves == engine,
                """
                the list and the engine disagree at revision \(state.revision): \
                missing \(engine.subtracting(list.reachableMoves).count), \
                invented \(list.reachableMoves.subtracting(engine).count)
                """
            )
            if !engine.isEmpty { positionsWithMoves += 1 }
        }
        // Otherwise the assertion above could pass on a hundred empty sets.
        #expect(positionsWithMoves > 20, "the walk found too few positions with moves to prove anything")
    }

    @Test("grouping by card loses nothing")
    func groupingIsLossless() {
        for state in positions(seats: 4, seed: 4242, stopAfter: 60) {
            let list = ActionList(observation: PlayerObservation(of: state, for: state.currentSeat))
            let regrouped = Set(list.byCard.flatMap(\.entries).map(\.move))
            #expect(regrouped == list.reachableMoves, "a move disappeared between the list and its sections")
        }
    }

    /// Seven splits are where a list most easily goes short: one card offers
    /// dozens of variants, and it is tempting to show "a Seven" once.
    @Test("every split variant of a Seven is its own entry")
    func sevenSplitsAreAllListed() throws {
        let match = MatchSession(
            configuration: .standard(seatCount: 4),
            seed: 2026,
            roles: [.human] + Array(repeating: SeatRole.computer(.medium), count: 3),
            fixture: .localCanPlay(.seven),
            fixtureLimit: 600
        )
        try #require(match.fixtureReached == true)

        let seat = match.state.currentSeat
        let engine = MoveGenerator.legalMoves(in: match.state, for: seat)
        let splits = engine.filter { if case .split = $0.action { true } else { false } }
        try #require(splits.count > 1, "the fixture was meant to offer several ways to split")

        let list = ActionList(observation: PlayerObservation(of: match.state, for: seat))
        #expect(Set(splits).isSubset(of: list.reachableMoves))
        // And each one is described distinctly: two rows reading the same
        // sentence are two rows a listener cannot choose between.
        let descriptions = list.entries
            .filter { if case .split = $0.move.action { true } else { false } }
            .map(\.description)
        #expect(Set(descriptions).count == descriptions.count, "two split rows read identically")
    }

    // MARK: - What the list says

    /// A pawn's phrase has to carry *where it is*, not only whose it is.
    ///
    /// "Red pawn 2" is the same words wherever it stands, and a player who
    /// hears only that cannot tell a piece in the start from one three squares
    /// short of home. So the phrase must change as the piece moves — and the
    /// distance it reports must count down.
    @Test("a pawn's phrase changes as the pawn moves, and counts down")
    func phrasesCarryPosition() throws {
        var distances: [Int] = []
        var phrases: Set<String> = []
        var subject: PawnID?

        for state in positions(seats: 4, seed: 313, stopAfter: 200) {
            let observation = PlayerObservation(of: state, for: Seat(0))
            // Whichever of seat 0's pawns is furthest along; once chosen, the
            // same one is followed so the comparison means something.
            let pawn = subject ?? observation.pawns(of: Seat(0))
                .first { !$0.isWaiting }?
                .id
            guard let pawn else { continue }
            subject = pawn
            guard !observation.pawns(of: Seat(0))[pawn.slot].isWaiting else { continue }

            phrases.insert(MoveNarrator.pawn(pawn, in: observation))
            distances.append(MoveNarrator.squaresFromHome(pawn, in: observation))
        }

        try #require(distances.count > 5, "the walk never kept one pawn on the board long enough")
        #expect(phrases.count > 1, "the pawn's phrase never changed as it travelled")
        let first = try #require(distances.first)
        let last = try #require(distances.last)
        #expect(first > last, "the distance to home never came down")
        #expect(distances.allSatisfy { $0 >= 0 }, "a pawn was described as being past home")
    }

    @Test("a capture is announced before it is made")
    func capturesAreAnnounced() {
        var found = false
        for state in positions(seats: 4, seed: 909, stopAfter: 200) {
            let observation = PlayerObservation(of: state, for: state.currentSeat)
            let list = ActionList(observation: observation)
            for (move, preview) in observation.previewAll() where !preview.captured.isEmpty {
                let entry = list.entries.first { $0.move == move }
                #expect(entry?.consequence != nil, "a capturing move was listed without saying so")
                #expect(entry?.spoken != entry?.description, "the consequence never reached the spoken row")
                found = true
            }
            if found { break }
        }
        #expect(found, "the walk never produced a capture, so nothing was tested")
    }
}
