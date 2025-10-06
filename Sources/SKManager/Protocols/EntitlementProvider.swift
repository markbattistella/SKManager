//
// Project: StoreManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import Foundation

/// A protocol that defines the interface for objects that provide information about the user’s
/// current App Store entitlements, including subscriptions and lifetime purchases.
///
/// Conforming types are responsible for exposing entitlement state and supporting asynchronous
/// refresh operations to ensure accuracy with the App Store.
///
/// Conform to this protocol when implementing a custom entitlement manager that interacts with
/// StoreKit or a backend service.
///
/// - Note: All conforming types are required to run on the main actor to ensure UI safety.
@MainActor
public protocol EntitlementProvider: AnyObject {

    /// The type representing available store products.
    associatedtype Item: StoreProductRepresentable

    /// The type representing product tiers or subscription levels.
    associatedtype Group: ProductTierRepresentable

    /// The set of all product identifiers that have been purchased by the user.
    var purchasedProductIDs: Set<String> { get }

    /// The list of lifetime entitlements owned by the user.
    var lifetimeEntitlements: [LifetimeEntitlement<Group>] { get }

    /// The user’s currently active subscription entitlement, if any.
    var activeSubscription: SubscriptionEntitlement<Group>? { get }

    /// A closure that is called whenever entitlement data is refreshed.
    var onRefresh: (() -> Void)? { get set }

    /// Refreshes the user’s entitlements by validating current App Store transactions.
    ///
    /// This method should update all entitlement-related properties and trigger the `onRefresh`
    /// callback upon completion.
    func refreshEntitlements() async
}
