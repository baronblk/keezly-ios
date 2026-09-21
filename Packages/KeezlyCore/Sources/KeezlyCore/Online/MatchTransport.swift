import Foundation

/// Somewhere matches are kept between devices.
///
/// Deliberately small, and deliberately free of any Game Center type. That is
/// the whole boundary: `KeezlyCore` never imports GameKit, the GameKit adapter
/// lives in the app and conforms to this, and every rule about revisions,
/// duplicates and validation can therefore be tested against a mock with no
/// network, no account and no simulator (§28).
///
/// Every operation names its match. Nothing here assumes there is only one.
public protocol MatchTransport: Sendable {
    /// Stores a newly created match.
    ///
    /// `firstParticipant` is given rather than assumed. Keezen does not start
    /// with the dealer but with the player to their left (§12), so the first
    /// seat on turn is not the first participant — and only the engine knows
    /// which it is.
    func create(
        _ data: Data,
        matchID: String,
        participants: [String],
        firstParticipant: String
    ) async throws

    /// The match as this transport currently holds it.
    func load(matchID: String) async throws -> Data

    /// Hands the match on, with the turn passing to `nextParticipant`.
    ///
    /// The transport does not judge the move; it moves bytes. Whether a turn
    /// is legal, current or a repeat is decided by the engine on the device
    /// that receives it.
    func send(_ data: Data, matchID: String, nextParticipant: String) async throws

    /// Ends the match for everyone, with the final data.
    func end(_ data: Data, matchID: String) async throws

    /// The matches this participant is in.
    func matches(for participant: String) async throws -> [String]
}

/// Why a transport could not do something.
public enum MatchTransportError: Error, Hashable, Sendable, LocalizedError {
    case noSuchMatch(String)
    case alreadyExists(String)
    case notAParticipant(String)
    case matchEnded(String)
    case unavailable(reason: String)

    public var errorDescription: String? {
        switch self {
        case .noSuchMatch(let id): "There is no match \(id)."
        case .alreadyExists(let id): "Match \(id) already exists."
        case .notAParticipant(let id): "You are not in match \(id)."
        case .matchEnded(let id): "Match \(id) is over."
        case .unavailable(let reason): "Online play is unavailable (\(reason))."
        }
    }
}

/// A transport that keeps matches in memory.
///
/// Not a stub: it is the transport every online rule is tested against, and it
/// is deliberately unhelpful — it hands back exactly the bytes it was given
/// and takes no view on whose turn it is. Anything that only works because the
/// transport was kind would fail against Game Center.
public actor InMemoryTransport: MatchTransport {
    private struct Stored {
        var data: Data
        var participants: [String]
        var nextParticipant: String?
        var isOver: Bool
    }

    private var matches: [String: Stored] = [:]

    /// Every `send` that has happened, in order. Lets a test replay a
    /// callback, deliver one twice, or deliver them out of order.
    public private(set) var deliveries: [(matchID: String, data: Data)] = []

    public init() {}

    public func create(
        _ data: Data,
        matchID: String,
        participants: [String],
        firstParticipant: String
    ) async throws {
        guard matches[matchID] == nil else { throw MatchTransportError.alreadyExists(matchID) }
        guard participants.contains(firstParticipant) else {
            throw MatchTransportError.notAParticipant(matchID)
        }
        matches[matchID] = Stored(
            data: data,
            participants: participants,
            nextParticipant: firstParticipant,
            isOver: false
        )
    }

    public func load(matchID: String) async throws -> Data {
        guard let stored = matches[matchID] else { throw MatchTransportError.noSuchMatch(matchID) }
        return stored.data
    }

    public func send(_ data: Data, matchID: String, nextParticipant: String) async throws {
        guard var stored = matches[matchID] else { throw MatchTransportError.noSuchMatch(matchID) }
        guard !stored.isOver else { throw MatchTransportError.matchEnded(matchID) }
        guard stored.participants.contains(nextParticipant) else {
            throw MatchTransportError.notAParticipant(matchID)
        }
        stored.data = data
        stored.nextParticipant = nextParticipant
        matches[matchID] = stored
        deliveries.append((matchID: matchID, data: data))
    }

    public func end(_ data: Data, matchID: String) async throws {
        guard var stored = matches[matchID] else { throw MatchTransportError.noSuchMatch(matchID) }
        stored.data = data
        stored.isOver = true
        stored.nextParticipant = nil
        matches[matchID] = stored
        deliveries.append((matchID: matchID, data: data))
    }

    public func matches(for participant: String) async throws -> [String] {
        matches
            .filter { $0.value.participants.contains(participant) }
            .keys
            .sorted()
    }

    // MARK: - Things only a test needs

    public func participantOnTurn(in matchID: String) -> String? {
        matches[matchID]?.nextParticipant
    }

    public func isOver(_ matchID: String) -> Bool {
        matches[matchID]?.isOver ?? false
    }

    /// Replaces the stored bytes without going through `send`, so a test can
    /// study what happens when what arrives is not what was sent.
    public func corrupt(matchID: String, with data: Data) {
        matches[matchID]?.data = data
    }
}
