import KeezlyCore
import SwiftUI

/// The middle of the board.
///
/// On a physical Keezen board this is where the cards sit, so it is where the
/// eye already looks for them. It holds the draw pile, the last card played,
/// and who is on turn — the status a player checks without wanting to read
/// anything (§35).
struct BoardCentreView: View {
    let state: GameState
    let roles: [SeatRole]
    var width: CGFloat

    private var identity: PlayerIdentity { PlayerIdentity.identity(for: state.currentSeat) }

    var body: some View {
        VStack(spacing: width * 0.06) {
            HStack(spacing: width * 0.08) {
                DrawPile(remaining: state.deck.count, width: width * 0.3)
                DiscardPile(top: state.discardPile.last, width: width * 0.3)
            }

            TurnIndicator(
                identity: identity,
                isComputer: {
                    if case .computer = roles[state.currentSeat.index] { return true }
                    return false
                }(),
                finished: state.result != nil,
                width: width
            )

            Text("deal.round \(state.deal.roundIndex + 1) \(DealState.cardsPerRound.count)")
                .font(.system(size: max(9, width * 0.055), weight: .medium, design: .rounded))
                .foregroundStyle(Keezly.Palette.secondaryText)
        }
        .frame(width: width)
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

            Text("\(remaining)")
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
    let identity: PlayerIdentity
    let isComputer: Bool
    let finished: Bool
    let width: CGFloat

    var body: some View {
        HStack(spacing: width * 0.04) {
            MarkShape(mark: identity.mark)
                .fill(identity.color)
                .frame(width: width * 0.12, height: width * 0.12)

            Text(finished ? "turn.finished" : (isComputer ? "turn.thinking" : "turn.yours"))
                .font(.system(size: max(10, width * 0.07), weight: .semibold, design: .rounded))
                .foregroundStyle(Keezly.Palette.primaryText)
        }
        .padding(.horizontal, width * 0.08)
        .padding(.vertical, width * 0.04)
        .background(
            Capsule().fill(identity.color.opacity(0.16))
        )
        .accessibilityElement(children: .combine)
    }
}
