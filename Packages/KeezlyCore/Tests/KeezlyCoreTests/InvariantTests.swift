import Foundation
import Testing
@testable import KeezlyCore

/// §65 — deterministic randomised self-play. These do not check that a
/// particular rule is right; they check that the engine can never get into a
/// state it considers impossible, no matter which legal moves are chosen.
@Suite("Invariants")
struct InvariantTests {

    /// Every invariant that must hold after *every* applied action.
    static func check(_ state: GameState, step: Int, seed: UInt64) {
        let context = "seed \(seed), step \(step)"
        let config = state.configuration

        // Exactly four pawns per seat, each in exactly one place.
        #expect(state.pawns.count == config.seatCount * pawnsPerSeat, "\(context): pawn count changed")
        #expect(Set(state.pawns.map(\.id)).count == state.pawns.count, "\(context): duplicate pawn id")

        // No two pawns share a square. Waiting slots are private per seat, so
        // the whole position value is the right key.
        let occupied = state.pawns.map(\.position)
        #expect(Set(occupied).count == occupied.count, "\(context): two pawns on one square")

        // Pawns only ever stand in their own private areas.
        for pawn in state.pawns {
            if let owner = pawn.position.owningSeat {
                #expect(owner == pawn.id.seat, "\(context): \(pawn.id) is in \(owner)'s private area")
            }
            if let index = pawn.position.trackIndex {
                #expect((0..<state.board.mainTrackCount).contains(index), "\(context): track index out of range")
            }
        }

        // Cards are conserved: hands + discard + deck is always a full deck.
        let inHands = config.seats.reduce(0) { $0 + state.hand(of: $1).count }
        let total = inHands + state.discardPile.count + state.deck.count
        #expect(total == config.seatCount * DealState.cardsPerCycle, "\(context): \(total) cards in play")

        // …and no card exists twice.
        let allCards = config.seats.flatMap { state.hand(of: $0).cards } + state.discardPile + state.deck.cards
        #expect(Set(allCards).count == allCards.count, "\(context): duplicated card")

        // A finished match offers nothing further.
        if state.isFinished {
            #expect(MoveGenerator.legalMoves(in: state, for: state.currentSeat).isEmpty, "\(context): finished match still has moves")
        }
    }

    /// Plays one match to completion by always choosing a legal move.
    /// Returns the number of actions applied.
    @discardableResult
    static func playOut(
        seatCount: Int,
        teamMode: TeamMode,
        rules: RuleSet,
        seed: UInt64,
        maxActions: Int = 4000
    ) throws -> (actions: Int, state: GameState) {
        var chooser = SeededGenerator(seed: seed &* 0x5DEE_CE66_D)
        var state = GameState.newMatch(
            configuration: GameConfiguration(seatCount: seatCount, teamMode: teamMode, ruleSet: rules),
            seed: seed
        )
        check(state, step: 0, seed: seed)

        var actions = 0
        var homePawns = Set<PawnID>()

        while !state.isFinished && actions < maxActions {
            let seat = state.currentSeat
            let moves = MoveGenerator.legalMoves(in: state, for: seat)
            let action: PlayerAction = moves.isEmpty
                ? .foldHand(seat: seat)
                : .play(moves[Int(chooser.next() % UInt64(moves.count))])

            let previousRevision = state.revision
            state = try GameReducer.apply(action, to: state).state
            actions += 1

            #expect(state.revision > previousRevision, "seed \(seed): revision did not advance")
            check(state, step: actions, seed: seed)

            // A pawn that reached home never comes back out (§16).
            let nowHome = Set(state.pawns.filter(\.isHome).map(\.id))
            #expect(homePawns.isSubset(of: nowHome), "seed \(seed): a pawn left its home lane")
            homePawns = nowHome
        }

        #expect(state.isFinished, "seed \(seed): \(seatCount)-seat match did not finish within \(maxActions) actions")
        return (actions, state)
    }

    @Test("random self-play stays consistent for every table size", arguments: 2...6)
    func randomisedSelfPlayPerSeatCount(seatCount: Int) throws {
        for seed in UInt64(1)...25 {
            let mode: TeamMode = (seatCount == 4 || seatCount == 6) ? .teamsOfTwo : .freeForAll
            _ = try Self.playOut(seatCount: seatCount, teamMode: mode, rules: .keezlyClassic, seed: seed)
        }
    }

