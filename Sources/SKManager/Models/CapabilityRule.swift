//
// Project: SKManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import Foundation

/// A default representation of feature access states.
///
/// `CapabilityRule` provides a flexible model for describing whether a feature is accessible,
/// limited, time-bound, or unavailable. It is suitable for most subscription-based entitlement
/// systems but can be replaced with a custom type if needed.
public enum CapabilityRule: Equatable, Sendable {
    
    /// Indicates that access is explicitly allowed or denied.
    case allowed(Bool)
    
    /// Indicates access is allowed with a numeric or quantity limit,
    /// such as a number of months, entries, or items.
    case limit(Int)
    
    /// Indicates that access is temporarily available until the specified date.
    case until(Date)
    
    /// Indicates full and unrestricted access.
    case unrestricted
    
    /// Indicates that the feature is unavailable or disabled.
    case unavailable
}

extension CapabilityRule {
    
    /// Returns whether the capability is currently active or available.
    ///
    /// - Note: Rules such as `.limit`, `.until`, and `.unrestricted` are considered accessible by
    /// default, while `.unavailable` is not.
    public var isAccessible: Bool {
        switch self {
            case .allowed(let flag): return flag
            case .limit, .until, .unrestricted: return true
            case .unavailable: return false
        }
    }
    
    /// The expiry date associated with `.until` rules, if any.
    ///
    /// - Returns: The expiry `Date` if the rule is `.until`, otherwise `nil`.
    public var expiry: Date? {
        if case .until(let date) = self { return date }
        return nil
    }
    
    /// The numeric limit associated with `.limit` rules, if any.
    ///
    /// - Returns: The limit value if the rule is `.limit`, otherwise `nil`.
    public var limit: Int? {
        if case .limit(let value) = self { return value }
        return nil
    }
}

extension TierCapabilities where CapabilityValue == CapabilityRule {
    
    /// Provides a default implementation of `isAccessible(_:)` for conformers using the built-in
    /// `CapabilityRule` type.
    ///
    /// This simply delegates to the `CapabilityRule.isAccessible` property.
    public func isAccessible(_ capability: CapabilityRule) -> Bool {
        capability.isAccessible
    }
}
