import Foundation

/// One turn, as it travels between devices.
///
/// The three fields that make a turn safe to receive twice: what it is, what
/// it expected the board to be, and a name of its own (§28).
public struct OnlineMove: Hashable, Sendable, Codable {
    /// Unique to this move, chosen by the device that made it. The only way to
    /// tell a re-delivered turn from a new one that happens to look the same.
    public let moveID: String
    /// The revision the player was looking at when they moved.
    public let expectedRevision: Int
    public let action: PlayerAction

    public init(moveID: String = UUID().uuidString, expectedRevision: Int, action: PlayerAction) {
        self.moveID = moveID
        self.expectedRevision = expectedRevision
        self.action = action
    }
}

/// What happened to a submitted turn.
///
/// Every case is a distinct situation with a distinct answer. Collapsing them
/// into "worked" and "did not" is how an online board game acquires a habit of
/// losing or repeating moves.
public enum TurnOutcome: Hashable, Sendable {
    /// Applied. The board is now at this revision.
    case accepted(resultingRevision: Int)
    /// This exact move has already been applied — a re-delivered callback, not
    /// a new turn. The board is untouched and already at this revision.
    case duplicate(resultingRevision: Int)
    /// The mover was looking at an older board. Their move is not valid for
    /// this position and is discarded, not applied to a different one.
    case stale(localRevision: Int, expected: Int)
    /// The mover was looking at a *newer* board than this device has. Something
    /// has been missed; the answer is to fetch, not to apply.
    case outOfOrder(localRevision: Int, expected: Int)
    /// The move was for this position and still could not be played.
    case rejected(OnlineRejection)

    public var didChangeTheBoard: Bool {
        if case .accepted = self { return true }
        return false
    }
}

/// Why a turn that was current was still refused.
public enum OnlineRejection: Hashable, Sendable {
    /// The participant who sent it does not hold a seat in this match.
    case notAParticipant
    /// It is somebody else's turn.
    case notYourSeat(seat: Int, onTurn: Int)
    /// The match is over.
    case matchFinished
    /// The engine refused the action.
    case illegal(String)
}

/// A match being played across devices.
///
/// Holds no state of its own beyond the engine's: the position is whatever the
/// recorded actions replay to, exactly as it is for a local match (DEC-023).
/// There is no second game model and no online engine — only a wrapper that
/// says who may move and what to do with a turn that arrives twice.
public struct OnlineMatch: Sendable {
    public private(set) var record: MatchRecord
    public private(set) var state: GameState
    public let participants: ParticipantMapping
    /// The move that produced the current position, if a move did.
    public private(set) var lastMoveID: String?

    public init(
        configuration: GameConfiguration,
        seed: UInt64,
        participants: ParticipantMapping,
        matchID: String = UUID().uuidString
    ) throws {
        self.participants = try participants.validated(against: configuration)
        record = MatchRecord(configuration: configuration, seed: seed, matchID: matchID)
        state = record.initialState
        lastMoveID = nil
    }

    init(record: MatchRecord, state: GameState, participants: ParticipantMapping, lastMoveID: String?) {
        self.record = record
        self.state = state
        self.participants = participants
        self.lastMoveID = lastMoveID
    }

    public var matchID: String { record.matchID }
    public var revision: Int { state.revision }
    public var currentSeat: Seat { state.currentSeat }

    /// Whose turn it is, as a participant.
    public var participantOnTurn: String? { participants.participant(at: state.currentSeat) }

    /// What a given player is allowed to know.
    ///
    /// The online layer hands this out and nothing else. An agent still sees
    /// only an observation, exactly as in a local match — the envelope carries
    /// the seed and the moves because determinism requires it, and neither is
    /// ever passed to a player (DEC-014).
    public func observation(for seat: Seat) -> PlayerObservation {
        PlayerObservation(of: state, for: seat)
    }

    // MARK: - Taking a turn

    /// Applies a turn, or says precisely why it did not.
    ///
    /// The order of the checks matters. Identity first — a re-delivered turn
    /// must be recognised before its revision makes it look stale. Then
    /// position, then seat, then the engine.
    public mutating func apply(_ move: OnlineMove, from participant: String) -> TurnOutcome {
        if move.moveID == lastMoveID {
            return .duplicate(resultingRevision: state.revision)
        }
        if move.expectedRevision < state.revision {
            return .stale(localRevision: state.revision, expected: move.expectedRevision)
        }
        if move.expectedRevision > state.revision {
            return .outOfOrder(localRevision: state.revision, expected: move.expectedRevision)
        }
        guard state.result == nil else {
            return .rejected(.matchFinished)
        }
        guard let seat = participants.seat(of: participant) else {
            return .rejected(.notAParticipant)
        }
        guard seat == state.currentSeat else {
            return .rejected(.notYourSeat(seat: seat.index, onTurn: state.currentSeat.index))
        }

        let transition: GameTransition
        do {
            transition = try GameReducer.apply(move.action, to: state)
        } catch {
            return .rejected(.illegal(String(describing: error)))
        }

        state = transition.state
        record.append(move.action)
        record.note(transition.state)
        lastMoveID = move.moveID
        return .accepted(resultingRevision: state.revision)
    }
}
