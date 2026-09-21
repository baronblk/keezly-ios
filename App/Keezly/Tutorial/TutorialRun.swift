import KeezlyCore
import Observation

/// How a lesson is going.
enum LessonProgress: Hashable, Sendable {
    /// Still asking.
    case open
    /// The player did the thing. Said because it happened, not because they
    /// tapped something.
    case met
    /// The board has moved past the point where the lesson is possible — the
    /// player played something else legal, or the opponents did. Not a
    /// failure, and not hidden either: the lesson offers to set itself up
    /// again.
    case impossible
    /// The lesson's position could not be reached from its seed at all. A bug
    /// in the lesson rather than in the play, and said as one.
    case unavailable
}

/// A run through the tutorial.
///
/// Each lesson is an ordinary match: the real engine, the real move generator,
/// the real opponents. Nothing is scripted and no move is forced — the player
/// can play anything the board allows, and the lesson simply watches to see
/// whether what they played is what it asked for (§52).
///
/// That is the whole design. A tutorial that only accepts one tap teaches the
/// tap; one that plays the game teaches the game.
@Observable
@MainActor
final class TutorialRun {
    private(set) var index: Int
    private(set) var session: MatchSession
    private(set) var progress: LessonProgress

    /// Lessons finished in this run, so returning to one already done does not
    /// lose the fact.
    private(set) var completed: Set<String> = []

    var lesson: Lesson { Tutorial.lessons[index] }
    var isLast: Bool { index == Tutorial.lessons.count - 1 }

    init(index: Int = 0) {
        let start = min(max(0, index), Tutorial.lessons.count - 1)
        self.index = start
        let lesson = Tutorial.lessons[start]
        let opened = Self.session(for: lesson)
        session = opened
        progress = Self.opening(lesson, in: opened)
    }

    // MARK: - Watching

    /// Called with an action the engine has already accepted.
    ///
    /// - Parameters:
    ///   - before: the board the player was looking at.
    ///   - after: the board their move produced.
    func record(_ action: PlayerAction, before: GameState, after: GameState) {
        guard progress == .open else { return }
        if lesson.goal.isMet(by: action, before: before, after: after) {
            progress = .met
            completed.insert(lesson.id)
        }
    }

    /// Called when the board has settled — after the opponents have replied.
    ///
    /// The lesson can become impossible without the player doing anything
    /// wrong: a Jack's target is knocked out, the pawn that was one square
    /// from home is sent back. Checked here so the tutorial notices at the
    /// same moment the player would.
    func boardSettled() {
        guard progress == .open, let seat = session.localSeat else { return }
        guard !lesson.goal.isStillPossible(in: session.state, for: seat) else { return }
        progress = .impossible
    }

    // MARK: - Moving about

    func restartLesson() {
        session = Self.session(for: lesson)
        progress = Self.opening(lesson, in: session)
    }

    /// Marks a reading lesson as read.
    func acknowledge() {
        guard lesson.goal == .read else { return }
        completed.insert(lesson.id)
        progress = .met
    }

    func advance() {
        go(to: index + 1)
    }

    /// Leaves this lesson for the next one without doing it.
    ///
    /// Offered on purpose. Somebody who already knows what a Four does should
    /// not have to demonstrate it to reach the Seven, and a tutorial with no
    /// way out is one people abandon at the point they got stuck (§52).
    func skip() {
        go(to: index + 1)
    }

    func go(to next: Int) {
        guard Tutorial.lessons.indices.contains(next) else { return }
        index = next
        session = Self.session(for: lesson)
        progress = Self.opening(lesson, in: session)
    }

    // MARK: - Building a lesson

    private static func session(for lesson: Lesson) -> MatchSession {
        MatchSession(
            configuration: lesson.configuration,
            seed: lesson.seed,
            // Easy opponents: the tutorial is about the rules, and a strong
            // opponent taking the lesson's pawn is a distraction, not a
            // challenge.
            roles: [.human] + Array(repeating: SeatRole.computer(.easy), count: lesson.seats - 1),
            fixture: lesson.fixture,
            // Never written to disk. A tutorial is not a match somebody wants
            // to find waiting for them in the menu (DEC-023).
            store: nil
        )
    }

    private static func opening(_ lesson: Lesson, in session: MatchSession) -> LessonProgress {
        if session.fixtureReached == false { return .unavailable }
        guard lesson.goal != .read, let seat = session.localSeat else { return .open }
        return lesson.goal.isStillPossible(in: session.state, for: seat) ? .open : .unavailable
    }
}
