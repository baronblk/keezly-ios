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
            drawBorderOrnament(in: &context, hole: hole)
            drawPlayerAreas(in: &context, hole: hole)
            drawHoles(in: &context, hole: hole)
            drawMedallion(in: &context, hole: hole)
        }
        .drawingGroup()
    }

    // MARK: - The panel

    private func panelPath() -> Path {
        closedPath(layout.outline(inflatedBy: layout.surfaceMargin))
    }

    private func drawPanel(_ panel: Path, in context: inout GraphicsContext, hole: CGFloat) {
        // Two shadows rather than one: a tight contact shadow that sits the
        // board on the table, and a wide soft one that gives it weight. A
        // single shadow reads either as a sticker or as a smudge.
        var contact = context
        contact.addFilter(.shadow(color: .black.opacity(0.55), radius: hole * 0.35, y: hole * 0.14))
        contact.fill(panel, with: .color(theme.surfaceMid))

        var shadowed = context
        shadowed.addFilter(.shadow(color: .black.opacity(0.38), radius: hole * 1.6, y: hole * 0.7))
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
        // The milled edge, then a bevel just inside it: lit along the top,
        // shaded along the bottom, which is what tells the eye the board has
        // thickness rather than being a printed shape.
        context.stroke(panel, with: .color(theme.edge.opacity(0.92)), lineWidth: max(1, hole * 0.11))

        let bevel = closedPath(BoardOrnament.offset(
            layout.outline(inflatedBy: layout.surfaceMargin),
            by: -layout.pitch * 0.10
        ))
        context.stroke(
            bevel,
            with: .linearGradient(
                Gradient(colors: [
                    .white.opacity(0.30),
                    .white.opacity(0.06),
                    .black.opacity(0.16),
                ]),
                startPoint: CGPoint(x: bounds.midX, y: bounds.minY),
                endPoint: CGPoint(x: bounds.midX, y: bounds.maxY)
            ),
            lineWidth: max(1, hole * 0.14)
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
            context.fill(laneShape, with: .color(colour.opacity(0.34)))
            context.stroke(laneShape, with: .color(colour.opacity(0.68)), lineWidth: max(0.9, hole * 0.06))

            // The waiting area: a shallow tray.
            let unitRect = layout.waitingTray(for: seat)
            let origin = transform.point(CGPoint(x: unitRect.minX, y: unitRect.minY))
            let rect = CGRect(
                x: origin.x, y: origin.y,
                width: transform.scaled(unitRect.width),
                height: transform.scaled(unitRect.height)
            )
            let tray = Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) * 0.28)
            context.fill(tray, with: .color(colour.opacity(0.26)))
            context.stroke(tray, with: .color(colour.opacity(0.62)), lineWidth: max(0.9, hole * 0.06))

            // The seat's own mark, engraved into its two areas.
            //
            // Colour alone told you whose corner and whose lane these were,
            // and amber measures 1.23:1 against this wood (ISS-016): in
            // greyscale, or to somebody who cannot separate the two, the
            // areas simply vanished. The mark is the same one the seat's
            // pieces carry, so identity is shape as well as hue everywhere it
            // matters (§42, §53).
            drawSeatMark(
                for: seat,
                centredOn: CGPoint(x: rect.midX, y: rect.midY),
                size: hole * 0.66,
                in: &context,
                hole: hole
            )
            drawSeatMark(
                for: seat,
                centredOn: homeMarkAnchor(for: seat),
                size: hole * 0.62,
                in: &context,
                hole: hole
            )
        }
    }

    /// Where a home lane's mark sits: just beyond its deepest square, on the
    /// lane's own line, where the ornament's chevron already points.
    private func homeMarkAnchor(for seat: Seat) -> CGPoint {
        let lane = layout.homePoints[seat.index]
        guard let deepest = lane.last, let entry = lane.first else { return .zero }
        let direction = CGPoint(x: deepest.x - entry.x, y: deepest.y - entry.y)
        let length = hypot(direction.x, direction.y)
        guard length > 0 else { return transform.point(deepest) }
        return transform.point(CGPoint(
            x: deepest.x + direction.x / length * layout.pitch * 0.85,
            y: deepest.y + direction.y / length * layout.pitch * 0.85
        ))
    }

    /// One seat's mark, engraved rather than printed, so it belongs to the
    /// board the way the ornament does.
    private func drawSeatMark(
        for seat: Seat,
        centredOn centre: CGPoint,
        size: CGFloat,
        in context: inout GraphicsContext,
        hole: CGFloat
    ) {
        // Below this a mark is a smudge, and a smudge helps nobody.
        guard hole >= 9 else { return }
        let shape = PlayerIdentity.identity(for: seat).mark.path(in: CGRect(
            x: centre.x - size / 2, y: centre.y - size / 2, width: size, height: size
        ))
        // Deeper than the border ornament. This one is not decoration: it is
        // how an *empty* tray or lane says whose it is, and a mark nobody can
        // see is the same as no mark at all.
        engrave(shape, in: &context, width: max(0.6, hole * 0.07), tint: theme.edge, strength: 0.62)
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

            // A hole is read from three things: a floor that darkens towards
            // the near rim, a shadow cast inside it by the far rim, and a lit
            // lower lip. Strengthened here, but still built from shading —
            // anything more would read as moulded plastic rather than as wood
            // that has been drilled.
            if let seat = homeSeat(of: position) {
                // A home square is tinted by its seat, so the four squares
                // that end a journey are never mistaken for track.
                context.fill(circle, with: .color(PlayerIdentity.identity(for: seat).color.opacity(0.30)))
            }
            context.fill(
                circle,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: theme.holeShadow, location: 0),
                        .init(color: theme.holeShadow.opacity(0.75), location: 0.42),
                        .init(color: theme.holeFill, location: 1),
                    ]),
                    startPoint: CGPoint(x: rect.midX, y: rect.minY),
                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                )
            )

            // The shadow the upper rim casts down into the hole.
            var upperShadow = Path()
            upperShadow.addArc(
                center: CGPoint(x: rect.midX, y: rect.midY),
                radius: hole / 2 - max(0.4, hole * 0.05),
                startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false
            )
            context.stroke(
                upperShadow,
                with: .color(.black.opacity(0.28)),
                lineWidth: max(0.6, hole * 0.11)
            )

            // The lit lower lip, which is what makes it read as carved.
            var lip = Path()
            lip.addArc(
                center: CGPoint(x: rect.midX, y: rect.midY),
                radius: hole / 2 - max(0.3, hole * 0.03),
                startAngle: .degrees(24), endAngle: .degrees(156), clockwise: false
            )
            context.stroke(lip, with: .color(theme.holeLip), lineWidth: max(0.7, hole * 0.095))
            context.stroke(circle, with: .color(theme.edge.opacity(0.46)), lineWidth: max(0.5, hole * 0.045))

            if let seat = startSeat(of: position) {
                // A start square is special: a pawn on it is untouchable and
                // blocks the track (§15), so its hole carries a colour ring.
                let colour = PlayerIdentity.identity(for: seat).color
                // A halo under the ring lifts the start square off the wood
                // without a flat block of colour.
                context.stroke(
                    Path(ellipseIn: rect.insetBy(dx: -hole * 0.20, dy: -hole * 0.20)),
                    with: .color(colour.opacity(0.28)),
                    lineWidth: max(1, hole * 0.16)
                )
                context.stroke(
                    Path(ellipseIn: rect.insetBy(dx: -hole * 0.09, dy: -hole * 0.09)),
                    with: .color(colour),
                    lineWidth: max(1.2, hole * 0.14)
                )
            }

            if legalTargets.contains(position) {
                // Dashed, not solid. A protected start square is already a
                // solid ring, and two rings in two colours are the same ring
                // to anybody reading the board in greyscale — which is the
                // one distinction a player cannot afford to lose, because it
                // separates "you may move here" from "nobody may pass" (§53).
                // Outside the start square's own rings, not between them. A
                // start square already carries a halo at 0.20 and a ring at
                // 0.09; a target drawn at 0.16 landed in the gap and, with the
                // colour taken away, disappeared into them — measured at
                // 3/255 by `GrayscaleTests` before this moved.
                context.stroke(
                    Path(ellipseIn: rect.insetBy(dx: -hole * 0.34, dy: -hole * 0.34)),
                    with: .color(Keezly.Palette.legalTarget),
                    style: StrokeStyle(
                        lineWidth: max(1.6, hole * 0.16),
                        lineCap: .round,
                        dash: [hole * 0.40, hole * 0.30]
                    )
                )
            }
        }
    }

    // MARK: - Ornament

    /// Draws a path as though it were cut into the wood rather than printed on
    /// it: a lit lower lip first, the incision over it.
    ///
    /// Exactly the trick that makes the milled holes read as holes. Using it
    /// again is what keeps the ornament part of the same board instead of a
    /// decal laid on top (§76).
    private func engrave(
        _ path: Path,
        in context: inout GraphicsContext,
        width: CGFloat,
        tint: Color,
        strength: Double
    ) {
        let lip = path.offsetBy(dx: 0, dy: max(0.4, width * 0.8))
        context.stroke(lip, with: .color(theme.holeLip.opacity(strength * 0.75)), lineWidth: width)
        context.stroke(path, with: .color(tint.opacity(strength)), lineWidth: width)
    }

    /// The running border: two fine incised lines with an alternating band of
    /// tulips and lozenges between them.
    ///
    /// Sized so that from playing distance it reads as a quiet edge and
    /// nothing more. The motifs only resolve when someone leans in, which is
    /// the whole intent (§76).
    private func drawBorderOrnament(in context: inout GraphicsContext, hole: CGFloat) {
        let pitch = layout.pitch
        let edge = layout.outline(inflatedBy: layout.surfaceMargin)
        let lineWidth = max(0.5, hole * 0.045)

        for inset in [CGFloat(0.35), 1.00] {
            engrave(
                closedPath(BoardOrnament.offset(edge, by: -pitch * inset)),
                in: &context,
                width: lineWidth,
                tint: theme.inlay,
                strength: 0.38
            )
        }

        // Below roughly nine points a hole the motifs stop being ornament and
        // start being noise, so the border keeps its lines and drops them.
        guard hole >= 9 else { return }

        let band = BoardOrnament.offset(edge, by: -pitch * 0.675)
        let perimeter = zip(band, band.dropFirst() + band.prefix(1))
            .reduce(CGFloat.zero) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        let count = BoardOrnament.motifCount(
            perimeter: perimeter,
            spacing: pitch * 1.15,
            seats: layout.board.seatCount
        )
        let size = transform.scaled(pitch * 0.46)

        for (index, placement) in BoardOrnament.placements(along: band, count: count).enumerated() {
            let motif = BoardOrnament.Motif.at(index)
            let shape = motif == .tulip
                ? BoardOrnament.tulip(size: size)
                : BoardOrnament.lozenge(size: size * 0.5)

            var placed = Path(shape)
            placed = placed.applying(
                CGAffineTransform(rotationAngle: placement.rotation)
                    .concatenating(CGAffineTransform(
                        translationX: transform.point(placement.point).x,
                        y: transform.point(placement.point).y
                    ))
            )
            engrave(
                placed,
                in: &context,
                width: max(0.5, hole * 0.05),
                tint: theme.inlay,
                strength: motif == .tulip ? 0.42 : 0.32
            )
        }
    }

    /// A small engraved chevron where each home lane ends, aimed the way the
    /// pawns travel.
    ///
    /// Linear on purpose: anything round this close to the holes would be read
    /// as another square. It carries no player colour either — the lane inlay
    /// already does that, and the colour must stay the loudest thing here.
    /// The medallion at the centre: two fine rings, a petal in each gap
    /// between the home lanes, and one small orange keystone.
    ///
    /// It frames the cards rather than sitting under them — an ornament hidden
    /// behind the draw pile would be ornament nobody ever sees. Contrast is
    /// deliberately at the edge of noticeable: the middle of the board must
    /// never compete with the game (§76).
    private func drawMedallion(in context: inout GraphicsContext, hole: CGFloat) {
        let centre = transform.point(.zero)
        // Measured against the board rather than in holes. A fixed number of
        // holes is right for four seats and wrong for two, where the inner
        // field is much smaller — at two seats a fixed medallion would have
        // been drawn straight across the deepest home square.
        let innerField = layout.homePoints
            .compactMap { $0.last.map { hypot($0.x, $0.y) } }
            .min() ?? 0
        guard let unitRadius = BoardOrnament.medallionRadius(
            innerField: innerField,
            square: layout.squareSize
        ) else { return }
        let radius = transform.scaled(unitRadius)

        for inset in [CGFloat(0), radius * 0.1] {
            let rect = CGRect(
                x: centre.x - radius + inset, y: centre.y - radius + inset,
                width: (radius - inset) * 2, height: (radius - inset) * 2
            )
            engrave(
                Path(ellipseIn: rect),
                in: &context,
                width: max(0.5, hole * (inset == 0 ? 0.045 : 0.03)),
                tint: theme.inlay,
                // Quieter than the border on purpose. The middle of the board
                // is where the cards are read, so the ornament there has to
                // sit behind them rather than beside them.
                strength: 0.14
            )
        }

        guard hole >= 9 else { return }

        let laneAngles = layout.homePoints.compactMap { lane -> CGFloat? in
            guard let inner = lane.last else { return nil }
            return atan2(inner.y, inner.x)
        }
        let angles = BoardOrnament.medallionAngles(
            seats: layout.board.seatCount,
            laneAngles: laneAngles
        )
        let size = hole * 1.15

        for angle in angles {
            let anchor = CGPoint(
                x: centre.x + cos(angle) * radius * BoardOrnament.petalAnchor,
                y: centre.y + sin(angle) * radius * BoardOrnament.petalAnchor
            )
            var petal = Path(BoardOrnament.petal(size: size))
            petal = petal.applying(
                CGAffineTransform(rotationAngle: angle - .pi / 2)
                    .concatenating(CGAffineTransform(translationX: anchor.x, y: anchor.y))
            )
            engrave(petal, in: &context, width: max(0.5, hole * 0.04), tint: theme.inlay, strength: 0.16)
        }

        // The one orange detail on the whole board, at the top of the ring:
        // a keystone, the way a cabinetmaker signs a piece.
        let keystone = CGPoint(x: centre.x, y: centre.y - radius)
        var mark = Path(BoardOrnament.lozenge(size: hole * 0.34))
        mark = mark.applying(CGAffineTransform(translationX: keystone.x, y: keystone.y))
        context.fill(mark, with: .color(theme.accent.opacity(0.42)))
    }

    /// A closed polyline in unit space, as a path in view space.
    private func closedPath(_ unitPoints: [CGPoint]) -> Path {
        var path = Path()
        let points = unitPoints.map(transform.point)
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }

    private func homeSeat(of position: BoardPosition) -> Seat? {
        guard case .home(let seat, _) = position else { return nil }
        return seat
    }

    private func startSeat(of position: BoardPosition) -> Seat? {
        guard case .track(let index) = position else { return nil }
        return layout.board.seats.first { layout.board.startIndex(for: $0) == index }
    }
}
