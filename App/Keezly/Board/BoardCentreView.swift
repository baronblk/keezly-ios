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

    var body: some View {
        ZStack {
            // A couple of offset backs read as a pile without drawing one card
            // per remaining card.
            ForEach(0..<min(3, max(1, remaining)), id: \.self) { layer in
                RoundedRectangle(cornerRadius: width * 0.14, style: .continuous)
                    .fill(Keezly.Palette.board)
                    .overlay(
                        RoundedRectangle(cornerRadius: width * 0.14, style: .continuous)
                            .strokeBorder(Keezly.Palette.rim, lineWidth: 1)
                    )
                    .offset(x: CGFloat(layer) * width * 0.03, y: CGFloat(layer) * -width * 0.03)
            }
            Text("\(remaining)")
                .font(.system(size: width * 0.34, weight: .semibold, design: .rounded))
                .foregroundStyle(Keezly.Palette.secondaryText)
                .offset(x: width * 0.06, y: -width * 0.06)
        }
        .frame(width: width, height: width * 1.4)
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
