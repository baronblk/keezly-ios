import Foundation

/// The outcome of one elementary pawn movement, fully resolved against the
/// current board.
public struct StepResolution: Hashable, Sendable {
    public let pawn: PawnID
    public let origin: BoardPosition
    public let destination: BoardPosition
    /// Squares crossed, excluding the origin and including the destination.
    /// Empty for a pawn entering from the waiting area, which teleports.
    public let path: [BoardPosition]
    public let captured: PawnID?
    public let backward: Bool
}

/// Legality and application of elementary pawn movements.
///
/// Both `MoveGenerator` and `GameReducer` go through here, which is what makes
/// "the generator offered it" and "the reducer accepted it" the same
/// statement. Re-implementing the rules in two places is the classic way a
/// board game engine drifts out of sync with its own UI.
public enum MoveResolver {

    // MARK: - Blocking and landing

    /// Whether two pawns are on the same side, for the friendly-capture rule.
    static func areFriendly(_ a: PawnID, _ b: PawnID, _ configuration: GameConfiguration) -> Bool {
        a.seat == b.seat || configuration.areAllied(a.seat, b.seat)
    }

    /// Whether an occupied square stops a pawn travelling *through* it.
    static func blocksPassage(_ position: BoardPosition, mover: PawnID, in state: GameState) -> Bool {
        guard let occupant = state.occupant(of: position) else { return false }
        // A pawn already home can never be jumped (§16).
        if position.isHome { return true }
        // A pawn on its own start square is an absolute blockade (§15).
        if state.isProtected(occupant) { return true }
        if state.configuration.ruleSet.ownPawnBlocking == .blocking,
           occupant.id.seat == mover.seat {
            return true
        }
        return false
    }

    /// Whether a pawn may finish its move on `position`, and whom it captures.
    ///
    /// Returns `nil` when landing is illegal, `.some(nil)` when the square is
    /// free, and `.some(id)` when the pawn standing there gets sent home.
    static func landingOutcome(
        on position: BoardPosition,
        mover: PawnID,
        in state: GameState
    ) -> PawnID?? {
        // Strict home ordering fills the lane from the back (§18).
        if case .home(let seat, let slot) = position,
           state.configuration.ruleSet.homeOrdering == .strictBackToFront {
            let deeperOccupied = ((slot + 1)..<pawnsPerSeat).allSatisfy {
                state.occupant(of: .home(seat: seat, slot: $0)) != nil
            }
            guard deeperOccupied else { return nil }
        }

        guard let occupant = state.occupant(of: position) else { return .some(nil) }
        // Home is a sanctuary: its squares are never captured into (§16).
        if position.isHome { return nil }
        if occupant.id == mover { return nil }
        if state.isProtected(occupant) { return nil }
        if state.configuration.ruleSet.friendlyCapture == .landingForbidden,
           areFriendly(occupant.id, mover, state.configuration) {
            return nil
        }
        return .some(occupant.id)
    }

    // MARK: - Elementary moves

    /// Ace or King bringing a pawn out of the waiting area (§11).
    public static func resolveEnter(pawn id: PawnID, in state: GameState) -> StepResolution? {
        let pawn = state.pawn(id)
        guard pawn.isWaiting else { return nil }
        let destination = BoardPosition.track(index: state.board.startIndex(for: id.seat))
        guard let capture = landingOutcome(on: destination, mover: id, in: state) else { return nil }
        return StepResolution(
            pawn: id,
            origin: pawn.position,
            destination: destination,
            path: [destination],
            captured: capture,
            backward: false
        )
    }

    /// Every legal forward move of `steps` for this pawn.
    ///
    /// Usually zero or one result. It is two only under the `allowExtraLap`
    /// house rule, where the player genuinely chooses between turning into
    /// home and riding past their own entry for another lap (§18).
    public static func resolveAdvance(
        pawn id: PawnID,
        steps: Int,
        in state: GameState
    ) -> [StepResolution] {
        guard steps > 0 else { return [] }
        let pawn = state.pawn(id)
        guard !pawn.isWaiting else { return [] }

        var results: [StepResolution] = []
        let board = state.board

        if let path = board.forwardPath(from: pawn.position, steps: steps, for: id.seat),
           let destination = path.last,
           let resolution = validate(path: path, destination: destination, pawn: pawn, backward: false, in: state) {
            results.append(resolution)
        }

        // The extra-lap route only exists as a *distinct* option when the
        // standard route would have turned into home.
        if state.configuration.ruleSet.homeEntry == .allowExtraLap,
           let trackIndex = pawn.position.trackIndex,
           board.progress(ofTrackIndex: trackIndex, for: id.seat) + steps > board.lapLength {
            let path = (1...steps).map {
                BoardPosition.track(index: (trackIndex + $0) % board.mainTrackCount)
            }
            if let destination = path.last,
               let resolution = validate(path: path, destination: destination, pawn: pawn, backward: false, in: state) {
                results.append(resolution)
            }
        }

        return results
    }

