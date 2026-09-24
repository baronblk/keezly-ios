import KeezlyCore
import SwiftUI

/// An online match, played on the ordinary board.
///
/// Deliberately thin. The board, the hand, the legal moves, the refusals and
/// the animations are all `GameScreen`'s, unchanged — an online match differs
/// from a local one only in who may move, and that is carried by the seat
/// roles (§28). What this adds is the three things that have no local
/// equivalent: the position arriving from elsewhere, a turn leaving the
/// device, and a plain sentence about what the match is waiting for.
struct OnlineGameScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    let run: OnlineMatchRun
    let preferences: Preferences
    var onLeave: () -> Void

    var body: some View {
        GameScreen(
            session: run.session,
            onLeave: onLeave,
            preferences: preferences,
            onSubmitted: { action in await run.submit(action) }
        )
        .safeAreaInset(edge: .top) { banner }
        .task { await run.refresh() }
        .onChange(of: scenePhase) { _, phase in
            // A turn-based match changes while the app is closed — that is the
            // whole shape of it (§27). Coming back to the foreground is the
            // one moment this device can be sure it is out of date.
            guard phase == .active else { return }
            Task { await run.refresh() }
        }
    }

    /// One line, and always one when the match is waiting on something.
    ///
    /// The order matters and is not arbitrary: a problem outranks the result,
    /// the result outranks whose turn it is, and a move in flight outranks
    /// "your turn" — otherwise a player who has just tapped is still told it
    /// is their turn while the move is being sent, which reads as though the
    /// tap was ignored.
    @ViewBuilder
    private var banner: some View {
        if let notice = run.notice {
            Line(text: notice, icon: "exclamationmark.circle", identifier: "online.notice")
        } else if run.isOver {
            Line(
                text: String(localized: run.didWin == true ? "online.wonBanner" : "online.lostBanner"),
                icon: run.didWin == true ? "trophy" : "flag.checkered",
                identifier: "online.result"
            )
        } else if run.isSending {
            Line(text: String(localized: "online.sendingBanner"),
                 icon: "arrow.up.circle", identifier: "online.sending")
        } else if !run.isMyTurn {
            Line(text: String(localized: "online.waitingBanner"), icon: "hourglass", identifier: "online.waiting")
        } else {
            // Said rather than left blank. On a board that looks identical
            // whoever is on turn, silence is not the same as "it is you".
            Line(text: String(localized: "online.yourTurnBanner"),
                 icon: "play.circle", identifier: "online.yourTurn")
        }
    }
}

private struct Line: View {
    let text: String
    let icon: String
    let identifier: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Keezly.Spacing.medium)
            .padding(.vertical, Keezly.Spacing.small)
            .background(.thinMaterial)
            .accessibilityIdentifier(identifier)
    }
}
