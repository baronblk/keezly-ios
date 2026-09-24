import Foundation

/// What is happening between tapping "New online match" and having one.
///
/// It exists because that stretch used to be a single `Bool`. A spinner ran for
/// about two seconds, the attempt failed, the error was discarded by its own
/// `catch`, and the screen went back to exactly what it had been — no match, no
/// matchmaker, no message, nothing to retry. From the player's side the button
/// simply did nothing.
///
/// A boolean cannot express the difference between "Game Center is opening",
/// "waiting for somebody to join" and "that did not work", so the screen could
/// not draw the difference either. These are the states worth telling apart,
/// because each one wants a different sentence and a different way out (§26).
enum OnlineStartState: Hashable, Sendable {
    /// Nothing in progress. The button is live.
    case idle
    /// Signing in, before anything can be asked of Game Center.
    case authenticating
    /// Apple's matchmaker is being put on screen.
    case openingMatchmaker
    /// The matchmaker is up and the player is choosing or inviting.
    case matchmaking
    /// A match exists but has empty seats. **Not an error** — it is the normal
    /// shape of a turn-based game, and the match is waiting in the list.
    case waitingForPlayers(filled: Int, of: Int)
    /// A full match is being turned into a board.
    case loadingMatch
    /// Something went wrong, in words, with a way out.
    case failed(OnlineStartFailure)

    /// Whether the start button should be available.
    var isBusy: Bool {
        switch self {
        case .idle, .failed, .waitingForPlayers: false
        case .authenticating, .openingMatchmaker, .matchmaking, .loadingMatch: true
        }
    }

    /// Whether a player can sensibly abandon what is happening.
    var isCancellable: Bool {
        switch self {
        case .openingMatchmaker, .matchmaking, .loadingMatch: true
        case .idle, .authenticating, .waitingForPlayers, .failed: false
        }
    }

    /// A stable name for this state, for a test to wait on.
    ///
    /// Published as an accessibility value so `XCUITest` can wait for a
    /// *semantic* state rather than for a spinner to appear or a fixed number
    /// of seconds to pass. Waiting on pixels is how a test ends up asserting
    /// that something looked right while the thing underneath had failed.
    ///
    /// This changes no behaviour: it is a name for what the screen is already
    /// doing, readable by the accessibility system, which is the same
    /// mechanism VoiceOver uses.
    var name: String {
        switch self {
        case .idle: "idle"
        case .authenticating: "authenticating"
        case .openingMatchmaker: "openingMatchmaker"
        case .matchmaking: "matchmaking"
        case .waitingForPlayers: "waitingForPlayers"
        case .loadingMatch: "loadingMatch"
        case .failed(let failure): "failed.\(failure)"
        }
    }

    /// The line to show while this is happening. Never a bare spinner: a
    /// spinner with no sentence is the thing that made this defect invisible.
    var progressKey: String? {
        switch self {
        case .idle, .failed: nil
        case .authenticating: "online.state.authenticating"
        case .openingMatchmaker: "online.state.openingMatchmaker"
        case .matchmaking: "online.state.matchmaking"
        case .waitingForPlayers: "online.state.waitingForPlayers"
        case .loadingMatch: "online.state.loadingMatch"
        }
    }
}

/// Why starting a match did not work, in a form the screen can draw.
///
/// Deliberately a small closed set rather than a string: each case decides its
/// own sentence and whether retrying is worth offering. A raw `GKError`
/// description in the interface is a bug, not a message — it names Apple's
/// internals and tells the player nothing they can act on (§70).
enum OnlineStartFailure: Hashable, Sendable {
    case notSignedIn
    case unavailable
    case cancelled
    case matchmakingFailed
    case couldNotCreate
    case couldNotLoad
    case network

    var messageKey: String {
        switch self {
        case .notSignedIn: "online.fail.notSignedIn"
        case .unavailable: "online.fail.unavailable"
        case .cancelled: "online.fail.cancelled"
        case .matchmakingFailed: "online.fail.matchmakingFailed"
        case .couldNotCreate: "online.fail.couldNotCreate"
        case .couldNotLoad: "online.fail.couldNotLoad"
        case .network: "online.fail.network"
        }
    }

