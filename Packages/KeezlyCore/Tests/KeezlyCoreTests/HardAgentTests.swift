import Testing
@testable import KeezlyCore

/// §24, §62 — Hard must play legally, stay reproducible, respect its time
/// budget, and stop when it is cancelled.
@Suite("Hard agent")
struct HardAgentTests {

    /// The shipped search size, used wherever a test needs the real agent.
    static func agent(seed: UInt64 = 5, budget: AIBudget = .simulation) -> HardAgent {
        HardAgent(seed: seed, budget: budget)
    }

    // MARK: - Basics

    @Test("every choice is legal", arguments: 2...6)
    func alwaysPlaysLegally(seatCount: Int) async throws {
        var state = GameState.newMatch(configuration: .standard(seatCount: seatCount), seed: 909)

        for _ in 0..<40 where !state.isFinished {
            let observation = PlayerObservation(of: state, for: state.currentSeat)
            let action = await Self.agent().chooseAction(for: observation)
            if case .play(let move) = action {
                #expect(observation.legalMoves.contains(move))
            } else {
                #expect(observation.legalMoves.isEmpty)
            }
            state = try GameReducer.apply(action, to: state).state
        }
    }

    @Test("the same position always yields the same move")
    func decisionsAreReproducible() async {
        let state = GameState.newMatch(configuration: .standard(seatCount: 4), seed: 2_718)
        let observation = PlayerObservation(of: state, for: state.currentSeat)
        let agent = Self.agent(seed: 11)

        var chosen: [String] = []
        for _ in 0..<4 { chosen.append(String(describing: await agent.chooseAction(for: observation))) }
        #expect(Set(chosen).count == 1, "sampling must be driven by the seeded generator, not by wall-clock timing")
    }

    @Test("it takes an obvious capture")
    func takesAnObviousCapture() async throws {
        let state = Fixture.state(
            seatCount: 4,
            pawns: [
                Fixture.pawn(0, 0): .track(index: 5),
                Fixture.pawn(0, 1): .track(index: 30),
                Fixture.pawn(1, 0): .track(index: 10),
            ],
            hands: [0: [.five]]
        )
        let observation = PlayerObservation(of: state, for: Seat(0))
        let action = await Self.agent().chooseAction(for: observation)
        guard case .play(let move) = action, let preview = observation.preview(move) else {
            Issue.record("Hard did not play a move")
            return
        }
        #expect(preview.captured == [Fixture.pawn(1, 0)])
    }

    // MARK: - Budget and cancellation (§24, §62)

    @Test("a cancelled search returns promptly with a legal move")
    func cancellationIsHonoured() async {
        let state = GameState.newMatch(configuration: .standard(seatCount: 6), seed: 31)
        let observation = PlayerObservation(of: state, for: state.currentSeat)
        // A search that would take minutes if it ran to completion.
        let greedy = HardAgent(
            seed: 1,
            budget: AIBudget(maximumDuration: .seconds(600)),
            candidateLimit: 64,
            samplesPerCandidate: 100_000,
            rolloutPlies: 200
        )

        let clock = ContinuousClock()
        let start = clock.now
        let task = Task { await greedy.chooseAction(for: observation) }
        task.cancel()
        let action = await task.value
        let elapsed = clock.now - start

        #expect(elapsed < .seconds(5), "a cancelled search took \(elapsed)")
        guard case .play(let move) = action else {
            #expect(observation.legalMoves.isEmpty)
            return
        }
        #expect(observation.legalMoves.contains(move), "cancellation must not produce an illegal move")
    }

