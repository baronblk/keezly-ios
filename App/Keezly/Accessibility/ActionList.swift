import Foundation
import KeezlyCore

/// One legal move, described.
struct ActionListEntry: Identifiable, Hashable {
    /// The move's own stable identity (§28), so the list can be diffed and a
    /// row can be matched back to what it will play.
    var id: String { move.id }
    let move: Move
    /// What playing it does, in words.
    let description: String
    /// What it would do beyond moving a piece, when there is something.
    let consequence: String?

    /// The whole row as one sentence, for VoiceOver.
    var spoken: String {
        guard let consequence else { return description }
        return "\(description). \(consequence)"
    }
}

/// Every legal move, as a list.
///
/// The board is the primary way to play, and for some people it is not a
/// usable one: hitting a particular square needs sight and a steady hand.
/// This offers the same game as a list of sentences (§53).
///
/// **It is the same moves, not a similar set.** Every entry comes from
/// `observation.legalMoves` — the engine's own answer, the same one the board
/// highlights from. There is no second idea here about what is legal, because
/// two ideas about legality is one too many (DEC-004). `ActionListTests`
/// asserts the two sets are equal rather than merely overlapping.
struct ActionList {
    let entries: [ActionListEntry]

    init(observation: PlayerObservation) {
        // Previewed in one pass, as an agent would: the shadow board is built
        // once rather than per move.
        let previews = Dictionary(
            observation.previewAll().map { ($0.move.id, $0.preview) },
            uniquingKeysWith: { first, _ in first }
        )

        entries = observation.legalMoves.map { move in
            ActionListEntry(
                move: move,
                description: MoveNarrator.move(move, in: observation),
                consequence: previews[move.id].flatMap {
                    MoveNarrator.consequence(preview: $0, in: observation)
                }
            )
        }
    }

    var isEmpty: Bool { entries.isEmpty }
    var count: Int { entries.count }

    /// The moves this list can reach. Used by the test that keeps it honest.
    var reachableMoves: Set<Move> { Set(entries.map(\.move)) }

    /// Grouped by the card that plays them, which is how a player thinks about
    /// a hand: pick a card, then decide what to do with it.
    var byCard: [ActionListGroup] {
        let grouped: [Card: [ActionListEntry]] = Dictionary(grouping: entries, by: \.move.card)
        let ordered: [(key: Card, value: [ActionListEntry])] = grouped.sorted { lhs, rhs in
            let left = lhs.key
            let right = rhs.key
            if left.rank.rawValue != right.rank.rawValue {
                return left.rank.rawValue < right.rank.rawValue
            }
            return left.id < right.id
        }
        return ordered.map { ActionListGroup(card: $0.key, entries: $0.value) }
    }
}

/// The moves one card can play.
struct ActionListGroup: Identifiable, Hashable {
    var id: Int { card.id }
    let card: Card
    let entries: [ActionListEntry]

    /// What the card is and what it does, spoken once for the whole group
    /// rather than repeated on every row.
    var spoken: String { MoveNarrator.card(card.rank) }
}
