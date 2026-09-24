import Foundation
import OSLog

/// What happened on the way into an online match, for reading off a device.
///
/// Keezly had no logging at all, which is why a P0 on real hardware presented
/// as "a spinner for two seconds and then nothing": every transition on the
/// start path was invisible from outside the process, and the one error that
/// explained it was discarded by its own `catch`.
///
/// This is deliberately narrow. It covers the path from the button to the
/// match and nothing else, because a log that covers everything is one nobody
/// reads.
///
/// **Nothing identifying is ever written.** Not an Apple ID, not a
/// `gamePlayerID`, not a display name, not match payload, not anybody's hand.
/// What goes in is the shape of what happened: which step, how many seats, how
/// many participants were filled, which error domain and code. That is what a
/// diagnosis needs, and it is all it needs — the count of filled participants
/// is what identified this defect, and it says nothing about who they were.
///
/// Read it from a connected device with:
///
///     log stream --device --predicate 'subsystem == "de.gcng.keezly"'
///
/// or afterwards, from the device's own store:
///
///     log collect --device --last 10m
enum OnlineLog {
    private static let log = Logger(subsystem: "de.gcng.keezly", category: "online")

    /// A step on the way into a match. Logged as it is *reached*, so a missing
    /// line is evidence: it says the path stopped before that point.
    enum Step: String {
        case startTapped = "start.tapped"
        case authenticationChecked = "auth.checked"
        case requestBuilt = "request.built"
        case matchmakerPresented = "matchmaker.presented"
        case matchmakerCancelled = "matchmaker.cancelled"
        case matchmakerFailed = "matchmaker.failed"
        case matchReceived = "match.received"
        case participantsResolved = "participants.resolved"
        case matchCreated = "match.created"
        case runOpened = "run.opened"
        case openRequested = "open.requested"
        case finished = "finished"
    }

    /// Also written to standard error, not only to `os_log`.
    ///
    /// Not redundancy for its own sake: on this toolchain the `log` command
    /// has no device mode at all, and `devicectl ... --console` bridges only
    /// the process's stdout/stderr. Without this line a diagnostic build tells
    /// a connected Mac nothing, which is how a P0 on real hardware went
    /// unexplained. `os_log` remains the one that survives into a sysdiagnose.
    private static func echo(_ line: String) {
        FileHandle.standardError.write(Data("[keezly.online] \(line)\n".utf8))
    }

    static func step(_ step: Step, _ detail: String = "") {
        if detail.isEmpty {
            log.notice("\(step.rawValue, privacy: .public)")
            echo(step.rawValue)
        } else {
            log.notice("\(step.rawValue, privacy: .public) \(detail, privacy: .public)")
            echo("\(step.rawValue) \(detail)")
        }
    }

    /// The table being asked for. Seat counts are not personal data.
    static func table(seats: Int, teams: Bool) {
        log.notice("table seats=\(seats, privacy: .public) teams=\(teams, privacy: .public)")
        echo("table seats=\(seats) teams=\(teams)")
    }

    /// How many of a match's participant slots have a real player in them.
    ///
    /// The number, never the players. This single count is what showed that
    /// `GKTurnBasedMatch.find` returns a match with unfilled slots, which is
    /// the whole defect.
    static func participants(filled: Int, of total: Int) {
        log.notice("participants filled=\(filled, privacy: .public) of=\(total, privacy: .public)")
        echo("participants filled=\(filled) of=\(total)")
    }

    /// An error, by its shape rather than its contents.
    ///
    /// `localizedDescription` can carry a player's name, so it is not logged.
    /// Domain and code are what identify a GameKit fault and neither is
    /// personal.
    static func failure(_ label: String, _ error: any Error) {
        let ns = error as NSError
        log.error("""
            \(label, privacy: .public) failed \
            domain=\(ns.domain, privacy: .public) \
            code=\(ns.code, privacy: .public) \
            type=\(String(describing: type(of: error)), privacy: .public)
            """)
        echo("\(label) FAILED domain=\(ns.domain) code=\(ns.code) type=\(type(of: error))")
    }

