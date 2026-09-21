import KeezlyCore
import SwiftUI

/// The end of a match.
///
/// Games need an ending as much as they need a start. Until this existed a
/// finished board simply stopped accepting moves and the player was left
/// holding a device that had gone quiet — the match was saved and the menu was
/// reachable in code, but nothing on screen said so.
///
/// Says who won and offers the one thing there is left to do.
struct MatchEndView: View {
    @Environment(\.boardTheme) private var theme
    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 26
    @ScaledMetric(relativeTo: .subheadline) private var labelSize: CGFloat = 15

    let result: GameResult
    /// The seat this device is playing, when there is one, so the winner can be
    /// addressed rather than described.
    let localSeat: Seat?
    var onLeave: () -> Void

    private var didWin: Bool {
        guard let localSeat else { return false }
        return result.winningSeats.contains(localSeat)
    }

    /// The winning seats, named and joined the way the language joins things.
    private var winners: String {
        ListFormatter.localizedString(
            byJoining: result.winningSeats.map { MoveNarrator.seatName($0) }
        )
    }

    var body: some View {
        ZStack {
            theme.table.opacity(0.94).ignoresSafeArea()

            VStack(spacing: Keezly.Spacing.large) {
                VStack(spacing: Keezly.Spacing.small) {
                    Text(didWin ? "result.youWin" : "result.winner \(winners)")
                        .font(.system(size: titleSize, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.95))
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("result")

                    if result.wonByDefault {
                        Text("result.byDefault")
                            .font(.system(size: labelSize, design: .rounded))
                            .foregroundStyle(.white.opacity(0.68))
                            .multilineTextAlignment(.center)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                Button(action: onLeave) {
                    Text("result.back")
                        .font(.system(size: labelSize * 1.15, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Keezly.Spacing.medium)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("result.back")
            }
            .frame(maxWidth: 420)
            .padding(Keezly.Spacing.section)
        }
    }
}
