import Testing
@testable import KeezlyCore

/// §23 — Medium must evaluate positions, weigh risk, and actually use the
/// public card history rather than merely having access to it.
@Suite("Medium agent")
struct MediumAgentTests {

    // MARK: - Basics

    @Test("every choice is legal", arguments: 2...6)
    func alwaysPlaysLegally(seatCount: Int) async throws {
        let agent = MediumAgent(seed: 3)
        var state = GameState.newMatch(configuration: .standard(seatCount: seatCount), seed: 66)

        for _ in 0..<120 where !state.isFinished {
            let observation = PlayerObservation(of: state, for: state.currentSeat)
            let action = await agent.chooseAction(for: observation)
            if case .play(let move) = action {
                #expect(observation.legalMoves.contains(move))
            } else {
                #expect(observation.legalMoves.isEmpty)
            }
            state = try GameReducer.apply(action, to: state).state
        }
    }

    @Test("the same position always yields the same move")
    func decisionsAreReproducible() async {
        let state = GameState.newMatch(configuration: .standard(seatCount: 4), seed: 4242)
        let observation = PlayerObservation(of: state, for: state.currentSeat)
        let agent = MediumAgent(seed: 9)
        var chosen: [String] = []
        for _ in 0..<6 { chosen.append(String(describing: await agent.chooseAction(for: observation))) }
        #expect(Set(chosen).count == 1)
    }

    // MARK: - It evaluates rather than pattern-matches

