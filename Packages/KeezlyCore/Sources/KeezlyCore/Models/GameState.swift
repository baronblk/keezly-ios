import Foundation

/// Which part of the deal cycle the table is in (§12).
///
/// A full cycle deals 5, then 4, then 4 cards to every seat — 13 in total,
/// which exactly exhausts the deck. After the third round the deck is
/// reshuffled and the cycle restarts with a new dealer.
public struct DealState: Hashable, Sendable, Codable {
    /// 0 = the 5-card round, 1 and 2 = the 4-card rounds.
    public var roundIndex: Int
    /// How many full 5/4/4 cycles have been completed this match.
    public var cycleIndex: Int

    public static let cardsPerRound = [5, 4, 4]
    public static let cardsPerCycle = cardsPerRound.reduce(0, +)   // 13

    public init(roundIndex: Int = 0, cycleIndex: Int = 0) {
        self.roundIndex = roundIndex
        self.cycleIndex = cycleIndex
    }

    public var cardsThisRound: Int { Self.cardsPerRound[roundIndex] }
    public var isLastRoundOfCycle: Bool { roundIndex == Self.cardsPerRound.count - 1 }
}

/// How a match ended.
public struct GameResult: Hashable, Sendable, Codable {
    public let winningTeam: TeamID
    public let winningSeats: [Seat]
    /// True when the win came from everyone else resigning rather than from
    /// bringing all pawns home (§30).
    public let wonByDefault: Bool

    public init(winningTeam: TeamID, winningSeats: [Seat], wonByDefault: Bool) {
        self.winningTeam = winningTeam
        self.winningSeats = winningSeats
        self.wonByDefault = wonByDefault
    }
}

/// The complete, authoritative state of a match.
///
/// This is the single source of truth (§68). It is a value type: the reducer
/// never mutates in place, it returns a new state. Nothing in here depends on
/// SwiftUI, GameKit or a persistence framework.
public struct GameState: Hashable, Sendable, Codable {
    public let configuration: GameConfiguration

    /// All pawns of all seats, ordered by `PawnID` so the encoding is stable.
    public private(set) var pawns: [PawnState]
    /// One hand per seat, indexed by `Seat.index`.
    public private(set) var hands: [Hand]
    public private(set) var deck: Deck
    /// Cards played or discarded during the current cycle. Public knowledge —
    /// the AI observation layer is allowed to see this (§21).
    public private(set) var discardPile: [Card]

    public private(set) var dealer: Seat
    public private(set) var currentSeat: Seat
    public private(set) var deal: DealState

    /// Seats that ran out of legal moves and threw in their hand for the rest
    /// of this deal round (§13).
    public private(set) var foldedSeats: Set<Seat>
    /// Seats that resigned from the match entirely (§30).
    public private(set) var resignedSeats: Set<Seat>

    public private(set) var rng: SeededGenerator
    /// Monotonic counter incremented by every applied move. Used for
    /// idempotent online turn submission (§28, §63).
    public private(set) var revision: Int
    public private(set) var result: GameResult?

    public var board: BoardGraph { configuration.board }
    public var isFinished: Bool { result != nil }

    // MARK: - Construction

    /// Creates a fresh match with the deck shuffled and the first 5-card round
    /// already dealt. The seat to the dealer's left is on turn (§12).
    public static func newMatch(configuration: GameConfiguration, seed: UInt64) -> GameState {
        var generator = SeededGenerator(seed: seed)
        var deck = Deck.standard(seatCount: configuration.seatCount)
        deck.shuffle(using: &generator)

        let pawns = configuration.seats.flatMap { seat in
            (0..<pawnsPerSeat).map { slot in
                PawnState(id: PawnID(seat: seat, slot: slot), position: .waiting(seat: seat, slot: slot))
            }
        }

        var state = GameState(
            configuration: configuration,
            pawns: pawns,
            hands: Array(repeating: Hand(), count: configuration.seatCount),
            deck: deck,
            discardPile: [],
            dealer: configuration.initialDealer,
            currentSeat: configuration.nextSeat(after: configuration.initialDealer),
            deal: DealState(),
            foldedSeats: [],
            resignedSeats: [],
            rng: generator,
            revision: 0,
            result: nil
        )
        state.dealCurrentRound()
        return state
    }

