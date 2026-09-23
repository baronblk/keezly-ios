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
enum MatchFixture: Hashable, Sendable {
    /// Play a fixed number of actions, whoever they fall to.
    case movesPlayed(Int)
    /// Play until the local seat is on turn holding a playable card of this
    /// rank. A Seven only counts when it can genuinely be split across two
    /// pawns, since a single-leg Seven shows none of the split interface.
    case localCanPlay(CardRank)
    /// Play until the local seat is on turn with a move that would knock
    /// somebody out.
    case localCanCapture
    /// Play until the local seat is on turn with a move that would put a pawn
    /// into its home lane.
    case localCanReachHome
}

/// Who is sitting in a seat.
enum SeatRole: Hashable, Sendable {
    /// A person at this device.
    case human
    case computer(AIDifficulty)
    /// A person at somebody else's device, over Game Center.
    ///
    /// Deliberately neither of the other two. It is not `human`, because this
    /// device must not be able to move that seat's pieces; and it is not
    /// `computer`, because no agent may think for it. Everything that follows
    /// from those two facts — a read-only board while they are on turn, no
    /// handover cover, no hint, no agent task — falls out of the role rather
    /// than being special-cased at each site (§28).
    case remote
}

extension SeatRole {
    /// Whether the person holding *this* device plays this seat.
    var isHuman: Bool { self == .human }

    /// Whether the seat is played by a person at all, here or elsewhere.
    var isPerson: Bool { self == .human || self == .remote }
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
    /// Where the match is written after every accepted action. `nil` for a
    /// session that is not meant to outlive the screen — a test fixture, or a
    /// deterministic capture.
    let store: MatchStore?
    /// Where earned achievements go. Injected so a test session reports into
    /// nothing at all rather than into Apple.
    let achievements: (any AchievementReporting)?
    /// What the last save did, if it failed. Surfaced rather than swallowed: a
    /// match that is quietly not being saved is worse than one that says so.
    private(set) var saveFailure: String?

    private var agents: [Seat: any AIAgent] = [:]
    /// Holds the running agent search.
    ///
    /// In a box rather than a stored property because `deinit` is not isolated
    /// to the main actor and so cannot touch one — and letting a Hard search
    /// run on after the screen is gone would burn up to a budget's worth of CPU
    /// for nothing.
    nonisolated private let search = SearchHandle()

