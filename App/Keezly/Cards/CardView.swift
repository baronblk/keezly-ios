import KeezlyCore
import SwiftUI

/// Where a card is being shown.
enum CardRole: String {
    case hand
    case discard
}

/// A playing card.
///
/// The goal is that a player's first thought is "that is a playing card", not
/// "that is a button with a letter on it" (§45). So: a cream face with a fine
/// border, classic corner indices top-left and rotated bottom-right, and a
/// traditional pip field in the middle. The court cards carry Keezly's own
/// reduced emblems rather than anyone's illustrations (§76).
///
/// What Keezen adds — that a Four goes backward, that a Seven splits — is a
/// small mark in the free top-right corner. Secondary by construction: it sits
/// where a real card has nothing, and never competes with the index.
struct CardView: View {
    let card: Card
    var width: CGFloat = 76
    var isPlayable = true
    var isSelected = false
    /// Where the keyboard is. Separate from `isSelected`, which is a choice the
    /// player has actually made (§46).
    var isFocused = false
    var role: CardRole = .hand
    var faceUp = true

    private var height: CGFloat { width * 1.45 }
    private var suit: CardSuitKind { Self.suit(of: card) }
    private var ink: Color { suit.isRed ? Keezly.Palette.cardRed : Keezly.Palette.cardInk }

    var body: some View {
        ZStack {
            face
            if !isPlayable {
                // Dimmed, never erased: a player who cannot move needs to see
                // which cards are stuck (§36).
                shape.fill(Keezly.Palette.table.opacity(0.42))
            }
        }
        .frame(width: width, height: height)
        // Two shadows: a tight one that sets the card on the fan, and a soft
        // one that gives it height. A chosen card lifts on both.
        .shadow(
            color: .black.opacity(isSelected ? 0.3 : 0.22),
            radius: width * (isSelected ? 0.045 : 0.025),
            y: width * (isSelected ? 0.02 : 0.012)
        )
        .shadow(
            color: .black.opacity(isSelected ? 0.3 : 0.14),
            radius: width * (isSelected ? 0.18 : 0.08),
            y: width * (isSelected ? 0.09 : 0.035)
        )
        .offset(y: isSelected ? -width * 0.18 : 0)
        .keyboardFocusRing(isFocused, cornerRadius: width * 0.14)
        .accessibilityElement(children: .ignore)
        // The rank sits in the identifier so a screenshot fixture can find,
        // say, the Jack in a hand without knowing the deck copy it came from.
        .accessibilityIdentifier("\(role.rawValue).card.\(card.rank.shorthand).\(card.id)")
        .accessibilityLabel(Self.accessibilityLabel(for: card.rank))
        .accessibilityAddTraits(isPlayable ? .isButton : [])
        .accessibilityValue(isPlayable ? "" : String(localized: "card.unplayable"))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: width * 0.085, style: .continuous)
    }

    @ViewBuilder
    private var face: some View {
        if faceUp {
            ZStack {
                // Card stock rather than flat paper: a faint sheen from the
                // top edge, the way a card catches light when it is held.
                shape.fill(Keezly.Palette.cardFace)
                shape.fill(
                    LinearGradient(
                        colors: [.white.opacity(0.5), .clear, Keezly.Palette.cardInk.opacity(0.045)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                shape.strokeBorder(Keezly.Palette.cardInk.opacity(0.22), lineWidth: max(0.5, width * 0.009))

                centre
                    .padding(.horizontal, width * 0.2)
                    .padding(.vertical, height * 0.13)

                cornerIndices
                if let hint = Self.hint(for: card.rank) { keezenHint(hint) }
            }
            .overlay {
                if isSelected {
                    // Chosen, not merely highlighted: the card's own ink draws
                    // the border, with a second inner line so the state reads
                    // at a glance without adding a colour of its own.
                    shape.strokeBorder(ink.opacity(0.68), lineWidth: max(1.2, width * 0.026))
                    shape
                        .strokeBorder(.white.opacity(0.7), lineWidth: max(0.5, width * 0.012))
                        .padding(max(1, width * 0.026))
                }
            }
        } else {
            CardBackPattern()
                .clipShape(shape)
                .overlay(shape.strokeBorder(.white.opacity(0.2), lineWidth: max(0.5, width * 0.01)))
        }
    }

    // MARK: - Parts

    @ViewBuilder
    private var centre: some View {
        switch card.rank {
        case .jack, .queen, .king:
            CourtPanel(rank: card.rank, suit: suit, ink: ink)
        default:
            PipField(value: card.rank == .ace ? 1 : card.rank.rawValue, suit: suit, ink: ink)
        }
    }

    private var cornerIndices: some View {
        GeometryReader { proxy in
            let index = CornerIndex(rank: card.rank, suit: suit, ink: ink, width: width)
            ZStack {
                index
                    .position(x: width * 0.145, y: height * 0.125)
                index
                    .rotationEffect(.degrees(180))
                    .position(x: proxy.size.width - width * 0.145, y: proxy.size.height - height * 0.125)
            }
        }
    }

    private func keezenHint(_ hint: String) -> some View {
        Text(hint)
            // The Keezen note, in the corner a real card leaves empty. Kept
            // secondary by weight as well as by position.
            .font(.system(size: width * 0.11, weight: .medium, design: .rounded))
            .foregroundStyle(Keezly.Palette.cardInk.opacity(0.42))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.top, height * 0.055)
            .padding(.trailing, width * 0.075)
    }

    // MARK: - Mapping and text

    /// The engine's decorative suit, turned into something drawable. The rules
    /// never see either (§10).
    static func suit(of card: Card) -> CardSuitKind {
        switch card.visualSuit {
        case .spades: .spade
        case .hearts: .heart
        case .diamonds: .diamond
        case .clubs: .club
        }
    }

    /// What Keezen makes this card do, when that is not its face value.
    static func hint(for rank: CardRank) -> String? {
        switch rank {
        case .ace: "⌂1"
        case .king: "⌂"
        case .queen: "12"
        case .jack: "⇄"
        case .four: "←4"
        case .seven: "1–7"
        default: nil
        }
    }

    /// Spoken description. A rank alone is ambiguous aloud, so each says what
    /// it does (§53). Held in `MoveNarrator` so the hand, the action list and
    /// the rulebook all describe a card with one set of words.
    static func accessibilityLabel(for rank: CardRank) -> String {
        MoveNarrator.card(rank)
    }
}

/// Rank over suit, the way a card has carried its value for two centuries.
private struct CornerIndex: View {
    let rank: CardRank
    let suit: CardSuitKind
    let ink: Color
    let width: CGFloat

    var body: some View {
        VStack(spacing: width * 0.01) {
            Text(rank.shorthand)
                .font(.system(size: width * 0.19, weight: .bold, design: .rounded))
                .foregroundStyle(ink)
            SuitGlyph(suit: suit)
                .fill(ink)
                .frame(width: width * 0.115, height: width * 0.115)
        }
        .fixedSize()
    }
}

/// The pips of a number card, laid out traditionally.
private struct PipField: View {
    let value: Int
    let suit: CardSuitKind
    let ink: Color

    var body: some View {
        GeometryReader { proxy in
            let pips = PipLayout.pips(for: value)
            // The ace carries one large pip; the rest scale down as the card
            // fills up, which is what keeps a ten from becoming a smudge.
            let size = value == 1
                ? min(proxy.size.width, proxy.size.height) * 0.62
                : proxy.size.width * (value >= 9 ? 0.3 : 0.36)

            ForEach(Array(pips.enumerated()), id: \.offset) { _, pip in
                SuitGlyph(suit: suit)
                    .fill(ink)
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(pip.inverted ? 180 : 0))
                    .position(
                        x: proxy.size.width * pip.x,
                        y: proxy.size.height * pip.y
                    )
            }
        }
    }
}

