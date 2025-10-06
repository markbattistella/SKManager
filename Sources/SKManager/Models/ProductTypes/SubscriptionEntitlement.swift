//
// Project: StoreManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import Foundation

/// A model representing a user’s active or past subscription entitlement.
///
/// This structure encapsulates information about the subscribed product tier, its expiration, and
/// any upcoming renewal or transition actions.
///
/// Used to determine the user’s current and future access level within the app.
public struct SubscriptionEntitlement<Tier: ProductTierRepresentable> {

    /// The unique product identifier of the active subscription.
    public let productID: String

    /// The subscription tier associated with the entitlement.
    public let tier: Tier

    /// The expiration date of the subscription, if applicable.
    ///
    /// `nil` indicates that the subscription is non-expiring.
    public let expirationDate: Date?

    /// The renewal or transition state of the subscription.
    ///
    /// Used to describe whether the subscription will renew, upgrade, downgrade, crossgrade, or
    /// be cancelled at the next renewal date.
    public let renewalAction: RenewalAction?

    /// Describes the upcoming change to the subscription at its renewal point.
    public enum RenewalAction {

        /// The subscription will renew to the same plan.
        case renewSame(plan: Tier, date: Date?)

        /// The subscription will upgrade to a higher tier at the specified date.
        case upgrade(to: Tier, nextProductID: String, date: Date?)

        /// The subscription will downgrade to a lower tier at the specified date.
        case downgrade(to: Tier, nextProductID: String, date: Date?)

        /// The subscription will change to a different product in the same tier level.
        case crossgrade(nextProductID: String, date: Date?)

        /// The subscription will not renew and will expire at the given date.
        case cancel(date: Date?)
    }
}
