import SwiftUI

/// The two switches Keezly has.
///
/// Small on purpose. Everything else the app does is either a rule (which
/// belongs to the table, not to a preferences screen) or a system setting like
/// text size and Reduce Motion, which Keezly reads rather than duplicates.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var preferences: Preferences
    /// Whether any sound has a recording behind it yet.
    let hasSound: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("settings.haptics", isOn: $preferences.playsHaptics)
                        .accessibilityIdentifier("settings.haptics")
                } footer: {
                    Text("settings.haptics.detail")
                }

                Section {
                    Toggle("settings.sound", isOn: $preferences.playsSound)
                        .disabled(!hasSound)
                        .accessibilityIdentifier("settings.sound")
                } footer: {
                    // Said plainly. A switch that governs nothing, with no
                    // explanation, is worse than an honest sentence (§36).
                    Text(hasSound ? "settings.sound.detail" : "settings.sound.pending")
                }
            }
            .navigationTitle(Text("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("settings")
    }
}