    @Test("it takes the opponent that is closest to home")
    func capturesTheMostAdvancedOpponent() async throws {
        // Seat 1 starts at track 16, so its pawn on track 10 has travelled 58
        // of 63 squares — nearly home — while its pawn on track 25 has barely
        // started. Both are capturable with the same Five.
        let state = Fixture.state(
            seatCount: 4,
            pawns: [
                Fixture.pawn(0, 0): .track(index: 5),    // +5 takes the advanced one
                Fixture.pawn(0, 1): .track(index: 20),   // +5 takes the fresh one
                Fixture.pawn(1, 0): .track(index: 10),
                Fixture.pawn(1, 1): .track(index: 25),
            ],
            hands: [0: [.five]]
        )
        let observation = PlayerObservation(of: state, for: Seat(0))
        #expect(observation.legalMoves.count == 2)

        let action = await MediumAgent(seed: 1).chooseAction(for: observation)
        guard case .play(let move) = action, let preview = observation.preview(move) else {
            Issue.record("Medium did not play a move")
            return
        }
        #expect(preview.captured == [Fixture.pawn(1, 0)],
                "it should take the pawn five squares from home, not the one that just started")
    }

    @Test("it goes home rather than idling forward")
    func prefersHome() async throws {
        let state = Fixture.state(
            seatCount: 4,
            pawns: [
                Fixture.pawn(0, 0): .track(index: 61),   // +3 reaches home
                Fixture.pawn(0, 1): .track(index: 20),   // +3 is just progress
            ],
            hands: [0: [.three]]
        )
        let observation = PlayerObservation(of: state, for: Seat(0))
        let action = await MediumAgent(seed: 1).chooseAction(for: observation)
        guard case .play(let move) = action, let preview = observation.preview(move) else {
            Issue.record("Medium did not play a move")
            return
        }
        #expect(!preview.reachedHome.isEmpty)
    }

    @Test("it will not knock out its own partner when anything else is legal")
    func avoidsFriendlyFire() async {
        let state = Fixture.state(
            seatCount: 4,
            teamMode: .teamsOfTwo,
            pawns: [
                Fixture.pawn(0, 0): .track(index: 5),
                Fixture.pawn(0, 1): .track(index: 30),
                Fixture.pawn(2, 0): .track(index: 10),
            ],
            hands: [0: [.five]]
        )
        let observation = PlayerObservation(of: state, for: Seat(0))
        #expect(observation.legalMoves.count == 2)

        for seed in UInt64(0)..<20 {
            let action = await MediumAgent(seed: seed).chooseAction(for: observation)
            guard case .play(let move) = action, let preview = observation.preview(move) else { continue }
            #expect(preview.captured.isEmpty, "seed \(seed) hit its own partner")
        }
    }

    // MARK: - Card counting drives the risk model

    @Test("reachable distances follow the rules, not the face values")
    func reachableDistancesAreRuleAccurate() {
        let classic = RuleSet.keezlyClassic
        // A Four moves backward only, so it threatens nothing ahead.
        #expect(PositionEvaluator.forwardDistances(of: .four, rules: classic).isEmpty)
        // A Jack swaps; it does not capture by landing.
        #expect(PositionEvaluator.forwardDistances(of: .jack, rules: classic).isEmpty)
        // A King only brings a pawn out under Classic rules.
        #expect(PositionEvaluator.forwardDistances(of: .king, rules: classic).isEmpty)
        var houseRules = RuleSet.houseRulesDefault
        houseRules.king = .enterOrAdvance13
        #expect(PositionEvaluator.forwardDistances(of: .king, rules: houseRules) == [13])
        // A Seven can be split, so it covers everything up to seven.
        #expect(PositionEvaluator.forwardDistances(of: .seven, rules: classic) == [1, 2, 3, 4, 5, 6, 7])
        #expect(PositionEvaluator.forwardDistances(of: .queen, rules: classic) == [12])
    }

    @Test("no card in the deck can travel exactly eleven squares")
    func elevenIsUnreachable() {
        let state = Fixture.state(seatCount: 4, hands: [0: [.two]])
        let availability = PositionEvaluator.rankAvailability(in: PlayerObservation(of: state, for: Seat(0)))
        #expect((availability[11] ?? 0) == 0)
        #expect((availability[12] ?? 0) > 0)
    }

    /// The point of the exercise: once every Queen has been played, a pawn
    /// sitting twelve squares in front of an opponent is no longer in danger,
    /// and the evaluator must notice.
    @Test("counting the queens removes the twelve-square threat")
    func cardCountingLowersRisk() throws {
        func observation(discard: [Card]) -> PlayerObservation {
            let state = Fixture.state(
                seatCount: 4,
                pawns: [
                    // The exposed pawn stays put: it sits exactly twelve squares
                    // in front of seat 1's pawn, which is Queen range.
                    Fixture.pawn(0, 0): .track(index: 40),
                    Fixture.pawn(1, 0): .track(index: 28),
                    // A second pawn far from the hunter provides the move, so the
                    // exposure being measured is not moved out from under itself.
                    Fixture.pawn(0, 1): .track(index: 5),
                ],
                hands: [0: [.two], 1: [.ace, .ace, .ace]],
                discard: discard
            )
            return PlayerObservation(of: state, for: Seat(0))
        }

        let open = observation(discard: [])
        let queensGone = observation(discard: (0..<4).map { Card(rank: .queen, deckCopy: $0) })

        #expect((open.unseenCards.filter { $0.rank == .queen }).count == 4)
        #expect(queensGone.unseenCards.contains { $0.rank == .queen } == false)

        let openAvailability = PositionEvaluator.rankAvailability(in: open)
        let goneAvailability = PositionEvaluator.rankAvailability(in: queensGone)
        #expect((openAvailability[12] ?? 0) > 0)
        #expect((goneAvailability[12] ?? 0) == 0, "a distance of twelve is only reachable by a Queen")

        // And the effect reaches the exposure term the agent actually uses.
        // Move the *other* pawn, so the exposed one stays in Queen range.
        func riskAfterMovingTheFarPawn(_ observation: PlayerObservation) throws -> Double {
            let move = try #require(observation.legalMoves.first {
                $0.involvedPawns == [Fixture.pawn(0, 1)]
            })
            return PositionEvaluator.exposure(
                after: try #require(observation.preview(move)), in: observation, weights: .medium
            )
        }
        let openRisk = try riskAfterMovingTheFarPawn(open)
        let goneRisk = try riskAfterMovingTheFarPawn(queensGone)
        #expect(openRisk > 0, "a pawn twelve squares ahead of an opponent should read as exposed")
        #expect(openRisk > goneRisk, "risk did not fall after every Queen was accounted for")
    }

    @Test("a pawn on its own start square is treated as safe")
    func protectedPawnsCarryNoRisk() throws {
        let state = Fixture.state(
            seatCount: 4,
            pawns: [
                Fixture.pawn(0, 0): .waiting(seat: Seat(0), slot: 0),
                Fixture.pawn(1, 0): .track(index: 60),   // four behind seat 0's start
            ],
            hands: [0: [.ace]]
        )
        let observation = PlayerObservation(of: state, for: Seat(0))
        let entering = try #require(observation.legalMoves.first {
            if case .enterFromWaiting = $0.action { return true } else { return false }
        })
        let preview = try #require(observation.preview(entering))
        #expect(preview.pawn(Fixture.pawn(0, 0)).position == .track(index: 0))
        #expect(PositionEvaluator.exposure(after: preview, in: observation, weights: .medium) == 0,
                "a pawn standing on its own start square cannot be taken (§15)")
    }
}
