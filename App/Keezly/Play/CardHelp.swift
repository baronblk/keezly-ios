import KeezlyCore
import SwiftUI

/// What a card does, at the moment somebody is holding it.
///
/// The rulebook answers this too, and asking somebody mid-turn to leave the
/// board, find the right section and come back is asking them to lose their
/// place. A long press on the card itself is the shortest route to the one
/// sentence they wanted (§52).
///
/// The wording is the rulebook's own — the same section, not a summary of it —
/// so the two can never come to disagree.
struct CardHelp: Identifiable, Hashable {
    let rank: CardRank
    var id: Int { rank.rawValue }

    /// The card's name, as everything else in the app says it.
    var title: String { MoveNarrator.rankName(rank) }

    /// The rule, from the rulebook.
    var body: String { Rulebook.text("rules.\(Self.section(for: rank)).body") }

    /// Which section of the rulebook explains this rank.
    ///
    /// The cards that behave unusually each have one of their own; the plain
    /// numbers share the section about moving forward, which is exactly what
    /// they do.
    static func section(for rank: CardRank) -> String {
        switch rank {
        case .ace: "ace"
        case .king: "king"
        case .queen: "queen"
        case .jack: "jack"
        case .four: "four"
        case .seven: "seven"
        default: "moving"
        }
    }
}

/// The card help as a sheet.
struct CardHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 16

    let help: CardHelp

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Keezly.Spacing.medium) {
                Text(verbatim: help.body)
                    .font(.system(size: bodySize, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Keezly.Spacing.large)
            .navigationTitle(Text(verbatim: help.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .accessibilityIdentifier("cardHelp")
    }
}