    /// Whether this match will offer the player a suggestion.
    ///
    /// True for everything Keezly currently plays. It exists as a property
    /// rather than as an assumption because a competitive online match must
    /// not offer one, and the place to decide that is the session rather than
    /// a view working it out from the kind of table it is looking at
    /// (DEC-025).
    var allowsHints: Bool { true }

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
        fixtureLimit: Int = 600,
        store: MatchStore? = nil,
        achievements: (any AchievementReporting)? = nil
    ) {
        precondition(roles.count == configuration.seatCount, "one role per seat is required")
        self.state = GameState.newMatch(configuration: configuration, seed: seed)
        self.record = MatchRecord(configuration: configuration, seed: seed)
        self.roles = roles
        self.budget = budget
        self.store = store
        self.achievements = achievements

        for (index, role) in roles.enumerated() {
            guard case .computer(let difficulty) = role else { continue }
            let seat = Seat(index)
            agents[seat] = Self.makeAgent(difficulty, seed: agentSeed &+ UInt64(index), budget: budget)
        }

        if let fixture {
            fixtureReached = fastForward(to: fixture, limit: fixtureLimit)
        }
    }

    /// Picks a match up where it was left off.
    ///
    /// The state comes from the restore, which has already replayed every
    /// action through the engine and checked that it produces this exact
    /// board. Nothing is recomputed here.
    init(
        restored: RestoredMatch,
        budget: AIBudget = .interactive,
        store: MatchStore?,
        achievements: (any AchievementReporting)? = nil
    ) {
        state = restored.state
        record = restored.record
        roles = restored.roles
        self.budget = budget
        self.store = store
        self.achievements = achievements
        // Taken from the restored position, not left at its default. A match
        // that was already won would otherwise come back reporting no result,
        // and the screen would offer moves in a finished game.
        result = restored.state.result

        for (index, role) in restored.roles.enumerated() {
            guard case .computer(let difficulty) = role else { continue }
            agents[Seat(index)] = Self.makeAgent(
                difficulty,
                seed: 0x5EA7_0000_0000_0001 &+ UInt64(index),
                budget: budget
            )
        }
    }

    /// A match whose authoritative copy lives in Game Center.
    ///
    /// Everything on screen still comes from the engine — the state, the legal
    /// moves, the refusals — and this device plays exactly one seat. The rest
    /// are `.remote`, which is what stops the board from being playable while
    /// somebody else is on turn, without a single `if online` anywhere in the
    /// view layer.
    ///
    /// No store and no achievements: the match is kept by Game Center, and a
    /// finished online match reports through `OnlineMatchRun`, which knows
    /// whether *this* player won. Persisting it locally as well would give two
    /// copies that can disagree.
    init(online match: OnlineMatch, mySeat: Seat) {
        state = match.state
        record = match.record
        roles = (0..<match.state.configuration.seatCount).map {
            Seat($0) == mySeat ? .human : .remote
        }
        budget = .interactive
        store = nil
        achievements = nil
        result = match.state.result
    }

    /// Replaces the position with one that arrived from Game Center.
    ///
    /// The whole state is taken, never merged: a turn-based match's payload is
    /// the position, and reconciling two of them here would be inventing an
    /// authority this device does not have.
    func adopt(_ match: OnlineMatch) {
        search.cancel()
        state = match.state
        record = match.record
        pendingEvents = []
        isBusy = false
        result = match.state.result
    }

    deinit {
        search.cancel()
    }

    // MARK: - Queries the UI needs

    /// Every seat played by a person at this device.
    var humanSeats: [Seat] {
        roles.indices.filter { roles[$0].isHuman }.map(Seat.init)
    }

    /// Whether the device has to change hands during a match (§34).
    var isPassAndPlay: Bool { humanSeats.count > 1 }

    /// The first human seat.
    ///
    /// The right answer for a table with one person at it, and the wrong one
    /// for pass & play — there "local" is whoever is holding the device, which
    /// is why the screen asks for `seatOnTurn` instead.
    var localSeat: Seat? { humanSeats.first }

    /// The seat a person must play right now, if it is a person's turn at all.
    var seatOnTurn: Seat? { currentRole.isHuman ? state.currentSeat : nil }

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

            if hasArrived(at: fixture, afterSteps: step) { return true }

            let seat = state.currentSeat
            let moves = MoveGenerator.legalMoves(in: state, for: seat)
            let action: PlayerAction = moves.isEmpty
                ? .foldHand(seat: seat)
                : .play(moves[Int.random(in: 0..<moves.count, using: &chooser)])

            guard let advanced = try? GameReducer.apply(action, to: state) else { return false }
            state = advanced.state
            record.append(action)
            // Noted as well as appended, exactly as `apply` does. Without this
            // the record's status stayed `.active` on a match the fixture had
            // played to its end, and a status that disagrees with the position
            // is the one thing `note` exists to prevent — it also made the
            // record earn no achievements, since an unfinished match earns
            // none.
            record.note(advanced.state)
            noteResult(advanced.state.result)
        }

        // Ran out of moves without arriving. Say so rather than leaving the
        // caller to guess from a board that looks plausible.
        return false
    }

    private func hasArrived(at fixture: MatchFixture, afterSteps step: Int) -> Bool {
        switch fixture {
        case .movesPlayed(let count):
            return step == count
        case .localCanPlay(let rank):
            return localSeatCanPlay(rank)
        case .localCanCapture:
            return localSeatHasMove { !$0.preview.captured.isEmpty }
        case .localCanReachHome:
            return localSeatHasMove { !$0.preview.reachedHome.isEmpty }
        }
    }

    /// Whether the local seat is on turn with a move whose effect matches.
    ///
    /// Asked of the engine's own preview rather than worked out here, so a
    /// fixture cannot come to rest on a position that only looks right.
    private func localSeatHasMove(
        where matches: ((move: Move, preview: MovePreview)) -> Bool
    ) -> Bool {
        guard result == nil, let seat = localSeat, state.currentSeat == seat else { return false }
        return PlayerObservation(of: state, for: seat).previewAll().contains(where: matches)
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
        record.note(transition.state)

        // Written here, between the engine accepting the action and the board
        // beginning to show it. An animation that is interrupted half way can
        // then never correspond to half a move on disk, because the move was
        // already whole when it was written (§57).
        persist()

        pendingEvents = transition.events
        noteResult(transition.state.result)
        // Closed until the board says it has caught up. The state is already
        // final; this only stops a second tap landing on a stale view (§63).
        isBusy = true
    }

    /// Tells Game Center what this match earned.
    ///
    /// Worked out by `AchievementEvaluator.unlocked(in:for:)`, which replays the
    /// finished record and watches its events — the same events the board
    /// animated. Nothing is counted as it happens, so there is no running
    /// total that could disagree with the matches actually played.
    ///
    /// **Only for a table with one person at it.** In pass & play several
    /// people share the device and only one of them owns the Game Center
    /// account; crediting whoever happens to sit in the first seat would
    /// attribute somebody else's win to the device's owner. A table of people
    /// earns nothing, which is the honest answer rather than a convenient one.
    /// The one place a match is noticed to be over.
    ///
    /// Both paths that can finish one go through here — an accepted action and
    /// `fastForward` — so there is no second way to reach a finished match
    /// that forgets to report it. That is not hypothetical tidiness: the whole
    /// reason this exists is that a feature was registered with Apple and
    /// never reported by anything.
    private func noteResult(_ newResult: GameResult?) {
        let wasFinished = result != nil
        result = newResult
        guard !wasFinished, newResult != nil else { return }

        guard let achievements else { return }
        let earned = achievementsEarned
        guard !earned.isEmpty else { return }
        achievements.report(earned)
    }

    /// What this match has earned the person holding the device, right now.
    ///
    /// Empty until the match is over, and empty for a table of people — kept
    /// as a property rather than buried in the reporting call so the rule can
    /// be tested without a Game Center of any kind.
    var achievementsEarned: Set<Achievement> {
        guard result != nil, !isPassAndPlay, let seat = localSeat else { return [] }
        return AchievementEvaluator.unlocked(in: record, for: seat)
    }

    /// Writes the match as it now stands.
    private func persist() {
        guard let store else { return }
        do {
            try store.save(record: record, state: state, roles: roles)
            saveFailure = nil
        } catch {
            saveFailure = error.localizedDescription
        }
    }

    /// Writes the opening position, before anybody has moved.
    ///
    /// Without this a match closed before its first move would not be there to
    /// continue, and the deal — which is part of the position — would be lost.
    func persistOpening() {
        guard record.actionCount == 0 else { return }
        record.note(state)
        persist()
    }

    /// Marks the match as one the player walked away from, and saves that.
    func abandon() {
        record.abandon()
        persist()
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
