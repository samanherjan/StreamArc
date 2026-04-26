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

    /// Standard card-style focus highlight on tvOS; no-op elsewhere.
    @ViewBuilder
    func cardFocusable() -> some View {
#if os(tvOS)
        self.buttonStyle(.card)
#else
        self
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
}

// MARK: - Conditional modifiers

extension View {
    @ViewBuilder
    func `if`<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }
}
