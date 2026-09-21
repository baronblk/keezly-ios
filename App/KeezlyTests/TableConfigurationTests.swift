import Foundation
@testable import Keezly
import KeezlyCore
import Testing

/// §8, §34 — the menu may only offer tables the engine would accept, and it
/// must never quietly set up a different table from the one shown.
@Suite("Table configuration")
struct TableConfigurationTests {

    @Test("every offered table size is one the engine supports")
    func offeredSizesAreLegal() {
        #expect(TableConfiguration.seatCounts == [2, 3, 4, 5, 6])
        for count in TableConfiguration.seatCounts {
            var table = TableConfiguration()
            table.seatCount = count
            // Would trap on an unsupported size, which is the point.
            #expect(table.gameConfiguration.seatCount == count)
        }
    }

    @Test("partners are offered only where they mean something", arguments: 2...6)
    func partnersOnlyWhereTheyMakeSense(seats: Int) {
        // Not merely "even". At two seats the engine pairs seat i with seat
        // i + seatCount/2, which is the same seat — both players would be on
        // one side. Three and five cannot pair at all.
        #expect(TableConfiguration.allowsTeams(seatCount: seats) == (seats == 4 || seats == 6))
    }

    @Test("a table that cannot have partners never claims to", arguments: 2...6)
    func teamPreferenceIsIgnoredWhereImpossible(seats: Int) {
        var table = TableConfiguration()
        table.seatCount = seats
        table.prefersTeams = true

        let expected: TeamMode = TableConfiguration.allowsTeams(seatCount: seats) ? .teamsOfTwo : .freeForAll
        #expect(table.teamMode == expected)
        #expect(table.gameConfiguration.teamMode == expected)
    }

    @Test("a two-player table really is everyone for themselves")
    func twoPlayersAreNeverPartners() {
        var table = TableConfiguration()
        table.seatCount = 2
        table.prefersTeams = true

        let configuration = table.gameConfiguration
        #expect(configuration.teamMode == .freeForAll)
        #expect(!configuration.areAllied(Seat(0), Seat(1)))
    }

    @Test("choosing partners actually pairs opposite seats")
    func partnersSitOpposite() {
        var table = TableConfiguration()
        table.seatCount = 4
        table.prefersTeams = true

        let configuration = table.gameConfiguration
        #expect(configuration.areAllied(Seat(0), Seat(2)))
        #expect(!configuration.areAllied(Seat(0), Seat(1)))
    }

    @Test("turning partners off leaves everyone on their own")
    func freeForAllIsHonoured() {
        var table = TableConfiguration()
        table.seatCount = 4
        table.prefersTeams = false

        #expect(table.teamMode == .freeForAll)
        #expect(!table.gameConfiguration.areAllied(Seat(0), Seat(2)))
    }

    @Test("one seat is the player's and the rest are the computer's", arguments: 2...6)
    func seatsAreFilled(seats: Int) {
        var table = TableConfiguration()
        table.seatCount = seats
        table.difficulty = .hard

        let roles = table.roles
        #expect(roles.count == seats)
        #expect(roles.first == .human)
        #expect(roles.dropFirst().allSatisfy { $0 == .computer(.hard) })
        // One role per seat, or the session's own precondition would trap.
        #expect(roles.count == table.gameConfiguration.seatCount)
    }

    @Test("the chosen difficulty is the one that plays", arguments: [AIDifficulty.easy, .medium, .hard])
    func difficultyReachesTheOpponents(difficulty: AIDifficulty) {
        var table = TableConfiguration()
        table.difficulty = difficulty
        #expect(table.roles.dropFirst().allSatisfy { $0 == .computer(difficulty) })
    }

    @Test("a table set up in the menu starts as that table", arguments: 2...6)
    @MainActor
    func theTableStartedIsTheTableChosen(seats: Int) {
        var table = TableConfiguration()
        table.seatCount = seats
        table.prefersTeams = true
        table.difficulty = .easy

        let session = MatchSession(
            configuration: table.gameConfiguration,
            seed: 2026,
            roles: table.roles
        )

        #expect(session.state.configuration.seatCount == seats)
        #expect(session.state.configuration.teamMode == table.teamMode)
        #expect(session.localSeat == Seat(0))
        #expect(session.state.pawns.count == seats * pawnsPerSeat)
    }
}
