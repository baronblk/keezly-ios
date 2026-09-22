import AVFoundation
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
        // On by default, because a board game that makes no sound when you
        // put a piece down feels broken. Quiet enough that leaving it on is
        // not a decision anybody has to regret.
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
    /// Loads whatever it needs, so the first cue is not late.
    @MainActor func prepare()
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
/// Seven cues, all synthesised by `Tools/soundforge.py` and installed by
/// `scripts/sounds-build.sh`. Nothing is sampled and nothing is downloaded:
/// the provenance of the audio is the source code that made it, which is the
/// only kind of provenance worth having (§77).
///
/// They are modal synthesis — the way a struck object actually sounds. A piece
/// set down on a board rings at a few inharmonic frequencies that decay at
/// different rates; a card is broadband noise that is over almost immediately.
/// That is why the set reads as wood and paper rather than as beeps, and it is
/// what keeps it inside the board's own design language.
///
/// Played through `AVAudioPlayer` on the **ambient** session category, which
/// is the correct choice for a board game: it respects the silent switch and
/// it does not stop whatever the player was listening to.
struct BundledSounds: SoundChannel {
    /// Where a recording for a cue lives.
    static func fileName(for cue: FeedbackCue) -> String { "\(cue.rawValue).caf" }

    @MainActor
    func hasAsset(for cue: FeedbackCue) -> Bool {
        SoundBank.shared.url(for: cue) != nil
    }

    @MainActor
    func prepare() {
        SoundBank.shared.prepare()
    }

    @MainActor
    func play(_ cue: FeedbackCue) {
        SoundBank.shared.play(cue)
    }
}

/// Holds the players so a cue lands the instant it is asked for.
///
/// Building an `AVAudioPlayer` takes long enough to be heard as lateness on a
/// sound that is meant to coincide with a piece going down, so each cue is
/// prepared once. Two players per cue, alternated: a Seven can put two pieces
/// down close enough together that the second would otherwise cut the first
/// off mid-knock.
@MainActor
final class SoundBank {
    static let shared = SoundBank()

    private var players: [FeedbackCue: [AVAudioPlayer]] = [:]
    private var next: [FeedbackCue: Int] = [:]
    private var sessionReady = false

    private init() {}

    func url(for cue: FeedbackCue) -> URL? {
        Bundle.main.url(forResource: cue.rawValue, withExtension: "caf")
    }

    /// Loads every cue and readies the audio session.
    ///
    /// Called when a board appears. Doing it lazily on the first cue would put
    /// the cost exactly where it is most audible.
    func prepare() {
        guard !sessionReady else { return }
        sessionReady = true

        do {
            // Ambient: the silent switch silences it, and the player's own
            // music keeps playing. A game that stopped somebody's podcast to
            // click at them would deserve what it got.
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Sound is not worth failing over. The game is silent and plays on.
            return
        }

        for cue in FeedbackCue.allCases {
            guard let url = url(for: cue) else { continue }
            let pair = (0..<2).compactMap { _ -> AVAudioPlayer? in
                guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
                player.prepareToPlay()
                return player
            }
            if !pair.isEmpty { players[cue] = pair }
        }
    }

    func play(_ cue: FeedbackCue) {
        prepare()
        guard let pair = players[cue], !pair.isEmpty else { return }
        let index = (next[cue] ?? 0) % pair.count
        next[cue] = index + 1

        let player = pair[index]
        player.currentTime = 0
        player.play()
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
        if preferences.playsHaptics { haptics.prepare() }
        if preferences.playsSound { sounds.prepare() }
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
