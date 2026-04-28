import SwiftUI
import StoreKit

struct PaywallView: View {

    @Environment(StoreManager.self)    private var store
    @Environment(EntitlementManager.self) private var entitlements
    @Environment(\.dismiss)            private var dismiss

    @State private var selectedProduct: Product?
    @State private var showSuccessBanner = false
    @State private var showErrorAlert = false

    private let features: [(String, String)] = [
        ("infinity", "Unlimited profiles and channels"),
        ("calendar", "Full 7-day EPG grid"),
        ("film.stack", "TV Series section"),
        ("play.rectangle", "Movie trailers (TMDB)"),
        ("clock.arrow.circlepath", "Continue Watching"),
        ("pip", "Picture in Picture"),
        ("antenna.radiowaves.left.and.right", "Enigma2 / E2 support"),
        ("nosign", "No ads, ever")
    ]

    var body: some View {
        ZStack(alignment: .top) {
            Color.saBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    // Header
                    VStack(spacing: 8) {
                        Text("StreamArc")
                            .font(.largeTitle.bold())
                            .foregroundStyle(Color.saAccent)
                        Text("+")
                            .font(.system(size: 44, weight: .black))
                            .foregroundStyle(Color.saAccent)
                            .offset(y: -20)
                            .padding(.top, -16)
                        Text("Unlock the full experience")
                            .font(.title3)
                            .foregroundStyle(Color.saTextSecondary)
                    }
                    .padding(.top, 32)

                    // Feature list
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(features, id: \.0) { (icon, label) in
                            HStack(spacing: 12) {
                                Image(systemName: icon)
                                    .frame(width: 24)
                                    .foregroundStyle(Color.saAccent)
                                Text(label)
                                    .foregroundStyle(Color.saTextPrimary)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .background(Color.saSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal)

                    // Subscription options
                    if store.products.isEmpty {
                        VStack(spacing: 8) {
                            ProgressView().tint(.saAccent)
                            if let error = store.purchaseError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(Color.saError)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                                Button("Retry") {
                                    store.clearError()
                                    Task { await store.loadProducts() }
                                }
                                .font(.caption.bold())
                                .foregroundStyle(Color.saAccent)
                            }
                        }
                    } else {
                        VStack(spacing: 12) {
                            // Monthly
                            if let monthly = store.monthlyProduct {
                                ProductOptionRow(
                                    product: monthly,
                                    badge: "7-day free trial",
                                    isSelected: selectedProduct?.id == monthly.id
                                ) { selectedProduct = monthly }
                            }

                            // Yearly (Best Value)
                            if let yearly = store.yearlyProduct {
                                ProductOptionRow(
                                    product: yearly,
                                    badge: "Best Value · 7-day free trial",
                                    isFeatured: true,
                                    isSelected: selectedProduct?.id == yearly.id
                                ) { selectedProduct = yearly }
                            }

                            // Lifetime
                            if let lifetime = store.lifetimeProduct {
                                ProductOptionRow(
                                    product: lifetime,
                                    badge: "One-time purchase",
                                    isSelected: selectedProduct?.id == lifetime.id
                                ) { selectedProduct = lifetime }
                            }
                        }
                        .padding(.horizontal)
                    }

                    // CTA
                    Button {
                        guard let product = selectedProduct ?? store.yearlyProduct else { return }
                        Task { await purchase(product) }
                    } label: {
                        HStack {
                            if store.isPurchasing {
                                ProgressView().tint(.white)
                            } else {
                                Text(ctaLabel)
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.saAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal)
                    .disabled(store.isPurchasing)

                    // Restore
                    Button("Restore Purchases") {
                        Task {
                            await store.restorePurchases()
                            if entitlements.isPremium { dismiss() }
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(Color.saTextSecondary)

                    // Legal
                    Text("Subscriptions auto-renew unless cancelled at least 24 hours before the renewal date. Manage in App Store settings.")
                        .font(.caption2)
                        .foregroundStyle(Color.saTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                }
            }

            // Success banner
            if showSuccessBanner {
                SuccessBannerView(message: "Welcome to StreamArc+!")
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .onAppear {
            selectedProduct = store.yearlyProduct
            // Ensure products are loaded (fallback if app launch didn't complete)
            if store.products.isEmpty {
                Task { await store.loadProducts() }
            }
        }
        .onChange(of: store.lastPurchaseSuccess) { _, success in
            if success {
                withAnimation { showSuccessBanner = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation { showSuccessBanner = false }
                    dismiss()
                }
            }
        }
        .alert("Purchase Failed", isPresented: $showErrorAlert) {
            Button("OK") { store.clearError() }
        } message: {
            Text(store.purchaseError ?? "An unknown error occurred.")
        }
        .onChange(of: store.products) { _, _ in
            if selectedProduct == nil {
                selectedProduct = store.yearlyProduct ?? store.products.first
            }
        }
        .onChange(of: store.purchaseError) { _, newVal in
            showErrorAlert = newVal != nil
        }
    }

    private var ctaLabel: String {
        if let product = selectedProduct {
            return "Get Premium · \(product.displayPrice)"
        }
        return "Get Premium"
    }

    private func purchase(_ product: Product) async {
        await store.purchase(product)
    }
}

// MARK: - Sub-views

private struct ProductOptionRow: View {
    let product: Product
    var badge: String = ""
    var isFeatured: Bool = false
    var isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(product.displayName)
                            .font(.headline)
                            .foregroundStyle(Color.saTextPrimary)
                        if isFeatured {
                            Text("BEST VALUE")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.saAccent)
                                .clipShape(Capsule())
                        }
                    }
                    if !badge.isEmpty {
                        Text(badge)
                            .font(.caption)
                            .foregroundStyle(Color.saAccent)
                    }
                }
                Spacer()
                Text(product.displayPrice)
                    .font(.headline)
                    .foregroundStyle(Color.saTextPrimary)
            }
            .padding()
            .background(isSelected ? Color.saAccent.opacity(0.15) : Color.saSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.saAccent : Color.clear, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SuccessBannerView: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(message)
                .font(.subheadline.bold())
                .foregroundStyle(Color.saTextPrimary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.saSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(radius: 10)
        .padding(.top, 60)
    }
}
