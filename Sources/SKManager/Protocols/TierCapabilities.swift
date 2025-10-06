//
// Project: StoreManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import Foundation

/// A protocol that defines the relationship between product tiers and app features.
///
/// Conforming types specify which features are available at each tier level, allowing feature
/// gating and entitlement-based access control throughout the app.
public protocol TierCapabilities {

    /// The type representing the product tier hierarchy.
    associatedtype Tier: ProductTierRepresentable

    /// The type representing app features that can be gated by tier.
    associatedtype Feature

    /// Determines whether a given feature is available for a specific tier.
    ///
    /// - Parameters:
    ///   - feature: The feature being checked.
    ///   - tier: The product tier to evaluate.
    /// - Returns: `true` if the feature is accessible at the specified tier, otherwise `false`.
    func allows(_ feature: Feature, for tier: Tier) -> Bool
}
