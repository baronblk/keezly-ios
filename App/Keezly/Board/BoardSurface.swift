import KeezlyCore
import SwiftUI

/// The board as a physical object: a wooden panel with holes milled into it.
///
/// Everything static is drawn once into a single `Canvas`. A turn-based board
/// game has no business running a render loop (§62), and the board does not
/// change during a match — only the pieces on it do.
///
/// The material is built rather than photographed: a warm base, a soft vertical
/// sheen, and a handful of very low-contrast grain strokes. A photographic wood
/// texture at this size reads as a cheap tiling artefact; grain that is felt
/// rather than read is what makes it look like a good board (§43).
struct BoardSurface: View {
    let layout: BoardLayout
    let transform: BoardTransform
    let theme: BoardTheme
    let legalTargets: Set<BoardPosition>

    var body: some View {
        Canvas { context, size in
            let hole = transform.scaled(layout.squareSize)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(theme.table))

            let panel = panelPath()
            drawPanel(panel, in: &context, hole: hole)
            drawGrain(clippedTo: panel, in: &context, size: size, hole: hole)
            drawPlayerAreas(in: &context, hole: hole)
            drawHoles(in: &context, hole: hole)
            drawMonogram(in: &context, hole: hole)
        }
        .drawingGroup()
    }

    // MARK: - The panel

    private func panelPath() -> Path {
        var path = Path()
        let points = layout.outline(inflatedBy: layout.surfaceMargin).map(transform.point)
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }

    private func drawPanel(_ panel: Path, in context: inout GraphicsContext, hole: CGFloat) {
        var shadowed = context
        shadowed.addFilter(.shadow(color: .black.opacity(0.4), radius: hole * 0.9, y: hole * 0.35))
        shadowed.fill(panel, with: .color(theme.surfaceMid))

        // A gentle top-to-bottom sheen, as a flat panel catches light.
        let bounds = panel.boundingRect
        context.fill(
            panel,
            with: .linearGradient(
                Gradient(colors: [theme.surfaceLight, theme.surfaceMid, theme.surfaceDeep]),
                startPoint: CGPoint(x: bounds.midX, y: bounds.minY),
                endPoint: CGPoint(x: bounds.midX, y: bounds.maxY)
            )
        )
        // The milled edge.
        context.stroke(panel, with: .color(theme.edge.opacity(0.85)), lineWidth: max(1, hole * 0.09))
        context.stroke(
            panel.strokedPath(StrokeStyle(lineWidth: hole * 0.06)),
            with: .color(.white.opacity(0.1))
        )
    }

    /// Grain: sparse, wandering, barely-there streaks. Deterministic, so the
    /// board looks the same every launch.
    ///
    /// The first attempt drew a line every half-hole at even spacing, which did
    /// not read as wood at all — it read as ruled notepaper. Wood grain is
    /// irregular, widely spaced and almost invisible; what sells it is that the
    /// eye cannot quite resolve it.
    private func drawGrain(clippedTo panel: Path, in context: inout GraphicsContext, size: CGSize, hole: CGFloat) {
        var clipped = context
        clipped.clip(to: panel)

        var generator = SeededGenerator(seed: 0x6_4A17)
        func unit() -> Double { Double(generator.next() % 1_000) / 1_000 }

        var y = -hole
        while y < size.height + hole {
            // Each streak gets its own weight and wander, and they are spaced
            // one to three holes apart rather than evenly.
            let amplitude = hole * (0.3 + unit() * 1.1)
            let drift = hole * (unit() - 0.5) * 1.6
            var streak = Path()
            streak.move(to: CGPoint(x: -hole, y: y))
            streak.addCurve(
                to: CGPoint(x: size.width + hole, y: y + drift),
                control1: CGPoint(x: size.width * (0.2 + unit() * 0.2), y: y + amplitude),
                control2: CGPoint(x: size.width * (0.6 + unit() * 0.2), y: y - amplitude * 0.7)
            )
            clipped.stroke(
                streak,
                with: .color(theme.grain.opacity(0.5 + unit() * 0.9)),
                lineWidth: max(0.4, hole * (0.02 + unit() * 0.06))
            )
            y += hole * (1.0 + unit() * 2.0)
        }
    }

    // MARK: - Player areas

    /// Each seat's home lane and waiting area, as inlaid colour rather than a
    /// painted rectangle (§42).
    private func drawPlayerAreas(in context: inout GraphicsContext, hole: CGFloat) {
        for seat in layout.board.seats {
            let colour = PlayerIdentity.identity(for: seat).color

            // The home lane: a rounded inlay under the four home holes.
            let first = transform.point(layout.homePoints[seat.index][0])
            let deepest = transform.point(layout.homePoints[seat.index][pawnsPerSeat - 1])
            var lane = Path()
            lane.move(to: first)
            lane.addLine(to: deepest)
            let laneShape = lane.strokedPath(StrokeStyle(lineWidth: hole * 1.6, lineCap: .round))
            context.fill(laneShape, with: .color(colour.opacity(0.24)))
            context.stroke(laneShape, with: .color(colour.opacity(0.5)), lineWidth: max(0.75, hole * 0.05))

            // The waiting area: a shallow tray.
            let unitRect = layout.waitingTray(for: seat)
            let origin = transform.point(CGPoint(x: unitRect.minX, y: unitRect.minY))
            let rect = CGRect(
                x: origin.x, y: origin.y,
                width: transform.scaled(unitRect.width),
                height: transform.scaled(unitRect.height)
            )
            let tray = Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) * 0.28)
            context.fill(tray, with: .color(colour.opacity(0.18)))
            context.stroke(tray, with: .color(colour.opacity(0.45)), lineWidth: max(0.75, hole * 0.05))
        }
    }

    // MARK: - Holes

    /// A milled hole: a dark floor, a shadow under the upper rim, and a lit
    /// lower lip. Those three together are what make it read as carved rather
    /// than as a dark dot painted on.
    private func drawHoles(in context: inout GraphicsContext, hole: CGFloat) {
        for position in layout.allPositions {
            let centre = transform.point(layout.point(for: position))
            let rect = CGRect(
                x: centre.x - hole / 2, y: centre.y - hole / 2,
                width: hole, height: hole
            )
            let circle = Path(ellipseIn: rect)

            context.fill(
                circle,
                with: .linearGradient(
                    Gradient(colors: [theme.holeShadow, theme.holeFill]),
                    startPoint: CGPoint(x: rect.midX, y: rect.minY),
                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                )
            )
            // The lit lower lip.
            var lip = Path()
            lip.addArc(
                center: CGPoint(x: rect.midX, y: rect.midY),
                radius: hole / 2, startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false
            )
            context.stroke(lip, with: .color(theme.holeLip), lineWidth: max(0.5, hole * 0.07))
            context.stroke(circle, with: .color(theme.edge.opacity(0.35)), lineWidth: max(0.5, hole * 0.04))

            if let seat = startSeat(of: position) {
                // A start square is special: a pawn on it is untouchable and
                // blocks the track (§15), so its hole carries a colour ring.
                context.stroke(
                    Path(ellipseIn: rect.insetBy(dx: -hole * 0.09, dy: -hole * 0.09)),
                    with: .color(PlayerIdentity.identity(for: seat).color.opacity(0.95)),
                    lineWidth: max(1, hole * 0.11)
                )
            }

            if legalTargets.contains(position) {
                context.stroke(
                    Path(ellipseIn: rect.insetBy(dx: -hole * 0.16, dy: -hole * 0.16)),
                    with: .color(Keezly.Palette.legalTarget),
                    lineWidth: max(1.5, hole * 0.14)
                )
            }
        }
    }

    /// A quiet mark at the centre. Not a logo — the board should look like a
    /// board, not a dashboard.
    private func drawMonogram(in context: inout GraphicsContext, hole: CGFloat) {
        let centre = transform.point(.zero)
        let radius = hole * 2.6
        let rect = CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
        context.stroke(Path(ellipseIn: rect), with: .color(theme.edge.opacity(0.14)), lineWidth: hole * 0.06)
        context.stroke(
            Path(ellipseIn: rect.insetBy(dx: radius * 0.14, dy: radius * 0.14)),
            with: .color(theme.edge.opacity(0.1)), lineWidth: hole * 0.04
        )
    }

    private func startSeat(of position: BoardPosition) -> Seat? {
        guard case .track(let index) = position else { return nil }
        return layout.board.seats.first { layout.board.startIndex(for: $0) == index }
    }
}
