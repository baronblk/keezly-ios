import KeezlyCore
import SwiftUI

/// Every legal move, as a list you can play from.
///
/// The second complete way into the game (§53). Not a hint panel and not a
/// simplified mode: the board and this list offer the same moves, and playing
/// one from here goes through exactly the same submission path as tapping a
/// square. A player who cannot use the board is not playing a lesser version.
///
/// Grouped by card, because that is the shape of the decision — first which
/// card, then what to do with it — and because it keeps the list short enough
/// to hear. Each row speaks the move and its consequence in one sentence, so
/// VoiceOver does not have to be asked twice.
struct ActionListView: View {
    @Environment(\.boardTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var rowSize: CGFloat = 16

    let list: ActionList
    /// Whether the player has no legal move and must throw in their hand.
    let mustFold: Bool
    var onPlay: (Move) -> Void
    var onFold: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if list.isEmpty {
                    empty
                } else {
                    moves
                }
            }
            .navigationTitle(Text("a11y.actions.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("actions")
    }

    private var moves: some View {
        List {
            ForEach(list.byCard) { group in
                Section {
                    ForEach(group.entries) { entry in
                        Button {
                            onPlay(entry.move)
                            dismiss()
                        } label: {
                            row(entry)
                        }
                        // One sentence, not three labels: a row read as
                        // "Red pawn 2 — five squares — knocks out blue pawn 1"
                        // in three stops is slower to act on than the same
                        // thing said once.
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(entry.spoken)
                        .accessibilityIdentifier("actions.move.\(entry.move.id)")
                    }
                } header: {
                    Text(MoveNarrator.rankName(group.card.rank))
                        .accessibilityLabel(group.spoken)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(_ entry: ActionListEntry) -> some View {
        VStack(alignment: .leading, spacing: Keezly.Spacing.tight) {
            Text(entry.description)
                .font(.system(size: rowSize, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            if let consequence = entry.consequence {
                Text(consequence)
                    .font(.system(size: rowSize * 0.85, weight: .medium, design: .rounded))
                    // Colour is never the only carrier: the consequence is a
                    // sentence of its own whether or not it can be seen (§53).
                    .foregroundStyle(theme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Keezly.Spacing.tight)
    }

    private var empty: some View {
        VStack(spacing: Keezly.Spacing.large) {
            Text("a11y.actions.none")
                .font(.system(size: rowSize, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if mustFold {
                Button {
                    onFold()
                    dismiss()
                } label: {
                    Text("action.fold")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Keezly.Spacing.small)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("actions.fold")
            }
        }
        .frame(maxWidth: 420)
        .padding(Keezly.Spacing.section)
    }
}
