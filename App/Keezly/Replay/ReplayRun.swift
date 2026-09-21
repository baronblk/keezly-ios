import Foundation
import KeezlyCore
import Observation

/// How fast a replay plays itself.
enum ReplaySpeed: Double, CaseIterable, Identifiable, Hashable, Sendable {
    case slow = 1.6
    case normal = 0.8
    case fast = 0.3

    var id: Double { rawValue }
    /// Seconds between steps.
    var interval: Double { rawValue }
    var label: String { Rulebook.text("replay.speed.\(name)") }

    private var name: String {
        switch self {
        case .slow: "slow"
        case .normal: "normal"
        case .fast: "fast"
        }
    }
}

/// A finished or abandoned match, played back.
///
/// Built on the same two things a saved match is: the seed and the accepted
/// actions (DEC-023). Nothing extra is stored to make replay possible, because
/// a record that can be replayed *is* the replay — and a second representation
/// would be a second thing that can disagree with the first.
///
/// **A replay never writes.** It holds a copy of the record, recomputes states
/// from it, and has no `MatchStore` at all. Watching a match back cannot
/// change it, cannot finish it, and cannot move it in the list.
@Observable
@MainActor
final class ReplayRun {
    /// The record being watched. A copy: the original is on disk and stays
    /// exactly as it was.
    let record: MatchRecord
    let roles: [SeatRole]

    /// How many actions have been applied, from 0 (the opening deal) to the
    /// whole record.
    private(set) var step: Int
    /// The board at `step`.
    private(set) var state: GameState
    /// The events the last step produced, for the board to animate.
    private(set) var lastEvents: [GameEvent] = []

    private(set) var isPlaying = false
    var speed: ReplaySpeed = .normal

    /// The opening position, and positions noted along the way.
    ///
    /// **Measured before it was built.** Stepping backwards has to rebuild
    /// from an earlier position, because the engine has no inverse. Rebuilding
    /// from the opening every time costs about 0.07 ms per action, which on a
    /// finished six-player match of 810 actions came to **59 ms a step** — four
    /// frames of waiting for a button press, measured by `ReplayTests` in a
    /// debug build. That is the number that justifies this; without it a
    /// checkpoint scheme would have been a guess.
    ///
    /// These are a *cache of the same computation*, held in memory and thrown
    /// away with the screen. Nothing extra is written to disk, so there is no
    /// second representation of the match that could disagree with the record
    /// (DEC-023).
    private let opening: GameState
    /// Every `checkpointStride` positions, as the replay first passes them.
    private var checkpoints: [Int: GameState] = [:]
    /// Chosen from the measurement: at 0.07 ms an action, 64 actions is about
    /// 4 ms, comfortably inside a frame even on the longest match.
    private static let checkpointStride = 64

    init(record: MatchRecord, roles: [SeatRole]) {
        self.record = record
        self.roles = roles
        opening = record.initialState
        state = opening
        step = 0
    }

    var stepCount: Int { record.actionCount }
    var isAtStart: Bool { step == 0 }
    var isAtEnd: Bool { step >= stepCount }
    var progress: Double { stepCount == 0 ? 1 : Double(step) / Double(stepCount) }

    // MARK: - Moving about

    /// Applies the next action, if there is one.
    @discardableResult
    func next() -> Bool {
        guard step < stepCount else {
            isPlaying = false
            return false
        }
        guard let transition = try? GameReducer.apply(record.actions[step], to: state) else {
            // A record that will not replay is a record that should never have
            // been written. Stopping is the honest response: the alternative
            // is showing a board that does not follow from the one before it.
            isPlaying = false
            return false
        }
        state = transition.state
        lastEvents = transition.events
        step += 1
        if step.isMultiple(of: Self.checkpointStride) {
            checkpoints[step] = state
        }
        return true
    }

    /// Goes back one action.
    ///
    /// Recomputed from an earlier position rather than undone, because the
    /// engine has no inverse and inventing one would be a second
    /// implementation of the rules (DEC-004).
    func previous() {
        goTo(step: step - 1)
    }

    /// Jumps to an exact point.
    func goTo(step target: Int) {
        let clamped = min(max(0, target), stepCount)
        // Forwards from here is cheaper than starting again, and is what
        // scrubbing right does.
        if clamped >= step {
            while step < clamped, next() {}
            return
        }

        // Back to the nearest position already worked out, then forward.
        let nearest = checkpoints.keys.filter { $0 <= clamped }.max() ?? 0
        var rebuilt = nearest == 0 ? opening : (checkpoints[nearest] ?? opening)
        for index in (nearest == 0 ? 0 : nearest)..<clamped {
            guard let transition = try? GameReducer.apply(record.actions[index], to: rebuilt) else { break }
            rebuilt = transition.state
        }
        state = rebuilt
        step = clamped
        lastEvents = []
    }

    func restart() {
        isPlaying = false
        goTo(step: 0)
    }

    func end() {
        isPlaying = false
        goTo(step: stepCount)
    }

    // MARK: - Playing

    func play() {
        guard !isAtEnd else { return }
        isPlaying = true
    }

    func pause() {
        isPlaying = false
    }

    func togglePlaying() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    /// One tick of the playback clock. Driven by the view, so there is no
    /// timer inside the model to leak.
    func tick() {
        guard isPlaying else { return }
        if !next() { isPlaying = false }
    }
}
