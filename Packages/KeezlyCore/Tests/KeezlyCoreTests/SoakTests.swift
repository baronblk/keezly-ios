@testable import KeezlyCore
import Testing

/// §25, §112 — the engine under sustained load, across everything it supports.
///
/// `SimulationTests` proves the harness works and that Easy can finish a match
/// at every table size. That is a smoke test: twelve matches of one strength.
/// This is the soak — every strength, every table, both team modes, and the
/// house rule variants — because the faults worth finding here are the ones
/// that need a particular deal to appear, and a particular deal needs volume.
///
/// **Nothing here is a new assertion.** Every match is checked by the same
/// `GameStateInvariant` the engine already applies after every action: pawns
/// exist exactly once, no two share a square, nobody stands in another seat's
/// private area, cards are conserved and unique, a pawn that reached home
/// never comes back out, and a finished match offers no further move. What the
/// soak adds is *occasions* for those checks, not more of them. Counting tests
/// would be the wrong measure of this file; counting matches is the right one.
/// It plays **630**: 410 across the strength-by-table matrix, 40 at mixed
/// tables, 60 across the two team modes and 120 across the rule variants.
///
/// Each strength gets a batch size matched to what it costs to think, so the
/// whole suite stays inside a nightly rather than a weekend. Hard searches, so
/// it plays fewer matches and each one is worth more.
///
/// Every batch starts from a **stated seed**. A failure names the exact seed
/// that produced it, and `SimulationTests.seedReproducesAMatch` establishes
/// that a seed replays identically — so a failure here is a bug report that
/// can be handed straight back to the engine, not a story about a machine that
/// once went wrong.
///
///     KEEZLY_EXTENDED_SIM=1 swift test --filter Soak
@Suite("Soak")
struct SoakTests {

    /// The three strengths, with the batch size each one earns.
    enum Strength: String, CaseIterable {
        case easy, medium, hard

        /// How many matches to play. Hard searches a tree per decision; a
        /// batch the size of Easy's would take the suite out of a nightly and
        /// would not find anything the smaller one misses, because what the
        /// soak is looking for is unusual *positions*, and Easy reaches
        /// stranger positions than Hard does.
        var batch: Int {
            switch self {
            case .easy: 48
            case .medium: 24
            case .hard: 10
            }
        }

        func agent(seat: Int, salt: UInt64) -> any AIAgent {
            let seed = salt &+ UInt64(seat &* 977)
            switch self {
            case .easy: return EasyAgent(seed: seed)
            case .medium: return MediumAgent(seed: seed)
            // A smaller search than Hard's default, and the counts *are* the
            // bound: the simulation budget consults no clock (ISS-017), so
            // what used to be cut short at fifty milliseconds now runs to
            // completion, and at full size a soak batch stops being something
            // that fits in a night.
            //
            // Legitimate because of what this suite is for. It is not
            // measuring how well Hard plays — `AIStrengthTests` does that, at
            // full size — it is checking that the engine survives a strong
            // agent reaching unusual positions, and a four-candidate search
            // reaches those just as well.
            case .hard: return HardAgent(
                seed: seed,
                budget: .simulation,
                candidateLimit: 4,
                samplesPerCandidate: 3,
                rolloutPlies: 6
            )
            }
        }
    }

    private static func table(_ strength: Strength, seatCount: Int, salt: UInt64) -> [any AIAgent] {
        (0..<seatCount).map { strength.agent(seat: $0, salt: salt) }
    }

    // MARK: - The matrix

