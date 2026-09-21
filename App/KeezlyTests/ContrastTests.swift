@testable import Keezly
import SwiftUI
import Testing
import UIKit

/// §53 — text has to be readable, and "looks fine to me" is not a measurement.
///
/// Written after `Keezly.Palette.secondaryText` was found at **2.88:1** against
/// the menu panel — below the floor for text of any size. It had been reviewed
/// by eye several times. The colour was `Color.secondary`, which follows the
/// system appearance; the panel it sits on is the board's own wood, which does
/// not, so in light mode the two drifted apart and nothing said so.
@Suite("Contrast")
@MainActor
struct ContrastTests {

    /// WCAG relative luminance.
    private func luminance(_ colour: UIColor) -> Double {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        colour.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        func channel(_ value: CGFloat) -> Double {
            let value = Double(value)
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// The contrast ratio between two colours, as the guidelines define it.
    private func ratio(_ first: Color, on second: Color) -> Double {
        // Resolved in the light appearance, which is where the failure was:
        // the wooden surfaces do not change with the system scheme, so a
        // colour that does will meet the wood differently in each.
        let light = UITraitCollection(userInterfaceStyle: .light)
        let foreground = UIColor(first).resolvedColor(with: light)
        let background = UIColor(second).resolvedColor(with: light)

        let one = luminance(foreground)
        let two = luminance(background)
        return (max(one, two) + 0.05) / (min(one, two) + 0.05)
    }

    private let wood = BoardTheme.classicWood

    // MARK: - The floors

    /// Normal-size text needs 4.5:1.
    @Test("quiet text on the app's wooden surfaces is readable")
    func secondaryTextIsReadable() {
        for surface in [wood.surfaceMid, wood.surfaceLight, wood.surfaceDeep] {
            let measured = ratio(Keezly.Palette.secondaryText, on: surface)
            #expect(measured >= 4.5, "secondary text measures \(String(format: "%.2f", measured)):1")
        }
    }

    @Test("ordinary text on the wood is readable")
    func primaryTextIsReadable() {
        let measured = ratio(Keezly.Palette.primaryText, on: wood.surfaceMid)
        #expect(measured >= 4.5, "primary text measures \(String(format: "%.2f", measured)):1")
    }

    /// The board's chrome is light text on the dark table.
    @Test("text on the table is readable")
    func tableTextIsReadable() {
        let measured = ratio(.white, on: wood.table)
        #expect(measured >= 4.5, "white on the table measures \(String(format: "%.2f", measured)):1")
    }

    /// **A seat's colour alone does not clear the 3:1 bar against the board,
    /// and is not asked to.**
    ///
    /// Measured rather than claimed. Amber on the light wood is the weakest at
    /// about 1.2:1; the dark outline every piece carries reaches about 2.0:1.
    /// Nothing short of a materially darker board would clear 3:1, and the
    /// board's appearance is settled (DEC-018).
    ///
    /// What carries identity instead is not colour: every seat has its own
    /// mark, every piece is named in words by `MoveNarrator`, and every move
    /// is reachable from the action list without looking at the board at all.
    /// Colour is the fastest carrier here, never the only one (§42, §53).
    ///
    /// So this is a regression guard on the numbers as they stand, not a pass
    /// against a standard the design does not meet. It is recorded as such in
    /// `KNOWN_ISSUES.md`.
    @Test("no seat colour disappears into the board, and none gets worse")
    func seatColoursAreNotInvisible() {
        var worst = Double.greatestFiniteMagnitude
        for identity in PlayerIdentity.all {
            let measured = ratio(identity.color, on: wood.surfaceMid)
            worst = min(worst, measured)
            #expect(
                measured >= 1.2,
                "\(identity.nameKey) measures \(String(format: "%.2f", measured)):1 against the board"
            )
        }
        // Today's worst is amber at 1.23:1. A change that pushes any seat
        // below this has made the board harder to read, whatever else it did.
        #expect(worst >= 1.2, "the weakest seat colour got weaker")
    }

    /// The outline is what separates a piece from the wood underneath it.
    ///
    /// `PawnView` strokes the silhouette with black at 30%. Composited over
    /// the board that comes to about 2.0:1 — still under the 3:1 a boundary is
    /// asked for, and the honest figure rather than an assumption. Together
    /// with the contact shadow beneath it, it is what makes a piece read as an
    /// object rather than a patch of colour.
    @Test("the outline every piece carries stands off the board")
    func pieceOutlineIsVisible() {
        let outline = composite(.black, alpha: 0.3, over: wood.surfaceMid)
        let measured = ratio(outline, on: wood.surfaceMid)
        #expect(measured >= 1.8, "the outline measures \(String(format: "%.2f", measured)):1")
    }

    /// One colour drawn at partial opacity over another, as the screen does it.
    private func composite(_ colour: Color, alpha: Double, over background: Color) -> Color {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let top = UIColor(colour).resolvedColor(with: light)
        let under = UIColor(background).resolvedColor(with: light)

        func components(_ colour: UIColor) -> (CGFloat, CGFloat, CGFloat) {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var unused: CGFloat = 0
            colour.getRed(&red, green: &green, blue: &blue, alpha: &unused)
            return (red, green, blue)
        }
        let (topRed, topGreen, topBlue) = components(top)
        let (underRed, underGreen, underBlue) = components(under)
        let mix = CGFloat(alpha)
        return Color(
            red: Double(topRed * mix + underRed * (1 - mix)),
            green: Double(topGreen * mix + underGreen * (1 - mix)),
            blue: Double(topBlue * mix + underBlue * (1 - mix))
        )
    }

    /// And from each other.
    ///
    /// Colour is never the only carrier — each seat has its own mark, and
    /// `MoveNarrator` names every piece in words — but two seats that look
    /// alike at a glance make a board slower to read for everybody.
    ///
    /// Two colours can be told apart by lightness or by hue, and a pair needs
    /// only one of the two. Red and blue sit within 1.04:1 of each other in
    /// lightness and 167° apart in hue; amber and orange are 16° apart in hue
    /// and 1.44:1 apart in lightness. Asserting lightness alone would have
    /// failed both, and would have been measuring the wrong thing.
    @Test("no two seats look alike")
    func seatsAreDistinguishable() {
        let identities = PlayerIdentity.all
        for (index, one) in identities.enumerated() {
            for other in identities[(index + 1)...] {
                #expect(one.mark != other.mark, "two seats share a mark")

                let lightness = ratio(one.color, on: other.color)
                let hues = abs(hue(of: one.color) - hue(of: other.color))
                let separation = min(hues, 360 - hues)
                #expect(
                    lightness >= 1.15 || separation >= 30,
                    """
                    \(one.nameKey) and \(other.nameKey) differ by only \
                    \(String(format: "%.2f", lightness)):1 in lightness and \
                    \(String(format: "%.0f", separation))° in hue
                    """
                )
            }
        }
    }

    /// A colour's hue in degrees, for telling two seats apart by something
    /// other than how light they are.
    private func hue(of colour: Color) -> Double {
        let light = UITraitCollection(userInterfaceStyle: .light)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(colour)
            .resolvedColor(with: light)
            .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Double(hue) * 360
    }
}
