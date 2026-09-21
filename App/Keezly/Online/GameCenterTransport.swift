import Foundation
import GameKit
import KeezlyCore

/// The one place in Keezly that knows Game Center exists.
///
/// `KeezlyCore` never imports GameKit; every rule about turns, revisions,
/// duplicates and validation lives there and is tested against
/// `InMemoryTransport`. This file's whole job is to turn those calls into
/// `GKTurnBasedMatch` ones. If it is wrong, the rules are still right — which
/// is the point of putting the boundary here (§28).
///
/// **Not verified.** Nothing here has been run against Game Center: that needs
/// an App Store Connect record for the bundle id, which does not exist yet
/// (MAN-02, MAN-05). It is written, it compiles, and it is the only part of
/// the online path that no test covers. Treated as unproven until a real match
/// has been played through it.
struct GameCenterTransport: MatchTransport {
    /// How long to wait for the next player before the turn times out.
    ///
    /// A week: Keezly is asynchronous by design (§27), and a board game played
    /// over a fortnight is a normal thing, not a stalled one.
    var turnTimeout: TimeInterval = 7 * 24 * 60 * 60

    func create(
        _ data: Data,
        matchID: String,
        participants: [String],
        firstParticipant: String
    ) async throws {
        // Game Center creates the match and assigns its own identifier; the
        // Keezly match id travels *inside* the payload. Matching them up is
        // the adapter's problem, not the engine's.
        let request = GKMatchRequest()
        request.minPlayers = participants.count
        request.maxPlayers = participants.count

        let match = try await GKTurnBasedMatch.find(for: request)
        guard let next = participant(firstParticipant, in: match) else {
            throw MatchTransportError.notAParticipant(matchID)
        }
        try await match.endTurn(
            withNextParticipants: [next],
            turnTimeout: turnTimeout,
            match: data
        )
    }

    func load(matchID: String) async throws -> Data {
        let match = try await find(matchID)
        guard let data = match.matchData else {
            throw MatchTransportError.unavailable(reason: "the match has no data yet")
        }
        return data
    }

    func send(_ data: Data, matchID: String, nextParticipant: String) async throws {
        let match = try await find(matchID)
        guard let next = participant(nextParticipant, in: match) else {
            throw MatchTransportError.notAParticipant(matchID)
        }
        try await match.endTurn(
            withNextParticipants: [next],
            turnTimeout: turnTimeout,
            match: data
        )
    }

    func end(_ data: Data, matchID: String) async throws {
        let match = try await find(matchID)
        // Every participant's outcome has to be set, or Game Center leaves the
        // match hanging for them. The result itself comes from the payload —
        // the engine decided it, not this layer.
        let outcomes = try outcomes(for: data, in: match)
        for participant in match.participants {
            participant.matchOutcome = outcomes[participant.player?.gamePlayerID ?? ""] ?? .tied
        }
        try await match.endMatchInTurn(withMatch: data)
    }

    func matches(for participant: String) async throws -> [String] {
        try await GKTurnBasedMatch.loadMatches().compactMap { match in
            guard let data = match.matchData, !data.isEmpty else { return nil }
            // The Keezly identifier is in the payload, so a match that will
            // not load is not listed rather than listed wrongly.
            return try? OnlineMatchEnvelope.load(data).matchID
        }
    }

    // MARK: - Helpers

    private func find(_ matchID: String) async throws -> GKTurnBasedMatch {
        for match in try await GKTurnBasedMatch.loadMatches() {
            guard let data = match.matchData,
                  let loaded = try? OnlineMatchEnvelope.load(data),
                  loaded.matchID == matchID
            else { continue }
            return match
        }
        throw MatchTransportError.noSuchMatch(matchID)
    }

    private func participant(_ id: String, in match: GKTurnBasedMatch) -> GKTurnBasedParticipant? {
        match.participants.first { $0.player?.gamePlayerID == id }
    }

    /// Who won, taken from the match itself rather than decided here.
    private func outcomes(for data: Data, in match: GKTurnBasedMatch) throws -> [String: GKTurnBasedMatch.Outcome] {
        let loaded = try OnlineMatchEnvelope.load(data)
        guard let result = loaded.state.result else { return [:] }

        var outcomes: [String: GKTurnBasedMatch.Outcome] = [:]
        for participant in match.participants {
            guard let playerID = participant.player?.gamePlayerID,
                  let seat = loaded.participants.seat(of: playerID)
            else { continue }
            outcomes[playerID] = result.winningSeats.contains(seat) ? .won : .lost
        }
        return outcomes
    }
}
