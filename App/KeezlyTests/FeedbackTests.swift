import AVFoundation
import Foundation
@testable import Keezly
import KeezlyCore
import Testing

/// §43, §77 — what the player feels and hears follows the game, and stops when
/// they say so.
@Suite("Feedback")
@MainActor
struct FeedbackTests {

    private func store(_ name: String = UUID().uuidString) -> UserDefaults {
        UserDefaults(suiteName: name) ?? .standard
    }

    /// A channel that records what it was asked to play instead of playing it.
    private final class Recorder: HapticChannel, SoundChannel, @unchecked Sendable {
        var played: [FeedbackCue] = []
        var prepared = false
        var assets: Set<FeedbackCue> = []

        func play(_ cue: FeedbackCue) { played.append(cue) }
        func prepare() { prepared = true }
        // Both channels are recorded the same way, so one recorder serves both
        // protocols and a test can see whichever it is asking about.
        func hasAsset(for cue: FeedbackCue) -> Bool { assets.contains(cue) }
    }

    /// A `Feedback` with both channels replaced by recorders, so a test can
    /// see what was asked for rather than feeling it.
    private struct Rig {
        let feedback: Feedback
        let touch: Recorder
        let ear: Recorder
    }

    private func rig(sound: Bool = true, haptics: Bool = true) -> Rig {
        let preferences = Preferences(defaults: store())
        preferences.playsSound = sound
        preferences.playsHaptics = haptics
        let touch = Recorder()
        let ear = Recorder()
        ear.assets = Set(FeedbackCue.allCases)
        return Rig(
            feedback: Feedback(preferences: preferences, haptics: touch, sounds: ear),
            touch: touch,
            ear: ear
        )
    }

    // MARK: - Off means off

    /// **The switch is honoured in one place, so it cannot be true of one path
    /// and false of another.**
    @Test("turning haptics off silences the hand")
    func hapticsCanBeTurnedOff() {
        let rig = rig(haptics: false)
        for cue in FeedbackCue.allCases { rig.feedback.play(cue) }
        #expect(rig.touch.played.isEmpty, "a cue reached the hand after haptics were turned off")
        #expect(rig.ear.played.count == FeedbackCue.allCases.count, "sound was turned off too")
    }

    @Test("turning sound off silences the ear")
    func soundCanBeTurnedOff() {
        let rig = rig(sound: false)
        for cue in FeedbackCue.allCases { rig.feedback.play(cue) }
        #expect(rig.ear.played.isEmpty)
        #expect(rig.touch.played.count == FeedbackCue.allCases.count)
    }

    @Test("both off means nothing at all")
    func bothCanBeTurnedOff() {
        let rig = rig(sound: false, haptics: false)
        rig.feedback.prepare()
        for cue in FeedbackCue.allCases { rig.feedback.play(cue) }
        #expect(rig.touch.played.isEmpty)
        #expect(rig.ear.played.isEmpty)
        #expect(!rig.touch.prepared, "the hardware was warmed up for a channel nobody asked for")
    }

    @Test("a preference survives the app being closed")
    func preferencesPersist() {
        let defaults = store()
        let first = Preferences(defaults: defaults)
        first.playsHaptics = false
        first.playsSound = false

        let second = Preferences(defaults: defaults)
        #expect(!second.playsHaptics)
        #expect(!second.playsSound)
    }

    @Test("both channels start on")
    func defaultsAreOn() {
        let preferences = Preferences(defaults: store())
        #expect(preferences.playsHaptics)
        #expect(preferences.playsSound)
    }

    // MARK: - The mapping

    @Test("the moments that matter have a cue, and the bookkeeping does not")
    func mappingCoversTheMoments() {
        let pawn = PawnID(seat: Seat(0), slot: 0)
        let other = PawnID(seat: Seat(1), slot: 0)
        let card = Card(rank: .seven, deckCopy: 0)

        #expect(FeedbackCue.cue(for: .cardPlayed(seat: Seat(0), card: card)) == .place)
        #expect(FeedbackCue.cue(for: .pawnEntered(pawn: pawn, at: .track(index: 0))) == .place)
        #expect(FeedbackCue.cue(for: .pawnReachedHome(pawn: pawn, slot: 0)) == .home)
        #expect(FeedbackCue.cue(for: .handFolded(seat: Seat(0), cardCount: 4)) == .fold)
        #expect(
            FeedbackCue.cue(for: .pawnCaptured(
                pawn: other, by: pawn,
                at: .track(index: 3), returnedTo: .waiting(seat: Seat(1), slot: 0)
            )) == .capture
        )

