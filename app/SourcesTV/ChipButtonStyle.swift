import SwiftUI

/// Filter / segment chip for tvOS, on the StremioX design system (see Theme.swift).
///
/// Three states, all warm-neutral with the ember accent reserved for meaning:
/// - **idle**     → `surface2` pill, secondary text
/// - **selected** → soft-ember pill, ember text (pass `accent`/`accentText` to override, e.g. destructive)
/// - **focused**  → ember ring + lift + brightened text, so the focused chip is unmistakable at ten feet
struct ChipButtonStyle: ButtonStyle {
    var selected: Bool = false
    var accent: Color = Theme.Palette.accent
    var accentText: Color = Theme.Palette.accent

    func makeBody(configuration: Configuration) -> some View {
        Chip(selected: selected, accent: accent, accentText: accentText, configuration: configuration)
    }

    private struct Chip: View {
        let selected: Bool
        let accent: Color
        let accentText: Color
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var focused: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(Theme.Typography.label)
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, Theme.Space.xs + 2)
                .foregroundStyle(textColor)
                .background(fill, in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).strokeBorder(accent, lineWidth: focused ? 3 : 0))
                .scaleEffect(configuration.isPressed ? 0.97 : (focused && !reduceMotion ? 1.06 : 1))
                .shadow(color: accent.opacity(focused ? 0.4 : 0), radius: 18, y: 8)
                .animation(reduceMotion ? nil : Theme.Motion.focus, value: focused)
        }

        private var fill: Color {
            if selected { return accent.opacity(0.18) }
            return Theme.Palette.surface2
        }
        private var textColor: Color {
            if selected { return accentText }
            return focused ? Theme.Palette.textPrimary : Theme.Palette.textSecondary
        }
    }
}
