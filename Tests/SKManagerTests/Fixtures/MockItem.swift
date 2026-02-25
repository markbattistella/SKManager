//
// Project: SKManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import StoreKit
@testable import SKManager

/// A minimal `StoreProductRepresentable` for use in tests.
enum MockItem: String, StoreProductRepresentable, CaseIterable, Comparable {
    case premiumMonthly
    case premiumYearly
    case standardMonthly
    case basicMonthly
    case addonPack       // non-consumable add-on used in conflict and group-hide tests

    typealias Tier = MockTier

    var sortOrder: Int {
        switch self {
            case .premiumMonthly: return 0
            case .premiumYearly: return 1
            case .standardMonthly: return 2
            case .basicMonthly: return 3
            case .addonPack: return 4
        }
    }

    var productType: Product.ProductType {
        switch self {
            case .addonPack: return .nonConsumable
            default: return .autoRenewable
        }
    }

    static var groupedByTier: [MockTier: [MockItem]] {
        [
            .premium: [.premiumMonthly, .premiumYearly],
            .standard: [.standardMonthly],
            .basic: [.basicMonthly]
        ]
    }

    static func < (lhs: MockItem, rhs: MockItem) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}
