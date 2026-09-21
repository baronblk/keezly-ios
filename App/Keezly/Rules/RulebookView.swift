import KeezlyCore
import SwiftUI

/// The rules, in the app, at the table.
///
/// Keezen is learned from whoever taught you, which means half a table is
/// usually playing a slightly different game. So this does two things a printed
/// sheet cannot: it says plainly which rules *this* match is using, and where
/// tables genuinely disagree it shows both readings side by side with the one
/// in force marked.
///
/// A reference, not a lesson. Somebody halfway through a turn wondering what a
/// Four does should find the answer in one tap and one sentence.
struct RulebookView: View {
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 16

    /// The rules actually in force, so the book can mark them.
    let rules: RuleSet

    var body: some View {
        NavigationStack {
            List {
                Section {
                    preset
                }
                ForEach(Rulebook.chapters) { chapter in
                    Section {
                        ForEach(chapter.sections) { section in
                            row(section)
                        }
                    } header: {
                        Text(verbatim: chapter.title)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(Text("rules.title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("rulebook")
    }

    /// Which rules are in play, said once at the top.
    private var preset: some View {
        VStack(alignment: .leading, spacing: Keezly.Spacing.tight) {
            Text("rules.preset.title")
                .font(.system(size: bodySize * 0.8, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(verbatim: Rulebook.name(of: rules.preset))
                .font(.system(size: bodySize * 1.1, weight: .semibold, design: .rounded))
            if Rulebook.isHouseRuled(rules) {
                Text("rules.houseRuled")
                    .font(.system(size: bodySize * 0.9, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Keezly.Spacing.tight)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("rulebook.preset")
    }

    private func row(_ section: RuleSection) -> some View {
        VStack(alignment: .leading, spacing: Keezly.Spacing.small) {
            Text(verbatim: section.title)
                .font(.system(size: bodySize, weight: .semibold, design: .rounded))
            Text(verbatim: section.body)
                .font(.system(size: bodySize * 0.95, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let facet = section.facet {
                variation(facet)
            }
        }
        .padding(.vertical, Keezly.Spacing.tight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rulebook.\(section.id)")
    }

    /// The two readings of a contested rule, with the one in force marked.
    ///
    /// Both are shown even when the table plays the traditional one. Knowing
    /// what you are *not* playing is half of what settles an argument.
    @ViewBuilder
    private func variation(_ facet: RuleFacet) -> some View {
        VStack(alignment: .leading, spacing: Keezly.Spacing.small) {
            Text("rules.variation.hint")
                .font(.system(size: bodySize * 0.8, design: .rounded))
                .foregroundStyle(.tertiary)

            ForEach(facet.options(in: rules)) { option in
                HStack(alignment: .firstTextBaseline, spacing: Keezly.Spacing.small) {
                    // A mark as well as weight and colour: the active option
                    // must be identifiable without seeing either (§53).
                    Image(systemName: option.isActive ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(option.isActive ? Color.accentColor : Color.secondary)
                        .font(.system(size: bodySize * 0.9))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: option.label)
                            .font(.system(
                                size: bodySize * 0.9,
                                weight: option.isActive ? .semibold : .regular,
                                design: .rounded
                            ))
                            .fixedSize(horizontal: false, vertical: true)
                        badges(for: option)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(option.isActive ? .isSelected : [])
                .accessibilityIdentifier("rulebook.option.\(option.id)")
            }
        }
        .padding(.top, Keezly.Spacing.tight)
    }

    private func badges(for option: RuleOption) -> some View {
        HStack(spacing: Keezly.Spacing.small) {
            if option.isActive {
                badge("rules.badge.active", prominent: true)
            }
            badge(option.isClassic ? "rules.badge.classic" : "rules.badge.house", prominent: false)
        }
    }

    private func badge(_ key: LocalizedStringKey, prominent: Bool) -> some View {
        Text(key)
            .font(.system(size: bodySize * 0.72, weight: .medium, design: .rounded))
            .padding(.horizontal, Keezly.Spacing.small)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(
                    prominent
                        ? Color.accentColor.opacity(0.18)
                        : Color.secondary.opacity(0.12)
                )
            )
            .foregroundStyle(prominent ? Color.accentColor : Color.secondary)
    }
}
