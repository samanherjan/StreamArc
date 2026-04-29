import SwiftUI

extension View {

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

    /// Standard card-style focus highlight on tvOS; `.plain` elsewhere.
    @ViewBuilder
    func cardFocusable() -> some View {
#if os(tvOS)
        self.buttonStyle(.card)
#else
        self.buttonStyle(.plain)
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
        self.sheet(isPresented: isPresented) {
            PaywallView()
        }
    }

    /// Returns a scaled value for tvOS (10-foot UI needs larger elements).
    /// On other platforms returns the base value.
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
}

// MARK: - tvOS Focus Scale Effect

#if os(tvOS)
struct TVFocusScaleModifier: ViewModifier {
    @Environment(\.isFocused) var isFocused

    func body(content: Content) -> some View {
        content
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .shadow(color: isFocused ? Color.saAccent.opacity(0.4) : .clear, radius: 10)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

extension View {
    func tvFocusScale() -> some View {
        self.modifier(TVFocusScaleModifier())
    }
}
#else
extension View {
    func tvFocusScale() -> some View { self }
}
#endif

// MARK: - iOS-only input modifiers (no-ops on macOS/tvOS)

extension View {
    /// Applies `.keyboardType(.URL)` + `.textInputAutocapitalization(.never)` on iOS; no-op elsewhere.
    @ViewBuilder
    func urlTextField() -> some View {
#if os(iOS)
        self
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
#else
        self
#endif
    }

    /// Applies `.keyboardType(.numberPad)` on iOS; no-op elsewhere.
    @ViewBuilder
    func numberPadField() -> some View {
#if os(iOS)
        self.keyboardType(.numberPad)
#else
        self
#endif
    }

    /// Applies `.textInputAutocapitalization(.never)` on iOS; no-op elsewhere.
    @ViewBuilder
    func noAutocapitalization() -> some View {
#if os(iOS)
        self.textInputAutocapitalization(.never)
#else
        self
#endif
    }
}
