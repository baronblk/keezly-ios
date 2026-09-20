import CoreGraphics
import Foundation
import KeezlyCore

/// Turns the engine's topology into coordinates (§9, DEC-001).
///
/// `KeezlyCore` knows that a pawn is seven squares from its home entry; it does
/// not know where that is on screen, and must not. This type is the only place
/// that decides. It is parametric over 2–6 seats exactly as the board is, so a
/// six-player table is not a special case with its own hand-placed squares.
///
/// Everything is computed in **unit space**: a square region centred on the
/// origin, with the track ring inscribed at radius 1. Views scale that to
/// whatever room they have, which is what lets the same board look right on an
/// iPhone in portrait and filling an iPad in landscape.
///
/// The ring is a superellipse rather than a circle. A circle reads as a
/// roulette wheel; a rounded square reads as a board, gives the four sides the
/// eye expects, and still distributes any seat count evenly.
struct BoardLayout: Sendable {

    /// Superellipse exponent.
    ///
    /// A traditional Keezen board is a square with straight runs of holes and
    /// rounded corners — that shape belongs to the game, not to any publisher,
    /// and players expect it. 8 gives straight sides and a soft corner: close
    /// to the familiar form, drawn from our own curve rather than copied from
    /// anyone's artwork (§76).
    static let ringExponent: Double = 8
    /// How much of the distance between neighbouring squares a square occupies.
    /// Below 1 so the track reads as separate squares rather than a stripe.
    static let squareFill: Double = 0.66
    /// How far outside the ring the waiting area sits, in square widths.
    static let waitingOffset: Double = 1.75

    let board: BoardGraph

    /// One point per track square, in track-index order.
    let trackPoints: [CGPoint]
    /// Four points per seat, indexed by seat then home slot (0 = nearest entry).
    let homePoints: [[CGPoint]]
    /// Four points per seat, indexed by seat then waiting slot.
    let waitingPoints: [[CGPoint]]
    /// Edge length of a square in unit space.
    let squareSize: CGFloat
    /// How far past the track ring the board's edge sits, in unit space.
    ///
    /// Wide enough that the waiting areas stand *on* the board rather than
    /// hanging off it — a physical board has room for the pieces that are not
    /// yet in play.
    let surfaceMargin: CGFloat
    /// The extent everything occupies, so a view can scale to fit exactly.
    let contentBounds: CGRect
    /// The board's outline, as a closed polygon in unit space. Decimated from
    /// the sampling used to place the squares, so the drawn edge and the square
    /// positions come from the same curve.
    let outline: [CGPoint]

    init(board: BoardGraph) {
        self.board = board

        let count = board.mainTrackCount
        let ring = Self.ringSamples()
        // Computed once and reused for every square. Recomputing it per square
        // is O(samples) each time, which at this resolution is millions of
        // operations for a board that never changes.
        let lengths = Self.arcLengths(of: ring)
        let perimeter = lengths.last ?? 1

        // Squares sit at equal *arc length* around the ring, not at equal
        // angle: on a superellipse those are different, and equal angle would
        // bunch the squares up at the corners.
        //
        // Index `count - 1` is seat 0's home entry, and it is placed at the
        // bottom of the board so the local player's home lane runs up towards
        // the centre — the orientation a player at the near edge expects.
        var points: [CGPoint] = []
        points.reserveCapacity(count)
        for index in 0..<count {
            let fraction = Double((index + 1) % count) / Double(count)
            points.append(Self.point(onRing: ring, lengths: lengths, atFraction: fraction))
        }
        self.trackPoints = points

        let pitch = perimeter / Double(count)
        let size = pitch * Self.squareFill
        self.squareSize = size
        self.surfaceMargin = pitch * (Self.waitingOffset + 1.9)

        // Home lanes run from each seat's entry square straight towards the
        // centre, which keeps every seat's lane the same length and angle
        // relative to its own side.
        var homes: [[CGPoint]] = []
        var waits: [[CGPoint]] = []
        for seat in board.seats {
            let entry = points[board.homeEntryIndex(for: seat)]
            let inward = Self.normalised(CGPoint(x: -entry.x, y: -entry.y))
            homes.append((0..<pawnsPerSeat).map { slot in
                CGPoint(
                    x: entry.x + inward.x * pitch * Double(slot + 1),
                    y: entry.y + inward.y * pitch * Double(slot + 1)
                )
            })

            // The waiting area sits just outside the ring by the seat's own
            // start square, which is where its pawns enter the board.
            let start = points[board.startIndex(for: seat)]
            let outward = Self.normalised(start)
            let tangent = CGPoint(x: -outward.y, y: outward.x)
            let anchor = CGPoint(
                x: start.x + outward.x * pitch * Self.waitingOffset,
                y: start.y + outward.y * pitch * Self.waitingOffset
            )
            // A 2×2 cluster reads as "four waiting pieces" at any size.
            waits.append((0..<pawnsPerSeat).map { slot in
                let column = Double(slot % 2) - 0.5
                let row = Double(slot / 2) - 0.5
                return CGPoint(
                    x: anchor.x + tangent.x * column * pitch + outward.x * row * pitch,
                    y: anchor.y + tangent.y * column * pitch + outward.y * row * pitch
                )
            })
        }
        self.homePoints = homes
        self.waitingPoints = waits

        // Decimate the dense sampling for drawing: 240 points is smooth at any
        // size Keezly is played at, and avoids handing a 4096-point path to
        // the renderer on every frame.
        let stride = max(1, (ring.count - 1) / 240)
        self.outline = Swift.stride(from: 0, to: ring.count - 1, by: stride).map { ring[$0] }

        self.contentBounds = Self.bounds(
            of: points + homes.flatMap(\.self) + waits.flatMap(\.self),
            padding: size
        )
    }

