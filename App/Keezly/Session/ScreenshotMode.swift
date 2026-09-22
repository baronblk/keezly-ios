import CoreGraphics
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

    /// The situation the board should already be in when the capture is taken.
    ///
    /// Without this a screenshot can only ever show the opening deal, where
    /// every pawn is still waiting — so the two cards with the most interesting
    /// interfaces, the Jack and the Seven, have no legal move to show (§87).
    ///
    /// `-KEEZLY_OPENING jack` · `seven` · `-KEEZLY_OPENING_MOVES <n>`
    static var fixture: MatchFixture? {
        switch value(for: "-KEEZLY_OPENING") {
        case "jack": return .localCanPlay(.jack)
        case "seven": return .localCanPlay(.seven)
        default: break
        }
        if let moves = value(for: "-KEEZLY_OPENING_MOVES").flatMap(Int.init), moves > 0 {
            return .movesPlayed(moves)
        }
        return nil
    }

    /// Whether to show the focus probe.
    ///
    /// Separate from `isActive` on purpose: every deterministic capture runs
    /// with `-KEEZLY_UI_TESTING`, and a debug label burned into an App Store
    /// screenshot would be a genuine mistake.
    static var showsFocusProbe: Bool { arguments.contains("-KEEZLY_DEBUG_FOCUS") }

    /// `-KEEZLY_REPLAY` — open a played-out match in the replay screen instead
    /// of playing one.
    ///
    /// The replay screen is otherwise only reachable from a *finished* match,
    /// which takes an hour to produce by hand. This plays one out with the
    /// fixture machinery and hands the record to the replay, so the screen can
    /// be looked at and captured deterministically (§87).
    static var showsReplay: Bool { arguments.contains("-KEEZLY_REPLAY") }

    /// `-KEEZLY_PANE 507x1376` — draw the app into a pane of that size rather
    /// than the whole screen.
    ///
    /// An iPad is not always full screen (§4). Split View hands an app a
    /// third, a half or two thirds of the width; Stage Manager hands it
    /// whatever the window has been dragged to. Those sizes cannot be reached
    /// from `simctl`, and driving the dock by gesture is not reliable enough
    /// to base a check on.
    ///
    /// This renders the **real views at the real pane size**, which is where
    /// the risk is. It does not exercise iPadOS's own multitasking machinery,
    /// and nothing here claims it does.
    static var pane: CGSize? {
        guard let value = value(for: "-KEEZLY_PANE") else { return nil }
        let parts = value.split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
        return CGSize(width: parts[0], height: parts[1])
    }

    /// Puts the keyboard somewhere at launch.
    ///
    /// iOS gives a view focus only when a hardware keyboard or Full Keyboard
    /// Access is present — with neither, focus is `nil` and nothing about the
    /// keyboard path can be observed at all. This makes the focus state
    /// reachable so it can be verified on a simulator that has no keyboard
    /// attached (§177: verify what can be verified, and say what cannot).
    static var forcesInitialFocus: Bool { value(for: "-KEEZLY_FOCUS") == "first" }

    /// How seats are grouped. Defaults to the standard arrangement for the
    /// table size, which is partners at four and six seats.
    ///
    /// `-KEEZLY_TEAMS teams` · `free`
    static var teamMode: TeamMode {
        switch value(for: "-KEEZLY_TEAMS") {
        case "teams" where seatCount.isMultiple(of: 2): .teamsOfTwo
        case "free": .freeForAll
        default: GameConfiguration.standard(seatCount: seatCount).teamMode
        }
    }

    /// The table Keezly should open with.
    static var configuration: GameConfiguration {
        GameConfiguration(seatCount: seatCount, teamMode: teamMode)
    }

    /// How many seats are played by a person at the device.
    ///
    /// Lets a test set up a deterministic pass-and-play table without driving
    /// the menu, so the privacy guarantee is checked against a fixed deal
    /// rather than whatever a random one happened to offer (§34).
    ///
    /// `-KEEZLY_HUMANS <n>`
    static var humanCount: Int {
        value(for: "-KEEZLY_HUMANS").flatMap(Int.init).map { max(1, min(seatCount, $0)) } ?? 1
    }

    /// People take the first seats, the computer the rest.
    static var roles: [SeatRole] {
        let people = humanCount
        return (0..<seatCount).map { $0 < people ? .human : .computer(.medium) }
    }

    private static func value(for flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
