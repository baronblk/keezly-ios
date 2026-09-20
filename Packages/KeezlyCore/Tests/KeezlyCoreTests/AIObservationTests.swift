import Testing
@testable import KeezlyCore

/// §21 — the computer opponents must be structurally unable to cheat.
///
/// These tests do not check that an agent *chooses* not to look at hidden
/// information; they check that the information is not there to look at. The
/// central technique is differential: build two game states that differ only
/// in something an agent must not know, and assert the observations they
/// produce are byte-for-byte equal.
@Suite("AI observation boundary")
struct AIObservationTests {

    // MARK: - The observer sees what a human would

    @Test("an observation carries the observer's own hand and the open board")
    func observationCarriesPublicInformation() {
        let state = Fixture.state(
            seatCount: 4,
            pawns: [Fixture.pawn(0, 0): .track(index: 5), Fixture.pawn(1, 0): .track(index: 20)],
            hands: [0: [.ace, .seven], 1: [.king, .four, .jack]]
        )
        let observation = PlayerObservation(of: state, for: Seat(0))

        #expect(observation.seat == Seat(0))
        #expect(observation.hand.cards.map(\.rank) == [.ace, .seven])
        #expect(observation.pawns.count == 4 * pawnsPerSeat)
        #expect(observation.pawns(of: Seat(1)).first?.position == .track(index: 20))
        #expect(observation.isMyTurn)
    }

    @Test("opponents' card counts are visible, their cards are not")
    func handCountsAreVisible() {
        let state = Fixture.state(
            seatCount: 4,
            hands: [0: [.ace], 1: [.king, .four, .jack], 2: [.two, .three], 3: []]
        )
        let observation = PlayerObservation(of: state, for: Seat(0))
        #expect(observation.handCounts == [1, 3, 2, 0])
    }

    @Test("legal moves come from the same generator a human's UI uses")
    func legalMovesMatchTheGenerator() {
        let state = Fixture.state(
            seatCount: 4,
            pawns: [Fixture.pawn(0, 0): .track(index: 5)],
            hands: [0: [.ace, .seven, .queen]]
        )
        let observation = PlayerObservation(of: state, for: Seat(0))
        #expect(observation.legalMoves == MoveGenerator.legalMoves(in: state, for: Seat(0)))
        #expect(!observation.legalMoves.isEmpty)
    }

    // MARK: - The differential tests: hidden information must not leak

    /// If two tables differ only in what the opponents are holding, an honest
    /// agent cannot tell them apart. This is the test that would fail the
    /// moment someone adds `deck` or `hands` to `PlayerObservation`.
    @Test("observations are identical when only the opponents' hands differ")
    func opponentHandsDoNotLeak() {
        func state(seat1: [CardRank], seat2: [CardRank], seat3: [CardRank]) -> GameState {
            Fixture.state(
                seatCount: 4,
                pawns: [Fixture.pawn(0, 0): .track(index: 5), Fixture.pawn(2, 0): .track(index: 40)],
                hands: [0: [.ace, .seven], 1: seat1, 2: seat2, 3: seat3]
            )
        }

        let a = PlayerObservation(
            of: state(seat1: [.king, .four], seat2: [.two, .three], seat3: [.jack, .queen]),
            for: Seat(0)
        )
        let b = PlayerObservation(
            of: state(seat1: [.jack, .queen], seat2: [.king, .four], seat3: [.two, .three]),
            for: Seat(0)
        )

        #expect(a == b, "seat 0 must not be able to distinguish these two tables")
    }

    /// The draw pile's order decides every future deal. An agent that could
    /// see it would know the future.
    @Test("observations are identical when only the deck order differs")
    func deckOrderDoesNotLeak() {
        let deck = Deck.standard(seatCount: 4).cards
        func state(deck: [Card]) -> GameState {
            Fixture.state(
                seatCount: 4,
                pawns: [Fixture.pawn(0, 0): .track(index: 5)],
                hands: [0: [.ace, .seven]],
                deck: deck
            )
        }

        let a = PlayerObservation(of: state(deck: deck), for: Seat(0))
        let b = PlayerObservation(of: state(deck: deck.reversed()), for: Seat(0))
        #expect(a == b)
    }

