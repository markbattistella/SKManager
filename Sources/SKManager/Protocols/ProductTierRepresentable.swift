//
// Project: StoreManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import Foundation

/// A protocol that defines a type representing a product tier or subscription level.
///
/// Conforming types describe the hierarchy and presentation details of product tiers, such as
/// display names, descriptions, and their relative ranking.
///
/// Tiers are typically used to organise products by capability or price level.
public protocol ProductTierRepresentable: StoreIdentifiable {

    /// The human-readable name displayed for the tier.
    var displayName: LocalizedStringResource { get }

    /// A localized description explaining the tier’s features or purpose.
    var description: LocalizedStringResource { get }

    /// The tier’s relative level used for comparison and sorting.
    ///
    /// Lower values usually indicate a more basic plan, while higher values represent more
    /// advanced or premium tiers.
    var tierLevel: Int { get }
}
