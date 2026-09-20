import KeezlyCore
import SwiftUI

/// A playing card.
///
/// The rank carries the card, large and rounded, legible across a table (§45).
/// Cards whose effect is not their face value carry a small hint — a Four moves
/// backward, a Seven splits — worded as a symbol rather than a sentence, so it
/// reads as part of the card rather than as a tutorial overlay.
struct CardView: View {
    let card: Card
    var width: CGFloat = 76
    var isPlayable = true
    var isSelected = false
    /// What this card *is* on screen. A card in the hand and the card on top of
    /// the discard pile look alike but are not interchangeable — a UI test that
    /// cannot tell them apart will happily count the discard as part of the
    /// hand, which is exactly what happened.
    var role: CardRole = .hand

    private var height: CGFloat { width * 1.4 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.13, style: .continuous)
                .fill(Keezly.Palette.cardFace)
                .overlay(
                    RoundedRectangle(cornerRadius: width * 0.13, style: .continuous)
                        .strokeBorder(
                            isSelected ? Keezly.Palette.legalTarget : Keezly.Palette.rim,
                            lineWidth: isSelected ? max(2, width * 0.05) : 1
                        )
                )
                .shadow(color: .black.opacity(isSelected ? 0.3 : 0.18),
                        radius: width * (isSelected ? 0.14 : 0.07),
                        y: width * 0.04)

            VStack(spacing: width * 0.04) {
                Text(card.rank.shorthand)
                    .font(Keezly.Typography.cardRank(size: width * 0.46))
                    .foregroundStyle(Keezly.Palette.cardInk)

                if let hint = Self.hint(for: card.rank) {
                    Text(hint)
                        .font(.system(size: width * 0.17, weight: .medium, design: .rounded))
                        .foregroundStyle(Keezly.Palette.cardInk.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(.horizontal, width * 0.08)
        }
        .frame(width: width, height: height)
        // An unplayable card stays a visible card, dimmed rather than erased:
        // a player who cannot move needs to see *which* cards are stuck, not
        // an empty space where their hand was (§36).
        .overlay {
            if !isPlayable {
                RoundedRectangle(cornerRadius: width * 0.13, style: .continuous)
                    .fill(Keezly.Palette.table.opacity(0.45))
            }
        }
        .offset(y: isSelected ? -width * 0.16 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("\(role.rawValue).card.\(card.id)")
        .accessibilityLabel(Self.accessibilityLabel(for: card.rank))
        .accessibilityAddTraits(isPlayable ? .isButton : [])
        .accessibilityValue(isPlayable ? "" : String(localized: "card.unplayable"))
    }

    /// The short functional hint, for cards that do not simply move their face
    /// value forward.
    static func hint(for rank: CardRank) -> String? {
        switch rank {
        case .ace: "⌂ / 1"
        case .king: "⌂"
        case .queen: "12"
        case .jack: "⇄"
        case .four: "← 4"
        case .seven: "7 ⋯"
        default: nil
        }
    }

    /// Spoken description. Ranks alone are ambiguous aloud, so each says what
    /// it does (§53).
    static func accessibilityLabel(for rank: CardRank) -> String {
        switch rank {
        case .ace: String(localized: "card.ace.spoken")
        case .king: String(localized: "card.king.spoken")
        case .queen: String(localized: "card.queen.spoken")
        case .jack: String(localized: "card.jack.spoken")
        case .four: String(localized: "card.four.spoken")
        case .seven: String(localized: "card.seven.spoken")
        default: String(localized: "card.number.spoken \(rank.rawValue)")
        }
    }
}

/// Where a card is being shown.
enum CardRole: String {
    case hand
    case discard
}

/// The local player's hand.
///
/// Cards overlap into a fan when there are many, so a full hand of five stays
/// reachable on a phone without shrinking the cards to illegibility.
struct HandView: View {
    let cards: [Card]
    let playable: Set<Card>
    var selected: Card?
    var cardWidth: CGFloat = 76
    var onSelect: (Card) -> Void

    var body: some View {
        HStack(spacing: -cardWidth * 0.08) {
            ForEach(cards) { card in
                CardView(
                    card: card,
                    width: cardWidth,
                    isPlayable: playable.contains(card),
                    isSelected: selected == card,
                    role: .hand
                )
                .zIndex(selected == card ? 1 : 0)
                .onTapGesture {
                    guard playable.contains(card) else { return }
                    onSelect(card)
                }
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: selected)
    }
}
