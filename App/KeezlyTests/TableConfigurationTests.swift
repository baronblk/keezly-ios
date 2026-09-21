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

/// §34 — pass & play: several people sharing one device.
@Suite("Pass and play")
struct PassAndPlayTests {

    private func table(seats: Int, people: Int, teams: Bool = true) -> TableConfiguration {
        var table = TableConfiguration()
        table.seatCount = seats
        table.humanCount = people
        table.prefersTeams = teams
        return table
    }

    @Test("one person at the table is not pass and play")
    func soloIsNotPassAndPlay() {
        #expect(!table(seats: 4, people: 1).isPassAndPlay)
        #expect(table(seats: 4, people: 2).isPassAndPlay)
    }

    @Test("people take the first seats and the computer takes the rest", arguments: 1...4)
    func peopleFillFromTheFirstSeat(people: Int) {
        let roles = table(seats: 4, people: people).roles
        #expect(roles.prefix(people).allSatisfy { $0.isHuman })
        #expect(roles.dropFirst(people).allSatisfy { !$0.isHuman })
        #expect(roles.count == 4)
    }

    @Test("a table cannot seat more people than it has seats")
    func peopleAreCappedBySeats() {
        // The stored count is deliberately *not* clamped, so shrinking a table
        // and growing it again does not forget how many people were playing.
        var table = table(seats: 6, people: 6)
        table.seatCount = 2
        #expect(table.seatedHumans == 2)
        #expect(table.roles.count == 2)
        #expect(table.roles.allSatisfy { $0.isHuman })

        table.seatCount = 6
        #expect(table.seatedHumans == 6, "the table forgot how many people were playing")
    }

    @Test("two people at a four-seat partners table are opponents")
    func twoPeopleAtFourSeatsAreRivals() {
        // Seats 0 and 2 are allies at four seats, so the first two seats are
        // on opposite sides.
        #expect(!table(seats: 4, people: 2).seatsPeopleAsPartners)
    }

    @Test("two people at a six-seat partners table are partners")
    func twoPeopleAtSixSeatsArePartners() {
        // At six seats seat 0 is allied with seat 3 — but seats 0, 1 and 2 are
        // one side each, so the first two people are on different sides.
        let six = table(seats: 6, people: 2)
        #expect(six.seatsPeopleAsPartners == six.gameConfiguration.areAllied(Seat(0), Seat(1)))
    }

    @Test("partners are never claimed where the table has none")
    func noPartnersWithoutTeams() {
        #expect(!table(seats: 4, people: 4, teams: false).seatsPeopleAsPartners)
        #expect(!table(seats: 3, people: 3).seatsPeopleAsPartners)
    }

    @Test("a session knows every seat a person plays", arguments: 1...4)
    @MainActor
    func sessionReportsTheHumanSeats(people: Int) {
        let table = table(seats: 4, people: people)
        let session = MatchSession(
            configuration: table.gameConfiguration,
            seed: 2026,
            roles: table.roles
        )
        #expect(session.humanSeats.map(\.index) == Array(0..<people))
        #expect(session.isPassAndPlay == (people > 1))
    }

    @Test("the seat on turn is a person's only when it really is")
    @MainActor
    func seatOnTurnIsOnlyEverAPerson() {
        let table = table(seats: 4, people: 2)
        let session = MatchSession(
            configuration: table.gameConfiguration,
            seed: 2026,
            roles: table.roles
        )
        // Whatever the deal produced, the rule holds: `seatOnTurn` is set if
        // and only if the seat playing is one a person holds. That is what the
        // privacy cover keys off, so it must never name a computer's seat.
        let onTurn = session.state.currentSeat
        let isPerson = session.roles[onTurn.index].isHuman
        #expect((session.seatOnTurn != nil) == isPerson)
        if let seat = session.seatOnTurn {
            #expect(session.humanSeats.contains(seat))
        }
    }
}
