import Foundation

/// Version identifiers for anything Keezly persists or transmits.
///
/// These are deliberately separate. A pure refactor bumps nothing; a change to
/// the stored shape bumps the schema; a change that alters which moves are
/// legal bumps the rules version, because an old client replaying a new match
/// would then compute a different board.
public enum KeezlyVersions {
    /// Layout of the persisted envelope. Increment on any stored-shape change.
    public static let schema = 1
    /// The engine build that produced a payload. Informational; used in
    /// diagnostics and bug reports.
    public static let engine = "1.0.0"
    /// Semantics of the rules. Increment whenever a rule change could make the
    /// same state and the same move produce a different result.
    public static let rules = 1
}

public enum SerializationError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The payload was written by a newer build than this one.
    case unsupportedSchemaVersion(found: Int, supported: Int)
    /// The payload decoded, but does not match its own checksum.
    case checksumMismatch(expected: UInt64, actual: UInt64)
    /// The payload exceeds the transport's limit, e.g. `matchDataMaximumSize`.
    case payloadTooLarge(bytes: Int, limit: Int)
    /// The payload could not be decoded at all.
    case corrupted(reason: String)

    public var description: String {
        switch self {
        case .unsupportedSchemaVersion(let found, let supported):
            "This match was saved by a newer version of Keezly (format \(found); this build understands \(supported))."
        case .checksumMismatch(let expected, let actual):
            "The saved match is damaged (checksum \(actual) does not match \(expected))."
        case .payloadTooLarge(let bytes, let limit):
            "The match state is \(bytes) bytes, above the \(limit) byte limit."
        case .corrupted(let reason):
            "The saved match could not be read: \(reason)"
        }
    }
}

/// A versioned, self-checking container around a `GameState`.
///
/// Every save to disk and every upload to Game Center goes through this. The
/// point is that a future refactor cannot silently mis-read an old match: it
/// either decodes correctly or fails with a typed error that the UI can turn
/// into a sentence a player understands (§20, §28, §29).
public struct GameStateEnvelope: Codable, Hashable, Sendable {
    public let schemaVersion: Int
    public let engineVersion: String
    public let rulesVersion: Int
    /// FNV-1a over the canonical encoding of `state`.
    public let stateChecksum: UInt64
    public let state: GameState

    /// Wraps a state, computing its checksum.
    public init(state: GameState) throws {
        self.schemaVersion = KeezlyVersions.schema
        self.engineVersion = KeezlyVersions.engine
        self.rulesVersion = KeezlyVersions.rules
        self.stateChecksum = try GameStateCoding.checksum(of: state)
        self.state = state
    }

    // MARK: - Encoding

    /// Serialises a state for storage or transmission.
    ///
    /// - Parameter maximumBytes: an optional transport limit. Pass
    ///   `match.matchDataMaximumSize` before a Game Center upload so an
    ///   oversized payload is caught here rather than by GameKit (§28).
    public static func encode(_ state: GameState, maximumBytes: Int? = nil) throws -> Data {
        let envelope = try GameStateEnvelope(state: state)
        let data = try GameStateCoding.makeEncoder().encode(envelope)
        if let maximumBytes, data.count > maximumBytes {
            throw SerializationError.payloadTooLarge(bytes: data.count, limit: maximumBytes)
        }
        return data
    }

    /// Reads a state back, refusing anything it cannot read correctly.
    ///
    /// A payload from a *newer* schema is rejected outright rather than decoded
    /// on a best-effort basis: partially understanding someone else's match is
    /// how a board silently ends up wrong.
    public static func decode(_ data: Data) throws -> GameState {
        let envelope: GameStateEnvelope
        do {
            envelope = try GameStateCoding.makeDecoder().decode(GameStateEnvelope.self, from: data)
        } catch {
            // Read just the version first, so "saved by a newer build" reports
            // as that rather than as generic corruption.
            if let header = try? GameStateCoding.makeDecoder().decode(VersionHeader.self, from: data),
               header.schemaVersion > KeezlyVersions.schema {
                throw SerializationError.unsupportedSchemaVersion(
                    found: header.schemaVersion,
                    supported: KeezlyVersions.schema
                )
            }
            throw SerializationError.corrupted(reason: String(describing: error))
        }

        guard envelope.schemaVersion <= KeezlyVersions.schema else {
            throw SerializationError.unsupportedSchemaVersion(
                found: envelope.schemaVersion,
                supported: KeezlyVersions.schema
            )
        }

        let actual = try GameStateCoding.checksum(of: envelope.state)
        guard actual == envelope.stateChecksum else {
            throw SerializationError.checksumMismatch(expected: envelope.stateChecksum, actual: actual)
        }

        return envelope.state
    }

    /// Just enough of the envelope to learn which build wrote it.
    private struct VersionHeader: Decodable {
        let schemaVersion: Int
    }
}
