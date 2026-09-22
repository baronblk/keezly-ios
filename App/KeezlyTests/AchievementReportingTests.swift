@testable import Keezly
import KeezlyCore
import Testing

/// Registered with Apple and never reported is the same as not shipped.
///
/// These tests exist because that is exactly what Keezly did for a while: ten
/// achievements in App Store Connect, a tested evaluator, and nothing in the
/// app that ever told Game Center about either. `AchievementTests` could not
/// catch it, because the evaluator was right the whole time — what was missing
/// was anything that called it.
@Suite("Achievement reporting")
@MainActor
struct AchievementReportingTests {

    /// Stands in for Game Center. Records what it was asked to report.
    final class Spy: AchievementReporting, @unchecked Sendable {
        private(set) var started = 0
        private(set) var reports: [Set<Achievement>] = []

        func start() { started += 1 }
        func report(_ achievements: Set<Achievement>) { reports.append(achievements) }
    }

    private func session(
        seats: Int = 4,
        humans: Int = 1,
        seed: UInt64 = 2026,
        fixture: MatchFixture? = nil,
        spy: Spy? = nil
    ) -> MatchSession {
        MatchSession(
            configuration: GameConfiguration(seatCount: seats, teamMode: .teamsOfTwo),
            seed: seed,
            roles: Array(repeating: SeatRole.human, count: humans)
                + Array(repeating: SeatRole.computer(.easy), count: seats - humans),
            budget: .simulation,
            fixture: fixture,
            fixtureLimit: 2000,
            achievements: spy
        )
    }

    // MARK: - The rule

    @Test("an unfinished match has earned nothing")
    func nothingUntilTheMatchIsOver() {
        let match = session(fixture: .movesPlayed(20))
        #expect(match.result == nil)
        #expect(match.achievementsEarned.isEmpty)
    }

    @Test("a finished solo match has earned at least the one everybody gets")
    func finishedMatchEarnsSomething() throws {
        let match = session(fixture: .movesPlayed(2000))
        try #require(match.result != nil, "the fixture never finished, so there is nothing to check")

        let seat = try #require(match.localSeat)
        #expect(match.achievementsEarned == AchievementEvaluator.unlocked(in: match.record, for: seat))
        #expect(match.achievementsEarned.contains(.finished))
    }

    /// The rule that keeps the feature honest: several people share the device
    /// and only one of them owns the Game Center account. Crediting whoever
    /// happens to sit in the first seat would attribute somebody else's win to
    /// the device's owner.
    @Test("a table of people has earned nothing, however it ended")
    func passAndPlayEarnsNothing() throws {
        let match = session(humans: 4, fixture: .movesPlayed(2000))
        try #require(match.result != nil)
        #expect(match.isPassAndPlay)
        #expect(match.achievementsEarned.isEmpty)
    }

    // MARK: - The wiring

    /// The gap this whole file exists for: the evaluator was right, and
    /// nothing called it.
    @Test("a match that finishes reports it, exactly once")
    func finishingReportsOnce() throws {
        let spy = Spy()
        let match = session(fixture: .movesPlayed(2000), spy: spy)
        try #require(match.result != nil, "the fixture never finished, so nothing could be reported")

        #expect(spy.reports.count == 1)
        #expect(spy.reports.first == match.achievementsEarned)
        #expect(spy.reports.first?.contains(.finished) == true)
    }

    @Test("a match still going has reported nothing")
    func midMatchReportsNothing() {
        let spy = Spy()
        let match = session(fixture: .movesPlayed(20), spy: spy)
        #expect(match.result == nil)
        #expect(spy.reports.isEmpty)
    }

    @Test("a table of people reports nothing even when it ends")
    func passAndPlayReportsNothing() throws {
        let spy = Spy()
        let match = session(humans: 4, fixture: .movesPlayed(2000), spy: spy)
        try #require(match.result != nil)
        #expect(spy.reports.isEmpty)
    }

    // MARK: - The harness

    /// A test or screenshot run must never reach Apple: authentication can put
    /// a system sheet over the board, which would fail whatever the run was
    /// checking and, in a screenshot run, ship the sheet to the App Store.
    @Test("Game Center is switched off under a test harness")
    func disabledUnderTests() {
        #expect(ScreenshotMode.isRunningTests, "this suite is running under XCTest and did not notice")
        #expect(GameCenterAchievements.isEnabled == false)
    }
}
