import CoreGraphics
@testable import Keezly
import Testing

/// §5, §35 — the playing screen has to add up on every display it runs on.
///
/// Written after a portrait iPad drew the far seat panel past the right edge
/// of the screen. The arithmetic was wrong by about a hundred points and had
/// been reviewed twice by looking at landscape screenshots, where it happened
/// to fit. A layout that is only checked by eye is checked on whatever device
/// was to hand.
@Suite("Play layout")
struct PlayLayoutTests {

    /// The sizes Keezly actually runs at, in points, both ways round, each
    /// with the layout it is meant to get.
    ///
    /// Written out rather than derived from an aspect ratio, because the rule
    /// is not "landscape gets columns" but "columns where there is room for
    /// them": a small Stage Manager window is wider than it is tall and still
    /// has no room, and saying so here is the point of the table.
    private struct Display {
        let name: String
        let size: CGSize
        /// The layout this display is meant to get.
        let columns: Bool

        init(_ name: String, _ width: CGFloat, _ height: CGFloat, columns: Bool) {
            self.name = name
            self.size = CGSize(width: width, height: height)
            self.columns = columns
        }
    }

    private static let displays: [Display] = [
        Display("iPad Pro 13 portrait", 1032, 1376, columns: false),
        Display("iPad Pro 13 landscape", 1376, 1032, columns: true),
        Display("iPad Pro 11 portrait", 834, 1210, columns: false),
        Display("iPad Pro 11 landscape", 1210, 834, columns: true),
        Display("iPad mini portrait", 744, 1133, columns: false),
        Display("iPad mini landscape", 1133, 744, columns: true),
        Display("iPad A16 portrait", 820, 1180, columns: false),
        Display("iPad A16 landscape", 1180, 820, columns: true),
        Display("Split View half", 507, 1032, columns: false),
        Display("Split View third", 320, 1032, columns: false),
        // Reached by the short-landscape layout before this decision is made;
        // listed so that if it ever is asked, the answer is still no.
        Display("Stage Manager small", 640, 480, columns: false),
    ]

    /// Roughly what a fanned hand of iPad-sized cards takes.
    private let handHeight: CGFloat = 112 * 1.45 + 112 * 0.3

    // MARK: - The guarantee

