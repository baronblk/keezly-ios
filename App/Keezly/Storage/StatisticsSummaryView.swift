import SwiftUI

/// The numbers, said plainly.
///
/// No graphs and no streaks. Keezen is a family game with a great deal of luck
/// in it, and a chart implying that a run of bad deals means something about
/// the player would be making a claim the game cannot support (§30).
struct StatisticsSummaryView: View {
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 16

    let statistics: Statistics

    var body: some View {
        VStack(alignment: .leading, spacing: Keezly.Spacing.small) {
            line("stats.played", value: "\(statistics.played)")
            line("stats.finished", value: "\(statistics.finished)")
            if let rate = statistics.winRate {
                line("stats.won", value: "\(statistics.won) · \(Int((rate * 100).rounded()))%")
            } else {
                line("stats.won", value: "\(statistics.won)")
            }
            line("stats.moves", value: "\(statistics.movesPlayed)")
            if statistics.inTeams > 0 || statistics.freeForAll > 0 {
                line("stats.sides", value: "\(statistics.inTeams) · \(statistics.freeForAll)")
            }
        }
        .padding(.vertical, Keezly.Spacing.tight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stats")
    }

    private func line(_ label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: bodySize * 0.95, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: Keezly.Spacing.medium)
            Text(verbatim: value)
                .font(.system(size: bodySize * 0.95, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
