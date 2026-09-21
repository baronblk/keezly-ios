import KeezlyCore

/// What a lesson asks the player to do.
///
/// Every case is decided by comparing the board before the move with the board
/// after it — an observation of what the engine did, never a second opinion
/// about what is legal (DEC-004). A lesson cannot therefore congratulate a
/// player for something that did not happen, which is the one thing a tutorial
/// must never do.
enum LessonGoal: Hashable, Sendable {
    /// Nothing to play. The board is there to be looked at while the point is
    /// explained, and the player moves on when they are ready.
    case read
    case bringAPawnOut
    case moveAPawnForward
    case moveAPawnBackward
    case splitASeven
    case swapWithAJack
    case knockAPawnOut
    case reachHome

    /// Whether the move just played is the thing the lesson asked for.
    func isMet(by action: PlayerAction, before: GameState, after: GameState) -> Bool {
        guard case .play(let move) = action else { return false }

        switch self {
        case .read:
            return false
        case .bringAPawnOut:
            if case .enterFromWaiting = move.action { return true }
            return false
        case .moveAPawnForward:
            if case .advance = move.action { return true }
            return false
        case .moveAPawnBackward:
            if case .moveBackward = move.action { return true }
            return false
        case .splitASeven:
            // A Seven spent on one pawn is a legal move and not this lesson:
            // the point is the split.
            if case .split(let steps) = move.action { return steps.count > 1 }
            return false
        case .swapWithAJack:
            if case .swap = move.action { return true }
            return false
        case .knockAPawnOut:
            return Self.sentHome(before: before, after: after).contains { $0.seat != move.seat }
        case .reachHome:
            return after.pawns(of: move.seat).count(where: \.isHome)
                > before.pawns(of: move.seat).count(where: \.isHome)
        }
    }

    /// Pawns that were on the board and are back in a start area.
    ///
    /// Read off the two positions rather than from an event, so it is true of
    /// whatever the engine actually did — including a capture that came about
    /// as the second leg of a Seven.
    private static func sentHome(before: GameState, after: GameState) -> [PawnID] {
        zip(before.pawns, after.pawns)
            .filter { !$0.0.isWaiting && $0.1.isWaiting }
            .map(\.1.id)
    }

    /// Whether this goal can still be reached in this position.
    ///
    /// A tutorial that lets a player wander into a board where the lesson is
    /// impossible and then says nothing is worse than one with no lessons.
    func isStillPossible(in state: GameState, for seat: Seat) -> Bool {
        guard case .read = self else {
            guard state.result == nil else { return false }
            let observation = PlayerObservation(of: state, for: seat)
            return observation.previewAll().contains { candidate in
                guard let next = try? GameReducer.apply(.play(candidate.move), to: state) else { return false }
                return isMet(by: .play(candidate.move), before: state, after: next.state)
            }
        }
        return true
    }
}

/// One lesson: a real position, a real task.
///
/// The board is reached by *playing* from a seed, so it is a position the game
/// can actually produce (§87). Nothing here is staged — the pieces stand where
/// a real sequence of legal moves put them.
struct Lesson: Identifiable, Hashable, Sendable {
    let id: String
    let seats: Int
    let teams: Bool
    let seed: UInt64
    /// How the board is brought to the teaching position, by playing to it.
    let fixture: MatchFixture?
    let goal: LessonGoal

    init(
        _ id: String,
        seats: Int = 4,
        teams: Bool = true,
        seed: UInt64,
        fixture: MatchFixture? = nil,
        goal: LessonGoal
    ) {
        self.id = id
        self.seats = seats
        self.teams = teams
        self.seed = seed
        self.fixture = fixture
        self.goal = goal
    }

    var title: String { Rulebook.text("lesson.\(id).title") }
    /// What the player is being shown.
    var body: String { Rulebook.text("lesson.\(id).body") }
    /// What they have to do about it, when there is something.
    var task: String? {
        guard goal != .read else { return nil }
        return Rulebook.text("lesson.\(id).task")
    }

    var configuration: GameConfiguration {
        GameConfiguration(seatCount: seats, teamMode: teams ? .teamsOfTwo : .freeForAll)
    }
}

/// The lessons, in the order they teach.
///
/// Ten, deliberately: enough to cover every card that behaves unusually and the
/// two rules — the protected start and the forced move — that surprise a new
/// player most. Each seed is checked by `TutorialTests`, which plays every
/// lesson to its position and refuses a lesson whose board cannot be reached.
enum Tutorial {
    static let lessons: [Lesson] = [
        // Nothing to do but look: the shape of the board, and where a pawn is
        // trying to get to.
        Lesson("goal", seed: 2026, goal: .read),
        // The gate. Everything else waits on this one.
        Lesson("entering", seed: 2026, fixture: .localCanPlay(.king), goal: .bringAPawnOut),
        Lesson("moving", seed: 9001, fixture: .localCanPlay(.five), goal: .moveAPawnForward),
        // Read, not played: the lesson is what a protected pawn *stops*, and
        // asking somebody to demonstrate being blocked is asking them to fail.
        Lesson("protection", seed: 4412, fixture: .movesPlayed(24), goal: .read),
        Lesson("capture", seed: 7781, fixture: .localCanCapture, goal: .knockAPawnOut),
        Lesson("four", seed: 5150, fixture: .localCanPlay(.four), goal: .moveAPawnBackward),
        Lesson("seven", seed: 2026, fixture: .localCanPlay(.seven), goal: .splitASeven),
        Lesson("jack", seed: 2026, fixture: .localCanPlay(.jack), goal: .swapWithAJack),
        Lesson("home", seed: 3300, fixture: .localCanReachHome, goal: .reachHome),
        // Last, because it is about the other three seats rather than the
        // pieces, and only makes sense once the pieces do.
        Lesson("teams", seed: 6120, fixture: .movesPlayed(40), goal: .read),
    ]

    static func lesson(at index: Int) -> Lesson? {
        Tutorial.lessons.indices.contains(index) ? Tutorial.lessons[index] : nil
    }
}
