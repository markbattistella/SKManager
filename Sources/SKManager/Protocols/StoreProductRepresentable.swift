//
// Project: StoreManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import Foundation
import StoreKit.SKProduct

/// A protocol that defines a type representing an App Store product, such as a subscription,
/// consumable, or non-consumable item.
///
/// Conforming types describe metadata for each product and define how products are grouped and
/// ordered within their associated tiers.
///
/// This protocol provides a bridge between StoreKit product identifiers and higher-level tier
/// models used by the app.
public protocol StoreProductRepresentable: StoreIdentifiable, Comparable {

    /// The type that defines logical tiers or levels associated with the product.
    associatedtype Tier: ProductTierRepresentable

    /// The order used to sort products within the same tier.
    var sortOrder: Int { get }

    /// The StoreKit product type (e.g., subscription, consumable, non-consumable).
    var productType: Product.ProductType { get }

    /// A mapping of tiers to the products they contain.
    ///
    /// Used to organise available products for display and entitlement resolution.
    static var groupedByTier: [Tier: [Self]] { get }
}
