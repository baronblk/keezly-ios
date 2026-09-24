import Foundation
@testable import Keezly
import KeezlyCore
import Testing

/// Achievements in a Game Center match.
///
/// The owner's decision, taken after the assumption behind the old behaviour
/// was shown not to hold: an online seat belongs to exactly one authenticated
/// account, so the attribution problem that keeps pass & play silent does not
/// exist here. What does exist is **repetition**, and that is what most of this
/// suite is about.
///
/// A local match finishes while this device watches, once. An online match
/// arrives already finished — the opponent's winning move lands while the app
/// is closed — and is then handed to this device again on every refresh, every
/// foreground and every reopen. So reporting cannot hang on the moment of
/// finishing, and instead has to ask "is it over, and has it been accounted
/// for?".
///
/// No leaderboards are involved and none are implied (DEC-025). Nothing here
/// claims anything about a modified client: an online match is played on
/// trust, which is written down rather than defended against.
@Suite("Online achievements")
@MainActor
struct OnlineAchievementTests {

    /// Stands in for Game Center. Records every set it was handed.
    final class Spy: AchievementReporting, @unchecked Sendable {
        private(set) var reports: [Set<Achievement>] = []
        func start() {}
        func report(_ achievements: Set<Achievement>) { reports.append(achievements) }

        var everyAchievementReported: Set<Achievement> {
            reports.reduce(into: Set<Achievement>()) { $0.formUnion($1) }
        }
    }

    // MARK: - Building a real, finished online match

    private func mapping(_ ids: [String]) throws -> ParticipantMapping {
        try ParticipantMapping(seatOrder: ids)
    }

    /// A match played to its end through `OnlineMatch.apply`, which is the same
    /// path a real turn takes — the engine decides, the record grows, and the
    /// status becomes `.completed` because the position says so.
    ///
    /// Not a hand-built record: `AchievementEvaluator` replays what it is
    /// given, so a fixture that skipped the engine would be testing itself.
    private func finishedMatch(
        seats: Int = 4,
        seed: UInt64 = 2026,
        matchID: String = "match-1",
        limit: Int = 4000
    ) throws -> OnlineMatch {
        let ids = (0..<seats).map { "player-\($0)" }
        var match = try OnlineMatch(
            configuration: GameConfiguration(
                seatCount: seats,
                teamMode: seats.isMultiple(of: 2) && seats >= 4 ? .teamsOfTwo : .freeForAll
            ),
            seed: seed,
            participants: mapping(ids),
            matchID: matchID
        )

        var turn = 0
        while match.state.result == nil, turn < limit {
            let seat = match.state.currentSeat
            let legal = MoveGenerator.legalMoves(in: match.state, for: seat)
            let action: PlayerAction = legal.first.map { .play($0) } ?? .foldHand(seat: seat)
            let mover = try #require(match.participants.participant(at: seat))
            let outcome = match.apply(
                OnlineMove(moveID: "t\(turn)", expectedRevision: match.revision, action: action),
                from: mover
            )
            guard case .accepted = outcome else {
                Issue.record("the match stopped being playable at turn \(turn): \(outcome)")
                break
            }
            turn += 1
        }
        return match
    }

    private func run(
        _ match: OnlineMatch,
        seat: Seat,
        spy: Spy,
        ledger: InMemoryAchievementLedger
    ) throws -> OnlineMatchRun {
        let me = try #require(match.participants.participant(at: seat))
        return try OnlineMatchRun(
            match: match,
            client: OnlineMatchClient(participantID: me, transport: InMemoryTransport()),
            me: me,
            achievements: spy,
            ledger: ledger
        )
    }

    // MARK: - It reports at all

    @Test("a finished online match reports what the local seat earned")
    func finishedOnlineMatchReports() throws {
        let match = try finishedMatch()
        try #require(match.state.result != nil, "the fixture never finished, so there is nothing to report")

        let spy = Spy()
        let mine = Seat(0)
        let session = MatchSession(
            online: match,
            mySeat: mine,
            achievements: spy,
            ledger: InMemoryAchievementLedger()
        )
        session.reportAchievementsIfFinished()

        #expect(spy.reports.count == 1)
        #expect(spy.reports.first == AchievementEvaluator.unlocked(in: match.record, for: mine))
        #expect(spy.everyAchievementReported.contains(.finished), "everyone who played one out gets this")
    }

    @Test("the seat that is reported for is this device's seat, at every seat",
          arguments: [0, 1, 2, 3])
    func reportsForTheLocalSeatOnly(index: Int) throws {
        let match = try finishedMatch()
        try #require(match.state.result != nil)

        let mine = Seat(index)
        let spy = Spy()
        let session = MatchSession(
            online: match,
            mySeat: mine,
            achievements: spy,
            ledger: InMemoryAchievementLedger()
        )
        session.reportAchievementsIfFinished()

        #expect(session.localSeat == mine)
        #expect(spy.reports.first == AchievementEvaluator.unlocked(in: match.record, for: mine))
    }