    @Test("free-for-all is consistent on the even table sizes too", arguments: [4, 6])
    func freeForAllOnEvenTables(seatCount: Int) throws {
        for seed in UInt64(100)...115 {
            _ = try Self.playOut(seatCount: seatCount, teamMode: .freeForAll, rules: .keezlyClassic, seed: seed)
        }
    }

    @Test("every rule variant plays to completion without corrupting state")
    func ruleVariantsSelfPlay() throws {
        var variants: [(String, RuleSet)] = [
            ("classic", .keezlyClassic),
            ("tournament", .tournament),
        ]
        var king = RuleSet.houseRulesDefault; king.king = .enterOrAdvance13
        var jack = RuleSet.houseRulesDefault; jack.jackOwnStart = .mayBeSwapSource
        var strictHome = RuleSet.houseRulesDefault; strictHome.homeOrdering = .strictBackToFront
        var extraLap = RuleSet.houseRulesDefault; extraLap.homeEntry = .allowExtraLap
        var blocking = RuleSet.houseRulesDefault; blocking.ownPawnBlocking = .blocking
        var noFriendlyFire = RuleSet.houseRulesDefault; noFriendlyFire.friendlyCapture = .landingForbidden
        variants += [
            ("king+13", king),
            ("jack from own start", jack),
            ("strict home order", strictHome),
            ("extra lap", extraLap),
            ("own pawns block", blocking),
            ("no friendly fire", noFriendlyFire),
        ]

        for (name, rules) in variants {
            for seed in UInt64(500)...507 {
                do {
                    _ = try Self.playOut(seatCount: 4, teamMode: .teamsOfTwo, rules: rules, seed: seed)
                } catch {
                    Issue.record("variant \(name) failed on seed \(seed): \(error)")
                }
            }
        }
    }

    @Test("the generator and the reducer agree on what is legal")
    func generatorAndReducerAgree() throws {
        var chooser = SeededGenerator(seed: 0xA11CE)
        var state = GameState.newMatch(configuration: .standard(seatCount: 4), seed: 77)

        for _ in 0..<300 where !state.isFinished {
            let seat = state.currentSeat
            let moves = MoveGenerator.legalMoves(in: state, for: seat)

            // Everything offered must be accepted …
            for move in moves {
                #expect(throws: Never.self) { try GameReducer.apply(.play(move), to: state) }
            }
            // … and folding must be refused while anything is on offer.
            if !moves.isEmpty {
                #expect(throws: MoveError.legalMoveAvailable) {
                    try GameReducer.apply(.foldHand(seat: seat), to: state)
                }
            }

            let action: PlayerAction = moves.isEmpty
                ? .foldHand(seat: seat)
                : .play(moves[Int(chooser.next() % UInt64(moves.count))])
            state = try GameReducer.apply(action, to: state).state
        }
    }

    @Test("a replayed action sequence reproduces the state exactly")
    func replayIsDeterministic() throws {
        func run() throws -> GameState {
            var chooser = SeededGenerator(seed: 0xDEAD_BEEF)
            var state = GameState.newMatch(configuration: .standard(seatCount: 5), seed: 4242)
            for _ in 0..<200 where !state.isFinished {
                let moves = MoveGenerator.legalMoves(in: state, for: state.currentSeat)
                let action: PlayerAction = moves.isEmpty
                    ? .foldHand(seat: state.currentSeat)
                    : .play(moves[Int(chooser.next() % UInt64(moves.count))])
                state = try GameReducer.apply(action, to: state).state
            }
            return state
        }
        #expect(try run() == (try run()))
    }

    @Test("state survives a JSON round trip", arguments: 2...6)
    func codableRoundTrip(seatCount: Int) throws {
        var state = GameState.newMatch(configuration: .standard(seatCount: seatCount), seed: 9)
        for _ in 0..<40 where !state.isFinished {
            let moves = MoveGenerator.legalMoves(in: state, for: state.currentSeat)
            let action: PlayerAction = moves.first.map { .play($0) } ?? .foldHand(seat: state.currentSeat)
            state = try GameReducer.apply(action, to: state).state
        }
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(GameState.self, from: data)
        #expect(decoded == state)
    }
}
