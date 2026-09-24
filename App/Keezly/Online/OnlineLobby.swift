import Foundation

/// One online match, as **Keezly** describes it.
///
/// Built from what Game Center holds plus what the Keezly payload says, so the
/// list can be drawn without opening anything.
///
/// Deliberately not Apple's own description of a match. Game Center names an
/// automatch "Auto-Match-Game" and gives every one of them the same name, so a
/// player looking at their own matches sees eleven identical rows and no way to
/// tell which is which. That name is GameKit's, it cannot usefully be changed,
/// and it is not used here for anything.
struct OnlineMatchSummary: Identifiable, Hashable, Sendable {
    /// The Keezly match id, from inside the payload — never shown.
    let id: String
    let seatCount: Int
    /// Whoever else is at the table, by whatever name Game Center gives them.
    /// Empty while automatch is still looking.
    let opponents: [String]
    /// How many seats have somebody in them.
    let filledSeats: Int
    let isMyTurn: Bool
    let isOver: Bool
    /// Waiting on Game Center to find somebody, rather than on a player.
    let isWaitingForPlayers: Bool
    /// An invitation this player has not answered yet.
    let isInvitation: Bool
    let lastActivity: Date
    /// The rule preset, when the payload carries one.
    let variantName: String?
    let isTeamMatch: Bool

    /// What this match is called **in Keezly**, built rather than taken.
    ///
    /// The people at the table if they are known, because that is what anybody
    /// actually remembers a game by; the table size if they are not.
    var title: String {
        if !opponents.isEmpty {
            return opponents.formatted(.list(type: .and))
        }
        if isWaitingForPlayers {
            return String(localized: "online.lobby.searching")
        }
        return String(localized: "online.seats \(seatCount)")
    }

    /// The second line: the table, and the rules if they are known.
    var subtitle: String {
        var parts = [String(localized: "online.seats \(seatCount)")]
        if isTeamMatch {
            parts.append(String(localized: "table.sides.teams"))
        }
        if let variantName {
            parts.append(variantName)
        }
        return parts.joined(separator: " · ")
    }

    /// Which group this belongs in.
    var group: OnlineLobby.Group {
        if isInvitation { return .invitations }
        if isOver { return .finished }
        if isWaitingForPlayers { return .waitingForPlayers }
        return isMyTurn ? .yourTurn : .theirTurn
    }
}

/// How Keezly arranges its own online matches.
///
/// A pure function of the summaries, so every arrangement below is testable
/// without GameKit, an account, a network or a second player.
enum OnlineLobby {

    /// The groups, in the order they are shown. The order is the point: what
    /// is waiting on *you* comes first, and what is over comes last and stays
    /// out of the way.
    enum Group: Int, CaseIterable, Hashable, Sendable {
        case invitations
        case yourTurn
        case theirTurn
        case waitingForPlayers
        case finished

        var titleKey: String {
            switch self {
            case .invitations: "online.lobby.invitations"
            case .yourTurn: "online.lobby.yourTurn"
            case .theirTurn: "online.lobby.theirTurn"
            case .waitingForPlayers: "online.lobby.waiting"
            case .finished: "online.lobby.finished"
            }
        }

        /// Whether the group is shown when it has nothing in it.
        ///
        /// None of them are. An empty "Finished" heading is furniture, and a
        /// screen made of empty headings is what a debug list looks like.
        var showsWhenEmpty: Bool { false }
    }

    struct Section: Identifiable, Hashable, Sendable {
        let group: Group
        let matches: [OnlineMatchSummary]
        var id: Group { group }
    }

    /// Groups and orders the matches for display.
    ///
    /// Within a group, most recently active first — a player coming back after
    /// a day wants the game they were just playing, not the oldest one.
    /// Finished matches sort the same way but sit at the bottom, because an
    /// old finished game must never push a live one off the screen.
    static func sections(for matches: [OnlineMatchSummary]) -> [Section] {
        Group.allCases.compactMap { group in
            let inGroup = matches
                .filter { $0.group == group }
                .sorted { $0.lastActivity > $1.lastActivity }
            guard !inGroup.isEmpty || group.showsWhenEmpty else { return nil }
            return Section(group: group, matches: inGroup)
        }
    }

    /// How many matches are waiting on this player right now.
    ///
    /// What a badge would show, and what the home screen says out loud so
    /// nobody has to count rows.
    static func waitingOnYou(in matches: [OnlineMatchSummary]) -> Int {
        matches.filter { $0.group == .yourTurn || $0.group == .invitations }.count
    }

    /// Whether there is anything at all worth drawing a list for.
    static func isEmpty(_ matches: [OnlineMatchSummary]) -> Bool {
        matches.allSatisfy { $0.group == .finished } && matches.isEmpty
    }

    /// Matches that are over and have been for a while.
    ///
    /// Not deleted and not hidden — Keezly does not delete somebody's matches
    /// — but kept out of the way of the ones still being played.
    static func finished(in matches: [OnlineMatchSummary]) -> [OnlineMatchSummary] {
        matches.filter { $0.isOver }.sorted { $0.lastActivity > $1.lastActivity }
    }
}
