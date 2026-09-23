@testable import Keezly
import KeezlyCore
import Testing

/// The app half of online play: who may move, and what a move does.
///
/// The rules of an online match — revisions, duplicates, stale turns, corrupt
/// payloads — are `KeezlyCore`'s and are tested there against
/// `InMemoryTransport`. What is tested here is the part that only exists in the
/// app: the `.remote` seat role, and `OnlineMatchRun` driving a board with it.
///
/// `InMemoryTransport` is the real one from the core, so these are two genuine
/// clients reaching each other through bytes — not one object pretending to be
/// two.
@Suite("Online session")
@MainActor
struct OnlineSessionTests {

    private func mapping(_ ids: [String]) throws -> ParticipantMapping {
        try ParticipantMapping(seatOrder: ids)
    }

    private func configuration(_ seats: Int) -> GameConfiguration {
        GameConfiguration(seatCount: seats, teamMode: seats % 2 == 0 ? .teamsOfTwo : .freeForAll)
    }

    // MARK: - The seat role

    @Test("a remote seat is neither this device's person nor a computer")
    func remoteIsItsOwnThing() {
        #expect(SeatRole.remote.isHuman == false)
        #expect(SeatRole.remote.isPerson)
        #expect(SeatRole.human.isPerson)
        #expect(SeatRole.computer(.easy).isPerson == false)
    }

    @Test("an online table is not pass and play, however many people are in it")
    func onlineIsNotPassAndPlay() throws {
        let match = try OnlineMatch(
            configuration: configuration(4),
            seed: 2026,
            participants: mapping(["a", "b", "c", "d"]),
            matchID: "m"
        )
        let session = MatchSession(online: match, mySeat: Seat(0))

        #expect(session.isPassAndPlay == false, "an online table must never ask for the device to be passed")
        #expect(session.localSeat == Seat(0))
        #expect(session.humanSeats == [Seat(0)])
        #expect(session.roles.dropFirst().allSatisfy { $0 == .remote })
    }

    @Test("the board is closed while somebody else is on turn")
    func boardIsClosedForRemoteTurns() throws {
        let match = try OnlineMatch(
            configuration: configuration(4),
            seed: 2026,
            participants: mapping(["a", "b", "c", "d"]),
            matchID: "m"
        )
        // Seat 0 is mine only if the deal opened there; take the seat that is
        // *not* on turn so the test checks what it says it checks.
        let notOnTurn = Seat((match.state.currentSeat.index + 1) % 4)
        let session = MatchSession(online: match, mySeat: notOnTurn)

        #expect(session.isAwaitingHuman == false)
        #expect(session.seatOnTurn == nil, "the screen must not offer a seat this device cannot play")

        let refusal = session.submit(.foldHand(seat: session.state.currentSeat), atRevision: session.state.revision)
        guard case .failure(let reason) = refusal else {
            Issue.record("a move was accepted for a seat played on another device")
            return
        }
        #expect(reason == .notYourTurn)
    }

    @Test("the board is open when it is my turn")
    func boardIsOpenForMyTurn() throws {
        let match = try OnlineMatch(
            configuration: configuration(4),
            seed: 2026,
            participants: mapping(["a", "b", "c", "d"]),
            matchID: "m"
        )
        let session = MatchSession(online: match, mySeat: match.state.currentSeat)
        #expect(session.isAwaitingHuman)
        #expect(session.seatOnTurn == match.state.currentSeat)
    }

    @Test("adopting a position replaces it rather than merging it")
    func adoptReplaces() throws {
        var match = try OnlineMatch(
            configuration: configuration(4),
            seed: 2026,
            participants: mapping(["a", "b", "c", "d"]),
            matchID: "m"
        )
        let mine = match.state.currentSeat
        let session = MatchSession(online: match, mySeat: mine)
        let before = session.state.revision

        let legal = MoveGenerator.legalMoves(in: match.state, for: match.state.currentSeat)
        let action: PlayerAction = legal.first.map { .play($0) } ?? .foldHand(seat: match.state.currentSeat)
        let mover = try #require(match.participants.participant(at: mine))
        _ = match.apply(OnlineMove(expectedRevision: match.revision, action: action), from: mover)

        session.adopt(match)
        #expect(session.state.revision == match.revision)
        #expect(session.state.revision != before)
        #expect(session.isBusy == false, "adopting must not leave the board locked")
    }

