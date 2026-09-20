import KeezlyCore
import SwiftUI

/// The board.
///
/// Drawn in two layers for a reason. The squares, lanes and rims never change
/// during a match, so they are one `Canvas` — a single draw pass with no view
/// tree to diff. The pawns move, so they are ordinary views that SwiftUI can
/// animate individually. A turn-based board game has no business running a
/// render loop (§62).
struct BoardView: View {
    let layout: BoardLayout
    let pawns: [PawnState]
    /// Positions to highlight as reachable by the current selection.
    var legalTargets: Set<BoardPosition> = []
    /// Pawns the player may pick up right now.
    var selectablePawns: Set<PawnID> = []
    var selectedPawn: PawnID?
    /// A pawn to pick out for a beat — just taken, or just home.
    var emphasised: PawnID?
    var onSelectPawn: ((PawnID) -> Void)?
    var onSelectTarget: ((BoardPosition) -> Void)?

    @Environment(\.boardTheme) private var theme

    var body: some View {
        GeometryReader { proxy in
            let transform = BoardTransform(bounds: layout.contentBounds, into: proxy.size)

            ZStack {
                BoardSurface(
                    layout: layout,
                    transform: transform,
                    theme: theme,
                    legalTargets: legalTargets
                )

                // Target squares first, so a pawn standing on one stays
                // tappable as a pawn.
                ForEach(Array(legalTargets), id: \.self) { target in
                    Color.clear
                        .frame(
                            width: max(Keezly.Target.minimum, transform.scaled(layout.squareSize)),
                            height: max(Keezly.Target.minimum, transform.scaled(layout.squareSize))
                        )
                        .contentShape(Rectangle())
                        .position(transform.point(layout.point(for: target)))
                        .onTapGesture { onSelectTarget?(target) }
                        .accessibilityIdentifier("target.\(Self.identifier(for: target))")
                        .accessibilityLabel("board.target")
                        .accessibilityAddTraits(.isButton)
                }

                ForEach(pawns, id: \.id) { pawn in
                    PawnView(
                        identity: PlayerIdentity.identity(for: pawn.id.seat),
                        diameter: transform.scaled(layout.squareSize) * 0.96,
                        isSelectable: selectablePawns.contains(pawn.id),
                        isSelected: selectedPawn == pawn.id,
                        isEmphasised: emphasised == pawn.id
                    )
                    // Anchored so the piece's base sits in its hole while its
                    // head rises above the board, as a real piece does.
                    .position(
                        x: transform.point(layout.point(for: pawn.position)).x,
                        y: transform.point(layout.point(for: pawn.position)).y
                            - transform.scaled(layout.squareSize) * 0.3
                    )
                    .onTapGesture { onSelectPawn?(pawn.id) }
                    .allowsHitTesting(selectablePawns.contains(pawn.id) || selectedPawn == pawn.id)
                    .accessibilityIdentifier("pawn.\(pawn.id.seat.index).\(pawn.id.slot)")
                }
            }
        }
        .aspectRatio(layout.contentBounds.width / layout.contentBounds.height, contentMode: .fit)
    }
}

extension BoardView {
    /// A stable identifier for a square, so UI tests can address one without
    /// depending on its label or its position on screen.
    static func identifier(for position: BoardPosition) -> String {
        switch position {
        case .track(let index): "track.\(index)"
        case .home(let seat, let slot): "home.\(seat.index).\(slot)"
        case .waiting(let seat, let slot): "waiting.\(seat.index).\(slot)"
        }
    }
}

/// Maps unit space onto the space a view actually has.
///
/// Kept separate from `BoardLayout` so the geometry stays pure and testable:
/// the layout knows proportions, this knows pixels.
struct BoardTransform {
    let scale: CGFloat
    let offset: CGPoint

    init(bounds: CGRect, into size: CGSize) {
        let raw = min(size.width / bounds.width, size.height / bounds.height)
        self.scale = raw.isFinite && raw > 0 ? raw : 1
        self.offset = CGPoint(
            x: size.width / 2 - bounds.midX * scale,
            y: size.height / 2 - bounds.midY * scale
        )
    }

    func point(_ unit: CGPoint) -> CGPoint {
        CGPoint(x: unit.x * scale + offset.x, y: unit.y * scale + offset.y)
    }

    func scaled(_ length: CGFloat) -> CGFloat { length * scale }
}
