@testable import KeezlyCore
import Testing

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

    /// Hard is reproducible **when its budget does not bind**.
    ///
    /// This is a real limit, not a test artefact. The search is time-boxed, so
    /// on a position heavy enough to exhaust the budget the number of completed
    /// samples depends on how busy the machine is — and a different sample
    /// count is a different average. The seeded generator makes the *sampling*
    /// reproducible; the clock does not.
    ///
    /// The budget here is deliberately far larger than the work, so the search
    /// always runs to completion and the guarantee is exact.
    @Test("the same position always yields the same move when the search completes")
    func decisionsAreReproducible() async {
        let state = GameState.newMatch(configuration: .standard(seatCount: 4), seed: 2_718)
        let observation = PlayerObservation(of: state, for: state.currentSeat)
        let agent = HardAgent(seed: 11, budget: AIBudget(maximumDuration: .seconds(120)))

        var chosen: [String] = []
        for _ in 0..<4 { chosen.append(String(describing: await agent.chooseAction(for: observation))) }
        #expect(Set(chosen).count == 1, "sampling must be driven by the seeded generator, not by wall-clock timing")
    }

    /// The other half of the same fact, stated explicitly so nobody later
    /// "fixes" the reproducibility test by widening a tolerance: with a budget
    /// that cuts the search short, identical inputs may legitimately produce
    /// different moves.
    @Test("a budget-limited search may legitimately vary", .timingSensitive)
    func budgetLimitedSearchNeedNotBeReproducible() async {
        let observation = Self.heavyObservation()
        let agent = HardAgent(seed: 11, budget: AIBudget(maximumDuration: .milliseconds(12)))

        var chosen: Set<String> = []
        for _ in 0..<12 { chosen.insert(String(describing: await agent.chooseAction(for: observation))) }
        // Not an assertion that it *must* vary — only that varying is allowed
        // and does not indicate a broken generator.
        #expect(!chosen.isEmpty)
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

    /// A position the search genuinely has to work on.
    ///
    /// This matters more than it looks: on a sparse position `HardAgent`
    /// short-circuits (`candidates.count > 1`) and returns before sampling at
    /// all, so a cancellation test built on a fresh deal can pass without ever
    /// exercising the thing it claims to test. Six seats, four of the acting
    /// seat's pawns on the track and a Seven in hand produce ~108 legal moves.
    static func heavyObservation() -> PlayerObservation {
        let state = Fixture.state(
            seatCount: 6,
            teamMode: .teamsOfTwo,
            pawns: [
                Fixture.pawn(0, 0): .track(index: 3),
                Fixture.pawn(0, 1): .track(index: 20),
                Fixture.pawn(0, 2): .track(index: 41),
                Fixture.pawn(0, 3): .track(index: 70),
                Fixture.pawn(1, 0): .track(index: 30),
                Fixture.pawn(2, 0): .track(index: 50),
                Fixture.pawn(3, 0): .track(index: 60),
                Fixture.pawn(4, 0): .track(index: 80),
                Fixture.pawn(5, 0): .track(index: 90),
            ],
            hands: [0: [.seven, .queen, .ten, .jack, .ace]]
        )
        return PlayerObservation(of: state, for: Seat(0))
    }

    /// A search large enough that it would run for minutes unchecked.
    static func unboundedSearch(seed: UInt64 = 9) -> HardAgent {
        HardAgent(
            seed: seed,
            budget: AIBudget(maximumDuration: .seconds(600)),
            candidateLimit: 64,
            samplesPerCandidate: 100_000,
            rolloutPlies: 200
        )
    }

    @Test("the test position is genuinely expensive to search")
    func heavyPositionIsActuallyHeavy() {
        // If this ever drops, the cancellation tests below stop proving
        // anything and must be rebuilt on a richer position.
        #expect(Self.heavyObservation().legalMoves.count > 40)
    }

    @Test("a search cancelled before it starts returns a legal move at once")
    func cancellationBeforeStartIsHonoured() async {
        let observation = Self.heavyObservation()
        // Timed inside the task deliberately: timing from outside measures how
        // long the global executor took to start it, which under a parallel
        // test run is seconds of queueing and says nothing about the agent.
        let task = Task { () -> (PlayerAction, Duration) in
            let clock = ContinuousClock()
            let start = clock.now
            let action = await Self.unboundedSearch().chooseAction(for: observation)
            return (action, clock.now - start)
        }
        task.cancel()
        let (action, elapsed) = await task.value

        #expect(elapsed < .milliseconds(500), "a cancelled search spent \(elapsed) working")
        guard case .play(let move) = action else {
            #expect(observation.legalMoves.isEmpty)
            return
        }
        #expect(observation.legalMoves.contains(move), "cancellation must not produce an illegal move")
    }

    /// The case that actually matters: the player taps while the agent is
    /// thinking. Measured from the cancel, not from the start.
    @Test("cancelling a search already under way stops it quickly")
    func cancellationMidSearchIsHonoured() async {
        let observation = Self.heavyObservation()
        let started = AsyncStream<Void>.makeStream()
        let task = Task { () -> PlayerAction in
            started.continuation.yield()
            started.continuation.finish()
            return await Self.unboundedSearch().chooseAction(for: observation)
        }

        for await _ in started.stream { break }
        try? await Task.sleep(for: .milliseconds(200))

        let clock = ContinuousClock()
        let cancelledAt = clock.now
        task.cancel()
        let action = await task.value
        let afterCancel = clock.now - cancelledAt

        // Measured at ~2 ms with the cancellation checks in place and ~31 ms
        // without them, so this bound distinguishes the two while leaving room
        // for a loaded machine.
        #expect(afterCancel < .milliseconds(250), "the agent kept working for \(afterCancel) after cancellation")
        guard case .play(let move) = action else { return }
        #expect(observation.legalMoves.contains(move))
    }

    @Test("an exhausted budget still yields a legal move")
    func budgetIsRespected() async {
        // Correctness only. The timing half of this guarantee lives in
        // `searchHonoursItsBudget`, behind the timing gate.
        let observation = Self.heavyObservation()
        // One microsecond: the sampling loop cannot complete a single world.
        let rushed = HardAgent(
            seed: 2,
            budget: AIBudget(maximumDuration: .microseconds(1)),
            candidateLimit: 64,
            samplesPerCandidate: 100_000,
            rolloutPlies: 200
        )

        let action = await rushed.chooseAction(for: observation)
        guard case .play(let move) = action else {
            Issue.record("expected a move")
            return
        }
        #expect(observation.legalMoves.contains(move),
                "with no samples the static evaluation must still choose legally")
    }

    /// The product requirement: a move chosen comfortably inside a second, even
    /// in the worst position the search will meet (§24).
    @Test("a decision on a heavy position stays under a second", .timingSensitive)
    func interactiveDecisionsAreFastEnough() async {
        let observation = Self.heavyObservation()
        let clock = ContinuousClock()

        let start = clock.now
        _ = await HardAgent(seed: 3, budget: .interactive).chooseAction(for: observation)
        let elapsed = clock.now - start

        // Measured at 681 ms against a 700 ms budget: the budget binds here,
        // which is the design. The ~5 ms overshoot is the static pass.
        #expect(elapsed < .seconds(1), "a single Hard decision took \(elapsed)")
    }

    @Test("the search stops when its budget runs out", .timingSensitive)
    func searchHonoursItsBudget() async {
        let observation = Self.heavyObservation()
        let clock = ContinuousClock()

        for budget in [AIBudget.simulation, .interactive] {
            let start = clock.now
            _ = await HardAgent(seed: 4, budget: budget).chooseAction(for: observation)
            let elapsed = clock.now - start
            // Allow the static pass on top of the budget, and no more.
            #expect(elapsed < budget.maximumDuration + .milliseconds(150),
                    "budget \(budget.maximumDuration) but the search took \(elapsed)")
        }
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
