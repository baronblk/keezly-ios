import Foundation

/// The weights behind the Medium and Hard evaluation (§23).
///
/// Every number lives here, in one reviewable table, rather than scattered
/// through the scoring code. Changing a weight is therefore a visible diff, and
/// `AI.md` records why (§146 — no undocumented tuning).
///
/// Scale: one point is roughly "one pawn advanced one square". Home is worth
/// far more than raw progress, because progress that never converts is worth
/// nothing.
public struct HeuristicWeights: Hashable, Sendable {

    // MARK: Position

    /// Per square of progress along a pawn's own lap, for the agent's side.
    public var progressPerSquare: Double
    /// A pawn safely in the home lane.
    public var pawnHome: Double
    /// A pawn still sitting in the waiting area — it is not in the race.
    public var pawnWaiting: Double
    /// A pawn holding its own start square, which blocks the track (§15).
    public var blockade: Double

    /// How heavily opposing pawns count. Below 1 because the agent controls its
    /// own side and can only react to the others.
    public var opponentFactor: Double
    /// Extra weight on an opponent pawn that is close to home, so the agent
    /// notices the player about to win.
    public var opponentNearHome: Double

    // MARK: Events caused by the move

    /// Sending an opponent back, before the bonus for how far it had come.
    public var captureOpponent: Double
    /// Scales the capture bonus by how much progress the victim loses.
    public var capturedProgressBonus: Double
    /// Knocking out your own or your partner's pawn (§14).
    public var captureFriendly: Double
    /// A pawn reaching the home lane on this move.
    public var reachHome: Double
    /// Bringing a pawn out of the waiting area.
    public var bringPawnOut: Double

    // MARK: Risk

    /// Penalty per unit of estimated capture risk left on the agent's own
    /// pawns after the move.
    public var exposureRisk: Double
    /// Risk is discounted for a pawn that has not travelled far, because it has
    /// little to lose.
    public var exposureProgressFactor: Double

    // MARK: Search behaviour

    /// Random spread on the final score, so two Medium agents at one table do
    /// not play in lockstep. Small: Medium is supposed to look deliberate.
    public var jitter: Double

    public init(
        progressPerSquare: Double = 1.0,
        pawnHome: Double = 45.0,
        pawnWaiting: Double = -12.0,
        blockade: Double = 8.0,
        opponentFactor: Double = 0.55,
        opponentNearHome: Double = 0.5,
        captureOpponent: Double = 18.0,
        capturedProgressBonus: Double = 0.9,
        captureFriendly: Double = -40.0,
        reachHome: Double = 25.0,
        bringPawnOut: Double = 10.0,
        exposureRisk: Double = 22.0,
        exposureProgressFactor: Double = 0.8,
        jitter: Double = 1.5
    ) {
        self.progressPerSquare = progressPerSquare
        self.pawnHome = pawnHome
        self.pawnWaiting = pawnWaiting
        self.blockade = blockade
        self.opponentFactor = opponentFactor
        self.opponentNearHome = opponentNearHome
        self.captureOpponent = captureOpponent
        self.capturedProgressBonus = capturedProgressBonus
        self.captureFriendly = captureFriendly
        self.reachHome = reachHome
        self.bringPawnOut = bringPawnOut
        self.exposureRisk = exposureRisk
        self.exposureProgressFactor = exposureProgressFactor
        self.jitter = jitter
    }

    /// The tuned defaults used by the Medium agent.
    public static let medium = HeuristicWeights()

    /// Hard evaluates the same features but trusts rollouts for the long view,
    /// so its static risk term is slightly softer and its jitter is off.
    public static let hard = HeuristicWeights(exposureRisk: 18.0, jitter: 0.0)
}
