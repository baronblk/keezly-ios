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

    /// One human, the rest played by the computer.
    ///
    /// Pass & play — several people sharing one device — arrives in M5. Until
    /// then the menu does not offer it, because a menu must not contain an
    /// option that does nothing (§36).
    var roles: [SeatRole] {
        [.human] + Array(repeating: SeatRole.computer(difficulty), count: max(0, seatCount - 1))
    }
}
