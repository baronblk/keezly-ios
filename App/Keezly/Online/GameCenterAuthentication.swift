import Foundation

/// Where this device stands with Game Center.
///
/// Five states, kept apart because they need different answers. "Not signed
/// in" is a thing a player can fix; "not available on this device" is not; and
/// "it went wrong" is neither. Collapsing them into a single boolean is how an
/// app ends up telling somebody to sign in to something their device does not
/// have (§26).
enum GameCenterAuthentication: Hashable, Sendable {
    /// Game Center is not available here at all.
    case unavailable(reason: String)
    /// Available, but nobody is signed in.
    case unauthenticated
    /// Asking.
    case authenticating
    /// Signed in, as this player.
    case authenticated(playerID: String)
    /// The attempt failed. Distinct from being signed out: there is something
    /// to report and something to retry.
    case failed(reason: String)

    var isAuthenticated: Bool {
        if case .authenticated = self { return true }
        return false
    }

    /// Whether asking again could plausibly help.
    var isWorthRetrying: Bool {
        switch self {
        case .unauthenticated, .failed: true
        case .unavailable, .authenticating, .authenticated: false
        }
    }

    /// The player, when there is one.
    var playerID: String? {
        if case .authenticated(let id) = self { return id }
        return nil
    }
}

/// What the world told us about signing in.
enum AuthenticationEvent: Hashable, Sendable {
    case began
    case succeeded(playerID: String)
    case signedOut
    case failed(reason: String)
    case becameUnavailable(reason: String)
}

/// How the state changes, as a function rather than as a set of scattered
/// assignments.
///
/// Written this way so the awkward cases can be tested without GameKit, an
/// account or a network: a sign-in that completes after the player has already
/// signed out, a failure arriving while another attempt is under way, an
/// answer for a device where Game Center is not available at all.
enum GameCenterAuthenticator {
    static func next(
        from state: GameCenterAuthentication,
        on event: AuthenticationEvent
    ) -> GameCenterAuthentication {
        switch event {
        case .becameUnavailable(let reason):
            // Always wins. Nothing else is true if Game Center is not there.
            return .unavailable(reason: reason)

        case .began:
            // A device without Game Center does not start asking.
            if case .unavailable = state { return state }
            return .authenticating

        case .succeeded(let playerID):
            if case .unavailable = state { return state }
            return .authenticated(playerID: playerID)

        case .signedOut:
            if case .unavailable = state { return state }
            return .unauthenticated

        case .failed(let reason):
            if case .unavailable = state { return state }
            // A failure after a successful sign-in is not a sign-out: the
            // player is still signed in, and something else went wrong.
            if case .authenticated = state { return state }
            return .failed(reason: reason)
        }
    }
}
