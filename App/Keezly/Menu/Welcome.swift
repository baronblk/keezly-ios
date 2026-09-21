import Foundation
import Observation

/// Whether the person holding the device has played Keezly before.
///
/// Keezly's onboarding is one line and one button, not a carousel. Somebody who
/// opens a board game wants to play it; screens that have to be swiped past
/// before that can happen are a tax on everybody, paid most often by the people
/// who already knew how to play (§36, §52).
///
/// So the whole of it is this: until a first match or a first lesson has been
/// started, the way to learn the game is the loudest thing on the menu. After
/// that it goes quiet and stays quiet.
@Observable
@MainActor
final class Welcome {
    private let defaults: UserDefaults
    private static let key = "keezly.hasPlayed"

    /// True until a match or a lesson has been started on this device.
    private(set) var isNewcomer: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isNewcomer = !defaults.bool(forKey: Self.key)
    }

    /// Called when a match or a lesson begins.
    ///
    /// Starting either counts. Somebody who dived straight into a game has
    /// answered the question the nudge was asking.
    func noteStarted() {
        guard isNewcomer else { return }
        isNewcomer = false
        defaults.set(true, forKey: Self.key)
    }

    /// Forgets that anything was played. Only for tests and for a device being
    /// handed on; nothing in the app calls it.
    func reset() {
        defaults.removeObject(forKey: Self.key)
        isNewcomer = true
    }
}
