import Foundation

/// Enumerates every legal move available to a seat.
///
/// This is the single authority the forced-move rule rests on (§13): a seat
/// may only throw in its hand when this generator finds nothing at all, across
/// every card it holds. The UI never decides that, and never filters targets
/// on its own (§36).
public enum MoveGenerator {

    /// All legal moves for `seat` in `state`.
    ///
    /// Duplicate cards of the same rank are collapsed onto one representative
    /// card: two Sevens in hand produce one set of moves, because they are
    /// interchangeable. Use `legalMoves(in:for:card:)` when the player has
    /// already picked a specific physical card.
    public static func legalMoves(in state: GameState, for seat: Seat) -> [Move] {
        guard !state.isFinished,
              !state.resignedSeats.contains(seat),
              !state.foldedSeats.contains(seat)
        else { return [] }

        var seenRanks = Set<CardRank>()
        var moves: [Move] = []
        for card in state.hand(of: seat).cards where seenRanks.insert(card.rank).inserted {
            moves.append(contentsOf: generateMoves(in: state, seat: seat, card: card))
        }
        return moves
    }

    /// All legal moves playing one specific card.
    public static func legalMoves(in state: GameState, for seat: Seat, card: Card) -> [Move] {
        guard !state.isFinished,
              !state.resignedSeats.contains(seat),
              !state.foldedSeats.contains(seat),
              state.hand(of: seat).contains(card)
        else { return [] }
        return generateMoves(in: state, seat: seat, card: card)
    }

    /// Whether the seat has any legal move. Cheaper than building the full
    /// list only in the common case where the first card already works.
    public static func hasAnyLegalMove(in state: GameState, for seat: Seat) -> Bool {
        guard !state.isFinished,
              !state.resignedSeats.contains(seat),
              !state.foldedSeats.contains(seat)
        else { return false }

        var seenRanks = Set<CardRank>()
        for card in state.hand(of: seat).cards where seenRanks.insert(card.rank).inserted {
            if !generateMoves(in: state, seat: seat, card: card).isEmpty { return true }
        }
        return false
    }

    // MARK: - Per-rank generation

    private static func generateMoves(in state: GameState, seat: Seat, card: Card) -> [Move] {
        let rules = state.configuration.ruleSet
        var actions: [CardAction] = []

        switch card.rank {
        case .ace:
            actions += enterActions(in: state, seat: seat)
            actions += advanceActions(in: state, seat: seat, steps: 1)

        case .king:
            actions += enterActions(in: state, seat: seat)
            if rules.king == .enterOrAdvance13 {
                actions += advanceActions(in: state, seat: seat, steps: 13)
            }

        case .queen:
            actions += advanceActions(in: state, seat: seat, steps: 12)

        case .jack:
            actions += swapActions(in: state, seat: seat)

        case .four:
            actions += backwardActions(in: state, seat: seat, steps: 4)

        case .seven:
            actions += splitActions(in: state, seat: seat)

        case .two, .three, .five, .six, .eight, .nine, .ten:
            actions += advanceActions(in: state, seat: seat, steps: card.rank.rawValue)
        }

        return actions.map { Move(seat: seat, card: card, action: $0) }
    }

    // MARK: - Action families

    /// Pawns this seat is allowed to move right now. A player whose own pawns
    /// are all home takes over their partner's (§8).
    static func movablePawns(in state: GameState, for seat: Seat) -> [PawnState] {
        state.controllableSeats(for: seat).flatMap { state.pawns(of: $0) }
    }

    private static func enterActions(in state: GameState, seat: Seat) -> [CardAction] {
        movablePawns(in: state, for: seat)
            .filter(\.isWaiting)
            .filter { MoveResolver.resolveEnter(pawn: $0.id, in: state) != nil }
            // All waiting pawns of a seat are interchangeable, so offering one
            // per seat keeps the move list free of meaningless duplicates.
            .reduce(into: [Seat: PawnID]()) { partial, pawn in
                if partial[pawn.id.seat] == nil { partial[pawn.id.seat] = pawn.id }
            }
            .values
            .sorted()
            .map { .enterFromWaiting(pawn: $0) }
    }

