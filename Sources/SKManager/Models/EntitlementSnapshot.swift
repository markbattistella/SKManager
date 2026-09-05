//
// Project: SKManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import Foundation

/// A launch-time hint persisted after StoreKit updates entitlement state.
///
/// Raw strings keep the cache independent of the app's tier type and StoreKit's non-Codable
/// ownership type. Purchased IDs are rebuilt from valid entries when restoring the snapshot.
struct EntitlementSnapshot: Codable, Sendable {
    var version = 1
    let activeSubscription: CachedSubscription?
    let lifetimeEntitlements: [CachedLifetime]

    struct CachedSubscription: Codable, Sendable {
        let productID: String
        let tierRawValue: String
        let expirationDate: Date?
        let ownershipRawValue: String
    }

    struct CachedLifetime: Codable, Sendable {
        let productID: String
        let tierRawValue: String
        let ownershipRawValue: String
    }
}
