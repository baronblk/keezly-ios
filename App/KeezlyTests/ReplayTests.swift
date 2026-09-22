import Foundation
@testable import Keezly
import KeezlyCore
import Testing

/// §M9.3 — a replay reproduces a match from its record and never touches it.
@Suite("Replay")
@MainActor
struct ReplayTests {

    /// A real match, played to the end.
    private func played(seats: Int = 4, seed: UInt64 = 2026, limit: Int = 900) -> MatchRecord {
        var record = MatchRecord(configuration: .standard(seatCount: seats), seed: seed)
        var state = record.initialState
        var generator = SeededGenerator(seed: seed &+ 3)

        for _ in 0..<limit where state.result == nil {
            let legal = MoveGenerator.legalMoves(in: state, for: state.currentSeat)
            let action: PlayerAction = legal.isEmpty
                ? .foldHand(seat: state.currentSeat)
                : .play(legal[Int.random(in: 0..<legal.count, using: &generator)])
            guard let next = try? GameReducer.apply(action, to: state) else { break }
            state = next.state
            record.append(action)
        }
        record.note(state)
        return record
    }

    private func run(_ record: MatchRecord) -> ReplayRun {
        ReplayRun(
            record: record,
            roles: [.human] + Array(repeating: SeatRole.computer(.medium), count: record.configuration.seatCount - 1)
        )
    }

    // MARK: - It reproduces the match

    /// **Playing the whole record through arrives at exactly the board the
    /// match ended on.**
    @Test("a replay reaches the same final position as the match", arguments: [2, 4, 6])
    func replayReachesTheSameEnd(seats: Int) throws {
        let record = played(seats: seats, seed: UInt64(seats) &* 101)
        let replay = run(record)
        try #require(replay.stepCount > 20, "the fixture produced too short a match to prove anything")

        replay.end()
        #expect(replay.isAtEnd)

        // The board the match itself finished on, computed independently.
        var expected = record.initialState
        for action in record.actions {
            expected = try GameReducer.apply(action, to: expected).state
        }
        #expect(replay.state.pawns == expected.pawns)
        #expect(replay.state.hands == expected.hands)
        #expect(replay.state.revision == expected.revision)
        #expect(replay.state.result == expected.result)
    }

    /// **Every step is the same board however you arrive at it.**
    ///
    /// Forwards one at a time, backwards one at a time, and jumped to
    /// directly all have to agree. They do not have to *get there* the same
    /// way — stepping back rebuilds from the opening, because the engine has
    /// no inverse and writing one would be a second implementation of the
    /// rules.
    @Test("stepping forwards, backwards and jumping all agree")
    func everyRouteAgrees() throws {
        let record = played(seed: 4242)
        let forwards = run(record)
        var boards: [Int: GameState] = [0: forwards.state]
        while forwards.next() { boards[forwards.step] = forwards.state }

        let backwards = run(record)
        backwards.end()
        while !backwards.isAtStart {
            backwards.previous()
            let expected = try #require(boards[backwards.step])
            #expect(backwards.state.pawns == expected.pawns, "step \(backwards.step) differs going backwards")
            #expect(backwards.state.revision == expected.revision)
        }

        let jumped = run(record)
        for target in stride(from: 0, through: record.actionCount, by: 7) {
            jumped.goTo(step: target)
            let expected = try #require(boards[target])
            #expect(jumped.state.pawns == expected.pawns, "step \(target) differs when jumped to")
        }
    }

    @Test("the transport controls stay inside the record")
    func controlsAreBounded() {
        let record = played(seed: 77)
        let replay = run(record)

        replay.previous()
        #expect(replay.step == 0, "stepping back from the start went somewhere")

        replay.end()
        #expect(replay.step == record.actionCount)
        #expect(!replay.next(), "stepping forward from the end went somewhere")
        #expect(replay.step == record.actionCount)

        replay.goTo(step: -50)
        #expect(replay.step == 0)
        replay.goTo(step: record.actionCount + 50)
        #expect(replay.step == record.actionCount)
    }

    @Test("playing stops by itself at the end")
    func playingStops() {
        let replay = run(played(seed: 5150))
        replay.goTo(step: replay.stepCount - 2)
        replay.play()
        #expect(replay.isPlaying)

        replay.tick()
        replay.tick()
        replay.tick()
        #expect(!replay.isPlaying, "the replay ran off the end still playing")
        #expect(replay.isAtEnd)
    }

    // MARK: - It changes nothing

    /// **A replay has nowhere to write to.**
    ///
    /// The strongest form this check can take: the type holds no store, so
    /// there is no path from watching a match back to changing it.
    @Test("watching a match back does not change the record")
    func replayDoesNotWrite() throws {
        let record = played(seed: 909)
        let before = try GameStateCoding.makeEncoder().encode(record)

        let replay = run(record)
        replay.end()
        replay.restart()
        replay.goTo(step: 12)
        replay.next()
        replay.previous()

        let after = try GameStateCoding.makeEncoder().encode(replay.record)
        #expect(before == after, "the record came out of the replay different from how it went in")
        #expect(replay.record.actions == record.actions)
        #expect(replay.record.status == record.status)
    }

    // MARK: - Fast enough to step through

    /// **Measured before anything was built to make it faster.**
    ///
    /// The first version rebuilt from the opening on every backward step.
    /// This test measured that at **59 ms a step** on a finished six-player
    /// match of 810 actions — four frames of waiting for a button press — and
    /// that number is what justified adding checkpoints. Without it they would
    /// have been a guess dressed as an optimisation.
    ///
    /// Measured in a debug build, which is pessimistic and is the point: a
    /// figure taken with optimisations on would flatter the slow version.
    @Test("stepping backwards through a whole match lands inside a frame")
    func steppingBackwardsIsFastEnough() throws {
        let record = played(seats: 6, seed: 404)
        try #require(record.actionCount > 200, "the worst case needs a long match: \(record.actionCount)")

        let replay = run(record)
        replay.end()

        let started = Date()
        var steps = 0
        while !replay.isAtStart, steps < 60 {
            replay.previous()
            steps += 1
        }
        let elapsed = Date().timeIntervalSince(started)
        let each = elapsed / Double(max(1, steps))

        // A step has to land inside one frame at 60 Hz to feel like a step
        // rather than a wait.
        #expect(
            each < 0.016,
            "a backwards step took \(Int(each * 1000))ms on a \(record.actionCount)-action match"
        )
    }

    @Test("a replay of an unfinished match is still a replay")
    func abandonedMatchesReplay() {
        var record = played(seed: 313, limit: 40)
        record.abandon()
        let replay = run(record)
        replay.end()
        #expect(replay.step == record.actionCount)
        #expect(replay.state.result == nil, "an abandoned match has no winner")
    }
}
