import SwiftUI

/// The candidates for Keezly's app icon (§79).
///
/// Three concepts, each drawn from what the board already is: the same maple,
/// the same milled holes, the same pawn silhouette, the same Delft-blue
/// engraving. Nothing is invented for the icon alone, so whichever wins, the
/// icon and the game look like the same object.
///
/// Drawn as code rather than exported from a drawing program, which is the
/// editable source the release needs: it re-renders at any size, in any
/// appearance, from one place.
///
/// Constraints the concepts are held to, all of them deliberate:
/// - **No lettering.** An icon 29 points across cannot carry a word, and a
///   name that has to be read is a name that has not been recognised.
/// - **No SF Symbol and no stock shape.** Every path here is Keezly's own.
/// - **It has to work at 29.** Concepts are compared at that size first and at
///   1024 second, because the small one is the one people actually see.
enum IconConcept: String, CaseIterable, Identifiable {
    /// The one that ships (DEC-026).
    static let chosen = IconConcept.table

    /// A corner of the board: the engraved rim, a run of milled holes, one
    /// pawn seated in one of them.
    case corner
    /// Four pawns round a centre — the table itself, seen from above.
    case table
    /// The engraved medallion from the middle of the board, with one pawn.
    case medallion

    var id: String { rawValue }

    /// What the concept is arguing for, in one line. Used by the comparison
    /// sheet and by the decision record.
    var argument: String {
        switch self {
        case .corner:
            "The board's own corner. Unmistakably a board game; the pawn gives it a subject."
        case .table:
            "Four seats round a middle. Says 'a game for several people' before it says anything else."
        case .medallion:
            "The Dutch engraving alone. The most distinctive and the least obviously a game."
        }
    }
}

/// One concept, drawn.
///
/// Sized in unit terms off `side`, so the same view renders correctly at 29 and
/// at 1024 without a second set of numbers.
struct AppIconArtwork: View {
    let concept: IconConcept
    let side: CGFloat
    /// The tinted appearance is a single-channel mask: iOS recolours it, so it
    /// must read as a silhouette with no colour of its own.
    var isMask = false

    private let theme = BoardTheme.classicWood

    var body: some View {
        ZStack {
            background
            switch concept {
            case .corner: corner
            case .table: table
            case .medallion: medallion
            }
        }
        .frame(width: side, height: side)
        .clipped()
    }

    // MARK: - Ground

