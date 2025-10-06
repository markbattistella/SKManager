//
// Project: StoreManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import Foundation

/// A model representing the user’s balance of a consumable StoreKit product.
///
/// Consumables are items that can be purchased multiple times and are depleted as they are used,
/// such as credits, tokens, or in-app currency.
public struct ConsumableBalance: Codable, Hashable {

    /// The unique product identifier associated with the consumable item.
    public let productID: String

    /// The remaining quantity of the consumable item available to the user.
    public var quantity: Int
}
