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
    /// How long the agent may think, or `nil` when it must not look at a clock
    /// at all.
    ///
    /// Somebody waiting for a move is a real constraint, so interactive play is
    /// time-boxed. A simulated match has nobody waiting, and there a clock is
    /// actively harmful: the number of worlds a decision gets to sample depends
    /// on how loaded the machine happens to be, so the same seed plays a
    /// different match on a busy afternoon than on a quiet one.
    ///
    /// That breaks the whole point of seeding (DEC-003) — a failing simulation
    /// seed is only a bug report if somebody else can run it — and it is how a
    /// soak failure came to vanish on the next run.
    public let maximumDuration: Duration?

    public init(maximumDuration: Duration) {
        self.maximumDuration = maximumDuration
    }

    private init() {
        maximumDuration = nil
    }

    public static let interactive = AIBudget(maximumDuration: .milliseconds(700))
    /// Used by the headless simulation harness, where reproducibility matters
    /// more than latency.
    ///
    /// Bounded by the search's own sample counts rather than by time. Those
    /// counts are small and fixed — six candidates, eight sampled worlds each,
    /// eight plies — so a decision is cheap without a clock needing to cut it
    /// short.
    public static let simulation = AIBudget()
}
