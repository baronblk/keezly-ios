import KeezlyCore
import SwiftUI

/// The middle of the board.
///
/// On a physical Keezen board this is where the cards sit, so it is where the
/// eye already looks for them. It holds the draw pile, the last card played,
/// and who is on turn — the status a player checks without wanting to read
/// anything (§35).
struct BoardCentreView: View {
    @ScaledMetric(relativeTo: .caption2) private var captionScale: CGFloat = 1

    let state: GameState
    let roles: [SeatRole]
    /// Whether this board is being watched rather than played.
    ///
    /// A replay has nobody waiting on it: "thinking…" would be describing a
    /// decision that was made and recorded some time ago.
    var isReplay = false
    var width: CGFloat
    /// Laid out down the middle of the board, or across a tray beside it.
    ///
    /// A two-seat board has no middle to sit in (ISS-013), so the same
    /// information is shown as a tray next to the board — the way a deck sits
    /// on the table beside a small board rather than on it.
    var axis: Axis = .vertical
    /// Which of the three things this instance is drawing.
    var content: Content = .full

    /// What the middle is carrying.
    ///
    /// Two of the three things here are text, and text has a floor: below
    /// about eleven points nobody can read it, so it stops shrinking with the
    /// board. On a phone the board's middle is around a hundred points across
    /// and the designed sizes — seven hundredths and five hundredths of that —
    /// come out at seven and five. Both hit the floor, and the turn pill ends
    /// up half again as large as it was drawn to be, sitting across a board
    /// that has no room for it (ISS-013).
    ///
    /// The cards have no such floor: they are shapes, and a thirty-point card
    /// back still reads as a stack of cards. So on a small board the middle
    /// keeps the piles and the two labels move out to a line beneath it, where
    /// they can be legible without being on top of anything.
    enum Content {
        /// The piles, the turn and the round: a board with room for all three.
        case full
        /// The piles alone, for a board whose middle cannot carry text.
        case piles
        /// The turn and the round, for the line beneath such a board.
        case labels

        /// How tall this block is against its own width, near enough to size
        /// it against the board's quiet middle.
        ///
        /// Measured off the layout rather than guessed: the piles are `0.3`
        /// wide and `1.45` tall each, the spacings are `0.11`, and the two
        /// text lines come to about `0.22` between them.
        var aspect: CGFloat {
            switch self {
            case .full: 0.88
            case .piles: 0.60
            case .labels: 0.16
            }
        }
    }

    // MARK: - Fitting

    /// The share of the board a four-player middle takes. The reference the
    /// rest is measured against, and never exceeded.
    static let classicScale: CGFloat = 0.26
    /// Below this the draw pile's count stops being readable, and an illegible
    /// count is worse than a crowded middle (ISS-013).
    static let minimumScale: CGFloat = 0.19
    /// `TurnIndicator`'s designed size, as a fraction of the middle's width.
    static let turnTextFraction: CGFloat = 0.07
    /// The size below which it stops shrinking, because nobody could read it.
    static let legibleText: CGFloat = 11
    /// The width the labels are drawn at once they have left the board.
    ///
    /// Chosen so the turn label lands exactly on its floor: off the board
    /// there is no reason to make it smaller, and none to make it larger than
    /// the middle would have.
    static let detachedWidth: CGFloat = legibleText / turnTextFraction

    /// What a board of this size can carry in its middle, and how wide.
    ///
    /// One answer, given in one place, because the playing screen and the
    /// replay screen both draw this and a hard-coded fraction in the second of
    /// them is how the two drift apart.
    static func fitted(in layout: BoardLayout, boardSide: CGFloat) -> (content: Content, width: CGFloat) {
        func width(_ content: Content) -> CGFloat {
            let byField = layout.centreWidthFraction(aspect: content.aspect)
            return boardSide * min(classicScale, max(minimumScale, byField))
        }
        // Decided on what the full block would be given, so the answer does
        // not depend on itself.
        let content: Content = width(.full) * turnTextFraction >= legibleText ? .full : .piles
        return (content, width(content))
    }

    private var identity: PlayerIdentity { PlayerIdentity.identity(for: state.currentSeat) }

