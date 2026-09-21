import CoreGraphics
import Foundation
@testable import Keezly
import KeezlyCore
import Testing

/// ISS-013 — the middle of the board is not the same size on every table, and
/// the decision about what goes there follows from measurement.
///
/// The numbers below are the board's real proportions. They are asserted, not
/// merely printed: a change to `squareFill`, `waitingOffset` or the lane
/// length would move them, and that must be a deliberate act rather than a
/// surprise.
@Suite("Inner field")
struct InnerFieldTests {

    private func layout(seats: Int) -> BoardLayout {
        BoardLayout(board: BoardGraph(seatCount: seats))
    }

    /// The quiet middle, in square pitches, for every table size.
    private static let measured: [Int: CGFloat] = [
        2: 0.28, 3: 2.42, 4: 4.56, 5: 6.70, 6: 8.84,
    ]

    @Test("the board's proportions are what the design was decided on", arguments: 2...6)
    func proportionsAreStable(seats: Int) {
        let layout = layout(seats: seats)
        let expected = Self.measured[seats] ?? 0
        let actual = layout.innerFieldRadius / layout.pitch
        #expect(abs(actual - expected) < 0.05, "seats \(seats): \(actual) pitch, expected about \(expected)")
    }

    @Test("the quiet middle grows with the table", arguments: [2, 3, 4, 5])
    func innerFieldGrowsWithSeats(seats: Int) {
        // The lanes are four squares long whatever the table size, while the
        // track is sixteen squares per seat — so the middle grows with every
        // seat added, and at two seats there is essentially none.
        #expect(layout(seats: seats).innerFieldRadius < layout(seats: seats + 1).innerFieldRadius)
    }

    @Test("only a two-player board has its cards beside it", arguments: 2...6)
    func onlyTwoSeatsMoveTheCardsOut(seats: Int) {
        let placement = layout(seats: seats).centrePlacement
        #expect(placement == (seats == 2 ? .beside : .inside))
    }

    @Test("the decision is made from the measurement, not from the seat count")
    func placementFollowsTheMeasurement() {
        // Stated as a rule about space rather than a special case for two, so
        // that a future change to the lanes or the track moves the decision
        // with it instead of leaving a stale exception behind.
        #expect(BoardLayout.centrePlacement(innerFieldRadius: 0.28, pitch: 1) == .beside)
        #expect(BoardLayout.centrePlacement(innerFieldRadius: 1.49, pitch: 1) == .beside)
        #expect(BoardLayout.centrePlacement(innerFieldRadius: 1.5, pitch: 1) == .inside)
        #expect(BoardLayout.centrePlacement(innerFieldRadius: 4.56, pitch: 1) == .inside)
    }

    @Test("a degenerate layout is not asked to hold anything")
    func degenerateLayoutIsHandled() {
        #expect(BoardLayout.centrePlacement(innerFieldRadius: 0, pitch: 0) == .beside)
    }

    @Test("the four-player board is the reference and is unchanged")
    func classicIsTheReference() {
        #expect(BoardLayout.classicInnerFieldFraction == layout(seats: 4).innerFieldFraction)
        #expect(layout(seats: 4).centrePlacement == .inside)
    }
}
