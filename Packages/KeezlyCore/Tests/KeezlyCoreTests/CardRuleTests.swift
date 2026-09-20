import Testing
@testable import KeezlyCore

/// §11, §64 — one focused test per card, plus the blocking and capture rules
/// they interact with. Board references assume the four-seat board:
/// 64 track squares, starts at 0/16/32/48, seat 0's home entry at 63.
@Suite("Card rules")
struct CardRuleTests {

    // MARK: - Ace

    @Test("ace either brings a pawn out or advances one square")
    func aceOffersBothOptions() {
        let state = Fixture.state(
            seatCount: 4,
            pawns: [Fixture.pawn(0, 0): .track(index: 5)],
            hands: [0: [.ace]]
        )
        let moves = MoveGenerator.legalMoves(in: state, for: Seat(0))
        #expect(moves.contains { if case .enterFromWaiting = $0.action { true } else { false } })
        #expect(moves.contains { if case .advance(_, let steps, _) = $0.action { steps == 1 } else { false } })
    }

    @Test("a pawn entering lands on its own start square")
    func enterUsesOwnStart() throws {
        let state = Fixture.state(seatCount: 4, hands: [0: [.ace]], currentSeat: 0)
        let move = try #require(
            MoveGenerator.legalMoves(in: state, for: Seat(0))
                .first { if case .enterFromWaiting = $0.action { true } else { false } }
        )
        let next = try GameReducer.apply(.play(move), to: state).state
        #expect(next.position(of: Fixture.pawn(0, 0)) == .track(index: 0))
    }

    // MARK: - King

    @Test("king only brings a pawn out under classic rules")
    func kingIsEnterOnlyByDefault() {
        let state = Fixture.state(
            seatCount: 4,
            pawns: [Fixture.pawn(0, 0): .track(index: 5)],
            hands: [0: [.king]]
        )
        let moves = MoveGenerator.legalMoves(in: state, for: Seat(0))
        #expect(moves.allSatisfy { if case .enterFromWaiting = $0.action { true } else { false } })
    }

    @Test("king advances thirteen under the house rule")
    func kingAdvancesThirteenWhenConfigured() throws {
        var rules = RuleSet.houseRulesDefault
        rules.king = .enterOrAdvance13
        let state = Fixture.state(
            seatCount: 4,
            rules: rules,
            pawns: [Fixture.pawn(0, 0): .track(index: 5)],
            hands: [0: [.king]]
        )
        let move = try #require(
            MoveGenerator.legalMoves(in: state, for: Seat(0))
                .first { if case .advance(_, let steps, _) = $0.action { steps == 13 } else { false } }
        )
        let next = try GameReducer.apply(.play(move), to: state).state
        #expect(next.position(of: Fixture.pawn(0, 0)) == .track(index: 18))
    }

    // MARK: - Queen and the plain numbers

    @Test("queen moves exactly twelve")
    func queenMovesTwelve() throws {
        let state = Fixture.state(
            seatCount: 4,
            pawns: [Fixture.pawn(0, 0): .track(index: 5)],
            hands: [0: [.queen]]
        )
        let move = try #require(MoveGenerator.legalMoves(in: state, for: Seat(0)).first)
        let next = try GameReducer.apply(.play(move), to: state).state
        #expect(next.position(of: Fixture.pawn(0, 0)) == .track(index: 17))
    }

    @Test(
        "plain number cards advance by their face value",
        arguments: [CardRank.two, .three, .five, .six, .eight, .nine, .ten]
    )
    func numberCardsAdvanceByFaceValue(rank: CardRank) throws {
        let state = Fixture.state(
            seatCount: 4,
            pawns: [Fixture.pawn(0, 0): .track(index: 5)],
            hands: [0: [rank]]
        )
        let move = try #require(MoveGenerator.legalMoves(in: state, for: Seat(0)).first)
        let next = try GameReducer.apply(.play(move), to: state).state
        #expect(next.position(of: Fixture.pawn(0, 0)) == .track(index: 5 + rank.rawValue))
    }

    // MARK: - Four

    @Test("four moves backward and wraps around the track")
    func fourMovesBackward() throws {
        let state = Fixture.state(
            seatCount: 4,
            pawns: [Fixture.pawn(0, 0): .track(index: 2)],
            hands: [0: [.four]]
        )
        let move = try #require(MoveGenerator.legalMoves(in: state, for: Seat(0)).first)
        let next = try GameReducer.apply(.play(move), to: state).state
        #expect(next.position(of: Fixture.pawn(0, 0)) == .track(index: 62))
    }

    @Test("four never moves a pawn out of home")
    func fourCannotLeaveHome() {
        let state = Fixture.state(
            seatCount: 4,
            pawns: [Fixture.pawn(0, 0): .home(seat: Seat(0), slot: 1)],
            hands: [0: [.four]]
        )
        #expect(MoveGenerator.legalMoves(in: state, for: Seat(0)).isEmpty)
    }

    @Test("four never reaches home, even from the home entry square")
    func fourCannotEnterHome() throws {
        let state = Fixture.state(
            seatCount: 4,
            pawns: [Fixture.pawn(0, 0): .track(index: 63)],   // seat 0's home entry
            hands: [0: [.four]]
        )
        let move = try #require(MoveGenerator.legalMoves(in: state, for: Seat(0)).first)
        let next = try GameReducer.apply(.play(move), to: state).state
        #expect(next.position(of: Fixture.pawn(0, 0)) == .track(index: 59))
    }

    @Test("four cannot cross a protected start square")
    func fourIsStoppedByABlockade() {
        let state = Fixture.state(
            seatCount: 4,
            pawns: [
                Fixture.pawn(1, 0): .track(index: 18),
                Fixture.pawn(0, 0): .track(index: 16),   // seat 1's start — not protected for seat 0
                Fixture.pawn(2, 0): .track(index: 34),
                Fixture.pawn(2, 1): .track(index: 32),   // seat 2 protected on its own start
            ],
            hands: [2: [.four]],
            currentSeat: 2
        )
        // Seat 2's pawn on 34 would pass 32, where its own protected pawn sits.
        let moves = MoveGenerator.legalMoves(in: state, for: Seat(2))
        #expect(!moves.contains { $0.involvedPawns == [Fixture.pawn(2, 0)] })
    }

    // MARK: - Jack

    @Test("jack swaps with another seat's pawn")
    func jackSwapsPositions() throws {
        let state = Fixture.state(
            seatCount: 4,
            pawns: [
                Fixture.pawn(0, 0): .track(index: 5),
                Fixture.pawn(1, 0): .track(index: 20),
            ],
            hands: [0: [.jack]]
        )
        let move = try #require(MoveGenerator.legalMoves(in: state, for: Seat(0)).first)
        let next = try GameReducer.apply(.play(move), to: state).state
        #expect(next.position(of: Fixture.pawn(0, 0)) == .track(index: 20))
        #expect(next.position(of: Fixture.pawn(1, 0)) == .track(index: 5))
    }

    @Test("jack may target a partner's pawn in team play")
    func jackMayTargetPartner() {
        let state = Fixture.state(
            seatCount: 4,
            teamMode: .teamsOfTwo,
            pawns: [
                Fixture.pawn(0, 0): .track(index: 5),
                Fixture.pawn(2, 0): .track(index: 40),
            ],
            hands: [0: [.jack]]
        )
        let moves = MoveGenerator.legalMoves(in: state, for: Seat(0))
        #expect(moves.contains { $0.involvedPawns.contains(Fixture.pawn(2, 0)) })
    }

    @Test("jack cannot touch a protected pawn or a pawn in home")
    func jackRespectsProtectionAndHome() {
        let state = Fixture.state(
            seatCount: 4,
            pawns: [
                Fixture.pawn(0, 0): .track(index: 5),
                Fixture.pawn(1, 0): .track(index: 16),                  // protected on own start
                Fixture.pawn(2, 0): .home(seat: Seat(2), slot: 0),      // safe at home
            ],
            hands: [0: [.jack]]
        )
        #expect(MoveGenerator.legalMoves(in: state, for: Seat(0)).isEmpty)
    }

    @Test("whether a protected pawn may initiate a swap is a rule option")
    func jackOwnStartPolicyIsHonoured() {
        let pawns: [PawnID: BoardPosition] = [
            Fixture.pawn(0, 0): .track(index: 0),    // seat 0 protected on its own start
            Fixture.pawn(1, 0): .track(index: 20),
        ]
        let strict = Fixture.state(seatCount: 4, pawns: pawns, hands: [0: [.jack]])
        #expect(MoveGenerator.legalMoves(in: strict, for: Seat(0)).isEmpty)

        var permissive = RuleSet.houseRulesDefault
        permissive.jackOwnStart = .mayBeSwapSource
        let loose = Fixture.state(seatCount: 4, rules: permissive, pawns: pawns, hands: [0: [.jack]])
        #expect(MoveGenerator.legalMoves(in: loose, for: Seat(0)).count == 1)
    }

    // MARK: - Seven

    @Test("seven always spends exactly seven steps across at most two pawns")
    func sevenSplitsAreWellFormed() {
        let state = Fixture.state(
            seatCount: 4,
            pawns: [
                Fixture.pawn(0, 0): .track(index: 5),
                Fixture.pawn(0, 1): .track(index: 10),
            ],
            hands: [0: [.seven]]
        )
        let moves = MoveGenerator.legalMoves(in: state, for: Seat(0))
        #expect(!moves.isEmpty)
        for move in moves {
            guard case .split(let steps) = move.action else {
                Issue.record("a seven must always produce a split action")
                continue
            }
            #expect(steps.reduce(0) { $0 + $1.steps } == 7)
            #expect((1...2).contains(steps.count))
            #expect(Set(steps.map(\.pawn)).count == steps.count)
        }
    }

    @Test("seven offers both the undivided move and every legal split")
    func sevenEnumeratesAllSplits() {
        let state = Fixture.state(
            seatCount: 4,
            pawns: [
                Fixture.pawn(0, 0): .track(index: 5),
                Fixture.pawn(0, 1): .track(index: 30),
            ],
            hands: [0: [.seven]]
        )
        let moves = MoveGenerator.legalMoves(in: state, for: Seat(0))
        let singleLeg = moves.filter { if case .split(let s) = $0.action { s.count == 1 } else { false } }
        let twoLeg = moves.filter { if case .split(let s) = $0.action { s.count == 2 } else { false } }
        // Either pawn may take all seven …
        #expect(singleLeg.count == 2)
        // … and 1+6 through 6+1 are all available on an empty stretch of track.
        #expect(twoLeg.count == 12)
    }

    @Test("seven may finish a player's own pawns and spend the rest on the partner's")
    func sevenCrossesToPartnerAfterFinishing() throws {
        let state = Fixture.state(
            seatCount: 4,
            teamMode: .teamsOfTwo,
            pawns: [
                // Three of seat 0's pawns are already home; the last needs three.
                Fixture.pawn(0, 1): .home(seat: Seat(0), slot: 1),
                Fixture.pawn(0, 2): .home(seat: Seat(0), slot: 2),
                Fixture.pawn(0, 3): .home(seat: Seat(0), slot: 3),
                Fixture.pawn(0, 0): .track(index: 61),
                Fixture.pawn(2, 0): .track(index: 40),
            ],
            hands: [0: [.seven]]
        )

        let crossing = MoveGenerator.legalMoves(in: state, for: Seat(0)).first { move in
            guard case .split(let steps) = move.action, steps.count == 2 else { return false }
            return steps[0].pawn == Fixture.pawn(0, 0) && steps[0].steps == 3
                && steps[1].pawn == Fixture.pawn(2, 0) && steps[1].steps == 4
        }
        let move = try #require(crossing, "the partner hand-off of §17 must be generated")

        let next = try GameReducer.apply(.play(move), to: state).state
        #expect(next.position(of: Fixture.pawn(0, 0)) == .home(seat: Seat(0), slot: 0))
        #expect(next.position(of: Fixture.pawn(2, 0)) == .track(index: 44))
        #expect(next.hasFinished(Seat(0)))
    }

    // MARK: - Capturing (§14)

    @Test("landing on an opponent sends it back to its waiting area")
    func capturingAnOpponent() throws {
        let state = Fixture.state(
            seatCount: 4,
            pawns: [
                Fixture.pawn(0, 0): .track(index: 5),
                Fixture.pawn(1, 0): .track(index: 10),
            ],
            hands: [0: [.five]]
        )
        let move = try #require(MoveGenerator.legalMoves(in: state, for: Seat(0)).first)
        let transition = try GameReducer.apply(.play(move), to: state)
        #expect(transition.state.position(of: Fixture.pawn(0, 0)) == .track(index: 10))
        #expect(transition.state.position(of: Fixture.pawn(1, 0)).isWaiting)
        #expect(transition.events.contains { if case .pawnCaptured = $0 { true } else { false } })
    }

    @Test("classic rules let a forced move knock out your own or your partner's pawn")
    func friendlyCaptureIsAllowedByDefault() throws {
        for victim in [Fixture.pawn(0, 1), Fixture.pawn(2, 0)] {
            let state = Fixture.state(
                seatCount: 4,
                teamMode: .teamsOfTwo,
                pawns: [Fixture.pawn(0, 0): .track(index: 5), victim: .track(index: 10)],
                hands: [0: [.five]]
            )
            let move = try #require(MoveGenerator.legalMoves(in: state, for: Seat(0)).first)
            let next = try GameReducer.apply(.play(move), to: state).state
            #expect(next.position(of: victim).isWaiting, "\(victim) should have been sent home")
        }
    }

    @Test("the house rule can forbid landing on a friendly pawn instead")
    func friendlyCaptureCanBeForbidden() {
        var rules = RuleSet.houseRulesDefault
        rules.friendlyCapture = .landingForbidden
        let state = Fixture.state(
            seatCount: 4,
            teamMode: .teamsOfTwo,
            rules: rules,
            pawns: [Fixture.pawn(0, 0): .track(index: 5), Fixture.pawn(2, 0): .track(index: 10)],
            hands: [0: [.five]]
        )
        #expect(MoveGenerator.legalMoves(in: state, for: Seat(0)).isEmpty)
    }

    // MARK: - Protected start square (§15)

    @Test("a protected pawn can be neither captured nor passed")
    func protectedStartIsAnAbsoluteBlockade() {
        let state = Fixture.state(
            seatCount: 4,
            pawns: [
                Fixture.pawn(1, 0): .track(index: 16),   // protected on its own start
                Fixture.pawn(0, 0): .track(index: 14),
            ],
            hands: [0: [.two, .three]]
        )
        let moves = MoveGenerator.legalMoves(in: state, for: Seat(0))
        // Two would land on it, three would pass it. Neither is legal.
        #expect(moves.isEmpty)
    }

    @Test("a seat cannot enter while its own start square is occupied by its own pawn")
    func ownStartBlocksEntering() {
        let state = Fixture.state(
            seatCount: 4,
            pawns: [Fixture.pawn(0, 0): .track(index: 0)],
            hands: [0: [.king]]
        )
        #expect(MoveGenerator.legalMoves(in: state, for: Seat(0)).isEmpty)
    }

    @Test("entering captures a foreign pawn squatting on the start square")
    func enteringCapturesSquatter() throws {
        let state = Fixture.state(
            seatCount: 4,
            pawns: [Fixture.pawn(1, 0): .track(index: 0)],
            hands: [0: [.king]]
        )
        let move = try #require(MoveGenerator.legalMoves(in: state, for: Seat(0)).first)
        let next = try GameReducer.apply(.play(move), to: state).state
        #expect(next.position(of: Fixture.pawn(1, 0)).isWaiting)
    }

    // MARK: - Home (§16)

    @Test("a pawn enters home only with an exact count")
    func homeRequiresExactCount() {
        let state = Fixture.state(
            seatCount: 4,
            pawns: [Fixture.pawn(0, 0): .track(index: 61)],   // three steps from home slot 0
            hands: [0: [.three, .six, .seven]]
        )
        let moves = MoveGenerator.legalMoves(in: state, for: Seat(0))
        let destinations = moves.destinations(for: Fixture.pawn(0, 0), in: state)
        #expect(destinations.contains(.home(seat: Seat(0), slot: 0)))   // 3 → first home square
        #expect(destinations.contains(.home(seat: Seat(0), slot: 3)))   // 6 → deepest home square
        // Seven would need progress 68 on a 67-step journey: no such move exists.
        #expect(!moves.contains { $0.card.rank == .seven })
    }

    @Test("a pawn never jumps over one that is already home")
    func homePawnsCannotBeJumped() {
        let state = Fixture.state(
            seatCount: 4,
            pawns: [
                Fixture.pawn(0, 0): .track(index: 61),
                Fixture.pawn(0, 1): .home(seat: Seat(0), slot: 1),
            ],
            hands: [0: [.four, .five]]
        )
        let destinations = MoveGenerator.legalMoves(in: state, for: Seat(0))
            .destinations(for: Fixture.pawn(0, 0), in: state)
        #expect(!destinations.contains(.home(seat: Seat(0), slot: 1)))   // occupied
        #expect(!destinations.contains(.home(seat: Seat(0), slot: 2)))   // would jump it
    }

    @Test("the strict home-ordering house rule fills the lane from the back")
    func strictHomeOrdering() {
        var rules = RuleSet.houseRulesDefault
        rules.homeOrdering = .strictBackToFront
        let state = Fixture.state(
            seatCount: 4,
            rules: rules,
            pawns: [Fixture.pawn(0, 0): .track(index: 61)],
            hands: [0: [.three, .six]]
        )
        let destinations = MoveGenerator.legalMoves(in: state, for: Seat(0))
            .destinations(for: Fixture.pawn(0, 0), in: state)
        #expect(destinations == [.home(seat: Seat(0), slot: 3)])
    }
}
