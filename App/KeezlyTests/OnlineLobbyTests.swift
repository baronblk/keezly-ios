import Foundation
@testable import Keezly
import Testing

/// Keezly's own online lobby.
///
/// This exists because the online area was, for a while, Apple's raw
/// `GKTurnBasedMatchmakerViewController` list presented as the whole
/// experience: eleven rows all called "Auto-Match-Game", all saying "Dein Zug",
/// with a `+` and an `i` and no way to tell one from another. Technically it
/// worked. As an interface it was indistinguishable from a debug screen.
///
/// Everything here is a pure function of the summaries, so every arrangement is
/// checked without GameKit, an account, a network or a second player.
@Suite("Online lobby")
struct OnlineLobbyTests {

    private func summary(
        id: String = "m",
        seats: Int = 4,
        opponents: [String] = ["Anna", "Max"],
        filled: Int = 4,
        myTurn: Bool = false,
        over: Bool = false,
        waiting: Bool = false,
        invitation: Bool = false,
        ago: TimeInterval = 0,
        variant: String? = nil,
        teams: Bool = false
    ) -> OnlineMatchSummary {
        OnlineMatchSummary(
            id: id,
            seatCount: seats,
            opponents: opponents,
            filledSeats: filled,
            isMyTurn: myTurn,
            isOver: over,
            isWaitingForPlayers: waiting,
            isInvitation: invitation,
            lastActivity: Date(timeIntervalSince1970: 1_000_000 - ago),
            variantName: variant,
            isTeamMatch: teams
        )
    }

    // MARK: - Nothing at all

    @Test("no matches produces no sections, not a page of empty headings")
    func noMatches() {
        #expect(OnlineLobby.sections(for: []).isEmpty)
        #expect(OnlineLobby.waitingOnYou(in: []) == 0)
    }

    @Test("a group with nothing in it is not drawn")
    func emptyGroupsAreNotDrawn() {
        let sections = OnlineLobby.sections(for: [summary(myTurn: true)])
        #expect(sections.count == 1)
        #expect(sections.first?.group == .yourTurn)
    }

    // MARK: - One match, and many

    @Test("one match lands in the group its state says")
    func oneMatch() {
        #expect(OnlineLobby.sections(for: [summary(myTurn: true)]).first?.group == .yourTurn)
        #expect(OnlineLobby.sections(for: [summary(myTurn: false)]).first?.group == .theirTurn)
        #expect(OnlineLobby.sections(for: [summary(over: true)]).first?.group == .finished)
        #expect(OnlineLobby.sections(for: [summary(waiting: true)]).first?.group == .waitingForPlayers)
        #expect(OnlineLobby.sections(for: [summary(invitation: true)]).first?.group == .invitations)
    }

    /// The screenshot that started this: eleven matches, every one of them
    /// yours to play, and nothing to tell them apart.
    @Test("eleven matches are grouped rather than listed flat")
    func manyMatches() {
        let matches = (0..<11).map { index in
            summary(id: "m\(index)", myTurn: index < 6, over: index >= 9, ago: TimeInterval(index * 60))
        }
        let sections = OnlineLobby.sections(for: matches)

        #expect(sections.map(\.group) == [.yourTurn, .theirTurn, .finished])
        #expect(sections.first { $0.group == .yourTurn }?.matches.count == 6)
        #expect(sections.first { $0.group == .finished }?.matches.count == 2)
        #expect(OnlineLobby.waitingOnYou(in: matches) == 6)
    }

    // MARK: - Order

