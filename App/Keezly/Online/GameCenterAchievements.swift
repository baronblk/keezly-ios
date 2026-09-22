import Foundation
import GameKit
import KeezlyCore

/// Reports finished achievements to Game Center.
///
/// `Achievement.unlocked(in:for:)` works out *what* was earned by replaying a
/// finished match's events, and is tested without a device. This file is the
/// other half — the only thing in Keezly that tells Apple about it — and it is
/// deliberately thin, because everything worth getting right is on the other
/// side of that boundary (§28).
///
/// It exists because the ten achievements were registered with App Store
/// Connect while nothing in the app ever reported one. Registered and earnable
/// are not the same thing, and only one of them is visible to a player.
protocol AchievementReporting: Sendable {
    /// Starts whatever sign-in the channel needs. Safe to call more than once.
    @MainActor func start()
    /// Reports a set of achievements as fully earned.
    @MainActor func report(_ achievements: Set<Achievement>)
}

/// Game Center, through `GKAchievement`.
///
/// Every achievement Keezly has is a thing you either did or did not do, so
/// each is reported at 100% in one call; there is no progress to accumulate
/// and therefore no tally on disk that could drift out of step with the
/// matches actually played.
///
/// Reporting an achievement the player already has is not an error and not a
/// duplicate banner — Game Center keeps the first completion date and ignores
/// the rest — so nothing here needs to remember what it has already sent.
@MainActor
struct GameCenterAchievements: AchievementReporting {
    /// Whether this process should talk to Game Center at all.
    ///
    /// A test or screenshot run must not: authentication can put a system
    /// sheet over the board, which would fail whatever the run was actually
    /// checking and, in a screenshot run, ship the sheet to the App Store.
    static var isEnabled: Bool { !ScreenshotMode.isActive && !ScreenshotMode.isRunningTests }

    func start() {
        guard Self.isEnabled, !GKLocalPlayer.local.isAuthenticated else { return }

        GKLocalPlayer.local.authenticateHandler = { viewController, _ in
            // An error here is ordinary. Somebody with no Game Center account,
            // or a device where it is turned off, has simply chosen not to use
            // it — the game is unaffected and says nothing about it.
            guard let viewController else { return }
            Self.present(viewController)
        }
    }

    func report(_ achievements: Set<Achievement>) {
        guard Self.isEnabled, !achievements.isEmpty, GKLocalPlayer.local.isAuthenticated else { return }

        let reports = achievements.map { achievement -> GKAchievement in
            let report = GKAchievement(identifier: achievement.gameCenterID)
            report.percentComplete = 100
            report.showsCompletionBanner = true
            return report
        }

        GKAchievement.report(reports) { _ in
            // Nothing to do and nothing to say. An achievement that did not
            // reach Apple is not worth interrupting a player who has just
            // finished a match, and the next win reports the same set again.
        }
    }

    /// Puts Apple's sign-in in front of whatever is on screen.
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
