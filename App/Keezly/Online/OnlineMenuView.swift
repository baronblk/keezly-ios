import KeezlyCore
import SwiftUI

/// Where an online match is started or picked up again.
///
/// Every state Game Center can be in is a state this screen draws, because the
/// five are not interchangeable: "not signed in" is something a player can
/// fix, "not available here" is not, and "it went wrong" is neither (§26).
struct OnlineMenuView: View {
    @Environment(\.dismiss) private var dismiss
    let online: OnlinePlay
    /// Called with a match the player chose to open.
    var onOpen: (OnlineMatchRun) -> Void

    @State private var seats = 4
    @State private var teams = true
    /// Which way in was chosen, so "Try again" repeats that rather than
    /// silently switching the player to the other one.
    @State private var lastKind: GameCenterMatchmaker.Kind = .quickMatch

    var body: some View {
        NavigationStack {
            Group {
                switch online.authentication {
                case .authenticated:
                    signedIn
                case .authenticating:
                    Waiting(labelKey: "online.authenticating")
                case .unavailable(let reason):
                    Unavailable(reason: reason)
                case .unauthenticated:
                    SignIn(action: online.authenticate)
                case .failed(let reason):
                    Failed(reason: reason, retry: online.authenticate)
                }
            }
            .accessibilityIdentifier("online.screen")
            // The start flow's state, by name, for a test to wait on. Carries
            // no behaviour — it is the same mechanism VoiceOver reads, and it
            // lets a physical-device test wait for `waitingForPlayers` rather
            // than for a spinner to appear or for a fixed number of seconds.
            .accessibilityElement(children: .contain)
            .accessibilityValue(online.startState.name)
            .navigationTitle(Text("online.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.done") { dismiss() }
                }
                // In the toolbar rather than at the foot of the list. Below
                // twenty-six rows it was not merely hard to reach: a `List` is
                // lazy, so it had not been built at all and nothing — a player
                // scrolling, or a test looking — could find it.
                ToolbarItem(placement: .primaryAction) {
                    if online.matches.filter(\.isAbandonedSearch).count >= 3 {
                        Button {
                            Task { await online.removeOwnAbandonedMatches() }
                        } label: {
                            Label("online.cleanup", systemImage: "sparkles")
                        }
                        .accessibilityIdentifier("online.cleanup")
                    }
                }
            }
        }
        .task { await online.refresh() }
    }

    // MARK: - Signed in

    private var signedIn: some View {
        List {
            stateProbe
            introSection
            gameCenterStatusSection
            newMatchSection
            howSection
            progressSection
            failureSection
            matchesSection
            if let failure = online.failure {
                Section { Notice(text: failure) }
            }
        }
        .refreshable { await online.refresh() }
    }

    /// The state, as an element a test can find by name.
    ///
    /// Always present and always current. Hidden from sight and from
    /// VoiceOver, because it is a name for a machine to read rather than
    /// anything a player needs.
    private var stateProbe: some View {
        VStack(spacing: 0) {
            Text(online.startState.name)
                .accessibilityIdentifier("online.startState")
                .accessibilityLabel(online.startState.name)
            // What a test needs that it cannot otherwise see. The app's own
            // log goes to the device console, which is a different channel
            // from the one `xcodebuild` captures — so the facts that decide
            // the gate are published here, where a test can read them and put
            // them in its own output.
            Text(online.probeSummary)
                .accessibilityIdentifier("online.probe")
                .accessibilityLabel(online.probeSummary)
        }
        .font(.caption2)
        .foregroundStyle(.clear)
        .frame(height: 0)
    }

    private var introSection: some View {
        Section {
            Text("online.subtitle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// Where this device stands with Game Center, said at the top rather than
    /// discovered by tapping something and having it not work.
    private var gameCenterStatusSection: some View {
        Section {
            Label {
                Text("online.gameCenter.connected")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            .font(.footnote)
            .accessibilityIdentifier("online.gameCenter.status")
        }
    }

    private var newMatchSection: some View {
        Section {
            TableSeatsRow(seats: $seats, teams: $teams)
        } header: {
            Text("online.start.table")
        }
    }

    /// The two ways in, each saying what it will do **before** it does it.
    ///
    /// The old screen had one button that opened Apple's matchmaker with no
    /// warning. Being dropped into a system screen without knowing why is most
    /// of what made the flow bewildering, and it also hid the difference
    /// between picking somebody and being matched with anybody.
    private var howSection: some View {
        Section {
            Button { start(kind: .inviteFriends) } label: {
                StartChoice(
                    titleKey: "online.start.inviteFriends",
                    detailKey: "online.start.inviteFriends.why",
                    symbol: "person.2.badge.plus"
                )
            }
            .disabled(online.startState.isBusy)
            .accessibilityIdentifier("online.invite")

            Button { start(kind: .quickMatch) } label: {
                StartChoice(
                    titleKey: "online.start.quickMatch",
                    detailKey: "online.start.quickMatch.why",
                    symbol: "bolt.horizontal"
                )
            }
            .disabled(online.startState.isBusy)
            .accessibilityIdentifier("online.new")
        } header: {
            Text("online.start.how")
        }
    }

    /// Whatever is happening, in words. The defect this replaces was a spinner
    /// that explained nothing and then simply stopped.
    @ViewBuilder
    private var progressSection: some View {
        if let progressKey = online.startState.progressKey {
            Section {
                StartProgress(
                    messageKey: progressKey,
                    detail: waitingDetail,
                    isCancellable: online.startState.isCancellable,
                    cancel: online.resetStart
                )
            }
        }
    }

    @ViewBuilder
    private var failureSection: some View {
        if case .failed(let failure) = online.startState {
            Section {
                StartFailure(
                    failure: failure,
                    retry: retryAction(for: failure),
                    dismiss: online.resetStart
                )
            }
        }
    }

    /// Keezly's own list, grouped by what it wants from the player.
    ///
    /// Replaces showing Apple's raw matchmaker list as the online screen. That
    /// list gave every automatch the same name — eleven rows of
    /// "Auto-Match-Game", all saying "your turn" — with no way to tell one from
    /// another and no sign of which table it belonged to.
    @ViewBuilder
    private var matchesSection: some View {
        if online.matches.isEmpty {
            Section {
                Text("online.empty")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("online.empty")
            }
        } else {
            ForEach(OnlineLobby.sections(for: online.matches)) { section in
                Section {
                    ForEach(section.matches) { match in
                        Button { open(match) } label: { MatchRow(match: match) }
                            .accessibilityIdentifier("online.match.\(match.id)")
                            .swipeActions(edge: .trailing) {
                                // Only where leaving costs nobody a game. A
                                // match somebody has joined is not tidied away
                                // from a lobby; walking out of one is a
                                // forfeit and belongs inside the match.
                                if match.isAbandonedSearch {
                                    Button(role: .destructive) {
                                        Task { await online.abandonWaitingMatch(match) }
                                    } label: {
                                        Label("online.abandon", systemImage: "trash")
                                    }
                                    .accessibilityIdentifier("online.abandon")
                                }
                            }
                    }
                } header: {
                    Text(LocalizedStringKey(section.group.titleKey))
                } footer: {
                    if section.group == .waitingForPlayers {
                        Text("online.abandon.explain")
                        Text("online.cleanup.explain")
                    }
                }
            }
        }
    }

    /// Retrying is offered only where it could help: not for being signed
    /// out, which is fixed in Settings, and not for Game Center being
    /// unavailable, which cannot be fixed at all (§26).
    private func retryAction(for failure: OnlineStartFailure) -> (() -> Void)? {
        guard failure.isWorthRetrying else { return nil }
        // Retrying repeats the choice the player made, not a default one.
        return { start(kind: lastKind) }
    }

    /// How many seats are still empty, when that is what is happening.
    private var waitingDetail: String? {
        guard case .waitingForPlayers(let filled, let total) = online.startState else { return nil }
        return String(localized: "online.state.waitingForPlayers.detail \(filled) \(total)")
    }

    /// No `do`/`catch` here any more, and nothing to swallow.
    ///
    /// Every outcome — cancelled, failed, waiting, opened — moves
    /// `online.startState`, and every one of those states is drawn above. The
    /// old version caught the error, bound it to nothing, and then called
    /// `refresh()`, which cleared the only field a message could have appeared
    /// in. That is why the button looked dead.
    private func start(kind: GameCenterMatchmaker.Kind) {
        lastKind = kind
        online.startMatch(seats: seats, teams: teams, kind: kind, onOpen: onOpen)
    }

    private func open(_ summary: OnlineMatchSummary) {
        Task {
            do {
                onOpen(try await online.open(summary))
            } catch {
                OnlineLog.failure("open", error)
                online.noteOpenFailure(error)
            }
        }
    }
}

// MARK: - Pieces

private struct MatchRow: View {
    let match: OnlineMatchSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                // Keezly's own title: who is at the table, not GameKit's
                // "Auto-Match-Game", which is the same string for every match
                // it ever creates.
                Text(match.title).font(.body)
                Text(match.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(match.lastActivity, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch match.group {
        case .invitations: "envelope.badge"
        case .yourTurn: "play.circle.fill"
        case .theirTurn: "hourglass"
        case .waitingForPlayers: "person.badge.clock"
        case .finished: "flag.checkered"
        }
    }

    private var tint: Color {
        switch match.group {
        case .invitations, .yourTurn: Color.accentColor
        case .theirTurn, .waitingForPlayers, .finished: .secondary
        }
    }
}

private struct TableSeatsRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var seats: Int
    @Binding var teams: Bool

    var body: some View {
        // The same control the local table uses, rather than a second kind of
        // seat picker. It was a plain menu picker here, which looked different
        // from the menu for no reason and — on a phone — opened a popup whose
        // options could not be reached at all.
        VStack(alignment: .leading, spacing: 4) {
            Text("table.players").font(.footnote).foregroundStyle(.secondary)
            Picker("table.players", selection: $seats) {
                ForEach(TableConfiguration.seatCounts, id: \.self) { count in
                    Text(verbatim: "\(count)").tag(count)
                }
            }
            .tableFieldPicker(accessibilitySize: typeSize.isAccessibilitySize)
            .accessibilityIdentifier("online.seats")
        }

        // Dieselbe Regel wie am lokalen Tisch, nicht eine zweite davon.
        if TableConfiguration.allowsTeams(seatCount: seats) {
            VStack(alignment: .leading, spacing: 4) {
                Text("table.sides").font(.footnote).foregroundStyle(.secondary)
                Picker("table.sides", selection: $teams) {
                    Text("table.sides.teams").tag(true)
                    Text("table.sides.free").tag(false)
                }
                .tableFieldPicker(accessibilitySize: typeSize.isAccessibilitySize)
                .accessibilityIdentifier("online.sides")
            }
        }
    }
}

private struct SignIn: View {
    let action: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("online.title", systemImage: "person.2")
        } description: {
            Text("online.signIn.why")
        } actions: {
            Button("online.signIn", action: action)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("online.signIn")
        }
    }
}

private struct Waiting: View {
    let labelKey: LocalizedStringKey

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(labelKey).foregroundStyle(.secondary)
        }
    }
}

