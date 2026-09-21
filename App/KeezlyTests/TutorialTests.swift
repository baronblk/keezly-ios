@testable import Keezly
import KeezlyCore
import Testing

/// §52 — a tutorial that congratulates a player for something they did not do
/// teaches them the wrong game.
///
/// Two things are tested here, and they are the two things that can be faked.
/// First, that every lesson's position is genuinely reached by playing — a
/// lesson whose board never arrives would otherwise ship as a screen that
/// quietly asks the impossible. Second, that a goal is met by the move it
/// names and by nothing else.
@Suite("Tutorial")
@MainActor
struct TutorialTests {

    // MARK: - The lessons are real

    /// **Every lesson reaches the position it teaches from.**
    ///
    /// Played through the real reducer from the lesson's own seed, exactly as
    /// the app does when the player opens it. A seed that stops working — after
    /// a rule change, a deal change, anything — fails here rather than in
    /// somebody's hands.
    @Test("every lesson sets up the board it needs", arguments: Tutorial.lessons)
    func everyLessonArrives(lesson: Lesson) throws {
        let run = TutorialRun(index: try #require(Tutorial.lessons.firstIndex(of: lesson)))
        #expect(run.lesson == lesson)
        #expect(
            run.progress != .unavailable,
            "lesson '\(lesson.id)' could not reach its position from seed \(lesson.seed)"
        )
        if lesson.fixture != nil {
            #expect(run.session.fixtureReached == true, "lesson '\(lesson.id)' missed its fixture")
        }
    }

    /// A lesson with something to do must open with that something available.
    @Test("a lesson that asks for a move opens with that move on offer", arguments: Tutorial.lessons)
    func askedForMoveIsAvailable(lesson: Lesson) throws {
        guard lesson.goal != .read else { return }
        let run = TutorialRun(index: try #require(Tutorial.lessons.firstIndex(of: lesson)))
        let seat = try #require(run.session.localSeat)

        #expect(run.session.state.currentSeat == seat, "lesson '\(lesson.id)' does not open on the player's turn")
        #expect(
            lesson.goal.isStillPossible(in: run.session.state, for: seat),
            "lesson '\(lesson.id)' opens with no way to do what it asks"
        )
    }

