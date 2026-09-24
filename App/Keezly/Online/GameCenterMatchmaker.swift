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

    private var onOutcome: ((Outcome) -> Void)?
    private var isListening = false
    private weak var presented: GKTurnBasedMatchmakerViewController?

    /// Starts listening for turn events, once.
    ///
    /// This is how a turn-based match actually reaches the app on current
    /// GameKit — including one the player accepted from an invitation
    /// elsewhere, and every later turn the opponent takes. Registering twice
    /// would deliver everything twice.
    func beginListening() {
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
    /// The callback is called exactly once, whichever way it ends.
    func present(seats: Int, kind: Kind, onOutcome: @escaping (Outcome) -> Void) {
        self.onOutcome = onOutcome

        let request = GKMatchRequest()
        request.minPlayers = seats
        request.maxPlayers = seats
        request.defaultNumberOfPlayers = seats
        OnlineLog.step(.requestBuilt, "min=\(seats) max=\(seats) default=\(seats)")

        guard kind == .inviteFriends else {
            // Automatch has no interface of its own: Game Center looks in the
            // background and the match arrives through the listener, possibly
            // minutes later. The screen says so rather than opening an Apple
            // sheet that would only show a spinner.
            Task { await self.findQuietly(request) }
            return
        }

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
        top.present(controller, animated: true) {
            OnlineLog.step(.matchmakerPresented)
        }
    }

    /// Automatch, without a screen.
    ///
    /// `GKTurnBasedMatch.find` **creates** a match rather than only looking for
    /// one, and returns it with its empty seats unfilled. That is not a
    /// failure and is no longer treated as one — the match is real, it belongs
    /// to this player, and it is handed back so Keezly can show it waiting.
    /// Refusing it and throwing is what left eleven orphaned matches at Apple
    /// with nothing on screen to explain them.
    private func findQuietly(_ request: GKMatchRequest) async {
        do {
            let match = try await GKTurnBasedMatch.find(for: request)
            let filled = match.participants.compactMap(\.player).count
            OnlineLog.step(.matchReceived, "automatch status=\(match.status.rawValue)")
            OnlineLog.participants(filled: filled, of: match.participants.count)
            deliver(.matched(match))
        } catch {
            OnlineLog.failure("automatch", error)
            deliver(.failed(error))
        }
    }

    /// Closes the matchmaker if it is still up.
    func dismiss() {
        presented?.dismiss(animated: true)
        presented = nil
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
            viewController.dismiss(animated: true)
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
            viewController.dismiss(animated: true)
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

            // Close the matchmaker if it is still up: the player has what they
            // came for and should be looking at the board, not at Game Center.
            dismiss()
            deliver(.matched(match))
        }
    }

    nonisolated func player(_ player: GKPlayer, matchEnded match: GKTurnBasedMatch) {
        nonisolated(unsafe) let match = match
        MainActor.assumeIsolated {
            OnlineLog.step(.finished, "status=\(match.status.rawValue)")
        }
    }
}
