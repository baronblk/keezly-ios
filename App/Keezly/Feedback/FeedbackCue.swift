import KeezlyCore

/// Something worth feeling or hearing.
///
/// One vocabulary for both channels. A capture is the same moment whether it
/// arrives as a knock in the hand or a click in the ear, and giving each
/// channel its own list of moments is how the two end up disagreeing about
/// what just happened.
enum FeedbackCue: String, CaseIterable, Hashable, Sendable {
    /// A card picked up in the hand. The lightest thing in the set.
    case select
    /// A card played and a piece set down.
    case place
    /// A piece knocked back to its start — somebody's, possibly your own.
    case capture
    /// A piece safely into its home lane.
    case home
    /// Two pieces exchanged by a Jack.
    case swap
    /// A hand thrown in with nothing playable in it.
    case fold
    /// The match over.
    case victory

    /// How hard it should land, 0 to 1.
    ///
    /// Deliberately quiet at the top end. A board game played for an hour is a
    /// bad place for a strong haptic: the one that feels satisfying on the
    /// first move is unbearable on the two hundredth (§43).
    var strength: Double {
        switch self {
        case .select: 0.25
        case .place: 0.4
        case .swap: 0.5
        case .home: 0.6
        case .capture: 0.7
        case .fold: 0.3
        case .victory: 0.85
        }
    }

    /// What the engine did, translated into what the player should feel.
    ///
    /// Driven from `GameEvent` rather than from taps, so the feedback follows
    /// the game rather than the interface: a capture made by a computer
    /// opponent lands the same way as one the player made, and a tap the engine
    /// refused produces nothing at all.
    ///
    /// Pure, so `FeedbackTests` can check the mapping without a device.
    static func cue(for event: GameEvent) -> FeedbackCue? {
        switch event {
        case .cardPlayed:
            .place
        case .pawnEntered, .pawnMoved:
            .place
        case .pawnCaptured:
            .capture
        case .pawnReachedHome:
            .home
        case .pawnsSwapped:
            .swap
        case .handFolded:
            .fold
        case .matchEnded:
            .victory
        // Bookkeeping. The turn passing, the deal advancing and the dealer
        // moving on are all things the screen says; none of them is a moment.
        case .seatFinished, .seatResigned, .turnPassed, .dealRoundStarted, .dealerChanged:
            nil
        }
    }

    /// The cues a run of events should produce, with runs of the same cue
    /// collapsed.
    ///
    /// A Seven split across two pieces is one move and produces several move
    /// events; buzzing once per square would turn a single decision into a
    /// stutter. The strongest cue in a burst wins, because a move that both
    /// travels and captures is a capture.
    static func cues(for events: [GameEvent]) -> [FeedbackCue] {
        var result: [FeedbackCue] = []
        for cue in events.compactMap(cue(for:)) {
            guard let previous = result.last else {
                result.append(cue)
                continue
            }
            if previous == cue { continue }
            // A place immediately followed by something louder is the same
            // moment: the piece landed *and* took something.
            if previous == .place, cue.strength > FeedbackCue.place.strength {
                result[result.count - 1] = cue
            } else {
                result.append(cue)
            }
        }
        return result
    }
}
