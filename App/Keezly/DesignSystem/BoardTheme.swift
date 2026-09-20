import SwiftUI

/// The material a board is made of.
///
/// Keezly's default is **Classic Wood**: a light maple board with holes milled
/// into it. The theme exists as a type rather than as scattered colours so a
/// second material can be added later without touching the renderer — and so
/// that "what does a hole look like" has exactly one answer (§42).
///
/// A theme is not an appearance. Classic Wood is the same board in light and
/// dark mode; the asset catalogue simply dims it for a darker room, the way a
/// real board would be dimmer.
struct BoardTheme: Sendable, Hashable {
    let id: String
    /// The lit face of the board.
    let surfaceLight: Color
    /// Its mid tone, used for the body of the panel.
    let surfaceMid: Color
    /// The shaded parts: the outer edge, and the bottom of a bevel.
    let surfaceDeep: Color
    /// Grain strokes. Very low alpha — grain should be felt, not read.
    let grain: Color
    /// The board's outer edge.
    let edge: Color
    /// The floor of a milled hole.
    let holeFill: Color
    /// The shadow cast inside a hole by its upper rim.
    let holeShadow: Color
    /// The lit lower lip of a hole, which is what makes it read as carved
    /// rather than as a dark dot.
    let holeLip: Color
    /// What the board rests on.
    let table: Color

    static let classicWood = BoardTheme(
        id: "classicWood",
        surfaceLight: Color("WoodLight", bundle: .main),
        surfaceMid: Color("WoodMid", bundle: .main),
        surfaceDeep: Color("WoodDeep", bundle: .main),
        grain: Color("WoodGrain", bundle: .main),
        edge: Color("WoodEdge", bundle: .main),
        holeFill: Color("HoleFill", bundle: .main),
        holeShadow: Color("HoleShadow", bundle: .main),
        holeLip: Color("HoleLip", bundle: .main),
        table: Color("TableFelt", bundle: .main)
    )

    /// The alternative material. Prepared, not yet offered in Settings —
    /// Classic Wood is the quality target for 1.0.0 and theme work must not
    /// come at its expense.
    static let darkGraphite = BoardTheme(
        id: "darkGraphite",
        surfaceLight: Color(hex: 0x3A3A3D),
        surfaceMid: Color(hex: 0x2E2E31),
        surfaceDeep: Color(hex: 0x232326),
        grain: Color(hex: 0x000000).opacity(0.08),
        edge: Color(hex: 0x17171A),
        holeFill: Color(hex: 0x232326),
        holeShadow: Color(hex: 0x000000).opacity(0.55),
        holeLip: Color(hex: 0xFFFFFF).opacity(0.14),
        table: Color(hex: 0x131315)
    )

    static let all: [BoardTheme] = [.classicWood, .darkGraphite]
}

extension EnvironmentValues {
    /// The board material in force. Defaults to Classic Wood.
    @Entry var boardTheme: BoardTheme = .classicWood
}