    /// Whether trying the same thing again could plausibly work.
    ///
    /// `notSignedIn` and `unavailable` are excluded on purpose: one is fixed in
    /// Settings and the other cannot be fixed at all, so offering "Try again"
    /// for either would just waste the player's time (§26).
    var isWorthRetrying: Bool {
        switch self {
        case .cancelled, .matchmakingFailed, .couldNotCreate, .couldNotLoad, .network: true
        case .notSignedIn, .unavailable: false
        }
    }

    /// Whether this is worth putting in front of somebody at all.
    ///
    /// Cancelling is not a failure. The player closed the matchmaker
    /// themselves and knows exactly what happened; an error about it would be
    /// the app arguing with them.
    var isWorthShowing: Bool { self != .cancelled }
}

/// What the world told us while starting a match.
enum OnlineStartEvent: Hashable, Sendable {
    case tapped(isAuthenticated: Bool)
    case matchmakerShown
    case matchmakerCancelled
    case matchmakerFailed
    /// A match arrived, with however many of its seats are actually taken.
    case matchArrived(filled: Int, of: Int)
    case matchOpened
    case failed(OnlineStartFailure)
    case dismissed
}

/// How the start flow moves, as a function rather than as assignments spread
/// across a view, a coordinator and a delegate.
///
/// Written this way so the cases that are hard to reach on a device can be
/// tested without GameKit, an account, a second player or a network: a
/// matchmaker cancelled after a match already arrived, a match that comes back
/// half full, a failure landing after the player has closed the screen.
enum OnlineStartFlow {
    static func next(from state: OnlineStartState, on event: OnlineStartEvent) -> OnlineStartState {
        switch event {
        case .tapped(let isAuthenticated):
            // A second tap while something is already running changes nothing.
            // The button is disabled, but a state machine should not depend on
            // a view remembering to disable it.
            guard !state.isBusy else { return state }
            return isAuthenticated ? .openingMatchmaker : .failed(.notSignedIn)

        case .matchmakerShown:
            guard state == .openingMatchmaker else { return state }
            return .matchmaking

        case .matchmakerCancelled:
            // Only meaningful while the matchmaker is what is happening. If a
            // match has already arrived and is loading, a late cancellation
            // callback must not throw away the match.
            switch state {
            case .openingMatchmaker, .matchmaking: return .idle
            default: return state
            }

        case .matchmakerFailed:
            switch state {
            case .openingMatchmaker, .matchmaking: return .failed(.matchmakingFailed)
            default: return state
            }

        case .matchArrived(let filled, let total):
            return arrived(state, filled: filled, of: total)

        case .matchOpened:
            return .idle

        case .failed(let failure):
            return failure.isWorthShowing ? .failed(failure) : .idle

        case .dismissed:
            return .idle
        }
    }

    /// A match turned up, with however many of its seats are taken.
    ///
    /// A turn-based match can arrive before it is full, and that is ordinary
    /// rather than wrong: the match exists, it is in the list, and it starts
    /// when somebody joins. Two cases where the count must **not** be taken at
    /// face value, both of them real things GameKit does.
    private static func arrived(
        _ state: OnlineStartState,
        filled: Int,
        of total: Int
    ) -> OnlineStartState {
        switch state {
        case .idle, .failed:
            // No start flow is running. A turn event for some *other* match —
            // an opponent moving in a game already on screen — must not put
            // this screen into a loading state behind their back.
            return state

        case .loadingMatch:
            // The table was full and the deal is under way. GameKit can
            // re-deliver an older, emptier event afterwards, and taking that
            // at face value would drag a match that is already opening back to
            // "waiting for players".
            //
            // A player genuinely leaving mid-deal is not ignored: the deal
            // itself then fails and arrives as `.failed`.
            return .loadingMatch

        default:
            return filled >= total
                ? .loadingMatch
                : .waitingForPlayers(filled: filled, of: total)
        }
    }
}