    var body: some View {
        Group {
            if content == .piles {
                piles
            } else if content == .labels {
                // Beneath the board rather than on it, so the two can be read
                // at a readable size without covering the playing surface —
                // and side by side rather than stacked, because height is
                // exactly what is short on the boards that need this.
                HStack(spacing: width * 0.12) {
                    turn
                    round
                }
            } else if axis == .vertical {
                // Enough air that the cards, the turn and the round read as
                // three things rather than one block — but not so much that
                // they stop reading as one *group*. The first attempt at this
                // used twice the spacing and the labels floated away from the
                // cards they belong to.
                VStack(spacing: width * 0.11) {
                    piles
                    turn
                    round
                }
                // Width comes from the piles; the labels are free to be wider
                // when the reader's text size asks for it. Pinning this to
                // `width` is what truncated them.
                .frame(maxWidth: width * 3, alignment: .center)
            } else {
                // Beside the board the tray runs across, so a wide screen is
                // not asked to carry a tall column of nothing.
                HStack(spacing: width * 0.22) {
                    piles
                    VStack(alignment: .leading, spacing: width * 0.08) {
                        turn
                        round
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var piles: some View {
        HStack(spacing: width * 0.13) {
            DrawPile(remaining: state.deck.count, width: width * 0.3)
            DiscardPile(top: state.discardPile.last, width: width * 0.3)
        }
    }

    private var turn: some View {
        TurnIndicator(
            identity: identity,
            isComputer: {
                if case .computer = roles[state.currentSeat.index] { return true }
                return false
            }(),
            finished: state.result != nil,
            isReplay: isReplay,
            width: width,
            onBoard: content != .labels
        )
    }

    private var round: some View {
        Text("deal.round \(state.deal.roundIndex + 1) \(DealState.cardsPerRound.count)")
            // The quietest thing in the middle. It answers a question nobody
            // asks mid-turn, so it recedes until looked for.
            .font(.system(size: max(9, width * 0.05) * captionScale, weight: .medium, design: .rounded))
            .opacity(content == .labels ? 1 : 0.72)
            // Wraps rather than truncates at large text sizes. Half a sentence
            // tells the reader nothing (§53).
            .multilineTextAlignment(axis == .vertical && content != .labels ? .center : .leading)
            .fixedSize(horizontal: false, vertical: true)
            // Off the board the wood is not behind it. The ink chosen to be
            // quiet on a light surface is all but invisible on the dark table,
            // which is how the round label came to be shipped unreadable for
            // exactly as long as nobody zoomed in on a capture.
            .foregroundStyle(content == .labels
                ? AnyShapeStyle(Color.white.opacity(0.7))
                : AnyShapeStyle(Keezly.Palette.secondaryText))
    }
}

private struct DrawPile: View {
    let remaining: Int
    let width: CGFloat

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: width * 0.085, style: .continuous) }

    var body: some View {
        ZStack {
            // A few offset backs read as a stack without drawing one card per
            // remaining card. The count rides on top as a small token rather
            // than as a number printed across the cards.
            ForEach(0..<min(3, max(1, remaining)), id: \.self) { layer in
                CardBackPattern()
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(.white.opacity(0.22), lineWidth: max(0.5, width * 0.012)))
                    .frame(width: width, height: width * 1.45)
                    .shadow(color: .black.opacity(0.22), radius: width * 0.05, y: width * 0.02)
                    .offset(x: CGFloat(layer) * width * 0.022, y: CGFloat(layer) * -width * 0.022)
            }

            Text(remaining, format: .number)
                .font(.system(size: width * 0.2, weight: .bold, design: .rounded))
                .foregroundStyle(Keezly.Palette.cardInk)
                .padding(.horizontal, width * 0.11)
                .padding(.vertical, width * 0.05)
                .background(Capsule().fill(Keezly.Palette.cardFace))
                .offset(y: width * 0.58)
        }
        .frame(width: width, height: width * 1.45)
        .accessibilityElement()
        .accessibilityLabel("pile.draw \(remaining)")
    }
}

private struct DiscardPile: View {
    let top: Card?
    let width: CGFloat

    var body: some View {
        Group {
            if let top {
                CardView(card: top, width: width, isPlayable: true, role: .discard)
            } else {
                RoundedRectangle(cornerRadius: width * 0.14, style: .continuous)
                    .strokeBorder(Keezly.Palette.rim, style: StrokeStyle(lineWidth: 1, dash: [width * 0.1]))
                    .frame(width: width, height: width * 1.4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(top.map { "pile.discard \($0.rank.shorthand)" } ?? "pile.discard.empty")
    }
}

private struct TurnIndicator: View {
    /// The one piece of board chrome that is genuinely text, so it follows the
    /// reader's setting (§53).
    @ScaledMetric(relativeTo: .subheadline) private var textScale: CGFloat = 1

    let identity: PlayerIdentity
    let isComputer: Bool
    let finished: Bool
    var isReplay = false
    let width: CGFloat
    /// Whether the board's own wood is behind this, or the dark table is.
    var onBoard = true

    /// Whose turn it is, in the tense that applies.
    private var label: LocalizedStringKey {
        if finished { return "turn.finished" }
        if isReplay { return "turn.watching" }
        return isComputer ? "turn.thinking" : "turn.yours"
    }

    var body: some View {
        HStack(spacing: width * 0.04) {
            MarkShape(mark: identity.mark)
                .fill(identity.color)
                .frame(width: width * 0.12, height: width * 0.12)

            Text(label)
                .font(.system(size: max(11, width * 0.07) * textScale, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(onBoard
                    ? AnyShapeStyle(Keezly.Palette.primaryText)
                    : AnyShapeStyle(Color.white))
        }
        .padding(.horizontal, width * 0.08)
        .padding(.vertical, width * 0.04)
        // A sixth of the seat's colour is enough to read as that player on the
        // board's light wood, and nowhere near enough on the dark table.
        .background(
            Capsule().fill(identity.color.opacity(onBoard ? 0.16 : 0.34))
        )
        .accessibilityElement(children: .combine)
    }
}
