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
    /// Of those, the ones that commit a leg of a Seven rather than finishing
    /// the move. They look the same; only their identifier differs, so a test
    /// can choose one on purpose.
    var legTargets: Set<BoardPosition> = []
    /// Pawns the player may pick up right now.
    var selectablePawns: Set<PawnID> = []
    var selectedPawn: PawnID?
    /// A pawn to pick out for a beat — just taken, or just home.
    var emphasised: PawnID?
    var onSelectPawn: ((PawnID) -> Void)?
    var onSelectTarget: ((BoardPosition) -> Void)?
    /// Where the keyboard is, shared with the hand.
    var focus: FocusState<PlayFocus?>.Binding?
    /// What the player being spoken to can see, for VoiceOver.
    ///
    /// The true position, not the animated one: `pawns` may be part-way
    /// through a move, and a board read aloud mid-animation would describe a
    /// square nobody is on yet. Optional so a preview or a screenshot fixture
    /// can draw a board without one (§53).
    var narration: PlayerObservation?

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
                // tappable as a pawn — but only while the player is still
                // choosing which pawn to move. See `targetsTakePrecedence`.
                // Which layer takes a tap where the two overlap.
                //
                // Both a square and a piece are given at least
                // `Target.minimum` to be tapped, and on a phone the board's
                // squares are smaller than that — so the two inflated areas
                // genuinely overlap, and whichever is drawn last wins. Until
                // a pawn is chosen the piece should win, because the question
                // on screen is *which piece*. Once one is chosen the question
                // is *where to*, and the square must win, or a highlighted
                // destination next to a piece cannot be tapped at all.
                //
                // ISS-020: on iPhone this swallowed the tap that would have
                // ended the turn. On iPad the squares are larger than 44pt,
                // nothing is inflated, nothing overlaps, and the same test
                // passed — which is why it looked like a harness fault for so
                // long.
                if !targetsTakePrecedence {
                    ForEach(Array(legalTargets), id: \.self) { target in
                        Color.clear
                            .frame(
                                width: max(Keezly.Target.minimum, transform.scaled(layout.squareSize)),
                                height: max(Keezly.Target.minimum, transform.scaled(layout.squareSize))
                            )
                            .contentShape(Rectangle())
                            .position(transform.point(layout.point(for: target)))
                            .onTapGesture { onSelectTarget?(target) }
                            .keyboardFocusRing(
                                focus?.wrappedValue == .target(target),
                                cornerRadius: transform.scaled(layout.squareSize) / 2
                            )
                            .pointerEffect(.highlight)
                            .focusable()
                            .keyboardFocus(focus, equals: .target(target))
                            .accessibilityIdentifier(
                                "target.\(legTargets.contains(target) ? "leg." : "")\(Self.identifier(for: target))"
                            )
                            .accessibilityLabel(targetLabel(for: target))
                            .accessibilityValue(narration.flatMap {
                                MoveNarrator.occupant(of: target, in: $0)
                            } ?? "")
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
                        .keyboardFocusRing(
                            focus?.wrappedValue == .pawn(pawn.id),
                            cornerRadius: transform.scaled(layout.squareSize) / 2
                        )
                        .pointerEffect(.lift, enabled: selectablePawns.contains(pawn.id))
                        .focusable(selectablePawns.contains(pawn.id))
                        .keyboardFocus(focus, equals: .pawn(pawn.id))
                        .accessibilityIdentifier("pawn.\(pawn.id.seat.index).\(pawn.id.slot)")
                        .accessibilityLabel(pawnLabel(for: pawn.id))
                        .accessibilityValue(
                            MoveNarrator.pawnState(
                                selectable: selectablePawns.contains(pawn.id),
                                selected: selectedPawn == pawn.id
                            ) ?? ""
                        )
                        .accessibilityAddTraits(selectablePawns.contains(pawn.id) ? .isButton : [])
                    }
                } else {
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
                        .keyboardFocusRing(
                            focus?.wrappedValue == .pawn(pawn.id),
                            cornerRadius: transform.scaled(layout.squareSize) / 2
                        )
                        .pointerEffect(.lift, enabled: selectablePawns.contains(pawn.id))
                        .focusable(selectablePawns.contains(pawn.id))
                        .keyboardFocus(focus, equals: .pawn(pawn.id))
                        .accessibilityIdentifier("pawn.\(pawn.id.seat.index).\(pawn.id.slot)")
                        .accessibilityLabel(pawnLabel(for: pawn.id))
                        .accessibilityValue(
                            MoveNarrator.pawnState(
                                selectable: selectablePawns.contains(pawn.id),
                                selected: selectedPawn == pawn.id
                            ) ?? ""
                        )
                        .accessibilityAddTraits(selectablePawns.contains(pawn.id) ? .isButton : [])
                    }
                    ForEach(Array(legalTargets), id: \.self) { target in
                        Color.clear
                            .frame(
                                width: max(Keezly.Target.minimum, transform.scaled(layout.squareSize)),
                                height: max(Keezly.Target.minimum, transform.scaled(layout.squareSize))
                            )
                            .contentShape(Rectangle())
                            .position(transform.point(layout.point(for: target)))
                            .onTapGesture { onSelectTarget?(target) }
                            .keyboardFocusRing(
                                focus?.wrappedValue == .target(target),
                                cornerRadius: transform.scaled(layout.squareSize) / 2
                            )
                            .pointerEffect(.highlight)
                            .focusable()
                            .keyboardFocus(focus, equals: .target(target))
                            .accessibilityIdentifier(
                                "target.\(legTargets.contains(target) ? "leg." : "")\(Self.identifier(for: target))"
                            )
                            .accessibilityLabel(targetLabel(for: target))
                            .accessibilityValue(narration.flatMap {
                                MoveNarrator.occupant(of: target, in: $0)
                            } ?? "")
                            .accessibilityAddTraits(.isButton)
                    }
                }
            }
        }
        .aspectRatio(layout.contentBounds.width / layout.contentBounds.height, contentMode: .fit)
    }

    /// Whether a tap where a square and a piece overlap belongs to the square.
    ///
    /// Both are given at least `Keezly.Target.minimum` to be tapped, and on a
    /// phone the board's squares are smaller than that — so the two inflated
    /// areas genuinely overlap and whichever is drawn last wins the tap.
    ///
    /// Until a pawn is chosen the piece should win: the question on screen is
    /// *which piece*. Once one is chosen the question is *where to*, and the
    /// square must win, or a highlighted destination beside a piece cannot be
    /// tapped at all (ISS-020).
    ///
    /// A property rather than an inline condition so the rule can be tested
    /// without a rendered board.
    var targetsTakePrecedence: Bool { selectedPawn != nil }

    /// A square offered as a destination.
    ///
    /// Falls back to a bare "move here" without an observation, which is what
    /// a preview gets — never nothing, because an unlabelled button is the one
    /// outcome VoiceOver cannot work around.
    private func targetLabel(for target: BoardPosition) -> String {
        guard let narration else { return String(localized: "board.target") }
        return String(localized: "a11y.target \(MoveNarrator.square(target, in: narration))")
    }

    private func pawnLabel(for id: PawnID) -> String {
        guard let narration else {
            return MoveNarrator.seatName(id.seat)
        }
        return MoveNarrator.pawn(id, in: narration)
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