    /// What is waiting on the player comes first. A finished match from last
    /// week must never push a live one off the screen.
    @Test("what needs you comes first, what is over comes last")
    func groupOrder() {
        let matches = [
            summary(id: "over", over: true),
            summary(id: "theirs", myTurn: false),
            summary(id: "invite", invitation: true),
            summary(id: "waiting", waiting: true),
            summary(id: "mine", myTurn: true),
        ]
        #expect(OnlineLobby.sections(for: matches).map(\.group)
                == [.invitations, .yourTurn, .theirTurn, .waitingForPlayers, .finished])
    }

    @Test("inside a group, the most recent is first")
    func recentFirst() {
        let matches = [
            summary(id: "old", myTurn: true, ago: 9_000),
            summary(id: "new", myTurn: true, ago: 10),
            summary(id: "middle", myTurn: true, ago: 500),
        ]
        let ids = OnlineLobby.sections(for: matches).first?.matches.map(\.id)
        #expect(ids == ["new", "middle", "old"])
    }

    // MARK: - What a row says

    /// Never "Auto-Match-Game". That is GameKit's name for every automatch it
    /// creates, it is the same for all of them, and it tells a player nothing.
    @Test("a match is named by who is at the table")
    func titleIsThePeople() {
        #expect(summary(opponents: ["Anna", "Max"]).title.contains("Anna"))
        #expect(summary(opponents: ["Anna", "Max"]).title.contains("Max"))
    }

    @Test("a match still being matched says so instead of naming nobody")
    func titleWhileSearching() {
        let title = summary(opponents: [], waiting: true).title
        #expect(!title.isEmpty)
        #expect(title != "Auto-Match-Game")
    }

    @Test("a match with nobody named falls back to the table size, not an id")
    func titleFallsBackToTheTable() {
        let match = summary(id: "8A7C-DEAD-BEEF", seats: 3, opponents: [])
        #expect(!match.title.contains("8A7C"), "an internal id reached the interface")
        #expect(match.title.contains("3"))
    }

    @Test("no row ever shows the Keezly match id")
    func noInternalIdsAnywhere() {
        let match = summary(id: "8A7C-DEAD-BEEF", opponents: [], waiting: true)
        #expect(!match.title.contains("8A7C"))
        #expect(!match.subtitle.contains("8A7C"))
    }

    @Test("the subtitle carries the table and the rules when they are known")
    func subtitleCarriesTheTable() {
        let match = summary(seats: 6, variant: "Keezly Classic", teams: true)
        #expect(match.subtitle.contains("6"))
        #expect(match.subtitle.contains("Keezly Classic"))
    }

    @Test("a subtitle with no variant does not leave a dangling separator")
    func subtitleWithoutVariant() {
        let subtitle = summary(seats: 2, variant: nil, teams: false).subtitle
        #expect(!subtitle.hasSuffix("·"))
        #expect(!subtitle.contains("··"))
    }

    // MARK: - The states the owner listed

    @Test("an invitation outranks whose turn it is")
    func invitationWins() {
        // An unanswered invitation is not a turn, whatever GameKit says about
        // whose move it is: the player has not joined yet.
        #expect(summary(myTurn: true, invitation: true).group == .invitations)
    }

    @Test("a finished match is never shown as needing a turn")
    func finishedIsNeverYourTurn() {
        #expect(summary(myTurn: true, over: true).group == .finished)
        #expect(OnlineLobby.waitingOnYou(in: [summary(myTurn: true, over: true)]) == 0)
    }

    @Test("finished matches are kept apart from live ones")
    func finishedAreSeparate() {
        let matches = [summary(id: "a", myTurn: true), summary(id: "b", over: true)]
        let sections = OnlineLobby.sections(for: matches)
        let live = sections.first { $0.group == .yourTurn }?.matches ?? []
        #expect(live.allSatisfy { !$0.isOver }, "a finished match was mixed in with live ones")
        #expect(OnlineLobby.finished(in: matches).map(\.id) == ["b"])
    }

    @Test("waiting for players is its own thing, not somebody else's turn")
    func waitingIsNotTheirTurn() {
        // These are the matches automatch created and has not filled. Calling
        // them "waiting for Anna" when there is no Anna would be a lie.
        #expect(summary(opponents: [], filled: 1, waiting: true).group == .waitingForPlayers)
    }

    @Test("the count waiting on you counts turns and invitations, nothing else")
    func waitingOnYouCount() {
        let matches = [
            summary(id: "1", myTurn: true),
            summary(id: "2", invitation: true),
            summary(id: "3", myTurn: false),
            summary(id: "4", over: true),
            summary(id: "5", waiting: true),
        ]
        #expect(OnlineLobby.waitingOnYou(in: matches) == 2)
    }
}
