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
    /// Identifies this match for as long as it exists, across saves and
    /// restores. A string rather than a Swift hash: hashes are not stable
    /// between processes, let alone between builds.
    public let matchID: String
    public let configuration: GameConfiguration
    public let seed: UInt64
    /// When the match was dealt, in whole seconds since the epoch.
    ///
    /// Seconds, not a `Date`: a fixed integer encodes the same way on every
    /// platform and in every locale, and nothing here needs more precision.
    public let createdAt: Int
    /// When an action was last added.
    public private(set) var updatedAt: Int
    public private(set) var actions: [PlayerAction]
    /// Where the match stands. Set from the validated state, never guessed.
    public private(set) var status: MatchStatus
    /// The outcome, once there is one.
    public private(set) var result: GameResult?

    public init(
        configuration: GameConfiguration,
        seed: UInt64,
        actions: [PlayerAction] = [],
        matchID: String = UUID().uuidString,
        createdAt: Int = Clock.now(),
        updatedAt: Int? = nil,
        status: MatchStatus = .active,
        result: GameResult? = nil
    ) {
        self.matchID = matchID
        self.configuration = configuration
        self.seed = seed
        self.actions = actions
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.status = status
        self.result = result
    }

    public var actionCount: Int { actions.count }

    /// The rules this match is played under. Part of the configuration, named
    /// here because a record is refused if they are not the current ones.
    public var ruleSet: RuleSet { configuration.ruleSet }

    public mutating func append(_ action: PlayerAction) {
        actions.append(action)
        updatedAt = Clock.now()
    }

    /// Records where the match stands, taken from a state the engine produced.
    ///
    /// Called with the validated state rather than inferred from the action
    /// count, so the stored status can never disagree with the position.
    public mutating func note(_ state: GameState) {
        result = state.result
        status = state.result == nil ? .active : .completed
        updatedAt = Clock.now()
    }

    /// Marks a match the player walked away from.
    public mutating func abandon() {
        guard status == .active else { return }
        status = .abandoned
        updatedAt = Clock.now()
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

/// Where a match stands.
public enum MatchStatus: String, Hashable, Sendable, Codable {
    /// Still being played.
    case active
    /// Somebody won.
    case completed
    /// The player walked away from it.
    case abandoned
}

/// The one place a wall-clock reading enters the engine.
///
/// Whole seconds, and overridable, so a test can produce a record byte for
/// byte identical to another. Nothing in the rules reads it — it exists for
/// the list of matches to continue, not for the game.
public enum Clock {
    nonisolated(unsafe) public static var reading: @Sendable () -> Int = {
        Int(Date().timeIntervalSince1970)
    }

    public static func now() -> Int { reading() }
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
    /// How many actions the record holds, and the revision the state was at
    /// when it was written. Both are checked on restore: a record that replays
    /// to a different revision is not this match.
    public let currentRevision: Int
    /// The checksum of the position the record replays to.
    ///
    /// Optional in the sense that a restore can be attempted without it, but
    /// always written: it is the difference between "the actions were all
    /// legal" and "the actions produce exactly the board that was saved".
    public let finalStateChecksum: UInt64
    public let recordChecksum: UInt64
    public let record: MatchRecord

    public init(record: MatchRecord, finalState: GameState) throws {
        self.schemaVersion = KeezlyVersions.schema
        self.engineVersion = KeezlyVersions.engine
        self.rulesVersion = KeezlyVersions.rules
        self.currentRevision = finalState.revision
        self.finalStateChecksum = try GameStateCoding.checksum(of: finalState)
        self.recordChecksum = Checksum.fnv1a(try GameStateCoding.makeEncoder().encode(record))
        self.record = record
    }

    public static func encode(_ record: MatchRecord, finalState: GameState) throws -> Data {
        try GameStateCoding.makeEncoder().encode(MatchRecordEnvelope(record: record, finalState: finalState))
    }

    /// Convenience for a record that is not being restored from — it replays
    /// to find its own final state, which is fine for a test or a one-off but
    /// wasteful for an autosave, where the caller already holds the state.
    public static func encode(_ record: MatchRecord) throws -> Data {
        try encode(record, finalState: record.finalState())
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

    // MARK: - Restore

    /// Rebuilds a match from stored bytes, or refuses.
    ///
    /// Every step is a check, and the order matters: nothing is replayed until
    /// the bytes are known to be intact, and nothing is handed back until the
    /// replay has produced exactly the position that was saved. A half-restored
    /// match is never returned — a partly-correct board that play continues
    /// from is worse than no saved match at all.
    public static func restore(_ data: Data) throws -> MatchRestoration {
        let envelope: MatchRecordEnvelope
        do {
            envelope = try GameStateCoding.makeDecoder().decode(MatchRecordEnvelope.self, from: data)
        } catch {
            throw MatchRestoreError.corrupted(reason: String(describing: error))
        }

        guard envelope.schemaVersion <= KeezlyVersions.schema else {
            throw MatchRestoreError.unsupportedSchema(
                found: envelope.schemaVersion,
                supported: KeezlyVersions.schema
            )
        }
        guard envelope.rulesVersion == KeezlyVersions.rules else {
            throw MatchRestoreError.unsupportedRules(
                found: envelope.rulesVersion,
                supported: KeezlyVersions.rules
            )
        }

        let actual = Checksum.fnv1a(try GameStateCoding.makeEncoder().encode(envelope.record))
        guard actual == envelope.recordChecksum else {
            throw MatchRestoreError.recordChecksumMismatch(expected: envelope.recordChecksum, actual: actual)
        }

        // Replayed through the real engine, action by action. Every one is
        // validated again — a stored action is not trusted simply because it
        // was stored.
        var state = envelope.record.initialState
        var lastRevision = state.revision
        for (index, action) in envelope.record.actions.enumerated() {
            let transition: GameTransition
            do {
                transition = try GameReducer.apply(action, to: state)
            } catch {
                throw MatchRestoreError.illegalAction(index: index, reason: String(describing: error))
            }
            state = transition.state
            guard state.revision > lastRevision else {
                throw MatchRestoreError.revisionNotMonotonic(atAction: index, revision: state.revision)
            }
            lastRevision = state.revision
        }

        guard state.revision == envelope.currentRevision else {
            throw MatchRestoreError.revisionMismatch(expected: envelope.currentRevision, actual: state.revision)
        }

        let replayedChecksum = try GameStateCoding.checksum(of: state)
        guard replayedChecksum == envelope.finalStateChecksum else {
            throw MatchRestoreError.stateChecksumMismatch(
                expected: envelope.finalStateChecksum,
                actual: replayedChecksum
            )
        }

        return MatchRestoration(record: envelope.record, state: state)
    }
}

/// A match rebuilt from storage, with the position it replayed to.
public struct MatchRestoration: Sendable {
    public let record: MatchRecord
    public let state: GameState
}

/// Why a stored match could not be restored.
///
/// Every case is a refusal, never a repair. A match whose history does not
/// reproduce its position is not this match, and continuing from a guess would
/// be worse than losing it (§57).
public enum MatchRestoreError: Error, Hashable, Sendable, LocalizedError {
    case corrupted(reason: String)
    case unsupportedSchema(found: Int, supported: Int)
    case unsupportedRules(found: Int, supported: Int)
    case recordChecksumMismatch(expected: UInt64, actual: UInt64)
    case illegalAction(index: Int, reason: String)
    case revisionNotMonotonic(atAction: Int, revision: Int)
    case revisionMismatch(expected: Int, actual: Int)
    case stateChecksumMismatch(expected: UInt64, actual: UInt64)

    public var errorDescription: String? {
        switch self {
        case .corrupted(let reason):
            "The saved match could not be read (\(reason))."
        case .unsupportedSchema(let found, let supported):
            "The saved match was written by a newer version of Keezly (format \(found), this build reads \(supported))."
        case .unsupportedRules(let found, let supported):
            "The saved match was played under different rules (\(found), this build plays \(supported))."
        case .recordChecksumMismatch:
            "The saved match is damaged."
        case .illegalAction(let index, let reason):
            "Move \(index + 1) of the saved match is not legal (\(reason))."
        case .revisionNotMonotonic(let index, let revision):
            "The saved match does not move forward at move \(index + 1) (revision \(revision))."
        case .revisionMismatch(let expected, let actual):
            "The saved match replays to a different point (expected \(expected), got \(actual))."
        case .stateChecksumMismatch:
            "The saved match replays to a different board than the one that was saved."
        }
    }
}
