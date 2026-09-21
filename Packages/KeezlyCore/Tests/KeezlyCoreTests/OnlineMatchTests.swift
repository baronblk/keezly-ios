import Foundation
@testable import KeezlyCore
import Testing

/// §28 — a match played across devices, with no second game model.
///
/// Every test here goes through bytes. Two clients never share an object;
/// whatever one knows, the other learns by loading what was sent. That is the
/// only way a synchronisation fault shows up in a test rather than in a game.
@Suite("Online match")
struct OnlineMatchTests {

    private func mapping(_ count: Int) throws -> ParticipantMapping {
        try ParticipantMapping(seatOrder: (0..<count).map { "player-\($0)" })
    }

    private func newMatch(seats: Int = 4, seed: UInt64 = 2026) throws -> OnlineMatch {
        try OnlineMatch(
            configuration: .standard(seatCount: seats),
            seed: seed,
            participants: mapping(seats),
            matchID: "match-1"
        )
    }

    /// A legal action for whoever is on turn.
    private func anyLegalAction(in match: OnlineMatch) -> PlayerAction {
        let seat = match.state.currentSeat
        let legal = MoveGenerator.legalMoves(in: match.state, for: seat)
        return legal.first.map { .play($0) } ?? .foldHand(seat: seat)
    }

    // MARK: - The mapping

    @Test("a seat is never inferred from an order")
    func mappingIsExplicit() throws {
        let map = try ParticipantMapping(seatOrder: ["alice", "bob", "carol", "dave"])
        #expect(map.seat(of: "carol") == Seat(2))
        #expect(map.participant(at: Seat(0)) == "alice")
        #expect(map.seat(of: "eve") == nil)
    }

