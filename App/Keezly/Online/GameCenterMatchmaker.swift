import Foundation
import GameKit
import UIKit

/// Puts Apple's own matchmaker on screen and reports what comes back.
///
/// Keezly had no matchmaker at all. It called `GKTurnBasedMatch.find(for:)`,
/// which is headless automatch: it shows nothing, offers no way to invite
/// anybody, and hands back a match whose empty seats have no player in them.
/// The old code then refused that match and threw, so the only possible
/// outcome of "New online match" was a two-second spinner and an error nobody
/// ever saw.
///
/// `GKTurnBasedMatchmakerViewController` is the interface Apple intends for
/// this: it shows the player their existing matches, lets them invite somebody
/// or take an automatch, and is the only way an invitation can be sent at all.
///
/// **This object must outlive the screen it presents.** A matchmaker whose
/// delegate has been deallocated reports nothing at all — the player closes
/// Game Center and the app sits there, which is the same invisible failure this
/// whole file exists to remove. It is therefore held by `OnlinePlay` for the
/// lifetime of the session rather than created at the point of use (§8).
@MainActor
final class GameCenterMatchmaker: NSObject {

    /// What came back. One closed set, so no caller can forget a case.
    enum Outcome {
        case matched(GKTurnBasedMatch)
        case cancelled
        case failed(any Error)
        /// The matchmaker could not be put on screen at all. Its own outcome
        /// rather than a generic failure, because it means something different:
        /// nothing was asked of Game Center and nothing is pending.
        case couldNotPresent
    }

    /// The result of **one** attempt to start a match. One-shot by design: a
    /// cancellation and a match must not both count for the same tap.
    private var onOutcome: ((Outcome) -> Void)?
    /// Every turn event, for as long as the app is running. **Not** one-shot,
    /// and that distinction is the whole point of having two of these.
    ///
    /// Routing turn events through `onOutcome` made `waitingForPlayers` a dead
    /// end: the first event cleared the callback, so the second player joining
    /// arrived, found nothing to call, and was dropped in silence. The match
    /// filled up at Apple and Keezly never noticed.
    private var onTurnEvent: ((GKTurnBasedMatch) -> Void)?
    private var isListening = false
    private weak var presented: GKTurnBasedMatchmakerViewController?

    /// Starts listening for turn events, once.
    ///
    /// This is how a turn-based match actually reaches the app on current
    /// GameKit — including one the player accepted from an invitation
    /// elsewhere, and every later turn the opponent takes. Registering twice
    /// would deliver everything twice.
    func beginListening(onTurnEvent: @escaping (GKTurnBasedMatch) -> Void) {
        // The handler is replaced even when already listening, so a second
        // call re-points it rather than leaving a stale closure holding a
        // released object.
        self.onTurnEvent = onTurnEvent
        guard !isListening else { return }
        isListening = true
        GKLocalPlayer.local.register(self)
        OnlineLog.step(.authenticationChecked, "listener registered")
    }

    /// How the other players are found.
    ///
    /// Two genuinely different things, and the player chooses which before
    /// any Apple screen appears. Being dropped into Game Center with no idea
    /// why is most of what made the old flow bewildering.
    enum Kind {
        /// Apple's picker, where somebody is chosen or invited by name.
        case inviteFriends
        /// Game Center looks for anybody. No screen of its own.
        case quickMatch
    }