    @Test("an exhausted budget still yields a legal move")
    func budgetIsRespected() async {
        let state = GameState.newMatch(configuration: .standard(seatCount: 6), seed: 77)
        let observation = PlayerObservation(of: state, for: state.currentSeat)
        // One microsecond: the sampling loop cannot complete a single world.
        let rushed = HardAgent(
            seed: 2,
            budget: AIBudget(maximumDuration: .microseconds(1)),
            candidateLimit: 64,
            samplesPerCandidate: 100_000,
            rolloutPlies: 200
        )

        let clock = ContinuousClock()
        let start = clock.now
        let action = await rushed.chooseAction(for: observation)
        let elapsed = clock.now - start

        // The static pass still runs, so this is not instantaneous — but it
        // must not run away.
        #expect(elapsed < .seconds(5), "an exhausted budget still took \(elapsed)")
        guard case .play(let move) = action else {
            Issue.record("expected a move")
            return
        }
        #expect(observation.legalMoves.contains(move),
                "with no samples the static evaluation must still choose legally")
    }

    @Test("interactive decisions stay far inside the budget")
    func interactiveDecisionsAreFastEnough() async {
        let state = GameState.newMatch(configuration: .standard(seatCount: 6), seed: 5)
        let observation = PlayerObservation(of: state, for: state.currentSeat)
        let clock = ContinuousClock()

        let start = clock.now
        _ = await HardAgent(seed: 3, budget: .interactive).chooseAction(for: observation)
        let elapsed = clock.now - start

        // Measured around 16-19 ms on an Apple-silicon Mac. The ceiling guards
        // against a blow-up, not against machine-to-machine variation.
        #expect(elapsed < .milliseconds(900), "a single Hard decision took \(elapsed)")
    }

    // MARK: - Determinization stays inside the boundary

    @Test("a sampled world matches every public fact and invents only hidden ones")
    func determinizationIsConsistent() {
        var state = GameState.newMatch(configuration: .standard(seatCount: 4), seed: 808)
        // Play one move so the discard pile is non-empty, making the sample a
        // real completion rather than a trivial one. A fresh deal can leave a
        // seat with no legal move at all, so this must not assume one exists.
        if let opener = MoveGenerator.legalMoves(in: state, for: state.currentSeat).first,
           let advanced = try? GameReducer.apply(.play(opener), to: state).state {
            state = advanced
        }

        let observation = PlayerObservation(of: state, for: state.currentSeat)
        var generator = SeededGenerator(seed: 4)
        let world = Determinization.sample(from: observation, using: &generator)

        // Public facts are reproduced exactly.
        #expect(world.pawns == observation.pawns)
        #expect(world.discardPile == observation.discardPile)
        #expect(world.currentSeat == observation.currentSeat)
        #expect(world.hand(of: observation.seat) == observation.hand)
        for seat in world.configuration.seats {
            #expect(world.hand(of: seat).count == observation.handCounts[seat.index],
                    "card counts must match what the observer can see")
        }

        // No card exists twice, and nothing outside the deck was conjured up.
        let all = world.configuration.seats.flatMap { world.hand(of: $0).cards }
            + world.discardPile + world.deck.cards
        #expect(Set(all).count == all.count)
        #expect(all.count == world.configuration.seatCount * DealState.cardsPerCycle)
        #expect(GameStateInvariant.violations(in: world).isEmpty)
    }

    @Test("sampling explores different worlds and never peeks at the real one")
    func samplingIsAGuess() {
        let state = GameState.newMatch(configuration: .standard(seatCount: 4), seed: 1_001)
        let observation = PlayerObservation(of: state, for: state.currentSeat)

        var worlds: Set<[Card]> = []
        var matchedReality = 0
        for seed in UInt64(0)..<40 {
            var generator = SeededGenerator(seed: seed)
            let world = Determinization.sample(from: observation, using: &generator)
            let opponent = Seat((observation.seat.index + 1) % 4)
            worlds.insert(world.hand(of: opponent).cards)
            if Set(world.hand(of: opponent).cards) == Set(state.hand(of: opponent).cards) {
                matchedReality += 1
            }
        }
        #expect(worlds.count > 30, "sampling should produce a spread of worlds, got \(worlds.count)")
        // Guessing five cards out of dozens correctly should essentially never
        // happen. If it always did, the sampler would be reading the real hand.
        #expect(matchedReality <= 1, "sampled hands matched reality \(matchedReality)/40 times")
    }

    // MARK: - Extended (KEEZLY_EXTENDED_SIM=1)

    @Test("Hard holds its advantage over Medium on a larger sample", .extendedSimulation)
    func extendedHardVersusMedium() async {
        let (rate, report) = await AIStrengthTests.teamDuel(
            { HardAgent(seed: UInt64(2_000 + $0), budget: .simulation) },
            { MediumAgent(seed: UInt64(2_100 + $0)) },
            count: 150, firstSeed: 80_000
        )
        #expect(report.isClean, "\(report.summary)")
        #expect(rate > 0.55, "Hard won \(rate) over \(report.completedMatches.count) matches")
    }
}
