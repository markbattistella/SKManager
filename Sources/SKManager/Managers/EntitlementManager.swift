//
// Project: StoreManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import Foundation
import Observation
import StoreKit
import SimpleLogger

/// A manager responsible for tracking and updating the user’s App Store entitlements, including
/// subscriptions, lifetime purchases, and consumable products.
///
/// The `EntitlementManager` listens to StoreKit transaction updates, validates entitlements, and
/// determines the user’s current access tier based on active purchases.
///
/// - Note: This class runs on the main actor and is observable for use in SwiftUI.
@MainActor
@Observable
public final class EntitlementManager<
    Item: StoreProductRepresentable,
    Group: ProductTierRepresentable,
    Capabilities: TierCapabilities
>: EntitlementProvider where Item.Tier == Group, Capabilities.Tier == Group {

    // MARK: - Properties

    private let logger = SimpleLogger(category: .storeKit)
    private var updatesTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private let config: Capabilities

    public var purchasedProductIDs: Set<String>
    public var activeSubscription: SubscriptionEntitlement<Group>?
    public var lifetimeEntitlements: [LifetimeEntitlement<Group>]
    public var consumables: [ConsumableBalance]

    public var onRefresh: (() -> Void)?

    // MARK: - Initialization

    /// Creates a new entitlement manager configured with the provided tier capabilities.
    ///
    /// - Parameter config: The app’s tier capability configuration.
    public init(config: Capabilities) {
        self.expiryTask = nil
        self.config = config
        self.purchasedProductIDs = []
        self.activeSubscription = nil
        self.lifetimeEntitlements = []
        self.consumables = []
        self.startObservingTransactions()
    }

    isolated deinit {
        updatesTask?.cancel()
        expiryTask?.cancel()
    }
}

// MARK: - Transaction Observation

extension EntitlementManager {

    /// Begins observing StoreKit transaction updates.
    ///
    /// This task listens for verified transactions and triggers an entitlement refresh
    /// whenever a purchase or renewal event occurs.
    private func startObservingTransactions() {
        updatesTask = Task(priority: .background) { [weak self] in
            guard let self else { return }
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                await transaction.finish()
                await self.refreshEntitlements()
            }
        }
    }
}

// MARK: - Entitlement Refresh

extension EntitlementManager {

    /// Refreshes the user’s entitlements by validating the latest App Store transactions.
    ///
    /// Updates active subscriptions, lifetime entitlements, and purchased product IDs. Invokes
    /// `onRefresh` when the refresh is complete.
    public func refreshEntitlements() async {
        var activeSub: SubscriptionEntitlement<Group>?
        var lifetimes: [LifetimeEntitlement<Group>] = []
        var activeIDs: Set<String> = []

        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result else { continue }
            if let revoked = t.revocationDate, revoked <= Date() { continue }

            activeIDs.insert(t.productID)
            guard let group = Item.groupedByTier
                .first(where: { $0.value.contains(where: { $0.rawValue == t.productID }) })?.key
            else { continue }

            switch t.productType {
                case .autoRenewable, .nonRenewable:
                    let sub = await buildSubscription(from: t, group: group)
                    if let existing = activeSub, group.tierLevel < existing.tier.tierLevel {
                        activeSub = sub
                    } else if activeSub == nil {
                        activeSub = sub
                    }

                case .nonConsumable:
                    lifetimes.append(LifetimeEntitlement(productID: t.productID, tier: group))

                case .consumable:
                    logger.info("Consumable \(t.productID) purchased (tip jar style).")

                default: break
            }
        }

        self.activeSubscription = activeSub
        self.lifetimeEntitlements = lifetimes
        self.purchasedProductIDs = activeIDs

        expiryTask?.cancel()
        if case .cancel(let date?) = activeSub?.renewalAction {
            scheduleExpiryRefresh(at: date)
        }

        self.onRefresh?()
    }
}

// MARK: - Subscription Building
extension EntitlementManager {

