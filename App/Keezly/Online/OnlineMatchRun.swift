import Foundation
import KeezlyCore

/// One online match, while it is open.
///
/// Holds the board the player sees and the only path by which a move leaves
/// this device. Everything it knows about rules, revisions, duplicates and
/// stale turns comes from `OnlineMatchClient`; this adds the part that client
/// deliberately has no opinion about — what to put on screen (§28).
@MainActor
@Observable
final class OnlineMatchRun {
    /// The board, driven exactly as a local match's is. The other seats are
    /// `.remote`, which is what makes it read-only while somebody else plays.
    private(set) var session: MatchSession
    private(set) var match: OnlineMatch
    /// Set when something went wrong, in words a player can act on.
    private(set) var notice: String?
    private(set) var isSending = false

    let mySeat: Seat
    private let client: OnlineMatchClient
    private let me: String

    init(match: OnlineMatch, client: OnlineMatchClient, me: String) throws {
        guard let seat = match.participants.seat(of: me) else {
            throw MatchTransportError.notAParticipant(match.matchID)
        }
        self.match = match
        self.client = client
        self.me = me
        mySeat = seat
        session = MatchSession(online: match, mySeat: seat)
    }

    var matchID: String { match.matchID }
    var isMyTurn: Bool { match.participantOnTurn == me && match.state.result == nil }
    var isOver: Bool { match.state.result != nil }

    /// Whether this player won, once it is over.
    var didWin: Bool? {
        guard let result = match.state.result else { return nil }
        return result.winningSeats.contains(mySeat)
    }

    /// Takes the latest position from Game Center.
    ///
    /// Called when the screen appears and when the app comes back to the
    /// foreground, because a turn-based match changes while the app is closed
    /// — that is the whole shape of the thing (§27).
    func refresh() async {
        do {
            let latest = try await client.load(matchID: matchID)
            adopt(latest)
            notice = nil
        } catch {
            notice = OnlinePlay.readable(error)
        }
    }

    /// Plays a move and sends it on.
    ///
    /// The engine decides first, exactly as in a local match; only a move that
    /// actually changed the board is sent. A refusal is reported in the
    /// player's words rather than as an engine enum, and never as a raw
    /// `GKError` (§70).
    func submit(_ action: PlayerAction) async {
        guard isMyTurn, !isSending else { return }
        isSending = true
        defer { isSending = false }

        do {
            let (outcome, updated) = try await client.submit(
                action,
                matchID: matchID,
                expectedRevision: match.revision
            )
            adopt(updated)

            switch outcome {
            case .accepted:
                notice = nil

            case .duplicate:
                // Already counted — a re-delivered callback, not a second
                // move. The board is right, so saying nothing is right.
                notice = nil

            case .stale, .outOfOrder:
                // Two sides of one situation: this device and the match
                // disagree about the position. Neither is worth explaining to
                // a player, and both are fixed the same way — take what Game
                // Center has and show it.
                await refresh()
                notice = String(localized: "online.refused.stale")

            case .rejected(let reason):
                notice = Self.words(for: reason)
            }
        } catch {
            notice = OnlinePlay.readable(error)
        }
    }

    private func adopt(_ latest: OnlineMatch) {
        match = latest
        session.adopt(latest)
    }

    /// Why a turn was refused, in words rather than in engine terms.
    private static func words(for rejection: OnlineRejection) -> String {
        switch rejection {
        case .notYourSeat:
            String(localized: "online.refused.notYourTurn")
        case .notAParticipant:
            String(localized: "online.refused.notAParticipant")
        case .matchFinished:
            String(localized: "online.refused.over")
        case .illegal:
            // Deliberately not the engine's reason. The interface only offers
            // legal moves, so a player reaching this has hit a disagreement
            // between two devices, not a mistake of their own (§36).
            String(localized: "online.refused.illegal")
        }
    }
}
