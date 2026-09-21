import Foundation
@testable import Keezly
import KeezlyCore
import Testing

/// §57 — a saved match is its starting conditions plus the accepted actions.
/// These tests are about the two things that follow from that: it must come
/// back *exactly*, and when it cannot, it must refuse rather than guess.
@Suite("Match store")
struct MatchStoreTests {

    /// A store of its own per test, so nothing here can touch a real save.
    private func freshStore() -> MatchStore {
        MatchStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("keezly-tests-\(UUID().uuidString)", isDirectory: true))
    }

    private func roles(seats: Int, people: Int = 1) -> [SeatRole] {
        (0..<seats).map { $0 < people ? .human : .computer(.medium) }
    }

    /// Plays a match out with legal moves, chosen deterministically.
    private func played(
        seats: Int,
        teams: TeamMode? = nil,
        seed: UInt64 = 2026,
        moves: Int
    ) throws -> (record: MatchRecord, state: GameState) {
        let configuration = GameConfiguration(
            seatCount: seats,
            teamMode: teams ?? GameConfiguration.standard(seatCount: seats).teamMode
        )
        var recorder = MatchRecorder(configuration: configuration, seed: seed)
        var chooser = SeededGenerator(seed: seed &+ 0xA11)

        for _ in 0..<moves where recorder.state.result == nil {
            let seat = recorder.state.currentSeat
            let legal = MoveGenerator.legalMoves(in: recorder.state, for: seat)
            let action: PlayerAction = legal.isEmpty
                ? .foldHand(seat: seat)
                : .play(legal[Int.random(in: 0..<legal.count, using: &chooser)])
            try recorder.apply(action)
        }

        var record = recorder.record
        record.note(recorder.state)
        return (record, recorder.state)
    }

    // MARK: - It comes back exactly

    @Test("a match saved and reopened is the same match", arguments: 2...6)
    func roundTripsForEveryTableSize(seats: Int) throws {
        let store = freshStore()
        let (record, state) = try played(seats: seats, moves: 40)
        try store.save(record: record, state: state, roles: roles(seats: seats))

        let restored = try store.restore(matchID: record.matchID)

        // Compared on the position, not on the bytes: the claim is that the
        // *game* came back, and the position is the game.
        #expect(restored.state.pawns == state.pawns)
        #expect(restored.state.revision == state.revision)
        #expect(restored.state.currentSeat == state.currentSeat)
        #expect(restored.state.deck == state.deck)
        #expect(restored.state.discardPile == state.discardPile)
        #expect(restored.record.actions == record.actions)
        #expect(restored.record.matchID == record.matchID)
    }

    @Test("a four-player partners match keeps its sides")
    func teamModeSurvives() throws {
        let store = freshStore()
        let (record, state) = try played(seats: 4, teams: .teamsOfTwo, moves: 30)
        try store.save(record: record, state: state, roles: roles(seats: 4))

        let restored = try store.restore(matchID: record.matchID)
        #expect(restored.state.configuration.teamMode == .teamsOfTwo)
        #expect(restored.state.configuration.areAllied(Seat(0), Seat(2)))
    }

    @Test("a free-for-all match does not come back as partners")
    func freeForAllSurvives() throws {
        let store = freshStore()
        let (record, state) = try played(seats: 4, teams: .freeForAll, moves: 30)
        try store.save(record: record, state: state, roles: roles(seats: 4))
        #expect(try store.restore(matchID: record.matchID).state.configuration.teamMode == .freeForAll)
    }

    @Test("who was playing comes back with the match", arguments: 1...4)
    func rolesSurvive(people: Int) throws {
        let store = freshStore()
        let (record, state) = try played(seats: 4, moves: 20)
        let roles = roles(seats: 4, people: people)
        try store.save(record: record, state: state, roles: roles)

        #expect(try store.restore(matchID: record.matchID).roles == roles)
    }

    @Test("a match saved before anybody has moved comes back")
    func openingPositionSurvives() throws {
        let store = freshStore()
        let (record, state) = try played(seats: 4, moves: 0)
        #expect(record.actionCount == 0)
        try store.save(record: record, state: state, roles: roles(seats: 4))

        let restored = try store.restore(matchID: record.matchID)
        // The deal is part of the position, so it has to survive too.
        #expect(restored.state.hands == state.hands)
        #expect(restored.state.deck == state.deck)
    }

    @Test("a finished match is stored as finished")
    func completedMatchIsMarked() throws {
        let store = freshStore()
        // Long enough for a four-player match to reach an end.
        let (record, state) = try played(seats: 4, moves: 4_000)
        try #require(state.result != nil, "the fixture did not finish a match")
        try store.save(record: record, state: state, roles: roles(seats: 4))

        let restored = try store.restore(matchID: record.matchID)
        #expect(restored.record.status == .completed)
        #expect(restored.record.result == state.result)
        #expect(restored.state.result == state.result)
        // It must not be offered as a match to continue.
        #expect(store.mostRecentActive() == nil)
    }

    @Test("a match walked away from is marked, not lost")
    func abandonedMatchIsMarked() throws {
        let store = freshStore()
        let played = try played(seats: 3, moves: 20)
        var record = played.record
        let state = played.state
        record.abandon()
        try store.save(record: record, state: state, roles: roles(seats: 3))

        #expect(try store.restore(matchID: record.matchID).record.status == .abandoned)
        #expect(store.mostRecentActive() == nil)
        #expect(store.list().count == 1, "an abandoned match is still there, just not offered")
    }

    // MARK: - Encoding is stable

    @Test("encoding, decoding and replaying leaves the bytes unchanged")
    func encodingIsStable() throws {
        let (record, state) = try played(seats: 4, moves: 50)
        let first = try MatchRecordEnvelope.encode(record, finalState: state)

        let restored = try MatchRecordEnvelope.restore(first)
        let second = try MatchRecordEnvelope.encode(restored.record, finalState: restored.state)

        // Byte-for-byte, not merely equivalent. A format that re-encodes
        // differently cannot be compared, and a checksum over it would be
        // worthless (DEC-009).
        #expect(first == second)
    }

    @Test("the saved position is the one the actions produce")
    func replayReachesTheSavedPosition() throws {
        let (record, state) = try played(seats: 5, moves: 60)
        let data = try MatchRecordEnvelope.encode(record, finalState: state)
        let restored = try MatchRecordEnvelope.restore(data)

        #expect(try GameStateCoding.checksum(of: restored.state) == GameStateCoding.checksum(of: state))
    }

    // MARK: - It refuses rather than guesses

    @Test("damaged bytes are refused")
    func damagedDataIsRefused() throws {
        let store = freshStore()
        let (record, state) = try played(seats: 4, moves: 20)
        try store.save(record: record, state: state, roles: roles(seats: 4))

        let file = store.directory.appendingPathComponent("\(record.matchID).keezly")
        var bytes = try Data(contentsOf: file)
        bytes[bytes.count / 2] = bytes[bytes.count / 2] &+ 1
        try bytes.write(to: file)

        #expect(throws: (any Error).self) { try store.restore(matchID: record.matchID) }
    }

    @Test("a file that is not a saved match is refused")
    func rubbishIsRefused() throws {
        let store = freshStore()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("not a match".utf8).write(
            to: store.directory.appendingPathComponent("nonsense.keezly")
        )

        #expect(throws: (any Error).self) { try store.restore(matchID: "nonsense") }
        // A broken file must not stop the others being listed.
        #expect(store.list().isEmpty)
    }

    @Test("a match from a newer version is refused, not reinterpreted")
    func newerSchemaIsRefused() throws {
        let (record, state) = try played(seats: 4, moves: 10)
        var data = try MatchRecordEnvelope.encode(record, finalState: state)
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Issue.record("the envelope is not an object")
            return
        }
        json["schemaVersion"] = KeezlyVersions.schema + 1
        data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])

        #expect(throws: MatchRestoreError.self) { try MatchRecordEnvelope.restore(data) }
    }

    @Test("a history that does not reach its saved position is refused")
    func truncatedHistoryIsRefused() throws {
        let (record, state) = try played(seats: 4, moves: 30)
        // The record loses its last move while the envelope still claims the
        // position that move produced. Replay is then legal but arrives
        // somewhere else — exactly the case a checksum over the actions alone
        // would miss.
        let shortened = MatchRecord(
            configuration: record.configuration,
            seed: record.seed,
            actions: Array(record.actions.dropLast()),
            matchID: record.matchID,
            createdAt: record.createdAt
        )
        let envelope = try MatchRecordEnvelope(record: record, finalState: state)
        let forged = try MatchRecordEnvelope(record: shortened, finalState: state)

        #expect(envelope.currentRevision == forged.currentRevision)
        let data = try GameStateCoding.makeEncoder().encode(forged)
        #expect(throws: MatchRestoreError.self) { try MatchRecordEnvelope.restore(data) }
    }

    @Test("an opponent this version does not have is refused")
    func unknownOpponentIsRefused() throws {
        let store = freshStore()
        let (record, state) = try played(seats: 4, moves: 10)
        try store.save(record: record, state: state, roles: roles(seats: 4))

        let file = store.directory.appendingPathComponent("\(record.matchID).keezly")
        let text = try String(contentsOf: file, encoding: .utf8)
            .replacingOccurrences(of: "\"medium\"", with: "\"telepathic\"")
        try Data(text.utf8).write(to: file)

        #expect(throws: (any Error).self) { try store.restore(matchID: record.matchID) }
    }

    @Test("a refused match is kept aside rather than deleted")
    func refusedMatchIsQuarantined() throws {
        let store = freshStore()
        let (record, state) = try played(seats: 4, moves: 10)
        try store.save(record: record, state: state, roles: roles(seats: 4))

        let kept = store.quarantine(matchID: record.matchID)
        #expect(kept != nil, "the file was not kept")
        #expect(FileManager.default.fileExists(atPath: kept?.path ?? ""))
        #expect(store.list().isEmpty, "a quarantined match must not be offered")
    }

    // MARK: - The list

    @Test("a match can be listed without replaying it")
    func summaryDescribesTheMatch() throws {
        let store = freshStore()
        let (record, state) = try played(seats: 6, moves: 35)
        try store.save(record: record, state: state, roles: roles(seats: 6, people: 3))

        let summary = try #require(store.list().first)
        #expect(summary.matchID == record.matchID)
        #expect(summary.seatCount == 6)
        #expect(summary.peopleCount == 3)
        #expect(summary.isPassAndPlay)
        #expect(summary.currentSeat == state.currentSeat.index)
        #expect(summary.round == state.deal.roundIndex + 1)
        #expect(summary.revision == state.revision)
        #expect(summary.status == .active)
    }

    @Test("the most recent unfinished match is the one offered")
    func mostRecentActiveIsOffered() throws {
        let store = freshStore()
        let older = try played(seats: 4, seed: 1, moves: 10)
        let newer = try played(seats: 3, seed: 2, moves: 10)

        Clock.reading = { 1_000 }
        var olderRecord = older.record
        olderRecord.note(older.state)
        try store.save(record: olderRecord, state: older.state, roles: roles(seats: 4))

        Clock.reading = { 2_000 }
        var newerRecord = newer.record
        newerRecord.note(newer.state)
        try store.save(record: newerRecord, state: newer.state, roles: roles(seats: 3))
        Clock.reading = { Int(Date().timeIntervalSince1970) }

        #expect(store.mostRecentActive()?.matchID == newerRecord.matchID)
        #expect(store.list().map(\.matchID) == [newerRecord.matchID, olderRecord.matchID])
    }
}