        // Things the screen says, which are not moments.
        #expect(FeedbackCue.cue(for: .turnPassed(to: Seat(1))) == nil)
        #expect(FeedbackCue.cue(for: .dealerChanged(to: Seat(1))) == nil)
        #expect(FeedbackCue.cue(for: .dealRoundStarted(roundIndex: 0, cycleIndex: 0, cardsPerSeat: 5)) == nil)
    }

    /// **A move is one moment, however many events it took.**
    ///
    /// A Seven split across two pieces produces a run of move events. Buzzing
    /// once a square would turn one decision into a stutter.
    @Test("a run of the same cue is one cue")
    func runsCollapse() {
        let pawn = PawnID(seat: Seat(0), slot: 0)
        let moves = (0..<7).map { index in
            GameEvent.pawnMoved(
                pawn: pawn,
                from: .track(index: index),
                to: .track(index: index + 1),
                path: [.track(index: index + 1)],
                backward: false
            )
        }
        #expect(FeedbackCue.cues(for: moves) == [.place])
    }

    /// A move that lands on somebody is a capture, not a landing followed by
    /// a capture.
    @Test("landing on somebody is one louder cue, not two")
    func captureAbsorbsTheLanding() {
        let pawn = PawnID(seat: Seat(0), slot: 0)
        let victim = PawnID(seat: Seat(1), slot: 2)
        let events: [GameEvent] = [
            .pawnMoved(
                pawn: pawn, from: .track(index: 1), to: .track(index: 4),
                path: [.track(index: 4)], backward: false
            ),
            .pawnCaptured(
                pawn: victim, by: pawn,
                at: .track(index: 4), returnedTo: .waiting(seat: Seat(1), slot: 2)
            ),
        ]
        #expect(FeedbackCue.cues(for: events) == [.capture])
    }

    @Test("a whole real turn produces a handful of cues, not a burst")
    func aRealTurnIsQuiet() throws {
        var state = GameState.newMatch(configuration: .standard(seatCount: 4), seed: 2026)
        var generator = SeededGenerator(seed: 99)
        var worst = 0

        for _ in 0..<80 where state.result == nil {
            let legal = MoveGenerator.legalMoves(in: state, for: state.currentSeat)
            let action: PlayerAction = legal.isEmpty
                ? .foldHand(seat: state.currentSeat)
                : .play(legal[Int.random(in: 0..<legal.count, using: &generator)])
            guard let next = try? GameReducer.apply(action, to: state) else { break }
            worst = max(worst, FeedbackCue.cues(for: next.events).count)
            state = next.state
        }
        #expect(worst > 0, "the walk produced no cues at all")
        #expect(worst <= 4, "one turn produced \(worst) separate cues, which is a stutter")
    }

    // MARK: - The sounds themselves

    /// **Every cue has a recording, and it is one we made.**
    ///
    /// The set is synthesised by `Tools/soundforge.py` and installed by
    /// `scripts/sounds-build.sh`: nothing sampled, nothing downloaded, no
    /// licence to wonder about (§77). A cue without a file is a moment that
    /// happens in silence while the others do not, which is worse than a game
    /// with no sound at all.
    @Test("every cue has a sound behind it")
    func everyCueHasASound() {
        let sounds = BundledSounds()
        for cue in FeedbackCue.allCases {
            #expect(sounds.hasAsset(for: cue), "\(cue.rawValue) has no recording")
        }
        #expect(Feedback(preferences: Preferences(defaults: store())).hasAnySound)
    }

    /// The file a cue looks for is the one the build script writes.
    @Test("a cue and its file agree on the name")
    func namesLineUp() {
        for cue in FeedbackCue.allCases {
            #expect(BundledSounds.fileName(for: cue) == "\(cue.rawValue).caf")
            #expect(SoundBank.shared.url(for: cue) != nil, "\(cue.rawValue).caf is not in the bundle")
        }
    }

    /// **A cue is short enough to be heard two hundred times.**
    ///
    /// Measured from the bundled file rather than trusted from the generator:
    /// what ships is what matters. The victory cue is allowed to be the long
    /// one; it is heard once a match.
    @Test("no cue outstays its welcome")
    func cuesAreShort() throws {
        for cue in FeedbackCue.allCases {
            let url = try #require(SoundBank.shared.url(for: cue))
            let player = try AVAudioPlayer(contentsOf: url)
            // The two musical cues are allowed to ring; a contact is not.
            let limit: Double
            switch cue {
            case .victory: limit = 2.0
            case .home: limit = 1.0
            default: limit = 0.6
            }
            #expect(
                player.duration <= limit,
                "\(cue.rawValue) runs \(String(format: "%.2f", player.duration))s"
            )
            #expect(player.duration > 0.01, "\(cue.rawValue) is empty")
        }
    }

    @Test("haptics stay quiet enough to play a whole match with")
    func hapticsAreRestrained() {
        for cue in FeedbackCue.allCases {
            #expect(cue.strength > 0 && cue.strength <= 0.85, "\(cue.rawValue) is too strong for an hour")
        }
        #expect(FeedbackCue.select.strength < FeedbackCue.capture.strength)
        #expect(FeedbackCue.capture.strength < FeedbackCue.victory.strength)
    }
}
