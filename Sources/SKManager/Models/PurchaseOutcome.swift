//
// Project: SKManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import Foundation

/// Represents the result of an attempted StoreKit purchase.
///
/// `PurchaseOutcome` provides a simplified, high-level abstraction over StoreKit's purchase
/// result types, making it suitable for driving UI flow, navigation, and user feedback without
/// exposing StoreKit internals.
///
/// This type is intentionally distinct from entitlement state; a `.success` outcome indicates
/// that the purchase transaction completed successfully, not that entitlements have already
/// been fully propagated through the app.
public enum PurchaseOutcome: Sendable {

    /// The purchase completed successfully and the transaction was verified.
    case success

    /// The user explicitly cancelled the purchase flow.
    case cancelled

    /// The purchase is pending external action (e.g. parental approval).
    case pending

    /// The purchase failed due to an error.
    case failed(any Error)
}
