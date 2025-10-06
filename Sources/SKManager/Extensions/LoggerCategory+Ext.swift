//
// Project: StoreManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import SimpleLogger

/// Extends the `LoggerCategory` type to include a predefined category for StoreKit logging.
///
/// Use this category when logging messages related to StoreKit operations, such as product
/// fetching, purchases, or entitlement updates. This helps keep log output organized and easier
/// to filter.
///
/// Example:
/// ```swift
/// let logger = SimpleLogger(category: .storeKit)
/// logger.info("Fetching products from App Store.")
/// ```
extension LoggerCategory {

    /// A `LoggerCategory` used for all StoreKit-related log messages.
    internal static let storeKit = LoggerCategory("StoreKit")
}
