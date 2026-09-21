import KeezlyCore
import SwiftUI

/// The app's root scene.
///
/// The menu is where a match begins; the board replaces it once a table has
/// been set up. A deterministic run — a UI test or a screenshot — goes straight
/// to the board instead, so the captures stay reproducible and the tests do not
/// have to drive the menu to reach the game (§87).
struct RootView: View {
    private let theme = BoardTheme.classicWood

    @State private var table = TableConfiguration()
    @State private var session: MatchSession?

    init() {
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
            if let session {
                GameScreen(session: session)
                    // Identity by the table, so starting a different table
                    // builds a new screen rather than reusing the old one's
                    // state against a board of another size.
                    .id(ObjectIdentifier(session))
            } else {
                MainMenuView(table: $table, onStart: start)
            }
        }
        .environment(\.boardTheme, theme)
    }

    private func start() {
        session = MatchSession(
            configuration: table.gameConfiguration,
            seed: SeededGenerator.systemSeeded().state,
            roles: table.roles
        )
    }
}

#Preview("Menu") {
    RootView()
}
