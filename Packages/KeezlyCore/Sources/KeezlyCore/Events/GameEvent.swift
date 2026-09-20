import Foundation

/// Something that happened as a result of applying an action.
///
/// Events are what the UI animates (§39). They describe the transition that
/// already took place — animating them must never be what *causes* the
/// transition, because the new `GameState` is authoritative the moment the
/// reducer returns.
public enum GameEvent: Hashable, Sendable, Codable {
    case cardPlayed(seat: Seat, card: Card)
    case pawnEntered(pawn: PawnID, at: BoardPosition)
    /// A pawn travelled along `path`, which the UI walks square by square.
    case pawnMoved(pawn: PawnID, from: BoardPosition, to: BoardPosition, path: [BoardPosition], backward: Bool)
    case pawnsSwapped(a: PawnID, aFrom: BoardPosition, b: PawnID, bFrom: BoardPosition)
    case pawnCaptured(pawn: PawnID, by: PawnID, at: BoardPosition, returnedTo: BoardPosition)
    case pawnReachedHome(pawn: PawnID, slot: Int)
    case seatFinished(Seat)
    /// A seat had no legal move at all and threw in its hand (§13).
    case handFolded(seat: Seat, cardCount: Int)
    case seatResigned(Seat)
    case turnPassed(to: Seat)
    case dealRoundStarted(roundIndex: Int, cycleIndex: Int, cardsPerSeat: Int)
    case dealerChanged(to: Seat)
    case matchEnded(GameResult)
}

/// The result of applying one action: the new state plus the events that
/// describe how it got there.
public struct GameTransition: Sendable {
    public let state: GameState
    public let events: [GameEvent]

    public init(state: GameState, events: [GameEvent]) {
        self.state = state
        self.events = events
    }
}
