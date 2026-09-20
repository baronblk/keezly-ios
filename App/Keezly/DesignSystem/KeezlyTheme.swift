import SwiftUI

/// The Keezly design system (§42).
///
/// One place for the decisions that would otherwise be re-made, slightly
/// differently, in every view: spacing, corner radii, type, materials and
/// motion. Values are scaled by size class where the difference is real — a
/// board on a 13-inch iPad is not a phone board with bigger numbers (§4).
enum Keezly {

    // MARK: - Spacing

    /// A four-point rhythm. Named rather than numbered so call sites read as
    /// intent instead of arithmetic.
    enum Spacing {
        static let hairline: CGFloat = 2
        static let tight: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let regular: CGFloat = 16
        static let large: CGFloat = 24
        static let extraLarge: CGFloat = 32
        static let section: CGFloat = 48
    }

    // MARK: - Shape

    enum Radius {
        static let small: CGFloat = 6
        static let card: CGFloat = 10
        static let panel: CGFloat = 18
        static let sheet: CGFloat = 28
    }

    // MARK: - Colour
    //
    // Deliberately a quiet, near-neutral table so the pieces carry the colour.
    // Every value has a dark and a light form; nothing is hard-coded per mode
    // at a call site.

    enum Palette {
        /// The surface the board sits on.
        static let table = Color("TableSurface", bundle: .main)
        /// The board itself.
        static let board = Color("BoardSurface", bundle: .main)
        /// An empty square on the track.
        static let square = Color("BoardSquare", bundle: .main)
        /// The rim drawn around squares and lanes.
        static let rim = Color("BoardRim", bundle: .main)

        static let primaryText = Color.primary
        static let secondaryText = Color.secondary

        /// Highlight for a square a selected pawn could move to.
        static let legalTarget = Color("LegalTarget", bundle: .main)
        /// Highlight for a pawn the player may pick up.
        static let selectable = Color("Selectable", bundle: .main)
    }

    // MARK: - Type

    enum Typography {
        static func display(compact: Bool) -> Font {
            .system(size: compact ? 34 : 52, weight: .semibold, design: .rounded)
        }

        static func title(compact: Bool) -> Font {
            .system(size: compact ? 20 : 26, weight: .semibold, design: .rounded)
        }

        static let body = Font.body
        static let caption = Font.caption
        /// Card ranks: rounded, tabular, legible at a glance across a table.
        static func cardRank(size: CGFloat) -> Font {
            .system(size: size, weight: .semibold, design: .rounded)
        }
    }

    // MARK: - Motion
    //
    // One place to slow everything down for Reduce Motion, and one place for
    // the settings-controlled animation speed (§39, §59).

    enum Motion {
        /// A pawn travelling one square.
        static let stepDuration: TimeInterval = 0.16
        /// A card leaving the hand.
        static let cardPlayDuration: TimeInterval = 0.28
        /// A captured pawn returning to its waiting area.
        static let captureDuration: TimeInterval = 0.42
        /// A Jack swap.
        static let swapDuration: TimeInterval = 0.5

        /// The standard move curve: quick to start, settles without bouncing.
        static func step(reduceMotion: Bool, speed: Double = 1) -> Animation {
            reduceMotion
                ? .linear(duration: stepDuration / speed * 0.5)
                : .timingCurve(0.2, 0.8, 0.2, 1, duration: stepDuration / speed)
        }

        static func transition(reduceMotion: Bool, speed: Double = 1) -> Animation {
            reduceMotion
                ? .linear(duration: cardPlayDuration / speed * 0.5)
                : .spring(response: cardPlayDuration / speed, dampingFraction: 0.82)
        }
    }

    // MARK: - Touch targets

    enum Target {
        /// Apple's minimum. Anything a finger must hit clears this, even when
        /// the drawn shape is smaller (§53).
        static let minimum: CGFloat = 44
    }
}
