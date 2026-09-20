import KeezlyCore
import SwiftUI

/// What is worth knowing about one seat at a glance (§35).
///
/// Colour, mark, how many cards are left, who deals, and who is on turn — and
/// nothing else. No debug information, no scores that do not exist yet.
struct SeatStatusView: View {
    let seat: Seat
    let role: SeatRole
    let cardCount: Int
    let pawnsHome: Int
    let isDealer: Bool
    let isOnTurn: Bool
    let isPartner: Bool
    var compact = false

    private var identity: PlayerIdentity { PlayerIdentity.identity(for: seat) }
    private var size: CGFloat { compact ? 30 : 40 }

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
                        .font(.system(size: compact ? 12 : 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Keezly.Palette.primaryText)
                    if isPartner {
                        Text("seat.partner")
                            .font(.system(size: compact ? 9 : 10, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(identity.color.opacity(0.22)))
                    }
                    if isDealer {
                        Text("seat.dealer")
                            .font(.system(size: compact ? 9 : 10, weight: .bold, design: .rounded))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Keezly.Palette.cardInk.opacity(0.12)))
                    }
                }

                HStack(spacing: Keezly.Spacing.small) {
                    Label("\(cardCount)", systemImage: "rectangle.on.rectangle")
                    Label("\(pawnsHome)/\(pawnsPerSeat)", systemImage: "house")
                }
                .font(.system(size: compact ? 10 : 12, design: .rounded))
                .foregroundStyle(Keezly.Palette.secondaryText)
                .labelStyle(.titleAndIcon)
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
                    compact: compact
                )
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 300)
        .frame(maxWidth: .infinity)
    }
}