/// A court card: Keezly's own emblem, mirrored top and bottom, with the suit
/// shown small at each end.
private struct CourtPanel: View {
    let rank: CardRank
    let suit: CardSuitKind
    let ink: Color

    private var emblem: CourtEmblem.Rank {
        switch rank {
        case .queen: .queen
        case .king: .king
        default: .jack
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                RoundedRectangle(cornerRadius: width * 0.1, style: .continuous)
                    .fill(ink.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: width * 0.1, style: .continuous)
                            .strokeBorder(ink.opacity(0.16), lineWidth: max(0.5, width * 0.014))
                    )

                VStack(spacing: 0) {
                    half(width: width, height: height / 2, inverted: false)
                    half(width: width, height: height / 2, inverted: true)
                }
            }
        }
    }

    private func half(width: CGFloat, height: CGFloat, inverted: Bool) -> some View {
        VStack(spacing: height * 0.06) {
            CourtEmblem(rank: emblem)
                .fill(ink.opacity(0.82))
                .frame(width: width * 0.48, height: height * 0.4)
            SuitGlyph(suit: suit)
                .fill(ink)
                .frame(width: width * 0.24, height: width * 0.24)
        }
        .padding(.vertical, height * 0.1)
        .rotationEffect(.degrees(inverted ? 180 : 0))
    }
}
