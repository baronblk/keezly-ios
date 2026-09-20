import Foundation

/// The thirteen ranks of a French deck. Keezen uses no jokers (§10).
public enum CardRank: Int, Hashable, Sendable, Codable, CaseIterable, Comparable {
    case ace = 1
    case two = 2
    case three = 3
    case four = 4
    case five = 5
    case six = 6
    case seven = 7
    case eight = 8
    case nine = 9
    case ten = 10
    case jack = 11
    case queen = 12
    case king = 13

    public static func < (lhs: CardRank, rhs: CardRank) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Short label for UI and logs. Not localised — display strings live in
    /// the app layer's String Catalog (§54).
    public var shorthand: String {
        switch self {
        case .ace: "A"
        case .jack: "J"
        case .queen: "Q"
        case .king: "K"
        default: String(rawValue)
        }
    }
}

/// Purely decorative suit. The engine must never branch on this (§10).
///
/// With five or six seats the deck contains more than four rank-sets, so
/// suits repeat. That is fine precisely because they carry no rule meaning.
public enum CardSuit: Int, Hashable, Sendable, Codable, CaseIterable {
    case spades, hearts, diamonds, clubs

    public var shorthand: String {
        switch self {
        case .spades: "♠"
        case .hearts: "♥"
        case .diamonds: "♦"
        case .clubs: "♣"
        }
    }
}

/// One physical card.
///
/// `deckCopy` distinguishes the otherwise identical rank-sets that make up a
/// multi-player deck, so that "the same card" can be tracked through deal,
/// hand, play and discard without ambiguity.
public struct Card: Hashable, Sendable, Codable, Identifiable, CustomStringConvertible {
    public let rank: CardRank
    /// 0..<seatCount — which copy of the rank-set this card belongs to.
    public let deckCopy: Int

    public init(rank: CardRank, deckCopy: Int) {
        self.rank = rank
        self.deckCopy = deckCopy
    }

    /// Stable identity: rank plus copy uniquely identifies a card in a deck.
    public var id: Int { deckCopy * 16 + rank.rawValue }

    /// Decorative only — see `CardSuit`.
    public var visualSuit: CardSuit {
        CardSuit(rawValue: deckCopy % CardSuit.allCases.count) ?? .spades
    }

    public var description: String { "\(rank.shorthand)\(visualSuit.shorthand)" }
}
