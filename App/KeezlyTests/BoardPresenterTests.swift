import Foundation
@testable import Keezly
import KeezlyCore
import Testing

/// §39, §63 — the animation pipeline shows how the board changed, and can
/// never change it.
@Suite("Board presenter")
@MainActor
struct BoardPresenterTests {
    static func startingPawns(seatCount: Int = 4) -> [PawnState] {
        GameState.newMatch(configuration: .standard(seatCount: seatCount), seed: 1).pawns
    }

    // MARK: - It ends where the engine says

    @Test("the board ends on the engine's positions, whatever was animated")
    func endsOnTheFinalPositions() async {
        let pawns = Self.startingPawns()
        let presenter = BoardPresenter(pawns: pawns, timing: .instant)

        var final = pawns
        final[0].position = .track(index: 7)
        final[5].position = .home(seat: Seat(1), slot: 0)

        await presenter.present(
            [.pawnMoved(
                pawn: pawns[0].id, from: pawns[0].position, to: .track(index: 7),
                path: [.track(index: 5), .track(index: 6), .track(index: 7)], backward: false
            )],
            finalPawns: final
        )

        #expect(presenter.displayedPawns == final)
        #expect(!presenter.isPresenting)
        #expect(presenter.emphasised == nil)
    }

    @Test("an event the board does not animate still leaves it correct")
    func unanimatedEventsStillSettle() async {
        let pawns = Self.startingPawns()
        let presenter = BoardPresenter(pawns: pawns, timing: .instant)
        var final = pawns
        final[2].position = .track(index: 30)

        await presenter.present([.turnPassed(to: Seat(2)), .dealerChanged(to: Seat(1))], finalPawns: final)
        #expect(presenter.displayedPawns == final)
    }

    // MARK: - It shows the journey

    @Test("a moving pawn visits every square it passes")
    func walksThePath() async {
        let pawns = Self.startingPawns()
        // A step duration that is non-zero but negligible: zero means Reduce
        // Motion, which deliberately lands the pawn instead of walking it —
        // using it here would have tested the opposite of the intent.
        let presenter = BoardPresenter(
            pawns: pawns,
            timing: .init(step: .microseconds(1), enter: .zero, capture: .zero,
                          swap: .zero, card: .zero, home: .zero)
        )

        var visited: [BoardPosition] = []
        let subject = pawns[0].id
        presenter.onStep = { pawn, position in
            if pawn == subject { visited.append(position) }
        }

        let path: [BoardPosition] = [
            .track(index: 1), .track(index: 2), .track(index: 3), .track(index: 4),
        ]
        var final = pawns
        final[0].position = .track(index: 4)

        await presenter.present(
            [.pawnMoved(pawn: subject, from: .track(index: 0), to: .track(index: 4), path: path, backward: false)],
            finalPawns: final
        )

        // Square by square, in order — this is how a player checks the engine
        // did what they expected (§39).
        #expect(visited == path)
    }

    /// The engine emits the capture first, because the square has to be free
    /// before the mover can take it. On screen that reads backwards.
    @Test("a captured pawn leaves after the pawn that took it arrives")
    func captureIsShownAfterTheMove() {
        let mover = PawnID(seat: Seat(0), slot: 0)
        let victim = PawnID(seat: Seat(1), slot: 0)
        let square = BoardPosition.track(index: 10)

        let engineOrder: [GameEvent] = [
            .pawnCaptured(pawn: victim, by: mover, at: square, returnedTo: .waiting(seat: Seat(1), slot: 0)),
            .pawnMoved(pawn: mover, from: .track(index: 5), to: square, path: [square], backward: false),
        ]

        let shown = BoardPresenter.presentationOrder(of: engineOrder)
        guard shown.count == 2 else {
            Issue.record("expected both events")
            return
        }
        if case .pawnMoved = shown[0] {} else { Issue.record("the move should be shown first") }
        if case .pawnCaptured = shown[1] {} else { Issue.record("the capture should be shown second") }
    }

    @Test("a capture unrelated to the next move keeps its place")
    func unrelatedCaptureIsNotReordered() {
        let victim = PawnID(seat: Seat(1), slot: 0)
        let other = PawnID(seat: Seat(2), slot: 0)
        let events: [GameEvent] = [
            .pawnCaptured(pawn: victim, by: PawnID(seat: Seat(0), slot: 0),
                          at: .track(index: 10), returnedTo: .waiting(seat: Seat(1), slot: 0)),
            .pawnMoved(pawn: other, from: .track(index: 20), to: .track(index: 22),
                       path: [.track(index: 22)], backward: false),
        ]
        let shown = BoardPresenter.presentationOrder(of: events)
        if case .pawnCaptured = shown[0] {} else { Issue.record("order should be unchanged") }
    }

