//
// Project: SKManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

/// Describes whether entitlement state has been resolved during this launch.
public enum EntitlementResolutionState: Sendable, Equatable {

    /// No readable, supported cache was loaded and StoreKit has not resolved state yet.
    case unresolved

    /// A launch-time cache was loaded and is awaiting a full StoreKit refresh.
    case cached

    /// StoreKit has resolved entitlement state, which may include no purchases.
    case confirmed
}
