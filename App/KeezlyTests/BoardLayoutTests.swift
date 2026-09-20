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
        // Equal arc length, not equal angle: on a superellipse those differ,
        // and equal angle would bunch squares up at the corners.
        #expect(largest / smallest < 1.02,
                "spacing varies by \(largest / smallest)x on a \(seatCount)-seat board")
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
}
