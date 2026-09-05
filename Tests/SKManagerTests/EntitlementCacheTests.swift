//
// Project: SKManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import Foundation
import StoreKit
import Testing

@testable import SKManager

@MainActor
@Suite("Entitlement cache")
struct EntitlementCacheTests {
    private typealias Manager = EntitlementManager<CacheItem, MockTier, CacheCapabilities>
    private let cacheKey = "test.entitlements"

    @Test("A first launch uses the fallback tier without publishing a refresh")
    func firstLaunch() throws {
        try withDefaults { defaults in
            let manager = makeManager(defaults: defaults)
            #expect(manager.effectiveTier == .basic)
            #expect(manager.purchasedProductIDs.isEmpty)
            #expect(manager.resolutionState == .unresolved)
            #expect(manager.refreshCount == 0)
            #expect(defaults.data(forKey: cacheKey) == nil)
        }
    }

    @Test("Subscriptions hydrate before initialization returns", arguments: [false, true])
    func synchronousSubscriptionHydration(nonExpiring: Bool) throws {
        try withDefaults { defaults in
            let expiry: Date? = nonExpiring ? nil : Date.now.addingTimeInterval(3_600)
            try saveSnapshot(subscription: cachedSubscription(expiry: expiry), to: defaults)

            let manager = makeManager(defaults: defaults)
            #expect(manager.effectiveTier == .premium)
            #expect(manager.hasAccess(to: .export))
            #expect(manager.activeSubscription?.expirationDate == expiry)
            #expect(manager.activeSubscription?.renewalAction == nil)
            #expect(manager.activeSubscription?.isFamilyShared == true)
            #expect(manager.purchasedProductIDs == [CacheItem.monthly.rawValue])
            #expect(manager.resolutionState == .cached)
            #expect(manager.refreshCount == 0)
        }
    }

    @Test("Expired subscriptions do not restore access or purchased IDs")
    func expiredSubscription() throws {
        try withDefaults { defaults in
            try saveSnapshot(subscription: cachedSubscription(expiry: .distantPast), to: defaults)
            let manager = makeManager(defaults: defaults)
            #expect(manager.activeSubscription == nil)
            #expect(manager.purchasedProductIDs.isEmpty)
            #expect(manager.effectiveTier == .basic)
            #expect(!manager.hasAccess(to: .export))
            #expect(manager.resolutionState == .cached)
        }
    }

    @Test("Lifetime ownership survives alongside a lapsed subscription")
    func lifetimeHydration() throws {
        try withDefaults { defaults in
            try saveSnapshot(
                subscription: cachedSubscription(expiry: .distantPast),
                lifetimes: [cachedLifetime()],
                to: defaults
            )
            let manager = makeManager(defaults: defaults)
            #expect(manager.activeSubscription == nil)
            #expect(manager.effectiveTier == .standard)
            #expect(manager.purchasedProductIDs == [CacheItem.lifetime.rawValue])
            #expect(manager.lifetimeEntitlements.first?.isFamilyShared == true)
        }
    }

    @Test("Malformed or unsupported cache data leaves state unresolved", arguments: [
        "not JSON", "{}", "{\"version\":2,\"lifetimeEntitlements\":[]}"
    ])
    func invalidCache(json: String) throws {
        try withDefaults { defaults in
            defaults.set(Data(json.utf8), forKey: cacheKey)
            let manager = makeManager(defaults: defaults)
            #expect(manager.effectiveTier == .basic)
            #expect(manager.resolutionState == .unresolved)
            #expect(manager.purchasedProductIDs.isEmpty)
            #expect(manager.lastError == nil)
        }
    }

