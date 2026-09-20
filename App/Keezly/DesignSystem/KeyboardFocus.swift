import SwiftUI

/// The visible focus ring.
///
/// Two concentric strokes, a light one inside a dark one, so it stays legible
/// on the cream of a card and on the wood of the board alike. Drawn rather
/// than tinted: relying on a colour would fail the same players the pawn marks
/// exist for (§42), and a focus ring nobody can see is the same as no keyboard
/// support at all (§46).
private struct KeyboardFocusRing: ViewModifier {
    let isFocused: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.overlay {
            if isFocused {
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                shape
                    .strokeBorder(Color.black.opacity(0.75), lineWidth: 5)
                    .overlay(shape.strokeBorder(Color.white.opacity(0.95), lineWidth: 2.5))
                    .padding(-3)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// Binds a view to a shared focus state, when there is one.
///
/// The board and the hand are separate views but share one focus, so the
/// keyboard can move between them. Previews and tests build them without a
/// focus at all, and neither should have to invent one.
private struct OptionalKeyboardFocus: ViewModifier {
    let focus: FocusState<PlayFocus?>.Binding?
    let value: PlayFocus

    @ViewBuilder
    func body(content: Content) -> some View {
        if let focus {
            content.focused(focus, equals: value)
        } else {
            content
        }
    }
}

extension View {
    /// Binds this view to `value` in a shared focus state, if one was given.
    func keyboardFocus(_ focus: FocusState<PlayFocus?>.Binding?, equals value: PlayFocus) -> some View {
        modifier(OptionalKeyboardFocus(focus: focus, value: value))
    }

    /// Marks this view as the keyboard's current position.
    func keyboardFocusRing(_ isFocused: Bool, cornerRadius: CGFloat) -> some View {
        modifier(KeyboardFocusRing(isFocused: isFocused, cornerRadius: cornerRadius))
    }

    /// The pointer treatment for something that can be acted on.
    ///
    /// Applied only where a tap would actually do something. A pointer that
    /// lifts a card the engine will refuse is a promise the game cannot keep,
    /// and on iPadOS the pointer is how a player finds out what is live (§46).
    @ViewBuilder
    func pointerEffect(_ effect: HoverEffect, enabled: Bool = true) -> some View {
        if enabled {
            hoverEffect(effect)
        } else {
            self
        }
    }
}
