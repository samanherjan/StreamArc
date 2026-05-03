import SwiftUI

// MARK: - tvOS Custom Focus Button Style

#if os(tvOS)
/// Custom tvOS button style: scale up + accent-coloured glow on focus. No white border.
struct TVAccentFocusButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : (isFocused ? 1.08 : 1.0))
            .shadow(
                color: isFocused ? Color.saAccent.opacity(0.55) : .black.opacity(0.25),
                radius: isFocused ? 18 : 6,
                y: isFocused ? 8 : 3
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.saAccent.opacity(isFocused ? 0.65 : 0), lineWidth: 2)
                    .allowsHitTesting(false)
            )
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: isFocused)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            // Suppress the system default white focus ring that tvOS adds by default.
            .focusEffectDisabled()
    }
}
#endif

// MARK: - iOS/macOS Card Button Style

/// Card button style for iOS/iPadOS/macOS: accent-glow on hover/press, no system ring.
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CardFocusLabel(label: configuration.label, isPressed: configuration.isPressed)
    }
}

/// Inner view so @Environment(\.isFocused) is read inside the button's own focus scope.
struct CardFocusLabel<L: View>: View {
    let label: L
    let isPressed: Bool
    @Environment(\.isFocused) private var isFocused
    @State private var isHovered = false

    private var isActive: Bool { isFocused || isHovered }

    var body: some View {
        label
            .scaleEffect(isPressed ? 0.94 : (isActive ? 1.05 : 1.0))
            .brightness(isActive ? 0.08 : 0)
            .shadow(
                color: isActive ? Color.saAccent.opacity(0.45) : .black.opacity(0.2),
                radius: isActive ? 14 : 5,
                y: isActive ? 6 : 2
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.saAccent.opacity(isActive ? 0.7 : 0), lineWidth: 2)
                    .allowsHitTesting(false)
            )
            .focusEffectDisabled()
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: isActive)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            #if !os(tvOS)
            .onHover { isHovered = $0 }
            #endif
    }
}

// MARK: - Card Focusable

extension View {

    /// Accent-glow focus on tvOS; CardButtonStyle (hover/press) on iOS/macOS.
    @ViewBuilder
    func cardFocusable() -> some View {
#if os(tvOS)
        self.buttonStyle(TVAccentFocusButtonStyle())
#else
        self.buttonStyle(CardButtonStyle())
#endif
    }

    /// Dark-themed background applied to every root view.
    func streamArcBackground() -> some View {
        self.background(Color.saBackground.ignoresSafeArea())
    }

    /// Rounded card container.
    func cardStyle(cornerRadius: CGFloat = 12) -> some View {
        self
            .background(Color.saCard)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Show a paywall sheet on a Boolean binding.
    func paywallSheet(isPresented: Binding<Bool>) -> some View {
        self.sheet(isPresented: isPresented) { PaywallView() }
    }

    /// Returns a scaled value for tvOS (10-foot UI needs larger elements).
    static func tvScaled(_ base: CGFloat, tvMultiplier: CGFloat = 1.6) -> CGFloat {
#if os(tvOS)
        return base * tvMultiplier
#else
        return base
#endif
    }
}

// MARK: - Conditional modifiers

extension View {
    @ViewBuilder
    func `if`<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }

    /// Apply a modifier only on iOS / iPadOS.
    @ViewBuilder
    func iOSOnly<M: ViewModifier>(_ modifier: M) -> some View {
#if os(iOS)
        self.modifier(modifier)
#else
        self
#endif
    }

    /// Apply a modifier only on tvOS.
    @ViewBuilder
    func tvOSOnly<M: ViewModifier>(_ modifier: M) -> some View {
#if os(tvOS)
        self.modifier(modifier)
#else
        self
#endif
    }
}

// MARK: - tvOS Focus Scale Effect

#if os(tvOS)
struct TVFocusScaleModifier: ViewModifier {
    @Environment(\.isFocused) var isFocused

    func body(content: Content) -> some View {
        content
            .scaleEffect(isFocused ? 1.1 : 1.0)
            .shadow(color: isFocused ? Color.saAccent.opacity(0.4) : .clear, radius: 10)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

extension View {
    func tvFocusScale() -> some View { self.modifier(TVFocusScaleModifier()) }
}
#else
extension View {
    func tvFocusScale() -> some View { self }
}
#endif

// MARK: - iOS-only input modifiers

extension View {
    @ViewBuilder
    func urlTextField() -> some View {
#if os(iOS)
        self.keyboardType(.URL).textInputAutocapitalization(.never)
#else
        self
#endif
    }

    @ViewBuilder
    func numberPadField() -> some View {
#if os(iOS)
        self.keyboardType(.numberPad)
#else
        self
#endif
    }

    @ViewBuilder
    func noAutocapitalization() -> some View {
#if os(iOS)
        self.textInputAutocapitalization(.never)
#else
        self
#endif
    }
}
