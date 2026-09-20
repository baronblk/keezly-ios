import SwiftUI

/// Where the pips go on a number card.
///
/// The arrangement is the traditional one — that layout is as old as the deck
/// and belongs to nobody. Positions are fractions of the pip field, and the
/// flag says whether the pip is rotated, as it is on the lower half of a real
/// card.
enum PipLayout {
    struct Pip: Hashable {
        let x: Double
        let y: Double
        let inverted: Bool
    }

    static func pips(for value: Int) -> [Pip] {
        let left = 0.24, right = 0.76, middle = 0.5
        switch value {
        case 1:
            return [Pip(x: middle, y: 0.5, inverted: false)]
        case 2:
            return [Pip(x: middle, y: 0.06, inverted: false), Pip(x: middle, y: 0.94, inverted: true)]
        case 3:
            return [
                Pip(x: middle, y: 0.06, inverted: false),
                Pip(x: middle, y: 0.5, inverted: false),
                Pip(x: middle, y: 0.94, inverted: true),
            ]
        case 4:
            return corners(left: left, right: right)
        case 5:
            return corners(left: left, right: right) + [Pip(x: middle, y: 0.5, inverted: false)]
        case 6:
            return corners(left: left, right: right) + [
                Pip(x: left, y: 0.5, inverted: false),
                Pip(x: right, y: 0.5, inverted: false),
            ]
        case 7:
            return pips(for: 6) + [Pip(x: middle, y: 0.28, inverted: false)]
        case 8:
            return pips(for: 7) + [Pip(x: middle, y: 0.72, inverted: true)]
        case 9:
            return quads(left: left, right: right) + [Pip(x: middle, y: 0.5, inverted: false)]
        case 10:
            return quads(left: left, right: right) + [
                Pip(x: middle, y: 0.28, inverted: false),
                Pip(x: middle, y: 0.72, inverted: true),
            ]
        default:
            return []
        }
    }

    private static func corners(left: Double, right: Double) -> [Pip] {
        [
            Pip(x: left, y: 0.06, inverted: false),
            Pip(x: right, y: 0.06, inverted: false),
            Pip(x: left, y: 0.94, inverted: true),
            Pip(x: right, y: 0.94, inverted: true),
        ]
    }

    private static func quads(left: Double, right: Double) -> [Pip] {
        [
            Pip(x: left, y: 0.06, inverted: false),
            Pip(x: right, y: 0.06, inverted: false),
            Pip(x: left, y: 0.35, inverted: false),
            Pip(x: right, y: 0.35, inverted: false),
            Pip(x: left, y: 0.65, inverted: true),
            Pip(x: right, y: 0.65, inverted: true),
            Pip(x: left, y: 0.94, inverted: true),
            Pip(x: right, y: 0.94, inverted: true),
        ]
    }
}

/// The court cards.
///
/// Traditional face-card illustrations are somebody's artwork; these are not
/// them (§76). Keezly draws its own: a reduced, symmetrical geometric emblem,
/// mirrored top and bottom the way a real court card is, in the suit's colour.
/// Timeless rather than cartoonish, and legible at the size a hand of cards is
/// actually seen.
struct CourtEmblem: Shape {
    enum Rank { case jack, queen, king }

    let rank: Rank

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height

        switch rank {
        case .king:
            // A stepped crown: three merlons over a band.
            let bandTop = rect.minY + height * 0.62
            path.move(to: CGPoint(x: rect.minX, y: bandTop))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + height * 0.22))
            path.addLine(to: CGPoint(x: rect.minX + width * 0.2, y: rect.minY + height * 0.44))
            path.addLine(to: CGPoint(x: rect.midX - width * 0.12, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX + width * 0.12, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - width * 0.2, y: rect.minY + height * 0.44))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + height * 0.22))
            path.addLine(to: CGPoint(x: rect.maxX, y: bandTop))
            path.closeSubpath()
            // A slim band under the crown, not a slab.
            path.addRoundedRect(
                in: CGRect(x: rect.minX + width * 0.06, y: bandTop + height * 0.14,
                           width: width * 0.88, height: height * 0.1),
                cornerSize: CGSize(width: height * 0.05, height: height * 0.05)
            )

        case .queen:
            // A coronet: a soft arc with a raised pearl.
            let arcTop = rect.minY + height * 0.3
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + height * 0.62))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + height * 0.62),
                control: CGPoint(x: rect.midX, y: arcTop - height * 0.26)
            )
            path.closeSubpath()
            path.addEllipse(in: CGRect(
                x: rect.midX - width * 0.11, y: rect.minY,
                width: width * 0.22, height: width * 0.22
            ))
            path.addRoundedRect(
                in: CGRect(x: rect.minX + width * 0.08, y: rect.minY + height * 0.78,
                           width: width * 0.84, height: height * 0.1),
                cornerSize: CGSize(width: height * 0.05, height: height * 0.05)
            )

        case .jack:
            // A plume: two sweeping chevrons.
            for offset in [0.0, 0.34] {
                var chevron = Path()
                let top = rect.minY + height * offset
                chevron.move(to: CGPoint(x: rect.minX, y: top + height * 0.34))
                chevron.addLine(to: CGPoint(x: rect.midX, y: top))
                chevron.addLine(to: CGPoint(x: rect.maxX, y: top + height * 0.34))
                chevron.addLine(to: CGPoint(x: rect.midX, y: top + height * 0.18))
                chevron.closeSubpath()
                path.addPath(chevron)
            }
        }
        return path
    }
}

/// The back of a Keezly card.
///
/// A lattice of small diamonds around a centred ring: symmetrical in both axes
/// so it looks right whichever way a card is dealt, and legible as a pattern
/// even at thumbnail size (§45).
struct CardBackPattern: View {
    var tint: Color = Color(hex: 0x1F4B5A)

    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 7
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(tint))

            // The lattice.
            var lattice = Path()
            var row = -1
            var y = -unit
            while y < size.height + unit {
                var x = row.isMultiple(of: 2) ? 0 : unit / 2
                while x < size.width + unit {
                    lattice.addPath(
                        SuitGlyph(suit: .diamond)
                            .path(in: CGRect(x: x - unit * 0.18, y: y - unit * 0.18,
                                             width: unit * 0.36, height: unit * 0.36))
                    )
                    x += unit
                }
                y += unit * 0.72
                row += 1
            }
            context.fill(lattice, with: .color(.white.opacity(0.16)))

            // A quiet centre, so the back has a focus without carrying a logo.
            let ring = min(size.width, size.height) * 0.3
            let centre = CGRect(
                x: size.width / 2 - ring / 2, y: size.height / 2 - ring / 2,
                width: ring, height: ring
            )
            context.stroke(Path(ellipseIn: centre), with: .color(.white.opacity(0.28)), lineWidth: unit * 0.1)
            context.stroke(
                Path(ellipseIn: centre.insetBy(dx: ring * 0.16, dy: ring * 0.16)),
                with: .color(.white.opacity(0.18)), lineWidth: unit * 0.06
            )
        }
    }
}
