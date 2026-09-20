import Testing
@testable import KeezlyCore

/// §25, §112 — the headless simulator must play complete matches for every
/// supported table and catch a broken engine or a misbehaving agent.
@Suite("Simulation harness")
struct SimulationTests {

    static func easyTable(seatCount: Int) -> [any AIAgent] {
        (0..<seatCount).map { EasyAgent(seed: 0xE5_0000 &+ UInt64($0)) }
    }

    // MARK: - Full matches on every table

    @Test("Easy plays complete, clean matches at every table size", arguments: 2...6)
    func everySeatCountCompletes(seatCount: Int) async {
        let simulator = MatchSimulator(
            configuration: .standard(seatCount: seatCount),
            agents: Self.easyTable(seatCount: seatCount)
        )
        let report = await simulator.runBatch(count: 12, firstSeed: 1_000)

        #expect(report.isClean, "seat count \(seatCount):\n\(report.summary)")
        #expect(report.completedMatches.count == 12)
        #expect(report.shortestMatch > 0)
    }

    @Test("free-for-all works on the even tables too", arguments: [4, 6])
    func freeForAllCompletes(seatCount: Int) async {
        let simulator = MatchSimulator(
            configuration: GameConfiguration(seatCount: seatCount, teamMode: .freeForAll),
            agents: Self.easyTable(seatCount: seatCount)
        )
        let report = await simulator.runBatch(count: 10, firstSeed: 2_000)
        #expect(report.isClean, "\(report.summary)")
    }

    @Test("team play produces a team winner, never a lone seat")
    func teamMatchesEndWithATeam() async {
        let simulator = MatchSimulator(
            configuration: GameConfiguration(seatCount: 4, teamMode: .teamsOfTwo),
            agents: Self.easyTable(seatCount: 4)
        )
        let report = await simulator.runBatch(count: 12, firstSeed: 3_000)
        #expect(report.isClean, "\(report.summary)")

        for outcome in report.completedMatches {
            let result = outcome.result!
            #expect(result.winningSeats.count == 2, "a team of two must win together")
            #expect(Set(result.winningSeats.map(\.index)) == Set([0, 2]) || Set(result.winningSeats.map(\.index)) == Set([1, 3]))
        }
    }

    @Test("every rule variant survives a batch of simulated matches")
    func ruleVariantsSimulate() async {
        var variants: [(String, RuleSet)] = [("classic", .keezlyClassic), ("tournament", .tournament)]
        var king = RuleSet.houseRulesDefault; king.king = .enterOrAdvance13
        var extraLap = RuleSet.houseRulesDefault; extraLap.homeEntry = .allowExtraLap
        var blocking = RuleSet.houseRulesDefault; blocking.ownPawnBlocking = .blocking
        var noFF = RuleSet.houseRulesDefault; noFF.friendlyCapture = .landingForbidden
        var strict = RuleSet.houseRulesDefault; strict.homeOrdering = .strictBackToFront
        variants += [("king+13", king), ("extra lap", extraLap), ("own pawns block", blocking),
                     ("no friendly fire", noFF), ("strict home", strict)]

        for (name, rules) in variants {
            let simulator = MatchSimulator(
                configuration: GameConfiguration(seatCount: 4, teamMode: .teamsOfTwo, ruleSet: rules),
                agents: Self.easyTable(seatCount: 4)
            )
            let report = await simulator.runBatch(count: 6, firstSeed: 4_000)
            #expect(report.isClean, "variant \(name):\n\(report.summary)")
        }
    }

    // MARK: - Reproducibility

    @Test("a seed reproduces a match exactly")
    func seedsAreReproducible() async {
        let simulator = MatchSimulator(configuration: .standard(seatCount: 4), agents: Self.easyTable(seatCount: 4))
        let first = await simulator.run(seed: 555)
        let second = await simulator.run(seed: 555)

        #expect(first.actions == second.actions)
        #expect(first.result == second.result)
    }

    @Test("the report names the seeds of failing matches")
    func failuresCarryTheirSeed() async {
        let simulator = MatchSimulator(
            configuration: .standard(seatCount: 4),
            agents: [BrokenAgent(), EasyAgent(), EasyAgent(), EasyAgent()]
        )
        let report = await simulator.runBatch(count: 3, firstSeed: 77)

        #expect(!report.isClean)
        #expect(report.failingSeeds == [77, 78, 79])
        #expect(report.summary.contains("77"))
    }

    // MARK: - The harness catches misbehaviour

    /// An agent that plays a card it does not hold. The simulator must catch
    /// this rather than let a corrupt match count as evidence.
    struct BrokenAgent: AIAgent {
        let difficulty = AIDifficulty.easy
        func chooseAction(for observation: PlayerObservation) async -> PlayerAction {
            .play(Move(
                seat: observation.seat,
                card: Card(rank: .king, deckCopy: 0),
                action: .enterFromWaiting(pawn: PawnID(seat: observation.seat, slot: 0))
            ))
        }
    }

    /// An agent that tries to pass while holding a playable card, which the
    /// forced-move rule forbids (§13).
    struct RefusingAgent: AIAgent {
        let difficulty = AIDifficulty.easy
        func chooseAction(for observation: PlayerObservation) async -> PlayerAction {
            .foldHand(seat: observation.seat)
        }
    }

    @Test("an agent playing a card it does not hold is caught")
    func illegalMoveIsCaught() async {
        let simulator = MatchSimulator(
            configuration: .standard(seatCount: 4),
            agents: [BrokenAgent(), EasyAgent(), EasyAgent(), EasyAgent()]
        )
        let outcome = await simulator.run(seed: 5)
        guard case .illegalAction = outcome.failure else {
            Issue.record("expected an illegalAction failure, got \(String(describing: outcome.failure))")
            return
        }
    }

    @Test("an agent refusing a forced move is caught")
    func refusingToMoveIsCaught() async {
        let simulator = MatchSimulator(
            configuration: .standard(seatCount: 4),
            agents: [RefusingAgent(), EasyAgent(), EasyAgent(), EasyAgent()]
        )
        let outcome = await simulator.run(seed: 6)
        guard case .illegalAction = outcome.failure else {
            Issue.record("expected an illegalAction failure, got \(String(describing: outcome.failure))")
            return
        }
    }

    @Test("a match that cannot finish is reported, not hidden")
    func stallIsReported() async {
        // A one-action ceiling guarantees the ceiling is hit.
        let simulator = MatchSimulator(
            configuration: .standard(seatCount: 4),
            agents: Self.easyTable(seatCount: 4),
            maximumActions: 1
        )
        let outcome = await simulator.run(seed: 8)
        guard case .didNotFinish(let actions) = outcome.failure else {
            Issue.record("expected didNotFinish, got \(String(describing: outcome.failure))")
            return
        }
        #expect(actions == 1)
    }
}
