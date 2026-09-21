import KeezlyCore
import SwiftUI

/// Where a match begins.
///
/// Laid out as the table itself rather than as a settings form: the board's
/// wood, the same seals that mark a seat, and one thing to do. Only what works
/// is here — a menu item that does nothing is worse than a missing one (§36).
struct MainMenuView: View {
    @Environment(\.boardTheme) private var theme
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 44
    @ScaledMetric(relativeTo: .subheadline) private var labelSize: CGFloat = 15

    @Binding var table: TableConfiguration
    /// The match a player could pick up again, if there is one.
    var resumable: MatchSummary?
    /// Why the last attempt to pick one up failed.
    var restoreFailure: String?
    var onStart: () -> Void
    var onContinue: () -> Void = {}
    var onTutorial: () -> Void = {}

    @State private var showsRules = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                theme.table.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Keezly.Spacing.large) {
                        masthead
                        if let resumable { continueButton(for: resumable) }
                        if let restoreFailure { failureNote(restoreFailure) }
                        panel
                        startButton
                        secondaryActions
                    }
                    .frame(maxWidth: 560)
                    .padding(.horizontal, Keezly.Spacing.large)
                    .padding(.vertical, Keezly.Spacing.section)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height, alignment: .center)
                }
            }
        }
        .accessibilityIdentifier("menu.root")
    }

    // MARK: - Pieces

    private var masthead: some View {
        VStack(spacing: Keezly.Spacing.small) {
            // Light, not the system's primary colour. This text sits on the
            // dark table rather than on a panel, and in light mode the system
            // colours are dark — the subtitle was all but invisible.
            Text(verbatim: "KEEZLY")
                .font(.system(size: titleSize, weight: .bold, design: .rounded))
                .tracking(titleSize * 0.10)
                .foregroundStyle(.white.opacity(0.94))
                .shadow(color: .black.opacity(0.4), radius: 6, y: 2)

            Text("menu.subtitle")
                .font(.system(size: labelSize, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: Keezly.Spacing.large) {
            field("table.players") {
                Picker("table.players", selection: $table.seatCount) {
                    ForEach(TableConfiguration.seatCounts, id: \.self) { count in
                        Text(verbatim: "\(count)").tag(count)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("table.players")
            }

            field("table.sides") {
                Picker("table.sides", selection: $table.prefersTeams) {
                    Text("table.sides.teams").tag(true)
                    Text("table.sides.free").tag(false)
                }
                .pickerStyle(.segmented)
                .disabled(!table.allowsTeams)
                .accessibilityIdentifier("table.sides")

                // Said plainly rather than left to be discovered: the control
                // is disabled for a reason, and the reason is the table size.
                if !table.allowsTeams {
                    Text("table.sides.unavailable")
                        .font(.system(size: labelSize * 0.88, design: .rounded))
                        .foregroundStyle(Keezly.Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            field("table.people") {
                Picker("table.people", selection: $table.humanCount) {
                    ForEach(table.humanRange, id: \.self) { count in
                        Text(verbatim: "\(count)").tag(count)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("table.people")

                // What sharing the device actually means at this table. At
                // four seats two people are opponents, at six they are
                // partners, and nobody should have to work that out from the
                // seating.
                Text(
                    table.isPassAndPlay
                        ? (table.seatsPeopleAsPartners ? "table.people.partners" : "table.people.rivals")
                        : "table.people.solo"
                )
                .font(.system(size: labelSize * 0.88, design: .rounded))
                .foregroundStyle(Keezly.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }

            field("table.opponents") {
                Picker("table.opponents", selection: $table.difficulty) {
                    Text("ai.easy").tag(AIDifficulty.easy)
                    Text("ai.medium").tag(AIDifficulty.medium)
                    Text("ai.hard").tag(AIDifficulty.hard)
                }
                .pickerStyle(.segmented)
                .disabled(table.seatedHumans >= table.seatCount)
                .accessibilityIdentifier("table.opponents")
            }

            seats
        }
        .padding(Keezly.Spacing.large)
        .background {
            let shape = RoundedRectangle(cornerRadius: Keezly.Radius.sheet, style: .continuous)
            shape
                .fill(theme.surfaceMid)
                .overlay(shape.strokeBorder(theme.edge.opacity(0.5), lineWidth: 1))
                .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1).padding(1))
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        }
    }

    /// The seats as they will actually be: the player's own first, then the
    /// opponents, with partners marked. Choosing a table should show what the
    /// table will look like, not just set a number.
    private var seats: some View {
        VStack(alignment: .leading, spacing: Keezly.Spacing.small) {
            Text("table.seats")
                .font(.system(size: labelSize, weight: .semibold, design: .rounded))
                .foregroundStyle(Keezly.Palette.secondaryText)

            HStack(spacing: Keezly.Spacing.small) {
                ForEach(0..<table.seatCount, id: \.self) { index in
                    let seat = Seat(index)
                    let identity = PlayerIdentity.identity(for: seat)
                    let isPerson = index < table.seatedHumans
                    let isPartner = table.teamMode == .teamsOfTwo
                        && index != 0
                        && table.gameConfiguration.areAllied(Seat(0), seat)

                    VStack(spacing: 4) {
                        ZStack {
                            Circle().fill(identity.color.opacity(0.28))
                            Circle().strokeBorder(identity.color.opacity(0.6), lineWidth: 1)
                            MarkShape(mark: identity.mark)
                                .fill(identity.color)
                                .frame(width: 15, height: 15)
                        }
                        .frame(width: 34, height: 34)
                        .overlay {
                            if isPerson {
                                Circle().strokeBorder(identity.color, lineWidth: 2.5)
                            }
                        }

                        Text(
                            index == 0
                                ? "seat.you"
                                : seatLabel(isPerson: isPerson, isPartner: isPartner, index: index)
                        )
                            .font(.system(size: labelSize * 0.74, weight: .medium, design: .rounded))
                            .foregroundStyle(Keezly.Palette.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("table.seats")
    }

    /// What a seat is called in the menu: a person, a partner, or the computer.
    private func seatLabel(isPerson: Bool, isPartner: Bool, index: Int) -> LocalizedStringKey {
        if isPerson { return "seat.person \(index + 1)" }
        return isPartner ? "seat.partner" : "seat.computer"
    }

    /// Offered above the table, because picking a match up again is what a
    /// player who left one in the middle came back for.
    private func continueButton(for match: MatchSummary) -> some View {
        Button(action: onContinue) {
            VStack(spacing: 2) {
                Text("menu.continue")
                    .font(.system(size: labelSize * 1.2, weight: .semibold, design: .rounded))
                Text("menu.continue.detail \(match.seatCount) \(match.round)")
                    .font(.system(size: labelSize * 0.82, design: .rounded))
                    .opacity(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Keezly.Spacing.medium)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier("menu.continue")
    }

    /// Said plainly. A saved match that will not open is not the player's
    /// fault and not something to hide behind a silent empty menu.
    private func failureNote(_ message: String) -> some View {
        Text("menu.restore.failed \(message)")
            .font(.system(size: labelSize * 0.88, design: .rounded))
            .foregroundStyle(.white.opacity(0.72))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Keezly.Spacing.medium)
            .background(
                RoundedRectangle(cornerRadius: Keezly.Radius.card, style: .continuous)
                    .fill(Color.black.opacity(0.28))
            )
            .accessibilityIdentifier("menu.restore.failed")
    }

    private var startButton: some View {
        Button(action: onStart) {
            VStack(spacing: 2) {
                Text("menu.start")
                    .font(.system(size: labelSize * 1.2, weight: .semibold, design: .rounded))
                Text(
                    table.teamMode == .teamsOfTwo
                        ? "table.summary.teams \(table.seatCount)"
                        : "table.summary.free \(table.seatCount)"
                )
                    .font(.system(size: labelSize * 0.82, design: .rounded))
                    .opacity(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Keezly.Spacing.medium)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier("menu.start")
    }

    /// Learning the game and looking it up, side by side and quiet.
    ///
    /// Both are secondary to starting a match, and neither should look like a
    /// third way of starting one.
    private var secondaryActions: some View {
        HStack(spacing: Keezly.Spacing.large) {
            tutorialButton
            rulesButton
        }
    }

    private var tutorialButton: some View {
        Button(action: onTutorial) {
            Text("menu.tutorial")
                .font(.system(size: labelSize, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Keezly.Spacing.small)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("menu.tutorial")
    }

    /// The rules, before a match rather than only during one.
    ///
    /// Half a Keezen table learned the game from somebody else, and the
    /// argument usually starts before the first card. Shown with the rules the
    /// configured table would actually play under, not a generic sheet.
    private var rulesButton: some View {
        Button {
            showsRules = true
        } label: {
            Text("menu.rules")
                .font(.system(size: labelSize, weight: .medium, design: .rounded))
                // Quiet on purpose. A filled control here would compete with
                // the two that actually start a game, and a greyed slab on the
                // dark table reads as disabled.
                .foregroundStyle(.white.opacity(0.72))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Keezly.Spacing.small)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("menu.rules")
        .sheet(isPresented: $showsRules) {
            RulebookView(rules: table.gameConfiguration.ruleSet)
        }
    }

    @ViewBuilder
    private func field(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Keezly.Spacing.small) {
            Text(title)
                .font(.system(size: labelSize, weight: .semibold, design: .rounded))
                .foregroundStyle(Keezly.Palette.secondaryText)
            content()
        }
    }
}
