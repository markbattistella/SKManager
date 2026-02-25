<!-- markdownlint-disable MD033 MD041 -->
<div align="center">

# SKManager

![Swift Versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmarkbattistella%2FSKManager%2Fbadge%3Ftype%3Dswift-versions)
![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmarkbattistella%2FSKManager%2Fbadge%3Ftype%3Dplatforms)
![Licence](https://img.shields.io/badge/Licence-MIT-white?labelColor=blue&style=flat)

</div>

`SKManager` is a strongly typed StoreKit 2 framework for Swift. It handles product fetching, purchasing, and entitlement tracking across all four IAP types (auto-renewable, non-renewable, non-consumable, consumable), and adds a visibility rules system purpose-built for custom paywalls — where owning one product should affect which others are offered.

---

## Why SKManager?

Most StoreKit wrappers handle purchasing but leave display logic up to you. SKManager solves the harder problem: **how do you build a paywall where ownership of one product changes what else is shown?**

- Owning a family lifetime should hide the subscription tier entirely
- Being on a basic subscription should reveal a lifetime upgrade option
- Owning an annual plan should hide the monthly option
- Pro subscribers can export; free users cannot; family plans get everything

All of this is expressed declaratively through `StoreRules` and `TierCapabilities`, not ad-hoc `if` statements scattered through view code.

---

## Requirements

- iOS 17+, macOS 14+, tvOS 17+, watchOS 10+, visionOS 1+
- Swift 6

---

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/markbattistella/SKManager", from: "1.0.0")
]
```

Or in Xcode: **File → Add Package Dependencies** → `https://github.com/markbattistella/SKManager`

---

## Core Concepts

| Type | Role |
| --- | --- |
| `EntitlementManager` | Source of truth for what the user owns |
| `StoreManager` | Fetches products, drives purchases, exposes per-product states |
| `ConsumableManager` | Dedicated manager for consumable products (credits, tips, tokens) |
| `StoreRules` | Declarative visibility rules — what to show/hide based on ownership |
| `TierCapabilities` | Maps features to tiers with `CapabilityRule` values |
| `StoreConfig` | Declares which tiers/products conflict (should not coexist) |

---

## Setup

### 1. Define your tiers

```swift
enum AppTier: Int, ProductTierRepresentable {
    case pro       // tierLevel = 1  (most premium)
    case basic     // tierLevel = 2
    case family    // tierLevel = 3  (could be same or different)

    var displayName: LocalizedStringResource { ... }
    var description: LocalizedStringResource { ... }
    var tierLevel: Int { rawValue }
}
```

Lower `tierLevel` = more premium. This drives upgrade/downgrade detection.

### 2. Define your products

```swift
enum AppProduct: String, StoreProductRepresentable, CaseIterable {
    case proMonthly    = "com.app.pro.monthly"
    case proYearly     = "com.app.pro.yearly"
    case basicMonthly  = "com.app.basic.monthly"
    case familyLifetime = "com.app.family.lifetime"

    typealias Tier = AppTier

    var sortOrder: Int { ... }

    var productType: Product.ProductType {
        switch self {
        case .familyLifetime: return .nonConsumable
        default: return .autoRenewable
        }
    }

    static var groupedByTier: [AppTier: [AppProduct]] {
        [
            .pro:    [.proMonthly, .proYearly],
            .basic:  [.basicMonthly],
            .family: [.familyLifetime]
        ]
    }
}
```

### 3. Define your capabilities

```swift
enum Feature { case export, darkMode, cloudSync }

struct AppCapabilities: TierCapabilities {
    typealias Tier = AppTier
    typealias Feature = Feature
    typealias CapabilityValue = CapabilityRule

    var capabilities: [Feature: [AppTier: CapabilityRule]] {
        [
            .export:    [.pro: .unrestricted, .basic: .unavailable, .family: .unrestricted],
            .darkMode:  [.pro: .allowed(true), .basic: .allowed(true), .family: .allowed(true)],
            .cloudSync: [.pro: .unrestricted, .basic: .limit(30), .family: .unrestricted]
        ]
    }
}
```

### 4. Define your store rules

This is the key differentiator. `StoreRules` controls what appears on your paywall based on what the user already owns.

