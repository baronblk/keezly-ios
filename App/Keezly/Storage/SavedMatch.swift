import Foundation
import KeezlyCore

/// Who holds a seat, in a form that survives being written down.
///
/// A mirror of `SeatRole` rather than `SeatRole` itself: the stored form is a
/// contract with the file on disk, and it must not change quietly every time
/// the in-memory type does.
enum PersistedRole: Hashable, Sendable, Codable {
    case person
    case computer(strength: String)

    init(_ role: SeatRole) {
        switch role {
        case .human: self = .person
        case .computer(let difficulty): self = .computer(strength: difficulty.rawValue)
        }
    }

    /// The role this describes, or `nil` if the file names a strength this
    /// build does not have. Refused rather than guessed: quietly substituting
    /// a different opponent would change the game.
    var role: SeatRole? {
        switch self {
        case .person: .human
        case .computer(let strength): AIDifficulty(rawValue: strength).map(SeatRole.computer)
        }
    }
}

/// Enough about a match to list it without replaying it.
///
/// Every field is taken from the validated state at the moment of writing, so
/// the list can never describe a position the record does not produce.
struct MatchSummary: Hashable, Sendable, Codable {
    let matchID: String
    let createdAt: Int
    let updatedAt: Int
    let seatCount: Int
    let teamMode: TeamMode
    let status: MatchStatus
    /// Who sits where, so the list can say "you and two others" without
    /// opening the match.
    let roles: [PersistedRole]
    /// Whose turn it is.
    let currentSeat: Int
    /// Which deal of the round the match is in, counted from one.
    let round: Int
    let actionCount: Int
    let revision: Int
    /// Who won, when the match is over; empty otherwise.
    ///
    /// Written from the validated state at save time, so the history list can
    /// say who won without replaying every match to find out.
    let winningSeats: [Int]

    var isPassAndPlay: Bool { roles.count(where: { $0 == .person }) > 1 }
    var peopleCount: Int { roles.count(where: { $0 == .person }) }

    init(record: MatchRecord, state: GameState, roles: [SeatRole]) {
        matchID = record.matchID
        createdAt = record.createdAt
        updatedAt = record.updatedAt
        seatCount = state.configuration.seatCount
        teamMode = state.configuration.teamMode
        status = record.status
        self.roles = roles.map(PersistedRole.init)
        currentSeat = state.currentSeat.index
        round = state.deal.roundIndex + 1
        actionCount = record.actionCount
        revision = state.revision
        winningSeats = state.result?.winningSeats.map(\.index) ?? []
    }

    /// Decoded leniently in one place only.
    ///
    /// `winningSeats` arrived after the first matches were saved. A file
    /// written before it exists is not damaged and must still open, so the
    /// field defaults to empty rather than failing the decode — and an old
    /// completed match simply says "finished" instead of who won, which is
    /// true of what was written down.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        matchID = try container.decode(String.self, forKey: .matchID)
        createdAt = try container.decode(Int.self, forKey: .createdAt)
        updatedAt = try container.decode(Int.self, forKey: .updatedAt)
        seatCount = try container.decode(Int.self, forKey: .seatCount)
        teamMode = try container.decode(TeamMode.self, forKey: .teamMode)
        status = try container.decode(MatchStatus.self, forKey: .status)
        roles = try container.decode([PersistedRole].self, forKey: .roles)
        currentSeat = try container.decode(Int.self, forKey: .currentSeat)
        round = try container.decode(Int.self, forKey: .round)
        actionCount = try container.decode(Int.self, forKey: .actionCount)
        revision = try container.decode(Int.self, forKey: .revision)
        winningSeats = try container.decodeIfPresent([Int].self, forKey: .winningSeats) ?? []
    }

    /// Built field by field. Used by tests to describe a table without
    /// playing one out, and by nothing in the app.
    init(
        matchID: String,
        createdAt: Int,
        updatedAt: Int,
        seatCount: Int,
        teamMode: TeamMode,
        status: MatchStatus,
        roles: [PersistedRole],
        currentSeat: Int,
        round: Int,
        actionCount: Int,
        revision: Int,
        winningSeats: [Int]
    ) {
        self.matchID = matchID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.seatCount = seatCount
        self.teamMode = teamMode
        self.status = status
        self.roles = roles
        self.currentSeat = currentSeat
        self.round = round
        self.actionCount = actionCount
        self.revision = revision
        self.winningSeats = winningSeats
    }

    /// The winner, for a table where one seat wins. `nil` when the match is
    /// unfinished, or was saved before winners were recorded.
    var winningSeat: Int? { winningSeats.first }

    /// Whether the person holding the device — seat 0 — won.
    var didLocalSeatWin: Bool { winningSeats.contains(0) }
}

