import Foundation

/// The parametric Keezen board for 2...6 seats (§9).
///
/// There are no hard-coded per-player-count boards. The board is generated
/// from a single rule: every seat contributes one 16-square segment to the
/// shared main track, so a 4-player board has the classic 64 track squares
/// plus 4×4 waiting and 4×4 home squares — 96 positions in total.
///
/// Geometry is intentionally absent. `BoardGraph` answers questions like
/// "which square is 7 steps ahead of this pawn" and "which squares does that
/// cross"; turning those answers into coordinates is the UI's job.
public struct BoardGraph: Hashable, Sendable, Codable {
    /// Track squares contributed by each seat. Fixed by the classic layout.
    public static let squaresPerSeatSegment = 16

    public let seatCount: Int
    public let mainTrackCount: Int

    public init(seatCount: Int) {
        precondition((2...6).contains(seatCount), "Keezly supports 2...6 seats")
        self.seatCount = seatCount
        self.mainTrackCount = seatCount * Self.squaresPerSeatSegment
    }

    public var seats: [Seat] { (0..<seatCount).map(Seat.init) }

    /// Total number of distinct positions on this board.
    public var positionCount: Int {
        mainTrackCount + seatCount * pawnsPerSeat * 2
    }

    // MARK: - Per-seat anchors

    /// The protected start square where pawns enter the track (§15).
    public func startIndex(for seat: Seat) -> Int {
        seat.index * Self.squaresPerSeatSegment
    }

    /// The last track square a pawn of `seat` visits before turning into its
    /// home lane: exactly one square "behind" its own start.
    ///
    /// This is what makes every seat's journey identical in length, which the
    /// board tests assert (§9: "kein Spieler wird geometrisch benachteiligt").
    public func homeEntryIndex(for seat: Seat) -> Int {
        (startIndex(for: seat) + mainTrackCount - 1) % mainTrackCount
    }

    /// Number of forward steps from a seat's start square to its home entry
    /// square. Identical for every seat by construction.
    public var lapLength: Int { mainTrackCount - 1 }

    /// Total forward steps from the start square into the deepest home square.
    public var fullJourneyLength: Int { lapLength + pawnsPerSeat }

    // MARK: - Progress

    /// How far along its own lap a pawn of `seat` stands on `trackIndex`.
    ///
    /// 0 means "on my start square", `lapLength` means "on my home entry
    /// square". Progress is the coordinate all forward movement is expressed
    /// in, because it is the only one that is seat-relative.
    public func progress(ofTrackIndex trackIndex: Int, for seat: Seat) -> Int {
        (trackIndex - startIndex(for: seat) + mainTrackCount) % mainTrackCount
    }

    /// Inverse of `progress(ofTrackIndex:for:)`.
    public func trackIndex(atProgress progress: Int, for seat: Seat) -> Int {
        (startIndex(for: seat) + progress) % mainTrackCount
    }

    /// The seat-relative progress of any position a pawn can move forward
    /// from, or `nil` for waiting pawns (which cannot advance at all).
    ///
    /// Home squares continue the same scale: home slot 0 sits one step past
    /// the home entry square.
    public func progress(of position: BoardPosition, for seat: Seat) -> Int? {
        switch position {
        case .waiting:
            return nil
        case .track(let index):
            return progress(ofTrackIndex: index, for: seat)
        case .home(let homeSeat, let slot):
            guard homeSeat == seat else { return nil }
            return lapLength + 1 + slot
        }
    }

    /// The position a pawn of `seat` reaches at a given progress value, or
    /// `nil` when that progress overshoots the deepest home square.
    public func position(atProgress progress: Int, for seat: Seat) -> BoardPosition? {
        guard progress >= 0 else { return nil }
        if progress <= lapLength {
            return .track(index: trackIndex(atProgress: progress, for: seat))
        }
        let homeSlot = progress - lapLength - 1
        guard homeSlot < pawnsPerSeat else { return nil }
        return .home(seat: seat, slot: homeSlot)
    }

    // MARK: - Paths

    /// Every position a pawn of `seat` passes through moving `steps` forward,
    /// excluding the origin and including the destination.
    ///
    /// Returns `nil` when the move overshoots the home lane — the engine needs
    /// exact counts into home (§16), so overshooting is not a legal move that
    /// happens to be blocked, it is simply not a move.
    public func forwardPath(from position: BoardPosition, steps: Int, for seat: Seat) -> [BoardPosition]? {
        precondition(steps > 0, "forwardPath requires a positive step count")
        guard let start = progress(of: position, for: seat) else { return nil }
        guard start + steps <= fullJourneyLength else { return nil }
        return (1...steps).compactMap { self.position(atProgress: start + $0, for: seat) }
    }

    /// Every track square a pawn passes moving `steps` backward, excluding the
    /// origin and including the destination.
    ///
    /// Backward movement is expressed in raw track indices rather than
    /// progress, because a pawn moving back past its own start square simply
    /// wraps onto the shared track — it does not re-enter its home lane (§11).
    /// Pawns in the waiting area or in home cannot move backward at all.
    public func backwardPath(from position: BoardPosition, steps: Int) -> [BoardPosition]? {
        precondition(steps > 0, "backwardPath requires a positive step count")
        guard let index = position.trackIndex else { return nil }
        return (1...steps).map {
            .track(index: (index - $0 + mainTrackCount * steps) % mainTrackCount)
        }
    }
}
