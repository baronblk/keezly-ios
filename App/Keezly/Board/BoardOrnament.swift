import CoreGraphics
import Foundation
import KeezlyCore

/// The board's ornament geometry.
///
/// Keezen is a Dutch game, and Keezly says so — quietly (§76). The vocabulary
/// is drawn from Dutch ceramic and cabinet ornament: a fine running border, a
/// symmetric medallion, an abstracted tulip. It is **ornament, not
/// illustration**: no windmills, no clogs, no flags, nothing that would turn a
/// good board into a souvenir.
///
/// Every shape here is Keezly's own construction — arcs and lozenges built from
/// a few proportions — rather than a traced tile pattern. Inspiration from a
/// tradition is fair; copying a specific pattern is not.
///
/// Pure geometry, in unit space, with no colour and no drawing. That keeps it
/// testable: the questions worth asking — does the border repeat evenly, does
/// it stay clear of the playing squares, is it the same every launch — are all
/// answerable without a renderer.
enum BoardOrnament {

    /// A motif placed on the board: where it sits, and which way is "out".
    struct Placement: Equatable {
        let point: CGPoint
        /// Rotation that puts the motif's +y axis along the outward normal.
        let rotation: CGFloat
    }

    /// Which of the two alternating border motifs sits at an index.
    enum Motif: Equatable {
        case tulip
        case lozenge

        static func at(_ index: Int) -> Motif { index.isMultiple(of: 2) ? .tulip : .lozenge }
    }

    // MARK: - The band

    /// Offsets a closed polyline along its own outward normals.
    ///
    /// `BoardLayout.outline(inflatedBy:)` pushes points out along the radius,
    /// which is right for one curve and wrong for two. On a rounded square the
    /// radius and the normal diverge towards the corners, so two radial offsets
    /// are not parallel: the band between them visibly pinches exactly where
    /// the eye follows it round. Offsetting along the normal keeps the band the
    /// same width the whole way.
    static func offset(_ polyline: [CGPoint], by distance: CGFloat) -> [CGPoint] {
        guard polyline.count > 2 else { return polyline }
        return polyline.indices.map { index in
            let previous = polyline[(index - 1 + polyline.count) % polyline.count]
            let next = polyline[(index + 1) % polyline.count]
            let tangent = CGPoint(x: next.x - previous.x, y: next.y - previous.y)
            let length = hypot(tangent.x, tangent.y)
            guard length > 0 else { return polyline[index] }

            var normal = CGPoint(x: tangent.y / length, y: -tangent.x / length)
            let point = polyline[index]
            if normal.x * point.x + normal.y * point.y < 0 {
                normal = CGPoint(x: -normal.x, y: -normal.y)
            }
            return CGPoint(x: point.x + normal.x * distance, y: point.y + normal.y * distance)
        }
    }

    // MARK: - Placement

    /// How many motifs fit around a border of this length.
    ///
    /// Rounded to a multiple of the seat count so the border is symmetric under
    /// the board's own rotation — on a six-player board the pattern has to come
    /// out even six ways, not four. A border that does not close cleanly is the
    /// single most obvious way ornament looks cheap.
    static func motifCount(perimeter: CGFloat, spacing: CGFloat, seats: Int) -> Int {
        guard perimeter > 0, spacing > 0, seats > 0 else { return 0 }
        // Two motifs per seat minimum, so the alternation is visible at all.
        let ideal = max(2, Int((perimeter / spacing).rounded()))
        let perSeat = max(2, Int((Double(ideal) / Double(seats)).rounded()))
        // An even number per seat keeps tulip and lozenge alternating across
        // the seam where the pattern wraps.
        let even = perSeat.isMultiple(of: 2) ? perSeat : perSeat + 1
        return even * seats
    }

