import KeezlyCore
import SwiftUI

/// The screen that covers the board while the device changes hands (§34).
///
/// Its only job is that the previous player's cards are gone and the next
/// player's have not appeared. It says whose turn it is and nothing else about
/// the position — no hand, no count, nothing that would reward holding on to
/// the device a moment longer.
struct HandoverView: View {
    @Environment(\.boardTheme) private var theme
    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 26
    @ScaledMetric(relativeTo: .subheadline) private var labelSize: CGFloat = 15

    let seat: Seat
    var onContinue: () -> Void

    private var identity: PlayerIdentity { PlayerIdentity.identity(for: seat) }

    var body: some View {
        ZStack {
            // Opaque, not a blur: a blurred hand is still a hand, and some of
            // these cards are large enough to read through one.
            theme.table.ignoresSafeArea()

            VStack(spacing: Keezly.Spacing.large) {
                ZStack {
                    Circle().fill(identity.color.opacity(0.28))
                    Circle().strokeBorder(identity.color.opacity(0.6), lineWidth: 2)
                    MarkShape(mark: identity.mark)
                        .fill(identity.color)
                        .frame(width: 34, height: 34)
                }
                .frame(width: 76, height: 76)

                VStack(spacing: Keezly.Spacing.small) {
                    Text("handover.title \(String(localized: String.LocalizationValue(identity.nameKey)))")
                        .font(.system(size: titleSize, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.94))
                        .multilineTextAlignment(.center)
                        // Carried by the title rather than by the cover itself:
                        // an identifier on the container made the button
                        // underneath it unreachable to a test, which is exactly
                        // the sort of thing that would have shipped unnoticed.
                        .accessibilityIdentifier("handover")

                    Text("handover.subtitle")
                        .font(.system(size: labelSize, design: .rounded))
                        .foregroundStyle(.white.opacity(0.66))
                        .multilineTextAlignment(.center)
                }
                .fixedSize(horizontal: false, vertical: true)

                Button(action: onContinue) {
                    Text("handover.ready")
                        .font(.system(size: labelSize * 1.15, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Keezly.Spacing.medium)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("handover.ready")
            }
            .frame(maxWidth: 420)
            .padding(Keezly.Spacing.section)
        }
    }
}
