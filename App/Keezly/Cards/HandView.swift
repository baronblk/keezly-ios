import KeezlyCore
import SwiftUI

/// The local player's hand, held as a hand of cards rather than laid out as a
/// row of buttons (§45).
///
/// Cards overlap and fan slightly, each tilted a little more than the last, so
/// the whole hand reads as one object. The chosen card straightens, lifts and
/// comes forward — the gesture a person makes with real cards. On a narrow
/// screen the fan tightens rather than the cards shrinking, because a card too
/// small to read is worse than a card partly covered (§45).
struct HandView: View {
    let cards: [Card]
    let playable: Set<Card>
    var selected: Card?
    var cardWidth: CGFloat = 76
    /// How much room the hand may take. The fan tightens to fit it.
    var availableWidth: CGFloat = .infinity
    var onSelect: (Card) -> Void

    /// Degrees of tilt between neighbouring cards.
    private var tilt: Double { cards.count > 1 ? min(4.5, 16 / Double(cards.count)) : 0 }

    /// Horizontal step between cards, tightened when space runs short.
    private var step: CGFloat {
        let comfortable = cardWidth * 0.66
        guard availableWidth.isFinite, cards.count > 1 else { return comfortable }
        let needed = (availableWidth - cardWidth) / CGFloat(cards.count - 1)
        return max(cardWidth * 0.3, min(comfortable, needed))
    }

    var body: some View {
        let count = cards.count
        let centre = Double(count - 1) / 2

        ZStack {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                let offsetFromCentre = Double(index) - centre
                let isChosen = selected == card

                CardView(
                    card: card,
                    width: cardWidth,
                    isPlayable: playable.contains(card),
                    isSelected: isChosen,
                    role: .hand
                )
                // A fanned card sits a little lower the further it is from the
                // middle, as it would in a hand.
                .rotationEffect(
                    .degrees(isChosen ? 0 : offsetFromCentre * tilt),
                    anchor: .bottom
                )
                .offset(
                    x: CGFloat(offsetFromCentre) * step,
                    y: isChosen ? 0 : abs(offsetFromCentre) * cardWidth * 0.035
                )
                .zIndex(isChosen ? 100 : Double(index))
                .onTapGesture {
                    guard playable.contains(card) else { return }
                    onSelect(card)
                }
            }
        }
        .frame(
            width: cardWidth + CGFloat(max(0, count - 1)) * step,
            height: cardWidth * 1.45 + cardWidth * 0.3
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: selected)
        .animation(.spring(response: 0.34, dampingFraction: 0.8), value: cards.count)
    }
}