    /// One existing match, in the only terms worth logging about it.
    ///
    /// A value rather than eight loose parameters, because the shape of a
    /// match is a thing and naming it is cheaper than repeating it.
    struct MatchFacts: Sendable {
        let index: Int
        /// Apple's own opaque handle. Included because two otherwise identical
        /// rows cannot be told apart without it, and it says nothing about a
        /// person.
        let matchID: String
        let status: String
        let participants: Int
        let filled: Int
        let isMyTurn: Bool
        let created: Date
        let payloadBytes: Int
    }

    /// One line per existing match, for taking stock of what has accumulated.
    ///
    /// Used to inventory the orphaned matches the old start path left behind.
    /// Deliberately shape-only: how many participants, what status, how big the
    /// payload is. **No display names and no player identifiers** — who
    /// somebody played against is not a diagnostic.
    static func inventory(_ facts: MatchFacts) {
        let stamp = ISO8601DateFormatter().string(from: facts.created)
        let line = "inventory[\(facts.index)] id=\(facts.matchID) status=\(facts.status) "
            + "participants=\(facts.filled)/\(facts.participants) myTurn=\(facts.isMyTurn) "
            + "created=\(stamp) payload=\(facts.payloadBytes)B"
        log.notice("\(line, privacy: .public)")
        echo(line)
    }

    /// The board itself, by its checksum — the evidence that two devices hold
    /// the same position.
    ///
    /// `role` says how this device came by it: `dealt` for the one that
    /// created the opening position, `received` for one that took somebody
    /// else's. Exactly one device may ever log `dealt` for a given match; two
    /// would mean a double deal, and two different checksums at the same
    /// revision would mean the devices are playing different games.
    ///
    /// A checksum is a number over the position. It carries no cards, no
    /// names and nothing about a person.
    static func board(role: String, matchID: String, revision: Int, checksum: UInt64, seats: Int) {
        let line = "board \(role) match=\(matchID) revision=\(revision) "
            + "checksum=\(String(checksum, radix: 16)) seats=\(seats)"
        log.notice("\(line, privacy: .public)")
        echo(line)
    }

    /// Whether this device is genuinely playing somebody else.
    ///
    /// Derived, never identified: a turn-based match with every seat filled
    /// holds that many **distinct** Game Center accounts, because GameKit will
    /// not seat one account twice. So a full table is itself the confirmation,
    /// and no account identifier is read, logged or compared to get it.
    static func accounts(authenticated: Bool, filled: Int, of total: Int) {
        let confirmed = total >= 2 && filled == total
        let line = "accounts authenticated=\(authenticated) "
            + "differentAccountConfirmed=\(confirmed) (\(filled)/\(total) seats filled)"
        log.notice("\(line, privacy: .public)")
        echo(line)
    }

    /// Everything about a match request that could affect whether two
    /// devices find each other.
    ///
    /// Logged in full because "the requests must be identical" is not
    /// something to assert from reading the code — two devices have to be
    /// compared line by line. None of it identifies anybody: seat counts and
    /// matchmaking flags only.
    static func request(kind: String, description: String) {
        let line = "request kind=\(kind) \(description)"
        log.notice("\(line, privacy: .public)")
        echo(line)
    }

    /// Which match Game Center actually handed back.
    ///
    /// **The single most important line for automatch.** If two devices
    /// searching at the same time report different match ids, they were never
    /// matched with each other, and the problem is the request or the queue
    /// rather than anything that happens afterwards.
    static func matched(matchID: String, status: String, filled: Int, of total: Int, wasExisting: Bool) {
        let line = "matched id=\(matchID) status=\(status) seats=\(filled)/\(total) "
            + "existing=\(wasExisting)"
        log.notice("\(line, privacy: .public)")
        echo(line)
    }

    /// A path that gave up without an error — the silent exits that hide a
    /// defect, each one named so its absence from the log means something.
    static func gaveUp(_ reason: String) {
        log.error("gave up: \(reason, privacy: .public)")
        echo("GAVE UP: \(reason)")
    }
}