    /// Shows the matchmaker for a table of this size.
    ///
    /// **Both kinds go through Apple's matchmaker**, and that is a change made
    /// on evidence rather than preference. Quick match used
    /// `GKTurnBasedMatch.find`, which in this environment never pairs two
    /// devices: with two accounts, identical requests, cleaned orphans, both a
    /// simultaneous and a staggered start, and ninety seconds of watching, each
    /// device got its own match at 1/2. It also creates a new match on every
    /// call rather than ever returning a joinable one — it will not reuse even
    /// the calling device's own pending matches, so it was never going to find
    /// anybody else's. Every tap left another empty match behind; twenty-six
    /// accumulated on one account.
    ///
    /// The matchmaker, by contrast, is shown to present correctly on hardware
    /// (`matchmaker.presented onScreen=true`) and is the route Apple supports.
    ///
    /// The two remain separate actions in Keezly's own interface, with their
    /// own wording and their own state — what they share is the substrate.
    ///
    /// The callback is called exactly once, whichever way it ends.
    func present(seats: Int, kind: Kind, onOutcome: @escaping (Outcome) -> Void) {
        self.onOutcome = onOutcome

        let request = Self.makeRequest(seats: seats, kind: kind)

        let controller = GKTurnBasedMatchmakerViewController(matchRequest: request)
        controller.turnBasedMatchmakerDelegate = self
        // **false, deliberately.** With this on, Apple's own match list is what
        // the player sees when they tap "New online match" — every automatch
        // named "Auto-Match-Game", eleven identical rows, a `+` and an `i`.
        // That is a system menu, not Keezly's online screen, and it told a
        // player nothing about which table was which or who they were playing.
        //
        // Keezly draws its own list from `GKTurnBasedMatch.loadMatches()` and
        // groups it by what each match wants (`OnlineLobby`). This controller
        // is now what it should always have been: a step, for choosing or
        // inviting somebody, that hands back and goes away.
        controller.showExistingMatches = false

        guard let top = Self.topViewController() else {
            // Never silent. A presentation that cannot happen is a real fault
            // and the player is told, rather than left with a dead button.
            OnlineLog.gaveUp("no view controller to present the matchmaker from")
            deliver(.couldNotPresent)
            return
        }

        presented = controller
        top.present(controller, animated: true) { [weak controller] in
            // Reported from the completion handler, so the log says the sheet
            // is really on screen rather than that presenting was attempted.
            OnlineLog.step(
                .matchmakerPresented,
                "onScreen=\(controller?.presentingViewController != nil)"
            )
        }
    }

    /// The match request, built the same way every time and logged in full.
    ///
    /// For **quick match** every matchmaking field is left at its default.
    /// That is deliberate and load-bearing: Apple only automatches requests
    /// that agree, and `recipients` in particular switches automatch off for
    /// the seats it names — a request with recipients invites those players
    /// instead of filling the table from the queue. Friend invitations and
    /// automatch therefore cannot share a configuration, and do not.
    ///
    /// `playerGroup` and `playerAttributes` stay 0. Keezly has no use for
    /// them, and a value set on one device but not the other silently prevents
    /// the two requests from ever meeting.
    private static func makeRequest(seats: Int, kind: Kind) -> GKMatchRequest {
        let request = GKMatchRequest()
        request.minPlayers = seats
        request.maxPlayers = seats
        request.defaultNumberOfPlayers = seats

        // Named rather than left implicit, so the log can prove it. GameKit
        // defaults these to 0/nil already; writing them down is what makes
        // "both devices sent the same request" checkable instead of assumed.
        request.playerGroup = 0
        request.playerAttributes = 0
        request.recipients = nil

        OnlineLog.request(
            kind: kind == .quickMatch ? "quickMatch" : "inviteFriends",
            description: "min=\(request.minPlayers) max=\(request.maxPlayers) "
                + "default=\(request.defaultNumberOfPlayers) "
                + "playerGroup=\(request.playerGroup) "
                + "playerAttributes=\(request.playerAttributes) "
                + "recipients=\(request.recipients?.count.description ?? "nil") "
                + "seats=\(seats)"
        )
        return request
    }

    static func describe(_ status: GKTurnBasedMatch.Status) -> String {
        switch status {
        case .open: "open"
        case .ended: "ended"
        case .matching: "matching"
        case .unknown: "unknown"
        @unknown default: "other"
        }
    }

    /// Closes the matchmaker if it is still up.
    ///
    /// **Only when it is genuinely on screen.** `dismiss(animated:)` sent to a
    /// controller that is not presented does not do nothing: UIKit forwards it
    /// to the nearest ancestor that *is* presenting something. Keezly shows the
    /// online screen as a sheet, so that ancestor is the online screen — and
    /// dismissing a matchmaker that never appeared closed the online screen
    /// instead, dropping the player back on the main menu with no explanation.
    func dismiss() {
        Self.close(presented)
        presented = nil
    }

    /// Dismisses a controller only if it is actually presented.
    private static func close(_ controller: UIViewController?) {
        guard let controller, controller.presentingViewController != nil else { return }
        controller.dismiss(animated: true)
    }

    /// Calls back once and then stops, so a late GameKit callback cannot
    /// deliver a second outcome for the same attempt.
    private func deliver(_ outcome: Outcome) {
        guard let onOutcome else { return }
        self.onOutcome = nil
        onOutcome(outcome)
    }

