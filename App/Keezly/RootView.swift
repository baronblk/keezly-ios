import KeezlyCore
import SwiftUI

/// The app's root scene.
///
/// The menu is where a match begins or is picked up again; the board replaces
/// it once there is a match. A deterministic run — a UI test or a screenshot —
/// goes straight to the board instead, so the captures stay reproducible and
/// the tests do not have to drive the menu to reach the game (§87).
struct RootView: View {
    private let theme = BoardTheme.classicWood

    @State private var table = TableConfiguration()
    @State private var session: MatchSession?
    @State private var resumable: MatchSummary?
    /// Why the last attempt to continue a match failed. Shown rather than
    /// swallowed: a match that will not open is something the player is
    /// entitled to know about (§57).
    @State private var restoreFailure: String?
    /// A run through the tutorial, when one is going on.
    @State private var tutorial: TutorialRun?
    /// Whether to offer the tutorial first. Answered once, on the first match
    /// or lesson, and never asked again.
    @State private var welcome = Welcome()
    /// Sound and haptics, owned here so one match cannot disagree with the
    /// next about what the player asked for.
    @State private var preferences = Preferences()
    /// A match being watched back, when one is.
    @State private var replay: ReplayRun?
    /// Every match on the device, refreshed when the menu appears.
    @State private var matches: [MatchSummary] = []

    private let store: MatchStore?
    /// Game Center, for the achievements a finished match earned. `nil` in a
    /// deterministic run, which must not put a sign-in sheet over the board.
    private let achievements: (any AchievementReporting)?

    init() {
        // Before anything reads a preference or lists a match. Does nothing
        // unless the app was launched with `-KEEZLY_UI_TEST_RESET_STATE YES`,
        // which no shipping build ever is.
        ScreenshotMode.resetStateIfRequested()

        // A deterministic run keeps its matches out of the real store: a test
        // must not overwrite a player's saved game, and its own matches must
        // not turn up in the list.
        store = ScreenshotMode.isActive ? nil : MatchStore()
        achievements = GameCenterAchievements.isEnabled ? GameCenterAchievements() : nil

        if ScreenshotMode.isActive, ScreenshotMode.showsReplay {
            // A whole match, played out, then handed to the replay.
            let played = MatchSession(
                configuration: ScreenshotMode.configuration,
                seed: ScreenshotMode.seed,
                roles: ScreenshotMode.roles,
                fixture: .movesPlayed(900)
            )
            _replay = State(initialValue: ReplayRun(record: played.record, roles: played.roles))
        } else if ScreenshotMode.isActive {
            _session = State(initialValue: MatchSession(
                configuration: ScreenshotMode.configuration,
                seed: ScreenshotMode.seed,
                roles: ScreenshotMode.roles,
                fixture: ScreenshotMode.fixture
            ))
        }
    }

    var body: some View {
        Group {
            if let replay {
                ReplayScreen(replay: replay, onLeave: { self.replay = nil })
                    .id(ObjectIdentifier(replay))
            } else if let tutorial {
                // The ordinary playing screen, with a lesson watching. Rebuilt
                // per lesson, because each one is its own match.
                GameScreen(
                    session: tutorial.session,
                    onLeave: leaveTutorial,
                    tutorial: tutorial,
                    preferences: preferences
                )
                .id(ObjectIdentifier(tutorial.session))
            } else if let session {
                GameScreen(session: session, onLeave: leaveMatch, preferences: preferences)
                    // Identity by the session, so starting a different table
                    // builds a new screen rather than reusing the old one's
                    // state against a board of another size.
                    .id(ObjectIdentifier(session))
            } else {
                MainMenuView(
                    table: $table,
                    resumable: resumable,
                    restoreFailure: restoreFailure,
                    onStart: start,
                    onContinue: resume,
                    onTutorial: {
                        welcome.noteStarted()
                        tutorial = TutorialRun()
                    },
                    isNewcomer: welcome.isNewcomer,
                    preferences: preferences,
                    hasSound: Feedback(preferences: preferences).hasAnySound,
                    matches: matches,
                    onWatch: watch,
                    onOpen: open
                )
                .task {
                    refreshResumable()
                    // Asked for once, when the menu appears rather than at
                    // launch: a sign-in sheet over a cold start is the first
                    // thing a new player would see, and Keezly has nothing
                    // that needs it.
                    achievements?.start()
                }
            }
        }
        .environment(\.boardTheme, theme)
        // Only ever set by a deterministic run. A pane is how the app is drawn
        // in Split View and in a resized Stage Manager window, and those sizes
        // are otherwise unreachable from a test.
        .modifier(PaneConstraint(size: ScreenshotMode.pane))
    }

    private func refreshResumable() {
        matches = store?.list() ?? []
        resumable = matches.first { $0.status == .active }
    }

    /// Opens a finished match to be watched back.
    ///
    /// Restored through the same validated path as playing one: a match that
    /// will not replay is not one to watch either (DEC-023).
    private func watch(_ summary: MatchSummary) {
        guard let store else { return }
        do {
            let restored = try store.restore(matchID: summary.matchID)
            replay = ReplayRun(record: restored.record, roles: restored.roles)
            restoreFailure = nil
        } catch {
            store.quarantine(matchID: summary.matchID)
            restoreFailure = error.localizedDescription
            refreshResumable()
        }
    }

    /// Picks a particular match up, rather than the most recent one.
    private func open(_ summary: MatchSummary) {
        guard let store else { return }
        do {
            session = MatchSession(
                restored: try store.restore(matchID: summary.matchID),
                store: store,
                achievements: achievements
            )
            restoreFailure = nil
        } catch {
            store.quarantine(matchID: summary.matchID)
            restoreFailure = error.localizedDescription
            refreshResumable()
        }
    }

    private func start() {
        welcome.noteStarted()
        restoreFailure = nil
        session = MatchSession(
            configuration: table.gameConfiguration,
            seed: SeededGenerator.systemSeeded().state,
            roles: table.roles,
            store: store,
            achievements: achievements
        )
    }

    /// Picks up the saved match, or says why it cannot.
    ///
    /// A failure moves the file aside rather than deleting it: the save is the
    /// only evidence of what went wrong, and the player still gets a working
    /// menu (§57).
    private func resume() {
        guard let store, let summary = resumable else { return }
        do {
            let restored = try store.restore(matchID: summary.matchID)
            session = MatchSession(restored: restored, store: store, achievements: achievements)
            restoreFailure = nil
        } catch {
            store.quarantine(matchID: summary.matchID)
            restoreFailure = error.localizedDescription
            refreshResumable()
        }
    }

    private func leaveMatch() {
        session = nil
        refreshResumable()
    }

    private func leaveTutorial() {
        tutorial = nil
        refreshResumable()
    }
}

/// Draws the app into a pane of a fixed size, centred on a dark surround, so a
/// capture shows exactly what a Split View pane would.
private struct PaneConstraint: ViewModifier {
    let size: CGSize?

    func body(content: Content) -> some View {
        if let size {
            ZStack {
                Color.black.ignoresSafeArea()
                content
                    .frame(width: size.width, height: size.height)
                    .clipped()
            }
        } else {
            content
        }
    }
}

#Preview("Menu") {
    RootView()
}
