import Foundation

/// The only thing in Keezly that changes a `GameState`.
///
/// Every state transition goes through `apply`, which validates first and
/// mutates second, and returns both the new state and the events that explain
/// it (§19). Views call this; they never move a pawn themselves.
public enum GameReducer {

    /// Validates and applies one action.
    ///
    /// - Throws: `MoveError` when the action is not legal in `state`. The
    ///   input state is never partially mutated — the caller either gets a
    ///   complete new state or an error.
    public static func apply(_ action: PlayerAction, to state: GameState) throws -> GameTransition {
        guard !state.isFinished else { throw MoveError.matchAlreadyFinished }

        switch action {
        case .play(let move):
            return try applyMove(move, to: state)
        case .foldHand(let seat):
            return try applyFold(seat: seat, to: state)
        case .resign(let seat):
            return try applyResign(seat: seat, to: state)
        }
    }

    // MARK: - Playing a card

    private static func applyMove(_ move: Move, to state: GameState) throws -> GameTransition {
        guard move.seat == state.currentSeat else {
            throw MoveError.notYourTurn(expected: state.currentSeat, got: move.seat)
        }
        guard !state.resignedSeats.contains(move.seat) else {
            throw MoveError.seatHasResigned(move.seat)
        }
        guard state.hand(of: move.seat).contains(move.card) else {
            throw MoveError.cardNotInHand(move.card)
        }
        try validateRankMatchesAction(move)

        // Legality is decided by the generator, not by a second, parallel set
        // of checks here. If the generator would not have offered this move,
        // it is not legal — full stop.
        guard MoveGenerator.legalMoves(in: state, for: move.seat, card: move.card).contains(move) else {
            throw MoveError.illegalMove
        }

        var next = state
        var events: [GameEvent] = []

        _ = next.removeCard(move.card, from: move.seat)
        events.append(.cardPlayed(seat: move.seat, card: move.card))
        events.append(contentsOf: performAction(move.action, in: &next))

        next.bumpRevision()

        if let result = evaluateVictory(in: next) {
            next.setResult(result)
            events.append(.matchEnded(result))
            return GameTransition(state: next, events: events)
        }

        advanceTurn(in: &next, events: &events)
        return GameTransition(state: next, events: events)
    }

    /// Executes an already-validated action against the board.
    ///
    /// Internal rather than private so `PlayerObservation` can reuse it to
    /// preview a move's public effect without duplicating the mechanics.
    static func performAction(_ action: CardAction, in state: inout GameState) -> [GameEvent] {
        switch action {
        case .enterFromWaiting(let pawn):
            guard let resolution = MoveResolver.resolveEnter(pawn: pawn, in: state) else { return [] }
            return MoveResolver.apply(resolution, to: &state)

        case .advance(let pawn, let steps, let route):
            let candidates = MoveResolver.resolveAdvance(pawn: pawn, steps: steps, in: state)
            guard let resolution = candidates.first(where: { matches(route, $0, in: state) }) else { return [] }
            return MoveResolver.apply(resolution, to: &state)

        case .moveBackward(let pawn, let steps):
            guard let resolution = MoveResolver.resolveBackward(pawn: pawn, steps: steps, in: state) else { return [] }
            return MoveResolver.apply(resolution, to: &state)

        case .swap(let own, let other):
            guard let resolution = MoveResolver.resolveSwap(own: own, other: other, in: state) else { return [] }
            return MoveResolver.applySwap(resolution, other: other, to: &state)

        case .split(let steps):
            // Legs are applied strictly in the submitted order: the legality
            // of the second depends on the board the first leaves behind (§17).
            return steps.flatMap { step -> [GameEvent] in
                let candidates = MoveResolver.resolveAdvance(pawn: step.pawn, steps: step.steps, in: state)
                guard let resolution = candidates.first(where: { matches(step.route, $0, in: state) })
                else { return [] }
                return MoveResolver.apply(resolution, to: &state)
            }
        }
    }

    private static func matches(_ route: AdvanceRoute, _ resolution: StepResolution, in state: GameState) -> Bool {
        switch route {
        case .standard:
            // The home route, or any move that never reaches the home entry.
            guard let originIndex = resolution.origin.trackIndex,
                  let destinationIndex = resolution.destination.trackIndex
            else { return true }
            let board = state.board
            let seat = resolution.pawn.seat
            return board.progress(ofTrackIndex: destinationIndex, for: seat)
                > board.progress(ofTrackIndex: originIndex, for: seat)
        case .stayOnTrack:
            guard let originIndex = resolution.origin.trackIndex,
                  let destinationIndex = resolution.destination.trackIndex
            else { return false }
            let board = state.board
            let seat = resolution.pawn.seat
            return board.progress(ofTrackIndex: destinationIndex, for: seat)
                < board.progress(ofTrackIndex: originIndex, for: seat)
        }
    }

    private static func validateRankMatchesAction(_ move: Move) throws {
        let rank = move.card.rank
        let ok: Bool
        switch move.action {
        case .enterFromWaiting:
            ok = rank == .ace || rank == .king
        case .advance(_, let steps, _):
            switch rank {
            case .ace: ok = steps == 1
            case .king: ok = steps == 13
            case .queen: ok = steps == 12
            case .jack, .four, .seven: ok = false
            default: ok = steps == rank.rawValue
            }
        case .moveBackward(_, let steps):
            ok = rank == .four && steps == 4
        case .swap:
            ok = rank == .jack
        case .split(let steps):
            ok = rank == .seven && steps.reduce(0) { $0 + $1.steps } == 7
        }
        guard ok else { throw MoveError.actionDoesNotMatchRank(rank) }
    }

