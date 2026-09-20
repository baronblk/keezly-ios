import SwiftUI

/// One playing piece.
///
/// Its seat is carried by colour **and** by the mark stamped on it, so the
/// board stays readable without colour vision (§42, §44). The states it can be
/// in — selectable, selected — are shown by ring and lift, not by hue alone.
struct PawnView: View {
    let identity: PlayerIdentity
    let diameter: CGFloat
    var isSelectable = false
    var isSelected = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    // A soft vertical gradient reads as a rounded physical
                    // piece without tipping into skeuomorphism (§43).
                    LinearGradient(
                        colors: [identity.color.opacity(0.95), identity.color.opacity(0.72)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    Circle().strokeBorder(.black.opacity(0.18), lineWidth: max(0.5, diameter * 0.04))
                )
                .shadow(color: .black.opacity(0.28), radius: diameter * 0.12, y: diameter * 0.06)

            MarkShape(mark: identity.mark)
                .fill(.white.opacity(0.92))
                .frame(width: diameter * 0.52, height: diameter * 0.52)

            if isSelectable || isSelected {
                Circle()
                    .strokeBorder(
                        isSelected ? Keezly.Palette.legalTarget : Keezly.Palette.selectable,
                        lineWidth: max(1.5, diameter * 0.1)
                    )
                    .padding(-diameter * 0.08)
            }
        }
        .frame(width: diameter, height: diameter)
        // The drawn piece is often smaller than a finger; the tappable area
        // is not (§53).
        .contentShape(Circle().inset(by: -max(0, (Keezly.Target.minimum - diameter) / 2)))
        .scaleEffect(isSelected ? 1.12 : 1)
    }
}

/// A `PawnMark` as a `Shape`, so it can be filled, animated and masked.
struct MarkShape: Shape {
    let mark: PawnMark

    func path(in rect: CGRect) -> Path {
        mark.path(in: rect)
    }
}
