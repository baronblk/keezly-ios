import Foundation
import KeezlyCore

/// Puts the board into words.
///
/// Written for somebody who cannot see it. "Red pawn" is not enough to play
/// with: a player needs to know *which* red pawn, where it stands, how far it
/// has left to go, and what a move would do (§53). So every phrase here
/// carries a position and, where there is one, a consequence.
///
/// Narrates from a `PlayerObservation`, never from a `GameState`. Not for
/// convenience — it is the same boundary an AI agent plays behind (DEC-014).
/// A spoken description is a channel like any other, and a blind player must
/// hear exactly what a sighted one sees: their own hand, everybody's pieces,
/// and nothing else. Taking the full state here would have made the
/// accessibility path the one way into the game that leaks.
///
/// Returns finished strings rather than `LocalizedStringKey`, because these
/// phrases are built out of each other — a move contains a pawn, a Seven
/// contains two legs — and a key cannot be nested inside another key.
enum MoveNarrator {

    // MARK: - Pieces

    /// A pawn: whose it is, which one, and where it stands.
    ///
    /// *Red pawn 2, 11 squares from home.*
    static func pawn(_ id: PawnID, in observation: PlayerObservation) -> String {
        let name = seatName(id.seat)
        let number = id.slot + 1
        switch state(of: id, in: observation).position {
        case .waiting:
            return String(localized: "a11y.pawn.waiting \(name) \(number)")
        case .home(_, let slot):
            return String(localized: "a11y.pawn.home \(name) \(number) \(slot + 1)")
        case .track:
            let remaining = squaresFromHome(id, in: observation)
            return String(localized: "a11y.pawn.track \(name) \(number) \(remaining)")
        }
    }

    /// How far a pawn still has to travel to be home.
    ///
    /// The number a player actually reasons with. A square index means nothing
    /// without the whole board in your head; "eleven from home" means
    /// something immediately.
    static func squaresFromHome(_ id: PawnID, in observation: PlayerObservation) -> Int {
        let pawn = state(of: id, in: observation)
        guard let travelled = observation.progress(of: pawn) else {
            return observation.board.fullJourneyLength
        }
        return max(0, observation.board.fullJourneyLength - travelled)
    }

    /// A pawn named but not placed.
    ///
    /// For phrases that already say where it is. "Bring red pawn 1, in the
    /// start, out of the start" is what saying it twice sounds like.
    static func pawnName(_ id: PawnID) -> String {
        String(localized: "a11y.pawn.name \(seatName(id.seat)) \(id.slot + 1)")
    }

    private static func state(of id: PawnID, in observation: PlayerObservation) -> PawnState {
        observation.pawns[id.seat.index * pawnsPerSeat + id.slot]
    }

    /// How a pawn is offering itself right now, if it is.
    ///
    /// Spoken as a value rather than folded into the label, so VoiceOver reads
    /// the piece the same way every time and only adds what has changed.
    static func pawnState(selectable: Bool, selected: Bool) -> String? {
        if selected { return String(localized: "a11y.pawn.selected") }
        if selectable { return String(localized: "a11y.pawn.selectable") }
        return nil
    }

    // MARK: - Squares

    /// A square, from the point of view of the player being spoken to.
    ///
    /// Distances are counted towards *their* home, because that is the only
    /// frame in which a number on this board means anything: "square 31" is
    /// arithmetic, "nine from home" is a decision.
    static func square(_ position: BoardPosition, in observation: PlayerObservation) -> String {
        switch position {
        case .waiting(let seat, _):
            return String(localized: "a11y.square.start \(seatName(seat))")
        case .home(let seat, let slot):
            return String(localized: "a11y.square.home \(seatName(seat)) \(slot + 1)")
        case .track(let index):
            let travelled = observation.board.progress(ofTrackIndex: index, for: observation.seat)
            let remaining = max(0, observation.board.fullJourneyLength - travelled)
            return String(localized: "a11y.square.track \(remaining)")
        }
    }

    /// Who is standing on a square, when somebody is.
    ///
    /// The thing a sighted player sees at a glance and a listener otherwise
    /// only finds out after the move: that the square they are about to take
    /// is occupied.
    static func occupant(of position: BoardPosition, in observation: PlayerObservation) -> String? {
        guard let standing = observation.pawns.first(where: { $0.position == position }) else { return nil }
        return String(localized: "a11y.square.occupied \(pawn(standing.id, in: observation))")
    }

