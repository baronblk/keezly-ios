@testable import KeezlyCore
import Testing

/// §22 — Easy must be weak but not broken, and reproducible from a seed.
@Suite("Easy agent")
struct EasyAgentTests {

    /// Runs one Easy decision in a fixed position, once per seed.
    static func decisions(in state: GameState, seeds: Range<UInt64>) async -> [PlayerAction] {
        let observation = PlayerObservation(of: state, for: state.currentSeat)
        var actions: [PlayerAction] = []
        for seed in seeds {
            actions.append(await EasyAgent(seed: seed).chooseAction(for: observation))
        }
        return actions
    }

    static func capturedSeats(of action: PlayerAction, in observation: PlayerObservation) -> [Seat] {
        guard case .play(let move) = action, let preview = observation.preview(move) else { return [] }
        return preview.captured.map(\.seat)
    }

    // MARK: - Legality and reproducibility

    @Test("every choice is one of the legal moves", arguments: 2...6)
    func alwaysPlaysLegally(seatCount: Int) async throws {
        let agent = EasyAgent(seed: 7)
        var state = GameState.newMatch(configuration: .standard(seatCount: seatCount), seed: 99)

        for _ in 0..<120 where !state.isFinished {
            let observation = PlayerObservation(of: state, for: state.currentSeat)
            let action = await agent.chooseAction(for: observation)
            if case .play(let move) = action {
                #expect(observation.legalMoves.contains(move))
            } else {
                #expect(observation.legalMoves.isEmpty, "folded while a legal move existed")
            }
            state = try GameReducer.apply(action, to: state).state
        }
    }

    @Test("the same agent in the same position always plays the same move")
    func decisionsAreReproducible() async {
        let state = GameState.newMatch(configuration: .standard(seatCount: 4), seed: 1234)
        let observation = PlayerObservation(of: state, for: state.currentSeat)
        let agent = EasyAgent(seed: 42)

        var chosen: [PlayerAction] = []
        for _ in 0..<8 { chosen.append(await agent.chooseAction(for: observation)) }
        #expect(Set(chosen.map(String.init(describing:))).count == 1)
    }

    @Test("different agent seeds produce genuinely different play")
    func seedsVaryTheAgent() async {
        // A position with plenty of choices, so variation is observable.
        let state = Fixture.state(
            seatCount: 4,
            pawns: [
                Fixture.pawn(0, 0): .track(index: 5),
                Fixture.pawn(0, 1): .track(index: 20),
                Fixture.pawn(0, 2): .track(index: 45),
            ],
            hands: [0: [.five, .nine, .queen, .ace]]
        )
        let actions = await Self.decisions(in: state, seeds: 0..<60)
        let distinct = Set(actions.map(String.init(describing:)))
        #expect(distinct.count > 1, "all sixty seeds produced the same move")
    }

    // MARK: - Not obviously broken

    @Test("a capture is clearly preferred over a neutral move")
    func prefersCapturingAnOpponent() async {
        let state = Fixture.state(
            seatCount: 4,
            teamMode: .teamsOfTwo,
            pawns: [
                Fixture.pawn(0, 0): .track(index: 5),    // +5 captures the opponent
                Fixture.pawn(0, 1): .track(index: 30),   // +5 is a neutral alternative
                Fixture.pawn(1, 0): .track(index: 10),
            ],
            hands: [0: [.five]]
        )
        let observation = PlayerObservation(of: state, for: Seat(0))
        let actions = await Self.decisions(in: state, seeds: 0..<200)
        let captures = actions.count { !Self.capturedSeats(of: $0, in: observation).isEmpty }

        #expect(observation.legalMoves.count == 2, "the fixture must offer exactly the two options")
        #expect(Double(captures) / 200 > 0.55, "captured in only \(captures)/200")
    }

    @Test("knocking out your own partner is avoided when anything else is legal")
    func avoidsFriendlyFire() async {
        let state = Fixture.state(
            seatCount: 4,
            teamMode: .teamsOfTwo,
            pawns: [
                Fixture.pawn(0, 0): .track(index: 5),    // +5 would capture the partner
                Fixture.pawn(0, 1): .track(index: 30),   // +5 is a neutral alternative
                Fixture.pawn(2, 0): .track(index: 10),   // seat 2 is seat 0's partner
            ],
            hands: [0: [.five]]
        )
        let observation = PlayerObservation(of: state, for: Seat(0))
        #expect(observation.legalMoves.count == 2)

        let actions = await Self.decisions(in: state, seeds: 0..<200)
        let friendlyFire = actions.count { action in
            Self.capturedSeats(of: action, in: observation).contains { observation.isAlly($0) }
        }
        #expect(Double(friendlyFire) / 200 < 0.08, "hit its own partner \(friendlyFire)/200 times")
    }

    @Test("a forced friendly capture is still played")
    func takesTheOnlyMoveEvenWhenItHurts() async throws {
        // The Five can only be played by capturing the partner; Keezen forces
        // the move (§13), so Easy must not refuse it.
        let state = Fixture.state(
            seatCount: 4,
            teamMode: .teamsOfTwo,
            pawns: [
                Fixture.pawn(0, 0): .track(index: 5),
                Fixture.pawn(2, 0): .track(index: 10),
            ],
            hands: [0: [.five]]
        )
        let observation = PlayerObservation(of: state, for: Seat(0))
        #expect(observation.legalMoves.count == 1)

        for seed in UInt64(0)..<25 {
            let action = await EasyAgent(seed: seed).chooseAction(for: observation)
            guard case .play = action else {
                Issue.record("Easy refused a forced move on seed \(seed)")
                continue
            }
            #expect(try GameReducer.apply(action, to: state).state.position(of: Fixture.pawn(2, 0)).isWaiting)
        }
    }

    @Test("going home is preferred over an idle move")
    func prefersReachingHome() async {
        let state = Fixture.state(
            seatCount: 4,
            pawns: [
                Fixture.pawn(0, 0): .track(index: 61),   // +3 reaches home
                Fixture.pawn(0, 1): .track(index: 20),   // +3 is neutral
            ],
            hands: [0: [.three]]
        )
        let observation = PlayerObservation(of: state, for: Seat(0))
        #expect(observation.legalMoves.count == 2)

        let actions = await Self.decisions(in: state, seeds: 0..<200)
        let wentHome = actions.count { action in
            guard case .play(let move) = action, let preview = observation.preview(move) else { return false }
            return !preview.reachedHome.isEmpty
        }
        #expect(Double(wentHome) / 200 > 0.6, "went home in only \(wentHome)/200")
    }
}
