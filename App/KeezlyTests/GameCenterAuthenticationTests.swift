import Foundation
@testable import Keezly
import Testing

/// §26 — signing in to Game Center, as a state machine rather than a boolean.
///
/// Written as a function so the awkward orderings can be tested without an
/// account, a network or GameKit: an answer arriving after the player signed
/// out, a failure landing on an already-signed-in device, and a device where
/// Game Center does not exist at all.
@Suite("Game Center authentication")
struct GameCenterAuthenticationTests {

    private func advance(
        _ state: GameCenterAuthentication,
        _ events: [AuthenticationEvent]
    ) -> GameCenterAuthentication {
        events.reduce(state) { GameCenterAuthenticator.next(from: $0, on: $1) }
    }

    @Test("the ordinary path")
    func theHappyPath() {
        let signedIn = advance(.unauthenticated, [.began, .succeeded(playerID: "G:123")])
        #expect(signedIn == .authenticated(playerID: "G:123"))
        #expect(signedIn.isAuthenticated)
        #expect(signedIn.playerID == "G:123")
    }

    @Test("a device without Game Center stays that way whatever happens")
    func unavailableIsFinal() {
        let unavailable = GameCenterAuthentication.unavailable(reason: "restricted")
        for event in [
            AuthenticationEvent.began,
            .succeeded(playerID: "G:1"),
            .signedOut,
            .failed(reason: "network"),
        ] {
            #expect(GameCenterAuthenticator.next(from: unavailable, on: event) == unavailable)
        }
    }

    @Test("becoming unavailable overrides anything else")
    func becomingUnavailableWins() {
        let after = advance(.authenticated(playerID: "G:1"), [.becameUnavailable(reason: "restricted")])
        #expect(after == .unavailable(reason: "restricted"))
        #expect(!after.isAuthenticated)
    }

    @Test("a failure after signing in is not a sign-out")
    func failureDoesNotSignThePlayerOut() {
        // Something else went wrong — a request, a network. The player is
        // still signed in, and telling them otherwise would send them off to
        // fix a problem they do not have.
        let after = advance(.authenticated(playerID: "G:1"), [.failed(reason: "timed out")])
        #expect(after == .authenticated(playerID: "G:1"))
    }

    @Test("signing out from a signed-in state is just signed out")
    func signOutIsClean() {
        #expect(advance(.authenticated(playerID: "G:1"), [.signedOut]) == .unauthenticated)
    }

    @Test("a late answer to an abandoned attempt still signs the player in")
    func lateSuccessIsHonoured() {
        // The attempt was given up on and the answer arrived anyway. It is
        // still true, so it is still taken.
        let after = advance(.unauthenticated, [.began, .failed(reason: "slow"), .succeeded(playerID: "G:7")])
        #expect(after == .authenticated(playerID: "G:7"))
    }

    @Test("only some states are worth asking again from")
    func retryIsOfferedWhereItCouldHelp() {
        #expect(GameCenterAuthentication.unauthenticated.isWorthRetrying)
        #expect(GameCenterAuthentication.failed(reason: "x").isWorthRetrying)
        #expect(!GameCenterAuthentication.authenticating.isWorthRetrying)
        #expect(!GameCenterAuthentication.authenticated(playerID: "G:1").isWorthRetrying)
        #expect(!GameCenterAuthentication.unavailable(reason: "x").isWorthRetrying)
    }

    @Test("a local match needs none of this")
    func localPlayIsIndependent() {
        // Not a test of the state machine so much as of the shape of the app:
        // a table is set up and played without Game Center being consulted at
        // all. If this ever needs an authentication state to compile, local
        // play has acquired a dependency it must not have (§26).
        var table = TableConfiguration()
        table.seatCount = 4
        #expect(table.roles.count == 4)
        #expect(table.gameConfiguration.seatCount == 4)
    }
}