    @Test(
        "every strength plays clean matches at every table size",
        .extendedSimulation,
        arguments: Strength.allCases, 2...6
    )
    func everyStrengthAtEveryTable(strength: Strength, seatCount: Int) async {
        // Seeds are derived from the case rather than shared, so two cases
        // never play the same match and the matrix is as wide as it looks.
        let salt = UInt64(0x50_0000 &+ seatCount &* 100 &+ strength.batch)
        let simulator = MatchSimulator(
            configuration: .standard(seatCount: seatCount),
            agents: Self.table(strength, seatCount: seatCount, salt: salt)
        )
        let report = await simulator.runBatch(count: strength.batch, firstSeed: salt)

        #expect(report.isClean, "\(strength.rawValue), \(seatCount) seats:\n\(report.summary)")
        let finished = report.completedMatches.count
        #expect(
            finished == strength.batch,
            "\(strength.rawValue), \(seatCount) seats: only \(finished) of \(strength.batch) finished"
        )
        // A match of no length is a match that did not happen, and a report
        // full of those would still call itself clean.
        #expect(report.shortestMatch > 0)
    }

    @Test(
        "a table of mixed strengths is no harder on the engine than a uniform one",
        .extendedSimulation,
        arguments: [4, 6]
    )
    func mixedStrengthsAtOneTable(seatCount: Int) async {
        // The real thing a person sets up: one human seat replaced by whatever
        // opponent they picked, and not all of them the same. An agent that
        // only ever met its own kind is an agent that has not been tested.
        let salt = UInt64(0x5A_0000 &+ seatCount)
        let order: [Strength] = [.hard, .easy, .medium, .easy, .hard, .medium]
        let agents: [any AIAgent] = (0..<seatCount).map {
            order[$0 % order.count].agent(seat: $0, salt: salt)
        }
        let simulator = MatchSimulator(
            configuration: GameConfiguration(seatCount: seatCount, teamMode: .freeForAll),
            agents: agents
        )
        let report = await simulator.runBatch(count: 20, firstSeed: salt)

        #expect(report.isClean, "\(seatCount) mixed seats:\n\(report.summary)")
        #expect(report.completedMatches.count == 20)
    }

    @Test("teams and free-for-all both survive a sustained run", .extendedSimulation)
    func bothTeamModesSoak() async {
        for mode in [TeamMode.teamsOfTwo, .freeForAll] {
            let salt: UInt64 = mode == .teamsOfTwo ? 0x5B_0000 : 0x5C_0000
            let configuration = GameConfiguration(seatCount: 4, teamMode: mode)
            let report = await MatchSimulator(
                configuration: configuration,
                agents: Self.table(.medium, seatCount: 4, salt: salt)
            )
            .runBatch(count: 30, firstSeed: salt)

            #expect(report.isClean, "\(mode):\n\(report.summary)")

            // A team match that ended with one winner, or a free-for-all that
            // ended with two, would be a scoring fault the invariants do not
            // look for — they check the board, not the result.
            for outcome in report.completedMatches {
                guard let result = outcome.result else { continue }
                #expect(
                    result.winningSeats.count == (mode == .teamsOfTwo ? 2 : 1),
                    "\(mode) seed \(outcome.seed): \(result.winningSeats.count) winning seats"
                )
            }
        }
    }

    @Test("each house rule variant holds up over a batch, not just a match", .extendedSimulation)
    func ruleVariantsSoak() async {
        var king = RuleSet.houseRulesDefault
        king.king = .enterOrAdvance13
        var extraLap = RuleSet.houseRulesDefault
        extraLap.homeEntry = .allowExtraLap
        var blocking = RuleSet.houseRulesDefault
        blocking.ownPawnBlocking = .blocking

        let variants: [(String, RuleSet)] = [
            ("classic", .keezlyClassic),
            ("tournament", .tournament),
            ("house", .houseRulesDefault),
            ("king-enters-or-advances", king),
            ("extra-lap", extraLap),
            ("own-pawn-blocks", blocking),
        ]

        for (index, (name, rules)) in variants.enumerated() {
            let salt = UInt64(0x5D_0000 &+ index &* 1_000)
            let report = await MatchSimulator(
                configuration: GameConfiguration(seatCount: 4, teamMode: .teamsOfTwo, ruleSet: rules),
                agents: Self.table(.medium, seatCount: 4, salt: salt)
            )
            .runBatch(count: 20, firstSeed: salt)

            #expect(report.isClean, "\(name):\n\(report.summary)")
            #expect(report.completedMatches.count == 20, "\(name): a match did not finish")
        }
    }
}
