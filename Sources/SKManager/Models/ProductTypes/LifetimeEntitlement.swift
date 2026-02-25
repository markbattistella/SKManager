//
// Project: SKManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import StoreKit

/// A model representing a user's lifetime entitlement to a product tier.
///
/// Lifetime entitlements are non-expiring purchases that permanently unlock access to specific
/// app features or content associated with a given tier.
public struct LifetimeEntitlement<Tier: ProductTierRepresentable>: Sendable {

    /// The unique product identifier associated with the entitlement.
    public let productID: String

    /// The tier unlocked by this lifetime purchase.
    public let tier: Tier

    /// Whether the entitlement was purchased directly or shared via Family Sharing.
    public let ownershipType: Transaction.OwnershipType

    /// Returns `true` when this entitlement was received through Family Sharing rather than a
    /// direct purchase by the current account.
    public var isFamilyShared: Bool { ownershipType == .familyShared }
}