    // MARK: - Folding (§13)

    private static func applyFold(seat: Seat, to state: GameState) throws -> GameTransition {
        guard seat == state.currentSeat else {
            throw MoveError.notYourTurn(expected: state.currentSeat, got: seat)
        }
        // Keezen forces a move whenever one exists. Folding with a playable
        // card in hand is not a tactical choice, it is an illegal action.
        guard !MoveGenerator.hasAnyLegalMove(in: state, for: seat) else {
            throw MoveError.legalMoveAvailable
        }

        var next = state
        var events: [GameEvent] = []
        let count = next.hand(of: seat).count
        next.foldHand(of: seat)
        events.append(.handFolded(seat: seat, cardCount: count))
        next.bumpRevision()
        advanceTurn(in: &next, events: &events)
        return GameTransition(state: next, events: events)
    }

    // MARK: - Resigning (§30)

    private static func applyResign(seat: Seat, to state: GameState) throws -> GameTransition {
        guard !state.resignedSeats.contains(seat) else { throw MoveError.seatHasResigned(seat) }

        var next = state
        var events: [GameEvent] = []

        // In team play a resignation takes the whole team out; in free-for-all
        // only the individual leaves and the others play on.
        let leaving: [Seat] = next.configuration.teamMode == .teamsOfTwo
            ? next.configuration.seats(in: next.configuration.team(of: seat))
            : [seat]

        for departing in leaving where !next.resignedSeats.contains(departing) {
            next.markResigned(departing)
            // Pawns leave the race so they stop blocking the remaining players.
            for pawn in next.pawns(of: departing) where !pawn.isWaiting {
                next.sendToWaiting(pawn.id)
            }
            next.foldHand(of: departing)
            events.append(.seatResigned(departing))
        }

        next.bumpRevision()

        if let result = evaluateVictory(in: next) {
            next.setResult(result)
            events.append(.matchEnded(result))
            return GameTransition(state: next, events: events)
        }

        if next.currentSeat == seat || leaving.contains(next.currentSeat) {
            advanceTurn(in: &next, events: &events)
        }
        return GameTransition(state: next, events: events)
    }

    // MARK: - Turn order

    /// Hands the turn to the next seat that can actually act.
    ///
    /// Seats holding cards but no legal move are folded on the way past (§13),
    /// so the state machine never parks on a seat that cannot move. When no
    /// seat is left, the next 5/4/4 deal round begins (§12).
    static func advanceTurn(in state: inout GameState, events: inout [GameEvent]) {
        // Two deal rounds without anyone being able to act would mean the rule
        // engine is broken; the bound stops that from becoming a hang (§62).
        for _ in 0..<3 {
            let next = state.configuration.nextSeat(after: state.currentSeat)
            if seatTheTurnPassesTo(in: &state, events: &events, from: next) {
                return
            }
            startNextDealRound(in: &state, events: &events)
            if seatTheTurnPassesTo(in: &state, events: &events, from: state.currentSeat) {
                return
            }
        }
        assertionFailure("No seat could act across three consecutive deal rounds")
    }

    /// Walks the table once from `start`, folding dead hands, and parks the
    /// turn on the first seat with a legal move. Returns false if there is none.
    private static func seatTheTurnPassesTo(
        in state: inout GameState,
        events: inout [GameEvent],
        from start: Seat
    ) -> Bool {
        var seat = start
        for _ in 0..<state.configuration.seatCount {
            if canAct(seat, in: state) {
                if MoveGenerator.hasAnyLegalMove(in: state, for: seat) {
                    state.setCurrentSeat(seat)
                    events.append(.turnPassed(to: seat))
                    return true
                }
                let count = state.hand(of: seat).count
                state.foldHand(of: seat)
                events.append(.handFolded(seat: seat, cardCount: count))
            }
            seat = state.configuration.nextSeat(after: seat)
        }
        return false
    }

    private static func canAct(_ seat: Seat, in state: GameState) -> Bool {
        !state.resignedSeats.contains(seat)
            && !state.foldedSeats.contains(seat)
            && !state.hand(of: seat).isEmpty
    }

    private static func startNextDealRound(in state: inout GameState, events: inout [GameEvent]) {
        let previousDealer = state.dealer
        state.advanceDealRound()
        if state.dealer != previousDealer {
            events.append(.dealerChanged(to: state.dealer))
        }
        events.append(
            .dealRoundStarted(
                roundIndex: state.deal.roundIndex,
                cycleIndex: state.deal.cycleIndex,
                cardsPerSeat: state.deal.cardsThisRound
            )
        )
    }

    // MARK: - Victory (§8, §30)

    static func evaluateVictory(in state: GameState) -> GameResult? {
        let config = state.configuration
        let remainingTeams = Set(state.activeSeats.map(config.team(of:)))

        // Everyone else left the table.
        if remainingTeams.count == 1, let team = remainingTeams.first,
           state.resignedSeats.isEmpty == false {
            return GameResult(
                winningTeam: team,
                winningSeats: config.seats(in: team).filter { !state.resignedSeats.contains($0) },
                wonByDefault: true
            )
        }

        // A side wins when every one of its seats has all four pawns home.
        for team in remainingTeams.sorted() {
            let seats = config.seats(in: team).filter { !state.resignedSeats.contains($0) }
            guard !seats.isEmpty, seats.allSatisfy(state.hasFinished) else { continue }
            return GameResult(winningTeam: team, winningSeats: seats, wonByDefault: false)
        }

        return nil
    }
}