    // MARK: - Interruption

    @Test("a cancelled animation leaves the board on the true position")
    func cancellationSettlesOnTruth() async {
        let pawns = Self.startingPawns()
        // Slow enough that cancellation lands mid-walk.
        let presenter = BoardPresenter(
            pawns: pawns,
            timing: .init(step: .milliseconds(80), enter: .zero, capture: .zero,
                          swap: .zero, card: .zero, home: .zero)
        )
        var final = pawns
        final[0].position = .track(index: 12)

        let path = (1...12).map { BoardPosition.track(index: $0) }
        let task = Task { @MainActor in
            await presenter.present(
                [.pawnMoved(pawn: pawns[0].id, from: .track(index: 0), to: .track(index: 12),
                            path: path, backward: false)],
                finalPawns: final
            )
        }
        try? await Task.sleep(for: .milliseconds(120))
        task.cancel()
        await task.value

        #expect(presenter.displayedPawns == final, "an interrupted animation must not strand the board")
        #expect(!presenter.isPresenting)
    }

    @Test("snapping jumps without animating")
    func snapIsImmediate() {
        let pawns = Self.startingPawns()
        let presenter = BoardPresenter(pawns: pawns, timing: .instant)
        var other = pawns
        other[3].position = .track(index: 44)

        presenter.snap(to: other)
        #expect(presenter.displayedPawns == other)
        #expect(presenter.emphasised == nil)
    }

    // MARK: - Reduce Motion

    @Test("reduce motion lands the move without walking it")
    func reduceMotionSkipsTheWalk() async {
        let pawns = Self.startingPawns()
        let presenter = BoardPresenter(pawns: pawns, timing: .instant)

        var steps = 0
        presenter.onStep = { _, _ in steps += 1 }

        let path = (1...9).map { BoardPosition.track(index: $0) }
        var final = pawns
        final[0].position = .track(index: 9)
        await presenter.present(
            [.pawnMoved(pawn: pawns[0].id, from: .track(index: 0), to: .track(index: 9),
                        path: path, backward: false)],
            finalPawns: final
        )

        #expect(steps == 1, "with motion reduced the pawn should land, not travel")
        #expect(presenter.displayedPawns == final)
    }

    // MARK: - A position with nothing to animate

    /// The rule the online board broke: whatever arrives, the pieces on screen
    /// must end up exactly where the state says.
    ///
    /// Every online move reaches the session through `adopt`, which carries no
    /// events at all — the events happened on another device, or inside the
    /// transport. The screen animated on events, so it animated nothing and
    /// left every piece where it was while the card vanished from the hand.
    ///
    /// This pins the repair at the level it was made: given a position and no
    /// events, the presenter shows that position, piece for piece.
    @Test("snapping shows the given position exactly, piece for piece")
    func snapShowsExactlyTheState() {
        let before = Self.startingPawns()
        let presenter = BoardPresenter(pawns: before, timing: .instant)

        // A different position, reached without any event describing how.
        var after = before
        after[0].position = .track(index: 11)
        after[1].position = .track(index: 4)

        presenter.snap(to: after)

        #expect(presenter.displayedPawns == after, "the board is not showing the position it was given")
        #expect(presenter.displayedPawns != before, "the board is still showing the old position")
    }

    @Test("snapping to a position a pawn entered from its waiting area shows it out")
    func snapShowsAPawnBroughtOut() throws {
        let before = Self.startingPawns()
        let presenter = BoardPresenter(pawns: before, timing: .instant)
        let waiting = try #require(
            before.first { if case .waiting = $0.position { return true } else { return false } },
            "the opening position should have pawns waiting"
        )

        var after = before
        let index = try #require(after.firstIndex { $0.id == waiting.id })
        after[index].position = .track(index: 0)
        presenter.snap(to: after)

        let shown = presenter.displayedPawns.first { $0.id == waiting.id }
        #expect(shown?.position == .track(index: 0), "a piece brought out was still shown waiting")
    }

    // MARK: - Timing

    @Test("the animation speed setting scales every duration")
    func timingScales() {
        let doubled = BoardPresenter.Timing.standard.scaled(by: 2)
        #expect(doubled.step < BoardPresenter.Timing.standard.step)
        #expect(doubled.swap < BoardPresenter.Timing.standard.swap)
        #expect(BoardPresenter.Timing.standard.scaled(by: 1) == .standard)
    }
}
