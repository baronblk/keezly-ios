import Foundation

/// How seats are grouped into competing sides (§8).
public enum TeamMode: String, Hashable, Sendable, Codable, CaseIterable {
    /// Everyone plays for themselves.
    case freeForAll
    /// Seats are paired with the seat directly opposite them.
    case teamsOfTwo
}

/// The fixed setup of a match: who sits where and under which rules.
/// Immutable for the lifetime of the match (§18, §28).
public struct GameConfiguration: Hashable, Sendable, Codable {
    public let seatCount: Int
    public let teamMode: TeamMode
    public let ruleSet: RuleSet
    /// Seat that deals the very first hand. The player to its left starts (§12).
    public let initialDealer: Seat

    public init(
        seatCount: Int,
        teamMode: TeamMode,
        ruleSet: RuleSet = .keezlyClassic,
        initialDealer: Seat = Seat(0)
    ) {
        precondition((2...6).contains(seatCount), "Keezly supports 2...6 seats")
        precondition(
            teamMode == .freeForAll || seatCount.isMultiple(of: 2),
            "Team play requires an even number of seats"
        )
        precondition((0..<seatCount).contains(initialDealer.index), "Dealer must be a valid seat")
        self.seatCount = seatCount
        self.teamMode = teamMode
        self.ruleSet = ruleSet
        self.initialDealer = initialDealer
    }

    /// The default arrangement for a table size, per §8: partners for 4 and 6
    /// seats, everyone-for-themselves otherwise.
    public static func standard(seatCount: Int, ruleSet: RuleSet = .keezlyClassic) -> GameConfiguration {
        let mode: TeamMode = (seatCount == 4 || seatCount == 6) ? .teamsOfTwo : .freeForAll
        return GameConfiguration(seatCount: seatCount, teamMode: mode, ruleSet: ruleSet)
    }

    public var board: BoardGraph { BoardGraph(seatCount: seatCount) }
    public var seats: [Seat] { (0..<seatCount).map(Seat.init) }

    // MARK: - Teams

    /// The team a seat belongs to.
    ///
    /// In `teamsOfTwo`, seats `i` and `i + seatCount/2` share a team, which
    /// places partners directly opposite each other on the board (§8).
    public func team(of seat: Seat) -> TeamID {
        switch teamMode {
        case .freeForAll:
            return TeamID(seat.index)
        case .teamsOfTwo:
            return TeamID(seat.index % (seatCount / 2))
        }
    }

    public var teamCount: Int {
        switch teamMode {
        case .freeForAll: seatCount
        case .teamsOfTwo: seatCount / 2
        }
    }

    public func seats(in team: TeamID) -> [Seat] {
        seats.filter { self.team(of: $0) == team }
    }

    /// The partner seats of `seat`, excluding itself. Empty in free-for-all.
    public func partners(of seat: Seat) -> [Seat] {
        seats(in: team(of: seat)).filter { $0 != seat }
    }

    public func areAllied(_ a: Seat, _ b: Seat) -> Bool {
        team(of: a) == team(of: b)
    }

    // MARK: - Turn order

    /// The seat that acts after `seat` — clockwise, wrapping around the table.
    public func nextSeat(after seat: Seat) -> Seat {
        Seat((seat.index + 1) % seatCount)
    }
}
