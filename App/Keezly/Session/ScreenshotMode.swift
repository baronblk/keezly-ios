import Foundation
import KeezlyCore

/// Deterministic configuration for tests and screenshots (§87).
///
/// Driven entirely by launch arguments, so it can only be reached by something
/// that launches the app deliberately — a UI test or a screenshot run. It is
/// not reachable from the app's own interface, changes no rule, and adds no
/// control a player could find.
enum ScreenshotMode {
    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    /// True when the app was launched by a test or screenshot harness.
    static var isActive: Bool { arguments.contains("-KEEZLY_UI_TESTING") }

    /// Seat count to open with. Defaults to four.
    static var seatCount: Int {
        value(for: "-KEEZLY_SEATS").flatMap(Int.init).map { max(2, min(6, $0)) } ?? 4
    }

    /// Match seed, so a screenshot shows the same board every time.
    static var seed: UInt64 {
        value(for: "-KEEZLY_SEED").flatMap(UInt64.init) ?? 2026
    }

    /// How many moves to play before handing control over, so a screenshot can
    /// show a match in progress rather than an untouched opening.
    static var openingMoves: Int {
        value(for: "-KEEZLY_OPENING_MOVES").flatMap(Int.init) ?? 0
    }

    /// The table Keezly should open with.
    static var configuration: GameConfiguration {
        .standard(seatCount: seatCount)
    }

    /// One human at seat zero, computer opponents elsewhere.
    static var roles: [SeatRole] {
        [.human] + Array(repeating: SeatRole.computer(.medium), count: seatCount - 1)
    }

    private static func value(for flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