    /// The controller to present from, found through the active scene.
    ///
    /// Deliberately not `UIApplication.shared.windows.first`, which is both
    /// deprecated and wrong in any app that can have more than one scene — on
    /// iPad with two windows open it can return the one the player is not
    /// looking at. This asks for the foreground-active scene's key window and
    /// then walks to whatever is actually on top, because Keezly presents the
    /// online screen as a sheet and a sheet cannot present from underneath.
    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }

        guard let root = scene?.windows.first(where: \.isKeyWindow)?.rootViewController else {
            return nil
        }
        var top = root
        while let next = top.presentedViewController, !next.isBeingDismissed {
            top = next
        }
        return top
    }
}

// MARK: - The matchmaker's own delegate

// GameKit's delegate protocols carry no actor isolation, so a `@MainActor`
// type cannot satisfy them directly under Swift 6. The methods are declared
// `nonisolated` and assume main-actor isolation inside, which is honest rather
// than a suppression: GameKit delivers these on the main thread, and
// `assumeIsolated` traps loudly if that ever stops being true instead of
// quietly racing. Same approach as `OnlinePlay.authenticate`.
extension GameCenterMatchmaker: GKTurnBasedMatchmakerViewControllerDelegate {

    nonisolated func turnBasedMatchmakerViewControllerWasCancelled(
        _ viewController: GKTurnBasedMatchmakerViewController
    ) {
        MainActor.assumeIsolated {
            OnlineLog.step(.matchmakerCancelled)
            presented = nil
            Self.close(viewController)
            deliver(.cancelled)
        }
    }

    nonisolated func turnBasedMatchmakerViewController(
        _ viewController: GKTurnBasedMatchmakerViewController,
        didFailWithError error: any Error
    ) {
        MainActor.assumeIsolated {
            OnlineLog.failure("matchmaker", error)
            OnlineLog.step(.matchmakerFailed)
            presented = nil
            Self.close(viewController)
            deliver(.failed(error))
        }
    }
}

// MARK: - Where a turn-based match actually arrives

extension GameCenterMatchmaker: GKLocalPlayerListener {

    /// A match this player is now in: newly matched, accepted from an
    /// invitation, or simply somebody else's turn arriving.
    ///
    /// This is the delivery point on current GameKit, not a delegate method on
    /// the matchmaker. The old `didFind` callback is long deprecated, and an
    /// integration that waits for it waits forever.
    nonisolated func player(
        _ player: GKPlayer,
        receivedTurnEventFor match: GKTurnBasedMatch,
        didBecomeActive: Bool
    ) {
        // `GKTurnBasedMatch` is not `Sendable`, so the compiler cannot see
        // that this never leaves the thread it arrived on. It does not:
        // GameKit delivers listener callbacks on the main thread, and the
        // `assumeIsolated` below traps rather than races if that is ever untrue.
        nonisolated(unsafe) let match = match
        MainActor.assumeIsolated {
            let filled = match.participants.compactMap(\.player).count
            OnlineLog.step(.matchReceived, "status=\(match.status.rawValue) active=\(didBecomeActive)")
            OnlineLog.participants(filled: filled, of: match.participants.count)

            // Two separate things, and both happen.
            //
            // The attempt that is waiting on an answer gets one, once — that
            // closes the matchmaker and moves the start flow off `matchmaking`.
            if onOutcome != nil {
                dismiss()
                deliver(.matched(match))
            }

            // And every event, always, goes to the standing handler. This is
            // what a second player joining looks like: a turn event for a
            // match Keezly is already waiting on. Dropping it because some
            // earlier callback had been consumed is what left a filled match
            // sitting at Apple with the app still saying "waiting".
            onTurnEvent?(match)
        }
    }

    nonisolated func player(_ player: GKPlayer, matchEnded match: GKTurnBasedMatch) {
        nonisolated(unsafe) let match = match
        MainActor.assumeIsolated {
            OnlineLog.step(.finished, "status=\(match.status.rawValue)")
            // A finished match is a change to the lobby like any other.
            onTurnEvent?(match)
        }
    }

    /// Somebody declined the invitation, or left.
    ///
    /// Handled rather than ignored: a two-player match whose opponent walked
    /// away is never going to fill, and a lobby that still says "looking for
    /// players" about it is lying.
    nonisolated func player(
        _ player: GKPlayer,
        wantsToQuitMatch match: GKTurnBasedMatch
    ) {
        nonisolated(unsafe) let match = match
        MainActor.assumeIsolated {
            OnlineLog.step(.finished, "quit status=\(match.status.rawValue)")
            onTurnEvent?(match)
        }
    }
}
