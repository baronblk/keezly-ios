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
    ///
    /// Re-measured when the silhouette was softened from a superellipse of
    /// exponent 8 to one of 5: a rounder ring encloses more area for the same
    /// perimeter, so every table gained middle. The two-seat figure moved much
    /// further, from 0.28 to 1.23, because its home lanes were set side by side
    /// rather than head to head (DEC-021) — which was the point of doing it.
    ///
    /// Still asserted rather than printed. These numbers moving is allowed;
    /// them moving *without anybody deciding to* is not.
    private static let measured: [Int: CGFloat] = [
        2: 1.23, 3: 2.67, 4: 4.90, 5: 7.12, 6: 9.34,
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
        // seat added, and at two seats there is barely any.
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
        #expect(BoardLayout.centrePlacement(innerFieldRadius: 1.23, pitch: 1) == .beside)
        #expect(BoardLayout.centrePlacement(innerFieldRadius: 1.49, pitch: 1) == .beside)
        #expect(BoardLayout.centrePlacement(innerFieldRadius: 1.5, pitch: 1) == .inside)
        #expect(BoardLayout.centrePlacement(innerFieldRadius: 4.90, pitch: 1) == .inside)
    }

    @Test("what sits in the middle is measured against the middle", arguments: 2...6)
    func centreWidthIsMeasuredAgainstTheField(seats: Int) {
        let layout = layout(seats: seats)
        let fraction = layout.centreWidthFraction(aspect: 1.95)
        let diameter = layout.innerFieldRadius * 2 / layout.contentBounds.width
        #expect(fraction > 0)
        // The block is nearly twice as tall as it is wide, so its diagonal is
        // what has to fit: it may never be as wide as the field it sits in.
        #expect(fraction < diameter, "seats \(seats): \(fraction) of \(diameter)")
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
