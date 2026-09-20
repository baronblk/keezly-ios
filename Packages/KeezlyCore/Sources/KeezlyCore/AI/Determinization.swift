import Foundation

/// Turns an observation into one *plausible* complete game state (§24).
///
/// This is how Hard reasons about hidden cards without knowing them. It deals
/// the cards it cannot see — `observation.unseenCards`, i.e. the deck minus its
/// own hand minus everything already played — back out to the other seats in
/// the quantities it *can* see, and puts the remainder in the draw pile. The
/// result is a world consistent with everything the agent legitimately knows,
/// and almost certainly wrong in its details. Averaging over many such worlds
/// is the point.
///
/// Nothing here can leak: the only inputs are observation fields. A sampled
/// hand is a guess, and the agent has no way to check it against reality.
enum Determinization {

    /// Samples one consistent world.
    ///
    /// - Returns: a state whose public facts match the observation exactly and
    ///   whose hidden cards are a random consistent completion.
    static func sample(
        from observation: PlayerObservation,
        using generator: inout SeededGenerator
    ) -> GameState {
        var pool = observation.unseenCards.keezlyShuffled(using: &generator)
        var hands = Array(repeating: Hand(), count: observation.configuration.seatCount)
        hands[observation.seat.index] = observation.hand

        for seat in observation.configuration.seats where seat != observation.seat {
            let count = min(observation.handCounts[seat.index], pool.count)
            guard count > 0 else { continue }
            hands[seat.index] = Hand(cards: Array(pool.prefix(count)))
            pool.removeFirst(count)
        }

        return GameState(
            configuration: observation.configuration,
            pawns: observation.pawns,
            hands: hands,
            deck: Deck(cards: pool),
            discardPile: observation.discardPile,
            dealer: observation.dealer,
            currentSeat: observation.currentSeat,
            deal: observation.deal,
            foldedSeats: observation.foldedSeats,
            resignedSeats: observation.resignedSeats,
            rng: SeededGenerator(seed: generator.next()),
            revision: 0,
            result: nil
        )
    }
}
