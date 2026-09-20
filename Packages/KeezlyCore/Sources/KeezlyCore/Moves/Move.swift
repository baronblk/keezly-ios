import Foundation

/// Which way a forward move treats the home entry.
///
/// Under Classic rules only `.standard` exists: a pawn that reaches its home
/// entry turns in, and a count that would overshoot home is simply not a legal
/// move (§16). The `allowExtraLap` house rule adds `.stayOnTrack`, letting the
/// pawn ride past its own entry and take another lap (§18).
public enum AdvanceRoute: String, Hashable, Sendable, Codable, CaseIterable {
    case standard
    case stayOnTrack
}

/// One leg of a seven-split (§11, §38).
public struct SplitStep: Hashable, Sendable, Codable {
    public let pawn: PawnID
    public let steps: Int
    public let route: AdvanceRoute

    public init(pawn: PawnID, steps: Int, route: AdvanceRoute = .standard) {
        self.pawn = pawn
        self.steps = steps
        self.route = route
    }
}

/// What a played card actually does.
///
/// The card's rank alone does not determine the action — an Ace can either
/// bring a pawn out or advance one square — so the action is chosen
/// explicitly and validated against the rank by the reducer.
public enum CardAction: Hashable, Sendable, Codable {
    /// Ace or King: move a pawn from the waiting area onto its start square.
    case enterFromWaiting(pawn: PawnID)
    /// Any forward move: Ace (1), 2/3/5/6/8/9/10, Queen (12), King (13, house rule).
    case advance(pawn: PawnID, steps: Int, route: AdvanceRoute)
    /// Four: exactly four squares backward, never into or out of home.
    case moveBackward(pawn: PawnID, steps: Int)
    /// Jack: exchange one of your pawns with another seat's pawn.
    case swap(own: PawnID, other: PawnID)
    /// Seven: one or two legs summing to exactly seven.
    case split(steps: [SplitStep])
}

/// A fully specified, legal-by-construction card play.
public struct Move: Hashable, Sendable, Codable, Identifiable {
    /// The seat taking the turn. Not necessarily the owner of the pawns being
    /// moved: a finished player moves their partner's pawns (§8).
    public let seat: Seat
    public let card: Card
    public let action: CardAction

    public init(seat: Seat, card: Card, action: CardAction) {
        self.seat = seat
        self.card = card
        self.action = action
    }

    /// Stable identity for UI diffing and for online duplicate detection (§28).
    public var id: String {
        "\(seat.index):\(card.id):\(actionKey)"
    }

    private var actionKey: String {
        switch action {
        case .enterFromWaiting(let pawn):
            "enter(\(pawn))"
        case .advance(let pawn, let steps, let route):
            "fwd(\(pawn),\(steps),\(route.rawValue))"
        case .moveBackward(let pawn, let steps):
            "back(\(pawn),\(steps))"
        case .swap(let own, let other):
            "swap(\(own),\(other))"
        case .split(let steps):
            "split(" + steps.map { "\($0.pawn)+\($0.steps)+\($0.route.rawValue)" }.joined(separator: "/") + ")"
        }
    }

    /// Every pawn this move touches, for animation sequencing and hinting.
    public var involvedPawns: [PawnID] {
        switch action {
        case .enterFromWaiting(let pawn), .advance(let pawn, _, _), .moveBackward(let pawn, _):
            [pawn]
        case .swap(let own, let other):
            [own, other]
        case .split(let steps):
            steps.map(\.pawn)
        }
    }
}

/// Everything a seat can do on its turn.
public enum PlayerAction: Hashable, Sendable, Codable {
    /// Play a card. The only option whenever any legal move exists (§13).
    case play(Move)
    /// Throw in the whole hand because no card yields a legal move (§13).
    case foldHand(seat: Seat)
    /// Leave the match for good (§30).
    case resign(seat: Seat)
}

/// Why a submitted action was rejected. Surfaced to developers and tests, not
/// to players — the UI is expected to only offer legal actions (§36).
public enum MoveError: Error, Hashable, Sendable {
    case matchAlreadyFinished
    case notYourTurn(expected: Seat, got: Seat)
    case seatHasResigned(Seat)
    case cardNotInHand(Card)
    case actionDoesNotMatchRank(CardRank)
    case illegalMove
    /// Folding was attempted while a legal move still existed. Keezen forces
    /// the move (§13).
    case legalMoveAvailable
}
