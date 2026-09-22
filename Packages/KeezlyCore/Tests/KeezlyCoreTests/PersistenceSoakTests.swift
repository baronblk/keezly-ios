import Foundation
@testable import KeezlyCore
import Testing

/// §112 — persistence and replay under sustained load.
///
/// `SerializationTests` and `MatchRecordTests` already establish the
/// properties: an envelope round-trips, a replay reproduces the match, encoding
/// twice gives identical bytes, and a tampered or newer payload is refused
/// rather than guessed at.
///
/// What they do not establish is **position**. `steppingIsMonotonic` walks a
/// record at `actionCount / 12` intervals — about twelve sample points in a
/// match of two hundred actions — and the round-trip tests use a fresh deal.
/// A save that is correct at the opening deal and wrong halfway through a
/// Seven split passes all of it, because nothing saves halfway through a Seven
/// split.
///
/// So this checks the same small number of properties at **every** point of a
/// real match, on every table size. Nothing here is a new assertion; what is
/// added is occasions to violate the ones already made.
///
///     KEEZLY_EXTENDED_SIM=1 swift test --filter "Persistence soak"
@Suite("Persistence soak")
struct PersistenceSoakTests {

    /// A complete match, and every state it passed through on the way.
    private static func played(seats: Int, seed: UInt64) throws -> (MatchRecorder, [GameState]) {
        var chooser = SeededGenerator(seed: seed &* 7)
        var recorder = MatchRecorder(configuration: .standard(seatCount: seats), seed: seed)
        var states: [GameState] = [recorder.state]

        var actions = 0
        while !recorder.state.isFinished, actions < 4_000 {
            let moves = MoveGenerator.legalMoves(in: recorder.state, for: recorder.state.currentSeat)
            let action: PlayerAction = moves.isEmpty
                ? .foldHand(seat: recorder.state.currentSeat)
                : .play(moves[Int(chooser.next() % UInt64(moves.count))])
            try recorder.apply(action)
            states.append(recorder.state)
            actions += 1
        }
        return (recorder, states)
    }

    // MARK: - Persistence

    /// **Every point of the match, not twelve of them.**
    ///
    /// A record is a seed and the actions accepted, so the state it rebuilds
    /// after *n* actions must be the state the live match was in after *n*
    /// actions — for every *n*.
    @Test(
        "a record rebuilds the exact state at every point the match reached",
        .extendedSimulation,
        arguments: 2...6
    )
    func rebuildsEveryPoint(seats: Int) throws {
        let (recorder, states) = try Self.played(seats: seats, seed: 0x9E_0000 &+ UInt64(seats))
        let record = recorder.record
        #expect(states.count > 20, "seats \(seats): the match was too short to be worth torturing")

        for step in 0...record.actionCount {
            let rebuilt = try record.state(after: step)
            #expect(
                rebuilt == states[step],
                "seats \(seats): rebuilding \(step) of \(record.actionCount) actions gave a different state"
            )
        }
    }

    /// Every intermediate state survives the wire, not only the first and last.
    ///
    /// Byte equality rather than value equality, because a save is bytes: two
    /// states that compare equal and encode differently would still break a
    /// checksum, and the byte-stable encoding is the whole point of DEC-009.
    @Test(
        "every state a match passes through round-trips, byte for byte",
        .extendedSimulation,
        arguments: 2...6
    )
    func everyStateRoundTrips(seats: Int) throws {
        let (_, states) = try Self.played(seats: seats, seed: 0x9F_0000 &+ UInt64(seats))

        for (index, state) in states.enumerated() {
            let data = try GameStateEnvelope.encode(state)
            let restored = try GameStateEnvelope.decode(data)
            #expect(restored == state, "seats \(seats): state \(index) changed on the way through")
            #expect(
                try GameStateEnvelope.encode(restored) == data,
                "seats \(seats): state \(index) did not encode back to the same bytes"
            )
        }
    }

    // MARK: - Replay

    /// **A replay is only worth having if it is the match.**
    ///
    /// Compared state by state rather than at the end: a replay that arrives at
    /// the right final position by a different route shows somebody a game they
    /// did not play.
    @Test("a replay reproduces every state, not just the last", .extendedSimulation, arguments: 2...6)
    func replayMatchesTheMatch(seats: Int) throws {
        let (recorder, states) = try Self.played(seats: seats, seed: 0xA0_0000 &+ UInt64(seats))
        let transitions = try recorder.record.replay()

        #expect(transitions.count == states.count - 1, "seats \(seats): the replay is a different length")
        for (index, transition) in transitions.enumerated() {
            #expect(
                transition.state == states[index + 1],
                "seats \(seats): the replay diverged at action \(index)"
            )
        }
    }

    /// Replaying one record twice gives one answer twice.
    ///
    /// Trivial if a replay is a pure function of a seed and a list of actions,
    /// which it is meant to be — and precisely the property that quietly stops
    /// holding the moment something in the path consults a clock. That is not
    /// hypothetical: it is how `HardAgent` behaved until today (ISS-017).
    @Test("replaying one record twice gives identical bytes", .extendedSimulation, arguments: 2...6)
    func replayIsDeterministic(seats: Int) throws {
        let (recorder, _) = try Self.played(seats: seats, seed: 0xA1_0000 &+ UInt64(seats))
        let record = recorder.record

        let first = try GameStateEnvelope.encode(record.finalState())
        let second = try GameStateEnvelope.encode(record.finalState())
        #expect(first == second, "seats \(seats): two replays of one record disagreed")
    }
}
