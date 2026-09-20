import SwiftUI

/// The silhouette of a Keezly playing piece.
///
/// A classic pawn — round head, collar, flared body — drawn as our own
/// geometry rather than modelled from anyone's product (§44). The proportions
/// are chosen so the outline is still unmistakable at the size a six-player
/// board leaves for it, which is the size that actually matters.
struct PawnSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + width * x, y: rect.minY + height * y)
        }

        var path = Path()

        // The body: a flared base narrowing to a neck.
        path.move(to: point(0.14, 1.00))
        path.addQuadCurve(to: point(0.35, 0.66), control: point(0.19, 0.88))
        path.addQuadCurve(to: point(0.385, 0.33), control: point(0.42, 0.52))
        path.addLine(to: point(0.615, 0.33))
        path.addQuadCurve(to: point(0.65, 0.66), control: point(0.58, 0.52))
        path.addQuadCurve(to: point(0.86, 1.00), control: point(0.81, 0.88))
        path.closeSubpath()

        // The collar, which is what stops the head reading as a separate dot.
        path.addRoundedRect(
            in: CGRect(x: rect.minX + width * 0.29, y: rect.minY + height * 0.30,
                       width: width * 0.42, height: height * 0.065),
            cornerSize: CGSize(width: width * 0.03, height: width * 0.03)
        )

        // The head.
        let radius = width * 0.21
        path.addEllipse(in: CGRect(
            x: rect.midX - radius, y: rect.minY + height * 0.035,
            width: radius * 2, height: radius * 2
        ))

        return path
    }
}

/// One playing piece.
///
/// Its seat is carried by colour **and** by the mark on its body, so the board
/// stays readable without colour vision and in greyscale (§42, §53). Depth
/// comes from a gradient, a single specular highlight and a contact shadow —
/// enough to read as a physical object, short of pretending to be a photograph
/// (§43).
struct PawnView: View {
    let identity: PlayerIdentity
    /// The width the piece occupies. Its height follows from the silhouette.
    let diameter: CGFloat
    var isSelectable = false
    var isSelected = false

    private var height: CGFloat { diameter * 1.28 }

    var body: some View {
        ZStack(alignment: .bottom) {
            // The piece's contact shadow on the board, which is what seats it
            // in its hole rather than floating above it.
            Ellipse()
                .fill(.black.opacity(0.32))
                .frame(width: diameter * 0.78, height: diameter * 0.2)
                .blur(radius: diameter * 0.06)
                .offset(y: diameter * 0.06)

            piece
        }
        .frame(width: diameter, height: height)
        // The drawn piece is often smaller than a finger; the tappable area
        // is not (§53).
        .contentShape(
            Rectangle().inset(by: -max(0, (Keezly.Target.minimum - diameter) / 2))
        )
        .scaleEffect(isSelected ? 1.14 : 1, anchor: .bottom)
        .animation(.spring(response: 0.26, dampingFraction: 0.72), value: isSelected)
    }

    private var piece: some View {
        ZStack {
            PawnSilhouette()
                .fill(
                    LinearGradient(
                        colors: [
                            identity.color.opacity(1).lighter(by: 0.18),
                            identity.color,
                            identity.color.darker(by: 0.22),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    PawnSilhouette()
                        .stroke(.black.opacity(0.3), lineWidth: max(0.5, diameter * 0.035))
                )

            // A single soft highlight on the head, up and to the left, matching
            // the light the board is lit by.
            Ellipse()
                .fill(.white.opacity(0.42))
                .frame(width: diameter * 0.17, height: diameter * 0.12)
                .blur(radius: diameter * 0.035)
                .offset(x: -diameter * 0.08, y: -height * 0.35)

            // The redundant, non-colour identifier.
            MarkShape(mark: identity.mark)
                .fill(.white.opacity(0.88))
                .frame(width: diameter * 0.28, height: diameter * 0.28)
                .offset(y: height * 0.26)

            if isSelectable || isSelected {
                PawnSilhouette()
                    .stroke(
                        isSelected ? Keezly.Palette.legalTarget : Keezly.Palette.selectable,
                        lineWidth: max(1.5, diameter * 0.09)
                    )
            }
        }
        .frame(width: diameter, height: height)
    }
}

/// A `PawnMark` as a `Shape`, so it can be filled, animated and masked.
struct MarkShape: Shape {
    let mark: PawnMark

    func path(in rect: CGRect) -> Path {
        mark.path(in: rect)
    }
}

extension Color {
    /// A lighter version, for the lit side of a piece.
    func lighter(by amount: Double) -> Color {
        blended(with: .white, amount: amount)
    }

    /// A darker version, for its shaded side.
    func darker(by amount: Double) -> Color {
        blended(with: .black, amount: amount)
    }

    private func blended(with other: Color, amount: Double) -> Color {
        let ratio = max(0, min(1, amount))
        return Color(
            UIColor(self).blended(with: UIColor(other), ratio: ratio)
        )
    }
}

private extension UIColor {
    func blended(with other: UIColor, ratio: Double) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = CGFloat(ratio)
        return UIColor(
            red: r1 + (r2 - r1) * t,
            green: g1 + (g2 - g1) * t,
            blue: b1 + (b2 - b1) * t,
            alpha: a1 + (a2 - a1) * t
        )
    }
}
