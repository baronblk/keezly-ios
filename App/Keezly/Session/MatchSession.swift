import Foundation
import KeezlyCore
import Observation

/// A cancellable handle to the running agent search.
///
/// Exists so `MatchSession.deinit`, which is not main-actor isolated, can still
/// stop a search that is under way.
private final class SearchHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    func replace(with task: Task<Void, Never>) {
        lock.lock()
        defer { lock.unlock() }
        self.task?.cancel()
        self.task = task
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        task?.cancel()
        task = nil
    }
}

/// A situation the board should be advanced to before anyone looks at it.
///
/// Screenshot and test scaffolding (§87). The opening deal has every pawn in
/// its waiting area, so the cards with the most interesting interfaces — the
/// Jack, which needs two pawns on the track, and the Seven, which needs
/// somewhere to spend seven steps — have no legal move to show at all. A
/// capture of those interfaces has to start from a match in progress.
enum MatchFixture: Equatable {
    /// Play a fixed number of actions, whoever they fall to.
    case movesPlayed(Int)
    /// Play until the local seat is on turn holding a playable card of this
    /// rank. A Seven only counts when it can genuinely be split across two
    /// pawns, since a single-leg Seven shows none of the split interface.
    case localCanPlay(CardRank)
}

/// Who is sitting in a seat.
enum SeatRole: Hashable, Sendable {
    case human
    case computer(AIDifficulty)

    var isHuman: Bool { self == .human }
}

/// What a submitted action was refused for. Surfaced to developers and tests;
/// players never see these, because the UI only offers legal actions (§36).
enum SubmissionRefusal: Error, Hashable, Sendable {
    /// The board is mid-animation or an agent is thinking.
    case busy
    /// The action was made against an older board than the current one — a
    /// duplicate tap, or a view that had not caught up (§63).
    case staleRevision(expected: Int, got: Int)
    /// It is not this seat's turn, or the seat is not played by a human.
    case notYourTurn
    case rejectedByEngine(MoveError)
}

/// Owns a match while it is being played.
///
/// Three responsibilities, and deliberately no more: hold the authoritative
/// `GameState`, decide when a human may act, and run the computer opponents
/// off the main actor.
///
/// **The state is authoritative the instant the reducer returns.** The events
/// it publishes are a description of what already happened, for the views to
/// animate (§39). Input is closed while that animation runs, and every
/// submission carries the revision it was made against, so a second tap on a
/// card cannot apply the move twice (§63).
@MainActor
@Observable
final class MatchSession {
    /// The single source of truth for the match.
    private(set) var state: GameState
    /// The replayable history (§57).
    private(set) var record: MatchRecord
    /// Events from the most recent action, in order, for the views to animate.
    private(set) var pendingEvents: [GameEvent] = []
    /// True while an agent is thinking or an animation is still playing.
    private(set) var isBusy = false
    /// Set when the match is over.
    private(set) var result: GameResult?

    let roles: [SeatRole]
    /// How long an agent may think. Shortened in tests and in simulation.
    let budget: AIBudget

    private var agents: [Seat: any AIAgent] = [:]
    /// Holds the running agent search.
    ///
    /// In a box rather than a stored property because `deinit` is not isolated
    /// to the main actor and so cannot touch one — and letting a Hard search
    /// run on after the screen is gone would burn up to a budget's worth of CPU
    /// for nothing.
    nonisolated private let search = SearchHandle()

    /// Whether the requested opening situation was actually reached.
    ///
    /// `nil` when none was asked for. `false` is a real miss — a capture taken
    /// against it would not show what it claims to (§87).
    private(set) var fixtureReached: Bool?

    init(
        configuration: GameConfiguration,
        seed: UInt64,
        roles: [SeatRole],
        budget: AIBudget = .interactive,
        agentSeed: UInt64 = 0x5EA7_0000_0000_0001,
        fixture: MatchFixture? = nil,
        fixtureLimit: Int = 600
    ) {
        precondition(roles.count == configuration.seatCount, "one role per seat is required")
        self.state = GameState.newMatch(configuration: configuration, seed: seed)
        self.record = MatchRecord(configuration: configuration, seed: seed)
        self.roles = roles
        self.budget = budget

        for (index, role) in roles.enumerated() {
            guard case .computer(let difficulty) = role else { continue }
            let seat = Seat(index)
            agents[seat] = Self.makeAgent(difficulty, seed: agentSeed &+ UInt64(index), budget: budget)
        }

        if let fixture {
            fixtureReached = fastForward(to: fixture, limit: fixtureLimit)
        }
    }

    deinit {
        search.cancel()
    }

    // MARK: - Queries the UI needs

    /// The seat the local player controls, if any. The first human seat: on a
    /// pass-and-play table the others take their turn in the same place (§34).
    var localSeat: Seat? {
        roles.firstIndex(where: \.isHuman).map(Seat.init)
    }

    var currentRole: SeatRole { roles[state.currentSeat.index] }

    /// Whether the person holding the device may act right now.
    var isAwaitingHuman: Bool {
        !isBusy && result == nil && currentRole.isHuman
    }

    /// What the seat on turn may legally do. Empty when it is not a human's
    /// turn, so a view cannot accidentally offer an agent's moves.
    var legalMoves: [Move] {
        guard isAwaitingHuman else { return [] }
        return MoveGenerator.legalMoves(in: state, for: state.currentSeat)
    }

    /// The seat on turn must throw in its hand: no card yields a legal move (§13).
    var mustFold: Bool {
        isAwaitingHuman && legalMoves.isEmpty
    }