private struct Unavailable: View {
    let reason: String

    var body: some View {
        ContentUnavailableView {
            Label("online.title", systemImage: "person.2.slash")
        } description: {
            // Apple's own words for why, kept because this is the one case a
            // player cannot fix and a vague message would leave them trying.
            Text(reason.isEmpty ? String(localized: "online.unavailable") : reason)
        }
    }
}

private struct Failed: View {
    let reason: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("online.title", systemImage: "exclamationmark.triangle")
        } description: {
            Text(reason)
        } actions: {
            Button("online.retry", action: retry)
        }
    }
}

/// What is happening, in a sentence, with a way out where one makes sense.
private struct StartProgress: View {
    let messageKey: String
    let detail: String?
    let isCancellable: Bool
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ProgressView()
                Text(LocalizedStringKey(messageKey))
            }
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if isCancellable {
                Button("common.cancel", action: cancel)
                    .accessibilityIdentifier("online.cancel")
            }
        }
        .accessibilityIdentifier("online.progress")
        .accessibilityElement(children: .combine)
    }
}

/// A failure the player can read and act on. Never an error code.
private struct StartFailure: View {
    let failure: OnlineStartFailure
    let retry: (() -> Void)?
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(LocalizedStringKey(failure.messageKey))
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 16) {
                if let retry {
                    Button("online.retry", action: retry)
                        .accessibilityIdentifier("online.retry")
                }
                Button("common.back", action: dismiss)
                    .accessibilityIdentifier("online.dismissError")
            }
            .font(.callout)
        }
        .accessibilityIdentifier("online.failure")
    }
}

/// One of the two ways into a match, with its own explanation.
private struct StartChoice: View {
    let titleKey: LocalizedStringKey
    let detailKey: LocalizedStringKey
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey)
                Text(detailKey)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct Notice: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "info.circle")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
