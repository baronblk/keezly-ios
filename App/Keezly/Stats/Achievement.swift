import KeezlyCore

/// Something a player did, worth noticing once.
///
/// **Every one is derived from what the engine did.** An achievement is worked
/// out by replaying a finished match and watching its `GameEvent`s go past —
/// the same events the board animates. Nothing in a view decides whether an
/// achievement is earned, and nothing is counted as it happens, so there is no
/// tally to drift out of step with the matches (§M9.4).
///
/// Chosen to be things a player would recognise having done. "Play 500 matches"
/// is a measure of endurance rather than of anything that happened at the
/// table, and Keezen has enough luck in it that most such targets say more
/// about the deal than the player.
enum Achievement: String, CaseIterable, Identifiable, Hashable, Sendable {
    /// Play a match through to its end.
    case finished
    /// Win one.
    case won
    /// Win one without ever being knocked back.
    case untouched
    /// Split a Seven across two pieces.
    case split
    /// Swap with a Jack.
    case swapped
    /// Send a piece backwards with a Four.
    case backwards
    /// Knock somebody out.
    case knockout
    /// Win after being knocked out at least once.
    case resilient
    /// Play a six-player match to the end.
    case fullTable
    /// Win as one of a pair.
    case partners

    var id: String { rawValue }

    /// The identifier registered with Game Center.
    ///
    /// Written out in full rather than derived, because it is a published
    /// name: once a player has earned one, renaming it loses their progress.
    var gameCenterID: String { "de.gcng.keezly.achievement.\(rawValue)" }

    /// Game Center points. They total 100 across the set, which is the shape
    /// Apple's guidance asks for: a handful of things worth doing rather than
    /// a hundred worth a point each.
    var points: Int {
        switch self {
        case .finished: 5
        case .won: 10
        case .untouched: 20
        case .split: 10
        case .swapped: 5
        case .backwards: 5
        case .knockout: 5
        case .resilient: 15
        case .fullTable: 10
        case .partners: 15
        }
    }

    var title: String { Rulebook.text("achievement.\(rawValue).title") }
    var detail: String { Rulebook.text("achievement.\(rawValue).detail") }
}

/// Works out what a finished match earned.
///
/// Pure, and given a record rather than a live session: an achievement is a
/// fact about a match that has already happened, and evaluating it by replaying
/// the record means it can be recomputed at any time and always gives the same
/// answer (DEC-023).
enum AchievementEvaluator {

    /// What this match earned for the seat the device was playing.
    ///
    /// Returns nothing for a match that was abandoned: leaving a game halfway
    /// is not an accomplishment, and counting it as one would make the set
    /// meaningless.
    static func unlocked(in record: MatchRecord, for seat: Seat) -> Set<Achievement> {
        guard record.status == .completed else { return [] }

        var earned: Set<Achievement> = []
        var state = record.initialState
        var wasKnockedOut = false

        for action in record.actions {
            guard let transition = try? GameReducer.apply(action, to: state) else { return earned }
            earned.formUnion(during(transition.events, playedBy: state.currentSeat, for: seat))
            if transition.events.contains(where: { knocked($0, belongsTo: seat) }) {
                wasKnockedOut = true
            }
            state = transition.state
        }

        guard let result = state.result else { return earned }
        earned.insert(.finished)
        if state.configuration.seatCount == 6 { earned.insert(.fullTable) }

        guard result.winningSeats.contains(seat) else { return earned }
        earned.insert(.won)
        if state.configuration.teamMode == .teamsOfTwo { earned.insert(.partners) }
        if wasKnockedOut {
            earned.insert(.resilient)
        } else {
            earned.insert(.untouched)
        }
        return earned
    }

    /// What one turn earned, if anything.
    ///
    /// `playedBy` is the seat that took the turn, which the events themselves
    /// do not all carry — a swap says which pieces moved, not whose move it
    /// was.
    private static func during(
        _ events: [GameEvent],
        playedBy actor: Seat,
        for seat: Seat
    ) -> Set<Achievement> {
        guard actor == seat else { return [] }

        var earned: Set<Achievement> = []
        var movedPawns: Set<PawnID> = []
        var playedASeven = false

        for event in events {
            switch event {
            case .cardPlayed(_, let card):
                if card.rank == .seven { playedASeven = true }
            case .pawnMoved(let pawn, _, _, _, let backward):
                movedPawns.insert(pawn)
                if backward { earned.insert(.backwards) }
            case .pawnsSwapped(let first, _, _, _):
                if first.seat == seat { earned.insert(.swapped) }
            case .pawnCaptured(let pawn, let by, _, _):
                // Knocking out your own partner is part of the game (§13), and
                // is not something to be congratulated for.
                if by.seat == seat, pawn.seat != seat { earned.insert(.knockout) }
            default:
                break
            }
        }

        // A Seven that moved two different pieces is a split; one that moved
        // one piece seven squares is not.
        if playedASeven, movedPawns.count > 1 { earned.insert(.split) }
        return earned
    }

    private static func knocked(_ event: GameEvent, belongsTo seat: Seat) -> Bool {
        if case .pawnCaptured(let pawn, _, _, _) = event { return pawn.seat == seat }
        return false
    }
}