    @Test("Invalid product and tier mappings cannot hydrate access", arguments: [
        ("removed", "premium"), ("monthly", "removed"), ("monthly", "basic"),
        ("lifetime", "standard"), ("tip", "premium"), ("unmapped", "premium")
    ])
    func invalidSubscriptionMapping(productID: String, tier: String) throws {
        try withDefaults { defaults in
            let subscription = EntitlementSnapshot.CachedSubscription(
                productID: productID, tierRawValue: tier, expirationDate: nil,
                ownershipRawValue: Transaction.OwnershipType.purchased.rawValue
            )
            try saveSnapshot(subscription: subscription, to: defaults)
            let manager = makeManager(defaults: defaults)
            #expect(manager.activeSubscription == nil)
            #expect(manager.purchasedProductIDs.isEmpty)
            #expect(manager.effectiveTier == .basic)
        }
    }

    @Test("Lifetime hydration filters invalid entries independently")
    func invalidLifetimes() throws {
        try withDefaults { defaults in
            let invalid = [
                ("removed", "standard"), ("lifetime", "removed"), ("lifetime", "premium"),
                ("monthly", "premium"), ("tip", "premium"), ("unmapped", "premium")
            ].map { productID, tier in
                EntitlementSnapshot.CachedLifetime(
                    productID: productID, tierRawValue: tier,
                    ownershipRawValue: Transaction.OwnershipType.purchased.rawValue
                )
            }
            try saveSnapshot(lifetimes: invalid + [cachedLifetime()], to: defaults)
            let manager = makeManager(defaults: defaults)
            #expect(manager.lifetimeEntitlements.count == 1)
            #expect(manager.purchasedProductIDs == [CacheItem.lifetime.rawValue])
            #expect(manager.effectiveTier == .standard)
        }
    }

    @Test("An unchanged StoreKit snapshot confirms the cache and notifies once")
    func unchangedRefreshConfirmsCache() throws {
        try withDefaults { defaults in
            try saveSnapshot(lifetimes: [cachedLifetime()], to: defaults)
            let manager = makeManager(defaults: defaults)
            let lifetime = try #require(manager.lifetimeEntitlements.first)
            var callbackCount = 0
            manager.onRefresh = {
                callbackCount += 1
                #expect(manager.resolutionState == .confirmed)
                let data = defaults.data(forKey: cacheKey)
                let persisted = data.flatMap { try? JSONDecoder().decode(EntitlementSnapshot.self, from: $0) }
                #expect(persisted?.lifetimeEntitlements.first?.productID == lifetime.productID)
            }

            for _ in 0..<2 {
                manager.applyEntitlementRefresh(
                    activeSub: nil, lifetimes: [lifetime], purchasedIDs: [lifetime.productID]
                )
            }

            #expect(manager.resolutionState == .confirmed)
            #expect(manager.refreshCount == 1)
            #expect(callbackCount == 1)
            manager.onRefresh = nil
        }
    }

    @Test("Empty scans keep cached access only during the boot window", arguments: [false, true])
    func cacheReconciliation(lifetime: Bool) throws {
        try withDefaults { defaults in
            try saveSnapshot(
                subscription: lifetime ? nil : cachedSubscription(expiry: nil),
                lifetimes: lifetime ? [cachedLifetime()] : [],
                to: defaults
            )
            let originalData = defaults.data(forKey: cacheKey)
            let manager = makeManager(defaults: defaults)

            manager.applyEntitlementRefresh(activeSub: nil, lifetimes: [], purchasedIDs: [])
            #expect(manager.resolutionState == .cached)
            #expect(manager.effectiveTier != .basic)
            #expect(manager.refreshCount == 0)
            #expect(defaults.data(forKey: cacheKey) == originalData)

            manager.applyEntitlementRefresh(
                activeSub: nil, lifetimes: [], purchasedIDs: [],
                now: Date.now.addingTimeInterval(11)
            )
            #expect(manager.resolutionState == .confirmed)
            #expect(manager.effectiveTier == .basic)
            #expect(manager.purchasedProductIDs.isEmpty)
            #expect(manager.refreshCount == 1)

            let relaunched = makeManager(defaults: defaults)
            #expect(relaunched.resolutionState == .cached)
            #expect(relaunched.effectiveTier == .basic)
            #expect(relaunched.activeSubscription == nil)
            #expect(relaunched.lifetimeEntitlements.isEmpty)
        }
    }

