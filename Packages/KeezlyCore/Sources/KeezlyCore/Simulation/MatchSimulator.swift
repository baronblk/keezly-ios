import Foundation

/// Why a simulated match is not usable as evidence.
public enum SimulationFailure: Hashable, Sendable, CustomStringConvertible {
    /// Hit the action ceiling without reaching a result — a possible deadlock.
    case didNotFinish(afterActions: Int)
    /// The reducer rejected an action an agent chose. Agents may only pick
    /// from `observation.legalMoves`, so this means either the agent or the
    /// boundary is wrong.
    case illegalAction(String)
    /// An invariant broke mid-match.
    case invariantViolated([String], afterActions: Int)

    public var description: String {
        switch self {
        case .didNotFinish(let actions):
            "match did not finish within \(actions) actions"
        case .illegalAction(let reason):
            "an agent chose an illegal action: \(reason)"
        case .invariantViolated(let problems, let actions):
            "invariant broken after \(actions) actions: \(problems.joined(separator: "; "))"
        }
    }
}

/// The outcome of one simulated match.
public struct SimulationOutcome: Sendable {
    /// The seed that produced this match. Replaying it reproduces the match
    /// exactly, which is what makes a failure actionable (§112).
    public let seed: UInt64
    public let actions: Int
    public let result: GameResult?
    public let failure: SimulationFailure?
    /// Wall-clock time the agents spent deciding.
    public let decisionDuration: Duration

    public var succeeded: Bool { failure == nil && result != nil }
}

/// Plays complete matches with no UI (§25, §112).
///
/// Every action is checked against `GameStateInvariant`, so a corrupted state
/// is caught at the action that caused it rather than thousands of moves later.
public struct MatchSimulator: Sendable {
    public let configuration: GameConfiguration
    /// One agent per seat, indexed by `Seat.index`.
    public let agents: [any AIAgent]
    /// Ceiling on applied actions. A healthy match finishes far below this;
    /// exceeding it is reported as a possible deadlock rather than hidden.
    public let maximumActions: Int

    public init(configuration: GameConfiguration, agents: [any AIAgent], maximumActions: Int = 6000) {
        precondition(agents.count == configuration.seatCount, "one agent per seat is required")
        self.configuration = configuration
        self.agents = agents
        self.maximumActions = maximumActions
    }

    /// Runs one match. Never throws: a broken match comes back as a `failure`
    /// with the seed attached, so a whole batch can keep going.
    public func run(seed: UInt64) async -> SimulationOutcome {
        var state = GameState.newMatch(configuration: configuration, seed: seed)
        var actions = 0
        var decisionTime = Duration.zero

        if case let problems = GameStateInvariant.violations(in: state), !problems.isEmpty {
            return SimulationOutcome(
                seed: seed, actions: 0, result: nil,
                failure: .invariantViolated(problems, afterActions: 0),
                decisionDuration: .zero
            )
        }

        while !state.isFinished && actions < maximumActions {
            if Task.isCancelled {
                return SimulationOutcome(
                    seed: seed, actions: actions, result: state.result,
                    failure: .didNotFinish(afterActions: actions),
                    decisionDuration: decisionTime
                )
            }

            let seat = state.currentSeat
            let observation = PlayerObservation(of: state, for: seat)

            let start = ContinuousClock.now
            let action = await agents[seat.index].chooseAction(for: observation)
            decisionTime += ContinuousClock.now - start

            let previous = state
            do {
                state = try GameReducer.apply(action, to: state).state
            } catch {
                return SimulationOutcome(
                    seed: seed, actions: actions, result: nil,
                    failure: .illegalAction("seat \(seat.index): \(error)"),
                    decisionDuration: decisionTime
                )
            }
            actions += 1

            let problems = GameStateInvariant.violations(in: state, previous: previous)
            if !problems.isEmpty {
                return SimulationOutcome(
                    seed: seed, actions: actions, result: state.result,
                    failure: .invariantViolated(problems, afterActions: actions),
                    decisionDuration: decisionTime
                )
            }
        }

        return SimulationOutcome(
            seed: seed,
            actions: actions,
            result: state.result,
            failure: state.isFinished ? nil : .didNotFinish(afterActions: actions),
            decisionDuration: decisionTime
        )
    }

    /// Runs `count` matches from consecutive seeds and aggregates them.
    public func runBatch(count: Int, firstSeed: UInt64 = 1) async -> SimulationReport {
        var outcomes: [SimulationOutcome] = []
        outcomes.reserveCapacity(count)
        for offset in 0..<UInt64(count) {
            outcomes.append(await run(seed: firstSeed &+ offset))
        }
        return SimulationReport(configuration: configuration, outcomes: outcomes)
    }
}