```swift
let rules = StoreRules<AppProduct>(
    // Products shown when user owns nothing
    defaultVisible: [.proMonthly, .proYearly, .basicMonthly],

    // When user owns X, hide Y from storefront
    hideMap: [
        .proYearly:  [.proMonthly],    // owning annual → hide monthly
        .basicMonthly: [.proMonthly]   // owning basic → hide pro monthly (show yearly upgrade instead)
    ],

    // When user owns X, show Y (normally hidden)
    showMap: [
        .basicMonthly: [.familyLifetime]   // on basic sub → reveal family lifetime
    ],

    // When user owns X, hide the entire tier group
    groupHideMap: [
        .familyLifetime: [.pro, .basic]    // owning family lifetime → hide all subscription tiers
    ]
)
```

### 5. Wire it together

```swift
@main
struct MyApp: App {

    @State private var entitlementManager = EntitlementManager<AppProduct, AppTier, AppCapabilities>(
        config: AppCapabilities(),
        defaultTier: nil  // nil = unauthenticated/free state
    )

    @State private var storeManager: MyStoreManager

    init() {
        let em = EntitlementManager<AppProduct, AppTier, AppCapabilities>(
            config: AppCapabilities()
        )
        _entitlementManager = State(initialValue: em)
        _storeManager = State(initialValue: MyStoreManager(
            entitlementManager: em,
            config: .defaultConfig,
            rules: rules
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(entitlementManager)
                .environment(storeManager)
        }
    }
}

// Subclass StoreManager to add your app-specific logic
@MainActor @Observable
final class MyStoreManager: StoreManager<AppProduct, AppTier, EntitlementManager<AppProduct, AppTier, AppCapabilities>> {}
```

> **Note:** Call `entitlementManager.invalidate()` and `consumableManager.invalidate()` when tearing
> down to cancel background tasks. This is a temporary workaround for a Swift 6.2 compiler issue.

---

## Displaying Products

`StoreManager.products(for:)` returns only the products the user should see for a given tier, after applying `StoreRules`.

```swift
struct PaywallView: View {
    @Environment(MyStoreManager.self) var store

    var body: some View {
        VStack {
            // Only shows products that pass visibility rules for the user's current ownership
            ForEach(store.products(for: .pro), id: \.id) { product in
                ProductRow(product: product, store: store)
            }
            ForEach(store.products(for: .basic), id: \.id) { product in
                ProductRow(product: product, store: store)
            }
        }
        .task { await store.refreshAll() }
    }
}
```

---

## Purchasing

```swift
let outcome = await store.purchase(product)
// or with promotional offers:
let outcome = await store.purchase(product, options: [.promotionalOffer(offerID: id, keyID: keyID, nonce: nonce, signature: signature, timestamp: ts)])

switch outcome {
case .success:   dismiss()
case .cancelled: break
case .pending:   showPendingBanner()
case .failed(let error):
    if let storeError = error as? StoreError, storeError == .purchasesUnavailable {
        showParentalControlsAlert()
    } else {
        showGenericError(error)
    }
}
```

Before showing a "Buy" button, use `canPurchase` to avoid presenting already-active products:

```swift
Button("Subscribe") {
    Task { await store.purchase(product) }
}
.disabled(!store.canPurchase(product))
```

---

## Purchase States

Each product has a `PurchaseState` you can read from `store.purchaseState(for: product)`:

| State | Meaning |
| --- | --- |
| `.ready(price:)` | Available for purchase |
| `.purchasing` | Purchase flow in progress |
| `.pending` | Awaiting parent/Ask to Buy approval |
| `.failed(Error)` | Purchase failed |
| `.active(type:)` | Currently owned and active |
| `.cancelled(timeRemaining:)` | Cancelled but access continues until expiry |
| `.upcoming(activationDate:)` | Scheduled upgrade or downgrade |

```swift
switch store.purchaseState(for: product) {
case .active:
    Label("Current plan", systemImage: "checkmark.circle.fill")
case .cancelled(let remaining):
    Text("Expires in \(remaining.formatted())")
case .upcoming(let date):
    Text("Activates \(date?.formatted() ?? "soon")")
default:
    Text(product.displayPrice)
}
```

---

## Feature Access

Check capabilities from `EntitlementManager`:

