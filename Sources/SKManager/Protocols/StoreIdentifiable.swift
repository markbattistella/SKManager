//
// Project: StoreManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import Foundation

/// A protocol that defines a store-related type identifiable by a string raw value.
///
/// Conforming types represent discrete items in the store, such as product identifiers, and gain
/// automatic conformance to `Identifiable`, `CaseIterable`, and `Hashable`.
///
/// By default, the `id` property returns the case’s `rawValue`, making it suitable for use in
/// SwiftUI lists and collections.
public protocol StoreIdentifiable: Identifiable, CaseIterable, Hashable, RawRepresentable
where RawValue == String {}

public extension StoreIdentifiable {

    /// A unique string identifier for the store item.
    var id: String { rawValue }
}
