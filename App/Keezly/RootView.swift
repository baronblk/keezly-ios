import KeezlyCore
import SwiftUI

/// The app's root scene.
///
/// **Scaffolding.** This exists so the project builds, installs and launches
/// end to end while the rules engine is being finished. It is deliberately
/// inert: no buttons that do nothing, no menu entries that lead nowhere.
///
/// M4.1 replaces this entirely with the real main menu and board. Tracked in
/// `ROADMAP.md`; do not grow this file into a placeholder UI.
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRegularWidth: Bool { horizontalSizeClass == .regular }

    var body: some View {
        ZStack {
            Color.launchBackground.ignoresSafeArea()

            VStack(spacing: isRegularWidth ? 20 : 14) {
                Text(verbatim: "KEEZLY")
                    .font(.system(size: isRegularWidth ? 68 : 44, weight: .semibold, design: .rounded))
                    .kerning(isRegularWidth ? 14 : 9)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)

                Text(verbatim: "Keezenspel")
                    .font(isRegularWidth ? .title3 : .callout)
                    .foregroundStyle(.secondary)

                Text(verbatim: "\(Self.version) · Development build")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            }
            .padding()
            .multilineTextAlignment(.center)
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(marketing) (\(build))"
    }
}

private extension Color {
    /// Matches the launch screen colour so there is no flash at startup.
    static let launchBackground = Color("LaunchBackground")
}

#Preview("iPhone") {
    RootView()
}

#Preview("iPad", traits: .landscapeLeft) {
    RootView()
}
