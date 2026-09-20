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

    var body: some View {
        GeometryReader { proxy in
            let transform = BoardTransform(bounds: layout.contentBounds, into: proxy.size)

            ZStack {
                BoardBackdrop(layout: layout, transform: transform, legalTargets: legalTargets)

                ForEach(pawns, id: \.id) { pawn in
                    PawnView(
                        identity: PlayerIdentity.identity(for: pawn.id.seat),
                        diameter: transform.scaled(layout.squareSize) * 0.82,
                        isSelectable: selectablePawns.contains(pawn.id),
                        isSelected: selectedPawn == pawn.id
                    )
                    .position(transform.point(layout.point(for: pawn.position)))
                }
            }
        }
        .aspectRatio(layout.contentBounds.width / layout.contentBounds.height, contentMode: .fit)
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

/// The static part of the board: the table, the squares and the lanes.
private struct BoardBackdrop: View {
    let layout: BoardLayout
    let transform: BoardTransform
    let legalTargets: Set<BoardPosition>

    var body: some View {
        Canvas { context, size in
            let squareSide = transform.scaled(layout.squareSize)

            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Keezly.Palette.table)
            )
            drawBoardSurface(in: context, squareSide: squareSide)
            drawWaitingTrays(in: context)
            drawHomeLanes(in: context, squareSide: squareSide)
            drawSquares(in: context, squareSide: squareSide)
        }
        .drawingGroup()
    }

    /// The board itself: a rounded-square panel the track sits on, so the
    /// pieces read as standing on an object rather than floating on the
    /// background (§43). Depth comes from a soft edge and a quiet gradient,
    /// not from imitation wood grain.
    private func drawBoardSurface(in context: GraphicsContext, squareSide: CGFloat) {
        let unitMargin = layout.surfaceMargin
        var path = Path()
        let points = layout.outline(inflatedBy: unitMargin).map(transform.point)
        guard let first = points.first else { return }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()

        var shadowed = context
        shadowed.addFilter(.shadow(color: .black.opacity(0.22), radius: squareSide * 0.5, y: squareSide * 0.22))
        shadowed.fill(path, with: .color(Keezly.Palette.board))

        context.stroke(path, with: .color(Keezly.Palette.rim), lineWidth: max(0.5, squareSide * 0.06))
    }

    /// A small tray under each seat's waiting pieces, so they read as parked
    /// rather than scattered on the table.
    private func drawWaitingTrays(in context: GraphicsContext) {
        for seat in layout.board.seats {
            let unitRect = layout.waitingTray(for: seat)
            let origin = transform.point(CGPoint(x: unitRect.minX, y: unitRect.minY))
            let rect = CGRect(
                x: origin.x,
                y: origin.y,
                width: transform.scaled(unitRect.width),
                height: transform.scaled(unitRect.height)
            )
            let shape = Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) * 0.26)
            context.fill(shape, with: .color(PlayerIdentity.identity(for: seat).color.opacity(0.10)))
            context.stroke(shape, with: .color(Keezly.Palette.rim), lineWidth: 0.75)
        }
    }

    /// A soft lane behind each seat's home squares, tinted with that seat's
    /// colour so the four private squares read as belonging to someone.
    private func drawHomeLanes(in context: GraphicsContext, squareSide: CGFloat) {
        for seat in layout.board.seats {
            let identity = PlayerIdentity.identity(for: seat)
            // Start the lane at the *first* home square, not at the entry: the
            // entry is a normal track square that everyone passes over, and
            // tinting it would suggest otherwise.
            let first = transform.point(layout.homePoints[seat.index][0])
            let deepest = transform.point(layout.homePoints[seat.index][pawnsPerSeat - 1])

            var lane = Path()
            lane.move(to: first)
            lane.addLine(to: deepest)
            context.stroke(
                lane,
                with: .color(identity.color.opacity(0.18)),
                style: StrokeStyle(lineWidth: squareSide * 1.25, lineCap: .round)
            )
        }
    }

    private func drawSquares(in context: GraphicsContext, squareSide: CGFloat) {
        for position in layout.allPositions {
            let centre = transform.point(layout.point(for: position))
            let rect = CGRect(
                x: centre.x - squareSide / 2,
                y: centre.y - squareSide / 2,
                width: squareSide,
                height: squareSide
            )
            let shape = Path(roundedRect: rect, cornerRadius: squareSide * 0.28)

            context.fill(shape, with: .color(fillColor(for: position)))
            context.stroke(shape, with: .color(Keezly.Palette.rim), lineWidth: max(0.5, squareSide * 0.05))

            // A seat's start square carries its colour and a ring, because
            // standing on it means something: the pawn there is untouchable
            // and blocks the track (§15).
            if let seat = startSeat(of: position) {
                let identity = PlayerIdentity.identity(for: seat)
                context.stroke(
                    shape,
                    with: .color(identity.color.opacity(0.9)),
                    lineWidth: max(1, squareSide * 0.12)
                )
            }

            if legalTargets.contains(position) {
                context.stroke(
                    shape,
                    with: .color(Keezly.Palette.legalTarget),
                    lineWidth: max(1.5, squareSide * 0.14)
                )
            }
        }
    }

    private func fillColor(for position: BoardPosition) -> Color {
        switch position {
        case .track:
            Keezly.Palette.square
        case .home(let seat, _), .waiting(let seat, _):
            PlayerIdentity.identity(for: seat).color.opacity(0.14)
        }
    }

    /// The seat whose start square this is, if any.
    private func startSeat(of position: BoardPosition) -> Seat? {
        guard case .track(let index) = position else { return nil }
        return layout.board.seats.first { layout.board.startIndex(for: $0) == index }
    }
}
