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
