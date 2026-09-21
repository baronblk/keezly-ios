import Foundation

/// A match as it travels between devices.
///
/// The same idea as the saved match on disk (DEC-023): the configuration, the
/// seed and the accepted actions, from which the position follows. Nothing is
/// carried that could disagree with them — the revision, the seat on turn and
/// the checksums are written down so that a receiver can *check* what it
/// replays, not so that it can believe them instead.
///
/// Every number here is stable across processes. Nothing uses a Swift hash.
public struct OnlineMatchEnvelope: Hashable, Sendable, Codable {
    public let schemaVersion: Int
    public let engineVersion: String
    public let rulesVersion: Int

    public let matchID: String
    public let configuration: GameConfiguration
    public let seed: UInt64
    public let participants: ParticipantMapping
    public let actions: [PlayerAction]

    /// Claimed, and checked on arrival.
    public let currentRevision: Int
    public let currentSeat: Int
    public let status: MatchStatus
    public let result: GameResult?
    public let lastMoveID: String?

    /// Of the position the actions replay to.
    public let stateChecksum: UInt64
    /// Of everything above, so a truncated or edited payload is caught before
    /// anything is replayed.
    public let payloadChecksum: UInt64

    public init(match: OnlineMatch) throws {
        schemaVersion = KeezlyVersions.schema
        engineVersion = KeezlyVersions.engine
        rulesVersion = KeezlyVersions.rules
        matchID = match.matchID
        configuration = match.record.configuration
        seed = match.record.seed
        participants = match.participants
        actions = match.record.actions
        currentRevision = match.state.revision
        currentSeat = match.state.currentSeat.index
        status = match.record.status
        result = match.record.result
        lastMoveID = match.lastMoveID
        stateChecksum = try GameStateCoding.checksum(of: match.state)
        payloadChecksum = try Payload(
            matchID: matchID,
            configuration: configuration,
            seed: seed,
            participants: participants,
            actions: actions,
            currentRevision: currentRevision,
            stateChecksum: stateChecksum
        ).checksum()
    }

    /// Everything the match *is*, gathered so it can be hashed in a fixed
    /// order.
    ///
    /// A type rather than a long argument list: these seven values travel
    /// together, are hashed together, and adding an eighth should be one
    /// change here rather than three at the call sites.
    private struct Payload: Codable {
        let matchID: String
        let configuration: GameConfiguration
        let seed: UInt64
        let participants: ParticipantMapping
        let actions: [PlayerAction]
        let currentRevision: Int
        let stateChecksum: UInt64

        func checksum() throws -> UInt64 {
            Checksum.fnv1a(try GameStateCoding.makeEncoder().encode(self))
        }
    }

    /// The payload this envelope claims to be.
    private var payload: Payload {
        Payload(
            matchID: matchID,
            configuration: configuration,
            seed: seed,
            participants: participants,
            actions: actions,
            currentRevision: currentRevision,
            stateChecksum: stateChecksum
        )
    }

    /// The canonical bytes — the ones every checksum is taken over.
    ///
    /// Kept separate from what is sent. The canonical form has to stay
    /// byte-stable for the checksums to mean anything (DEC-009); what travels
    /// only has to arrive.
    public static func canonical(_ match: OnlineMatch) throws -> Data {
        try GameStateCoding.makeEncoder().encode(OnlineMatchEnvelope(match: match))
    }

    /// What is actually sent: the canonical bytes, compressed.
    ///
    /// Measured before it was added. A four-hundred-move six-player match came
    /// to **64,384 bytes** as plain JSON, against Game Center's 65,536-byte
    /// limit — so a full six-player match, which runs to something like seven
    /// hundred moves, would not have fitted. Compressing the same bytes brings
    /// it well inside the limit and changes nothing about how a match is
    /// represented (§28).
    ///
    /// Deliberately the smaller of the two available answers. A compact binary
    /// action encoding or a checkpoint scheme would both work and both cost
    /// more: another format to version, another way to disagree with the
    /// canonical bytes. They stay available if this stops being enough, and
    /// the size test will say when.
    public static func encode(_ match: OnlineMatch) throws -> Data {
        try compress(canonical(match))
    }

    static func compress(_ data: Data) throws -> Data {
        do {
            return try (data as NSData).compressed(using: .zlib) as Data
        } catch {
            throw OnlineMatchError.corrupted(reason: "could not compress: \(error)")
        }
    }

