import Foundation

/// The three strengths Keezly ships (§21–§24).
public enum AIDifficulty: String, Hashable, Sendable, Codable, CaseIterable {
    case easy
    case medium
    case hard
}

/// A computer opponent.
///
/// The signature is the point: an agent is handed a `PlayerObservation` and
/// nothing else. It has no way to ask for the game state, the draw pile or an
/// opponent's hand, because it is never given one. "The AI does not cheat" is
/// therefore a property of this protocol rather than a promise in a comment.
///
/// `chooseAction` is `async` so the Hard agent can run a time-boxed search off
/// the main actor and honour cancellation (§24, §62).
public protocol AIAgent: Sendable {
    var difficulty: AIDifficulty { get }

    /// Picks what to do. Implementations must return one of
    /// `observation.legalMoves`, or `.foldHand` when that list is empty —
    /// the forced-move rule applies to computer opponents exactly as it does
    /// to humans (§13).
    func chooseAction(for observation: PlayerObservation) async -> PlayerAction
}

public extension AIAgent {
    /// The action to take when no legal move exists.
    func forcedFold(for observation: PlayerObservation) -> PlayerAction {
        .foldHand(seat: observation.seat)
    }
}

/// How long an agent may think before it must answer.
///
/// A budget rather than a fixed pause: Easy and Medium answer immediately, and
/// Hard searches until the budget runs out. The UI adds its own small delay for
/// feel — that is presentation, not thinking time (§24).
public struct AIBudget: Hashable, Sendable {
    public let maximumDuration: Duration

    public init(maximumDuration: Duration) {
        self.maximumDuration = maximumDuration
    }

    public static let interactive = AIBudget(maximumDuration: .milliseconds(700))
    /// Used by the headless simulation harness, where wall-clock time matters
    /// more than move quality.
    public static let simulation = AIBudget(maximumDuration: .milliseconds(50))
}
