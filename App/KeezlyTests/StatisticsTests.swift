@testable import Keezly
import Foundation
import KeezlyCore
import Testing

/// §M9.1 — the statistics are derived from the matches, not kept beside them.
///
/// A stored tally is a second source of truth, and the one that drifts is
/// always the one nobody is looking at: a match deleted, a save that failed, a
/// crash between the move and the increment. These tests hold the numbers to
/// the matches they claim to describe.
@Suite("Statistics")
@MainActor
struct StatisticsTests {

    private func summary(
        seats: Int = 4,
        teams: Bool = true,
        status: MatchStatus,
        winners: [Int] = [],
        actions: Int = 40,
        id: String = UUID().uuidString
    ) -> MatchSummary {
        var record = MatchRecord(
            configuration: GameConfiguration(seatCount: seats, teamMode: teams ? .teamsOfTwo : .freeForAll),
            seed: 1,
            matchID: id
        )
        var state = record.initialState
        var generator = SeededGenerator(seed: 7)
        for _ in 0..<actions where state.result == nil {
            let legal = MoveGenerator.legalMoves(in: state, for: state.currentSeat)
            let action: PlayerAction = legal.isEmpty
                ? .foldHand(seat: state.currentSeat)
                : .play(legal[Int.random(in: 0..<legal.count, using: &generator)])
            guard let next = try? GameReducer.apply(action, to: state) else { break }
            state = next.state
            record.append(action)
        }

        var built = MatchSummary(
            record: record,
            state: state,
            roles: [.human] + Array(repeating: SeatRole.computer(.medium), count: seats - 1)
        )
        // The status and winners a real match would have arrived at; set here
        // so a test can describe a table without playing it out for an hour.
        built = MatchSummary(
            matchID: built.matchID,
            createdAt: built.createdAt,
            updatedAt: built.updatedAt,
            seatCount: built.seatCount,
            teamMode: built.teamMode,
            status: status,
            roles: built.roles,
            currentSeat: built.currentSeat,
            round: built.round,
            actionCount: built.actionCount,
            revision: built.revision,
            winningSeats: winners
        )
        return built
    }

    @Test("no matches means no numbers, and no divide by zero")
    func emptyIsEmpty() {
        let statistics = Statistics(matches: [])
        #expect(statistics.played == 0)
        #expect(statistics.winRate == nil, "a win rate out of no matches is a made-up number")
        #expect(statistics == .empty)
    }

    @Test("every match is counted once, in the right column")
    func matchesAreCounted() {
        let matches = [
            summary(status: .completed, winners: [0, 2]),
            summary(status: .completed, winners: [1, 3]),
            summary(status: .abandoned),
            summary(status: .active),
            summary(seats: 6, teams: false, status: .completed, winners: [4]),
        ]
        let statistics = Statistics(matches: matches)

        #expect(statistics.played == 5)
        #expect(statistics.finished == 3)
        #expect(statistics.abandoned == 1)
        #expect(statistics.active == 1)
        #expect(statistics.won == 1, "only the match seat 0 won counts as a win")
        #expect(statistics.bySeatCount[4] == 4)
        #expect(statistics.bySeatCount[6] == 1)
        #expect(statistics.inTeams == 4)
        #expect(statistics.freeForAll == 1)
    }

    /// **An unfinished match is not a loss.**
    ///
    /// Counting one would make the rate unfair in one direction; counting it
    /// as a win would make it flattering in the other. It is neither.
    @Test("the win rate is out of the matches that reached an ending")
    func winRateIgnoresUnfinishedMatches() throws {
        let matches = [
            summary(status: .completed, winners: [0, 2]),
            summary(status: .completed, winners: [1, 3]),
            summary(status: .abandoned),
            summary(status: .abandoned),
            summary(status: .active),
        ]
        let rate = try #require(Statistics(matches: matches).winRate)
        #expect(abs(rate - 0.5) < 0.0001, "the rate counted matches that never ended")
    }

    @Test("moves played counts the playing, not the starting")
    func movesAreCounted() {
        let brief = summary(status: .abandoned, actions: 4)
        let long = summary(status: .completed, winners: [0], actions: 120)
        let statistics = Statistics(matches: [brief, long])
        #expect(statistics.movesPlayed == brief.actionCount + long.actionCount)
        #expect(statistics.movesPlayed > 0)
    }

    // MARK: - What the summary carries

    @Test("a finished match records who won")
    func summaryCarriesTheWinner() throws {
        var record = MatchRecord(configuration: .standard(seatCount: 4), seed: 2026)
        var state = record.initialState
        var generator = SeededGenerator(seed: 11)
        for _ in 0..<900 where state.result == nil {
            let legal = MoveGenerator.legalMoves(in: state, for: state.currentSeat)
            let action: PlayerAction = legal.isEmpty
                ? .foldHand(seat: state.currentSeat)
                : .play(legal[Int.random(in: 0..<legal.count, using: &generator)])
            guard let next = try? GameReducer.apply(action, to: state) else { break }
            state = next.state
            record.append(action)
        }
        record.note(state)
        let result = try #require(state.result, "the fixture never finished a match")

        let built = MatchSummary(record: record, state: state, roles: Array(repeating: .computer(.easy), count: 4))
        #expect(built.status == .completed)
        #expect(Set(built.winningSeats) == Set(result.winningSeats.map(\.index)))
        #expect(built.didLocalSeatWin == result.winningSeats.contains(Seat(0)))
    }

    /// **A match saved before winners were recorded still opens.**
    ///
    /// The field arrived after the first matches were written. An old file is
    /// not damaged and must not be treated as such: it says "finished" rather
    /// than who won, which is exactly what was written down.
    @Test("a summary written before winners existed still decodes")
    func oldSummariesStillDecode() throws {
        let built = summary(status: .completed, winners: [0])
        var json = try #require(
            try JSONSerialization.jsonObject(
                with: GameStateCoding.makeEncoder().encode(built)
            ) as? [String: Any]
        )
        json.removeValue(forKey: "winningSeats")

        let older = try GameStateCoding.makeDecoder().decode(
            MatchSummary.self,
            from: JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        )
        #expect(older.winningSeats.isEmpty)
        #expect(older.winningSeat == nil)
        #expect(older.status == .completed, "an old match lost its status as well as its winner")
    }
}
