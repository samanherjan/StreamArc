import Foundation
import StoreKit

// Checks active premium entitlements by re-verifying with StoreKit on every
// app launch and foreground event. Never persists the isPremium flag itself
// — always re-derived from StoreKit to prevent local bypass.
@MainActor
@Observable
final class EntitlementManager {

    private(set) var isPremium: Bool = false
    private(set) var isLifetime: Bool = false

    private static let allProductIDs: Set<String> = [
        "streamarc.premium.monthly",
        "streamarc.premium.yearly",
        "streamarc.premium.lifetime"
    ]

    func refresh() async {
        var foundActive = false
        var foundLifetime = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result else { continue }
            guard Self.allProductIDs.contains(tx.productID) else { continue }

            if tx.productID == "streamarc.premium.lifetime" {
                foundLifetime = true
                foundActive   = true
            } else if let expiry = tx.expirationDate, expiry > .now {
                foundActive = true
            } else if tx.expirationDate == nil {
                // Non-renewable or lifetime
                foundActive = true
            }
        }

        isPremium  = foundActive
        isLifetime = foundLifetime
    }
}