    @ViewBuilder
    private var background: some View {
        if isMask {
            Color.black
        } else {
            // The maple, lit from the top left exactly as the board is.
            LinearGradient(
                colors: [theme.surfaceLight, theme.surfaceMid, theme.surfaceDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var ink: Color { isMask ? .white : theme.inlay }
    private var hole: Color { isMask ? .white.opacity(0.35) : theme.holeFill }
    private var lip: Color { isMask ? .clear : theme.holeLip.opacity(0.7) }

    // MARK: - Concepts

    /// A corner of the board, enlarged: the engraved rim, the track curving
    /// away, and one pawn seated in its hole.
    private var corner: some View {
        ZStack {
            // The rim: two engraved lines with the band between them, running
            // off the icon's edge as a real corner does.
            RoundedRectangle(cornerRadius: side * 0.36, style: .continuous)
                .strokeBorder(ink.opacity(isMask ? 0.9 : 0.55), lineWidth: side * 0.022)
                .frame(width: side * 1.52, height: side * 1.52)
                .offset(x: side * 0.44, y: side * 0.44)

            RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
                .strokeBorder(ink.opacity(isMask ? 0.9 : 0.34), lineWidth: side * 0.011)
                .frame(width: side * 1.34, height: side * 1.34)
                .offset(x: side * 0.44, y: side * 0.44)

            // The track: four holes following the corner round. Four rather
            // than five, so each one is large enough to still be a hole at 29.
            ForEach(0..<4, id: \.self) { index in
                let angle = Double(index) / 3 * 84 + 178
                milledHole(diameter: side * 0.18)
                    .offset(
                        x: side * 0.44 + cos(angle * .pi / 180) * side * 0.52,
                        y: side * 0.44 + sin(angle * .pi / 180) * side * 0.52
                    )
            }

            // The subject: one piece, seated, big enough to carry the icon on
            // its own when everything else has dissolved.
            pawn(diameter: side * 0.42, colour: Color(hex: 0xDC4F_4A))
                .offset(x: -side * 0.15, y: -side * 0.08)
        }
    }

    /// The table seen from above: four pieces round a quiet middle.
    ///
    /// The middle is the board's own engraved ring rather than a plain circle —
    /// two fine lines, the same Delft blue as the border. Small enough that no
    /// piece stands on it, which is what made an earlier, larger ring read as a
    /// line drawn *through* the pawns.
    private var table: some View {
        ZStack {
            Circle()
                .strokeBorder(ink.opacity(isMask ? 0.8 : 0.45), lineWidth: side * 0.016)
                .frame(width: side * 0.26, height: side * 0.26)
            Circle()
                .strokeBorder(ink.opacity(isMask ? 0.8 : 0.28), lineWidth: side * 0.008)
                .frame(width: side * 0.175, height: side * 0.175)

            ForEach(Array(Self.seatColours.enumerated()), id: \.offset) { index, colour in
                let angle = Double(index) / 4 * 360 - 90
                pawn(diameter: side * 0.32, colour: colour)
                    .offset(
                        x: cos(angle * .pi / 180) * side * 0.29,
                        // The pieces sit a little above their centre, because
                        // a pawn is drawn from its base and four of them
                        // aligned on their centres look as if the lower two
                        // have slipped.
                        y: sin(angle * .pi / 180) * side * 0.27 - side * 0.03
                    )
            }
        }
    }

    /// The engraving from the middle of the board, alone.
    private var medallion: some View {
        ZStack {
            // Six leaves rather than eight: at 29 points, eight strokes this
            // close together stop being a pattern and become a grey mesh.
            ForEach(0..<6, id: \.self) { index in
                Petal()
                    .stroke(ink.opacity(isMask ? 0.9 : 0.58), lineWidth: side * 0.022)
                    .frame(width: side * 0.26, height: side * 0.44)
                    .offset(y: -side * 0.22)
                    .rotationEffect(.degrees(Double(index) / 6 * 360))
            }

            Circle()
                .strokeBorder(ink.opacity(isMask ? 0.9 : 0.45), lineWidth: side * 0.016)
                .frame(width: side * 0.76, height: side * 0.76)

            // A disc behind the piece, so the leaves do not run through it.
            if !isMask {
                Circle()
                    .fill(theme.surfaceLight)
                    .frame(width: side * 0.4, height: side * 0.4)
            }

            pawn(diameter: side * 0.34, colour: Color(hex: 0xC46A_1A))
        }
    }

    // MARK: - Parts

    private static let seatColours: [Color] = [
        Color(hex: 0xDC4F_4A), Color(hex: 0x298C_AE),
        Color(hex: 0xE8B0_38), Color(hex: 0x5C99_59),
    ]

    /// A hole milled into the panel: a recess, a shadow at its upper rim and a
    /// thin lit lip at its lower one — the same three layers the board draws,
    /// at a thickness that survives being 5 pixels across.
    private func milledHole(diameter: CGFloat) -> some View {
        Circle()
            .fill(isMask ? AnyShapeStyle(Color.white.opacity(0.4)) : AnyShapeStyle(
                RadialGradient(
                    colors: [theme.holeShadow.opacity(0.55), hole],
                    center: .init(x: 0.36, y: 0.32),
                    startRadius: 0,
                    endRadius: diameter * 0.7
                )
            ))
            .frame(width: diameter, height: diameter)
            .overlay(
                Circle()
                    .strokeBorder(lip, lineWidth: diameter * 0.05)
                    .offset(y: diameter * 0.03)
            )
    }

    /// A piece, seated in its hole and lit from the same direction as the
    /// board, so it reads as an object rather than a sticker.
    private func pawn(diameter: CGFloat, colour: Color) -> some View {
        ZStack(alignment: .bottom) {
            if !isMask {
                Ellipse()
                    .fill(.black.opacity(0.3))
                    .frame(width: diameter * 0.8, height: diameter * 0.22)
                    .offset(y: diameter * 0.08)
                    .blur(radius: diameter * 0.06)
            }

            PawnSilhouette()
                .fill(
                    isMask
                        ? AnyShapeStyle(Color.white)
                        : AnyShapeStyle(LinearGradient(
                            colors: [colour.lighter(by: 0.2), colour, colour.darker(by: 0.24)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                )
                .overlay(
                    PawnSilhouette()
                        .stroke(.black.opacity(isMask ? 0 : 0.32), lineWidth: max(0.5, diameter * 0.04))
                )
                .frame(width: diameter, height: diameter * 1.28)
        }
    }
}

/// One leaf of the medallion: a closed pointed arc, the shape the board's
/// centre ornament is built from.
private struct Petal: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.midY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.midY)
        )
        path.closeSubpath()
        return path
    }
}

#Preview("Concepts") {
    HStack(spacing: 24) {
        ForEach(IconConcept.allCases) { concept in
            VStack(spacing: 8) {
                AppIconArtwork(concept: concept, side: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                AppIconArtwork(concept: concept, side: 29)
                    .clipShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
                Text(verbatim: concept.rawValue)
            }
        }
    }
    .padding(32)
}
