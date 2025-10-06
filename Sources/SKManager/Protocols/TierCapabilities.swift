//
// Project: StoreManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import Foundation

/// A protocol defining how features are mapped to access capabilities across product tiers.
///
/// Conforming types describe which features are available at each tier and how access is
/// evaluated. Each feature–tier combination is associated with a capability value that determines
/// availability, limits, or conditions of access.
///
/// This protocol is generic and supports both simple and complex entitlement models. A default
/// implementation of `CapabilityRule` is provided for convenience.
///
/// The `EntitlementManager` queries this protocol to determine whether a user can access a feature
/// based on their current subscription or entitlement tier.
public protocol TierCapabilities: Sendable {

    /// The type representing the product tier hierarchy.
    associatedtype Tier: ProductTierRepresentable & Hashable

    /// The type representing individual features that can be gated by tier.
    associatedtype Feature: Hashable

    /// The type that defines how feature availability is represented. Apps can use `CapabilityRule`
    /// or define their own custom type.
    associatedtype CapabilityValue

    /// The complete mapping of feature capabilities across all tiers.
    var capabilities: [Feature: [Tier: CapabilityValue]] { get }

    /// Returns the capability value for the specified feature–tier pair.
    ///
    /// - Parameters:
    ///   - feature: The feature whose capability should be retrieved.
    ///   - tier: The tier to evaluate.
    /// - Returns: The capability value for the feature and tier, or `nil` if undefined.
    func capability(for feature: Feature, in tier: Tier) -> CapabilityValue?

    /// Evaluates whether a given capability should be considered active or accessible.
    ///
    /// The conforming type defines the rules for accessibility, such as allowing `.allowed(true)`,
    /// `.limit(> 0)`, or `.until(date > now)`.
    ///
    /// - Parameter capability: The capability value to evaluate.
    /// - Returns: `true` if the capability is currently accessible; otherwise `false`.
    func isAccessible(_ capability: CapabilityValue) -> Bool
}

public extension TierCapabilities {

    /// Default lookup implementation that retrieves the capability value for the specified
    /// feature and tier from the `capabilities` map.
    func capability(for feature: Feature, in tier: Tier) -> CapabilityValue? {
        capabilities[feature]?[tier]
    }
}