    // MARK: - Cards

    /// A card, with what it does in Keezen.
    ///
    /// *Seven. Seven steps, split across one or two pawns.*
    ///
    /// The hand and the action list say this the same way because they say it
    /// with the same function. A card described one way when it is held and
    /// another when it is listed is two vocabularies for one object, and a
    /// listener has to learn both.
    static func card(_ rank: CardRank) -> String {
        switch rank {
        case .ace: String(localized: "card.ace.spoken")
        case .king: String(localized: "card.king.spoken")
        case .queen: String(localized: "card.queen.spoken")
        case .jack: String(localized: "card.jack.spoken")
        case .four: String(localized: "card.four.spoken")
        case .seven: String(localized: "card.seven.spoken")
        default: String(localized: "card.number.spoken \(rank.rawValue)")
        }
    }

    /// The card's name alone, for phrases that go on to say what the move is.
    ///
    /// The key is built into a variable first: interpolating it straight into
    /// `String(localized:)` would look up `rank.%lld` and speak the key.
    static func rankName(_ rank: CardRank) -> String {
        Rulebook.text("rank.\(rank.rawValue)")
    }

    // MARK: - Moves

    /// A whole move, as an instruction a player could act on.
    ///
    /// *Ace — bring red pawn 2 out of the start.*
    /// *Seven — red pawn 2 three squares, then red pawn 4 four squares.*
    /// *Jack — swap red pawn 1 with blue pawn 3.*
    static func move(_ move: Move, in observation: PlayerObservation) -> String {
        let rank = rankName(move.card.rank)
        switch move.action {
        case .enterFromWaiting(let id):
            return String(localized: "a11y.move.enter \(rank) \(pawnName(id))")
        case .advance(let id, let steps, _):
            return String(localized: "a11y.move.advance \(rank) \(pawn(id, in: observation)) \(steps)")
        case .moveBackward(let id, let steps):
            return String(localized: "a11y.move.backward \(rank) \(pawn(id, in: observation)) \(steps)")
        case .swap(let own, let other):
            let mine = pawn(own, in: observation)
            let theirs = pawn(other, in: observation)
            return String(localized: "a11y.move.swap \(rank) \(mine) \(theirs)")
        case .split(let steps):
            return String(localized: "a11y.move.split \(rank) \(splitPhrase(steps, in: observation))")
        }
    }

    /// The legs of a Seven, written out in order.
    private static func splitPhrase(_ steps: [SplitStep], in observation: PlayerObservation) -> String {
        steps
            .map { String(localized: "a11y.leg \(pawn($0.pawn, in: observation)) \($0.steps)") }
            .joined(separator: String(localized: "a11y.leg.separator"))
    }

    // MARK: - Consequences

    /// What a move would do beyond moving a piece.
    ///
    /// Capturing, reaching home and finishing are what a player most wants to
    /// know before committing — and the hardest things to work out from a
    /// board you cannot see.
    static func consequence(preview: MovePreview, in observation: PlayerObservation) -> String? {
        if !preview.finishedSeats.isEmpty {
            return String(localized: "a11y.consequence.finishes")
        }
        if let captured = preview.captured.first {
            return String(localized: "a11y.consequence.capture \(pawn(captured, in: observation))")
        }
        if let home = preview.reachedHome.first {
            return String(localized: "a11y.consequence.home \(pawn(home, in: observation))")
        }
        return nil
    }

    // MARK: - Helpers

    static func seatName(_ seat: Seat) -> String {
        Rulebook.text(PlayerIdentity.identity(for: seat).nameKey)
    }

    /// A whole turn's worth of context, for the board itself.
    ///
    /// *Your turn as red. 5 cards, 1 pawn home.*
    static func turnSummary(for observation: PlayerObservation) -> String {
        let name = seatName(observation.seat)
        let cards = observation.hand.count
        let home = observation.homeCount(of: observation.seat)
        return String(localized: "a11y.turn \(name) \(cards) \(home)")
    }
}