    /// Spreads `count` motifs at equal arc length around a closed polyline.
    ///
    /// Equal arc length rather than equal angle, for the same reason the track
    /// squares are placed that way: on a rounded square the two are different,
    /// and equal angle bunches the motifs at the corners.
    static func placements(along polyline: [CGPoint], count: Int) -> [Placement] {
        guard count > 0, polyline.count > 2 else { return [] }

        let closed = polyline + [polyline[0]]
        var lengths: [CGFloat] = [0]
        lengths.reserveCapacity(closed.count)
        for (a, b) in zip(closed, closed.dropFirst()) {
            lengths.append(lengths[lengths.count - 1] + hypot(b.x - a.x, b.y - a.y))
        }
        guard let perimeter = lengths.last, perimeter > 0 else { return [] }

        return (0..<count).map { index in
            let distance = perimeter * CGFloat(index) / CGFloat(count)
            let segment = Self.segment(containing: distance, in: lengths)
            let span = lengths[segment + 1] - lengths[segment]
            let t = span > 0 ? (distance - lengths[segment]) / span : 0

            let a = closed[segment]
            let b = closed[segment + 1]
            let point = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)

            return Placement(point: point, rotation: outwardRotation(from: a, to: b, at: point))
        }
    }

    /// The rotation that points a motif's +y axis away from the board's centre.
    ///
    /// Taken from the local tangent rather than from the radius: along the flat
    /// side of a rounded square those differ badly, and a motif tilted to the
    /// radius would visibly lean as it approached a corner.
    private static func outwardRotation(from a: CGPoint, to b: CGPoint, at point: CGPoint) -> CGFloat {
        let tangent = CGPoint(x: b.x - a.x, y: b.y - a.y)
        guard tangent.x != 0 || tangent.y != 0 else { return 0 }

        // Either perpendicular is a normal; take the one facing away from the
        // centre, which the board places at the origin.
        var normal = CGPoint(x: tangent.y, y: -tangent.x)
        if normal.x * point.x + normal.y * point.y < 0 {
            normal = CGPoint(x: -normal.x, y: -normal.y)
        }
        // The motif is drawn with +y outward, so rotate that axis onto it.
        return atan2(normal.y, normal.x) - .pi / 2
    }

    private static func segment(containing distance: CGFloat, in lengths: [CGFloat]) -> Int {
        var low = 0
        var high = lengths.count - 2
        while low < high {
            let mid = (low + high + 1) / 2
            if lengths[mid] <= distance { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// How big the centre medallion may be, or `nil` when there is no room.
    ///
    /// At two seats the home lanes run almost to the middle of the board and
    /// there is no quiet centre left to decorate. The honest answer there is no
    /// medallion at all: ornament drawn over the game is worse than none (§76).
    static func medallionRadius(innerField: CGFloat, square: CGFloat) -> CGFloat? {
        guard innerField > 0, square > 0 else { return nil }
        let radius = innerField * 0.72
        // A petal reaches past the ring, and the deepest home square needs its
        // own clearance on the other side.
        let outermost = radius * petalAnchor + square * 0.6
        guard outermost < innerField - square * 0.5 else { return nil }
        return radius
    }

    /// Where a petal sits, as a fraction of the medallion's radius.
    static let petalAnchor: CGFloat = 0.86

    /// Where the medallion's petals sit: in the gaps *between* the home lanes,
    /// never on one. The lanes carry the player colours and must stay the
    /// loudest thing inside the ring.
    static func medallionAngles(seats: Int, laneAngles: [CGFloat]) -> [CGFloat] {
        guard seats > 1, laneAngles.count == seats else { return [] }
        let sorted = laneAngles.sorted()
        return sorted.indices.map { index in
            let a = sorted[index]
            var b = sorted[(index + 1) % sorted.count]
            if b < a { b += 2 * .pi }
            return (a + b) / 2
        }
    }

    // MARK: - The motifs themselves

    /// One pointed leaf, rising from the origin along +y.
    ///
    /// The single building block of the tulip and the medallion petal, so the
    /// border and the centre are demonstrably the same hand.
    static func leaf(length: CGFloat, width: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addQuadCurve(to: CGPoint(x: 0, y: length), control: CGPoint(x: width, y: length * 0.45))
        path.addQuadCurve(to: .zero, control: CGPoint(x: -width, y: length * 0.45))
        path.closeSubpath()
        return path
    }

    /// An abstracted tulip: three leaves springing from one point.
    ///
    /// The first attempt drew a bud with curling side strokes and a stem.
    /// Rendered at a fifth of a square it did not read as a tulip at all — it
    /// read as a stray squiggle, which is worse than no ornament. Three
    /// symmetric leaves survive being small, which is the only size this is
    /// ever drawn at (§76). Fits a `size`-square box centred on the origin,
    /// +y outward.
    static func tulip(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let base = CGPoint(x: 0, y: -size * 0.5)

        // The centre leaf, full height.
        path.addPath(
            leaf(length: size, width: size * 0.17),
            transform: CGAffineTransform(translationX: base.x, y: base.y)
        )

        // Two shorter leaves fanned out either side, held below the centre so
        // the silhouette comes to a single point.
        for side in [CGFloat(1), -1] {
            path.addPath(
                leaf(length: size * 0.62, width: size * 0.12),
                transform: CGAffineTransform(rotationAngle: -side * .pi / 4)
                    .concatenating(CGAffineTransform(translationX: base.x, y: base.y))
            )
        }
        return path
    }

    /// A lozenge with concave sides — the quiet beat between two tulips.
    static func lozenge(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let r = size / 2
        let pinch = r * 0.42

        path.move(to: CGPoint(x: 0, y: r))
        path.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: pinch, y: pinch))
        path.addQuadCurve(to: CGPoint(x: 0, y: -r), control: CGPoint(x: pinch, y: -pinch))
        path.addQuadCurve(to: CGPoint(x: -r, y: 0), control: CGPoint(x: -pinch, y: -pinch))
        path.addQuadCurve(to: CGPoint(x: 0, y: r), control: CGPoint(x: -pinch, y: pinch))
        path.closeSubpath()
        return path
    }

    /// A petal for the centre medallion: the tulip's centre leaf alone, so the
    /// middle of the board stays calmer than its border.
    static func petal(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addPath(
            leaf(length: size, width: size * 0.2),
            transform: CGAffineTransform(translationX: 0, y: -size * 0.5)
        )
        return path
    }

    /// The chevron at the inner end of a home lane: two nested strokes aimed
    /// the way the pawns travel. Linear on purpose — anything round risks
    /// being read as another hole.
    static func chevron(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let w = size / 2
        for depth in [CGFloat(0), 0.42] {
            path.move(to: CGPoint(x: -w, y: -size * depth))
            path.addLine(to: CGPoint(x: 0, y: size * (0.5 - depth)))
            path.addLine(to: CGPoint(x: w, y: -size * depth))
        }
        return path
    }
}
