import SwiftUI

/// The four suit symbols, drawn as geometry.
///
/// The symbols themselves are centuries old and belong to nobody; what is drawn
/// here is our own construction of them, not anyone's artwork (§76). Drawing
/// rather than shipping glyphs means they scale cleanly from a corner index a
/// few points tall to a pip in the middle of a card.
struct SuitGlyph: Shape {
    let suit: CardSuitKind

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let box = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)

        switch suit {
        case .heart: return Self.heart(in: box, side: side)
        case .diamond: return Self.diamond(in: box, side: side)
        case .spade: return Self.spade(in: box, side: side)
        case .club: return Self.club(in: box, side: side)
        }
    }

    private static func heart(in box: CGRect, side: CGFloat) -> Path {
        var path = Path()
        let top = box.minY + side * 0.28
        path.move(to: CGPoint(x: box.midX, y: box.maxY))
        path.addCurve(
            to: CGPoint(x: box.minX, y: top),
            control1: CGPoint(x: box.minX + side * 0.06, y: box.maxY - side * 0.32),
            control2: CGPoint(x: box.minX, y: box.midY - side * 0.06)
        )
        path.addArc(
            center: CGPoint(x: box.minX + side * 0.25, y: top),
            radius: side * 0.25, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false
        )
        path.addArc(
            center: CGPoint(x: box.maxX - side * 0.25, y: top),
            radius: side * 0.25, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false
        )
        path.addCurve(
            to: CGPoint(x: box.midX, y: box.maxY),
            control1: CGPoint(x: box.maxX, y: box.midY - side * 0.06),
            control2: CGPoint(x: box.maxX - side * 0.06, y: box.maxY - side * 0.32)
        )
        path.closeSubpath()
        return path
    }

    /// Very slightly convex sides, so it reads as a drawn pip rather than as a
    /// rotated square.
    private static func diamond(in box: CGRect, side: CGFloat) -> Path {
        var path = Path()
        let bulge = side * 0.1
        path.move(to: CGPoint(x: box.midX, y: box.minY))
        path.addQuadCurve(
            to: CGPoint(x: box.maxX, y: box.midY),
            control: CGPoint(x: box.maxX - bulge, y: box.midY - bulge)
        )
        path.addQuadCurve(
            to: CGPoint(x: box.midX, y: box.maxY),
            control: CGPoint(x: box.maxX - bulge, y: box.midY + bulge)
        )
        path.addQuadCurve(
            to: CGPoint(x: box.minX, y: box.midY),
            control: CGPoint(x: box.minX + bulge, y: box.midY + bulge)
        )
        path.addQuadCurve(
            to: CGPoint(x: box.midX, y: box.minY),
            control: CGPoint(x: box.minX + bulge, y: box.midY - bulge)
        )
        path.closeSubpath()
        return path
    }

    private static func spade(in box: CGRect, side: CGFloat) -> Path {
        var path = Path()
        let tip = CGPoint(x: box.midX, y: box.minY)
        path.move(to: tip)
        path.addCurve(
            to: CGPoint(x: box.maxX, y: box.midY + side * 0.12),
            control1: CGPoint(x: box.midX + side * 0.24, y: box.minY + side * 0.22),
            control2: CGPoint(x: box.maxX, y: box.midY - side * 0.12)
        )
        path.addArc(
            center: CGPoint(x: box.maxX - side * 0.21, y: box.midY + side * 0.24),
            radius: side * 0.21, startAngle: .degrees(-40), endAngle: .degrees(150), clockwise: false
        )
        path.addLine(to: CGPoint(x: box.midX, y: box.midY + side * 0.3))
        path.addArc(
            center: CGPoint(x: box.minX + side * 0.21, y: box.midY + side * 0.24),
            radius: side * 0.21, startAngle: .degrees(30), endAngle: .degrees(220), clockwise: false
        )
        path.addCurve(
            to: tip,
            control1: CGPoint(x: box.minX, y: box.midY - side * 0.12),
            control2: CGPoint(x: box.midX - side * 0.24, y: box.minY + side * 0.22)
        )
        path.closeSubpath()
        path.addPath(stem(in: box, side: side))
        return path
    }

    private static func club(in box: CGRect, side: CGFloat) -> Path {
        var path = Path()
        let radius = side * 0.2
        path.addEllipse(in: CGRect(x: box.midX - radius, y: box.minY, width: radius * 2, height: radius * 2))
        path.addEllipse(in: CGRect(x: box.minX, y: box.midY - radius * 0.5, width: radius * 2, height: radius * 2))
        path.addEllipse(in: CGRect(
            x: box.maxX - radius * 2, y: box.midY - radius * 0.5,
            width: radius * 2, height: radius * 2
        ))
        path.addPath(stem(in: box, side: side))
        return path
    }

    /// The tapered stem shared by the spade and the club.
    private static func stem(in box: CGRect, side: CGFloat) -> Path {
        var stem = Path()
        stem.move(to: CGPoint(x: box.midX - side * 0.05, y: box.midY + side * 0.16))
        stem.addCurve(
            to: CGPoint(x: box.midX - side * 0.24, y: box.maxY),
            control1: CGPoint(x: box.midX - side * 0.06, y: box.midY + side * 0.34),
            control2: CGPoint(x: box.midX - side * 0.16, y: box.maxY - side * 0.04)
        )
        stem.addLine(to: CGPoint(x: box.midX + side * 0.24, y: box.maxY))
        stem.addCurve(
            to: CGPoint(x: box.midX + side * 0.05, y: box.midY + side * 0.16),
            control1: CGPoint(x: box.midX + side * 0.16, y: box.maxY - side * 0.04),
            control2: CGPoint(x: box.midX + side * 0.06, y: box.midY + side * 0.34)
        )
        stem.closeSubpath()
        return stem
    }
}

/// Which suit is drawn. Separate from `KeezlyCore.CardSuit` on purpose: the
/// engine's suit is decorative data, this is a drawing instruction, and the
/// rules must stay independent of both (§10).
enum CardSuitKind: String, CaseIterable, Sendable {
    case spade, heart, diamond, club

    /// Traditional colouring. Carries no rule meaning whatsoever.
    var isRed: Bool { self == .heart || self == .diamond }
}