    static func decompress(_ data: Data) throws -> Data {
        do {
            return try (data as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw OnlineMatchError.corrupted(reason: "could not decompress: \(error)")
        }
    }

    // MARK: - Arriving

    /// Rebuilds a match from bytes that came off a network, or refuses.
    ///
    /// Remote data is never taken as a position. It is taken as a *claim*
    /// about a position, and the claim is checked by replaying the moves
    /// through the real engine and comparing the result with what was sent. A
    /// board that cannot be reproduced from its own history is not a board
    /// this device will play on (§28).
    public static func load(_ data: Data) throws -> OnlineMatch {
        let envelope: OnlineMatchEnvelope
        do {
            envelope = try GameStateCoding.makeDecoder()
                .decode(OnlineMatchEnvelope.self, from: try decompress(data))
        } catch let error as OnlineMatchError {
            throw error
        } catch {
            throw OnlineMatchError.corrupted(reason: String(describing: error))
        }

        guard envelope.schemaVersion <= KeezlyVersions.schema else {
            throw OnlineMatchError.unsupportedSchema(
                found: envelope.schemaVersion,
                supported: KeezlyVersions.schema
            )
        }
        guard envelope.rulesVersion == KeezlyVersions.rules else {
            throw OnlineMatchError.incompatibleRules(
                found: envelope.rulesVersion,
                supported: KeezlyVersions.rules
            )
        }

        let expectedPayload = try envelope.payload.checksum()
        guard expectedPayload == envelope.payloadChecksum else {
            throw OnlineMatchError.payloadChecksumMismatch(
                expected: envelope.payloadChecksum,
                actual: expectedPayload
            )
        }

        let participants = try envelope.participants.validated(against: envelope.configuration)

        let (record, state) = try replayed(envelope)

        guard state.revision == envelope.currentRevision else {
            throw OnlineMatchError.revisionMismatch(
                expected: envelope.currentRevision,
                actual: state.revision
            )
        }
        guard state.currentSeat.index == envelope.currentSeat else {
            throw OnlineMatchError.seatMismatch(expected: envelope.currentSeat, actual: state.currentSeat.index)
        }
        let replayedChecksum = try GameStateCoding.checksum(of: state)
        guard replayedChecksum == envelope.stateChecksum else {
            throw OnlineMatchError.stateChecksumMismatch(
                expected: envelope.stateChecksum,
                actual: replayedChecksum
            )
        }
        guard record.status == envelope.status, record.result == envelope.result else {
            throw OnlineMatchError.statusMismatch
        }

        return OnlineMatch(
            record: record,
            state: state,
            participants: participants,
            lastMoveID: envelope.lastMoveID
        )
    }

    /// Plays the recorded actions through the engine.
    ///
    /// A remote move is not trusted because it arrived; it is trusted because
    /// it is legal here too. Exactly what a saved match does on restore — the
    /// same engine, the same refusals (DEC-023).
    private static func replayed(
        _ envelope: OnlineMatchEnvelope
    ) throws -> (record: MatchRecord, state: GameState) {
        var record = MatchRecord(
            configuration: envelope.configuration,
            seed: envelope.seed,
            matchID: envelope.matchID
        )
        var state = record.initialState
        var previousRevision = state.revision

        for (index, action) in envelope.actions.enumerated() {
            let transition: GameTransition
            do {
                transition = try GameReducer.apply(action, to: state)
            } catch {
                throw OnlineMatchError.illegalAction(index: index, reason: String(describing: error))
            }
            state = transition.state
            guard state.revision > previousRevision else {
                throw OnlineMatchError.revisionNotMonotonic(atAction: index, revision: state.revision)
            }
            previousRevision = state.revision
            record.append(action)
        }

        record.note(state)
        return (record, state)
    }
}

/// Why a match that arrived from elsewhere was refused.
///
/// Each one is a refusal. Nothing is repaired, and no position is half
/// accepted: a device that plays on from a board it could not reproduce would
/// quietly diverge from everybody else's (§28).
public enum OnlineMatchError: Error, Hashable, Sendable, LocalizedError {
    case corrupted(reason: String)
    case unsupportedSchema(found: Int, supported: Int)
    case incompatibleRules(found: Int, supported: Int)
    case payloadChecksumMismatch(expected: UInt64, actual: UInt64)
    case illegalAction(index: Int, reason: String)
    case revisionNotMonotonic(atAction: Int, revision: Int)
    case revisionMismatch(expected: Int, actual: Int)
    case seatMismatch(expected: Int, actual: Int)
    case stateChecksumMismatch(expected: UInt64, actual: UInt64)
    case statusMismatch
    case mapping(ParticipantMappingError)

    public var errorDescription: String? {
        switch self {
        case .corrupted(let reason):
            "The match data could not be read (\(reason))."
        case .unsupportedSchema(let found, let supported):
            "This match was created by a newer version of Keezly (\(found) against \(supported))."
        case .incompatibleRules(let found, let supported):
            "This match is played under different rules (\(found) against \(supported))."
        case .payloadChecksumMismatch:
            "The match data was altered in transit."
        case .illegalAction(let index, let reason):
            "Move \(index + 1) is not legal here (\(reason))."
        case .revisionNotMonotonic(let index, _):
            "The match does not move forward at move \(index + 1)."
        case .revisionMismatch(let expected, let actual):
            "The match replays to a different point (expected \(expected), got \(actual))."
        case .seatMismatch(let expected, let actual):
            "The match says it is seat \(expected)'s turn but replays to seat \(actual)."
        case .stateChecksumMismatch:
            "The match replays to a different board than the one that was sent."
        case .statusMismatch:
            "The match disagrees with its own history about whether it is over."
        case .mapping(let error):
            error.errorDescription
        }
    }
}
