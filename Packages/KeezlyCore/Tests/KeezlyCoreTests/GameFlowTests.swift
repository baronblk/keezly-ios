import Testing
@testable import KeezlyCore

/// §12, §13, §30 — dealing, the forced-move rule, and how matches end.
@Suite("Game flow")
struct GameFlowTests {

    /// An arbitrary but fixed seed, so determinism tests state what they mean.
    static let fixedSeed: UInt64 = 0xC0FF_EE00_1234_5678

    // MARK: - Dealing (§12)

    @Test("the deck holds thirteen cards per seat", arguments: 2...6)
    func deckSizeScalesWithTable(seatCount: Int) {
        #expect(Deck.standard(seatCount: seatCount).count == seatCount * 13)
    }

    @Test("a new match deals five cards to everyone", arguments: 2...6)
    func firstRoundDealsFive(seatCount: Int) {
        let state = GameState.newMatch(configuration: .standard(seatCount: seatCount), seed: 42)
        for seat in state.configuration.seats {
            #expect(state.hand(of: seat).count == 5)
        }
        #expect(state.deck.count == seatCount * 13 - seatCount * 5)
    }

    @Test("a 5/4/4 cycle deals thirteen cards and exhausts the deck exactly")
    func fullCycleExhaustsDeck() {
        var state = GameState.newMatch(configuration: .standard(seatCount: 4), seed: 7)
        var dealt = 5
        for _ in 0..<2 {
            state.advanceDealRound()
            dealt += state.deal.cardsThisRound
        }
        #expect(dealt == DealState.cardsPerCycle)
        #expect(dealt == 13)
        #expect(state.deck.isEmpty)
    }

    @Test("the player to the dealer's left opens the match")
    func firstTurnIsLeftOfDealer() {
        let configuration = GameConfiguration(seatCount: 5, teamMode: .freeForAll, initialDealer: Seat(3))
        let state = GameState.newMatch(configuration: configuration, seed: 1)
        #expect(state.currentSeat == Seat(4))
    }

    @Test("the dealer rotates after a completed 5/4/4 cycle")
    func dealerRotatesBetweenCycles() {
        var state = GameState.newMatch(configuration: .standard(seatCount: 4), seed: 3)
        let firstDealer = state.dealer
        state.advanceDealRound()
        #expect(state.dealer == firstDealer)   // still inside the cycle
        state.advanceDealRound()
        #expect(state.dealer == firstDealer)
        state.advanceDealRound()               // cycle complete → new dealer
        #expect(state.dealer == state.configuration.nextSeat(after: firstDealer))
        #expect(state.deck.count == 4 * 13 - 4 * 5)
    }

    // MARK: - Determinism (§20)

    @Test("the same seed always produces the same deal")
    func dealingIsDeterministic() {
        let a = GameState.newMatch(configuration: .standard(seatCount: 4), seed: Self.fixedSeed)
        let b = GameState.newMatch(configuration: .standard(seatCount: 4), seed: Self.fixedSeed)
        #expect(a == b)

        let c = GameState.newMatch(configuration: .standard(seatCount: 4), seed: Self.fixedSeed &+ 1)
        #expect(a != c)
    }

    // MARK: - Forced move (§13)

    @Test("a seat with no legal move at all may throw in its hand")
    func foldingIsAllowedWhenNothingIsPlayable() throws {
        // Every pawn still waiting and not a single Ace or King in hand.
        // Seat 1 is given a playable card so the deal round continues after the
        // fold: a round in which *nobody* can act is immediately redealt, and
        // redealing clears the folded set by design (§12).
        let state = Fixture.state(
            seatCount: 4,
            hands: [0: [.two, .three, .nine], 1: [.ace]],
            currentSeat: 0
        )
        #expect(!MoveGenerator.hasAnyLegalMove(in: state, for: Seat(0)))

        let transition = try GameReducer.apply(.foldHand(seat: Seat(0)), to: state)
        #expect(transition.state.foldedSeats.contains(Seat(0)))
        #expect(transition.state.hand(of: Seat(0)).isEmpty)
        #expect(transition.events.contains { if case .handFolded = $0 { true } else { false } })
    }