    // MARK: - It never reports for the opponent

    /// The rule the owner set out in so many words. Stated as a property over
    /// the whole table rather than as one example: whatever a seat earned, the
    /// only set that ever reaches Game Center from this device is that seat's.
    @Test("nothing another seat earned is ever reported from this device")
    func neverReportsForAnOpponent() throws {
        let match = try finishedMatch()
        try #require(match.state.result != nil)

        for index in 0..<4 {
            let mine = Seat(index)
            let spy = Spy()
            let session = MatchSession(
                online: match,
                mySeat: mine,
                achievements: spy,
                ledger: InMemoryAchievementLedger()
            )
            session.reportAchievementsIfFinished()

            let mineEarned = AchievementEvaluator.unlocked(in: match.record, for: mine)
            #expect(spy.everyAchievementReported == mineEarned)

            // And specifically: anything an opponent earned that this seat did
            // not must not be in there.
            for other in (0..<4).map(Seat.init) where other != mine {
                let theirs = AchievementEvaluator.unlocked(in: match.record, for: other)
                let onlyTheirs = theirs.subtracting(mineEarned)
                #expect(
                    spy.everyAchievementReported.isDisjoint(with: onlyTheirs),
                    "seat \(index) was credited with something only seat \(other.index) earned"
                )
            }
        }
    }

    /// The one achievement whose owner is unambiguous, used as a sharp check on
    /// the general rule above: only the winning seats may be told they won.
    @Test("only a seat that actually won is told it won")
    func onlyTheWinnerIsToldTheyWon() throws {
        let match = try finishedMatch()
        let result = try #require(match.state.result)

        for index in 0..<4 {
            let mine = Seat(index)
            let spy = Spy()
            let session = MatchSession(
                online: match,
                mySeat: mine,
                achievements: spy,
                ledger: InMemoryAchievementLedger()
            )
            session.reportAchievementsIfFinished()

            #expect(
                spy.everyAchievementReported.contains(.won) == result.winningSeats.contains(mine),
                "seat \(index) was told the wrong thing about winning"
            )
        }
    }

    // MARK: - It reports once, and only once

    @Test("a match that is already over when the screen opens still reports")
    func alreadyFinishedOnFirstOpenStillReports() throws {
        // The ordinary case in a turn-based game: the opponent played the
        // winning move while the app was closed, so this device never sees the
        // match change. Reporting only on a change would report nothing.
        let match = try finishedMatch()
        try #require(match.state.result != nil)

        let spy = Spy()
        let run = try run(match, seat: Seat(0), spy: spy, ledger: InMemoryAchievementLedger())

        #expect(run.isOver)
        #expect(spy.reports.count == 1, "a match that arrived finished was never reported")
    }

    @Test("refreshing a finished match again reports nothing more")
    func repeatedAdoptReportsOnce() throws {
        let match = try finishedMatch()
        try #require(match.state.result != nil)

        let spy = Spy()
        let mine = Seat(0)
        let session = MatchSession(
            online: match,
            mySeat: mine,
            achievements: spy,
            ledger: InMemoryAchievementLedger()
        )
        session.reportAchievementsIfFinished()

        // Every foreground, every refresh, every reopened screen.
        for _ in 0..<10 {
            session.adopt(match)
        }

        #expect(spy.reports.count == 1, "the same finished match was reported \(spy.reports.count) times")
    }

    /// Resume. The app was killed and started again, so the session is new and
    /// remembers nothing — only the ledger survives, and it is what has to
    /// carry the guarantee.
    @Test("reopening the same match in a new session reports nothing more")
    func resumeReportsOnce() throws {
        let match = try finishedMatch()
        try #require(match.state.result != nil)

        let spy = Spy()
        let ledger = InMemoryAchievementLedger()

        _ = try run(match, seat: Seat(0), spy: spy, ledger: ledger)
        #expect(spy.reports.count == 1)

        // Killed, relaunched, opened again — three times over.
        for _ in 0..<3 {
            _ = try run(match, seat: Seat(0), spy: spy, ledger: ledger)
        }

        #expect(spy.reports.count == 1, "resuming a finished match awarded it again")
    }

    @Test("a different match is still reported after the first one was")
    func theLedgerDoesNotSwallowEverything() throws {
        let spy = Spy()
        let ledger = InMemoryAchievementLedger()

        let first = try finishedMatch(seed: 2026, matchID: "match-1")
        let second = try finishedMatch(seed: 99, matchID: "match-2")
        try #require(first.state.result != nil)
        try #require(second.state.result != nil)
        try #require(first.matchID != second.matchID)

        _ = try run(first, seat: Seat(0), spy: spy, ledger: ledger)
        _ = try run(second, seat: Seat(0), spy: spy, ledger: ledger)

        #expect(spy.reports.count == 2, "the ledger blocked a match it had never seen")
    }

    @Test("a match still being played reports nothing")
    func unfinishedReportsNothing() throws {
        let match = try OnlineMatch(
            configuration: GameConfiguration(seatCount: 4, teamMode: .teamsOfTwo),
            seed: 2026,
            participants: mapping(["a", "b", "c", "d"]),
            matchID: "open"
        )
        let spy = Spy()
        let run = try run(match, seat: Seat(0), spy: spy, ledger: InMemoryAchievementLedger())

        #expect(run.isOver == false)
        #expect(spy.reports.isEmpty)
    }

    // MARK: - The same conditions as a local match

    /// The owner asked for the *same* conditions, not a second set of rules for
    /// online. There is only one evaluator and this pins that: what an online
    /// seat is credited with is exactly what the same record and the same seat
    /// would earn anywhere else.
    @Test("an online seat earns exactly what the evaluator says, with no online-only extras")
    func sameConditionsAsLocal() throws {
        let match = try finishedMatch()
        try #require(match.state.result != nil)

        for index in 0..<4 {
            let seat = Seat(index)
            let session = MatchSession(
                online: match,
                mySeat: seat,
                achievements: Spy(),
                ledger: InMemoryAchievementLedger()
            )
            #expect(session.achievementsEarned == AchievementEvaluator.unlocked(in: match.record, for: seat))
        }
    }

    @Test("an online table is never treated as pass and play")
    func onlineIsNeverPassAndPlay() throws {
        let match = try finishedMatch()
        let session = MatchSession(
            online: match,
            mySeat: Seat(1),
            achievements: Spy(),
            ledger: InMemoryAchievementLedger()
        )
        #expect(session.isPassAndPlay == false)
        #expect(session.humanSeats == [Seat(1)])
        #expect(session.roles.enumerated().allSatisfy { $0.offset == 1 || $0.element == .remote })
    }

    // MARK: - A session with no reporter stays silent

    @Test("a session built without a reporter touches nothing")
    func noReporterNoReport() throws {
        let match = try finishedMatch()
        let session = MatchSession(online: match, mySeat: Seat(0))
        session.reportAchievementsIfFinished()
        // Nothing to assert against but the absence of a crash and the absence
        // of a ledger write — the point is that the defaults are safe, because
        // every screenshot and test session uses them.
        #expect(session.achievements == nil)
    }
}

