import Foundation
import GameKit
import KeezlyCore

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
    /// Kept for the match this device is waiting on, so it can be opened when
    /// the table fills — which happens long after the tap that started it.
    private var onOpenWaiting: ((OnlineMatchRun) -> Void)?
    /// What the player asked for when they started the wait. A table that
    /// fills minutes later must use the settings they chose, not today's
    /// default.
    private var waitingPrefersTeams = true
    /// The last thing Game Center said about the match being started, in the
    /// same shape the log uses, so a test reads exactly what a log reader
    /// would.
    private(set) var lastMatchFacts: String?
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
            matchmaker.beginListening { [weak self] match in
                self?.handleTurnEvent(match)
            }
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
        await inventoryMatches()
        isWorking = true
        defer { isWorking = false }
        do {
            matches = try await loadSummaries()
            failure = nil
        } catch {
            failure = Self.readable(error)
        }
    }

    /// Turns Game Center's matches into Keezly's own description of them.
    ///
    /// A match with no Keezly payload yet is **kept**, not dropped. Those are
    /// the ones automatch created and has not filled, and dropping them is why
    /// eleven of them could pile up invisibly while the player was told
    /// nothing: they existed at Apple, they were this player's, and Keezly
    /// pretended they were not there.
    private func loadSummaries() async throws -> [OnlineMatchSummary] {
        let me = GKLocalPlayer.local.gamePlayerID
        // Bound first: `loadMatches()` also has a completion-handler overload,
        // and chaining straight onto it lets the compiler pick that one, whose
        // result is Void.
        let gkMatches: [GKTurnBasedMatch] = try await GKTurnBasedMatch.loadMatches()
        return gkMatches.map { gk in
            // Written out rather than with `flatMap`: `Data` is itself a
            // Collection, so `Data?.flatMap` binds to the *sequence* overload
            // and quietly maps over the bytes.
            var payload: OnlineMatch?
            if let data = gk.matchData, !data.isEmpty {
                payload = try? OnlineMatchEnvelope.load(data)
            }
            let named = gk.participants.compactMap(\.player)
            let mine = gk.participants.first { $0.player?.gamePlayerID == me }

            return OnlineMatchSummary(
                // Falls back to Game Center's own identifier only so the row
                // has something to be identified *by*. It is never displayed.
                id: payload?.matchID ?? gk.matchID ?? UUID().uuidString,
                seatCount: payload?.participants.seatCount ?? gk.participants.count,
                opponents: named
                    .filter { $0.gamePlayerID != me }
                    .map(\.displayName),
                filledSeats: named.count,
                isMyTurn: gk.currentParticipant?.player?.gamePlayerID == me,
                isOver: gk.status == .ended || payload?.state.result != nil,
                // Automatch has not finished filling the table. Not an error
                // and not somebody's turn — its own thing, said as itself.
                hasBoard: payload != nil,
                isWaitingForPlayers: gk.status == .matching || named.count < gk.participants.count,
                isInvitation: mine?.status == .invited,
                // The most recent turn anybody took, or the match's own age
                // if nobody has moved yet. `GKTurnBasedMatch` has no
                // last-activity of its own; its participants do.
                lastActivity: gk.participants.compactMap(\.lastTurnDate).max() ?? gk.creationDate,
                variantName: payload.flatMap { Self.variantName(for: $0) },
                isTeamMatch: payload?.state.configuration.teamMode == .teamsOfTwo
            )
        }
    }

    /// The facts a physical test needs, in one readable line.
    ///
    /// The app's diagnostics go to the device console; `xcodebuild` captures
    /// its own output and not that. Rather than stitch two channels together
    /// afterwards, the handful of facts that decide the gate are published
    /// where a test can read them directly.
    ///
    /// Seat counts, a match handle and a checksum. No account, no name.
    var probeSummary: String {
        var parts = ["auth=\(authentication.isAuthenticated)"]
        parts.append("matches=\(matches.count)")
        // The breakdown, not just the total. Twice now a cleanup has reported
        // "nothing to clean" against twenty-six matches and the total alone
        // could not say which assumption was wrong.
        parts.append("abandoned=\(matches.filter(\.isAbandonedSearch).count)")
        parts.append("boards=\(matches.filter(\.hasBoard).count)")
        parts.append("waiting=\(matches.filter(\.isWaitingForPlayers).count)")
        parts.append("solo=\(matches.filter { $0.filledSeats <= 1 }.count)")
        if let waiting = lastMatchFacts {
            parts.append(waiting)
        }
        return parts.joined(separator: " ")
    }

    /// The board's checksum, for comparing two devices.
    ///
    /// `dealt` appears exactly once per match across both devices; `received`
    /// on the others. Two `dealt` lines for one match would be a double deal,
    /// and two different checksums at the same revision would mean the two
    /// devices are playing different games.
    private static func logBoard(role: String, _ match: OnlineMatch) {
        guard let checksum = try? GameStateCoding.checksum(of: match.state) else { return }
        OnlineLog.board(
            role: role,
            matchID: match.matchID,
            revision: match.state.revision,
            checksum: checksum,
            seats: match.state.configuration.seatCount
        )
    }

    /// Removes this device's own abandoned automatch attempts.
    ///
    /// Only matches that are **unambiguously nobody else's**: no second player
    /// has joined, and no board was ever dealt. Those can only be attempts this
    /// device made and walked away from — every one of them was created by a
    /// tap that then threw the match away, before that defect was fixed.
    ///
    /// Nothing with another player in it is touched, whatever its state.
    ///
    /// Returns how many were removed, so a caller can say so rather than
    /// guess.
    @discardableResult
    func removeOwnAbandonedMatches() async -> Int {
        guard Self.isEnabled else { return 0 }
        var removed = 0
        do {
            let all: [GKTurnBasedMatch] = try await GKTurnBasedMatch.loadMatches()
            OnlineLog.step(.openRequested, "cleanup: \(all.count) match(es) to consider")
            for gk in all {
                let others = gk.participants.compactMap(\.player).count
                let dealt = !(gk.matchData?.isEmpty ?? true)
                guard others <= 1, !dealt else { continue }
                do {
                    try await gk.remove()
                    removed += 1
                } catch {
                    // One that will not go is not worth stopping for; the rest
                    // still should. Reported so it is not silent.
                    OnlineLog.failure("cleanup.remove", error)
                }
            }
            OnlineLog.step(.finished, "cleanup removed \(removed)")
            await refresh()
        } catch {
            OnlineLog.failure("cleanup", error)
        }
        return removed
    }

    /// Abandons a match this device is still waiting on.
    ///
    /// Exists because the old start path left orphaned matches at Apple with
    /// no way to be rid of them: eleven of them accumulated on one account,
    /// invisible to the app and untouchable from it.
    ///
    /// **Only matches with nobody else in them.** A match somebody has already
    /// joined is a game with another person in it, and walking out of one is a
    /// forfeit — a decision for the player inside the match, not a tidy-up
    /// button in a lobby. Those are left alone.
    ///
    /// What Apple allows depends on the match's state, so both paths are
    /// taken: an unstarted match is removed outright, and one that has begun
    /// is quit in turn with a loss for this seat, which is the only honest
    /// outcome for leaving.
    func abandonWaitingMatch(_ summary: OnlineMatchSummary) async {
        guard Self.isEnabled else { return }
        guard summary.isWaitingForPlayers, summary.filledSeats <= 1 else {
            OnlineLog.gaveUp("refused to abandon a match with other players in it")
            return
        }

        do {
            let all: [GKTurnBasedMatch] = try await GKTurnBasedMatch.loadMatches()
            guard let gk = all.first(where: { Self.identifies($0, summary) }) else { return }

            if gk.status == .matching || (gk.matchData?.isEmpty ?? true) {
                // Never dealt and nobody else in it. Removing leaves nothing
                // behind for anybody.
                try await gk.remove()
                OnlineLog.step(.finished, "abandoned an unstarted match")
            } else {
                try await gk.participantQuitOutOfTurn(with: .quit)
                OnlineLog.step(.finished, "quit a waiting match")
            }
            await refresh()
        } catch {
            OnlineLog.failure("abandon", error)
            failure = Self.readable(error)
        }
    }

    /// Whether this Game Center match is the one a summary describes.
    ///
    /// Matched on the Keezly id when there is a payload, and on Apple's own id
    /// when there is not — which is exactly the case for the waiting matches
    /// this is used for.
    private static func identifies(_ gk: GKTurnBasedMatch, _ summary: OnlineMatchSummary) -> Bool {
        if gk.matchID == summary.id { return true }
        guard let data = gk.matchData, !data.isEmpty,
              let match = try? OnlineMatchEnvelope.load(data) else { return false }
        return match.matchID == summary.id
    }

    /// Writes one log line per Game Center match this account holds.
    ///
    /// Read-only, and it exists because the old start path left orphaned
    /// matches at Apple that nothing in the app ever showed. Nothing is
    /// deleted here and nothing ever will be by this method: leaving somebody
    /// else's match is a decision, not a tidy-up.
    func inventoryMatches() async {
        guard Self.isEnabled else { return }
        let me = GKLocalPlayer.local.gamePlayerID
        do {
            let all: [GKTurnBasedMatch] = try await GKTurnBasedMatch.loadMatches()
            OnlineLog.step(.openRequested, "inventory of \(all.count) match(es)")
            for (index, gk) in all.enumerated() {
                OnlineLog.inventory(OnlineLog.MatchFacts(
                    index: index,
                    matchID: gk.matchID ?? "-",
                    status: Self.describe(gk.status),
                    participants: gk.participants.count,
                    filled: gk.participants.compactMap(\.player).count,
                    isMyTurn: gk.currentParticipant?.player?.gamePlayerID == me,
                    created: gk.creationDate,
                    payloadBytes: gk.matchData?.count ?? 0
                ))
            }
        } catch {
            OnlineLog.failure("inventory", error)
        }
    }

    private static func describe(_ status: GKTurnBasedMatch.Status) -> String {
        switch status {
        case .open: "open"
        case .ended: "ended"
        case .matching: "matching"
        case .unknown: "unknown"
        @unknown default: "other"
        }
    }

    /// The rule preset's name, for the second line of a row.
    private static func variantName(for match: OnlineMatch) -> String? {
        Rulebook.name(of: match.state.configuration.ruleSet.preset)
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
    func startMatch(
        seats: Int,
        teams: Bool,
        kind: GameCenterMatchmaker.Kind,
        onOpen: @escaping (OnlineMatchRun) -> Void
    ) {
        OnlineLog.step(.startTapped)
        OnlineLog.table(seats: seats, teams: teams)
        OnlineLog.step(
            .authenticationChecked,
            "enabled=\(Self.isEnabled) authenticated=\(authentication.isAuthenticated)"
        )

        onOpenWaiting = onOpen
        waitingPrefersTeams = teams
        apply(.tapped(isAuthenticated: Self.isEnabled && authentication.isAuthenticated))
        guard startState == .openingMatchmaker else {
            OnlineLog.gaveUp("not signed in, or Game Center disabled in this process")
            return
        }

        matchmaker.present(seats: seats, kind: kind) { [weak self] outcome in
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
                // Recorded the moment the match arrives, not only on a later
                // turn event. Without this the probe never carries a match id
                // and two devices cannot be told apart from one.
                let filled = gkMatch.participants.compactMap(\.player).count
                self.lastMatchFacts = "match=\(gkMatch.matchID ?? "-") "
                    + "filled=\(filled)/\(gkMatch.participants.count)"
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

    /// A match changed at Apple: somebody joined, moved, quit or finished.
    ///
    /// **Everything is read from the match the event carried**, never from a
    /// participant array kept from an earlier one. A cached array is exactly
    /// how a table that has filled up still looks half empty.
    ///
    /// This is what makes `waitingForPlayers` a step rather than a dead end:
    /// the second player joining is a turn event for a match Keezly is already
    /// waiting on, and it is this method that notices.
    private func handleTurnEvent(_ gkMatch: GKTurnBasedMatch) {
        let filled = gkMatch.participants.compactMap(\.player).count
        let total = gkMatch.participants.count
        OnlineLog.participants(filled: filled, of: total)
        lastMatchFacts = "match=\(gkMatch.matchID ?? "-") filled=\(filled)/\(total)"

        // The lobby is refreshed whatever the event was, so a row's state is
        // never older than the last thing Game Center said.
        Task { await refresh() }

        OnlineLog.accounts(
            authenticated: authentication.isAuthenticated,
            filled: filled,
            of: total
        )

        guard case .waitingForPlayers = startState else { return }
        apply(.matchArrived(filled: filled, of: total))
        guard case .loadingMatch = startState else {
            OnlineLog.step(.matchReceived, "still waiting: \(filled) of \(total)")
            return
        }

        OnlineLog.step(.matchReceived, "table filled: \(filled) of \(total)")
        Task { await openWhenFull(gkMatch) }
    }

    /// Deals a match that has just filled up, and opens it.
    ///
    /// Only the participant whose turn it is deals. That is not a tie-break
    /// invented here — it is GameKit's own rule about who may write the match
    /// data, and it means exactly one device deals however many join at once.
    private func openWhenFull(_ gkMatch: GKTurnBasedMatch) async {
        guard let client, let onOpenWaiting else { return }
        let me = GKLocalPlayer.local.gamePlayerID

        do {
            if let data = gkMatch.matchData, !data.isEmpty {
                // Somebody already dealt. Take their board, do not make one.
                let existing = try await client.load(matchID: OnlineMatchEnvelope.load(data).matchID)
                Self.logBoard(role: "received", existing)
                let run = try run(existing, client: client)
                apply(.matchOpened)
                onOpenWaiting(run)
                return
            }

            guard gkMatch.currentParticipant?.player?.gamePlayerID == me else {
                // Not ours to deal. The dealer will end their turn to us and
                // that arrives as another event.
                OnlineLog.step(.matchReceived, "full, waiting for the dealer")
                apply(.matchArrived(filled: 1, of: gkMatch.participants.count))
                return
            }

            let players = gkMatch.participants.compactMap { $0.player?.gamePlayerID }
            let configuration = GameConfiguration(
                seatCount: players.count,
                teamMode: TableConfiguration.allowsTeams(seatCount: players.count) && waitingPrefersTeams
                    ? .teamsOfTwo
                    : .freeForAll
            )
            let match = try await client.create(
                configuration: configuration,
                seed: SeededGenerator.systemSeeded().state,
                participants: try ParticipantMapping(seatOrder: players)
            )
            OnlineLog.step(.matchCreated, "seats=\(configuration.seatCount)")
            Self.logBoard(role: "dealt", match)
            let run = try run(match, client: client)
            OnlineLog.step(.runOpened)
            apply(.matchOpened)
            onOpenWaiting(run)
        } catch {
            OnlineLog.failure("openWhenFull", error)
            apply(.failed(Self.failure(for: error)))
        }
        await refresh()
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