    /// **And doing it actually satisfies the lesson.**
    ///
    /// Not asserted from the goal's own logic but by playing: the move is put
    /// through `GameReducer`, and the lesson is asked about the two boards.
    @Test("playing what the lesson asks for satisfies it", arguments: Tutorial.lessons)
    func doingItCounts(lesson: Lesson) throws {
        guard lesson.goal != .read else { return }
        let run = TutorialRun(index: try #require(Tutorial.lessons.firstIndex(of: lesson)))
        let seat = try #require(run.session.localSeat)
        let before = run.session.state

        let satisfying = PlayerObservation(of: before, for: seat).legalMoves.first { move in
            guard let next = try? GameReducer.apply(.play(move), to: before) else { return false }
            return lesson.goal.isMet(by: .play(move), before: before, after: next.state)
        }
        let move = try #require(satisfying, "no legal move satisfies lesson '\(lesson.id)'")
        let after = try GameReducer.apply(.play(move), to: before)

        run.record(.play(move), before: before, after: after.state)
        #expect(run.progress == .met, "lesson '\(lesson.id)' did not notice its own goal being met")
        #expect(run.completed.contains(lesson.id))
    }

    @Test("the lessons are distinct and cover the cards that surprise people")
    func lessonsAreWellFormed() {
        let ids = Tutorial.lessons.map(\.id)
        #expect(Set(ids).count == ids.count, "two lessons share an identifier")
        #expect(Tutorial.lessons.count == 10)

        let goals = Set(Tutorial.lessons.map(\.goal))
        for required in [LessonGoal.bringAPawnOut, .moveAPawnBackward, .splitASeven, .swapWithAJack, .reachHome] {
            #expect(goals.contains(required), "no lesson teaches \(required)")
        }
    }

    @Test("every lesson has real text in every part it shows")
    func lessonTextExists() {
        for lesson in Tutorial.lessons {
            #expect(!lesson.title.hasPrefix("lesson."), "\(lesson.id) shows its title key")
            #expect(!lesson.body.hasPrefix("lesson."), "\(lesson.id) shows its body key")
            #expect(lesson.body.count > 60, "\(lesson.id) explains too little to be a lesson")
            if lesson.goal == .read {
                #expect(lesson.task == nil)
            } else {
                let task = lesson.task
                #expect(task?.hasPrefix("lesson.") == false, "\(lesson.id) shows its task key")
            }
        }
    }

    // MARK: - A goal is met by its own move and no other

    @Test("a goal is not met by a different legal move")
    func otherMovesDoNotCount() throws {
        let state = GameState.newMatch(configuration: .standard(seatCount: 4), seed: 2026)
        let seat = state.currentSeat
        let entering = try #require(
            MoveGenerator.legalMoves(in: state, for: seat).first { move in
                if case .enterFromWaiting = move.action { return true }
                return false
            }
        )
        let after = try GameReducer.apply(.play(entering), to: state)

        #expect(LessonGoal.bringAPawnOut.isMet(by: .play(entering), before: state, after: after.state))
        // The same move must not satisfy every other lesson.
        for goal in [
            LessonGoal.moveAPawnForward, .moveAPawnBackward, .splitASeven,
            .swapWithAJack, .knockAPawnOut, .reachHome, .read,
        ] {
            #expect(
                !goal.isMet(by: .play(entering), before: state, after: after.state),
                "bringing a pawn out counted as \(goal)"
            )
        }
    }

    /// Throwing in a dead hand is a legal action and is never a lesson's goal.
    @Test("folding never satisfies a lesson")
    func foldingIsNeverTheAnswer() {
        let state = GameState.newMatch(configuration: .standard(seatCount: 4), seed: 2026)
        let fold = PlayerAction.foldHand(seat: state.currentSeat)
        for goal in [
            LessonGoal.read, .bringAPawnOut, .moveAPawnForward, .moveAPawnBackward,
            .splitASeven, .swapWithAJack, .knockAPawnOut, .reachHome,
        ] {
            #expect(!goal.isMet(by: fold, before: state, after: state))
        }
    }

    /// A Seven played on one pawn is legal, and is not the Seven lesson.
    @Test("a seven spent on one pawn does not count as splitting it")
    func singleLegSevenIsNotASplit() throws {
        let run = TutorialRun(index: try #require(Tutorial.lessons.firstIndex { $0.id == "seven" }))
        let seat = try #require(run.session.localSeat)
        let state = run.session.state

        let whole = MoveGenerator.legalMoves(in: state, for: seat).first { move in
            guard case .split(let steps) = move.action else { return false }
            return steps.count == 1
        }
        guard let whole else { return }
        let after = try GameReducer.apply(.play(whole), to: state)
        #expect(!LessonGoal.splitASeven.isMet(by: .play(whole), before: state, after: after.state))
    }

    // MARK: - Getting about

    @Test("a lesson can be skipped, repeated and left")
    func navigationWorks() {
        let run = TutorialRun()
        let first = run.lesson.id

        run.skip()
        #expect(run.lesson.id != first, "skipping stayed on the same lesson")
        #expect(!run.completed.contains(run.lesson.id), "skipping counted as finishing")

        let before = ObjectIdentifier(run.session)
        run.restartLesson()
        #expect(ObjectIdentifier(run.session) != before, "restarting reused the old board")
        #expect(run.progress != .met)

        run.go(to: Tutorial.lessons.count - 1)
        #expect(run.isLast)
        run.advance()
        #expect(run.isLast, "advancing past the last lesson moved somewhere")
    }

    /// A reading lesson finishes when the player says so, and only then.
    @Test("a reading lesson is finished by the reader")
    func readingLessonsAreAcknowledged() throws {
        let index = try #require(Tutorial.lessons.firstIndex { $0.goal == .read })
        let run = TutorialRun(index: index)
        #expect(run.progress == .open)
        run.acknowledge()
        #expect(run.progress == .met)
        #expect(run.completed.contains(run.lesson.id))
    }

    /// A tutorial match is never written to disk.
    @Test("a lesson does not turn up in the player's saved matches")
    func lessonsAreNotSaved() {
        #expect(TutorialRun().session.store == nil)
    }
}
