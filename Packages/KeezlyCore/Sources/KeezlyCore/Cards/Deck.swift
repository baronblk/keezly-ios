import Foundation

/// The draw pile for one match.
///
/// Size scales with the table: one full rank-set per seat, i.e. 13 × seats
/// (§10). Four seats therefore reproduce the classic 52-card deck, and every
/// seat count divides evenly into the 5/4/4 deal (§12) because 5+4+4 = 13.
public struct Deck: Hashable, Sendable, Codable {
    public private(set) var cards: [Card]

    public init(cards: [Card]) {
        self.cards = cards
    }

    /// Builds the ordered, unshuffled deck for `seatCount` seats.
    public static func standard(seatCount: Int) -> Deck {
        precondition((2...6).contains(seatCount), "Keezly supports 2...6 seats")
        var cards: [Card] = []
        cards.reserveCapacity(seatCount * CardRank.allCases.count)
        for copy in 0..<seatCount {
            for rank in CardRank.allCases {
                cards.append(Card(rank: rank, deckCopy: copy))
            }
        }
        return Deck(cards: cards)
    }

    public var count: Int { cards.count }
    public var isEmpty: Bool { cards.isEmpty }

    public mutating func shuffle(using generator: inout SeededGenerator) {
        cards = cards.keezlyShuffled(using: &generator)
    }

    /// Removes and returns the top `count` cards, or `nil` if the deck is
    /// short. Dealing must never partially succeed.
    public mutating func draw(_ count: Int) -> [Card]? {
        guard cards.count >= count else { return nil }
        let drawn = Array(cards.prefix(count))
        cards.removeFirst(count)
        return drawn
    }
}

/// A seat's private hand. Order is irrelevant to the rules but kept stable so
/// the UI does not reshuffle cards under the player's finger.
public struct Hand: Hashable, Sendable, Codable {
    public private(set) var cards: [Card]

    public init(cards: [Card] = []) {
        self.cards = cards
    }

    public var count: Int { cards.count }
    public var isEmpty: Bool { cards.isEmpty }

    public mutating func add(_ newCards: [Card]) {
        cards.append(contentsOf: newCards)
    }

    /// Removes one specific card. Returns `false` when the hand does not hold
    /// it, which the reducer treats as an illegal move rather than a crash.
    @discardableResult
    public mutating func remove(_ card: Card) -> Bool {
        guard let index = cards.firstIndex(of: card) else { return false }
        cards.remove(at: index)
        return true
    }

    public mutating func removeAll() -> [Card] {
        defer { cards = [] }
        return cards
    }

    public func contains(_ card: Card) -> Bool { cards.contains(card) }

    /// The distinct ranks held, used by the move generator to avoid
    /// enumerating duplicate cards' identical move sets.
    public var distinctRanks: [CardRank] {
        Array(Set(cards.map(\.rank))).sorted()
    }
}
