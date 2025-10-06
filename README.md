<!-- markdownlint-disable MD033 MD041 -->
<div align="center">

# SKManager

![Swift Versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmarkbattistella%2FSKManager%2Fbadge%3Ftype%3Dswift-versions)
![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmarkbattistella%2FSKManager%2Fbadge%3Ftype%3Dplatforms)
![Licence](https://img.shields.io/badge/Licence-MIT-white?labelColor=blue&style=flat)

</div>

`SKManager` is a modular, strongly typed StoreKit 2 framework for Swift applications that simplifies product management, entitlement tracking, and feature gating across iOS, macOS, tvOS, and watchOS. It provides a clean abstraction layer between StoreKit and your app’s logic, offering clear configuration, conflict detection, and entitlement synchronisation.

---

## Features

- **Unified StoreKit Abstraction:** A complete model for product fetching, purchasing, and entitlement synchronisation.
- **Type-Safe Architecture:** All products, tiers, and capabilities are represented as Swift protocols and generics.
- **Observable and SwiftUI-Ready:** All core managers conform to `@MainActor` and `@Observable` for real-time UI updates.
- **Configurable Store Logic:** Define custom upgrade paths, conflicts, and visibility rules.
- **Automatic Entitlement Refresh:** Responds to StoreKit transaction updates and subscription renewals.
- **Feature Access Control:** Gate app functionality based on purchased tiers.

---

## Installation

Add `SKManager` to your Swift project using Swift Package Manager.

```swift
dependencies: [
  .package(url: "https://github.com/markbattistella/SKManager", from: "1.0.0")
]
```

Alternatively, in Xcode:

`File > Add Packages > https://github.com/markbattistella/SKManager`

## Usage

### Core Components

#### `StoreManager`

`StoreManager` handles fetching, purchasing, and restoring StoreKit products while maintaining synchronised purchase states.

```swift
import SKManager
import SimpleLogger

@MainActor
@Observable
final class MyStore: StoreManager<MyProduct, MyTier, MyEntitlementManager> {}
```

Basic usage example:

```swift
let manager = StoreManager(
    entitlementManager: myEntitlementManager,
    config: .defaultConfig,
    rules: nil
)

Task {
    await manager.refreshAll()
    if let product = manager.product(with: "com.myapp.pro") {
        await manager.purchase(product)
    }
}
```

#### `EntitlementManager`

Tracks and validates entitlements by observing StoreKit transactions, maintaining the current subscription, lifetime, and consumable states.

```swift
let entitlementManager = EntitlementManager<MyProduct, MyTier, MyCapabilities>(config: MyCapabilities())
await entitlementManager.refreshEntitlements()
```

Entitlement checks:

```swift
if entitlementManager.hasAccess(to: .advancedFeature) {
    // Enable feature
}
```

#### `StoreConfig`

Defines upgrade rules and product conflicts.

| Property           | Description                                            |
| ------------------ | ------------------------------------------------------ |
| `lifetimeGroups`   | Tiers with lifetime (non-expiring) access.             |
| `upgradeLogic`     | Closure that determines whether an upgrade is allowed. |
| `conflictGroups`   | Defines tier-level conflicts.                          |
| `conflictProducts` | Defines product-level conflicts.                       |

Example:

```swift
let config = StoreConfig(
    lifetimeGroups: [.lifetime],
    upgradeLogic: { target, owned in target.tierLevel > 0 && !owned.isEmpty },
    conflictGroups: [.pro: [.basic]],
    conflictProducts: [.premium: [.standard]]
)
```

#### `StoreRules`

Manages product visibility depending on ownership.

```swift
let rules = StoreRules(
    defaultVisible: [.basic],
    hideMap: [.basic: [.basic]],
    showMap: [.pro: [.premiumUpgrade]]
)
```

#### `TierCapabilities`

Defines what features each tier grants access to.

```swift
enum MyTier: Int, ProductTierRepresentable {
    case free, pro
    var displayName: LocalizedStringResource { "Pro Tier" }
    var description: LocalizedStringResource { "Unlocks all premium features." }
    var tierLevel: Int { rawValue }
}

struct MyCapabilities: TierCapabilities {
    func allows(_ feature: Feature, for tier: MyTier) -> Bool {
        switch (feature, tier) {
        case (.premiumFeature, .pro): return true
        default: return false
        }
    }
}
```

## Product Model Protocols

| Protocol                    | Purpose                                                   |
| --------------------------- | --------------------------------------------------------- |
| `StoreProductRepresentable` | Describes StoreKit products, including type and grouping. |
| `ProductTierRepresentable`  | Defines tier hierarchy and metadata.                      |
| `EntitlementProvider`       | Interface for entitlement tracking.                       |
| `StoreIdentifiable`         | Provides case-based string identifiers.                   |

Example product enum:

```swift
enum MyProduct: String, StoreProductRepresentable {
    case proMonthly = "com.myapp.pro.monthly"
    case proYearly = "com.myapp.pro.yearly"

    var sortOrder: Int { self == .proMonthly ? 0 : 1 }
    var productType: Product.ProductType { .autoRenewable }

    static var groupedByTier: [MyTier: [Self]] {
        [.pro: [.proMonthly, .proYearly]]
    }
}
```

## Purchase States

`StoreManager` exposes granular `PurchaseState` values for each product:

| State                        | Meaning                                         |
| ---------------------------- | ----------------------------------------------- |
| `.ready(price:)`             | Product available for purchase.                 |
| `.purchasing`                | Currently processing purchase.                  |
| `.pending`                   | Awaiting confirmation.                          |
| `.failed(Error)`             | Purchase failed.                                |
| `.active(type:)`             | Active ownership (subscription or lifetime).    |
| `.cancelled(timeRemaining:)` | Subscription cancelled but active until expiry. |
| `.upcoming(activationDate:)` | Future upgrade or downgrade scheduled.          |

## Entitlement Flow

1. `EntitlementManager` observes StoreKit `Transaction.updates`.
1. Verified transactions update purchased IDs.
1. `StoreManager` syncs purchase states.
1. UI updates automatically via SwiftUI observation.

## Example Integration

```swift
@main
struct MyApp: App {
    @StateObject private var entitlementManager =
        EntitlementManager<MyProduct, MyTier, MyCapabilities>(config: MyCapabilities())

    @StateObject private var storeManager: StoreManager<MyProduct, MyTier, EntitlementManager<MyProduct, MyTier, MyCapabilities>>

    init() {
        _storeManager = StateObject(wrappedValue: StoreManager(
            entitlementManager: entitlementManager,
            config: .defaultConfig
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(storeManager)
        }
    }
}
```

## Contributing

Pull requests for new features, improvements, and documentation are welcome.

## License

`SKManager` is available under the MIT License. See the LICENCE file for details.
