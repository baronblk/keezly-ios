import Foundation
@testable import KeezlyCore
import Testing

/// What a participant can work out from the bytes they are given.
///
/// This suite does not test that Keezly is safe. It measures precisely how
/// much hidden information a Game Center participant holds, so the answer is a
/// demonstrated fact rather than an assumption either way (DEC-025).
///
/// Every test here uses **only** the payload — the same bytes every
/// participant receives — and no privileged access to the dealing device.
@Suite("Online hidden information")
struct OnlineHiddenInformationTests {

    private func mapping(_ count: Int) throws -> ParticipantMapping {
        try ParticipantMapping(seatOrder: (0..<count).map { "player-\($0)" })
    }

    private func playedMatch(seats: Int = 4, seed: UInt64 = 2026, turns: Int = 6) throws -> OnlineMatch {
        var match = try OnlineMatch(
            configuration: .standard(seatCount: seats),
            seed: seed,
            participants: mapping(seats),
            matchID: "match-1"
        )
        for turn in 0..<turns {
            let seat = match.state.currentSeat
            let legal = MoveGenerator.legalMoves(in: match.state, for: seat)
            let action: PlayerAction = legal.first.map { .play($0) } ?? .foldHand(seat: seat)
            let outcome = match.apply(
                OnlineMove(moveID: "t\(turn)", expectedRevision: match.revision, action: action),
                from: "player-\(seat.index)"
            )
            guard outcome.didChangeTheBoard else { break }
        }
        return match
    }

    /// Everything a participant actually receives: the match data, and nothing
    /// else. No access to the device that dealt, no side channel.
    private func payloadEveryParticipantReceives(_ match: OnlineMatch) throws -> Data {
        try OnlineMatchEnvelope.encode(match)
    }

    // MARK: - The finding

    /// **A participant can reconstruct every opponent's hand.**
    ///
    /// Not through a bug, and not by reading anything they were not sent. The
    /// payload carries the seed and the accepted actions because that is what
    /// makes the match reproducible — and reproducing the match reproduces the
    /// deal. Determinism and hidden information are in direct conflict, and as
    /// built, determinism wins.
    @Test("a participant can reconstruct every other hand from the payload alone")
    func opponentHandsAreReconstructable() throws {
        let match = try playedMatch()
        let payload = try payloadEveryParticipantReceives(match)

        // Seat 0's device. It replays what it was sent, exactly as the app
        // does on every turn — this is not an attack, it is `load`.
        let reconstructed = try OnlineMatchEnvelope.load(payload)

        for seat in match.state.configuration.seats {
            #expect(
                reconstructed.state.hand(of: seat) == match.state.hand(of: seat),
                "seat \(seat.index)'s hand was reconstructed exactly"
            )
        }
        // Stated plainly so the fact is not mistaken for an accident: every
        // card in every hand is known to every participant's device.
        let allCards = match.state.configuration.seats.flatMap { match.state.hand(of: $0).cards }
        #expect(!allCards.isEmpty, "the fixture dealt no cards")
    }

    /// **A participant can read the future.**
    ///
    /// The undealt deck is part of the reproduced state, so the order of every
    /// card still to come is known before it is drawn.
    @Test("a participant can read the remaining deck order from the payload alone")
    func futureDeckIsReconstructable() throws {
        let match = try playedMatch()
        let reconstructed = try OnlineMatchEnvelope.load(try payloadEveryParticipantReceives(match))

        #expect(reconstructed.state.deck == match.state.deck)
        #expect(!reconstructed.state.deck.isEmpty, "the fixture left no deck to read")
    }

    /// The reconstruction needs nothing clever: the seed alone is the deal.
    @Test("the seed alone reproduces the deal")
    func theSeedIsTheDeal() throws {
        let match = try playedMatch(turns: 0)
        let envelope = try JSONSerialization.jsonObject(
            with: try OnlineMatchEnvelope.canonical(match)
        ) as? [String: Any]
        let seed = try #require((envelope?["seed"] as? NSNumber)?.uint64Value)

        // Anyone holding the seed and the configuration can deal the same
        // cards, without the rest of the payload at all.
        let dealt = GameState.newMatch(configuration: match.state.configuration, seed: seed)
        for seatIndex in 0..<4 {
            #expect(dealt.hand(of: Seat(seatIndex)) == match.state.hand(of: Seat(seatIndex)))
        }
    }

    // MARK: - What is and is not protected

    /// The agent boundary still holds, and is a different guarantee.
    ///
    /// `PlayerObservation` stops *Keezly's own code* from using what it should
    /// not know — a real protection against the game cheating by accident. It
    /// says nothing about what a modified client could do with the same bytes.
    @Test("the agent boundary protects Keezly's code, not the payload")
    func agentBoundaryIsADifferentGuarantee() throws {
        let match = try playedMatch()
        let observation = match.observation(for: Seat(0))

        // What an agent is given: one hand and counts.
        #expect(observation.hand == match.state.hand(of: Seat(0)))
        #expect(observation.handCounts.count == 4)

        // What the same device could work out anyway, from the bytes it holds.
        let reconstructed = try OnlineMatchEnvelope.load(try payloadEveryParticipantReceives(match))
        #expect(reconstructed.state.hand(of: Seat(1)) == match.state.hand(of: Seat(1)))

        // Both are true at once. The first is a guarantee about Keezly; the
        // second is a fact about Game Center's shared match data.
    }

    /// Encrypting a hand into the same shared payload would prove nothing.
    ///
    /// Written as a test so the reasoning cannot quietly be forgotten and
    /// re-invented as a "fix": with no trusted party and no private channel,
    /// any key placed in the payload is available to everyone who receives the
    /// payload. Keeping the seed there and encrypting the hands on top would
    /// be decoration, not protection.
    @Test("hiding hands inside the same shared payload cannot work")
    func sharedPayloadCannotHideAnything() throws {
        let match = try playedMatch()
        let payload = try payloadEveryParticipantReceives(match)

        // Whatever else were added, the seed and the actions are what make the
        // match reproducible — and they are what reveal it. Removing them is
        // not an option while replay validation depends on them.
        let reconstructed = try OnlineMatchEnvelope.load(payload)
        #expect(reconstructed.record.seed == match.record.seed)
        #expect(reconstructed.record.actions == match.record.actions)

        // So the only honest statements are: this protects against Keezly
        // leaking information (it does), and it does not protect against a
        // participant who modifies their client (it cannot). See DEC-025.
    }
}
