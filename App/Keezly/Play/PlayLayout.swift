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

/// How the stacked layout divides a display: the board above, the hand below.
///
/// The layout a phone always gets, a portrait iPad gets, and an iPad in Split
/// View or a resized Stage Manager window gets. It has to hold at *every*
/// width between a third of an iPad and the whole of one, not only at the
/// handful of sizes a device list happens to name — which is what
/// `PlayLayoutTests` sweeps.
struct StackedLayout {
    /// Below this a board stops being a board, whatever else is competing for
    /// the space.
    static let minimumBoardSide: CGFloat = 240
    /// The range a hand card's width moves through, narrow display to wide.
    static let compactCardWidth: CGFloat = 110
    static let regularCardWidth: CGFloat = 150
    /// The range its starting size moves through, before spare height is
    /// given to it.
    static let compactBaseCard: CGFloat = 92
    static let regularBaseCard: CGFloat = 112

    let margin: CGFloat
    let boardSide: CGFloat
    let cardWidth: CGFloat
    /// What the hand's frame is given, which is narrower than the screen: a
    /// fanned card is rotated about its foot and reaches further sideways than
    /// the frame it sits in.
    let handWidth: CGFloat

    /// Everything here scales with the width rather than stepping at the
    /// size-class boundary.
    ///
    /// It used to step, and `PlayLayoutTests` caught what that cost: at 600
    /// points the margin jumped from 8 to 24 and the card base from 92 to 112,
    /// so the **board shrank by 28 points as the window grew by 4**. On a
    /// phone that boundary is never crossed and nobody would see it; under
    /// Stage Manager a resize drags straight through it, and the board would
    /// visibly jolt backwards mid-drag.
    ///
    /// Size class says which kind of device this probably is. It does not say
    /// how much room there is, and how much room there is, is the question
    /// (§4, §5).
    init(size: CGSize, chromeHeight: CGFloat) {
        // A phone wants its board near the edges; a thirteen-inch panel
        // touching the glass looks like a mistake. Between them, in between.
        margin = min(Keezly.Spacing.large, max(Keezly.Spacing.small, size.width * 0.022))
        let baseCardWidth = min(Self.regularBaseCard, max(Self.compactBaseCard, size.width * 0.11))

        // The board would happily take the whole width, but the chrome above
        // and below it grows with the reader's text size. Whatever else
        // happens, the cards stay reachable (§53).
        boardSide = max(
            Self.minimumBoardSide,
            min(size.width - margin * 2, size.height - chromeHeight - baseCardWidth * 1.2)
        )
        let spare = max(0, size.height - boardSide - chromeHeight)
        let cap = min(Self.regularCardWidth, max(Self.compactCardWidth, size.width * 0.145))
        cardWidth = min(cap, max(baseCardWidth, spare / 1.95))
        handWidth = max(0, size.width - Keezly.Spacing.section)
    }

    /// Everything the row of content occupies across, padding included.
    var totalWidth: CGFloat { boardSide + margin * 2 }
}
