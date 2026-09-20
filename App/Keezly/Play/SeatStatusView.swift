import KeezlyCore
import SwiftUI

/// What is worth knowing about one seat at a glance (§35).
///
/// Colour, mark, how many cards are left, who deals, and who is on turn — and
/// nothing else. No debug information, no scores that do not exist yet.
struct SeatStatusView: View {
    // Chrome text follows the reader's setting (§53). Card ranks and pips
    // deliberately do not: they scale with the card they are printed on, and a
    // rank that outgrew its card would be less readable, not more.
    @ScaledMetric(relativeTo: .subheadline) private var nameSize: CGFloat = 14
    @ScaledMetric(relativeTo: .caption) private var detailSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption2) private var badgeSize: CGFloat = 10
    @ScaledMetric(relativeTo: .subheadline) private var markSize: CGFloat = 40

    let seat: Seat
    let role: SeatRole
    let cardCount: Int
    let pawnsHome: Int
    let isDealer: Bool
    let isOnTurn: Bool
    let isPartner: Bool

    private var identity: PlayerIdentity { PlayerIdentity.identity(for: seat) }
    private var size: CGFloat { markSize }

    var body: some View {
        HStack(spacing: Keezly.Spacing.small) {
            ZStack {
                Circle().fill(identity.color.opacity(0.22))
                MarkShape(mark: identity.mark)
                    .fill(identity.color)
                    .frame(width: size * 0.5, height: size * 0.5)
            }
            .frame(width: size, height: size)
            .overlay(
                Circle().strokeBorder(
                    isOnTurn ? identity.color : .clear,
                    lineWidth: 2.5
                )
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(LocalizedStringKey(identity.nameKey))
                        .font(.system(size: nameSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(Keezly.Palette.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if isPartner {
                        Text("seat.partner")
                            .font(.system(size: badgeSize, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(identity.color.opacity(0.22)))
                    }
                    if isDealer {
                        Text("seat.dealer")
                            .font(.system(size: badgeSize, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Keezly.Palette.cardInk.opacity(0.12)))
                    }
                }

                HStack(spacing: Keezly.Spacing.small) {
                    Label("\(cardCount)", systemImage: "rectangle.on.rectangle")
                    Label("\(pawnsHome)/\(pawnsPerSeat)", systemImage: "house")
                }
                .font(.system(size: detailSize, design: .rounded))
                .foregroundStyle(Keezly.Palette.secondaryText)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .fixedSize()
            }
        }
        .padding(.horizontal, Keezly.Spacing.small)
        .padding(.vertical, Keezly.Spacing.tight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Keezly.Radius.card, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(isOnTurn ? 1 : 0.65)
        )
        .accessibilityElement(children: .combine)
    }
}

/// A seat on a phone.
///
/// Not the panel with the name squeezed smaller — a different component. Six
/// panels across a phone forced the names to wrap and pushed the whole layout
/// wider than the screen, which clipped the board. The chip drops the name
/// entirely: colour and mark already identify the seat, and they identify it
/// the same way on the board, so nothing is lost (§42).
struct SeatChip: View {
    /// Follows the reader's text size, within reason: a chip may grow, but six
    /// of them still have to fit across a phone, so the mark is capped.
    @ScaledMetric(relativeTo: .caption2) private var countSize: CGFloat = 10
    @ScaledMetric(relativeTo: .caption2) private var chipSize: CGFloat = 30

    let seat: Seat
    let cardCount: Int
    let pawnsHome: Int
    let isDealer: Bool
    let isOnTurn: Bool
    let isPartner: Bool

    private var identity: PlayerIdentity { PlayerIdentity.identity(for: seat) }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().fill(identity.color.opacity(0.24))
                MarkShape(mark: identity.mark)
                    .fill(identity.color)
                    .frame(width: 15, height: 15)

                if isDealer {
                    Text("seat.dealer.short")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundStyle(Keezly.Palette.cardInk)
                        .padding(2)
                        .background(Circle().fill(Keezly.Palette.cardFace))
                        .offset(x: 12, y: -11)
                }
            }
            .frame(width: min(chipSize, 42), height: min(chipSize, 42))
            .overlay(Circle().strokeBorder(isOnTurn ? identity.color : .clear, lineWidth: 2.5))
            .overlay(alignment: .bottomLeading) {
                if isPartner {
                    Circle()
                        .strokeBorder(identity.color, lineWidth: 2)
                        .frame(width: 8, height: 8)
                        .background(Circle().fill(Keezly.Palette.cardFace))
                        .offset(x: -2, y: 2)
                }
            }

            Text(verbatim: "\(cardCount) · \(pawnsHome)/\(pawnsPerSeat)")
                .font(.system(size: min(countSize, 14), weight: .medium, design: .rounded))
                .foregroundStyle(Keezly.Palette.secondaryText)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: Keezly.Radius.small, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(isOnTurn ? 1 : 0.6)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LocalizedStringKey(identity.nameKey))
        .accessibilityValue("seat.status \(cardCount) \(pawnsHome)")
    }
}

/// The seats down one side of the board.
struct SeatColumn: View {
    let seats: [Seat]
    let state: GameState
    let roles: [SeatRole]
    let localSeat: Seat?
    var compact = false

    var body: some View {
        // Capped rather than stretched: on a 13-inch iPad the spare width
        // beside a square board is generous, and a panel spread across all of
        // it reads as empty rather than as informative.
        VStack(spacing: Keezly.Spacing.small) {
            Spacer(minLength: 0)
            ForEach(seats, id: \.self) { seat in
                SeatStatusView(
                    seat: seat,
                    role: roles[seat.index],
                    cardCount: state.hand(of: seat).count,
                    pawnsHome: state.pawns(of: seat).count(where: \.isHome),
                    isDealer: state.dealer == seat,
                    isOnTurn: state.currentSeat == seat,
                    isPartner: localSeat.map { state.configuration.areAllied($0, seat) && $0 != seat } ?? false,
                )
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 300)
        .frame(maxWidth: .infinity)
    }
}
