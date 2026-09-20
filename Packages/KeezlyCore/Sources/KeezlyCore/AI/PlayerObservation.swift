import Foundation

/// Everything a computer opponent is allowed to know (§21).
///
/// This type is the whole anti-cheating mechanism. An agent never receives a
/// `GameState`; it receives one of these. There is deliberately no stored
/// property, no computed property and no initialiser here that can reach
/// another seat's hand, the order of the draw pile, or the random generator's
/// state — so an agent cannot read hidden information even by mistake.
///
/// What it *does* contain is everything a human at the table can see or work
/// out: their own cards, every pawn on the board, the cards already played,
/// how many cards each opponent is holding, and whose turn it is. Deducing
/// "all four Aces are gone, so nobody can bring a pawn out" from
/// `discardPile` is legitimate play, not cheating, and is explicitly supported
/// through `unseenCards`.
public struct PlayerObservation: Hashable, Sendable {

    /// The seat this observation belongs to.
    public let seat: Seat

    /// Table setup: seat count, team mode and the rule set. All public.
    public let configuration: GameConfiguration

    /// The observing seat's own cards. No other hand is reachable from here.
    public let hand: Hand

    /// Every pawn's position. The board is open information.
    public let pawns: [PawnState]

    /// Cards already played this deal cycle — the basis for card counting.
    public let discardPile: [Card]

    /// How many cards each seat holds, indexed by `Seat.index`.
    ///
    /// A count, never a content: this is exactly what a player sees by looking
    /// at the fan of cards in someone's hand.
    public let handCounts: [Int]

    public let dealer: Seat
    public let currentSeat: Seat
    public let deal: DealState
    public let foldedSeats: Set<Seat>
    public let resignedSeats: Set<Seat>

    /// The moves this seat may legally play right now.
    ///
    /// Supplied rather than recomputed so an agent cannot be tempted to derive
    /// legality from a state it should not have.
    public let legalMoves: [Move]

    /// The only way to build an observation.
    ///
    /// Everything hidden is dropped here, at one chokepoint that is easy to
    /// review and is covered by tests asserting that two states differing only
    /// in hidden information produce *identical* observations.
    public init(of state: GameState, for seat: Seat) {
        self.seat = seat
        self.configuration = state.configuration
        self.hand = state.hand(of: seat)
        self.pawns = state.pawns
        self.discardPile = state.discardPile
        self.handCounts = state.configuration.seats.map { state.hand(of: $0).count }
        self.dealer = state.dealer
        self.currentSeat = state.currentSeat
        self.deal = state.deal
        self.foldedSeats = state.foldedSeats
        self.resignedSeats = state.resignedSeats
        self.legalMoves = MoveGenerator.legalMoves(in: state, for: seat)
        // Note what is *not* copied: state.deck, state.rng, and every other
        // seat's hand. Adding any of them here would break the AI's honesty
        // guarantee, and `AIObservationTests` would fail.
    }

    // MARK: - Public deductions

    public var board: BoardGraph { configuration.board }
    public var ruleSet: RuleSet { configuration.ruleSet }
    public var isMyTurn: Bool { currentSeat == seat }

    public func pawns(of otherSeat: Seat) -> [PawnState] {
        let base = otherSeat.index * pawnsPerSeat
        return Array(pawns[base..<(base + pawnsPerSeat)])
    }

    /// Seats on the observer's own side.
    public var teamSeats: [Seat] { configuration.seats(in: configuration.team(of: seat)) }

    public func isAlly(_ otherSeat: Seat) -> Bool { configuration.areAllied(seat, otherSeat) }

    /// Cards whose location the observer cannot see: still in someone's hand
    /// or still in the draw pile.
    ///
    /// This is the full deck minus the observer's own cards minus everything
    /// already played — a deduction any attentive human makes, and the basis
    /// for the Hard agent's sampling. It deliberately does not say *where*
    /// each unseen card is.
    public var unseenCards: [Card] {
        let accounted = Set(hand.cards).union(discardPile)
        return Deck.standard(seatCount: configuration.seatCount)
            .cards
            .filter { !accounted.contains($0) }
    }

    /// A stable 64-bit fingerprint of everything this observation contains.
    ///
    /// Agents use it to seed a generator, so an agent's choice is reproducible
    /// for a given position and seed. It is derived *only* from observation
    /// fields, so by construction it cannot carry hidden information — two
    /// equal observations always produce the same key, which is precisely what
    /// the differential tests assert.
    ///
    /// `Hasher` is unusable here: it is salted per process, so the same
    /// position would seed differently on every launch.
    public var stableKey: UInt64 {
        var bytes: [UInt8] = []
        func feed(_ value: Int) {
            var v = UInt64(bitPattern: Int64(value))
            for _ in 0..<8 { bytes.append(UInt8(truncatingIfNeeded: v)); v >>= 8 }
        }
        feed(seat.index)
        feed(configuration.seatCount)
        feed(configuration.teamMode == .teamsOfTwo ? 1 : 0)
        feed(currentSeat.index)
        feed(dealer.index)
        feed(deal.roundIndex)
        feed(deal.cycleIndex)
        for card in hand.cards.sorted(by: { $0.id < $1.id }) { feed(card.id) }
        for pawn in pawns {
            feed(pawn.id.seat.index)
            feed(pawn.id.slot)
            switch pawn.position {
            case .waiting(_, let slot): feed(0); feed(slot)
            case .track(let index): feed(1); feed(index)
            case .home(_, let slot): feed(2); feed(slot)
            }
        }
        for card in discardPile { feed(card.id) }
        for count in handCounts { feed(count) }
        for folded in foldedSeats.sorted() { feed(folded.index) }
        for resigned in resignedSeats.sorted() { feed(resigned.index) }
        return Checksum.fnv1a(bytes)
    }

    /// How far a pawn has travelled along its own lap.
    ///
    /// `nil` for a pawn still waiting. 0 is its start square, `board.lapLength`
    /// its home entry, and higher values are inside the home lane. This is the
    /// natural measure of progress for any heuristic, and is pure public
    /// geometry.
    public func progress(of pawn: PawnState) -> Int? {
        board.progress(of: pawn.position, for: pawn.id.seat)
    }

    /// How many of a seat's pawns have reached home.
    public func homeCount(of otherSeat: Seat) -> Int {
        pawns(of: otherSeat).count(where: \.isHome)
    }

    /// How many cards are hidden from the observer in total. Equals the unseen
    /// count, and is the sample size the Hard agent must distribute.
    public var hiddenCardCount: Int {
        configuration.seatCount * DealState.cardsPerCycle - hand.count - discardPile.count
    }
}