    /// Builds a `SubscriptionEntitlement` instance from a StoreKit transaction.
    ///
    /// - Parameters:
    ///   - transaction: The StoreKit transaction representing the subscription.
    ///   - group: The product tier associated with the transaction.
    /// - Returns: A fully configured `SubscriptionEntitlement` object.
    private func buildSubscription(from transaction: Transaction, group: Group) async -> SubscriptionEntitlement<Group> {
        var action: SubscriptionEntitlement<Group>.RenewalAction?

        if let status = await transaction.subscriptionStatus {
            switch status.renewalInfo {
                case .verified(let info):
                    action = renewalAction(for: info, transaction: transaction, group: group)

                case .unverified(let info, let error):
                    logger
                        .warning("Unverified renewal info: \(info.debugDescription), error: \(error)")
                    action = .cancel(date: transaction.expirationDate)
            }
        }

        return SubscriptionEntitlement(
            productID: transaction.productID,
            tier: group,
            expirationDate: transaction.expirationDate,
            renewalAction: action
        )
    }

    /// Determines the next renewal product identifier, if different from the current one.
    private func nextRenewalProductID(from info: Product.SubscriptionInfo.RenewalInfo, currentID: String) -> String? {
        if let preference = info.autoRenewPreference, preference != currentID { return preference }
        let candidate = info.currentProductID
        return candidate == currentID ? nil : candidate
    }

    /// Determines the renewal action that applies to a subscription.
    ///
    /// - Parameters:
    ///   - info: The renewal information from StoreKit.
    ///   - transaction: The current transaction.
    ///   - group: The tier associated with the current subscription.
    /// - Returns: The computed renewal action.
    private func renewalAction(
        for info: Product.SubscriptionInfo.RenewalInfo,
        transaction: Transaction,
        group: Group
    ) -> SubscriptionEntitlement<Group>.RenewalAction {
        if info.willAutoRenew {
            if let nextID = nextRenewalProductID(from: info, currentID: transaction.productID),
               let nextGroup = Item.groupedByTier.first(where: {
                   $0.value.contains(where: { $0.rawValue == nextID })
               })?.key {
                if nextGroup.tierLevel < group.tierLevel {
                    return .upgrade(to: nextGroup, nextProductID: nextID, date: info.renewalDate)
                } else if nextGroup.tierLevel > group.tierLevel {
                    return .downgrade(to: nextGroup, nextProductID: nextID, date: info.renewalDate)
                } else {
                    return .crossgrade(nextProductID: nextID, date: info.renewalDate)
                }
            } else {
                return .renewSame(plan: group, date: info.renewalDate)
            }
        } else {
            return .cancel(date: transaction.expirationDate)
        }
    }
}

// MARK: - Expiry Scheduling
extension EntitlementManager {

    /// Schedules a refresh to occur when a subscription reaches its expiry date.
    ///
    /// - Parameter date: The scheduled expiration date.
    private func scheduleExpiryRefresh(at date: Date) {
        expiryTask?.cancel()
        let delay = date.timeIntervalSinceNow
        guard delay > 0 else {
            Task { await refreshEntitlements() }
            return
        }
        expiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await self?.refreshEntitlements()
        }
    }
}

// MARK: - Feature Access

extension EntitlementManager {
    /// Determines whether the user currently has access to a given feature.
    ///
    /// - Parameter feature: The feature being checked.
    /// - Returns: `true` if access is granted, otherwise `false`.
    public func hasAccess(to feature: Capabilities.Feature) -> Bool {
        guard let tier = activeTier else { return false }
        return config.allows(feature, for: tier)
    }

    /// Alias for `hasAccess(to:)` to allow concise access checking syntax.
    public func check(_ feature: Capabilities.Feature) -> Bool {
        hasAccess(to: feature)
    }

    /// The currently active tier, accounting for subscriptions and lifetime entitlements.
    private var activeTier: Group? {
        if let lifetime = lifetimeEntitlements.first { return lifetime.tier }
        if let sub = activeSubscription {
            if case .cancel(let expiry?) = sub.renewalAction, expiry.timeIntervalSinceNow <= 0 {
                return nil
            }
            return sub.tier
        }
        return nil
    }

    /// The user’s effective tier used to determine feature availability.
    public var effectiveTier: Group? {
        if let lifetime = lifetimeEntitlements.first { return lifetime.tier }
        if let sub = activeSubscription {
            if case .cancel(let expiry?) = sub.renewalAction, expiry.timeIntervalSinceNow <= 0 {
                return nil
            }
            return sub.tier
        }
        return nil
    }
}