    @Test("a mapping that cannot describe a table is refused")
    func mappingIsValidated() throws {
        #expect(throws: ParticipantMappingError.self) {
            try ParticipantMapping(seatOrder: ["alice", "alice"])
        }
        #expect(throws: ParticipantMappingError.self) {
            try ParticipantMapping(seatOrder: ["alice", ""])
        }
        #expect(throws: ParticipantMappingError.self) {
            try ParticipantMapping(seatOrder: []).validated(against: .standard(seatCount: 4))
        }
        #expect(throws: ParticipantMappingError.self) {
            try ParticipantMapping(seatOrder: ["a", "b"]).validated(against: .standard(seatCount: 4))
        }
    }

    @Test("teams come from the configuration, never from the participants")
    func teamsComeFromTheConfiguration() throws {
        let four = try newMatch(seats: 4)
        #expect(four.state.configuration.areAllied(Seat(0), Seat(2)))
        #expect(!four.state.configuration.areAllied(Seat(0), Seat(1)))

        let six = try newMatch(seats: 6)
        // Three pairs, each seat allied with the one opposite.
        #expect(six.state.configuration.teamCount == 3)
        #expect(six.state.configuration.areAllied(Seat(0), Seat(3)))
        #expect(six.state.configuration.areAllied(Seat(1), Seat(4)))
        #expect(!six.state.configuration.areAllied(Seat(0), Seat(1)))
        // The participants are still individuals — nothing about the mapping
        // says anything about sides.
        #expect(six.participants.seatOrder.count == 6)
    }

    // MARK: - Revisions and repeats

    @Test("a turn for the current position is applied")
    func currentTurnIsAccepted() throws {
        var match = try newMatch()
        let seat = match.state.currentSeat
        let before = match.revision

        let outcome = match.apply(
            OnlineMove(moveID: "m1", expectedRevision: before, action: anyLegalAction(in: match)),
            from: "player-\(seat.index)"
        )
        #expect(outcome == .accepted(resultingRevision: match.revision))
        #expect(match.revision > before)
        #expect(match.record.actionCount == 1)
    }

    @Test("the same turn arriving twice is recognised, not replayed")
    func duplicateIsRecognised() throws {
        var match = try newMatch()
        let seat = match.state.currentSeat
        let move = OnlineMove(moveID: "m1", expectedRevision: match.revision, action: anyLegalAction(in: match))

        _ = match.apply(move, from: "player-\(seat.index)")
        let revisionAfterFirst = match.revision
        let actionsAfterFirst = match.record.actionCount

        let second = match.apply(move, from: "player-\(seat.index)")
        #expect(second == .duplicate(resultingRevision: revisionAfterFirst))
        #expect(match.revision == revisionAfterFirst, "a repeat must not advance the board")
        #expect(match.record.actionCount == actionsAfterFirst, "a repeat must not be recorded twice")
    }

    @Test("a turn from an older board is stale, not applied to this one")
    func staleTurnIsRefused() throws {
        var match = try newMatch()
        let seat = match.state.currentSeat
        _ = match.apply(
            OnlineMove(moveID: "m1", expectedRevision: match.revision, action: anyLegalAction(in: match)),
            from: "player-\(seat.index)"
        )
        let now = match.revision

        let late = match.apply(
            OnlineMove(moveID: "m2", expectedRevision: now - 1, action: anyLegalAction(in: match)),
            from: "player-\(match.state.currentSeat.index)"
        )
        #expect(late == .stale(localRevision: now, expected: now - 1))
        #expect(match.revision == now)
    }

    @Test("a turn expecting a newer board is out of order, not applied")
    func outOfOrderTurnIsRefused() throws {
        var match = try newMatch()
        let now = match.revision
        let early = match.apply(
            OnlineMove(moveID: "m9", expectedRevision: now + 1, action: anyLegalAction(in: match)),
            from: "player-\(match.state.currentSeat.index)"
        )
        #expect(early == .outOfOrder(localRevision: now, expected: now + 1))
        #expect(match.record.actionCount == 0)
    }

    @Test("somebody else's turn is refused")
    func wrongSeatIsRefused() throws {
        var match = try newMatch()
        let onTurn = match.state.currentSeat.index
        let other = (onTurn + 1) % 4

        let outcome = match.apply(
            OnlineMove(moveID: "m1", expectedRevision: match.revision, action: anyLegalAction(in: match)),
            from: "player-\(other)"
        )
        #expect(outcome == .rejected(.notYourSeat(seat: other, onTurn: onTurn)))
    }

    @Test("somebody who is not in the match is refused")
    func strangerIsRefused() throws {
        var match = try newMatch()
        let outcome = match.apply(
            OnlineMove(moveID: "m1", expectedRevision: match.revision, action: anyLegalAction(in: match)),
            from: "someone-else"
        )
        #expect(outcome == .rejected(.notAParticipant))
    }

    @Test("an illegal move is refused even when everything else is right")
    func illegalMoveIsRefused() throws {
        var match = try newMatch()
        let seat = match.state.currentSeat
        // Folding is only legal with no playable card; a fresh deal has one.
        let outcome = match.apply(
            OnlineMove(moveID: "m1", expectedRevision: match.revision, action: .foldHand(seat: seat)),
            from: "player-\(seat.index)"
        )
        if case .rejected(.illegal) = outcome {
            #expect(match.record.actionCount == 0)
        } else {
            Issue.record("expected the engine to refuse the fold, got \(outcome)")
        }
    }

    // MARK: - What travels

    @Test("a match survives the journey unchanged")
    func envelopeRoundTrips() throws {
        var match = try newMatch()
        for _ in 0..<12 {
            let seat = match.state.currentSeat
            _ = match.apply(
                OnlineMove(expectedRevision: match.revision, action: anyLegalAction(in: match)),
                from: "player-\(seat.index)"
            )
        }

        let arrived = try OnlineMatchEnvelope.load(OnlineMatchEnvelope.encode(match))
        #expect(arrived.revision == match.revision)
        #expect(arrived.state.pawns == match.state.pawns)
        #expect(arrived.state.hands == match.state.hands)
        #expect(arrived.record.actions == match.record.actions)
        #expect(arrived.participants == match.participants)
        #expect(arrived.lastMoveID == match.lastMoveID)
    }

    @Test("encoding is stable across a round trip")
    func encodingIsStable() throws {
        var match = try newMatch()
        for _ in 0..<8 {
            _ = match.apply(
                OnlineMove(expectedRevision: match.revision, action: anyLegalAction(in: match)),
                from: "player-\(match.state.currentSeat.index)"
            )
        }
        let first = try OnlineMatchEnvelope.encode(match)
        let second = try OnlineMatchEnvelope.encode(OnlineMatchEnvelope.load(first))
        #expect(first == second)
    }

    @Test("a payload that was altered in transit is refused")
    func alteredPayloadIsRefused() throws {
        var match = try newMatch()
        _ = match.apply(
            OnlineMove(expectedRevision: match.revision, action: anyLegalAction(in: match)),
            from: "player-\(match.state.currentSeat.index)"
        )
        var data = try OnlineMatchEnvelope.encode(match)
        data[data.count / 2] = data[data.count / 2] &+ 1
        #expect(throws: OnlineMatchError.self) { try OnlineMatchEnvelope.load(data) }
    }

    @Test("a payload claiming the wrong revision is refused")
    func forgedRevisionIsRefused() throws {
        let match = try newMatch()
        var json = try #require(
            try JSONSerialization.jsonObject(with: OnlineMatchEnvelope.canonical(match)) as? [String: Any]
        )
        json["currentRevision"] = 99
        let forged = try OnlineMatchEnvelope.compress(
            JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        )
        #expect(throws: OnlineMatchError.self) { try OnlineMatchEnvelope.load(forged) }
    }

    @Test("a payload from a newer version is refused, not reinterpreted")
    func newerSchemaIsRefused() throws {
        let match = try newMatch()
        var json = try #require(
            try JSONSerialization.jsonObject(with: OnlineMatchEnvelope.canonical(match)) as? [String: Any]
        )
        json["schemaVersion"] = KeezlyVersions.schema + 1
        let future = try OnlineMatchEnvelope.compress(
            JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        )
        #expect(throws: OnlineMatchError.self) { try OnlineMatchEnvelope.load(future) }
    }

    @Test("a payload whose seats do not match its table is refused")
    func wrongMappingIsRefused() throws {
        let match = try newMatch(seats: 4)
        var json = try #require(
            try JSONSerialization.jsonObject(with: OnlineMatchEnvelope.canonical(match)) as? [String: Any]
        )
        json["participants"] = ["seatOrder": ["a", "b"]]
        let wrong = try OnlineMatchEnvelope.compress(
            JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        )
        #expect(throws: (any Error).self) { try OnlineMatchEnvelope.load(wrong) }
    }

    // MARK: - The information boundary

    @Test("the online layer shows a player only their own hand")
    func onlineLayerKeepsTheBoundary() throws {
        let match = try newMatch()
        let observation = match.observation(for: Seat(0))

        // The same guarantee as a local match: one hand, and for everybody
        // else a *count* and nothing more. The envelope has to carry the seed
        // and the moves for the position to be reproducible at all — which is
        // exactly why the online layer must hand an agent an observation and
        // never a match (DEC-014).
        #expect(observation.seat == Seat(0))
        #expect(observation.hand == match.state.hand(of: Seat(0)))
        #expect(observation.handCounts.count == 4)
        for seat in 1..<4 {
            #expect(observation.handCounts[seat] == match.state.hand(of: Seat(seat)).count)
        }
        // The cards themselves are not reachable: `unseenCards` is what an
        // agent may reason about, and it holds every card it has not seen —
        // its own hand and the discards removed, not one opponent's hand
        // singled out.
        let unseen = observation.unseenCards
        for seat in 1..<4 where !match.state.hand(of: Seat(seat)).cards.isEmpty {
            let theirs = Set(match.state.hand(of: Seat(seat)).cards)
            #expect(theirs.isSubset(of: Set(unseen)), "an opponent's cards must be indistinguishable from the rest")
        }
    }
}