```swift
@Environment(EntitlementManager<AppProduct, AppTier, AppCapabilities>.self) var entitlements

// Can the user export?
if entitlements.hasAccess(to: .export) { ... }

// How many months of history can they see?
let months = entitlements.limit(for: .cloudSync) ?? 0

// When does their trial feature expire?
let expiry = entitlements.expiry(for: .darkMode)

// What tier are they on?
switch entitlements.effectiveTier {
case .pro:    showProUI()
case .basic:  showBasicUI()
case .family: showFamilyUI()
case nil:     showFreeUI()
}
```

### `CapabilityRule` values

| Rule | `isAccessible` | Use case |
| --- | --- | --- |
| `.allowed(true)` | `true` | Simple on/off toggle |
| `.allowed(false)` | `false` | Feature blocked for tier |
| `.limit(n)` | `true` | Access with quantity cap (check `.limit`) |
| `.until(date)` | `date > now` | Time-bounded access |
| `.unrestricted` | `true` | Full access, no limit |
| `.unavailable` | `false` | Feature does not exist at this tier |

---

## Family Sharing

Both `LifetimeEntitlement` and `SubscriptionEntitlement` expose ownership type:

```swift
if let sub = entitlements.activeSubscription, sub.isFamilyShared {
    Text("Shared via Family Sharing")
}

for lifetime in entitlements.lifetimeEntitlements where lifetime.isFamilyShared {
    Text("\(lifetime.productID) is family shared")
}
```

---

## Consumables

Use `ConsumableManager` for credits, hearts, tip-jar purchases, or anything that can be bought multiple times.

```swift
@State private var consumableManager = ConsumableManager<AppProduct>()

// Set the delivery handler before any purchase can occur.
// This is called with a verified transaction before it is finished.
consumableManager.onDeliver = { transaction in
    switch AppProduct(rawValue: transaction.productID) {
    case .credits100: await creditsStore.add(100)
    case .credits500: await creditsStore.add(500)
    default: break
    }
}

// Load products
await consumableManager.fetchProducts()

// Purchase
let outcome = await consumableManager.purchase(product)
```

The handler is guaranteed to be called before `transaction.finish()`. If the app crashes between purchase and delivery, the transaction re-delivers on the next launch.

---

## Conflict Detection

Use `StoreConfig` to declare which tiers or products should never coexist. `StoreManager.hasConflictingPlans` reports whether the current user state violates any rule — useful for support diagnostics or admin tooling.

```swift
let config = StoreConfig<AppTier, AppProduct>(
    conflictGroups: [.pro: [.basic]],        // pro and basic subscriptions simultaneously
    conflictProducts: [.proYearly: [.proMonthly]]  // both billing periods
)

if store.hasConflictingPlans {
    // Prompt user to contact support
}
```

You can also call `config.hasConflicts(activeTiers:ownedProducts:)` directly in your own code or tests, without needing a store instance.

---

## Transaction History

```swift
// Full history (for a "Purchases" screen or refund support)
let transactions = await store.allTransactions()

// Most recent transaction for a specific product
if let tx = await store.latestTransaction(for: "com.app.pro.monthly") {
    // Pass tx.id to Apple's refund request API if needed
}
```

---

## SwiftUI Sheet Helpers

`StoreManager` exposes two booleans that wire directly to SwiftUI's subscription management modifiers:

```swift
Button("Manage Subscription") {
    store.showManageSubscriptionsSheet = true
}
.manageSubscriptionsSheet(isPresented: Binding(
    get: { store.showManageSubscriptionsSheet },
    set: { store.showManageSubscriptionsSheet = $0 }
))

Button("Redeem Offer Code") {
    store.showOfferCodeRedemption = true
}
.offerCodeRedemption(isPresented: Binding(
    get: { store.showOfferCodeRedemption },
    set: { store.showOfferCodeRedemption = $0 }
))
```

---

## Protocols

Implement these to integrate SKManager with your app's product/tier model:

| Protocol | Required members |
| --- | --- |
| `StoreProductRepresentable` | `rawValue: String`, `sortOrder`, `productType`, `groupedByTier`, `Tier` |
| `ProductTierRepresentable` | `displayName`, `description`, `tierLevel: Int` |
| `TierCapabilities` | `capabilities`, `isAccessible(_:)` |
| `EntitlementProvider` | Implement a custom entitlement backend instead of `EntitlementManager` |

---

## Contributing

Pull requests for bug fixes, improvements, and documentation are welcome.

## License

`SKManager` is available under the MIT License. See the LICENCE file for details.
