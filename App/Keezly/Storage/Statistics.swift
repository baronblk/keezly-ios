import Foundation
import KeezlyCore

/// What the matches on this device add up to.
///
/// **Derived, never kept.** There is no counter written to disk beside the
/// matches; every number here is computed from the saved matches themselves,
/// each of which has already been replayed through the engine and checked
/// (DEC-023). A stored tally is a second source of truth, and the one that
/// drifts is always the one nobody is looking at — a match deleted, a save
/// that failed, a crash between the move and the increment.
///
/// The cost is that these numbers come from reading the match list rather than
/// from one integer. That is a list bounded by the store, read when somebody
/// opens the history screen, so the trade is worth making.
struct Statistics: Hashable, Sendable {
    /// Matches that reached an ending.
    let finished: Int
    /// Matches the person holding this device won. Seat 0 is theirs.
    let won: Int
    /// Matches begun and left.
    let abandoned: Int
    /// Matches still open.
    let active: Int
    /// How many matches were played at each table size.
    let bySeatCount: [Int: Int]
    /// Matches played in pairs, and matches played with everyone for
    /// themselves.
    let inTeams: Int
    let freeForAll: Int
    /// Total accepted actions across every match — a better measure of "how
    /// much Keezen has been played here" than a match count, because a match
    /// abandoned on the second turn and one played to the end are not the same
    /// amount of playing.
    let movesPlayed: Int

    var played: Int { finished + abandoned + active }
    /// Out of the matches that reached an ending. Unfinished matches are not
    /// losses, and counting them as such would make the number flattering in
    /// one direction or unfair in the other.
    var winRate: Double? {
        guard finished > 0 else { return nil }
        return Double(won) / Double(finished)
    }

    static let empty = Statistics(
        finished: 0, won: 0, abandoned: 0, active: 0,
        bySeatCount: [:], inTeams: 0, freeForAll: 0, movesPlayed: 0
    )

    init(
        finished: Int,
        won: Int,
        abandoned: Int,
        active: Int,
        bySeatCount: [Int: Int],
        inTeams: Int,
        freeForAll: Int,
        movesPlayed: Int
    ) {
        self.finished = finished
        self.won = won
        self.abandoned = abandoned
        self.active = active
        self.bySeatCount = bySeatCount
        self.inTeams = inTeams
        self.freeForAll = freeForAll
        self.movesPlayed = movesPlayed
    }

    /// Adds up a list of saved matches.
    init(matches: [MatchSummary]) {
        var finished = 0
        var won = 0
        var abandoned = 0
        var active = 0
        var seats: [Int: Int] = [:]
        var teams = 0
        var free = 0
        var moves = 0

        for match in matches {
            switch match.status {
            case .completed:
                finished += 1
                // Seat 0 is the person holding the device, at every table
                // Keezly currently deals.
                if match.winningSeats.contains(0) { won += 1 }
            case .abandoned: abandoned += 1
            case .active: active += 1
            }
            seats[match.seatCount, default: 0] += 1
            if match.teamMode == .teamsOfTwo { teams += 1 } else { free += 1 }
            moves += match.actionCount
        }

        self.init(
            finished: finished, won: won, abandoned: abandoned, active: active,
            bySeatCount: seats, inTeams: teams, freeForAll: free, movesPlayed: moves
        )
    }
}
