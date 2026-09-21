import KeezlyCore
import SwiftUI

/// Every match on the device, with what became of it.
///
/// Built from `MatchStore.list()`, which reads each saved match and refuses any
/// it cannot verify — so a match in this list is one that will open (§57,
/// DEC-023). A row that says "four players, you won" is saying something the
/// engine confirmed, not something written down beside the match and hoped for.
struct MatchListView: View {
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 16

    let matches: [MatchSummary]
    /// The statistics these matches add up to.
    let statistics: Statistics
    var onWatch: (MatchSummary) -> Void
    var onResume: (MatchSummary) -> Void

    var body: some View {
        NavigationStack {
            List {
                if !matches.isEmpty {
                    Section {
                        StatisticsSummaryView(statistics: statistics)
                    }
                }

                Section {
                    if matches.isEmpty {
                        Text("history.empty")
                            .font(.system(size: bodySize, design: .rounded))
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("history.empty")
                    }
                    ForEach(matches, id: \.matchID) { match in
                        row(match)
                    }
                } header: {
                    Text("history.matches")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(Text("history.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("history")
    }

    private func row(_ match: MatchSummary) -> some View {
        Button {
            // An unfinished match is picked up; a finished one is watched.
            // Offering "resume" on a match that is over would be a control
            // that cannot do what it says.
            if match.status == .active {
                onResume(match)
            } else {
                onWatch(match)
            }
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: Keezly.Spacing.tight) {
                Text(title(for: match))
                    .font(.system(size: bodySize, weight: .medium, design: .rounded))
                HStack(spacing: Keezly.Spacing.small) {
                    Text(detail(for: match))
                    Text(verbatim: "·")
                    Text(date(match.updatedAt), style: .date)
                }
                .font(.system(size: bodySize * 0.85, design: .rounded))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Keezly.Spacing.tight)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("history.match")
    }

    private func date(_ seconds: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    private func title(for match: MatchSummary) -> LocalizedStringKey {
        match.teamMode == .teamsOfTwo
            ? "table.summary.teams \(match.seatCount)"
            : "table.summary.free \(match.seatCount)"
    }

    private func detail(for match: MatchSummary) -> LocalizedStringKey {
        switch match.status {
        case .active: "history.unfinished \(match.round)"
        case .abandoned: "history.abandoned"
        case .completed:
            if let winner = match.winningSeat {
                winner == 0 ? "history.won" : "history.lost \(MoveNarrator.seatName(Seat(winner)))"
            } else {
                "history.finished"
            }
        }
    }
}
