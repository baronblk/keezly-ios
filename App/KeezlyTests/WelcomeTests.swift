@testable import Keezly
import Foundation
import Testing

/// §36, §52 — the newcomer nudge appears once and then never again.
///
/// A prompt that comes back after somebody has answered it is worse than no
/// prompt: it says the app was not listening.
@Suite("Welcome")
@MainActor
struct WelcomeTests {

    /// A throwaway store, so a test can never touch the real one.
    private func store(_ name: String = UUID().uuidString) -> UserDefaults {
        UserDefaults(suiteName: name) ?? .standard
    }

    @Test("somebody who has never played is a newcomer")
    func startsAsNewcomer() {
        #expect(Welcome(defaults: store()).isNewcomer)
    }

    @Test("starting a match answers the question for good")
    func startingStops() {
        let defaults = store()
        let welcome = Welcome(defaults: defaults)
        welcome.noteStarted()
        #expect(!welcome.isNewcomer)

        // And it survives the app being closed and opened again, which is the
        // whole point of writing it down.
        #expect(!Welcome(defaults: defaults).isNewcomer)
    }

    @Test("being told twice changes nothing")
    func noteIsIdempotent() {
        let defaults = store()
        let welcome = Welcome(defaults: defaults)
        welcome.noteStarted()
        welcome.noteStarted()
        #expect(!welcome.isNewcomer)
        #expect(!Welcome(defaults: defaults).isNewcomer)
    }

    @Test("two devices do not share an answer")
    func storesAreIndependent() {
        let first = store()
        Welcome(defaults: first).noteStarted()
        #expect(Welcome(defaults: store()).isNewcomer, "a fresh store came back already answered")
    }

    @Test("the nudge can be brought back for a device being handed on")
    func resetWorks() {
        let defaults = store()
        let welcome = Welcome(defaults: defaults)
        welcome.noteStarted()
        welcome.reset()
        #expect(welcome.isNewcomer)
        #expect(Welcome(defaults: defaults).isNewcomer)
    }
}
