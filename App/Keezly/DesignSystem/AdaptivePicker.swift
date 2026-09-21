import SwiftUI

extension View {
    /// A picker that stays readable at every text size.
    ///
    /// A segmented control caps how far its labels will grow, so at the
    /// accessibility sizes it ends up as small text inside a very large
    /// layout — the one control on the screen that ignored the setting. A menu
    /// picker honours it, at the cost of a tap to open. That trade is the
    /// right way round: somebody who has asked for large text has asked for
    /// large text (§53).
    func tableFieldPicker(accessibilitySize: Bool) -> some View {
        modifier(TableFieldPicker(accessibilitySize: accessibilitySize))
    }
}

private struct TableFieldPicker: ViewModifier {
    let accessibilitySize: Bool

    func body(content: Content) -> some View {
        if accessibilitySize {
            // The field above it already says what is being chosen, so the
            // picker shows only the choice.
            content.pickerStyle(.menu).labelsHidden()
        } else {
            content.pickerStyle(.segmented)
        }
    }
}
