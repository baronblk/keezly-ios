import Foundation
@testable import Keezly
import KeezlyCore
import Testing

/// §46 — the keyboard must be a complete way to play, not a courtesy.
///
/// A hardware keyboard is the one input a simulator run cannot be relied on to
/// reproduce, so the whole contract is written as pure logic and tested here
/// rather than hoped for in a UI test.
@Suite("Keyboard and focus")
struct PlayFocusTests {

    private func card(_ rank: CardRank, copy: Int = 0) -> Card {
        Card(rank: rank, deckCopy: copy)
    }

    private func pawn(_ seat: Int, _ slot: Int) -> PawnID {
        PawnID(seat: Seat(seat), slot: slot)
    }

    private func fullRing() -> FocusRing {
        FocusRing(
            mustFold: false,
            hand: [card(.ace), card(.four), card(.seven)],
            playable: [card(.ace), card(.seven)],
            selectablePawns: [pawn(0, 1), pawn(0, 0)],
            targets: [.track(index: 9), .track(index: 3), .home(seat: Seat(0), slot: 0)]
        )
    }

    // MARK: - What the ring contains

    @Test("only playable cards are reachable")
    func unplayableCardsAreNotOffered() {
        let ring = fullRing()
        #expect(ring.contains(.card(card(.ace))))
        #expect(ring.contains(.card(card(.seven))))
        // A Four with no legal move is shown on screen so the player can see
        // why they are stuck, but the keyboard must not stop on it: that would
        // be a dead end a pointer user never meets.
        #expect(!ring.contains(.card(card(.four))))
    }

    @Test("bands appear in screen order and empty ones are left out")
    func bandsFollowTheScreen() {
        #expect(fullRing().bands.map(\.group) == [.hand, .pawns, .targets])

        let noTargets = FocusRing(
            mustFold: false,
            hand: [card(.ace)],
            playable: [card(.ace)],
            selectablePawns: [pawn(0, 0)]
        )
        #expect(noTargets.bands.map(\.group) == [.hand, .pawns])
    }

    @Test("a forced fold leaves exactly one thing to do")
    func forcedFoldIsTheOnlyOption() {
        let ring = FocusRing(mustFold: true, hand: [card(.ace)], playable: [card(.ace)])
        #expect(ring.items == [.fold])
    }

