//
// Project: StoreManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import Foundation

/// A model representing a user’s lifetime entitlement to a product tier.
///
/// Lifetime entitlements are non-expiring purchases that permanently unlock access to specific app
/// features or content associated with a given tier.
public struct LifetimeEntitlement<Tier: ProductTierRepresentable> {

    /// The unique product identifier associated with the entitlement.
    public let productID: String

    /// The tier unlocked by this lifetime purchase.
    public let tier: Tier
}