    @Test("Confirmed subscription access still survives a temporary empty scan")
    func confirmedSubscriptionRetention() throws {
        try withDefaults { defaults in
            let manager = makeManager(defaults: defaults)
            defer { manager.invalidate() }
            let subscription = SubscriptionEntitlement(
                productID: CacheItem.monthly.rawValue, tier: MockTier.premium,
                expirationDate: Date.now.addingTimeInterval(3_600), renewalAction: nil,
                ownershipType: Transaction.OwnershipType.purchased
            )
            manager.applyEntitlementRefresh(
                activeSub: subscription, lifetimes: [], purchasedIDs: [subscription.productID]
            )
            manager.applyEntitlementRefresh(
                activeSub: nil, lifetimes: [], purchasedIDs: [],
                now: Date.now.addingTimeInterval(11)
            )

            #expect(manager.resolutionState == .confirmed)
            #expect(manager.effectiveTier == .premium)
            #expect(manager.refreshCount == 1)

            let relaunched = makeManager(defaults: defaults)
            #expect(relaunched.activeSubscription?.ownershipType == .purchased)
            #expect(relaunched.effectiveTier == .premium)
        }
    }

    @Test("Confirmed lifetime removal overwrites the persisted purchase")
    func lifetimeRemovalPersists() throws {
        try withDefaults { defaults in
            let manager = makeManager(defaults: defaults)
            let lifetime = LifetimeEntitlement(
                productID: CacheItem.lifetime.rawValue, tier: MockTier.standard,
                ownershipType: Transaction.OwnershipType.purchased
            )
            manager.applyEntitlementRefresh(
                activeSub: nil, lifetimes: [lifetime], purchasedIDs: [lifetime.productID]
            )
            #expect(makeManager(defaults: defaults).effectiveTier == .standard)

            manager.applyEntitlementRefresh(
                activeSub: nil, lifetimes: [], purchasedIDs: [],
                now: Date.now.addingTimeInterval(11)
            )
            #expect(makeManager(defaults: defaults).effectiveTier == .basic)
        }
    }

    @Test("Cache keys isolate managers sharing the same defaults store")
    func separateCacheKeys() throws {
        try withDefaults { defaults in
            try saveSnapshot(lifetimes: [cachedLifetime()], to: defaults)
            let manager = Manager(config: CacheCapabilities(), cacheKey: "separate", userDefaults: defaults)
            manager.invalidate()
            #expect(manager.resolutionState == .unresolved)
            #expect(manager.purchasedProductIDs.isEmpty)

            manager.applyEntitlementRefresh(activeSub: nil, lifetimes: [], purchasedIDs: [])
            #expect(makeManager(defaults: defaults).effectiveTier == .standard)
        }
    }

    @Test("Caching can be disabled")
    func disabledCache() {
        let key = "SKManagerTests.disabled.\(UUID().uuidString)"
        let manager = Manager(config: CacheCapabilities(), cacheKey: key, userDefaults: nil)
        manager.invalidate()
        #expect(manager.resolutionState == .unresolved)
        manager.applyEntitlementRefresh(activeSub: nil, lifetimes: [], purchasedIDs: [])
        #expect(manager.resolutionState == .confirmed)
        #expect(UserDefaults.standard.object(forKey: key) == nil)
    }

    @Test("The default cache key persists across manager instances and separates product types")
    func defaultCacheKey() throws {
        try withDefaults { defaults in
            let manager = Manager(config: CacheCapabilities(), userDefaults: defaults)
            manager.invalidate()
            let lifetime = LifetimeEntitlement(
                productID: CacheItem.lifetime.rawValue, tier: MockTier.standard,
                ownershipType: Transaction.OwnershipType.purchased
            )
            manager.applyEntitlementRefresh(
                activeSub: nil, lifetimes: [lifetime], purchasedIDs: [lifetime.productID]
            )

            // Private types must not put reflection's process-specific context address in the key.
            #expect(defaults.data(forKey: "SKManager.entitlements.CacheItem.MockTier") != nil)
            let relaunched = Manager(config: CacheCapabilities(), userDefaults: defaults)
            relaunched.invalidate()
            #expect(relaunched.resolutionState == .cached)
            #expect(relaunched.effectiveTier == .standard)

            let unrelated = EntitlementManager<MockItem, MockTier, CacheCapabilities>(
                config: CacheCapabilities(), userDefaults: defaults
            )
            unrelated.invalidate()
            #expect(unrelated.resolutionState == .unresolved)
        }
    }

