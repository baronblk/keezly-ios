import KeezlyCore

/// A suggestion, with the reason it is trustworthy attached.
struct Hint: Hashable, Sendable {
    let move: Move
    /// The move in words, in the same vocabulary as everything else.
    let description: String
    /// What it would do beyond moving a piece, when there is something.
    let consequence: String?

    var spoken: String {
        guard let consequence else { return description }
        return "\(description). \(consequence)"
    }
}

/// Where a hint comes from.
///
/// **It is a computer opponent, playing your hand.** The hint is produced by
/// handing the same `PlayerObservation` the player has to the same agent that
/// plays the other seats, and saying what it would do. That is what makes it
/// honest: an agent cannot see a card the player cannot see, because the
/// boundary that stops it is the same one the whole game is built on
/// (DEC-014). A hint calculated from the real `GameState` would be a hint that
/// knows the deck, and nothing on screen would say so.
///
/// It is also why the hint is sometimes wrong. It is one competent player's
/// opinion, not an oracle, and the wording says as much.
enum HintProvider {

    /// The strength a hint is given at.
    ///
    /// Medium, always, and deliberately not the table's own difficulty. A hint
    /// from the Easy agent would be near-random and worse than none; one from
    /// Hard would take a search budget the player is waiting on. Medium
    /// answers immediately and plays a sensible game.
    static let strength: AIDifficulty = .medium

    /// Asks for a move, or returns nothing when there is none to suggest.
    ///
    /// Seeded from the observation itself, so the same position always gives
    /// the same advice — a hint that changed every time it was asked would
    /// teach nobody anything.
    static func hint(for observation: PlayerObservation) async -> Hint? {
        guard !observation.legalMoves.isEmpty else { return nil }

        let agent = MediumAgent(seed: observation.stableKey)
        guard case .play(let move) = await agent.chooseAction(for: observation) else { return nil }

        return Hint(
            move: move,
            description: MoveNarrator.move(move, in: observation),
            consequence: observation.preview(move).flatMap {
                MoveNarrator.consequence(preview: $0, in: observation)
            }
        )
    }
}
