import CoreGraphics
import Foundation
import KeezlyCore

/// Where the table's own cards are shown.
enum CentrePlacement: Equatable {
    /// In the middle of the board, where a board game puts them (§35).
    case inside
    /// Beside the board, for a table whose board has no middle.
    case beside
}

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
    /// A traditional Keezen board is a square with runs of holes and rounded
    /// corners — that shape belongs to the game, not to any publisher, and
    /// players expect it. It is drawn from our own curve rather than copied
    /// from anyone's artwork (§76).
    ///
    /// **5, not 8.** Eight gives almost dead-straight sides and puts all the
    /// curvature into a short corner, so the silhouette changes direction
    /// abruptly: the eye reads the join between the flat and the corner as a
    /// corner of its own, and the whole outline looks stamped out rather than
    /// milled. Five spreads the same turn over a longer arc — the curvature
    /// changes continuously, there is no point on the edge where the shape
    /// visibly *starts* turning, and it still reads unmistakably as a rounded
    /// square rather than an oval.
    static let ringExponent: Double = 5
    /// How many points the drawn outline is resampled to.
    ///
    /// Spaced by distance along the curve and joined with cubic segments, so
    /// this is about smoothness of *shape*, not of rendering: 192 is well past
    /// the point where another point changes anything visible, and far short of
    /// handing the renderer a path it has to think about.
    static let outlineResolution = 192
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
    /// Centre-to-centre spacing of adjacent track squares, in unit space.
    /// The board's natural rhythm — ornament is measured in it so that a
    /// two-player board and a six-player one look equally well proportioned.
    var pitch: CGFloat { squareSize / Self.squareFill }

    /// How far the quiet middle reaches, in unit space: the distance from the
    /// centre to the deepest home square of the nearest seat.
    var innerFieldRadius: CGFloat {
        homePoints.compactMap { $0.last.map { hypot($0.x, $0.y) } }.min() ?? 0
    }

    /// Where the draw pile, the played card and the turn indicator belong.
    ///
    /// The home lanes are four squares long whatever the table size, but the
    /// track is sixteen squares *per seat*. On a two-seat board the lanes
    /// therefore reach almost to the middle — measured, the quiet field is
    /// **1.2 square pitches**, against 2.7 at three seats and 4.9 at four.
    /// There is not enough middle to put a draw pile in.
    ///
    /// So a two-player table is presented differently: the cards sit beside
    /// the board, the way a deck sits on the table next to a small board,
    /// rather than being shrunk until they are unreadable (ISS-013). Nothing
    /// about the rules or the board itself changes — `BoardGraph` is untouched
    /// and the two boards are the same game.
    var centrePlacement: CentrePlacement {
        Self.centrePlacement(innerFieldRadius: innerFieldRadius, pitch: pitch)
    }

    static func centrePlacement(innerFieldRadius: CGFloat, pitch: CGFloat) -> CentrePlacement {
        guard pitch > 0 else { return .beside }
        // A pile and a played card need something like a square and a half of
        // clearance either side of the centre. Below that they would be drawn
        // across the home lanes.
        return innerFieldRadius / pitch >= 1.5 ? .inside : .beside
    }

    /// How wide something laid out in the quiet middle may be, as a fraction
    /// of the extent a view scales to fit.
    ///
    /// `aspect` is the content's height over its width. What has to fit inside
    /// a round field is the content's **diagonal**, not its width, which is
    /// why a block twice as tall as it is wide gets less than half the
    /// diameter.
    ///
    /// Measured against `contentBounds` because that is what a view fits —
    /// and that is the whole point of having this. The middle content used to
    /// be sized as a fixed fraction of the view, which was the same thing
    /// while `contentBounds` was the playing squares. It stopped being the
    /// same thing the moment the bounds grew to include the panel, its shadow
    /// and the air around it: the board got smaller inside its frame and the
    /// draw pile did not, so the pile ended up about a fifth too large and
    /// the round label sat out on the home lanes.
    func centreWidthFraction(aspect: CGFloat) -> CGFloat {
        guard contentBounds.width > 0, aspect > 0 else { return 0 }
        let diameter = innerFieldRadius * 2 / contentBounds.width
        return diameter * Self.centreClearance / hypot(1, aspect)
    }

    /// How close the middle content may come to the first home square.
    ///
    /// Not touching it. A draw pile whose corner meets a home square reads as
    /// a collision even when it is geometrically clear.
    static let centreClearance: CGFloat = 0.94

    /// How much of the board is quiet middle, as a fraction of its whole
    /// extent.
    ///
    /// The home lanes run inwards from the track, so the fewer seats there
    /// are, the shorter the track and the closer the lanes come to the centre.
    /// A two-player board has barely any middle at all. Anything placed there
    /// — a medallion, the cards — has to be measured against this rather than
    /// against the size of the view (ISS-008).
    var innerFieldFraction: CGFloat {
        // Measured against the track, not the frame. The margin of air around
        // the board is a layout decision and has nothing to do with how much
        // quiet middle the *playing area* has.
        let extent = trackPoints.map { max(abs($0.x), abs($0.y)) }.max() ?? 0
        guard extent > 0 else { return 0 }
        let inner = homePoints.compactMap { $0.last.map { hypot($0.x, $0.y) } }.min() ?? 0
        return inner / extent
    }

    /// The classic four-player board's quiet middle, which everything else is
    /// proportioned against.
    static let classicInnerFieldFraction: CGFloat =
        BoardLayout(board: BoardGraph(seatCount: 4)).innerFieldFraction
    /// How far past the track ring the board's edge sits, in unit space.
    ///
    /// Wide enough that the waiting areas stand *on* the board rather than
    /// hanging off it — a physical board has room for the pieces that are not
    /// yet in play.
    let surfaceMargin: CGFloat
    /// The extent everything occupies, so a view can scale to fit exactly.
    ///
    /// Includes the panel, the shadow it casts and a deliberate margin of air
    /// around it, so the board reads as an object on a table rather than a
    /// surface pressed into its container.
    let contentBounds: CGRect
    /// The drawn panel alone, without the shadow or the air. What a test
    /// measures when it asks whether the board has room around it.
    let panelBounds: CGRect
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
        // Wide enough to carry the ornamental border as well as the waiting
        // areas. A rim too narrow for its border is what makes a decorated
        // board look crowded, so the frame was widened rather than the
        // ornament squeezed into the gap (§76).
        self.surfaceMargin = pitch * (Self.waitingOffset + 2.75)

        // Home lanes run from each seat's entry square straight towards the
        // centre, which keeps every seat's lane the same length and angle
        // relative to its own side.
        var homes: [[CGPoint]] = []
        var waits: [[CGPoint]] = []
        for seat in board.seats {
            let entry = points[board.homeEntryIndex(for: seat)]
            let inward = Self.normalised(CGPoint(x: -entry.x, y: -entry.y))
            // Two seats get their lanes set side by side rather than head to
            // head; every other table runs them straight in. See `laneOffset`.
            let sideways = Self.laneOffset(along: inward, seatCount: board.seatCount, pitch: pitch)
            homes.append((0..<pawnsPerSeat).map { slot in
                CGPoint(
                    x: entry.x + sideways.x + inward.x * pitch * Double(slot + 1),
                    y: entry.y + sideways.y + inward.y * pitch * Double(slot + 1)
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

        // Resampled by **arc length**, not by index.
        //
        // The dense ring is sampled at equal *angles*, and on a superellipse
        // equal angles are nowhere near equal distances: the samples crowd
        // along the flats and thin out round the corners — exactly backwards,
        // because the corners are where all the curvature is. Decimating that
        // by index left the corners with a handful of points, and the corners
        // were then drawn as short straight chords. That is what made the
        // silhouette look faceted, and faceted is what "cut out" looks like.
        //
        // Walking the ring by distance puts the same number of points in every
        // millimetre of edge, so the corners get their share.
        self.outline = (0..<Self.outlineResolution).map { index in
            Self.point(
                onRing: ring,
                lengths: lengths,
                atFraction: Double(index) / Double(Self.outlineResolution)
            )
        }

        // The panel, which is what is actually drawn — not the squares on it.
        //
        // This used to measure the *playing positions* and pad them by one
        // square. But the panel is inflated by `surfaceMargin`, several squares
        // further out, so the thing being scaled to fit was smaller than the
        // thing being drawn: the board's rounded corners, its border ornament
        // and its shadow were all pushed past the edge of the view. It was not
        // clipped — it was worse than clipped, because it looked deliberate.
        let panel = Self.inflated(self.outline, by: self.surfaceMargin)
        self.panelBounds = Self.bounds(of: panel, padding: 0)

        // Room for the shadow the panel casts, and then air.
        //
        // The board is a physical object standing on a table. An object whose
        // edge touches the frame is not standing on anything — and when space
        // runs short the board is drawn a little smaller rather than a little
        // closer to the edge (§43).
        let shadowAllowance = size * 2.0
        let breathingRoom = size * 1.4
        self.contentBounds = Self.bounds(of: panel, padding: shadowAllowance + breathingRoom)
    }

    /// How far a seat's home lane is set to one side of its entry square.
    ///
    /// Zero for four seats and up, which is what a real board does: with four
    /// or six lanes arriving from different sides they meet in the middle as
    /// spokes, and the shape reads immediately.
    ///
    /// **Two seats are a different composition and are given one.** With only
    /// two entries, and those opposite each other, lanes that run straight in
    /// fall on the same line: the two meet nose to nose and form a single
    /// column through the middle. Nothing about it is wrong — and it looks
    /// like arithmetic rather than a board. There is no centre left, and
    /// nothing tells you at a glance which half of that column is whose.
    ///
    /// So a two-seat table sets each lane a little to one side. The two then
    /// run **parallel, side by side**, each still straight in from its own
    /// player's entry, and the half-turn that maps one seat onto the other
    /// maps one lane onto the other exactly. Between them the middle is
    /// genuinely empty, which is what lets a two-player table keep the draw
    /// pile where every other table has it (ISS-008, ISS-013, DEC-021).
    ///
    /// Presentation only. `BoardGraph` is untouched, the rules are untouched,
    /// and a home square is the same home square wherever it is drawn.
    private static func laneOffset(along inward: CGPoint, seatCount: Int, pitch: CGFloat) -> CGPoint {
        guard seatCount == 2 else { return .zero }
        // Perpendicular to the lane, and the same way round in world space for
        // both seats — which is what makes the pair symmetric under a
        // half-turn rather than mirrored.
        let tangent = CGPoint(x: -inward.y, y: inward.x)
        return CGPoint(x: tangent.x * pitch * twoSeatLaneOffset, y: tangent.y * pitch * twoSeatLaneOffset)
    }

    /// How far off its entry a two-seat home lane sits, in squares.
    ///
    /// Far enough that the two lanes clear each other with a square of board
    /// between them, and no further: a lane that wandered away from its own
    /// entry would stop looking like that player's lane.
    static let twoSeatLaneOffset: CGFloat = 1.15

    /// Pushes a closed outline out along its own radius.
    private static func inflated(_ outline: [CGPoint], by margin: CGFloat) -> [CGPoint] {
        outline.map { point in
            let length = hypot(point.x, point.y)
            guard length > 0 else { return point }
            return CGPoint(
                x: point.x * (length + margin) / length,
                y: point.y * (length + margin) / length
            )
        }
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
