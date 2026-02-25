//
// Project: SKManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import Foundation
@testable import SKManager

/// A minimal `ProductTierRepresentable` for use in tests.
///
/// Tier levels follow the package convention: lower = more premium.
/// - `.premium` = 1 (most premium)
/// - `.standard` = 2
/// - `.basic` = 3 (least premium)
enum MockTier: String, ProductTierRepresentable, CaseIterable {
    case premium
    case standard
    case basic

    var displayName: LocalizedStringResource { "\(rawValue)" }
    var description: LocalizedStringResource { "\(rawValue) tier" }

    var tierLevel: Int {
        switch self {
            case .premium: return 1
            case .standard: return 2
            case .basic: return 3
        }
    }
}
