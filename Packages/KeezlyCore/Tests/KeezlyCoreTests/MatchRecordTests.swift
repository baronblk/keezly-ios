import Foundation
@testable import KeezlyCore
import Testing

/// §57 — replay falls out of determinism: a seed plus the actions taken is the
/// whole match.
@Suite("Match record")
struct MatchRecordTests {

    /// Plays a full match through the recorder.
    static func recordedMatch(seatCount: Int, seed: UInt64, maxActions: Int = 4000) throws -> MatchRecorder {
        var chooser = SeededGenerator(seed: seed &* 7)
        var recorder = MatchRecorder(configuration: .standard(seatCount: seatCount), seed: seed)
        var actions = 0

        while !recorder.state.isFinished && actions < maxActions {
            let moves = MoveGenerator.legalMoves(in: recorder.state, for: recorder.state.currentSeat)
            let action: PlayerAction = moves.isEmpty
                ? .foldHand(seat: recorder.state.currentSeat)
                : .play(moves[Int(chooser.next() % UInt64(moves.count))])
            try recorder.apply(action)
            actions += 1
        }
        return recorder
    }

    @Test("a replayed match reproduces every state exactly", arguments: 2...6)
    func replayReproducesTheMatch(seatCount: Int) throws {
        let recorder = try Self.recordedMatch(seatCount: seatCount, seed: 4_242)
        #expect(recorder.state.isFinished)

        let transitions = try recorder.record.replay()
        #expect(transitions.count == recorder.record.actionCount)
        #expect(transitions.last?.state == recorder.state)
        #expect(try recorder.record.finalState() == recorder.state)
    }

    @Test("stepping through a record gives monotonic revisions")
    func steppingIsMonotonic() throws {
        let recorder = try Self.recordedMatch(seatCount: 4, seed: 99)
        let record = recorder.record

        #expect(try record.state(after: 0) == record.initialState)
        var previous = try record.state(after: 0).revision
        for step in stride(from: 1, through: record.actionCount, by: max(1, record.actionCount / 12)) {
            let revision = try record.state(after: step).revision
            #expect(revision > previous, "revision did not advance by step \(step)")
            previous = revision
        }
    }

    @Test("the events a replay produces match the ones the live match produced")
    func replayReproducesEvents() throws {
        var chooser = SeededGenerator(seed: 5)
        var recorder = MatchRecorder(configuration: .standard(seatCount: 4), seed: 1_234)
        var liveEvents: [GameEvent] = []

        for _ in 0..<80 where !recorder.state.isFinished {
            let moves = MoveGenerator.legalMoves(in: recorder.state, for: recorder.state.currentSeat)
            let action: PlayerAction = moves.isEmpty
                ? .foldHand(seat: recorder.state.currentSeat)
                : .play(moves[Int(chooser.next() % UInt64(moves.count))])
            liveEvents += try recorder.apply(action).events
        }

        let replayed = try recorder.record.replay().flatMap(\.events)
        #expect(replayed == liveEvents, "a replay must animate exactly what happened")
    }

    // MARK: - Storage

    @Test("a record round-trips through its envelope")
    func envelopeRoundTrip() throws {
        let record = try Self.recordedMatch(seatCount: 4, seed: 77).record
        let data = try MatchRecordEnvelope.encode(record)
        #expect(try MatchRecordEnvelope.decode(data) == record)
    }

    @Test("a tampered record is refused")
    func tamperedRecordIsRefused() throws {
        let record = try Self.recordedMatch(seatCount: 4, seed: 78).record
        let data = try MatchRecordEnvelope.encode(record)
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["recordChecksum"] = (json["recordChecksum"] as? UInt64 ?? 0) &+ 1
        let tampered = try JSONSerialization.data(withJSONObject: json)

        #expect(throws: SerializationError.self) {
            try MatchRecordEnvelope.decode(tampered)
        }
    }

    @Test("a history from a newer build is refused rather than replayed")
    func newerSchemaIsRefused() throws {
        let record = try Self.recordedMatch(seatCount: 4, seed: 79).record
        let data = try MatchRecordEnvelope.encode(record)
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["schemaVersion"] = KeezlyVersions.schema + 3
        let future = try JSONSerialization.data(withJSONObject: json)

        #expect(throws: SerializationError.self) {
            try MatchRecordEnvelope.decode(future)
        }
    }

    /// A record is the seed plus the actions, so it stays small enough to keep
    /// many of them on device without thought (§56).
    @Test("a full six-player match record stays compact")
    func recordsAreCompact() throws {
        let record = try Self.recordedMatch(seatCount: 6, seed: 11).record
        let size = try MatchRecordEnvelope.encode(record).count
        #expect(record.actionCount > 50, "the fixture should be a real match")
        #expect(size < 200 * 1024, "a six-player record took \(size) bytes for \(record.actionCount) actions")
    }
}
