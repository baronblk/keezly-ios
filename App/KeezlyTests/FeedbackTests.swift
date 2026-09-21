@testable import Keezly
import Foundation
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

    // MARK: - Sound is not here yet

    /// **ASSET PENDING**, said out loud rather than implied by silence.
    @Test("the shipped sound channel has no recordings behind it")
    func soundIsPending() {
        let sounds = BundledSounds()
        for cue in FeedbackCue.allCases {
            #expect(!sounds.hasAsset(for: cue), "\(cue.rawValue) has an asset — update this test and the docs")
        }
        #expect(!Feedback(preferences: Preferences(defaults: store())).hasAnySound)
        // And the place a recording would go is named, so adding one is a
        // matter of dropping a file in rather than finding the code.
        #expect(BundledSounds.fileName(for: .capture) == "capture.caf")
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
