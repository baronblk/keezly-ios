import Foundation
import KeezlyCore
import Observation
import SwiftUI

/// Walks the board through the events of a move (§39).
///
/// The engine has already decided everything: by the time a `GameEvent` reaches
/// here, `GameState` is final. This type exists only to show *how* the board
/// got there — a pawn visiting each square it passed, a captured piece leaving
/// after the piece that took it arrives.
///
/// Two rules it never breaks:
///
/// - **No animation changes the game.** The presenter owns a separate copy of
///   the pawn positions for drawing and cannot reach `GameState` at all.
/// - **An interrupted animation never leaves the board wrong.** Cancelling,
///   backgrounding or Reduce Motion all end with the board showing exactly the
///   final positions, because the last thing `present` does is assign them.
@MainActor
@Observable
final class BoardPresenter {
    /// How long each kind of step takes. Injectable so tests need not sleep.
    struct Timing: Sendable, Hashable {
        var step: Duration
        var enter: Duration
        var capture: Duration
        var swap: Duration
        var card: Duration
        var home: Duration

        static let standard = Timing(
            step: .milliseconds(150),
            enter: .milliseconds(260),
            capture: .milliseconds(380),
            swap: .milliseconds(460),
            card: .milliseconds(240),
            home: .milliseconds(300)
        )

        /// Reduce Motion, and tests: everything lands at once.
        static let instant = Timing(
            step: .zero, enter: .zero, capture: .zero,
            swap: .zero, card: .zero, home: .zero
        )

        /// Scaled by the animation-speed setting (§59).
        func scaled(by factor: Double) -> Timing {
            guard factor > 0, factor != 1 else { return self }
            func scale(_ duration: Duration) -> Duration {
                .seconds(duration.seconds / factor)
            }
            return Timing(
                step: scale(step), enter: scale(enter), capture: scale(capture),
                swap: scale(swap), card: scale(card), home: scale(home)
            )
        }
    }

    /// The positions the board should draw right now.
    private(set) var displayedPawns: [PawnState]
    /// True while events are being played out.
    private(set) var isPresenting = false
    /// A pawn to emphasise for a beat — one that has just been taken, or has
    /// just reached home.
    private(set) var emphasised: PawnID?

    private var timing: Timing

    /// Called after every position change, in order.
    ///
    /// Exists so a test can assert *which squares a pawn visited* rather than
    /// polling and hoping to catch it mid-flight. Unused in the app.
    var onStep: ((PawnID, BoardPosition) -> Void)?

    init(pawns: [PawnState], timing: Timing = .standard) {
        self.displayedPawns = pawns
        self.timing = timing
    }

    func updateTiming(_ timing: Timing) {
        self.timing = timing
    }

    /// Plays `events`, then guarantees the board shows `finalPawns`.
    ///
    /// Safe to cancel at any point: the `defer` makes the final positions the
    /// last thing that happens either way.
    func present(_ events: [GameEvent], finalPawns: [PawnState]) async {
        isPresenting = true
        defer {
            // Whatever happened — finished, cancelled, or an event we do not
            // animate — the board ends up showing the truth.
            displayedPawns = finalPawns
            emphasised = nil
            isPresenting = false
        }

        for event in Self.presentationOrder(of: events) {
            if Task.isCancelled { return }
            await play(event)
        }
    }

    /// Snaps to a position without animating. Used when a match is restored or
    /// a replay jumps.
    func snap(to pawns: [PawnState]) {
        displayedPawns = pawns
        emphasised = nil
    }

    // MARK: - Ordering

    /// Reorders events for presentation only.
    ///
    /// The engine emits a capture *before* the move that caused it, which is
    /// the right order for a log: the square has to be vacated before the
    /// mover can occupy it. On screen it reads backwards — a piece flies off
    /// before anything hits it. So a capture is swapped behind the move that
    /// caused it.
    ///
    /// This is a presentation decision and touches nothing in the engine.
    static func presentationOrder(of events: [GameEvent]) -> [GameEvent] {
        var ordered: [GameEvent] = []
        var index = 0
        while index < events.count {
            if case .pawnCaptured(_, let capturer, _, _) = events[index],
               index + 1 < events.count,
               Self.pawn(movedBy: events[index + 1]) == capturer {
                ordered.append(events[index + 1])
                ordered.append(events[index])
                index += 2
                continue
            }
            ordered.append(events[index])
            index += 1
        }
        return ordered
    }

    private static func pawn(movedBy event: GameEvent) -> PawnID? {
        switch event {
        case .pawnMoved(let pawn, _, _, _, _), .pawnEntered(let pawn, _):
            pawn
        default:
            nil
        }
    }

    // MARK: - Playing one event

    private func play(_ event: GameEvent) async {
        switch event {
        case .cardPlayed:
            // The hand animates the card itself; this is the beat the board
            // waits while that happens.
            await pause(timing.card)

        case .pawnEntered(let pawn, let position):
            withAnimation(.spring(response: timing.enter.seconds, dampingFraction: 0.68)) {
                move(pawn, to: position)
            }
            await pause(timing.enter)

        case .pawnMoved(let pawn, _, let destination, let path, _):
            await walk(pawn, along: path, to: destination)

        case .pawnsSwapped(let first, let firstFrom, let second, let secondFrom):
            // Both pieces travel at once, which is what a swap looks like.
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: timing.swap.seconds)) {
                move(first, to: secondFrom)
                move(second, to: firstFrom)
            }
            await pause(timing.swap)

        case .pawnCaptured(let pawn, _, _, let returnedTo):
            emphasised = pawn
            withAnimation(.spring(response: timing.capture.seconds, dampingFraction: 0.6)) {
                move(pawn, to: returnedTo)
            }
            await pause(timing.capture)
            emphasised = nil

        case .pawnReachedHome(let pawn, _):
            emphasised = pawn
            await pause(timing.home)
            emphasised = nil

        case .handFolded, .seatResigned, .turnPassed, .dealRoundStarted,
             .dealerChanged, .matchEnded, .seatFinished:
            // Nothing on the board moves for these; the HUD reflects them from
            // the state directly.
            break
        }
    }

    /// Walks a pawn square by square, so a long move reads as a journey rather
    /// than a teleport — which is also how a player checks the engine did what
    /// they expected.
    private func walk(_ pawn: PawnID, along path: [BoardPosition], to destination: BoardPosition) async {
        guard timing.step > .zero, path.count > 1 else {
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: timing.step.seconds)) {
                move(pawn, to: destination)
            }
            await pause(timing.step)
            return
        }

        for square in path {
            if Task.isCancelled { return }
            withAnimation(.linear(duration: timing.step.seconds)) {
                move(pawn, to: square)
            }
            await pause(timing.step)
        }
    }

    private func move(_ pawn: PawnID, to position: BoardPosition) {
        guard let index = displayedPawns.firstIndex(where: { $0.id == pawn }) else { return }
        displayedPawns[index].position = position
        onStep?(pawn, position)
    }

    private func pause(_ duration: Duration) async {
        guard duration > .zero else { return }
        try? await Task.sleep(for: duration)
    }
}

extension Duration {
    /// This type as seconds, for the SwiftUI animation APIs that want a Double.
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