    @Test("squares are walked in a stable, readable order")
    func targetsHaveAStableOrder() {
        let ring = FocusRing(
            mustFold: false,
            targets: [
                .waiting(seat: Seat(1), slot: 0),
                .home(seat: Seat(0), slot: 2),
                .track(index: 40),
                .track(index: 2),
                .home(seat: Seat(0), slot: 1),
            ]
        )
        // Round the track, then home, then the waiting area — the order a
        // player reads the board in. A Set has no order of its own, so without
        // this the keyboard would wander differently every render.
        #expect(ring.items == [
            .target(.track(index: 2)),
            .target(.track(index: 40)),
            .target(.home(seat: Seat(0), slot: 1)),
            .target(.home(seat: Seat(0), slot: 2)),
            .target(.waiting(seat: Seat(1), slot: 0)),
        ])
    }

    @Test("the ring is the same for the same position")
    func ringIsDeterministic() {
        #expect(fullRing() == fullRing())
        #expect(fullRing().items == fullRing().items)
    }

    // MARK: - Movement

    @Test("left and right walk the current band and wrap round it")
    func arrowsWalkTheBand() {
        let ring = fullRing()
        let first = PlayFocus.card(card(.ace))
        let last = PlayFocus.card(card(.seven))

        #expect(ring.step(from: first, by: 1) == last)
        // Two playable cards, so right twice returns to the start.
        #expect(ring.step(from: last, by: 1) == first)
        #expect(ring.step(from: first, by: -1) == last)
    }

    @Test("up and down cross between the hand, the pieces and the squares")
    func arrowsCrossBands() {
        let ring = fullRing()
        let fromCard = PlayFocus.card(card(.ace))

        #expect(ring.jump(from: fromCard, by: 1) == .pawn(pawn(0, 0)))
        #expect(ring.jump(from: .pawn(pawn(0, 0)), by: 1) == .target(.track(index: 3)))
        // Down from the last band wraps back to the hand.
        #expect(ring.jump(from: .target(.track(index: 3)), by: 1) == fromCard)
        #expect(ring.jump(from: fromCard, by: -1) == .target(.track(index: 3)))
    }

    @Test("moving from nothing lands on the first thing")
    func movingFromNowhereLandsSomewhere() {
        let ring = fullRing()
        #expect(ring.step(from: nil, by: 1) == ring.first)
        #expect(ring.jump(from: nil, by: 1) == ring.first)
    }

    // MARK: - Keys

    @Test("return and space act on what is focused")
    func activationActsOnFocus() {
        let ring = fullRing()
        let focus = PlayFocus.card(card(.seven))
        #expect(PlayKeyboard.intent(for: .activate, focus: focus, ring: ring) == .activate(focus))
    }

    @Test("escape always cancels, even with nothing to act on")
    func escapeAlwaysCancels() {
        #expect(PlayKeyboard.intent(for: .cancel, focus: nil, ring: fullRing()) == .cancel)
        // A player who chose a card and found no square still needs a way out
        // (§37), so cancel survives an empty ring.
        #expect(PlayKeyboard.intent(for: .cancel, focus: nil, ring: FocusRing(mustFold: false)) == .cancel)
    }

    @Test("stale focus never strands the keyboard")
    func staleFocusRecovers() throws {
        let ring = fullRing()
        let landing = try #require(ring.first)
        // The card was played, so this focus no longer exists. Every key must
        // still get the player somewhere real rather than doing nothing.
        let gone = PlayFocus.card(card(.king, copy: 3))

        #expect(PlayKeyboard.intent(for: .right, focus: gone, ring: ring) == .moveFocus(landing))
        #expect(PlayKeyboard.intent(for: .down, focus: gone, ring: ring) == .moveFocus(landing))
        #expect(PlayKeyboard.intent(for: .activate, focus: gone, ring: ring) == .moveFocus(landing))
    }

    @Test("keys do nothing when there is nothing to do")
    func emptyRingIgnoresMovement() {
        let empty = FocusRing(mustFold: false)
        #expect(PlayKeyboard.intent(for: .right, focus: nil, ring: empty) == .ignored)
        #expect(PlayKeyboard.intent(for: .activate, focus: nil, ring: empty) == .ignored)
    }

    @Test("a forced fold can be played with the keyboard alone")
    func foldIsReachableByKeyboard() {
        let ring = FocusRing(mustFold: true)
        let move = PlayKeyboard.intent(for: .right, focus: nil, ring: ring)
        #expect(move == .moveFocus(.fold))
        #expect(PlayKeyboard.intent(for: .activate, focus: .fold, ring: ring) == .activate(.fold))
    }

    // MARK: - The whole point

    @Test("every legal move is reachable without a pointer")
    @MainActor
    func keyboardCanReachEveryLegalMove() {
        // Built from a real match rather than a hand-made fixture: the claim is
        // about the game, not about the ring.
        let session = MatchSession(
            configuration: .standard(seatCount: 4),
            seed: 2026,
            roles: [.human] + Array(repeating: SeatRole.computer(.medium), count: 3),
            fixture: .localCanPlay(.jack)
        )
        let observation = PlayerObservation(of: session.state, for: Seat(0))
        let planner = PlayPlanner(observation: observation)

        let ring = FocusRing(
            mustFold: false,
            hand: session.state.hand(of: Seat(0)).cards,
            playable: planner.playableCards,
            selectablePawns: planner.selectablePawns,
            targets: planner.highlightedTargets
        )

        // Every card that starts a legal move must be reachable. If one were
        // missing, that move could only ever be played with a pointer.
        for move in observation.legalMoves {
            #expect(ring.contains(.card(move.card)), "no keyboard route to \(move.card)")
        }
    }
}