/// The ledger on its own, away from any match.
@Suite("Achievement ledger")
@MainActor
struct AchievementLedgerTests {

    private func emptyDefaults(_ name: String) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("a match is unknown until it is marked, and known afterwards")
    func marksAndRemembers() throws {
        let ledger = StoredAchievementLedger(defaults: try emptyDefaults("keezly.test.ledger.1"))
        #expect(ledger.hasAccountedFor(matchID: "m") == false)
        ledger.markAccountedFor(matchID: "m")
        #expect(ledger.hasAccountedFor(matchID: "m"))
        #expect(ledger.hasAccountedFor(matchID: "other") == false)
    }

    @Test("marking the same match twice does not store it twice")
    func markingIsIdempotent() throws {
        let defaults = try emptyDefaults("keezly.test.ledger.2")
        let ledger = StoredAchievementLedger(defaults: defaults)
        ledger.markAccountedFor(matchID: "m")
        ledger.markAccountedFor(matchID: "m")
        #expect(defaults.stringArray(forKey: StoredAchievementLedger.key) == ["m"])
    }

    /// It survives the process. A new instance over the same storage is what a
    /// relaunch looks like from here, and the whole resume guarantee rests on
    /// this one property.
    @Test("a new ledger over the same storage still knows")
    func survivesARelaunch() throws {
        let defaults = try emptyDefaults("keezly.test.ledger.3")
        StoredAchievementLedger(defaults: defaults).markAccountedFor(matchID: "m")
        #expect(StoredAchievementLedger(defaults: defaults).hasAccountedFor(matchID: "m"))
    }

    @Test("the list is bounded, and it is the oldest that goes")
    func isBounded() throws {
        let defaults = try emptyDefaults("keezly.test.ledger.4")
        let ledger = StoredAchievementLedger(defaults: defaults)
        for index in 0..<(StoredAchievementLedger.limit + 5) {
            ledger.markAccountedFor(matchID: "m\(index)")
        }
        let stored = defaults.stringArray(forKey: StoredAchievementLedger.key) ?? []
        #expect(stored.count == StoredAchievementLedger.limit)
        #expect(stored.first == "m5", "the oldest entries should be the ones dropped")
        #expect(ledger.hasAccountedFor(matchID: "m0") == false)
        #expect(ledger.hasAccountedFor(matchID: "m\(StoredAchievementLedger.limit + 4)"))
    }
}