    @Test("Terminal status updates persist removals without confirming other cached products")
    func terminalStatusPersists() throws {
        try withDefaults { defaults in
            try saveSnapshot(
                subscription: cachedSubscription(expiry: nil),
                lifetimes: [cachedLifetime()], to: defaults
            )
            let manager = makeManager(defaults: defaults)
            manager.clearEntitlement(for: CacheItem.monthly.rawValue, reason: "expired")
            #expect(manager.resolutionState == .cached)
            #expect(manager.refreshCount == 1)
            #expect(manager.activeSubscription == nil)
            #expect(manager.purchasedProductIDs == [CacheItem.lifetime.rawValue])
            #expect(makeManager(defaults: defaults).activeSubscription == nil)

            // An unchanged full scan must still confirm state after a partial live update.
            manager.applyEntitlementRefresh(
                activeSub: nil, lifetimes: manager.lifetimeEntitlements,
                purchasedIDs: manager.purchasedProductIDs
            )
            #expect(manager.resolutionState == .confirmed)
            #expect(manager.refreshCount == 2)

            manager.clearEntitlement(for: CacheItem.lifetime.rawValue, reason: "revoked")
            manager.clearEntitlement(for: CacheItem.lifetime.rawValue, reason: "revoked")
            #expect(manager.refreshCount == 3)
            #expect(manager.effectiveTier == .basic)
            #expect(makeManager(defaults: defaults).purchasedProductIDs.isEmpty)
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "SKManagerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    private func makeManager(defaults: UserDefaults) -> Manager {
        let manager = Manager(
            config: CacheCapabilities(), defaultTier: .basic,
            cacheKey: cacheKey, userDefaults: defaults
        )
        // These synchronous tests exercise cache and reconciliation without starting StoreKit.
        manager.invalidate()
        return manager
    }

    private func saveSnapshot(
        subscription: EntitlementSnapshot.CachedSubscription? = nil,
        lifetimes: [EntitlementSnapshot.CachedLifetime] = [],
        to defaults: UserDefaults
    ) throws {
        let snapshot = EntitlementSnapshot(activeSubscription: subscription, lifetimeEntitlements: lifetimes)
        defaults.set(try JSONEncoder().encode(snapshot), forKey: cacheKey)
    }

    private func cachedSubscription(expiry: Date?) -> EntitlementSnapshot.CachedSubscription {
        .init(
            productID: CacheItem.monthly.rawValue, tierRawValue: MockTier.premium.rawValue,
            expirationDate: expiry, ownershipRawValue: Transaction.OwnershipType.familyShared.rawValue
        )
    }

    private func cachedLifetime() -> EntitlementSnapshot.CachedLifetime {
        .init(
            productID: CacheItem.lifetime.rawValue, tierRawValue: MockTier.standard.rawValue,
            ownershipRawValue: Transaction.OwnershipType.familyShared.rawValue
        )
    }
}

private enum CacheItem: String, StoreProductRepresentable {
    case monthly, lifetime, tip, unmapped

    typealias Tier = MockTier
    var sortOrder: Int { 0 }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var productType: Product.ProductType {
        switch self {
            case .monthly, .unmapped: .autoRenewable
            case .lifetime: .nonConsumable
            case .tip: .consumable
        }
    }

    static var groupedByTier: [MockTier: [Self]] {
        [.premium: [.monthly, .tip], .standard: [.lifetime]]
    }
}

private struct CacheCapabilities: TierCapabilities {
    enum Feature { case export }
    var capabilities: [Feature: [MockTier: CapabilityRule]] {
        [.export: [.premium: .unrestricted, .basic: .unavailable]]
    }
}
