import Foundation

/// A seat at the table, numbered clockwise starting at 0.
///
/// Seats are the engine's only notion of "who": display names, Game Center
/// participants and AI agents are all mapped onto seats by higher layers.
public struct Seat: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let index: Int

    public init(_ index: Int) {
        self.index = index
    }

    public static func < (lhs: Seat, rhs: Seat) -> Bool { lhs.index < rhs.index }
    public var description: String { "seat\(index)" }
}

/// Identifies one of the four pawns belonging to a seat.
public struct PawnID: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let seat: Seat
    /// 0...3 within the owning seat.
    public let slot: Int

    public init(seat: Seat, slot: Int) {
        self.seat = seat
        self.slot = slot
    }

    public static func < (lhs: PawnID, rhs: PawnID) -> Bool {
        (lhs.seat.index, lhs.slot) < (rhs.seat.index, rhs.slot)
    }

    public var description: String { "p\(seat.index).\(slot)" }
}

/// A team of one or more seats. In free-for-all every seat is its own team.
public struct TeamID: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let index: Int

    public init(_ index: Int) {
        self.index = index
    }

    public static func < (lhs: TeamID, rhs: TeamID) -> Bool { lhs.index < rhs.index }
    public var description: String { "team\(index)" }
}

/// Number of pawns every seat owns. Fixed by the rules of Keezen (§6).
public let pawnsPerSeat = 4
