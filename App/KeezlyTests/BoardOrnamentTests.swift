import CoreGraphics
import Foundation
@testable import Keezly
import KeezlyCore
import Testing

/// §76 — the ornament has to be quiet, even, and unmistakably not part of the
/// game. Those are geometric claims, so they are tested as such.
@Suite("Board ornament")
struct BoardOrnamentTests {

    private func layout(seats: Int) -> BoardLayout {
        BoardLayout(board: BoardGraph(seatCount: seats))
    }

    private func band(_ layout: BoardLayout) -> [CGPoint] {
        BoardOrnament.offset(
            layout.outline(inflatedBy: layout.surfaceMargin),
            by: -layout.pitch * 0.675
        )
    }

    private func perimeter(of polyline: [CGPoint]) -> CGFloat {
        zip(polyline, polyline.dropFirst() + polyline.prefix(1))
            .reduce(CGFloat.zero) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    @Test("the border closes evenly on every table size", arguments: 2...6)
    func borderIsSymmetricPerSeat(seats: Int) {
        let layout = layout(seats: seats)
        let count = BoardOrnament.motifCount(
            perimeter: perimeter(of: band(layout)),
            spacing: layout.pitch * 1.15,
            seats: seats
        )
        // Symmetric under the board's own rotation, and alternating cleanly:
        // an odd count would put two tulips side by side at the seam.
        #expect(count.isMultiple(of: seats))
        #expect(count.isMultiple(of: 2))
        #expect(count >= seats * 2)
    }

    @Test("motifs are spread at equal arc length", arguments: 2...6)
    func motifsAreEvenlySpaced(seats: Int) {
        let layout = layout(seats: seats)
        let polyline = band(layout)
        let placements = BoardOrnament.placements(along: polyline, count: 24)
        #expect(placements.count == 24)

        let gaps = zip(placements, placements.dropFirst()).map {
            hypot($1.point.x - $0.point.x, $1.point.y - $0.point.y)
        }
        let mean = gaps.reduce(0, +) / CGFloat(gaps.count)
        // Chord length varies slightly with curvature; anything beyond a few
        // percent would be visible bunching at the corners.
        #expect(gaps.allSatisfy { abs($0 - mean) / mean < 0.06 })
    }

    @Test("every motif faces away from the middle of the board")
    func motifsFaceOutward() {
        let layout = layout(seats: 4)
        for placement in BoardOrnament.placements(along: band(layout), count: 32) {
            // The motif is drawn with +y outward, so rotating (0, 1) by the
            // placement's rotation must point away from the origin.
            let outward = CGPoint(
                x: -sin(placement.rotation),
                y: cos(placement.rotation)
            )
            let radial = hypot(placement.point.x, placement.point.y)
            let alignment = (outward.x * placement.point.x + outward.y * placement.point.y) / radial
            #expect(alignment > 0.5, "a motif leaned inward at \(placement.point)")
        }
    }

    @Test("the border never strays onto a playing square", arguments: 2...6)
    func ornamentStaysClearOfTheGame(seats: Int) {
        let layout = layout(seats: seats)
        let placements = BoardOrnament.placements(
            along: band(layout),
            count: BoardOrnament.motifCount(
                perimeter: perimeter(of: band(layout)),
                spacing: layout.pitch * 1.15,
                seats: seats
            )
        )
        // Half a motif plus half a square is the point at which the two would
        // touch. Ornament a player could mistake for a square is a rule
        // problem, not a taste problem.
        let clearance = layout.pitch * 0.46 / 2 + layout.squareSize / 2

        for position in layout.allPositions {
            let square = layout.point(for: position)
            let nearest = placements
                .map { hypot($0.point.x - square.x, $0.point.y - square.y) }
                .min() ?? .greatestFiniteMagnitude
            #expect(nearest > clearance, "a motif crowded \(position)")
        }
    }

    @Test("the medallion sits in the gaps between home lanes, never on one", arguments: 2...6)
    func medallionAvoidsTheLanes(seats: Int) {
        let layout = layout(seats: seats)
        let laneAngles = layout.homePoints.compactMap { $0.last.map { atan2($0.y, $0.x) } }
        let angles = BoardOrnament.medallionAngles(seats: seats, laneAngles: laneAngles)
        #expect(angles.count == seats)

        for angle in angles {
            for lane in laneAngles {
                var delta = abs(angle - lane).truncatingRemainder(dividingBy: 2 * .pi)
                if delta > .pi { delta = 2 * .pi - delta }
                // Half the gap between neighbouring lanes, with room to spare.
                #expect(delta > .pi / CGFloat(seats) * 0.8)
            }
        }
    }

    @Test("the border band keeps its width the whole way round", arguments: 2...6)
    func bandDoesNotPinch(seats: Int) {
        let layout = layout(seats: seats)
        let edge = layout.outline(inflatedBy: layout.surfaceMargin)
        let inner = BoardOrnament.offset(edge, by: -layout.pitch)

        // Radial inflation pinched the band to a fraction of its width at the
        // corners, which was plainly visible on the first capture. Every point
        // of the inner guide must now sit a full pitch from the edge.
        for point in inner {
            let nearest = edge
                .map { hypot($0.x - point.x, $0.y - point.y) }
                .min() ?? 0
            #expect(abs(nearest - layout.pitch) < layout.pitch * 0.1)
        }
    }

    @Test("the medallion either fits the inner field or is not drawn", arguments: 2...6)
    func medallionFitsOrIsOmitted(seats: Int) {
        let layout = layout(seats: seats)
        let innerField = layout.homePoints
            .compactMap { $0.last.map { hypot($0.x, $0.y) } }
            .min() ?? 0
        let radius = BoardOrnament.medallionRadius(
            innerField: innerField,
            square: layout.squareSize
        )

        guard let radius else {
            // Two seats: the home lanes reach almost to the middle, so there
            // is nothing to decorate. Omitting it is the correct answer, not a
            // gap — see KNOWN_ISSUES ISS-008.
            #expect(seats == 2)
            return
        }
        let outermost = radius * BoardOrnament.petalAnchor + layout.squareSize * 0.6
        #expect(outermost < innerField - layout.squareSize * 0.5)
    }

    @Test("a board with no quiet centre gets no medallion")
    func noRoomMeansNoMedallion() {
        #expect(BoardOrnament.medallionRadius(innerField: 1, square: 10) == nil)
        #expect(BoardOrnament.medallionRadius(innerField: 100, square: 10) != nil)
    }

    @Test("the ornament is the same every launch")
    func ornamentIsDeterministic() {
        let layout = layout(seats: 4)
        let first = BoardOrnament.placements(along: band(layout), count: 32)
        let second = BoardOrnament.placements(along: band(layout), count: 32)
        #expect(first == second)
    }

    @Test("tulip and lozenge alternate")
    func motifsAlternate() {
        #expect(BoardOrnament.Motif.at(0) == .tulip)
        #expect(BoardOrnament.Motif.at(1) == .lozenge)
        #expect(BoardOrnament.Motif.at(2) == .tulip)
    }

    @Test("every motif is drawn inside the box it is given")
    func motifsRespectTheirSize() {
        let size: CGFloat = 20
        let shapes = [
            BoardOrnament.tulip(size: size),
            BoardOrnament.lozenge(size: size),
            BoardOrnament.petal(size: size),
            BoardOrnament.chevron(size: size),
        ]
        // A motif that overflowed its box would collide with its neighbours
        // once the border packed them at a fixed spacing.
        for shape in shapes {
            let box = shape.boundingBox
            #expect(box.width <= size * 1.01)
            #expect(box.height <= size * 1.01)
        }
    }
}

/// ISS-020 — which layer wins a tap where a square and a piece overlap.
///
/// Both are given at least `Keezly.Target.minimum` to be tapped, and on a phone
/// the squares are smaller than that, so the two inflated areas overlap for
/// real. Whichever is drawn last takes the tap, and getting that order wrong
/// meant a highlighted destination beside a piece could not be tapped at all:
/// the piece swallowed it, the move was never made, and the turn never passed.
///
/// It failed only on iPhone. On iPad the squares are larger than 44pt, nothing
/// is inflated and nothing overlaps — which is why it looked like a test
/// harness fault for as long as it did.
@Suite("Board tap precedence")
@MainActor
struct BoardTapPrecedenceTests {

    private func board(selecting pawn: PawnID?) -> BoardView {
        BoardView(
            layout: BoardLayout(board: BoardGraph(seatCount: 4)),
            pawns: [],
            legalTargets: [],
            selectablePawns: [],
            selectedPawn: pawn
        )
    }

    @Test("while no piece is chosen, the piece wins the tap")
    func pieceWinsWhileChoosing() {
        #expect(board(selecting: nil).targetsTakePrecedence == false)
    }

    @Test("once a piece is chosen, the square wins the tap")
    func squareWinsAfterChoosing() {
        #expect(board(selecting: PawnID(seat: Seat(0), slot: 0)).targetsTakePrecedence)
    }
}
