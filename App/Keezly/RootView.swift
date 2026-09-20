import KeezlyCore
import SwiftUI

/// The app's root scene.
///
/// **M4 in progress.** This currently renders the board for a real match state
/// so the geometry and visual design can be judged on device. It is not yet
/// interactive — the interaction flow arrives with M4.5 and M4.6, on top of the
/// event pipeline. There are deliberately no controls here that do nothing.
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// A real match, dealt by the real engine.
    private let state = GameState.newMatch(configuration: .standard(seatCount: 4), seed: 2026)

    private var isCompact: Bool { horizontalSizeClass == .compact }

    var body: some View {
        ZStack {
            Keezly.Palette.table.ignoresSafeArea()

            VStack(spacing: Keezly.Spacing.large) {
                Text(verbatim: "KEEZLY")
                    .font(Keezly.Typography.title(compact: isCompact))
                    .kerning(isCompact ? 6 : 9)
                    .foregroundStyle(Keezly.Palette.secondaryText)

                BoardView(
                    layout: BoardLayout(board: state.board),
                    pawns: state.pawns
                )
                .padding(isCompact ? Keezly.Spacing.small : Keezly.Spacing.large)
            }
            .padding(Keezly.Spacing.regular)
        }
    }
}

#Preview("iPhone") {
    RootView()
}

#Preview("iPad", traits: .landscapeLeft) {
    RootView()
}