    private static func advanceActions(in state: GameState, seat: Seat, steps: Int) -> [CardAction] {
        movablePawns(in: state, for: seat).flatMap { pawn in
            MoveResolver.resolveAdvance(pawn: pawn.id, steps: steps, in: state).map { resolution in
                CardAction.advance(pawn: pawn.id, steps: steps, route: route(of: resolution, in: state))
            }
        }
    }

    private static func backwardActions(in state: GameState, seat: Seat, steps: Int) -> [CardAction] {
        movablePawns(in: state, for: seat).compactMap { pawn in
            MoveResolver.resolveBackward(pawn: pawn.id, steps: steps, in: state) != nil
                ? .moveBackward(pawn: pawn.id, steps: steps)
                : nil
        }
    }

    private static func swapActions(in state: GameState, seat: Seat) -> [CardAction] {
        // A Jack trades one of *your* pawns for another seat's. Which seats
        // count as "yours" is the set you currently control, so a finished
        // player swapping on their partner's behalf cannot trade that
        // partner's pawns against each other.
        let controlled = Set(state.controllableSeats(for: seat))
        let own = movablePawns(in: state, for: seat).filter { $0.position.isTrack }
        let others = state.pawns.filter {
            $0.position.isTrack && !controlled.contains($0.id.seat)
        }
        return own.flatMap { mine in
            others.compactMap { theirs in
                MoveResolver.resolveSwap(own: mine.id, other: theirs.id, in: state) != nil
                    ? .swap(own: mine.id, other: theirs.id)
                    : nil
            }
        }
    }

    /// Every legal way to spend exactly seven steps (§11, §17, §38).
    ///
    /// The generator produces complete sequences only. That is deliberate: the
    /// UI can therefore never walk the player into a dead end where four steps
    /// remain and nothing legal is left, because a prefix that cannot be
    /// completed is never offered in the first place.
    private static func splitActions(in state: GameState, seat: Seat) -> [CardAction] {
        var results: [[SplitStep]] = []

        for firstSteps in 1...7 {
            for pawn in movablePawns(in: state, for: seat) {
                for resolution in MoveResolver.resolveAdvance(pawn: pawn.id, steps: firstSteps, in: state) {
                    let firstRoute = route(of: resolution, in: state)
                    let firstStep = SplitStep(pawn: pawn.id, steps: firstSteps, route: firstRoute)

                    if firstSteps == 7 {
                        results.append([firstStep])
                        continue
                    }

                    // Apply the leg, then ask what is legal *afterwards*. This
                    // is what lets a player finish their own pawns with the
                    // first leg and spend the remainder on a partner's (§17).
                    var afterFirst = state
                    MoveResolver.apply(resolution, to: &afterFirst)

                    let remaining = 7 - firstSteps
                    for second in movablePawns(in: afterFirst, for: seat) where second.id != pawn.id {
                        for secondResolution in MoveResolver.resolveAdvance(
                            pawn: second.id, steps: remaining, in: afterFirst
                        ) {
                            results.append([
                                firstStep,
                                SplitStep(
                                    pawn: second.id,
                                    steps: remaining,
                                    route: route(of: secondResolution, in: afterFirst)
                                ),
                            ])
                        }
                    }
                }
            }
        }

        // Distinct sequences only; order of legs is significant and preserved.
        var seen = Set<[SplitStep]>()
        return results.filter { seen.insert($0).inserted }.map { .split(steps: $0) }
    }

    /// Classifies a resolution as the standard route or the extra-lap route.
    private static func route(of resolution: StepResolution, in state: GameState) -> AdvanceRoute {
        guard state.configuration.ruleSet.homeEntry == .allowExtraLap,
              let originIndex = resolution.origin.trackIndex,
              let destinationIndex = resolution.destination.trackIndex
        else { return .standard }

        let board = state.board
        let seat = resolution.pawn.seat
        let originProgress = board.progress(ofTrackIndex: originIndex, for: seat)
        let destinationProgress = board.progress(ofTrackIndex: destinationIndex, for: seat)
        // Riding past your own home entry shows up as progress going *down*.
        return destinationProgress < originProgress ? .stayOnTrack : .standard
    }
}
