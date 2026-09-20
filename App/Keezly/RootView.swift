import KeezlyCore
import SwiftUI

/// The app's root scene.
///
/// **M4 in progress.** It starts a real four-player match — one human, three
/// computer opponents — so the board, the hand and the interaction can be
/// judged on device. The main menu, where the table is configured, arrives
/// later in M4; there are deliberately no controls here that do nothing.
struct RootView: View {
    @State private var session = MatchSession(
        configuration: .standard(seatCount: 4),
        seed: 2026,
        roles: [.human, .computer(.medium), .computer(.medium), .computer(.medium)]
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
