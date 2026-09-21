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

    private let store: MatchStore?

    init() {
        // A deterministic run keeps its matches out of the real store: a test
        // must not overwrite a player's saved game, and its own matches must
        // not turn up in the list.
        store = ScreenshotMode.isActive ? nil : MatchStore()

        if ScreenshotMode.isActive {
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
            if let tutorial {
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
                    hasSound: Feedback(preferences: preferences).hasAnySound
                )
                .task { refreshResumable() }
            }
        }
        .environment(\.boardTheme, theme)
    }

    private func refreshResumable() {
        resumable = store?.mostRecentActive()
    }

    private func start() {
        welcome.noteStarted()
        restoreFailure = nil
        session = MatchSession(
            configuration: table.gameConfiguration,
            seed: SeededGenerator.systemSeeded().state,
            roles: table.roles,
            store: store
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
            session = MatchSession(restored: restored, store: store)
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

#Preview("Menu") {
    RootView()
}