    /// The Four: exactly four squares backward, on the track only (§11, §16).
    public static func resolveBackward(
        pawn id: PawnID,
        steps: Int,
        in state: GameState
    ) -> StepResolution? {
        guard steps > 0 else { return nil }
        let pawn = state.pawn(id)
        // A pawn in the waiting area or in home cannot move backward at all —
        // this is what keeps the Four from reaching into or out of home.
        guard pawn.position.isTrack else { return nil }
        guard let path = state.board.backwardPath(from: pawn.position, steps: steps),
              let destination = path.last
        else { return nil }
        return validate(path: path, destination: destination, pawn: pawn, backward: true, in: state)
    }

    /// The Jack: exchange one of your pawns with another seat's pawn (§11, §37).
    public static func resolveSwap(
        own ownID: PawnID,
        other otherID: PawnID,
        in state: GameState
    ) -> StepResolution? {
        guard ownID != otherID, ownID.seat != otherID.seat else { return nil }
        let own = state.pawn(ownID)
        let other = state.pawn(otherID)
        // Both pawns must be out on the shared track: waiting and home pawns
        // are untouchable by a Jack (§16).
        guard own.position.isTrack, other.position.isTrack else { return nil }
        // The target's protection is absolute (§15).
        guard !state.isProtected(other) else { return nil }
        if state.configuration.ruleSet.jackOwnStart == .mayNotBeSwapSource,
           state.isProtected(own) {
            return nil
        }
        return StepResolution(
            pawn: ownID,
            origin: own.position,
            destination: other.position,
            path: [other.position],
            captured: nil,
            backward: false
        )
    }

    // MARK: - Shared validation

    private static func validate(
        path: [BoardPosition],
        destination: BoardPosition,
        pawn: PawnState,
        backward: Bool,
        in state: GameState
    ) -> StepResolution? {
        for crossed in path.dropLast() where blocksPassage(crossed, mover: pawn.id, in: state) {
            return nil
        }
        guard let capture = landingOutcome(on: destination, mover: pawn.id, in: state) else { return nil }
        return StepResolution(
            pawn: pawn.id,
            origin: pawn.position,
            destination: destination,
            path: path,
            captured: capture,
            backward: backward
        )
    }

    // MARK: - Application

    /// Applies a resolved step and returns the events describing it.
    ///
    /// The caller is responsible for having obtained the resolution from this
    /// same type against this same state.
    @discardableResult
    static func apply(_ resolution: StepResolution, to state: inout GameState) -> [GameEvent] {
        var events: [GameEvent] = []

        if let capturedID = resolution.captured {
            state.sendToWaiting(capturedID)
            events.append(
                .pawnCaptured(
                    pawn: capturedID,
                    by: resolution.pawn,
                    at: resolution.destination,
                    returnedTo: state.pawn(capturedID).position
                )
            )
        }

        state.setPosition(resolution.destination, for: resolution.pawn)

        if resolution.origin.isWaiting {
            events.append(.pawnEntered(pawn: resolution.pawn, at: resolution.destination))
        } else {
            events.append(
                .pawnMoved(
                    pawn: resolution.pawn,
                    from: resolution.origin,
                    to: resolution.destination,
                    path: resolution.path,
                    backward: resolution.backward
                )
            )
        }

        if case .home(_, let slot) = resolution.destination {
            events.append(.pawnReachedHome(pawn: resolution.pawn, slot: slot))
            if state.hasFinished(resolution.pawn.seat) {
                events.append(.seatFinished(resolution.pawn.seat))
            }
        }

        return events
    }

    /// Applies a Jack swap. Swaps are not captures: both pawns stay in play.
    @discardableResult
    static func applySwap(
        _ resolution: StepResolution,
        other otherID: PawnID,
        to state: inout GameState
    ) -> [GameEvent] {
        let otherOrigin = state.pawn(otherID).position
        state.setPosition(resolution.destination, for: resolution.pawn)
        state.setPosition(resolution.origin, for: otherID)
        return [
            .pawnsSwapped(
                a: resolution.pawn,
                aFrom: resolution.origin,
                b: otherID,
                bFrom: otherOrigin
            )
        ]
    }
}