    init(
        configuration: GameConfiguration,
        pawns: [PawnState],
        hands: [Hand],
        deck: Deck,
        discardPile: [Card],
        dealer: Seat,
        currentSeat: Seat,
        deal: DealState,
        foldedSeats: Set<Seat>,
        resignedSeats: Set<Seat>,
        rng: SeededGenerator,
        revision: Int,
        result: GameResult?
    ) {
        self.configuration = configuration
        self.pawns = pawns
        self.hands = hands
        self.deck = deck
        self.discardPile = discardPile
        self.dealer = dealer
        self.currentSeat = currentSeat
        self.deal = deal
        self.foldedSeats = foldedSeats
        self.resignedSeats = resignedSeats
        self.rng = rng
        self.revision = revision
        self.result = result
    }

    // MARK: - Pawn queries

    public func pawn(_ id: PawnID) -> PawnState {
        // Pawns are stored in PawnID order, so the index is computable.
        pawns[id.seat.index * pawnsPerSeat + id.slot]
    }

    public func pawns(of seat: Seat) -> [PawnState] {
        let base = seat.index * pawnsPerSeat
        return Array(pawns[base..<(base + pawnsPerSeat)])
    }

    /// The pawn occupying a position, if any. Waiting slots are private to a
    /// seat and never collide, so only track and home squares matter here.
    public func occupant(of position: BoardPosition) -> PawnState? {
        pawns.first { $0.position == position }
    }

    /// True when the pawn sits on its own start square and is therefore
    /// protected: it cannot be captured, passed or targeted by a Jack (§15).
    public func isProtected(_ pawn: PawnState) -> Bool {
        guard let index = pawn.position.trackIndex else { return false }
        return index == board.startIndex(for: pawn.id.seat)
    }

    /// Seats still competing: neither resigned nor already finished.
    public var activeSeats: [Seat] {
        configuration.seats.filter { !resignedSeats.contains($0) }
    }

    /// True when every pawn of `seat` has reached its home lane.
    public func hasFinished(_ seat: Seat) -> Bool {
        pawns(of: seat).allSatisfy(\.isHome)
    }

    /// Seats whose pawns this seat may legally move.
    ///
    /// Classic team rule (§8): once all your own pawns are home you keep
    /// playing with your partner's pawns.
    public func controllableSeats(for seat: Seat) -> [Seat] {
        guard hasFinished(seat) else { return [seat] }
        let partners = configuration.partners(of: seat).filter { !hasFinished($0) }
        return partners.isEmpty ? [seat] : partners
    }

    public func hand(of seat: Seat) -> Hand { hands[seat.index] }

    // MARK: - Mutation (internal — only the reducer drives these)

    mutating func setPosition(_ position: BoardPosition, for id: PawnID) {
        pawns[id.seat.index * pawnsPerSeat + id.slot].position = position
    }

    mutating func sendToWaiting(_ id: PawnID) {
        // Reuse the lowest free waiting slot so the UI has a stable target.
        let occupied = Set(
            pawns(of: id.seat).compactMap { state -> Int? in
                if case .waiting(_, let slot) = state.position, state.id != id { return slot }
                return nil
            }
        )
        let slot = (0..<pawnsPerSeat).first { !occupied.contains($0) } ?? id.slot
        setPosition(.waiting(seat: id.seat, slot: slot), for: id)
    }

    mutating func removeCard(_ card: Card, from seat: Seat) -> Bool {
        guard hands[seat.index].remove(card) else { return false }
        discardPile.append(card)
        return true
    }

    mutating func foldHand(of seat: Seat) {
        discardPile.append(contentsOf: hands[seat.index].removeAll())
        foldedSeats.insert(seat)
    }

    mutating func bumpRevision() {
        revision += 1
    }

    mutating func setCurrentSeat(_ seat: Seat) {
        currentSeat = seat
    }

    mutating func setResult(_ newResult: GameResult) {
        result = newResult
    }

    mutating func markResigned(_ seat: Seat) {
        resignedSeats.insert(seat)
    }

    /// Deals the cards for `deal.roundIndex` to every non-resigned seat.
    mutating func dealCurrentRound() {
        let count = deal.cardsThisRound
        for seat in configuration.seats {
            guard let drawn = deck.draw(count) else { continue }
            hands[seat.index].add(drawn)
        }
    }

    /// Advances to the next deal round, reshuffling and rotating the dealer at
    /// the end of a 5/4/4 cycle (§12).
    mutating func advanceDealRound() {
        foldedSeats.removeAll()

        if deal.isLastRoundOfCycle {
            deal = DealState(roundIndex: 0, cycleIndex: deal.cycleIndex + 1)
            var rebuilt = Deck.standard(seatCount: configuration.seatCount)
            rebuilt.shuffle(using: &rng)
            deck = rebuilt
            discardPile.removeAll()
            dealer = configuration.nextSeat(after: dealer)
        } else {
            deal.roundIndex += 1
        }

        dealCurrentRound()
        currentSeat = configuration.nextSeat(after: dealer)
    }
}
