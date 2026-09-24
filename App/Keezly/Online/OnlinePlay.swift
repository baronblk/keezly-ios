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

    /// Where the start flow stands. Drawn by the screen, so a player is never
    /// looking at an unexplained spinner (`OnlineStartFlow`).
    private(set) var startState: OnlineStartState = .idle

    private let transport = GameCenterTransport()
    /// Held for the session, not made at the point of use. A matchmaker whose
    /// delegate has been deallocated reports nothing at all, and the player is
    /// left with a screen that never changes (§8).
    private let matchmaker = GameCenterMatchmaker()
    /// Where a finished online match's achievements go, and what stops the
    /// same match sending them twice. Held here rather than made per match, so
    /// every run this object hands out shares one ledger (`AchievementLedger`).
    private let achievements: any AchievementReporting = GameCenterAchievements()
    private let ledger: any AchievementLedger = StoredAchievementLedger()

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
        // Listening has to start once the player is known, and only then: a
        // listener registered while signed out never receives anything, and
        // this is where a turn-based match arrives from.
        if authentication.isAuthenticated {
            matchmaker.beginListening()
        }
    }

    /// The one place the start flow moves.
    private func apply(_ event: OnlineStartEvent) {
        let before = startState
        startState = OnlineStartFlow.next(from: startState, on: event)
        if before != startState {
            OnlineLog.step(.startTapped, "state \(before) -> \(startState)")
        }
    }

    /// Puts the flow back to idle — closing the screen, or dismissing an error.
    func resetStart() {
        matchmaker.dismiss()
        apply(.dismissed)
    }

    /// Turns whatever GameKit handed back into one of the failures the screen
    /// knows how to draw. A raw `GKError` is never shown to a player (§70).
    static func failure(for error: any Error) -> OnlineStartFailure {
        if let transport = error as? MatchTransportError {
            switch transport {
            case .unavailable: return .unavailable
            default: return .couldNotCreate
            }
        }
        switch GKError.Code(rawValue: (error as NSError).code) {
        case .notAuthenticated: return .notSignedIn
        case .gameUnrecognized, .notSupported: return .unavailable
        case .cancelled: return .cancelled
        case .communicationsFailure, .unknown: return .network
        default: return .matchmakingFailed
        }
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

    /// Starts a match through Apple's own matchmaker.
    ///
    /// **Not** `GKTurnBasedMatch.find`, which is what this used to call. That
    /// is headless automatch: it shows the player nothing, gives them no way to
    /// invite anybody, and hands back a match whose empty seats have no player
    /// in them. The old code then refused that match and threw, and the throw
    /// was discarded by its caller — so the only possible outcome of tapping
    /// the button was a two-second spinner and silence.
    ///
    /// Every way this can end now moves `startState`, and every one of those
    /// states has a sentence attached. Nothing returns quietly to idle.
    func startMatch(seats: Int, teams: Bool, onOpen: @escaping (OnlineMatchRun) -> Void) {
        OnlineLog.step(.startTapped)
        OnlineLog.table(seats: seats, teams: teams)
        OnlineLog.step(
            .authenticationChecked,
            "enabled=\(Self.isEnabled) authenticated=\(authentication.isAuthenticated)"
        )

        apply(.tapped(isAuthenticated: Self.isEnabled && authentication.isAuthenticated))
        guard startState == .openingMatchmaker else {
            OnlineLog.gaveUp("not signed in, or Game Center disabled in this process")
            return
        }

        matchmaker.present(seats: seats) { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .cancelled:
                self.apply(.matchmakerCancelled)
            case .failed(let error):
                OnlineLog.failure("matchmaker", error)
                self.apply(.failed(Self.failure(for: error)))
            case .couldNotPresent:
                self.apply(.failed(.matchmakingFailed))
            case .matched(let gkMatch):
                Task { await self.adopt(gkMatch, seats: seats, teams: teams, onOpen: onOpen) }
            }
        }
        apply(.matchmakerShown)
    }

    /// Turns a Game Center match into a Keezly one, once it is full.
    ///
    /// A turn-based match can exist before it is full — Game Center fills the
    /// empty seats as people accept — and Keezly cannot deal into one, because
    /// a seat with nobody in it cannot be mapped and a board dealt now would
    /// have to be re-dealt. That wait is **not a failure**, and is no longer
    /// reported as one: the match exists, it is in the list, and it opens by
    /// itself when somebody joins, because the listener delivers that too.
    private func adopt(
        _ gkMatch: GKTurnBasedMatch,
        seats: Int,
        teams: Bool,
        onOpen: @escaping (OnlineMatchRun) -> Void
    ) async {
        let players = gkMatch.participants.compactMap { $0.player?.gamePlayerID }
        apply(.matchArrived(filled: players.count, of: gkMatch.participants.count))

        guard case .loadingMatch = startState else {
            // Waiting for players. The match is real and will come back
            // through the listener; nothing more to do and nothing to report.
            await refresh()
            return
        }
        guard let client else {
            apply(.failed(.notSignedIn))
            return
        }

        do {
            // An existing match already carries a board. Only a brand-new one
            // is dealt, and only once — dealing again would replace a match in
            // progress with a fresh position.
            let run: OnlineMatchRun
            if let data = gkMatch.matchData, !data.isEmpty {
                let existing = try await client.load(matchID: OnlineMatchEnvelope.load(data).matchID)
                run = try self.run(existing, client: client)
            } else {
                // Die Teamregel kommt aus `TableConfiguration` und wird hier
                // nicht noch einmal formuliert. Eine zweite Fassung war genau
                // der Defekt hinter ISS-021: der Online-Bildschirm prüfte
                // `seats % 2 == 0`, behielt `teams = true` beim Wechsel auf
                // drei oder fünf Sitze, und `GameConfiguration(seatCount: 3,
                // teamMode: .teamsOfTwo)` brach mit einer precondition.
                let configuration = GameConfiguration(
                    seatCount: seats,
                    teamMode: TableConfiguration.allowsTeams(seatCount: seats) && teams
                        ? .teamsOfTwo
                        : .freeForAll
                )
                let mapping = try ParticipantMapping(seatOrder: players)
                let match = try await client.create(
                    configuration: configuration,
                    seed: SeededGenerator.systemSeeded().state,
                    participants: mapping
                )
                OnlineLog.step(.matchCreated, "seats=\(configuration.seatCount)")
                run = try self.run(match, client: client)
            }
            OnlineLog.step(.runOpened)
            apply(.matchOpened)
            onOpen(run)
            await refresh()
        } catch {
            OnlineLog.failure("adopt", error)
            apply(.failed(Self.failure(for: error)))
        }
    }

    /// Records that opening an existing match went wrong, so the screen can
    /// say so. Opening used to be `try?`, which discarded the reason.
    func noteOpenFailure(_ error: any Error) {
        // Always `couldNotLoad`: whatever the underlying reason, what the
        // player asked for was to open a match that is already theirs, and
        // that is the sentence that fits. The real domain and code go to the log.
        apply(.failed(.couldNotLoad))
    }

    func open(_ matchID: String) async throws -> OnlineMatchRun {
        guard Self.isEnabled, let client else {
            throw MatchTransportError.unavailable(reason: "not signed in")
        }
        let match = try await client.load(matchID: matchID)
        return try run(match, client: client)
    }

    /// The one place a run is built, so no path can be the one that forgets
    /// the reporter. That is exactly how the achievements came to be
    /// registered with Apple and never reported by anything.
    private func run(_ match: OnlineMatch, client: OnlineMatchClient) throws -> OnlineMatchRun {
        try OnlineMatchRun(
            match: match,
            client: client,
            me: client.participantID,
            achievements: achievements,
            ledger: ledger
        )
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
