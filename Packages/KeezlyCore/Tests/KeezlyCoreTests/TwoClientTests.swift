import Foundation
@testable import KeezlyCore
import Testing

/// §28 — two devices, playing the same match.
///
/// The point of this suite is what it refuses to do: the two clients share no
/// object, no state and no engine. Everything one knows, the other learns by
/// loading bytes from the transport. A synchronisation fault therefore shows
/// up here rather than between two phones a fortnight before release.
@Suite("Two clients")
struct TwoClientTests {

    private func seatOrder(_ count: Int) -> [String] {
        (0..<count).map { "player-\($0)" }
    }

    /// A match in the transport, with a client for every seat.
    private func table(
        seats: Int = 4,
        seed: UInt64 = 2026,
        matchID: String = "match-1"
    ) async throws -> (transport: InMemoryTransport, clients: [OnlineMatchClient]) {
        let transport = InMemoryTransport()
        let clients = seatOrder(seats).map { OnlineMatchClient(participantID: $0, transport: transport) }
        _ = try await clients[0].create(
            configuration: .standard(seatCount: seats),
            seed: seed,
            participants: try ParticipantMapping(seatOrder: seatOrder(seats)),
            matchID: matchID
        )
        return (transport, clients)
    }

    private func legalAction(in match: OnlineMatch) -> PlayerAction {
        let seat = match.state.currentSeat
        let legal = MoveGenerator.legalMoves(in: match.state, for: seat)
        return legal.first.map { .play($0) } ?? .foldHand(seat: seat)
    }

    /// Plays whoever's turn it is, from that player's own client.
    @discardableResult
    private func playCurrentTurn(
        _ clients: [OnlineMatchClient],
        matchID: String,
        moveID: String = UUID().uuidString
    ) async throws -> (outcome: TurnOutcome, match: OnlineMatch) {
        let seen = try await clients[0].load(matchID: matchID)
        let seat = seen.state.currentSeat
        return try await clients[seat.index].submit(
            legalAction(in: seen),
            matchID: matchID,
            moveID: moveID
        )
    }

    // MARK: - The basic exchange

    @Test("what one client plays, another sees exactly")
    func aTurnCrossesTheGap() async throws {
        let (_, clients) = try await table()

        let (outcome, played) = try await playCurrentTurn(clients, matchID: "match-1")
        #expect(outcome.didChangeTheBoard)

        // Loaded by a different client, from bytes. Nothing was shared.
        let seenByAnother = try await clients[1].load(matchID: "match-1")
        #expect(seenByAnother.revision == played.revision)
        #expect(seenByAnother.state.pawns == played.state.pawns)
        #expect(seenByAnother.state.hands == played.state.hands)
        #expect(seenByAnother.record.actions == played.record.actions)
    }

