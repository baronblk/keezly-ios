import KeezlyCore
import SwiftUI

/// The app's root scene.
///
/// **M4 in progress.** It starts a real four-player match — one human, three
/// computer opponents — so the board, the hand and the interaction can be
/// judged on device. The main menu, where the table is configured, arrives
/// later in M4; there are deliberately no controls here that do nothing.
struct RootView: View {
    // The table comes from ScreenshotMode so a UI test or a screenshot run can
    // ask for a specific seat count and seed. Outside such a run it returns the
    // ordinary four-player defaults (§87).
    @State private var session = MatchSession(
        configuration: ScreenshotMode.configuration,
        seed: ScreenshotMode.seed,
        roles: ScreenshotMode.roles
    )

    var body: some View {
        GameScreen(session: session)
    }
}

#Preview("iPhone") {
    RootView()
}

#Preview("iPad", traits: .landscapeLeft) {
    RootView()
}
