import KeezlyCore
import SwiftUI

/// How a seat is identified on screen.
///
/// **Colour is never the only signal** (§42, §53). Every seat also has a
/// distinct geometric mark, so the board remains readable for colour-blind
/// players, in greyscale, and in a screenshot printed in black and white.
/// The marks are drawn in code — simple original geometry, no assets and
/// nothing borrowed.
struct PlayerIdentity: Hashable, Sendable {
    let seat: Seat
    let color: Color
    let mark: PawnMark
    /// Short label for VoiceOver and for compact HUD elements. Localised by
    /// the caller; this is the key.
    let nameKey: String

    /// The six seat identities, in seating order.
    ///
    /// Hues are spread around the wheel *and* separated in lightness, so the
    /// set survives both common colour-vision deficiencies and greyscale.
    static let all: [PlayerIdentity] = [
        PlayerIdentity(seat: 0, hex: 0xDC4F_4A, mark: .circle, nameKey: "seat.red"),
        PlayerIdentity(seat: 1, hex: 0x298C_AE, mark: .triangle, nameKey: "seat.blue"),
        PlayerIdentity(seat: 2, hex: 0xE8B0_38, mark: .square, nameKey: "seat.amber"),
        PlayerIdentity(seat: 3, hex: 0x5C99_59, mark: .diamond, nameKey: "seat.green"),
        PlayerIdentity(seat: 4, hex: 0x8563_B5, mark: .hexagon, nameKey: "seat.violet"),
        PlayerIdentity(seat: 5, hex: 0xD985_4A, mark: .chevron, nameKey: "seat.orange"),
    ]

    private init(seat index: Int, hex: UInt32, mark: PawnMark, nameKey: String) {
        self.seat = Seat(index)
        self.color = Color(hex: hex)
        self.mark = mark
        self.nameKey = nameKey
    }

    static func identity(for seat: Seat) -> PlayerIdentity {
        all[seat.index % all.count]
    }
}

extension Color {
    /// Builds a colour from `0xRRGGBB`, which keeps the palette table readable
    /// as a table.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// The redundant, non-colour channel of seat identity.
enum PawnMark: String, Hashable, Sendable, CaseIterable {
    case circle, triangle, square, diamond, hexagon, chevron

    /// The mark as a path inside `rect`, centred and inset.
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let box = CGRect(
            x: rect.midX - side / 2,
            y: rect.midY - side / 2,
            width: side,
            height: side
        ).insetBy(dx: side * 0.18, dy: side * 0.18)

        var path = Path()
        switch self {
        case .circle:
            path.addEllipse(in: box)
        case .triangle:
            path.move(to: CGPoint(x: box.midX, y: box.minY))
            path.addLine(to: CGPoint(x: box.maxX, y: box.maxY))
            path.addLine(to: CGPoint(x: box.minX, y: box.maxY))
            path.closeSubpath()
        case .square:
            path.addRoundedRect(in: box, cornerSize: CGSize(width: box.width * 0.16, height: box.width * 0.16))
        case .diamond:
            path.move(to: CGPoint(x: box.midX, y: box.minY))
            path.addLine(to: CGPoint(x: box.maxX, y: box.midY))
            path.addLine(to: CGPoint(x: box.midX, y: box.maxY))
            path.addLine(to: CGPoint(x: box.minX, y: box.midY))
            path.closeSubpath()
        case .hexagon:
            for step in 0..<6 {
                let angle = Double(step) / 6 * 2 * .pi - .pi / 2
                let point = CGPoint(
                    x: box.midX + cos(angle) * box.width / 2,
                    y: box.midY + sin(angle) * box.height / 2
                )
                if step == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.closeSubpath()
        case .chevron:
            path.move(to: CGPoint(x: box.minX, y: box.maxY))
            path.addLine(to: CGPoint(x: box.midX, y: box.minY))
            path.addLine(to: CGPoint(x: box.maxX, y: box.maxY))
            path.addLine(to: CGPoint(x: box.midX, y: box.midY + box.height * 0.08))
            path.closeSubpath()
        }
        return path
    }
}
