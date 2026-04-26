import Foundation
import StoreKit

@MainActor
@Observable
final class StoreManager {

    private(set) var products: [Product] = []
    private(set) var isPurchasing = false
    private(set) var purchaseError: String?
    private(set) var lastPurchaseSuccess = false

    private let entitlementManager: EntitlementManager
    private var updatesTask: Task<Void, Never>?

    private static let productIDs = [
        "streamarc.premium.monthly",
        "streamarc.premium.yearly",
        "streamarc.premium.lifetime"
    ]

    init(entitlementManager: EntitlementManager) {
        self.entitlementManager = entitlementManager
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Load products

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            // Sort: monthly, yearly, lifetime
            products = loaded.sorted { a, b in
                let order = Self.productIDs
                return (order.firstIndex(of: a.id) ?? 99) < (order.firstIndex(of: b.id) ?? 99)
            }
        } catch {
            purchaseError = error.localizedDescription
        }
        listenForTransactionUpdates()
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async {
        isPurchasing = true
        purchaseError = nil
        lastPurchaseSuccess = false

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let tx) = verification else { break }
                await tx.finish()
                await entitlementManager.refresh()
                lastPurchaseSuccess = true
            case .userCancelled:
                break
            case .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }

        isPurchasing = false
    }

    // MARK: - Restore

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await entitlementManager.refresh()
            lastPurchaseSuccess = entitlementManager.isPremium
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Transaction listener

    private func listenForTransactionUpdates() {
        updatesTask = Task(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let tx) = result else { continue }
                await tx.finish()
                await self?.entitlementManager.refresh()
            }
        }
    }

    // MARK: - Helpers

    var monthlyProduct: Product? { products.first(where: { $0.id == "streamarc.premium.monthly" }) }
    var yearlyProduct:  Product? { products.first(where: { $0.id == "streamarc.premium.yearly" }) }
    var lifetimeProduct: Product? { products.first(where: { $0.id == "streamarc.premium.lifetime" }) }
}
