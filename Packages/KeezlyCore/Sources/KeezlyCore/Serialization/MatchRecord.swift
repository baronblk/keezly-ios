import Foundation

/// A complete match, stored as its starting conditions plus the actions taken.
///
/// This is deliberately tiny. Because the engine is deterministic (DEC-003),
/// the seed and the ordered list of actions *are* the match: replaying them
/// reconstructs every intermediate state exactly. There is no need to store
/// board snapshots, and storing them would only create a second source of truth
/// that could drift.
///
/// It is kept separate from `GameState` on purpose: a live match needs the
/// current position, not its history, and a Game Center payload must stay small
/// (§28). History is local (§57).
public struct MatchRecord: Hashable, Sendable, Codable {
    public let configuration: GameConfiguration
    public let seed: UInt64
    public private(set) var actions: [PlayerAction]

    public init(configuration: GameConfiguration, seed: UInt64, actions: [PlayerAction] = []) {
        self.configuration = configuration
        self.seed = seed
        self.actions = actions
    }

    public var actionCount: Int { actions.count }

    public mutating func append(_ action: PlayerAction) {
        actions.append(action)
    }

    // MARK: - Replay

    /// The state the match started from.
    public var initialState: GameState {
        GameState.newMatch(configuration: configuration, seed: seed)
    }

    /// Replays the whole match, returning every transition in order.
    ///
    /// - Throws: `MoveError` if a recorded action is not legal at its point in
    ///   the sequence, which means the record and the engine disagree — a
    ///   corrupted record, or a rules change that was not accompanied by a
    ///   `rulesVersion` bump.
    public func replay() throws -> [GameTransition] {
        var state = initialState
        var transitions: [GameTransition] = []
        transitions.reserveCapacity(actions.count)
        for action in actions {
            let transition = try GameReducer.apply(action, to: state)
            transitions.append(transition)
            state = transition.state
        }
        return transitions
    }

    /// The state after `count` actions. `count` of 0 is the initial position.
    public func state(after count: Int) throws -> GameState {
        precondition((0...actions.count).contains(count), "step \(count) is outside this record")
        var state = initialState
        for action in actions.prefix(count) {
            state = try GameReducer.apply(action, to: state).state
        }
        return state
    }

    public func finalState() throws -> GameState {
        try state(after: actions.count)
    }
}

/// Keeps a live match and its record in step.
///
/// Using this rather than appending by hand means a replay can never miss an
/// action: the only way to advance the state is `apply`, and that records.
public struct MatchRecorder: Sendable {
    public private(set) var state: GameState
    public private(set) var record: MatchRecord

    public init(configuration: GameConfiguration, seed: UInt64) {
        self.state = GameState.newMatch(configuration: configuration, seed: seed)
        self.record = MatchRecord(configuration: configuration, seed: seed)
    }

    /// Applies an action and records it.
    @discardableResult
    public mutating func apply(_ action: PlayerAction) throws -> GameTransition {
        let transition = try GameReducer.apply(action, to: state)
        state = transition.state
        record.append(action)
        return transition
    }
}

/// A versioned container for a stored match history.
///
/// Mirrors `GameStateEnvelope`: same version fields, same refuse-rather-than-
/// guess decoding, so a history written by a newer build is reported clearly
/// instead of replaying into a subtly different board.
public struct MatchRecordEnvelope: Codable, Hashable, Sendable {
    public let schemaVersion: Int
    public let engineVersion: String
    public let rulesVersion: Int
    public let recordChecksum: UInt64
    public let record: MatchRecord

    public init(record: MatchRecord) throws {
        self.schemaVersion = KeezlyVersions.schema
        self.engineVersion = KeezlyVersions.engine
        self.rulesVersion = KeezlyVersions.rules
        self.recordChecksum = Checksum.fnv1a(try GameStateCoding.makeEncoder().encode(record))
        self.record = record
    }

    public static func encode(_ record: MatchRecord) throws -> Data {
        try GameStateCoding.makeEncoder().encode(MatchRecordEnvelope(record: record))
    }

    public static func decode(_ data: Data) throws -> MatchRecord {
        let envelope: MatchRecordEnvelope
        do {
            envelope = try GameStateCoding.makeDecoder().decode(MatchRecordEnvelope.self, from: data)
        } catch {
            throw SerializationError.corrupted(reason: String(describing: error))
        }

        guard envelope.schemaVersion <= KeezlyVersions.schema else {
            throw SerializationError.unsupportedSchemaVersion(
                found: envelope.schemaVersion,
                supported: KeezlyVersions.schema
            )
        }

        let actual = Checksum.fnv1a(try GameStateCoding.makeEncoder().encode(envelope.record))
        guard actual == envelope.recordChecksum else {
            throw SerializationError.checksumMismatch(expected: envelope.recordChecksum, actual: actual)
        }

        // A history written under different rules would replay into a different
        // board, so it is refused rather than silently reinterpreted.
        guard envelope.rulesVersion == KeezlyVersions.rules else {
            throw SerializationError.unsupportedSchemaVersion(
                found: envelope.rulesVersion,
                supported: KeezlyVersions.rules
            )
        }

        return envelope.record
    }
}
