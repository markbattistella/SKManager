//
// Project: StoreManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import Foundation

/// A structure defining store visibility rules for products based on user ownership.
///
/// `StoreRules` determines which products should be shown or hidden in the store depending on what
/// the user has already purchased.
///
/// This enables contextual product visibility, such as hiding purchased items or revealing upgrade
/// options. Rules operate at two levels:
/// - **Group level** (`groupHideMap`): hides an entire tier when a specific product is owned.
/// - **Product level** (`hideMap`/`showMap`): hides or reveals individual products within a tier.
public struct StoreRules<Item: StoreProductRepresentable> {

    /// The set of products visible when the user owns no items.
    internal let defaultVisible: Set<Item>

    /// A mapping of products to the set of products that should be hidden when each is owned.
    internal let hideMap: [Item: Set<Item>]

    /// A mapping of products to the set of products that should be shown when each is owned.
    internal let showMap: [Item: Set<Item>]

    /// A mapping of products to the set of tiers that should be hidden when each is owned.
    ///
    /// Use this to suppress an entire group from the storefront when the user already owns a
    /// product that supersedes it. For example, owning a lifetime family upgrade could hide the
    /// family subscription tier entirely.
    internal let groupHideMap: [Item: Set<Item.Tier>]

    public init(
        defaultVisible: Set<Item>,
        hideMap: [Item: Set<Item>],
        showMap: [Item: Set<Item>],
        groupHideMap: [Item: Set<Item.Tier>] = [:]
    ) {
        self.defaultVisible = defaultVisible
        self.hideMap = hideMap
        self.showMap = showMap
        self.groupHideMap = groupHideMap
    }

    /// Determines the set of products that should be visible for a given set of owned product IDs.
    ///
    /// - Parameter owned: The set of product identifiers owned by the user.
    /// - Returns: The set of products that should be visible in the store.
    internal func visibleProducts(for owned: Set<String>) -> Set<Item> {
        guard !owned.isEmpty else { return defaultVisible }

        var visible: Set<Item> = []
        for id in owned {
            if let item = Item(rawValue: id),
               let shows = showMap[item] { visible.formUnion(shows) }
        }
        return visible
    }

    /// Determines the set of products that should be hidden for a given set of owned product IDs.
    ///
    /// - Parameter owned: The set of product identifiers owned by the user.
    /// - Returns: The set of products that should be hidden in the store.
    internal func hiddenProducts(for owned: Set<String>) -> Set<Item> {
        var hidden: Set<Item> = []
        for id in owned {
            if let item = Item(rawValue: id),
               let hides = hideMap[item] { hidden.formUnion(hides) }
        }
        return hidden
    }

    /// Determines the set of tiers that should be hidden for a given set of owned product IDs.
    ///
    /// - Parameter owned: The set of product identifiers owned by the user.
    /// - Returns: The set of tiers whose products should not appear in the store.
    internal func hiddenGroups(for owned: Set<String>) -> Set<Item.Tier> {
        var hidden: Set<Item.Tier> = []
        for id in owned {
            if let item = Item(rawValue: id),
               let hides = groupHideMap[item] { hidden.formUnion(hides) }
        }
        return hidden
    }
}
