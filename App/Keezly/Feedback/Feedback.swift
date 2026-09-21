import Foundation
import Observation
import UIKit

/// What the player has asked for.
///
/// Both channels are off-switchable and both switches are honoured in one
/// place, so "I turned that off" cannot be true of one code path and false of
/// another (§43).
@Observable
@MainActor
final class Preferences {
    private let defaults: UserDefaults

    var playsSound: Bool {
        didSet { defaults.set(playsSound, forKey: Keys.sound) }
    }

    var playsHaptics: Bool {
        didSet { defaults.set(playsHaptics, forKey: Keys.haptics) }
    }

    private enum Keys {
        static let sound = "keezly.sound"
        static let haptics = "keezly.haptics"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // On by default, because a board game that makes no sound when you put
        // a piece down feels broken — but see `SoundPlayer`: until there are
        // sounds to play, this switch governs silence.
        playsSound = defaults.object(forKey: Keys.sound) as? Bool ?? true
        playsHaptics = defaults.object(forKey: Keys.haptics) as? Bool ?? true
    }
}

// MARK: - Channels

/// Something that can make the device knock.
protocol HapticChannel: Sendable {
    @MainActor func play(_ cue: FeedbackCue)
    /// Warms the hardware up so the first cue is not late.
    @MainActor func prepare()
}

/// Something that can make a sound.
protocol SoundChannel: Sendable {
    @MainActor func play(_ cue: FeedbackCue)
    /// Whether this cue has an actual recording behind it.
    @MainActor func hasAsset(for cue: FeedbackCue) -> Bool
}

/// The real haptics, through the system's feedback generators.
///
/// Deliberately built on the standard generators rather than on Core Haptics
/// patterns of our own. A board game wants the same small vocabulary of knocks
/// every other app uses — a piece going down should feel like a piece going
/// down, not like a signature.
struct SystemHaptics: HapticChannel {
    @MainActor
    func prepare() {
        UIImpactFeedbackGenerator(style: .light).prepare()
    }

    @MainActor
    func play(_ cue: FeedbackCue) {
        switch cue {
        case .select, .fold:
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: cue.strength)
        case .place, .swap:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: cue.strength)
        case .capture:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: cue.strength)
        case .home:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .victory:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

/// The sound channel.
///
/// **ASSET PENDING.** The architecture is here and the cues are wired; there
/// are no recordings behind them yet, so every call is silence.
///
/// That is a decision rather than an oversight. Keezly may only ship audio it
/// owns or can clearly account for (§77), and a set of mediocre placeholder
/// noises would be worse than none: they would be heard on every move, they
/// would set the tone of the whole game, and they would be very hard to
/// justify removing later. `hasAsset(for:)` answers honestly, and the settings
/// screen says so rather than offering a switch that does nothing.
///
/// When the recordings exist they drop into the bundle under the cue's own
/// name — `place.caf`, `capture.caf` — and nothing else changes.
struct BundledSounds: SoundChannel {
    /// Where a recording for a cue would be found.
    static func fileName(for cue: FeedbackCue) -> String { "\(cue.rawValue).caf" }

    @MainActor
    func hasAsset(for cue: FeedbackCue) -> Bool {
        Bundle.main.url(forResource: cue.rawValue, withExtension: "caf") != nil
    }

    @MainActor
    func play(_ cue: FeedbackCue) {
        guard hasAsset(for: cue) else { return }
        // Intentionally unimplemented until there is something to play. A
        // player who has never heard a sound from Keezly has heard exactly
        // what this release promises.
    }
}

// MARK: - The one place both channels are consulted

/// Turns what the engine did into what the player feels and hears.
///
/// Every cue in the app goes through here, which is what makes the two
/// switches mean something: there is no second path that plays a sound.
@MainActor
struct Feedback {
    let preferences: Preferences
    var haptics: any HapticChannel = SystemHaptics()
    var sounds: any SoundChannel = BundledSounds()

    func prepare() {
        guard preferences.playsHaptics else { return }
        haptics.prepare()
    }

    /// Plays whatever this run of events is worth.
    func play(_ events: [GameEventCue]) {
        for cue in events {
            play(cue)
        }
    }

    func play(_ cue: FeedbackCue) {
        if preferences.playsHaptics { haptics.play(cue) }
        if preferences.playsSound { sounds.play(cue) }
    }

    /// Whether any cue has a recording behind it. Used by the settings screen
    /// to say plainly that sound is not here yet rather than offering a switch
    /// that governs nothing.
    var hasAnySound: Bool {
        FeedbackCue.allCases.contains { sounds.hasAsset(for: $0) }
    }
}

/// Alias kept for readability at the call site.
typealias GameEventCue = FeedbackCue
