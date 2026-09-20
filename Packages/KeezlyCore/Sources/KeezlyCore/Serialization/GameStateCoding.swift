import Foundation

/// Deterministic encoding and decoding of a `GameState`.
///
/// "Deterministic" here means byte-for-byte: encoding the same state twice, in
/// two processes, on two devices, must produce identical data. Without that a
/// checksum is meaningless and two Game Center clients cannot agree that they
/// hold the same board (§20, §28).
public enum GameStateCoding {

    /// The shared encoder. `sortedKeys` fixes key order; without it, dictionary
    /// and object key order varies between runs.
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }

    public static func encode(_ state: GameState) throws -> Data {
        try makeEncoder().encode(state)
    }

    public static func decode(_ data: Data) throws -> GameState {
        try makeDecoder().decode(GameState.self, from: data)
    }

    /// The checksum of a state's canonical encoding.
    public static func checksum(of state: GameState) throws -> UInt64 {
        Checksum.fnv1a(try encode(state))
    }
}

// MARK: - Deterministic Codable for GameState

extension GameState {
    private enum CodingKeys: String, CodingKey {
        case configuration, pawns, hands, deck, discardPile
        case dealer, currentSeat, deal
        case foldedSeats, resignedSeats
        case rng, revision, result
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            configuration: try container.decode(GameConfiguration.self, forKey: .configuration),
            pawns: try container.decode([PawnState].self, forKey: .pawns),
            hands: try container.decode([Hand].self, forKey: .hands),
            deck: try container.decode(Deck.self, forKey: .deck),
            discardPile: try container.decode([Card].self, forKey: .discardPile),
            dealer: try container.decode(Seat.self, forKey: .dealer),
            currentSeat: try container.decode(Seat.self, forKey: .currentSeat),
            deal: try container.decode(DealState.self, forKey: .deal),
            foldedSeats: Set(try container.decode([Seat].self, forKey: .foldedSeats)),
            resignedSeats: Set(try container.decode([Seat].self, forKey: .resignedSeats)),
            rng: try container.decode(SeededGenerator.self, forKey: .rng),
            revision: try container.decode(Int.self, forKey: .revision),
            result: try container.decodeIfPresent(GameResult.self, forKey: .result)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(configuration, forKey: .configuration)
        try container.encode(pawns, forKey: .pawns)
        try container.encode(hands, forKey: .hands)
        try container.encode(deck, forKey: .deck)
        try container.encode(discardPile, forKey: .discardPile)
        try container.encode(dealer, forKey: .dealer)
        try container.encode(currentSeat, forKey: .currentSeat)
        try container.encode(deal, forKey: .deal)
        // Sets have no defined iteration order, and Swift's is salted per
        // process. Sorting here is what makes the encoding reproducible.
        try container.encode(foldedSeats.sorted(), forKey: .foldedSeats)
        try container.encode(resignedSeats.sorted(), forKey: .resignedSeats)
        try container.encode(rng, forKey: .rng)
        try container.encode(revision, forKey: .revision)
        try container.encodeIfPresent(result, forKey: .result)
    }
}