    // MARK: - Lookup

    /// Where a pawn standing on `position` is drawn, in unit space.
    func point(for position: BoardPosition) -> CGPoint {
        switch position {
        case .track(let index):
            trackPoints[index % trackPoints.count]
        case .home(let seat, let slot):
            homePoints[seat.index][slot]
        case .waiting(let seat, let slot):
            waitingPoints[seat.index][slot]
        }
    }

    /// The board's edge, pushed out by `margin` so the track squares sit
    /// comfortably inside it rather than on its rim.
    func outline(inflatedBy margin: CGFloat) -> [CGPoint] {
        outline.map { point in
            let length = hypot(point.x, point.y)
            guard length > 0 else { return point }
            return CGPoint(
                x: point.x * (length + margin) / length,
                y: point.y * (length + margin) / length
            )
        }
    }

    /// The rectangle a seat's four waiting squares occupy, for drawing a tray.
    func waitingTray(for seat: Seat) -> CGRect {
        Self.bounds(of: waitingPoints[seat.index], padding: squareSize * 0.9)
    }

    /// Every position on this board, for rendering the empty squares.
    var allPositions: [BoardPosition] {
        var positions: [BoardPosition] = (0..<board.mainTrackCount).map { .track(index: $0) }
        for seat in board.seats {
            positions += (0..<pawnsPerSeat).map { .home(seat: seat, slot: $0) }
            positions += (0..<pawnsPerSeat).map { .waiting(seat: seat, slot: $0) }
        }
        return positions
    }

    // MARK: - Ring geometry

    /// Dense samples of the superellipse, used to walk it by arc length.
    ///
    /// The resolution has to carry the corners: a squared ring turns sharply,
    /// and too coarse a polygon makes the chords there measurably shorter than
    /// the arc, which shows up as uneven square spacing. 16384 keeps the worst
    /// spacing deviation under half a percent.
    private static func ringSamples(resolution: Int = 16_384) -> [CGPoint] {
        (0...resolution).map { step in
            // Start at the bottom of the board and go clockwise, so fraction 0
            // is where the local player sits.
            let angle = Double(step) / Double(resolution) * 2 * .pi + .pi / 2
            return superellipsePoint(at: angle)
        }
    }

    private static func superellipsePoint(at angle: Double) -> CGPoint {
        let exponent = 2 / ringExponent
        let cosine = cos(angle)
        let sine = sin(angle)
        return CGPoint(
            x: (cosine < 0 ? -1 : 1) * pow(abs(cosine), exponent),
            y: (sine < 0 ? -1 : 1) * pow(abs(sine), exponent)
        )
    }

    private static func arcLengths(of samples: [CGPoint]) -> [Double] {
        var lengths: [Double] = [0]
        lengths.reserveCapacity(samples.count)
        for index in 1..<samples.count {
            let previous = samples[index - 1]
            let current = samples[index]
            let step = hypot(current.x - previous.x, current.y - previous.y)
            lengths.append(lengths[index - 1] + step)
        }
        return lengths
    }

    /// The point `fraction` of the way around the ring, measured by arc length.
    private static func point(onRing samples: [CGPoint], lengths: [Double], atFraction fraction: Double) -> CGPoint {
        let target = fraction * (lengths.last ?? 1)

        // Binary search for the sample pair spanning the target length.
        var low = 0
        var high = lengths.count - 1
        while low < high - 1 {
            let middle = (low + high) / 2
            if lengths[middle] <= target { low = middle } else { high = middle }
        }

        let span = lengths[high] - lengths[low]
        let t = span > 0 ? (target - lengths[low]) / span : 0
        return CGPoint(
            x: samples[low].x + (samples[high].x - samples[low].x) * t,
            y: samples[low].y + (samples[high].y - samples[low].y) * t
        )
    }

    private static func normalised(_ point: CGPoint) -> CGPoint {
        let length = hypot(point.x, point.y)
        guard length > 0 else { return CGPoint(x: 0, y: -1) }
        return CGPoint(x: point.x / length, y: point.y / length)
    }

    private static func bounds(of points: [CGPoint], padding: Double) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            .insetBy(dx: -padding, dy: -padding)
    }
}
