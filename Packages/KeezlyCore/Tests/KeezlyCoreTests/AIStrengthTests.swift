@testable import KeezlyCore
import Testing

/// §25 — every claim about relative agent strength is backed by a simulation
/// that actually ran. No assertion here demands that a stronger agent wins
/// every match; they are all about aggregates, with margins well clear of the
/// measured values so ordinary variance does not turn the suite red.
@Suite("AI strength")
struct AIStrengthTests {

    /// Plays team matches with one side's agents against the other's and
    /// returns the first team's win rate.
    static func teamDuel(
        _ teamA: @Sendable (Int) -> any AIAgent,
        _ teamB: @Sendable (Int) -> any AIAgent,
        seatCount: Int = 4,
        count: Int,
        firstSeed: UInt64
    ) async -> (rate: Double, report: SimulationReport) {
        let configuration = GameConfiguration(seatCount: seatCount, teamMode: .teamsOfTwo)
        let agents: [any AIAgent] = (0..<seatCount).map { seat in
            configuration.team(of: Seat(seat)) == TeamID(0) ? teamA(seat) : teamB(seat)
        }
        let report = await MatchSimulator(configuration: configuration, agents: agents)
            .runBatch(count: count, firstSeed: firstSeed)
        return (report.winRate(ofSeats: Set(configuration.seats(in: TeamID(0)).map(\.index))), report)
    }

    // MARK: - Fast assertions

    @Test("Hard clearly outplays Easy")
    func hardBeatsEasy() async {
        let (rate, report) = await Self.teamDuel(
            { HardAgent(seed: UInt64(150 + $0), budget: .simulation) },
            { EasyAgent(seed: UInt64(250 + $0)) },
            count: 24, firstSeed: 11_000
        )
        #expect(report.isClean, "\(report.summary)")
        // Measured at 0.975 over 40 matches.
        #expect(rate > 0.70, "Hard won only \(rate) of \(report.completedMatches.count) matches")
    }

    @Test("Hard measurably outplays Medium")
    func hardBeatsMedium() async {
        let (rate, report) = await Self.teamDuel(
            { HardAgent(seed: UInt64(160 + $0), budget: .simulation) },
            { MediumAgent(seed: UInt64(260 + $0)) },
            count: 24, firstSeed: 12_000
        )
        #expect(report.isClean, "\(report.summary)")
        // Measured at 0.675 over 40 matches and 0.633 over 30. The bar allows
        // for the wide variance of a 24-match sample.
        #expect(rate > 0.50, "Hard won only \(rate) of \(report.completedMatches.count) matches")
    }

    @Test("Medium clearly outplays Easy")
    func mediumBeatsEasy() async {
        let (rate, report) = await Self.teamDuel(
            { MediumAgent(seed: UInt64(100 + $0)) },
            { EasyAgent(seed: UInt64(200 + $0)) },
            count: 40, firstSeed: 10_000
        )
        #expect(report.isClean, "\(report.summary)")
        // Measured at 0.975 over 80 matches; the bar sits far below that so
        // normal variance cannot fail the suite.
        #expect(rate > 0.70, "Medium won only \(rate) of \(report.completedMatches.count) matches")
    }

    @Test("two Easy agents are roughly even")
    func easyBaselineIsBalanced() async {
        let (rate, report) = await Self.teamDuel(
            { EasyAgent(seed: UInt64(300 + $0)) },
            { EasyAgent(seed: UInt64(400 + $0)) },
            count: 40, firstSeed: 20_000
        )
        #expect(report.isClean, "\(report.summary)")
        #expect(rate > 0.2 && rate < 0.8, "Easy vs Easy came out at \(rate), which suggests a structural bias")
    }

    @Test("agents keep their advantage at other table sizes", arguments: [2, 6])
    func mediumBeatsEasyAtOtherTableSizes(seatCount: Int) async {
        let (rate, report) = await Self.teamDuel(
            { MediumAgent(seed: UInt64(500 + $0)) },
            { EasyAgent(seed: UInt64(600 + $0)) },
            seatCount: seatCount, count: 24, firstSeed: 30_000
        )
        #expect(report.isClean, "\(report.summary)")
        #expect(rate > 0.60, "seat count \(seatCount): Medium won only \(rate)")
    }

    @Test("agents decide fast enough for interactive play")
    func decisionsAreFast() async {
        let (_, report) = await Self.teamDuel(
            { MediumAgent(seed: UInt64(700 + $0)) },
            { EasyAgent(seed: UInt64(800 + $0)) },
            count: 20, firstSeed: 40_000
        )
        // Measured around 0.3 ms per action on an M-series Mac. The ceiling is
        // deliberately loose: this guards against an accidental blow-up, not
        // against normal machine-to-machine variation.
        #expect(report.averageDecisionDuration < .milliseconds(50),
                "average decision took \(report.averageDecisionDuration)")
    }

    // MARK: - Extended runs (KEEZLY_EXTENDED_SIM=1)

    @Test("no seat is structurally favoured", .extendedSimulation, arguments: [2, 3, 4, 6])
    func seatsAreFair(seatCount: Int) async {
        // Identical agents everywhere, so any imbalance is the board or the
        // turn order rather than the agents (§9).
        let configuration = GameConfiguration(seatCount: seatCount, teamMode: .freeForAll)
        let agents: [any AIAgent] = (0..<seatCount).map { _ in EasyAgent(seed: 1) }
        let report = await MatchSimulator(configuration: configuration, agents: agents)
            .runBatch(count: 400, firstSeed: 900_000)

        #expect(report.isClean, "\(report.summary)")
        let total = Double(report.completedMatches.count)
        let expected = 1.0 / Double(seatCount)
        // Three standard errors of a binomial proportion.
        let tolerance = 3 * (expected * (1 - expected) / total).squareRoot()
        for seat in 0..<seatCount {
            let share = Double(report.winsBySeat[seat] ?? 0) / total
            #expect(abs(share - expected) < tolerance,
                    "seat \(seat) won \(share) of \(Int(total)) matches, expected \(expected) ± \(tolerance)")
        }
    }

    @Test("a large Medium versus Easy sample confirms the advantage", .extendedSimulation)
    func extendedMediumVersusEasy() async {
        let (rate, report) = await Self.teamDuel(
            { MediumAgent(seed: UInt64(1_100 + $0)) },
            { EasyAgent(seed: UInt64(1_200 + $0)) },
            count: 300, firstSeed: 50_000
        )
        #expect(report.isClean, "\(report.summary)")
        #expect(rate > 0.80, "Medium won \(rate) over \(report.completedMatches.count) matches")
    }
}
