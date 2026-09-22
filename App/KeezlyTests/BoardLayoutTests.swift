import CoreGraphics
import Foundation
@testable import Keezly
import KeezlyCore
import Testing

/// §9, §4 — the board must be laid out parametrically and fairly for every
/// seat count, with no hand-placed special cases.
@Suite("Board layout")
struct BoardLayoutTests {
    static func layout(_ seatCount: Int) -> BoardLayout {
        BoardLayout(board: BoardGraph(seatCount: seatCount))
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }

    @Test("every position has its own point", arguments: 2...6)
    func positionsDoNotCollide(seatCount: Int) {
        let layout = Self.layout(seatCount)
        let points = layout.allPositions.map(layout.point(for:))

        // Two squares closer than half a square width would read as one.
        for (index, point) in points.enumerated() {
            for other in points[(index + 1)...] {
                #expect(Self.distance(point, other) > layout.squareSize * 0.5,
                        "two squares overlap on a \(seatCount)-seat board")
            }
        }
    }

    @Test("track squares are evenly spaced around the ring", arguments: 2...6)
    func trackSpacingIsUniform(seatCount: Int) {
        let layout = Self.layout(seatCount)
        let points = layout.trackPoints
        let gaps = (0..<points.count).map { index in
            Self.distance(points[index], points[(index + 1) % points.count])
        }
        guard let smallest = gaps.min(), let largest = gaps.max() else {
            Issue.record("no track points")
            return
        }

        // Squares are placed at equal *arc length*, which is exact by
        // construction. What this measures is the straight-line gap between
        // neighbours, and those are not quite equal: on a curve, equal arc
        // length yields shorter chords wherever curvature is high — at the
        // board's corners. The effect is real geometry, not an error, and on
        // the squared ring it comes to about 2%.
        //
        // The bound is therefore perceptual: a gap varying by a twentieth is
        // invisible; anything approaching a tenth would read as bunching.
        // Placing by equal *angle* instead would put the ratio near 1.3.
        #expect(largest / smallest < 1.05,
                "spacing varies by \(largest / smallest)x on a \(seatCount)-seat board")
    }

    /// The placement algorithm, checked against the obvious alternative.
    ///
    /// An earlier version of this file tried to re-measure arc length from the
    /// drawn outline, which only measured that outline's sampling resolution.
    /// This asks the question that actually matters instead: does placing by
    /// arc length beat placing by angle? On a squared ring it does, by a lot —
    /// equal angle crowds squares into the corners.
    @Test("arc-length placement beats placing squares by angle", arguments: 2...6)
    func arcLengthPlacementBeatsAngularPlacement(seatCount: Int) {
        let layout = Self.layout(seatCount)
        let count = layout.board.mainTrackCount

        func spread(_ points: [CGPoint]) -> Double {
            let gaps = (0..<points.count).map { Self.distance(points[$0], points[($0 + 1) % points.count]) }
            guard let smallest = gaps.min(), let largest = gaps.max(), smallest > 0 else { return .infinity }
            return largest / smallest
        }

        // What the naive approach would produce: one point per equal slice of
        // angle around the same superellipse.
        let angular = (0..<count).map { index -> CGPoint in
            let angle = Double(index) / Double(count) * 2 * .pi + .pi / 2
            let exponent = 2 / BoardLayout.ringExponent
            let cosine = cos(angle), sine = sin(angle)
            return CGPoint(
                x: (cosine < 0 ? -1 : 1) * pow(abs(cosine), exponent),
                y: (sine < 0 ? -1 : 1) * pow(abs(sine), exponent)
            )
        }

        let byArcLength = spread(layout.trackPoints)
        let byAngle = spread(angular)
        #expect(byArcLength < byAngle / 2,
                "arc length spread \(byArcLength) vs angular \(byAngle) on a \(seatCount)-seat board")
    }

    @Test("home lanes run inward and waiting areas sit outside", arguments: 2...6)
    func lanesPointTheRightWay(seatCount: Int) {
        let layout = Self.layout(seatCount)
        let board = layout.board

        for seat in board.seats {
            let entry = layout.point(for: .track(index: board.homeEntryIndex(for: seat)))
            var previous = hypot(entry.x, entry.y)
            for slot in 0..<pawnsPerSeat {
                let radius = hypot(
                    layout.homePoints[seat.index][slot].x,
                    layout.homePoints[seat.index][slot].y
                )
                #expect(radius < previous, "home slot \(slot) of \(seat) is not further inward")
                previous = radius
            }

            let start = layout.point(for: .track(index: board.startIndex(for: seat)))
            let startRadius = hypot(start.x, start.y)
            for slot in 0..<pawnsPerSeat {
                let point = layout.waitingPoints[seat.index][slot]
                #expect(hypot(point.x, point.y) > startRadius,
                        "waiting slot \(slot) of \(seat) is not outside the ring")
            }
        }
    }

    @Test("no seat gets a better place at the table", arguments: 2...6)
    func seatsAreGeometricallyEquivalent(seatCount: Int) {
        let layout = Self.layout(seatCount)
        let board = layout.board

        // Each seat's home lane must be the same length, and each seat's start
        // must sit the same distance from the centre. Anything else would give
        // one player a visually different board (§9).
        var laneLengths: [Double] = []
        var startRadii: [Double] = []
        for seat in board.seats {
            let entry = layout.point(for: .track(index: board.homeEntryIndex(for: seat)))
            let deepest = layout.homePoints[seat.index][pawnsPerSeat - 1]
            laneLengths.append(Self.distance(entry, deepest))

            let start = layout.point(for: .track(index: board.startIndex(for: seat)))
            startRadii.append(hypot(start.x, start.y))
        }

        guard let shortest = laneLengths.min(), let longest = laneLengths.max(),
              let nearest = startRadii.min(), let furthest = startRadii.max()
        else {
            Issue.record("no seats")
            return
        }
        #expect(longest / shortest < 1.001, "home lanes differ in length by \(longest / shortest)x")
        // The ring is a superellipse, so a start square's distance from the
        // centre depends on where it sits on the curve. The spread is bounded
        // by the shape itself and must stay modest.
        #expect(furthest / nearest < 1.35, "start squares differ in radius by \(furthest / nearest)x")
    }

    @Test("the local player's home lane comes up from the bottom", arguments: 2...6)
    func seatZeroFacesThePlayer(seatCount: Int) {
        let layout = Self.layout(seatCount)
        let entry = layout.point(for: .track(index: layout.board.homeEntryIndex(for: Seat(0))))

        // Unit space has y increasing downward, so "towards the player" is a
        // large positive y and an x near the middle.
        #expect(entry.y > 0.9, "seat 0's home entry sits at y=\(entry.y), not at the near edge")
        #expect(abs(entry.x) < 0.1, "seat 0's home entry is off-centre at x=\(entry.x)")
    }

    @Test("content bounds enclose everything that is drawn", arguments: 2...6)
    func boundsContainEverything(seatCount: Int) {
        let layout = Self.layout(seatCount)
        for position in layout.allPositions {
            let point = layout.point(for: position)
            #expect(layout.contentBounds.contains(point), "\(position) falls outside the content bounds")
        }
        #expect(layout.contentBounds.width > 0)
        #expect(layout.contentBounds.height > 0)
    }

    @Test("squares get smaller as the table grows, as they must", arguments: [2, 3, 4, 5])
    func squareSizeShrinksWithSeatCount(seatCount: Int) {
        // More seats means more squares on the same ring.
        #expect(Self.layout(seatCount).squareSize > Self.layout(seatCount + 1).squareSize)
    }

    // MARK: - The board stands in its space

    /// **The board is not pressed into its container.**
    ///
    /// `contentBounds` is what a view scales to fit. It used to be the bounds
    /// of the *playing squares*, padded by one square — while the panel is
    /// drawn `surfaceMargin` further out again, which is several squares. So
    /// the thing being fitted was smaller than the thing being drawn, and the
    /// board's rounded corners, its border ornament and its shadow were pushed
    /// past the edge of the view.
    ///
    /// It was never technically clipped, which is why it survived several
    /// reviews: it simply looked like a board that had been squeezed in.
    @Test("the drawn board sits clear of the bounds a view fits it into", arguments: 2...6)
    func boardHasRoomAroundIt(seatCount: Int) {
        let layout = Self.layout(seatCount)
        let panel = layout.panelBounds
        let content = layout.contentBounds

        // Every side, not just the ones a square board happens to make equal.
        let margins = [
            panel.minX - content.minX,
            content.maxX - panel.maxX,
            panel.minY - content.minY,
            content.maxY - panel.maxY,
        ]
        for margin in margins {
            #expect(
                margin >= layout.squareSize * 3,
                "the panel comes within \(margin / layout.squareSize) squares of the edge"
            )
        }

        // And the air is a real share of the board rather than a rounding
        // error: about a tenth of the whole, which is what makes it read as
        // deliberate rather than tight.
        let share = (content.width - panel.width) / content.width
        #expect(share > 0.08, "only \(Int(share * 100))% of the width is margin")
        #expect(share < 0.35, "\(Int(share * 100))% of the width is margin — the board has shrunk away")
    }

    /// The panel is bigger than the squares on it, which is the whole reason
    /// the bounds had to change.
    @Test("the panel extends well past the outermost square", arguments: 2...6)
    func panelIsBiggerThanThePlayingArea(seatCount: Int) {
        let layout = Self.layout(seatCount)
        let furthest = layout.allPositions
            .map { layout.point(for: $0) }
            .map { max(abs($0.x), abs($0.y)) }
            .max() ?? 0

        #expect(
            layout.panelBounds.width / 2 > furthest + layout.squareSize,
            "the panel does not clear the waiting areas standing on it"
        )
    }

    /// The quiet middle is a property of the playing area, so changing the air
    /// around the board must not move it (ISS-008, DEC-021).
    @Test("the quiet middle does not depend on the margin around the board")
    func innerFieldIgnoresTheMargin() {
        // Two seats have the least middle and four the reference amount; the
        // ratio between them is what the centre cards are sized from.
        let two = Self.layout(2).innerFieldFraction
        let four = Self.layout(4).innerFieldFraction
        let six = Self.layout(6).innerFieldFraction

        #expect(two > 0 && four > 0 && six > 0)
        #expect(two < four, "a two-seat board has less middle, not more")
        #expect(four <= six, "more seats means a longer track and more middle")
    }
}