    /// **Nothing is drawn past the edge of the screen.**
    @Test("where the columns are used, the three of them fit the width")
    func columnsFitTheScreen() {
        for display in Self.displays where display.columns {
            let layout = PlayLayout(size: display.size, handHeight: handHeight)
            #expect(
                layout.totalWidth <= display.size.width + 0.5,
                """
                \(display.name) overflows by \(layout.totalWidth - display.size.width) points: \
                board \(layout.boardSide), columns \(layout.sideWidth) each
                """
            )
        }
    }

    @Test("a seat panel is never squeezed past reading")
    func columnsStayReadable() {
        for display in Self.displays where display.columns {
            let layout = PlayLayout(size: display.size, handHeight: handHeight)
            #expect(layout.sideWidth >= PlayLayout.minimumSideColumn, "\(display.name) squeezed its seat panels")
        }
    }

    @Test("a board beside two columns is still worth looking at")
    func boardStaysLarge() {
        for display in Self.displays where display.columns {
            let layout = PlayLayout(size: display.size, handHeight: handHeight)
            #expect(
                layout.boardSide >= min(display.size.width, display.size.height) * 0.5,
                "\(display.name) left the board smaller than half the short edge"
            )
        }
    }

    // MARK: - Choosing between the two layouts

    @Test("each display gets the layout it was meant to get")
    func eachDisplayGetsItsLayout() {
        for display in Self.displays {
            #expect(
                PlayLayout.prefersColumns(size: display.size, handHeight: handHeight) == display.columns,
                "\(display.name) wanted \(display.columns ? "columns" : "a stack") and got the other"
            )
        }
        // Every full-size iPad in landscape, so the panels are not quietly
        // lost to a rounding change.
        #expect(Self.displays.count(where: \.columns) == 4)
    }

    @Test("a narrow display never asks for three columns")
    func narrowDisplaysStack() {
        for width in stride(from: CGFloat(320), through: 700, by: 20) {
            let size = CGSize(width: width, height: 1000)
            #expect(!PlayLayout.prefersColumns(size: size, handHeight: handHeight))
        }
    }

    // MARK: - Split View, Stage Manager, and everything between

    /// The widths an iPad actually hands an app.
    ///
    /// An iPad is **not** always full screen (§4). Split View gives a third,
    /// a half or two thirds; Stage Manager gives whatever the person has
    /// dragged the window to. A layout tested only at device sizes is a layout
    /// tested at the sizes nobody in Split View ever sees.
    private static let splitViewWidths: [(name: String, width: CGFloat)] = [
        ("13\" one third", 375), ("13\" half", 507), ("13\" two thirds", 639),
        ("11\" one third", 320), ("11\" half", 405), ("11\" two thirds", 504),
        ("mini one third", 320), ("mini half", 360),
    ]

    /// **Every width an iPad can hand the app, swept rather than sampled.**
    ///
    /// From a third of the narrowest iPad to the whole of the widest, at every
    /// point in between, in both orientations. Whichever layout is chosen, it
    /// has to fit the width it was given and leave the hand on screen.
    @Test("the layout fits at every width between a third of an iPad and all of one")
    func everyIntermediateWidthFits() {
        for width in stride(from: CGFloat(320), through: 1400, by: 8) {
            for height in [CGFloat(440), 620, 834, 1032, 1210, 1376] {
                let size = CGSize(width: width, height: height)

                if PlayLayout.prefersColumns(size: size, handHeight: handHeight) {
                    let layout = PlayLayout(size: size, handHeight: handHeight)
                    #expect(
                        layout.totalWidth <= width + 0.5,
                        "columns overflow \(Int(width))×\(Int(height)) by \(Int(layout.totalWidth - width))"
                    )
                    #expect(layout.sideWidth >= PlayLayout.minimumSideColumn)
                } else {
                    let layout = StackedLayout(size: size, chromeHeight: 132)
                    #expect(
                        layout.totalWidth <= width + 0.5 || layout.boardSide == StackedLayout.minimumBoardSide,
                        "the stack overflows \(Int(width))×\(Int(height)) by \(Int(layout.totalWidth - width))"
                    )
                    #expect(layout.boardSide >= StackedLayout.minimumBoardSide)
                    #expect(layout.cardWidth > 0)
                    #expect(layout.handWidth >= 0)
                }
            }
        }
    }

    /// A Split View pane is never wide enough for a board flanked by two
    /// readable seat panels, so it must always get the stack.
    @Test("every Split View width stacks rather than trying three columns")
    func splitViewAlwaysStacks() {
        for pane in Self.splitViewWidths {
            for height in [CGFloat(834), 1032, 1210, 1376] {
                let size = CGSize(width: pane.width, height: height)
                #expect(
                    !PlayLayout.prefersColumns(size: size, handHeight: handHeight),
                    "\(pane.name) at \(Int(height)) tried to fit three columns into \(Int(pane.width))pt"
                )
            }
        }
    }

    /// **The board never leaves the pane it was given.**
    @Test("a Split View pane holds its board and its hand")
    func splitViewPanesHoldTheirContent() {
        for pane in Self.splitViewWidths {
            let size = CGSize(width: pane.width, height: 1032)
            let layout = StackedLayout(size: size, chromeHeight: 132)
            #expect(
                layout.totalWidth <= pane.width + 0.5,
                "\(pane.name) overflows by \(Int(layout.totalWidth - pane.width))pt"
            )
            // And the hand still has somewhere to be.
            #expect(
                size.height - layout.boardSide - 132 > 0,
                "\(pane.name) left no room for the hand"
            )
        }
    }

    /// **Resizing a window must not make the board jump.**
    ///
    /// Under Stage Manager a resize drags through every width on the way, so
    /// what matters is that the layout is *continuous*: a small change in
    /// width may only make a small change to the board.
    ///
    /// Not monotonic — the board deliberately gives up about a point per four
    /// as the window widens, because the cards grow with it, and that trade is
    /// the design. What is not allowed is a step. The first version of this
    /// layout stepped at the size-class boundary: the margin went from 8 to 24
    /// and the card base from 92 to 112 at 600 points, so **the board shrank
    /// 28 points as the window grew 4** — a visible jolt in the middle of a
    /// drag, which nobody would ever have seen on a phone because a phone
    /// never crosses that boundary.
    @Test("resizing a window moves the board smoothly, never in a step")
    func resizingIsContinuous() {
        func board(at width: CGFloat) -> (side: CGFloat, columns: Bool) {
            let size = CGSize(width: width, height: 1032)
            if PlayLayout.prefersColumns(size: size, handHeight: handHeight) {
                return (PlayLayout(size: size, handHeight: handHeight).boardSide, true)
            }
            return (StackedLayout(size: size, chromeHeight: 132).boardSide, false)
        }

        let step = CGFloat(4)
        var previous = board(at: 320)
        var worst = CGFloat(0)
        for width in stride(from: CGFloat(324), through: 1376, by: step) {
            let current = board(at: width)
            // Crossing between the stack and the columns is allowed to change
            // the board's size: they are two different layouts.
            if current.columns == previous.columns {
                let jump = abs(current.side - previous.side)
                worst = max(worst, jump)
                #expect(
                    jump <= step * 1.5,
                    "the board moved \(Int(jump))pt for a \(Int(step))pt resize at \(Int(width))pt"
                )
            }
            previous = current
        }
        #expect(worst > 0, "the board never moved at all, so nothing was measured")
    }

    /// Whatever the size, the numbers stay numbers.
    @Test("an impossible size produces no negative geometry")
    func degenerateSizesAreSafe() {
        for size in [CGSize.zero, CGSize(width: 1, height: 1), CGSize(width: 2000, height: 10)] {
            let layout = PlayLayout(size: size, handHeight: handHeight)
            #expect(layout.boardSide >= 0)
            #expect(layout.sideWidth >= PlayLayout.minimumSideColumn)
        }
    }
}