/// One saved match, as it sits on disk.
///
/// The game itself is the core's own envelope, kept as its bytes so that the
/// core's checks — schema, rules, checksum, replay — run exactly as they do
/// anywhere else. Around it sits only what the *device* knows: who was playing
/// and enough to list the match.
struct SavedMatchEnvelope: Hashable, Sendable, Codable {
    /// The app-level format version. Separate from the engine's: the layout of
    /// this wrapper can change without the rules having changed.
    static let currentSchema = 1

    let schemaVersion: Int
    let summary: MatchSummary
    /// A `MatchRecordEnvelope`, encoded. Held as bytes so it is validated by
    /// the engine rather than by this wrapper.
    let record: Data
    /// Covers the summary and the record together, so neither can be swapped
    /// for another match's.
    let checksum: UInt64

    init(summary: MatchSummary, record: Data) throws {
        schemaVersion = Self.currentSchema
        self.summary = summary
        self.record = record
        checksum = try Self.checksum(summary: summary, record: record)
    }

    private static func checksum(summary: MatchSummary, record: Data) throws -> UInt64 {
        var bytes = try GameStateCoding.makeEncoder().encode(summary)
        bytes.append(record)
        return Checksum.fnv1a(bytes)
    }

    func verified() throws -> SavedMatchEnvelope {
        guard schemaVersion <= Self.currentSchema else {
            throw MatchStoreError.unsupportedSchema(found: schemaVersion, supported: Self.currentSchema)
        }
        let actual = try Self.checksum(summary: summary, record: record)
        guard actual == checksum else {
            throw MatchStoreError.damaged(expected: checksum, actual: actual)
        }
        return self
    }
}

/// A match rebuilt from disk, with everything needed to carry on playing it.
struct RestoredMatch: Sendable {
    let record: MatchRecord
    let state: GameState
    let roles: [SeatRole]
    let summary: MatchSummary
}

/// Why a saved match could not be opened.
///
/// Distinct from `MatchRestoreError`, which is the engine's verdict on the
/// game itself. These are the wrapper's: the file, its version, its integrity,
/// and whether this build still has the opponents it names.
enum MatchStoreError: Error, Hashable, Sendable, LocalizedError {
    case unreadable(reason: String)
    case unsupportedSchema(found: Int, supported: Int)
    case damaged(expected: UInt64, actual: UInt64)
    case unknownOpponent(strength: String)
    case seatCountMismatch(seats: Int, roles: Int)
    case engineRefused(MatchRestoreError)

    var errorDescription: String? {
        switch self {
        case .unreadable(let reason):
            "The saved match could not be read (\(reason))."
        case .unsupportedSchema(let found, let supported):
            "The saved match was written by a newer version of Keezly (\(found) against \(supported))."
        case .damaged:
            "The saved match is damaged."
        case .unknownOpponent(let strength):
            "The saved match uses an opponent this version does not have (\(strength))."
        case .seatCountMismatch(let seats, let roles):
            "The saved match has \(seats) seats but \(roles) players."
        case .engineRefused(let error):
            error.errorDescription
        }
    }
}