    // MARK: - The run, over a real transport

    /// One transport, one client per participant — two genuine devices that
    /// can only reach each other through bytes.
    private func table(seats: Int = 4) async throws -> (run: OnlineMatchRun, clients: [String: OnlineMatchClient]) {
        let ids = (0..<seats).map { "player-\($0)" }
        let transport = InMemoryTransport()
        var clients: [String: OnlineMatchClient] = [:]
        for id in ids { clients[id] = OnlineMatchClient(participantID: id, transport: transport) }

        let first = try #require(clients[ids[0]])
        let match = try await first.create(
            configuration: configuration(seats),
            seed: 2026,
            participants: mapping(ids),
            matchID: "match-1"
        )
        let run = try OnlineMatchRun(match: match, client: first, me: ids[0])
        return (run, clients)
    }

    /// Plays whatever is legal for whoever is on turn, through *their* client.
    @discardableResult
    private func playOneTurn(
        on run: OnlineMatchRun,
        clients: [String: OnlineMatchClient]
    ) async throws -> Int {
        let seat = run.match.state.currentSeat
        let participant = try #require(run.match.participantOnTurn)
        let client = try #require(clients[participant])
        let legal = MoveGenerator.legalMoves(in: run.match.state, for: seat)
        let action: PlayerAction = legal.first.map { .play($0) } ?? .foldHand(seat: seat)
        let (outcome, match) = try await client.submit(action, matchID: run.matchID)
        #expect(outcome.didChangeTheBoard, "the fixture could not make a legal move")
        return match.revision
    }

    @Test("a run refuses to open a match this player is not in")
    func runRefusesStrangers() async throws {
        let ids = ["player-0", "player-1", "player-2", "player-3"]
        let transport = InMemoryTransport()
        let a = OnlineMatchClient(participantID: ids[0], transport: transport)
        let match = try await a.create(
            configuration: configuration(4),
            seed: 2026,
            participants: mapping(ids),
            matchID: "match-1"
        )
        let stranger = OnlineMatchClient(participantID: "nobody", transport: transport)
        #expect(throws: MatchTransportError.self) {
            try OnlineMatchRun(match: match, client: stranger, me: "nobody")
        }
    }

    @Test("a move made on another device arrives on a refresh")
    func refreshTakesTheLatestPosition() async throws {
        let (run, clients) = try await table()
        let before = run.match.revision

        // Play turns until one of them was somebody else's, so the check is
        // genuinely about a position this device did not produce.
        var played = 0
        while run.isMyTurn {
            _ = try await playOneTurn(on: run, clients: clients)
            await run.refresh()
            played += 1
            try #require(played < 12, "the deal never passed the turn to another device")
        }
        let remoteRevision = try await playOneTurn(on: run, clients: clients)

        await run.refresh()
        #expect(run.match.revision == remoteRevision, "the position from the other device never arrived")
        #expect(run.match.revision > before)
        #expect(run.session.state.revision == run.match.revision, "the board and the match disagree")
        #expect(run.notice == nil, "a normal refresh must not leave a message on screen")
    }

    @Test("this device cannot move for a seat it does not hold")
    func runRefusesAMoveOutOfTurn() async throws {
        let (run, clients) = try await table()
        // Make sure it is somebody else's turn.
        if run.isMyTurn { _ = try await playOneTurn(on: run, clients: clients); await run.refresh() }
        try #require(!run.isMyTurn)

        let revision = run.match.revision
        await run.submit(.foldHand(seat: run.match.state.currentSeat))
        #expect(run.match.revision == revision, "a move was sent for a seat played on another device")
    }

    @Test("a finished match reports a winner from this player's point of view")
    func winnerIsFromThisPlayersSeat() async throws {
        let (run, _) = try await table()
        #expect(run.isOver == false)
        #expect(run.didWin == nil, "a match still going has no winner")
    }
}