    @Test("a seat holding a playable card is not allowed to fold")
    func foldingIsRejectedWhenAMoveExists() {
        let state = Fixture.state(seatCount: 4, hands: [0: [.ace]], currentSeat: 0)
        #expect(throws: MoveError.legalMoveAvailable) {
            try GameReducer.apply(.foldHand(seat: Seat(0)), to: state)
        }
    }

    @Test("the turn never parks on a seat that cannot move")
    func deadHandsAreFoldedWhilePassingTheTurn() throws {
        // Seat 0 plays; seat 1 holds only unplayable cards; seat 2 can act.
        let state = Fixture.state(
            seatCount: 4,
            pawns: [Fixture.pawn(2, 0): .track(index: 40)],
            hands: [0: [.ace], 1: [.two, .five], 2: [.three], 3: []],
            currentSeat: 0
        )
        let move = try #require(MoveGenerator.legalMoves(in: state, for: Seat(0)).first)
        let transition = try GameReducer.apply(.play(move), to: state)

        #expect(transition.state.foldedSeats.contains(Seat(1)))
        #expect(transition.state.currentSeat == Seat(2))
    }

    // MARK: - Victory and resignation (§8, §30)

    @Test("a free-for-all seat wins by bringing all four pawns home")
    func freeForAllVictory() throws {
        let state = Fixture.state(
            seatCount: 3,
            teamMode: .freeForAll,
            pawns: [
                Fixture.pawn(0, 1): .home(seat: Seat(0), slot: 1),
                Fixture.pawn(0, 2): .home(seat: Seat(0), slot: 2),
                Fixture.pawn(0, 3): .home(seat: Seat(0), slot: 3),
                Fixture.pawn(0, 0): .track(index: 46),   // seat 0's home entry is 47
            ],
            hands: [0: [.two]]
        )
        let move = try #require(MoveGenerator.legalMoves(in: state, for: Seat(0)).first)
        let transition = try GameReducer.apply(.play(move), to: state)
        let result = try #require(transition.state.result)
        #expect(result.winningSeats == [Seat(0)])
        #expect(!result.wonByDefault)
    }

    @Test("a team wins only when both partners have finished")
    func teamVictoryNeedsBothPartners() {
        var pawns: [PawnID: BoardPosition] = [:]
        for slot in 0..<pawnsPerSeat {
            pawns[Fixture.pawn(0, slot)] = .home(seat: Seat(0), slot: slot)
        }
        let halfDone = Fixture.state(seatCount: 4, teamMode: .teamsOfTwo, pawns: pawns)
        #expect(GameReducer.evaluateVictory(in: halfDone) == nil)

        for slot in 0..<pawnsPerSeat {
            pawns[Fixture.pawn(2, slot)] = .home(seat: Seat(2), slot: slot)
        }
        let done = Fixture.state(seatCount: 4, teamMode: .teamsOfTwo, pawns: pawns)
        let result = done.configuration.team(of: Seat(0))
        #expect(GameReducer.evaluateVictory(in: done)?.winningTeam == result)
    }

    @Test("resigning in team play takes the whole team out")
    func resigningForfeitsTheTeam() throws {
        let state = Fixture.state(
            seatCount: 4,
            teamMode: .teamsOfTwo,
            pawns: [Fixture.pawn(1, 0): .track(index: 20)],
            hands: [0: [.ace], 1: [.ace], 2: [.ace], 3: [.ace]]
        )
        let transition = try GameReducer.apply(.resign(seat: Seat(1)), to: state)
        #expect(transition.state.resignedSeats == [Seat(1), Seat(3)])
        // Their pawns leave the track so they stop blocking the remaining team.
        #expect(transition.state.position(of: Fixture.pawn(1, 0)).isWaiting)
        let result = try #require(transition.state.result)
        #expect(result.wonByDefault)
        #expect(result.winningSeats == [Seat(0), Seat(2)])
    }

    @Test("resigning in free-for-all only removes that player")
    func resigningInFreeForAllLeavesOthersPlaying() throws {
        let state = Fixture.state(
            seatCount: 4,
            teamMode: .freeForAll,
            hands: [0: [.ace], 1: [.ace], 2: [.ace], 3: [.ace]]
        )
        let transition = try GameReducer.apply(.resign(seat: Seat(1)), to: state)
        #expect(transition.state.resignedSeats == [Seat(1)])
        #expect(transition.state.result == nil)
        #expect(transition.state.activeSeats.count == 3)
    }

    @Test("a finished match rejects every further action")
    func finishedMatchIsSealed() {
        var pawns: [PawnID: BoardPosition] = [:]
        for seat in [0, 2] {
            for slot in 0..<pawnsPerSeat {
                pawns[Fixture.pawn(seat, slot)] = .home(seat: Seat(seat), slot: slot)
            }
        }
        var state = Fixture.state(seatCount: 4, teamMode: .teamsOfTwo, pawns: pawns, hands: [1: [.ace]], currentSeat: 1)
        state.setResult(GameReducer.evaluateVictory(in: state)!)

        #expect(throws: MoveError.matchAlreadyFinished) {
            try GameReducer.apply(.foldHand(seat: Seat(1)), to: state)
        }
        #expect(MoveGenerator.legalMoves(in: state, for: Seat(1)).isEmpty)
    }

    // MARK: - Turn integrity (§63)

    @Test("playing out of turn is rejected")
    func outOfTurnIsRejected() {
        let state = Fixture.state(seatCount: 4, hands: [0: [.ace], 1: [.ace]], currentSeat: 0)
        let move = Move(seat: Seat(1), card: Fixture.card(.ace, seat: 1), action: .enterFromWaiting(pawn: Fixture.pawn(1, 0)))
        #expect(throws: MoveError.self) {
            try GameReducer.apply(.play(move), to: state)
        }
    }

    @Test("every applied action advances the revision counter")
    func revisionIsMonotonic() throws {
        var state = GameState.newMatch(configuration: .standard(seatCount: 4), seed: 11)
        var lastRevision = state.revision
        for _ in 0..<10 {
            guard !state.isFinished else { break }
            let moves = MoveGenerator.legalMoves(in: state, for: state.currentSeat)
            let action: PlayerAction = moves.first.map { .play($0) } ?? .foldHand(seat: state.currentSeat)
            state = try GameReducer.apply(action, to: state).state
            #expect(state.revision > lastRevision)
            lastRevision = state.revision
        }
    }
}
