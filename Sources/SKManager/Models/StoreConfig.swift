//
// Project: StoreManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import Foundation

/// A configuration model defining store behaviour, upgrade logic, and conflict rules.
///
/// `StoreConfig` is used by store management components to determine how products and tiers
/// interact, including upgrade eligibility, lifetime access, and product conflicts.
public struct StoreConfig<Group: ProductTierRepresentable, Item: StoreProductRepresentable> {

    /// The set of tiers that represent lifetime entitlements (non-expiring access).
    internal let lifetimeGroups: [Group]

    /// A closure defining the logic for whether a user can upgrade from one tier to another.
    ///
    /// - Parameters:
    ///   - targetTier: The tier being upgraded to.
    ///   - ownedProductIDs: The set of currently owned product identifiers.
    /// - Returns: `true` if the upgrade is permitted; otherwise `false`.
    internal let upgradeLogic: (Group, Set<String>) -> Bool

    /// A mapping that defines which tiers are incompatible with each other.
    ///
    /// Used to prevent users from holding multiple conflicting tiers simultaneously.
    internal let conflictGroups: [Group: [Group]]

    /// A mapping that defines which individual products conflict with each other.
    ///
    /// Used to detect and prevent conflicting purchases at the product level.
    internal let conflictProducts: [Item: [Item]]

    public init(
        lifetimeGroups: [Group],
        upgradeLogic: @escaping (Group, Set<String>) -> Bool,
        conflictGroups: [Group : [Group]],
        conflictProducts: [Item : [Item]]
    ) {
        self.lifetimeGroups = lifetimeGroups
        self.upgradeLogic = upgradeLogic
        self.conflictGroups = conflictGroups
        self.conflictProducts = conflictProducts
    }

    /// A default configuration with no lifetime tiers, universal upgrade permission, and no
    /// conflicts defined.
    public static var defaultConfig: Self {
        .init(
            lifetimeGroups: [],
            upgradeLogic: { _, _ in true },
            conflictGroups: [:],
            conflictProducts: [:]
        )
    }
}