    // MARK: - Driving the match

    /// Starts the match, letting a computer open if the first seat is one.
    func begin() {
        continueIfComputerTurn()
    }

    /// Advances a freshly created match to a given situation by playing legal
    /// moves, before anyone is watching.
    ///
    /// Everything goes through the same reducer and is appended to the record,
    /// so the result is an ordinary, replayable match rather than a position
    /// assembled by hand — a hand-built board could be one no legal sequence
    /// can reach, which would make a screenshot of it a lie.
    ///
    /// Deterministic: the same seed and fixture produce the same board every
    /// run, which is the entire point of a screenshot fixture (§87).
    ///
    /// - Returns: whether the situation was reached. A `false` is a genuine
    ///   miss and callers should treat it as one, not screenshot whatever
    ///   position they happened to land in.
    @discardableResult
    func fastForward(to fixture: MatchFixture, limit: Int = 600) -> Bool {
        var chooser = SeededGenerator(seed: 0xF1F7 &+ state.rng.state)

        for step in 0..<limit {
            if result != nil { return false }

            switch fixture {
            case .movesPlayed(let count):
                if step == count { return true }
            case .localCanPlay(let rank):
                if localSeatCanPlay(rank) { return true }
            }

            let seat = state.currentSeat
            let moves = MoveGenerator.legalMoves(in: state, for: seat)
            let action: PlayerAction = moves.isEmpty
                ? .foldHand(seat: seat)
                : .play(moves[Int.random(in: 0..<moves.count, using: &chooser)])

            guard let advanced = try? GameReducer.apply(action, to: state) else { return false }
            state = advanced.state
            record.append(action)
            result = advanced.state.result
        }

        // Ran out of moves without arriving. Say so rather than leaving the
        // caller to guess from a board that looks plausible.
        return false
    }

    /// Whether the person holding the device is on turn and could play `rank`.
    private func localSeatCanPlay(_ rank: CardRank) -> Bool {
        guard result == nil, let seat = localSeat, state.currentSeat == seat else { return false }
        let moves = MoveGenerator.legalMoves(in: state, for: seat)
        guard rank == .seven else { return moves.contains { $0.card.rank == rank } }
        return moves.contains { move in
            guard move.card.rank == .seven, case .split(let steps) = move.action else { return false }
            return steps.count > 1
        }
    }

    /// Submits a human action.
    ///
    /// - Parameter revision: the revision the view was showing. A mismatch
    ///   means the board moved on since the tap was rendered, so the action is
    ///   dropped rather than applied to a different position.
    @discardableResult
    func submit(_ action: PlayerAction, atRevision revision: Int) -> Result<Void, SubmissionRefusal> {
        guard !isBusy, result == nil else { return .failure(.busy) }
        guard revision == state.revision else {
            return .failure(.staleRevision(expected: state.revision, got: revision))
        }
        guard currentRole.isHuman else { return .failure(.notYourTurn) }

        if case .play(let move) = action, move.seat != state.currentSeat {
            return .failure(.notYourTurn)
        }

        do {
            try apply(action)
        } catch let error as MoveError {
            return .failure(.rejectedByEngine(error))
        } catch {
            return .failure(.rejectedByEngine(.illegalMove))
        }
        return .success(())
    }

    /// Called by the board once it has finished animating `pendingEvents`.
    /// Until then input stays closed.
    func animationsFinished() {
        pendingEvents = []
        isBusy = false
        continueIfComputerTurn()
    }

    // MARK: - Internals

    private func apply(_ action: PlayerAction) throws {
        let transition = try GameReducer.apply(action, to: state)
        state = transition.state
        record.append(action)
        pendingEvents = transition.events
        result = transition.state.result
        // Closed until the board says it has caught up. The state is already
        // final; this only stops a second tap landing on a stale view (§63).
        isBusy = true
    }

    private func continueIfComputerTurn() {
        guard result == nil, !isBusy, case .computer = currentRole else { return }

        isBusy = true
        let observation = PlayerObservation(of: state, for: state.currentSeat)
        let agent = agents[state.currentSeat]

        // Detached on purpose: an agent's search must never run on the main
        // actor (§62). The result comes back here to be applied.
        search.replace(with: Task.detached(priority: .userInitiated) { [weak self] in
            let action = await Self.decide(agent: agent, observation: observation)
            guard !Task.isCancelled else { return }
            await self?.applyComputerAction(action)
        })
    }

    private static func decide(agent: (any AIAgent)?, observation: PlayerObservation) async -> PlayerAction {
        guard let agent else {
            return observation.legalMoves.first.map { .play($0) } ?? .foldHand(seat: observation.seat)
        }
        return await agent.chooseAction(for: observation)
    }

    private func applyComputerAction(_ action: PlayerAction) {
        isBusy = false
        do {
            try apply(action)
        } catch {
            // An agent that produces an illegal action is a bug, not a player
            // mistake. Fall back to the forced fold so the match cannot hang.
            assertionFailure("agent produced an illegal action: \(error)")
            try? apply(.foldHand(seat: state.currentSeat))
        }
    }

    private static func makeAgent(_ difficulty: AIDifficulty, seed: UInt64, budget: AIBudget) -> any AIAgent {
        switch difficulty {
        case .easy: EasyAgent(seed: seed)
        case .medium: MediumAgent(seed: seed)
        case .hard: HardAgent(seed: seed, budget: budget)
        }
    }
}
