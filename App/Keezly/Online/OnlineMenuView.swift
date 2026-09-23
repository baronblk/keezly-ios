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

    @State private var starting = false
    @State private var seats = 4
    @State private var teams = true

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
            .navigationTitle(Text("online.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.done") { dismiss() }
                }
            }
        }
        .task { await online.refresh() }
    }

    // MARK: - Signed in

    private var signedIn: some View {
        List {
            Section {
                Text("online.subtitle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                TableSeatsRow(seats: $seats, teams: $teams)
                Button {
                    start()
                } label: {
                    HStack {
                        Label("online.new", systemImage: "person.2.badge.plus")
                        Spacer()
                        if starting { ProgressView() }
                    }
                }
                .disabled(starting || online.isWorking)
                .accessibilityIdentifier("online.new")
            }

            Section {
                if online.matches.isEmpty {
                    Text("online.empty")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("online.empty")
                } else {
                    ForEach(online.matches) { match in
                        Button { open(match) } label: { MatchRow(match: match) }
                            .accessibilityIdentifier("online.match.\(match.id)")
                    }
                }
            }

            if let failure = online.failure {
                Section { Notice(text: failure) }
            }
        }
        .refreshable { await online.refresh() }
    }

    private func start() {
        starting = true
        Task {
            defer { starting = false }
            do {
                onOpen(try await online.startMatch(seats: seats, teams: teams))
            } catch {
                await online.refresh()
            }
        }
    }

    private func open(_ summary: OnlineMatchSummary) {
        Task {
            if let run = try? await online.open(summary.id) { onOpen(run) }
        }
    }
}

// MARK: - Pieces

private struct MatchRow: View {
    let match: OnlineMatchSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: match.isOver ? "flag.checkered" : (match.isMyTurn ? "play.circle.fill" : "hourglass"))
                .foregroundStyle(match.isMyTurn && !match.isOver ? Color.accentColor : .secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(match.opponents.isEmpty
                     ? String(localized: "online.seats \(match.seatCount)")
                     : match.opponents.formatted(.list(type: .and)))
                    .font(.body)
                Text(LocalizedStringKey(match.statusKey))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TableSeatsRow: View {
    @Binding var seats: Int
    @Binding var teams: Bool

    var body: some View {
        Picker(selection: $seats) {
            ForEach(TableConfiguration.seatCounts, id: \.self) { count in
                Text("online.seats \(count)").tag(count)
            }
        } label: {
            Text("table.seats")
        }
        .accessibilityIdentifier("online.seats")

        if seats % 2 == 0 {
            Toggle(isOn: $teams) { Text("table.sides.teams") }
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

private struct Notice: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "info.circle")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
