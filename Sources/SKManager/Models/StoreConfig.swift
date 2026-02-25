//
// Project: SKManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import Foundation

/// A configuration model defining store behaviour and conflict rules.
///
/// `StoreConfig` is used by store management components to determine how products and tiers
/// interact, including product and tier conflict detection.
public struct StoreConfig<Group: ProductTierRepresentable, Item: StoreProductRepresentable>: Sendable {

    /// A mapping that defines which tiers are incompatible with each other.
    ///
    /// Used to prevent users from holding multiple conflicting tiers simultaneously.
    internal let conflictGroups: [Group: [Group]]

    /// A mapping that defines which individual products conflict with each other.
    ///
    /// Used to detect and prevent conflicting purchases at the product level.
    internal let conflictProducts: [Item: [Item]]

    public init(
        conflictGroups: [Group: [Group]],
        conflictProducts: [Item: [Item]]
    ) {
        self.conflictGroups = conflictGroups
        self.conflictProducts = conflictProducts
    }

    /// A default configuration with no conflicts defined.
    public static var defaultConfig: Self {
        .init(
            conflictGroups: [:],
            conflictProducts: [:]
        )
    }
}

// MARK: - Conflict Detection

extension StoreConfig {

    /// Returns `true` if the provided active tiers or owned product IDs conflict according to
    /// the configured rules.
    ///
    /// Extracted from `StoreManager` so that conflict logic can be tested independently without
    /// requiring a fully initialised store or StoreKit products.
    ///
    /// - Parameters:
    ///   - activeTiers: All tiers currently active for the user (subscriptions + lifetime
    ///   entitlements).
    ///   - ownedProducts: All product identifiers currently owned by the user.
    /// - Returns: `true` if any tier or product conflict is detected.
    public func hasConflicts(
        activeTiers: Set<Group>,
        ownedProducts: Set<String>
    ) -> Bool {
        for (tier, conflicts) in conflictGroups {
            guard activeTiers.contains(tier) else { continue }
            if conflicts.contains(where: { activeTiers.contains($0) }) { return true }
        }

        for (item, conflicts) in conflictProducts {
            guard ownedProducts.contains(item.rawValue) else { continue }
            if conflicts.contains(where: { ownedProducts.contains($0.rawValue) }) { return true }
        }

        return false
    }
}