    @Test("a match stays identical across many turns and many clients")
    func manyTurnsStayInStep() async throws {
        let (_, clients) = try await table()

        for turn in 0..<24 {
            let (outcome, played) = try await playCurrentTurn(
                clients,
                matchID: "match-1",
                moveID: "turn-\(turn)"
            )
            guard outcome.didChangeTheBoard else {
                Issue.record("turn \(turn) was refused: \(outcome)")
                return
            }

            // Every client, every turn. Any divergence is caught the moment it
            // appears rather than at the end, when it would be hard to place.
            for client in clients {
                let seen = try await client.load(matchID: "match-1")
                #expect(seen.revision == played.revision, "client \(client.participantID) at turn \(turn)")
                #expect(try GameStateCoding.checksum(of: seen.state)
                    == GameStateCoding.checksum(of: played.state))
            }
        }
    }

    @Test("the turn passes to the player whose seat it is")
    func theTurnPassesToTheRightPlayer() async throws {
        let (transport, clients) = try await table()

        for _ in 0..<8 {
            let before = try await clients[0].load(matchID: "match-1")
            let expectedNext = try #require(before.participants.participant(at: before.state.currentSeat))
            #expect(await transport.participantOnTurn(in: "match-1") == expectedNext)

            _ = try await playCurrentTurn(clients, matchID: "match-1")
        }
    }

    // MARK: - Things that go wrong between devices

    @Test("a client that plays on a board it has already lost is stale")
    func aClientPlayingOnAnOldBoardIsRefused() async throws {
        let (_, clients) = try await table()

        // One client looks at the board and does not act yet.
        let stale = try await clients[0].load(matchID: "match-1")
        let staleRevision = stale.revision

        // Somebody else moves in the meantime.
        _ = try await playCurrentTurn(clients, matchID: "match-1", moveID: "first")

        // Now the first client submits against the revision it remembers.
        let seat = stale.state.currentSeat
        let (outcome, _) = try await clients[seat.index].submit(
            legalAction(in: stale),
            matchID: "match-1",
            moveID: "late",
            expectedRevision: staleRevision
        )
        if case .stale = outcome {
            // The transport must not have been written to.
            let current = try await clients[1].load(matchID: "match-1")
            #expect(current.record.actionCount == 1, "a stale turn must not reach the other devices")
        } else {
            Issue.record("expected a stale turn, got \(outcome)")
        }
    }

    @Test("the same turn delivered twice changes the board once")
    func aRedeliveredTurnIsIdempotent() async throws {
        let (transport, clients) = try await table()

        let (_, afterFirst) = try await playCurrentTurn(clients, matchID: "match-1", moveID: "only-once")
        let deliveries = await transport.deliveries.count

        // The callback arrives again with the same payload — the classic
        // Game Center re-delivery. Loading it must not move anything on.
        let payload = try await transport.load(matchID: "match-1")
        let again = try clients[1].receive(payload)
        #expect(again.revision == afterFirst.revision)
        #expect(again.record.actionCount == afterFirst.record.actionCount)
        #expect(again.lastMoveID == "only-once")

        // And submitting the identical move again is recognised as the same
        // move rather than played a second time.
        let seat = afterFirst.state.currentSeat
        let (outcome, _) = try await clients[seat.index].submit(
            legalAction(in: afterFirst),
            matchID: "match-1",
            moveID: "only-once",
            expectedRevision: afterFirst.revision
        )
        #expect(outcome == .duplicate(resultingRevision: afterFirst.revision))
        #expect(await transport.deliveries.count == deliveries, "a duplicate must not be sent on")
    }

    @Test("a payload damaged in transit is refused by the receiver")
    func damagedPayloadIsRefusedOnArrival() async throws {
        let (transport, clients) = try await table()
        _ = try await playCurrentTurn(clients, matchID: "match-1")

        var payload = try await transport.load(matchID: "match-1")
        payload[payload.count / 2] = payload[payload.count / 2] &+ 1
        await transport.corrupt(matchID: "match-1", with: payload)

        await #expect(throws: OnlineMatchError.self) {
            try await clients[1].load(matchID: "match-1")
        }
    }

    // MARK: - Leaving, and winning

    @Test("a player who quits a partners match loses it for their side")
    func quittingCostsTheTeamTheMatch() async throws {
        let (_, clients) = try await table(seats: 4)
        let before = try await clients[0].load(matchID: "match-1")
        let quitter = before.state.currentSeat

        let (outcome, after) = try await clients[quitter.index].submit(
            .resign(seat: quitter),
            matchID: "match-1"
        )
        #expect(outcome.didChangeTheBoard)

        // The policy is the engine's, not the online layer's — which is the
        // point. Whatever resigning means, it means the same thing offline.
        let result = try #require(after.state.result)
        let quittersTeam = after.state.configuration.team(of: quitter)
        #expect(result.winningTeam != quittersTeam, "the side that quit must not win")
        #expect(!result.winningSeats.contains(quitter))
        #expect(result.wonByDefault, "a win after a resignation is a win by default (§30)")
    }

    @Test("a finished match is ended for everybody")
    func aFinishedMatchIsClosed() async throws {
        let (transport, clients) = try await table(seats: 4)
        let before = try await clients[0].load(matchID: "match-1")
        let quitter = before.state.currentSeat

        _ = try await clients[quitter.index].submit(.resign(seat: quitter), matchID: "match-1")

        #expect(await transport.isOver("match-1"), "a finished match must not wait for another turn")
        let final = try await clients[1].load(matchID: "match-1")
        #expect(final.record.status == .completed)
        #expect(final.state.result != nil)
    }

    @Test("a turn sent to a finished match is refused")
    func noTurnsAfterTheEnd() async throws {
        let (_, clients) = try await table(seats: 4)
        let before = try await clients[0].load(matchID: "match-1")
        let quitter = before.state.currentSeat
        _ = try await clients[quitter.index].submit(.resign(seat: quitter), matchID: "match-1")

        let finished = try await clients[0].load(matchID: "match-1")
        var copy = finished
        let outcome = copy.apply(
            OnlineMove(expectedRevision: finished.revision, action: legalAction(in: finished)),
            from: "player-0"
        )
        #expect(outcome == .rejected(.matchFinished))
    }

    // MARK: - More than one match at a time

    @Test("a client can hold several matches at once without confusing them")
    func matchesAreKeptApart() async throws {
        let transport = InMemoryTransport()
        let alice = OnlineMatchClient(participantID: "player-0", transport: transport)
        let bob = OnlineMatchClient(participantID: "player-1", transport: transport)
        let mapping = try ParticipantMapping(seatOrder: ["player-0", "player-1", "player-2", "player-3"])

        for (index, id) in ["first", "second", "third"].enumerated() {
            _ = try await alice.create(
                configuration: .standard(seatCount: 4),
                seed: UInt64(100 + index),
                participants: mapping,
                matchID: id
            )
        }

        // A turn in one match must leave the others exactly as they were.
        let firstBefore = try await bob.load(matchID: "first")
        let secondBefore = try await bob.load(matchID: "second")
        let seat = secondBefore.state.currentSeat
        let players = [alice, bob, OnlineMatchClient(participantID: "player-2", transport: transport),
                       OnlineMatchClient(participantID: "player-3", transport: transport)]
        _ = try await players[seat.index].submit(legalAction(in: secondBefore), matchID: "second")

        #expect(try await bob.load(matchID: "first").revision == firstBefore.revision)
        #expect(try await bob.load(matchID: "second").revision > secondBefore.revision)
        #expect(try await alice.matches().sorted() == ["first", "second", "third"])
    }

    // MARK: - Closing the app

    @Test("a match survives every device forgetting it")
    func nothingIsHeldBetweenTurns() async throws {
        let transport = InMemoryTransport()
        let mapping = try ParticipantMapping(seatOrder: seatOrder(4))
        _ = try await OnlineMatchClient(participantID: "player-0", transport: transport).create(
            configuration: .standard(seatCount: 4),
            seed: 77,
            participants: mapping,
            matchID: "match-1"
        )

        // Every turn is taken by a *newly built* client, as if the app had
        // been closed and reopened between each one. Nothing may depend on
        // anything a client remembered (§27).
        for turn in 0..<10 {
            let looker = OnlineMatchClient(participantID: "player-0", transport: transport)
            let seen = try await looker.load(matchID: "match-1")
            let seat = seen.state.currentSeat

            let mover = OnlineMatchClient(participantID: "player-\(seat.index)", transport: transport)
            let (outcome, _) = try await mover.submit(
                legalAction(in: seen),
                matchID: "match-1",
                moveID: "turn-\(turn)"
            )
            #expect(outcome.didChangeTheBoard, "turn \(turn): \(outcome)")
        }

        let final = try await OnlineMatchClient(participantID: "player-2", transport: transport)
            .load(matchID: "match-1")
        #expect(final.record.actionCount == 10)
    }

    // MARK: - How big it gets

    @Test("a long six-player match still fits in a Game Center payload")
    func payloadStaysWithinBudget() async throws {
        let (transport, clients) = try await table(seats: 6, seed: 4242, matchID: "long")

        var turns = 0
        while turns < 400 {
            let seen = try await clients[0].load(matchID: "long")
            guard seen.state.result == nil else { break }
            let seat = seen.state.currentSeat
            let (outcome, _) = try await clients[seat.index].submit(
                legalAction(in: seen),
                matchID: "long",
                moveID: "t\(turns)"
            )
            guard outcome.didChangeTheBoard else { break }
            turns += 1
        }

        let payload = try await transport.load(matchID: "long")
        let final = try OnlineMatchEnvelope.load(payload)
        #expect(final.record.actionCount > 100, "the fixture did not produce a long match")

        // Game Center allows 64 KiB of match data. Measured rather than
        // assumed: if a full action log ever stops fitting, the answer is a
        // more compact encoding or checkpoints — decided on this number, not
        // guessed at in advance (§28).
        let limit = 64 * 1024
        print("MEASURE online payload: \(final.record.actionCount) moves, \(payload.count) bytes of \(limit)")
        #expect(
            payload.count < limit,
            "\(final.record.actionCount) moves came to \(payload.count) bytes of \(limit)"
        )
    }
}
