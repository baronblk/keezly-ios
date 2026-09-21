import Foundation

/// Which player holds which seat, stated once and never inferred.
///
/// Game Center hands back participants in an order of its own, and callbacks
/// arrive in whatever order the network produces. Treating either as the seat
/// number is the classic way an online board game ends up moving the wrong
/// player's pieces — so the mapping is written down when the match is created,
/// travels with it, and cannot change afterwards (§28).
///
/// The identifiers are opaque strings. `KeezlyCore` neither knows nor cares
/// that they come from GameKit; that keeps the engine free of any dependency
/// on it, and lets the whole online path be tested without one.
public struct ParticipantMapping: Hashable, Sendable, Codable {
    /// Participant identifiers, indexed by seat.
    public let seatOrder: [String]

    public init(seatOrder: [String]) throws {
        guard !seatOrder.isEmpty else {
            throw ParticipantMappingError.empty
        }
        guard !seatOrder.contains(where: \.isEmpty) else {
            throw ParticipantMappingError.emptyIdentifier
        }
        guard Set(seatOrder).count == seatOrder.count else {
            throw ParticipantMappingError.duplicateParticipant
        }
        self.seatOrder = seatOrder
    }

    public var seatCount: Int { seatOrder.count }

    public func participant(at seat: Seat) -> String? {
        seatOrder.indices.contains(seat.index) ? seatOrder[seat.index] : nil
    }

    public func seat(of participant: String) -> Seat? {
        seatOrder.firstIndex(of: participant).map(Seat.init)
    }

    public func contains(_ participant: String) -> Bool {
        seatOrder.contains(participant)
    }

    /// Checks the mapping describes this table.
    ///
    /// A mapping with the wrong number of seats is not a smaller table — it is
    /// a mapping for a different match, and playing it would put pieces in the
    /// wrong hands.
    public func validated(against configuration: GameConfiguration) throws -> ParticipantMapping {
        guard seatCount == configuration.seatCount else {
            throw ParticipantMappingError.seatCountMismatch(
                seats: configuration.seatCount,
                participants: seatCount
            )
        }
        return self
    }
}

public enum ParticipantMappingError: Error, Hashable, Sendable, LocalizedError {
    case empty
    case emptyIdentifier
    case duplicateParticipant
    case seatCountMismatch(seats: Int, participants: Int)

    public var errorDescription: String? {
        switch self {
        case .empty:
            "The match has no players."
        case .emptyIdentifier:
            "One of the players has no identifier."
        case .duplicateParticipant:
            "The same player was given two seats."
        case .seatCountMismatch(let seats, let participants):
            "The match has \(seats) seats but \(participants) players."
        }
    }
}