/// §57 — the parts of resuming that only a running session can answer.
@Suite("Resuming a match")
@MainActor
struct MatchResumeTests {

    private func freshStore() -> MatchStore {
        MatchStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("keezly-resume-\(UUID().uuidString)", isDirectory: true))
    }

    private func roles(seats: Int, people: Int = 1) -> [SeatRole] {
        (0..<seats).map { $0 < people ? .human : .computer(.easy) }
    }

    /// Plays a session the way the app does — through `submit` — so what is
    /// saved is what a real match would have saved.
    private func play(_ session: MatchSession, moves: Int) {
        for _ in 0..<moves {
            guard session.result == nil, session.isAwaitingHuman else { break }
            let legal = session.legalMoves
            guard let move = legal.first else {
                session.submit(.foldHand(seat: session.state.currentSeat), atRevision: session.state.revision)
                session.animationsFinished()
                continue
            }
            session.submit(.play(move), atRevision: session.state.revision)
            session.animationsFinished()
        }
    }

    @Test("a session saves itself as it is played, and comes back")
    func aPlayedSessionComesBack() throws {
        let store = freshStore()
        let session = MatchSession(
            configuration: .standard(seatCount: 4),
            seed: 2026,
            roles: roles(seats: 4),
            store: store
        )
        session.persistOpening()
        play(session, moves: 6)

        #expect(session.saveFailure == nil, "the match was not being saved")
        let restored = try store.restore(matchID: session.record.matchID)
        #expect(restored.state.revision == session.state.revision)
        #expect(restored.state.pawns == session.state.pawns)
        #expect(restored.record.actionCount == session.record.actionCount)
    }

    @Test("resuming does not replay an action that was already taken")
    func resumingDoesNotDuplicateActions() throws {
        let store = freshStore()
        let first = MatchSession(
            configuration: .standard(seatCount: 4),
            seed: 7,
            roles: roles(seats: 4),
            store: store
        )
        first.persistOpening()
        play(first, moves: 4)
        let actionsWhenSaved = first.record.actionCount

        let resumed = MatchSession(restored: try store.restore(matchID: first.record.matchID), store: store)

        // Restoring is not playing. The computer opponents must not run, and
        // nothing must be appended, until the screen says to begin.
        #expect(resumed.record.actionCount == actionsWhenSaved)
        #expect(resumed.state.revision == first.state.revision)
        #expect(!resumed.isBusy)
    }

    @Test("a resumed match carries on and can be finished")
    func aResumedMatchCanBeFinished() throws {
        let store = freshStore()
        let first = MatchSession(
            configuration: .standard(seatCount: 4),
            seed: 99,
            roles: [.human, .human, .human, .human],
            store: store
        )
        first.persistOpening()
        play(first, moves: 30)
        try #require(first.result == nil, "the fixture finished before it was saved")

        var session = MatchSession(restored: try store.restore(matchID: first.record.matchID), store: store)
        // Played on in chunks, restoring between them, so the match is carried
        // across a restore more than once rather than only at the start.
        for _ in 0..<40 where session.result == nil {
            play(session, moves: 50)
            session = MatchSession(restored: try store.restore(matchID: session.record.matchID), store: store)
        }

        #expect(session.result != nil, "the match never finished")
        #expect(session.record.status == .completed)
        let reopened = try store.restore(matchID: session.record.matchID)
        #expect(reopened.record.result == session.result)
        #expect(reopened.state.result == session.result)
    }

    @Test("restoring a long six-player match is quick")
    func restoringALongMatchIsQuick() throws {
        let store = freshStore()
        let session = MatchSession(
            configuration: .standard(seatCount: 6),
            seed: 4242,
            roles: (0..<6).map { _ in SeatRole.human },
            store: store
        )
        session.persistOpening()
        play(session, moves: 600)
        let actions = session.record.actionCount
        try #require(actions > 200, "the fixture did not produce a long match (\(actions) actions)")

        let started = Date()
        let restored = try store.restore(matchID: session.record.matchID)
        let seconds = Date().timeIntervalSince(started)

        #expect(restored.state.revision == session.state.revision)
        // A generous bound, checked rather than assumed: the whole case for
        // storing a seed and a list of actions instead of board snapshots is
        // that replaying them is cheap. If this ever stops being true, the
        // answer is measured checkpoints — not a guess made in advance.
        #expect(seconds < 2.0, "restoring \(actions) actions took \(seconds)s")
    }
}
