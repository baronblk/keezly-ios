import Foundation
import KeezlyCore

/// What the keyboard is currently on.
///
/// A separate idea from *selection*: selection is what the player has chosen
/// and the engine will act on, focus is only where the keyboard is pointing.
/// A pointer user never sees focus; a keyboard user has nothing else (§46).
enum PlayFocus: Hashable {
    /// The screen itself. Holds focus before the player has moved it anywhere,
    /// so that the very first key press arrives at all — without it, a fresh
    /// board swallows every arrow key. Never shows a ring, and never appears
    /// in the ring.
    case screen
    case fold
    case card(Card)
    case pawn(PawnID)
    case target(BoardPosition)
}

/// A stable order for walking the board with a keyboard.
///
/// Board positions have no natural order — the engine never needs one — so
/// traversal defines its own: round the track first, then home, then the
/// waiting area, which is also the order a player would read the board in.
extension BoardPosition {
    /// Where a square falls in keyboard traversal.
    struct FocusOrder: Comparable {
        let band: Int
        let major: Int
        let minor: Int

        static func < (lhs: Self, rhs: Self) -> Bool {
            (lhs.band, lhs.major, lhs.minor) < (rhs.band, rhs.major, rhs.minor)
        }
    }

    var focusOrder: FocusOrder {
        switch self {
        case .track(let index): FocusOrder(band: 0, major: index, minor: 0)
        case .home(let seat, let slot): FocusOrder(band: 1, major: seat.index, minor: slot)
        case .waiting(let seat, let slot): FocusOrder(band: 2, major: seat.index, minor: slot)
        }
    }

    static func focusPrecedes(_ lhs: BoardPosition, _ rhs: BoardPosition) -> Bool {
        lhs.focusOrder < rhs.focusOrder
    }
}

/// Everything the keyboard can reach right now, grouped the way the screen is.
///
/// Built fresh from the session on every render, exactly as `PlayPlanner` is,
/// so focus can never offer something the engine would refuse.
struct FocusRing: Equatable {
    /// The bands the keyboard moves between. Left and right move along a band;
    /// up and down move between them.
    enum Group: Int, CaseIterable, Comparable {
        case fold
        case hand
        case pawns
        case targets

        static func < (lhs: Group, rhs: Group) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Non-empty groups, in screen order.
    private(set) var bands: [(group: Group, items: [PlayFocus])] = []

    static func == (lhs: FocusRing, rhs: FocusRing) -> Bool {
        lhs.bands.count == rhs.bands.count
            && zip(lhs.bands, rhs.bands).allSatisfy { $0.group == $1.group && $0.items == $1.items }
    }

    /// Everything reachable, in order.
    var items: [PlayFocus] { bands.flatMap(\.items) }

    var isEmpty: Bool { bands.isEmpty }

    /// Builds the ring from the same facts the planner works from.
    ///
    /// Only *playable* cards are included. Offering the keyboard a card the
    /// engine will not accept would be a dead end a mouse user never meets,
    /// and the keyboard must not be the worse way to play (§46).
    init(
        mustFold: Bool,
        hand: [Card] = [],
        playable: Set<Card> = [],
        selectablePawns: Set<PawnID> = [],
        targets: Set<BoardPosition> = []
    ) {
        if mustFold {
            bands = [(.fold, [.fold])]
            return
        }

        let cards = hand.filter(playable.contains).map(PlayFocus.card)
        let pawns = selectablePawns
            .sorted { ($0.seat.index, $0.slot) < ($1.seat.index, $1.slot) }
            .map(PlayFocus.pawn)
        let squares = targets
            .sorted(by: BoardPosition.focusPrecedes)
            .map(PlayFocus.target)

        let candidates: [(group: Group, items: [PlayFocus])] = [
            (group: .hand, items: cards),
            (group: .pawns, items: pawns),
            (group: .targets, items: squares),
        ]
        bands = candidates.filter { !$0.items.isEmpty }
    }

    // MARK: - Movement

    func group(of focus: PlayFocus) -> Group? {
        bands.first { $0.items.contains(focus) }?.group
    }

    func contains(_ focus: PlayFocus) -> Bool {
        bands.contains { $0.items.contains(focus) }
    }

    /// The first thing worth focusing when the keyboard arrives.
    var first: PlayFocus? { bands.first?.items.first }

    /// Moves along the current band, wrapping at its ends.
    ///
    /// Wrapping rather than stopping: a hand of five cards is a ring, and a
    /// player pressing right at the last card means "the other end", not
    /// "nothing happens".
    func step(from focus: PlayFocus?, by delta: Int) -> PlayFocus? {
        guard let focus, let band = bands.first(where: { $0.items.contains(focus) }),
              let index = band.items.firstIndex(of: focus)
        else { return first }

        let count = band.items.count
        let next = ((index + delta) % count + count) % count
        return band.items[next]
    }

    /// Moves to the next band up or down, landing on its first item.
    func jump(from focus: PlayFocus?, by delta: Int) -> PlayFocus? {
        guard let focus, let current = bands.firstIndex(where: { $0.items.contains(focus) })
        else { return first }

        let count = bands.count
        let next = ((current + delta) % count + count) % count
        return bands[next].items.first
    }
}

/// A key the play screen understands.
enum PlayKey: Equatable {
    case left, right, up, down
    case activate
    case cancel
}

/// What a key press should cause.
enum PlayIntent: Equatable {
    case moveFocus(PlayFocus)
    case activate(PlayFocus)
    case cancel
    case ignored
}

/// Translates a key press into an intent.
///
/// Deliberately pure. A hardware keyboard is the one input a simulator run
/// cannot be relied on to reproduce, so the entire keyboard contract lives
/// somewhere a unit test can reach it, and the view is left with nothing but
/// the wiring.
enum PlayKeyboard {
    static func intent(for key: PlayKey, focus: PlayFocus?, ring: FocusRing) -> PlayIntent {
        guard !ring.isEmpty else {
            // Nothing to act on. Cancel still works: a player who has chosen a
            // card and found no target needs a way back out (§37).
            return key == .cancel ? .cancel : .ignored
        }

        // Focus that has gone stale — the card was played, the target is no
        // longer legal — must not strand the keyboard. Any key brings it back
        // to something real.
        let live = focus.flatMap { ring.contains($0) ? $0 : nil }

        switch key {
        case .cancel:
            return .cancel
        case .activate:
            guard let live else { return ring.first.map(PlayIntent.moveFocus) ?? .ignored }
            return .activate(live)
        case .left:
            return ring.step(from: live, by: -1).map(PlayIntent.moveFocus) ?? .ignored
        case .right:
            return ring.step(from: live, by: 1).map(PlayIntent.moveFocus) ?? .ignored
        case .up:
            return ring.jump(from: live, by: -1).map(PlayIntent.moveFocus) ?? .ignored
        case .down:
            return ring.jump(from: live, by: 1).map(PlayIntent.moveFocus) ?? .ignored
        }
    }
}