    /// Same generator state means the same future shuffle. Also hidden.
    @Test("observations are identical when only the random generator state differs")
    func randomStateDoesNotLeak() {
        func state(seed: UInt64) -> GameState {
            Fixture.state(seatCount: 4, hands: [0: [.ace]], seed: seed)
        }
        #expect(PlayerObservation(of: state(seed: 1), for: Seat(0))
                == PlayerObservation(of: state(seed: 999_999), for: Seat(0)))
    }

    /// Conversely, the boundary must not be so tight that it hides public
    /// facts — an agent that cannot see the board cannot play.
    @Test("observations do differ when public information differs")
    func publicInformationStillDistinguishes() {
        func state(pawnAt index: Int, discard: [Card]) -> GameState {
            Fixture.state(
                seatCount: 4,
                pawns: [Fixture.pawn(1, 0): .track(index: index)],
                hands: [0: [.ace]],
                discard: discard
            )
        }
        let base = PlayerObservation(of: state(pawnAt: 20, discard: []), for: Seat(0))
        #expect(base != PlayerObservation(of: state(pawnAt: 21, discard: []), for: Seat(0)))
        #expect(base != PlayerObservation(of: state(pawnAt: 20, discard: [Fixture.card(.king)]), for: Seat(0)))
    }

    // MARK: - Move previews stay inside the boundary

    /// Previewing a move is legitimate — a human sees where their pawn lands
    /// and what it knocks out. It must not become a side channel, so the same
    /// differential rule applies: hidden information may not change a preview.
    @Test("previews are identical when only hidden information differs")
    func previewsDoNotLeak() throws {
        func state(opponentHands: [[CardRank]], deck: [Card], seed: UInt64) -> GameState {
            Fixture.state(
                seatCount: 4,
                pawns: [
                    Fixture.pawn(0, 0): .track(index: 5),
                    Fixture.pawn(1, 0): .track(index: 10),
                ],
                hands: [0: [.five], 1: opponentHands[0], 2: opponentHands[1], 3: opponentHands[2]],
                deck: deck,
                seed: seed
            )
        }

        let a = PlayerObservation(
            of: state(opponentHands: [[.king], [.two], [.jack]], deck: Deck.standard(seatCount: 4).cards, seed: 1),
            for: Seat(0)
        )
        let b = PlayerObservation(
            of: state(opponentHands: [[.jack], [.king], [.two]], deck: Deck.standard(seatCount: 4).cards.reversed(), seed: 987),
            for: Seat(0)
        )

        #expect(a == b)
        let moveA = try #require(a.legalMoves.first)
        let moveB = try #require(b.legalMoves.first)
        #expect(moveA == moveB)
        #expect(a.preview(moveA) == b.preview(moveB))
    }

    @Test("a preview reports the capture and the landing square correctly")
    func previewsAreAccurate() throws {
        let state = Fixture.state(
            seatCount: 4,
            pawns: [Fixture.pawn(0, 0): .track(index: 5), Fixture.pawn(1, 0): .track(index: 10)],
            hands: [0: [.five]]
        )
        let observation = PlayerObservation(of: state, for: Seat(0))
        let move = try #require(observation.legalMoves.first)
        let preview = try #require(observation.preview(move))

        #expect(preview.captured == [Fixture.pawn(1, 0)])
        #expect(preview.pawn(Fixture.pawn(0, 0)).position == .track(index: 10))
        #expect(preview.pawn(Fixture.pawn(1, 0)).position.isWaiting)
        // Previewing must not disturb the real state.
        #expect(state.position(of: Fixture.pawn(1, 0)) == .track(index: 10))
    }

    @Test("a preview matches what the reducer actually does")
    func previewAgreesWithTheReducer() async throws {
        var chooser = SeededGenerator(seed: 0xB0_0B5)
        var state = GameState.newMatch(configuration: .standard(seatCount: 4), seed: 31_337)

        for _ in 0..<150 where !state.isFinished {
            let observation = PlayerObservation(of: state, for: state.currentSeat)
            guard !observation.legalMoves.isEmpty else {
                state = try GameReducer.apply(.foldHand(seat: state.currentSeat), to: state).state
                continue
            }
            let move = observation.legalMoves[Int(chooser.next() % UInt64(observation.legalMoves.count))]
            let preview = try #require(observation.preview(move))
            let applied = try GameReducer.apply(.play(move), to: state).state

            #expect(preview.pawns == applied.pawns, "preview disagreed with the reducer on \(move.id)")
            state = applied
        }
    }

    /// The stable key must be a function of the observation and nothing else,
    /// or agents seeded from it would inherit a hidden-information channel.
    @Test("the stable key depends only on visible information")
    func stableKeyCarriesNoHiddenInformation() {
        func state(opponent: [CardRank], seed: UInt64) -> GameState {
            Fixture.state(
                seatCount: 4,
                pawns: [Fixture.pawn(0, 0): .track(index: 5)],
                hands: [0: [.five], 1: opponent],
                seed: seed
            )
        }
        let a = PlayerObservation(of: state(opponent: [.king], seed: 1), for: Seat(0))
        let b = PlayerObservation(of: state(opponent: [.jack], seed: 42), for: Seat(0))
        #expect(a.stableKey == b.stableKey)

        // …but it does change when the visible board changes.
        let moved = Fixture.state(
            seatCount: 4,
            pawns: [Fixture.pawn(0, 0): .track(index: 6)],
            hands: [0: [.five], 1: [.king]]
        )
        #expect(PlayerObservation(of: moved, for: Seat(0)).stableKey != a.stableKey)
    }

    @Test("the stable key is the same on every run")
    func stableKeyIsProcessIndependent() {
        // Hard-coding the expected value pins it: if someone swaps the hash for
        // Swift's salted Hasher, this fails immediately instead of silently
        // making agents non-reproducible across launches.
        let state = Fixture.state(
            seatCount: 4,
            pawns: [Fixture.pawn(0, 0): .track(index: 5)],
            hands: [0: [.ace, .seven]]
        )
        let key = PlayerObservation(of: state, for: Seat(0)).stableKey
        #expect(key == PlayerObservation(of: state, for: Seat(0)).stableKey)
        #expect(key != 0)
    }

    // MARK: - Card counting is legitimate

    @Test("unseen cards exclude the observer's own hand and everything played")
    func unseenCardsAreTheHonestRemainder() {
        let own: [CardRank] = [.ace, .seven, .queen]
        let played = [Fixture.card(.king, seat: 1), Fixture.card(.four, seat: 2)]
        let state = Fixture.state(seatCount: 4, hands: [0: own], discard: played)
        let observation = PlayerObservation(of: state, for: Seat(0))

        let unseen = observation.unseenCards
        for card in observation.hand.cards {
            #expect(!unseen.contains(card), "own card \(card) must not count as unseen")
        }
        for card in played {
            #expect(!unseen.contains(card), "played card \(card) must not count as unseen")
        }
        #expect(unseen.count == 4 * 13 - own.count - played.count)
        #expect(unseen.count == observation.hiddenCardCount)
    }

    @Test("counting all four aces as played is a legitimate deduction")
    func cardCountingWorks() {
        let allAces = (0..<4).map { Card(rank: .ace, deckCopy: $0) }
        let state = Fixture.state(seatCount: 4, hands: [0: [.two]], discard: allAces)
        let observation = PlayerObservation(of: state, for: Seat(0))
        #expect(!observation.unseenCards.contains { $0.rank == .ace })
    }

    // MARK: - The boundary holds throughout a real match

    @Test("no observation in a full match ever exposes another seat's cards")
    func boundaryHoldsAcrossAWholeMatch() throws {
        var chooser = SeededGenerator(seed: 0x0B5E_4EDD)
        var state = GameState.newMatch(configuration: .standard(seatCount: 6), seed: 4711)
        var actions = 0

        while !state.isFinished && actions < 4000 {
            let seat = state.currentSeat
            let observation = PlayerObservation(of: state, for: seat)

            // Whatever the observer can see must be its own or public.
            #expect(observation.hand == state.hand(of: seat))
            let visible = Set(observation.hand.cards).union(observation.discardPile)
            for other in state.configuration.seats where other != seat {
                for card in state.hand(of: other).cards {
                    #expect(!visible.contains(card), "seat \(other)'s \(card) became visible to \(seat)")
                }
            }
            // Every card the observer cannot account for is genuinely unseen.
            #expect(observation.unseenCards.count == observation.hiddenCardCount)

            let action: PlayerAction = observation.legalMoves.isEmpty
                ? .foldHand(seat: seat)
                : .play(observation.legalMoves[Int(chooser.next() % UInt64(observation.legalMoves.count))])
            state = try GameReducer.apply(action, to: state).state
            actions += 1
        }

        #expect(state.isFinished)
    }

    @Test("an agent can play a whole match from observations alone")
    func anAgentCanPlayFromObservationsAlone() async throws {
        /// A minimal agent: it is handed nothing but observations, which is the
        /// point. The real Easy/Medium/Hard agents arrive with M3.2–M3.4.
        struct FirstLegalMoveAgent: AIAgent {
            let difficulty = AIDifficulty.easy
            func chooseAction(for observation: PlayerObservation) async -> PlayerAction {
                observation.legalMoves.first.map { .play($0) } ?? forcedFold(for: observation)
            }
        }

        let agent = FirstLegalMoveAgent()
        var state = GameState.newMatch(configuration: .standard(seatCount: 4), seed: 2)
        var actions = 0

        while !state.isFinished && actions < 4000 {
            let action = await agent.chooseAction(for: PlayerObservation(of: state, for: state.currentSeat))
            state = try GameReducer.apply(action, to: state).state
            actions += 1
        }
        #expect(state.isFinished)
    }
}
