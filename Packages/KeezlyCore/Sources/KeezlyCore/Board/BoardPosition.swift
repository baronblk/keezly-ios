import Foundation

/// Every place a pawn can legally be. Purely topological — the engine never
/// knows about pixels, angles or layout (§9).
public enum BoardPosition: Hashable, Sendable, Codable {
    /// Parking area ("wachtrij"). `slot` is 0...3 and carries no rule meaning;
    /// it exists so the UI can keep pawns visually stable.
    case waiting(seat: Seat, slot: Int)

    /// A square on the shared main track, indexed 0..<mainTrackCount clockwise.
    case track(index: Int)

    /// One of the four private home squares ("thuishonk").
    /// `slot` 0 is the square closest to the entry, 3 is the deepest.
    case home(seat: Seat, slot: Int)

    public var isWaiting: Bool { if case .waiting = self { return true }; return false }
    public var isTrack: Bool { if case .track = self { return true }; return false }
    public var isHome: Bool { if case .home = self { return true }; return false }

    /// The track index, or `nil` when the pawn is not on the shared track.
    public var trackIndex: Int? {
        if case .track(let index) = self { return index }
        return nil
    }

    /// The seat owning this private area, or `nil` for shared track squares.
    public var owningSeat: Seat? {
        switch self {
        case .waiting(let seat, _), .home(let seat, _): return seat
        case .track: return nil
        }
    }
}

/// Where a pawn stands, together with the bookkeeping the rules need.
public struct PawnState: Hashable, Sendable, Codable {
    public let id: PawnID
    public var position: BoardPosition

    public init(id: PawnID, position: BoardPosition) {
        self.id = id
        self.position = position
    }

    public var isHome: Bool { position.isHome }
    public var isWaiting: Bool { position.isWaiting }
}
