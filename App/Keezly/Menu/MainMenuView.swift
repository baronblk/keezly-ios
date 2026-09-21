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
    @Environment(\.dynamicTypeSize) private var typeSize

    @Binding var table: TableConfiguration
    /// The match a player could pick up again, if there is one.
    var resumable: MatchSummary?
    /// Why the last attempt to pick one up failed.
    var restoreFailure: String?
    var onStart: () -> Void
    var onContinue: () -> Void = {}
    var onTutorial: () -> Void = {}
    /// Whether this is somebody's first time here.
    var isNewcomer = false

    @State private var showsRules = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                theme.table.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Keezly.Spacing.large) {
                        masthead
                        if isNewcomer { welcome }
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
                .tableFieldPicker(accessibilitySize: typeSize.isAccessibilitySize)
                .accessibilityIdentifier("table.players")
            }

            field("table.sides") {
                Picker("table.sides", selection: $table.prefersTeams) {
                    Text("table.sides.teams").tag(true)
                    Text("table.sides.free").tag(false)
                }
                .tableFieldPicker(accessibilitySize: typeSize.isAccessibilitySize)
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
                .tableFieldPicker(accessibilitySize: typeSize.isAccessibilitySize)
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
                .tableFieldPicker(accessibilitySize: typeSize.isAccessibilitySize)
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

            // A row of labelled swatches is a picture of the table, and at
            // accessibility text sizes it stops being one: the labels grow
            // past their swatches and run into each other. There the same
            // information becomes a list, which reads at any size.
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Keezly.Spacing.small) {
                    ForEach(0..<table.seatCount, id: \.self) { index in
                        HStack(spacing: Keezly.Spacing.small) {
                            swatch(at: index)
                            Text(role(at: index))
                                .font(.system(size: labelSize, weight: .medium, design: .rounded))
                                .foregroundStyle(Keezly.Palette.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: Keezly.Spacing.small) {
                    ForEach(0..<table.seatCount, id: \.self) { index in
                        VStack(spacing: 4) {
                            swatch(at: index)
                            Text(role(at: index))
                                .font(.system(size: labelSize * 0.74, weight: .medium, design: .rounded))
                                .foregroundStyle(Keezly.Palette.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("table.seats")
    }

    /// One seat's colour and mark.
    private func swatch(at index: Int) -> some View {
        let identity = PlayerIdentity.identity(for: Seat(index))
        let isPerson = index < table.seatedHumans
        return ZStack {
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
    }

    /// What a seat is called in the menu: you, a person, a partner, or the
    /// computer.
    private func role(at index: Int) -> LocalizedStringKey {
        guard index != 0 else { return "seat.you" }
        if index < table.seatedHumans { return "seat.person \(index + 1)" }
        let isPartner = table.teamMode == .teamsOfTwo
            && table.gameConfiguration.areAllied(Seat(0), Seat(index))
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
            // Already offered loudly at the top for a newcomer; offering it
            // twice on one screen is how a menu starts to look like a form.
            if !isNewcomer { tutorialButton }
            rulesButton
        }
    }

    /// The whole of Keezly's onboarding.
    ///
    /// One line and one button, shown until a first match or lesson has been
    /// started. A board game somebody has to swipe through three screens to
    /// reach is a board game they open once (§36).
    private var welcome: some View {
        VStack(spacing: Keezly.Spacing.small) {
            Text("menu.welcome")
                .font(.system(size: labelSize, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onTutorial) {
                Text("menu.tutorial")
                    .font(.system(size: labelSize * 1.1, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Keezly.Spacing.medium)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("menu.tutorial")
        }
        .accessibilityIdentifier("menu.welcome")
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
