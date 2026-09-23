import Foundation
import GameKit
import KeezlyCore

/// One entry in the list of online matches.
///
/// Built from what Game Center already holds, so the list can be drawn without
/// opening a match. The Keezly identifier comes out of the payload, because
/// Game Center's own identifier is not the one the engine knows (§28).
struct OnlineMatchSummary: Identifiable, Sendable {
    let id: String
    let seatCount: Int
    let isMyTurn: Bool
    let isOver: Bool
    /// The other players, by whatever name Game Center gives them.
    let opponents: [String]
    let lastActivity: Date

    var statusKey: String {
        if isOver { return "online.status.finished" }
        return isMyTurn ? "online.status.yours" : "online.status.waiting"
    }
}

/// Game Center, for the screens that offer online play.
///
/// Owns three things and no more: whether the player is signed in, what
/// matches they are in, and how to start one. Everything about the *rules* of
/// an online match is in `KeezlyCore` behind `OnlineMatchClient`, which this
/// only calls (§28).
@MainActor
@Observable
final class OnlinePlay {
    private(set) var authentication: GameCenterAuthentication = .unauthenticated
    private(set) var matches: [OnlineMatchSummary] = []
    private(set) var isWorking = false
    /// The last thing that went wrong, in words a player can act on.
    private(set) var failure: String?

    private let transport = GameCenterTransport()

    /// Whether this process may talk to Game Center at all.
    ///
    /// A test or screenshot run must not: authentication puts a system sheet
    /// over whatever is on screen, which would fail the run and, in a
    /// screenshot run, ship the sheet to the App Store.
    static var isEnabled: Bool { GameCenterAchievements.isEnabled }

    var client: OnlineMatchClient? {
        guard let id = authentication.playerID else { return nil }
        return OnlineMatchClient(participantID: id, transport: transport)
    }

    // MARK: - Signing in

    /// Starts Apple's sign-in, and keeps the state machine in step with it.
    ///
    /// The handler is set once and then called by GameKit whenever the
    /// account changes — including a sign-out long after launch, which is why
    /// the state is updated from inside it rather than once at the end.
    func authenticate() {
        guard Self.isEnabled else { return }
        guard !authentication.isAuthenticated else { return }

        apply(.began)
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            guard let self else { return }
            MainActor.assumeIsolated {
                if let viewController {
                    Self.present(viewController)
                    return
                }
                if GKLocalPlayer.local.isAuthenticated {
                    self.apply(.succeeded(playerID: GKLocalPlayer.local.gamePlayerID))
                } else if let error {
                    self.apply(Self.event(for: error))
                } else {
                    self.apply(.signedOut)
                }
            }
        }
    }

    /// Distinguishes "you are not signed in" from "this device cannot".
    ///
    /// Collapsing them loses the only thing a player can act on: one is fixed
    /// in Settings, the other cannot be fixed at all (§26).
    private static func event(for error: any Error) -> AuthenticationEvent {
        let code = (error as NSError).code
        if code == GKError.Code.gameUnrecognized.rawValue
            || code == GKError.Code.notSupported.rawValue {
            return .becameUnavailable(reason: error.localizedDescription)
        }
        if code == GKError.Code.cancelled.rawValue {
            return .signedOut
        }
        return .failed(reason: error.localizedDescription)
    }

    private func apply(_ event: AuthenticationEvent) {
        authentication = GameCenterAuthenticator.next(from: authentication, on: event)
    }

    // MARK: - The list

    func refresh() async {
        guard Self.isEnabled, authentication.isAuthenticated else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            matches = try await loadSummaries()
            failure = nil
        } catch {
            failure = Self.readable(error)
        }
    }

    private func loadSummaries() async throws -> [OnlineMatchSummary] {
        let me = GKLocalPlayer.local.gamePlayerID
        return try await GKTurnBasedMatch.loadMatches().compactMap { gk in
            guard let data = gk.matchData, !data.isEmpty,
                  let match = try? OnlineMatchEnvelope.load(data)
            else { return nil }
            return OnlineMatchSummary(
                id: match.matchID,
                seatCount: match.participants.seatCount,
                isMyTurn: gk.currentParticipant?.player?.gamePlayerID == me,
                isOver: match.state.result != nil,
                opponents: gk.participants
                    .compactMap(\.player)
                    .filter { $0.gamePlayerID != me }
                    .map(\.displayName),
                lastActivity: gk.creationDate
            )
        }
    }

    // MARK: - Starting and opening

    /// Starts a match against whoever Game Center finds.
    ///
    /// Seats are assigned in the order Game Center returns participants, which
    /// is the only order every device agrees on — deriving it from anything
    /// local would give two devices two different boards (§28).
    func startMatch(seats: Int, teams: Bool) async throws -> OnlineMatchRun {
        guard Self.isEnabled, let client else {
            throw MatchTransportError.unavailable(reason: "not signed in")
        }
        isWorking = true
        defer { isWorking = false }

        // Die Teamregel kommt aus `TableConfiguration` und wird hier nicht
        // noch einmal formuliert. Eine zweite Fassung war genau der Defekt:
        // der Online-Bildschirm prüfte `seats % 2 == 0`, behielt `teams = true`
        // beim Wechsel auf drei oder fünf Sitze, und
        // `GameConfiguration(seatCount: 3, teamMode: .teamsOfTwo)` brach mit
        // einer precondition — die App stürzte beim Tippen auf „Neue
        // Onlinepartie" ab, noch bevor GameKit gerufen wurde.
        //
        // `allowsTeams` ist ausserdem strenger als „gerade": bei zwei Sitzen
        // stünden beide Spieler auf derselben Seite.
        let configuration = GameConfiguration(
            seatCount: seats,
            teamMode: TableConfiguration.allowsTeams(seatCount: seats) && teams
                ? .teamsOfTwo
                : .freeForAll
        )
        let participants = try await transport.matchmake(seats: seats)
        let mapping = try ParticipantMapping(seatOrder: participants)
        let match = try await client.create(
            configuration: configuration,
            seed: SeededGenerator.systemSeeded().state,
            participants: mapping
        )
        return try OnlineMatchRun(match: match, client: client, me: client.participantID)
    }

    func open(_ matchID: String) async throws -> OnlineMatchRun {
        guard Self.isEnabled, let client else {
            throw MatchTransportError.unavailable(reason: "not signed in")
        }
        let match = try await client.load(matchID: matchID)
        return try OnlineMatchRun(match: match, client: client, me: client.participantID)
    }

    // MARK: - Words a player can act on

    /// Turns whatever went wrong into something worth reading.
    ///
    /// A raw `GKError` in the interface is a bug, not a message: it names
    /// Apple's internals and tells the player nothing they can do (§70).
    static func readable(_ error: any Error) -> String {
        if let transport = error as? MatchTransportError {
            return transport.errorDescription ?? String(localized: "online.error.generic")
        }
        let code = (error as NSError).code
        switch GKError.Code(rawValue: code) {
        case .notAuthenticated:
            return String(localized: "online.error.signedOut")
        case .communicationsFailure, .unknown:
            return String(localized: "online.error.network")
        case .cancelled:
            return String(localized: "online.error.cancelled")
        case .matchNotConnected, .invalidPlayer:
            return String(localized: "online.error.match")
        default:
            return String(localized: "online.error.generic")
        }
    }

    private static func present(_ viewController: UIViewController) {
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
            let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(viewController, animated: true)
    }
}
