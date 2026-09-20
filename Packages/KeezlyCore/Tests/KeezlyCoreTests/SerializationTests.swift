import Foundation
import Testing
@testable import KeezlyCore

/// §20, §28, §29 — a saved or transmitted match must survive a refactor, or
/// fail loudly. It must never be read back *almost* correctly.
@Suite("Serialization")
struct SerializationTests {

    /// A state deep enough into a match to exercise folds, discards and moves.
    static func playedState(seatCount: Int, seed: UInt64, actions: Int = 60) throws -> GameState {
        var chooser = SeededGenerator(seed: seed &* 31)
        var state = GameState.newMatch(configuration: .standard(seatCount: seatCount), seed: seed)
        for _ in 0..<actions where !state.isFinished {
            let moves = MoveGenerator.legalMoves(in: state, for: state.currentSeat)
            let action: PlayerAction = moves.isEmpty
                ? .foldHand(seat: state.currentSeat)
                : .play(moves[Int(chooser.next() % UInt64(moves.count))])
            state = try GameReducer.apply(action, to: state).state
        }
        return state
    }

    // MARK: - Round trip

    @Test("an envelope round-trips to an identical state", arguments: 2...6)
    func roundTrip(seatCount: Int) throws {
        let original = try Self.playedState(seatCount: seatCount, seed: 2024)
        let data = try GameStateEnvelope.encode(original)
        let restored = try GameStateEnvelope.decode(data)
        #expect(restored == original)
    }

    @Test("a restored match continues exactly as the original would have")
    func restoredMatchContinuesIdentically() throws {
        let original = try Self.playedState(seatCount: 4, seed: 808)
        let restored = try GameStateEnvelope.decode(try GameStateEnvelope.encode(original))

        // Same legal moves, and the same result after applying the same one.
        let a = MoveGenerator.legalMoves(in: original, for: original.currentSeat)
        let b = MoveGenerator.legalMoves(in: restored, for: restored.currentSeat)
        #expect(a == b)

        if let move = a.first {
            let afterOriginal = try GameReducer.apply(.play(move), to: original).state
            let afterRestored = try GameReducer.apply(.play(move), to: restored).state
            #expect(afterOriginal == afterRestored)
        }
    }

    // MARK: - Determinism of the encoding itself

    @Test("encoding the same state twice produces identical bytes", arguments: 2...6)
    func encodingIsByteStable(seatCount: Int) throws {
        let state = try Self.playedState(seatCount: seatCount, seed: 55)
        #expect(try GameStateEnvelope.encode(state) == (try GameStateEnvelope.encode(state)))
    }

    /// This is the reason `GameState` has a hand-written `Codable`: `Set`
    /// iteration order is salted per process, so a synthesised encoding would
    /// differ between runs and break every checksum comparison.
    @Test("seat sets encode in a stable order regardless of insertion order")
    func setsEncodeDeterministically() throws {
        func state(withFoldsInOrder order: [Int]) -> GameState {
            var s = Fixture.state(seatCount: 6, hands: [:])
            for index in order { s.foldHand(of: Seat(index)) }
            return s
        }
        let ascending = try GameStateCoding.encode(state(withFoldsInOrder: [0, 2, 4, 5]))
        let shuffled = try GameStateCoding.encode(state(withFoldsInOrder: [5, 0, 4, 2]))
        #expect(ascending == shuffled)
    }

    @Test("the checksum is stable across encodings and sensitive to change")
    func checksumBehaviour() throws {
        let state = try Self.playedState(seatCount: 4, seed: 99)
        #expect(try GameStateCoding.checksum(of: state) == (try GameStateCoding.checksum(of: state)))

        let moved = try GameReducer.apply(
            MoveGenerator.legalMoves(in: state, for: state.currentSeat).first.map { .play($0) }
                ?? .foldHand(seat: state.currentSeat),
            to: state
        ).state
        #expect(try GameStateCoding.checksum(of: moved) != (try GameStateCoding.checksum(of: state)))
    }

    // MARK: - Version and integrity guards

    @Test("the envelope records the current versions")
    func envelopeCarriesVersions() throws {
        let envelope = try GameStateEnvelope(state: Self.playedState(seatCount: 4, seed: 1))
        #expect(envelope.schemaVersion == KeezlyVersions.schema)
        #expect(envelope.rulesVersion == KeezlyVersions.rules)
        #expect(envelope.engineVersion == KeezlyVersions.engine)
    }

    @Test("a payload from a newer schema is refused, not guessed at")
    func newerSchemaIsRefused() throws {
        let data = try GameStateEnvelope.encode(Self.playedState(seatCount: 4, seed: 5))
        var json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        json["schemaVersion"] = KeezlyVersions.schema + 7
        let tampered = try JSONSerialization.data(withJSONObject: json)

        #expect(throws: SerializationError.unsupportedSchemaVersion(
            found: KeezlyVersions.schema + 7,
            supported: KeezlyVersions.schema
        )) {
            try GameStateEnvelope.decode(tampered)
        }
    }

    @Test("a damaged payload is refused rather than partially restored")
    func checksumMismatchIsRefused() throws {
        let data = try GameStateEnvelope.encode(Self.playedState(seatCount: 4, seed: 6))
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        // Corrupt the state without touching the recorded checksum.
        var state = try #require(json["state"] as? [String: Any])
        state["revision"] = (state["revision"] as? Int ?? 0) + 1
        json["state"] = state
        let tampered = try JSONSerialization.data(withJSONObject: json)

        #expect(throws: SerializationError.self) {
            try GameStateEnvelope.decode(tampered)
        }
    }

    @Test("unreadable data fails with a typed error, never a crash")
    func garbageIsRejectedCleanly() {
        #expect(throws: SerializationError.self) {
            try GameStateEnvelope.decode(Data("not a keezly match".utf8))
        }
        #expect(throws: SerializationError.self) {
            try GameStateEnvelope.decode(Data())
        }
    }

    // MARK: - Transport limits (§28)

    @Test("an oversized payload is caught before it reaches the transport")
    func payloadLimitIsEnforced() throws {
        let state = try Self.playedState(seatCount: 6, seed: 12)
        let size = try GameStateEnvelope.encode(state).count

        #expect(throws: SerializationError.payloadTooLarge(bytes: size, limit: size - 1)) {
            try GameStateEnvelope.encode(state, maximumBytes: size - 1)
        }
        #expect(throws: Never.self) {
            try GameStateEnvelope.encode(state, maximumBytes: size)
        }
    }

    /// Game Center's turn-based limit has been 64 KiB for a long time, but the
    /// real value is read from the match at runtime. This test is a canary on
    /// the *shape* of our payload, so a future state change that bloats it
    /// shows up here rather than as a failed upload on a device.
    @Test("a six-player state stays comfortably inside a 64 KiB budget")
    func sixPlayerStateIsCompactEnough() throws {
        let size = try GameStateEnvelope.encode(Self.playedState(seatCount: 6, seed: 3, actions: 120)).count
        #expect(size < 64 * 1024, "six-player envelope is \(size) bytes")
    }
}
