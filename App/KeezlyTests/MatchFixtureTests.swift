@testable import Keezly
import KeezlyCore
import Testing

/// §87 — a screenshot fixture is only worth having if it reliably reaches the
/// situation it names, and reaches the *same* one every run.
@Suite("Match fixtures")
@MainActor
struct MatchFixtureTests {

    private func session(
        seats: Int = 4,
        seed: UInt64,
        fixture: MatchFixture? = nil,
        limit: Int = 600
    ) -> MatchSession {
        MatchSession(
            configuration: .standard(seatCount: seats),
            seed: seed,
            roles: [.human] + Array(repeating: SeatRole.computer(.medium), count: seats - 1),
            fixture: fixture,
            fixtureLimit: limit
        )
    }

    @Test("no fixture leaves the match at the opening deal")
    func noFixtureDoesNothing() {
        let match = session(seed: 2026)
        #expect(match.fixtureReached == nil)
        #expect(match.record.actions.isEmpty)
        #expect(match.state.pawns.allSatisfy { $0.isWaiting })
    }

    @Test("a move count is played out exactly")
    func movesPlayedIsExact() {
        let match = session(seed: 2026, fixture: .movesPlayed(20))
        #expect(match.fixtureReached == true)
        #expect(match.record.actions.count == 20)
    }

    @Test("the Jack fixture stops with a playable Jack in the local hand")
    func jackFixtureArrives() {
        let match = session(seed: 2026, fixture: .localCanPlay(.jack))
        #expect(match.fixtureReached == true)
        #expect(match.state.currentSeat == Seat(0))

        let swaps = MoveGenerator.legalMoves(in: match.state, for: Seat(0))
            .filter { $0.card.rank == .jack }
        #expect(!swaps.isEmpty, "the point of the fixture is a Jack with somewhere to go")
        #expect(swaps.allSatisfy { if case .swap = $0.action { true } else { false } })
    }

    @Test("the Seven fixture stops with a Seven that can genuinely be split")
    func sevenFixtureArrives() {
        let match = session(seed: 2026, fixture: .localCanPlay(.seven))
        #expect(match.fixtureReached == true)
        #expect(match.state.currentSeat == Seat(0))

        let splits = MoveGenerator.legalMoves(in: match.state, for: Seat(0))
            .compactMap { move -> [SplitStep]? in
                guard move.card.rank == .seven, case .split(let steps) = move.action else { return nil }
                return steps
            }
        // A single-leg Seven shows none of the split interface, so the fixture
        // must find one actually spread across two pawns.
        #expect(splits.contains { $0.count > 1 })
        #expect(splits.allSatisfy { $0.reduce(0) { $0 + $1.steps } == 7 })
    }

    @Test("the same seed and fixture produce the same board every run")
    func fixturesAreDeterministic() {
        let first = session(seed: 2026, fixture: .localCanPlay(.jack))
        let second = session(seed: 2026, fixture: .localCanPlay(.jack))
        #expect(first.record.actions == second.record.actions)
        #expect(first.state.pawns == second.state.pawns)
        #expect(first.state.revision == second.state.revision)
    }

    @Test("a fixture that cannot be reached is reported, not silently accepted")
    func unreachableFixtureIsHonest() {
        // A single action cannot put two pawns on the track, so no playable
        // Jack can exist yet. The fixture must say so rather than leave the
        // caller to screenshot whatever position it stopped in.
        let match = session(seed: 2026, fixture: .localCanPlay(.jack), limit: 1)
        #expect(match.fixtureReached == false)
    }

    @Test("the fast-forwarded match is a real, replayable one")
    func fastForwardProducesAReplayableMatch() throws {
        let match = session(seed: 2026, fixture: .localCanPlay(.jack))
        let replayed = try #require(match.record.replay().last?.state)
        #expect(replayed.pawns == match.state.pawns)
        #expect(replayed.revision == match.state.revision)
    }

    @Test("a free-for-all table really has no partners")
    func freeForAllHasNoPartners() {
        let match = MatchSession(
            configuration: GameConfiguration(seatCount: 4, teamMode: .freeForAll),
            seed: 2026,
            roles: [.human] + Array(repeating: SeatRole.computer(.medium), count: 3)
        )
        #expect(match.state.configuration.partners(of: Seat(0)).isEmpty)
    }
}
