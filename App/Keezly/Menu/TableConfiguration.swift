import Foundation
import KeezlyCore

/// The table a player has set up, before a card has been dealt.
///
/// A value, kept apart from the screen that edits it, so the rules about which
/// tables make sense can be tested without a view — and so the menu can never
/// offer a table the engine would refuse (§34).
struct TableConfiguration: Equatable {
    /// How many seats are at the table. The engine supports 2 to 6 (§8).
    var seatCount: Int = 4
    /// Whether the seats are paired. Only meaningful on some tables; see
    /// `allowsTeams`.
    var prefersTeams: Bool = true
    /// How hard the computer opponents play.
    var difficulty: AIDifficulty = .medium
    /// How many seats are taken by people sharing the device (§34).
    ///
    /// One is an ordinary game against the computer. More is pass & play: the
    /// device goes round the table, and the seats fill from the first.
    var humanCount: Int = 1

    static let seatCounts = Array(2...6)

    /// Whether partners are possible at this table size.
    ///
    /// Not simply "an even number". At two seats `teamsOfTwo` would put both
    /// players on the same side — the engine pairs seat *i* with seat
    /// *i + seatCount/2*, which at two seats is the same seat — so a two-player
    /// table is always everyone for themselves. Three and five are odd and
    /// cannot pair at all.
    static func allowsTeams(seatCount: Int) -> Bool {
        seatCount >= 4 && seatCount.isMultiple(of: 2)
    }

    var allowsTeams: Bool { Self.allowsTeams(seatCount: seatCount) }

    /// What the table actually is, once the seat count has had its say.
    var teamMode: TeamMode {
        allowsTeams && prefersTeams ? .teamsOfTwo : .freeForAll
    }

    /// The configuration the engine is started with.
    var gameConfiguration: GameConfiguration {
        GameConfiguration(seatCount: seatCount, teamMode: teamMode)
    }

    /// How many people can share this table. At least one, at most every seat.
    var humanRange: ClosedRange<Int> { 1...seatCount }

    /// The number of people actually seated, whatever the stepper last held.
    ///
    /// Kept as a separate reading rather than clamping the stored value, so
    /// reducing the table from six seats to two and back does not silently
    /// forget that four people were playing.
    var seatedHumans: Int { min(max(1, humanCount), seatCount) }

    /// Who plays each seat: the people first, then the computer.
    ///
    /// People take consecutive seats rather than being spread around the
    /// table. On a partners table that matters — seats *i* and *i + n/2* are
    /// allies — and `partnerships` says what it comes to.
    var roles: [SeatRole] {
        let people = seatedHumans
        return (0..<seatCount).map { $0 < people ? .human : .computer(difficulty) }
    }

    /// Whether two people at this table are partners rather than opponents.
    ///
    /// Worth saying out loud in the menu: at four seats two people are
    /// opponents, at six seats they are partners, and a player setting up the
    /// table should not have to work that out from the seating.
    var seatsPeopleAsPartners: Bool {
        guard teamMode == .teamsOfTwo, seatedHumans >= 2 else { return false }
        let configuration = gameConfiguration
        return (1..<seatedHumans).contains { configuration.areAllied(Seat(0), Seat($0)) }
    }

    /// Whether the device has to change hands during a turn (§34).
    var isPassAndPlay: Bool { seatedHumans > 1 }
}
