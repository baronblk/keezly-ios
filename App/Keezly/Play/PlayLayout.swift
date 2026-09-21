import CoreGraphics

/// How the playing screen divides a landscape display between the board and
/// the two seat columns beside it (§35).
///
/// Pure arithmetic, deliberately outside the view. A layout that does not add
/// up shows itself as something drawn off the edge of the screen, which is
/// only ever noticed on the device that happens to be in somebody's hand —
/// `PlayLayoutTests` adds it up instead, across every size Keezly runs on.
struct PlayLayout {
    /// The narrowest a seat panel can be and still be read: a name, a card
    /// count and a home count, side by side.
    static let minimumSideColumn: CGFloat = 210

    let boardSide: CGFloat
    let sideWidth: CGFloat

    init(size: CGSize, handHeight: CGFloat) {
        let available = Self.availableWidth(size)
        let heightBudget = Self.heightBudget(size, handHeight: handHeight)
        // What the width can spare for a board once both columns are readable.
        let roomBesideColumns = max(0, available - Self.minimumSideColumn * 2)

        // The board is square, so height sets its size — but never more than
        // the width can hold. An earlier version took the larger of the two
        // and floored it at most of the short screen edge, which on a portrait
        // iPad made a board wider than the row it sits in and pushed the far
        // seat panel clean off the screen.
        boardSide = min(roomBesideColumns, heightBudget)
        sideWidth = max(Self.minimumSideColumn, (available - boardSide) / 2)
    }

    /// Everything the row occupies, padding and gaps included.
    var totalWidth: CGFloat {
        boardSide + sideWidth * 2 + Keezly.Spacing.large * 2 + Keezly.Spacing.regular * 2
    }

    /// Whether a board flanked by two seat panels is the better use of this
    /// screen at all.
    ///
    /// True only where width is the abundant dimension: the board can be as
    /// large as the height allows *and* still leave room for two readable
    /// columns. That is a landscape display, whatever the size class says.
    /// Everywhere else the board goes above the hand and the opponents become
    /// a strip, because a portrait iPad gives a board a thousand points of
    /// width and squeezing columns in beside it wastes most of them.
    static func prefersColumns(size: CGSize, handHeight: CGFloat) -> Bool {
        let available = availableWidth(size)
        return available - minimumSideColumn * 2 >= heightBudget(size, handHeight: handHeight)
    }

    private static func availableWidth(_ size: CGSize) -> CGFloat {
        size.width - Keezly.Spacing.regular * 2 - Keezly.Spacing.large * 2
    }

    private static func heightBudget(_ size: CGSize, handHeight: CGFloat) -> CGFloat {
        max(0, size.height - handHeight - Keezly.Spacing.section)
    }
}
