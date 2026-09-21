import Foundation

/// One device's view of the online matches it is in.
///
/// Holds no match between calls. Every operation loads the match, checks it,
/// acts and sends it on — which is what a turn-based game over Game Center
/// actually is: the app may be closed between any two turns, and the next
/// player may be on the other side of the world a day later (§27).
///
/// Two clients are two of these with different `participantID`s and nothing
/// shared but the transport. That is how the online rules are tested: not one
/// object pretending to be two, but two that can only reach each other through
/// bytes.
public struct OnlineMatchClient: Sendable {
    public let participantID: String
    private let transport: any MatchTransport

    public init(participantID: String, transport: any MatchTransport) {
        self.participantID = participantID
        self.transport = transport
    }

    /// Starts a match and puts it where the others can find it.
    public func create(
        configuration: GameConfiguration,
        seed: UInt64,
        participants: ParticipantMapping,
        matchID: String = UUID().uuidString
    ) async throws -> OnlineMatch {
        let match = try OnlineMatch(
            configuration: configuration,
            seed: seed,
            participants: participants,
            matchID: matchID
        )
        // Told, not guessed: the match may open on any seat, depending on
        // where the deal put the dealer.
        guard let first = match.participantOnTurn else {
            throw MatchTransportError.unavailable(reason: "no seat is on turn")
        }
        try await transport.create(
            OnlineMatchEnvelope.encode(match),
            matchID: matchID,
            participants: participants.seatOrder,
            firstParticipant: first
        )
        return match
    }

    /// Fetches a match and validates it before returning it.
    public func load(matchID: String) async throws -> OnlineMatch {
        try OnlineMatchEnvelope.load(try await transport.load(matchID: matchID))
    }

    public func matches() async throws -> [String] {
        try await transport.matches(for: participantID)
    }

    /// Plays a turn: load, apply, send on.
    ///
    /// The match is loaded rather than remembered, so a device that has been
    /// closed, or that missed a turn, works from what everybody else has
    /// rather than from what it last saw. The outcome says exactly what
    /// happened, including when nothing did.
    @discardableResult
    public func submit(
        _ action: PlayerAction,
        matchID: String,
        moveID: String = UUID().uuidString,
        expectedRevision: Int? = nil
    ) async throws -> (outcome: TurnOutcome, match: OnlineMatch) {
        var match = try await load(matchID: matchID)
        let move = OnlineMove(
            moveID: moveID,
            expectedRevision: expectedRevision ?? match.revision,
            action: action
        )
        let outcome = match.apply(move, from: participantID)

        // Only a turn that changed the board is worth sending. Sending after a
        // duplicate or a stale move would overwrite a good position with an
        // identical one at best, and with an older one at worst.
        guard outcome.didChangeTheBoard else { return (outcome, match) }

        let data = try OnlineMatchEnvelope.encode(match)
        if match.state.result == nil {
            guard let next = match.participantOnTurn else {
                throw MatchTransportError.unavailable(reason: "no seat is on turn")
            }
            try await transport.send(data, matchID: matchID, nextParticipant: next)
        } else {
            try await transport.end(data, matchID: matchID)
        }
        return (outcome, match)
    }

    /// Applies a turn that arrived from elsewhere.
    ///
    /// Used when a callback hands over the payload directly rather than the
    /// device fetching it. The payload is validated exactly as a fetched one
    /// is — arriving through a callback does not make it trustworthy.
    public func receive(_ data: Data) throws -> OnlineMatch {
        try OnlineMatchEnvelope.load(data)
    }
}
