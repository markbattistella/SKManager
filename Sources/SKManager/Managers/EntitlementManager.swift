//
// Project: StoreManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import Foundation
import Observation
import StoreKit
import SimpleLogger

/// A manager responsible for tracking and updating the user’s App Store entitlements.
///
/// `EntitlementManager` observes StoreKit transactions, validates entitlements, and determines
/// the user’s current access tier based on active subscriptions or lifetime purchases. It serves
/// as the single source of truth for product ownership and feature availability.
///
/// - Note: Runs on the main actor and is observable for SwiftUI integration.
@MainActor
@Observable
public final class EntitlementManager<
    Item: StoreProductRepresentable,
    Group: ProductTierRepresentable,
    Capabilities: TierCapabilities
>: EntitlementProvider where Item.Tier == Group, Capabilities.Tier == Group {

    // MARK: - Properties

    /// Logger used for entitlement and StoreKit event reporting.
    private let logger = SimpleLogger(category: .storeKit)

    /// The asynchronous task that listens for StoreKit transaction updates.
    @ObservationIgnored
    private var updatesTask: Task<Void, Never>?

    /// The scheduled task that refreshes entitlements when a subscription expires.
    @ObservationIgnored
    private var expiryTask: Task<Void, Never>?

    /// The configuration describing the app’s capability rules and tier mappings.
    private let config: Capabilities

    /// The fallback tier applied when no active entitlement or lifetime access exists.
    ///
    /// For example, an app may use a `.free` tier to represent users without a subscription.
    public var defaultTier: Group?

    /// The set of all product identifiers currently owned by the user.
    public var purchasedProductIDs: Set<String>

    /// The user’s currently active subscription entitlement, if any.
    public var activeSubscription: SubscriptionEntitlement<Group>?

    /// The list of lifetime entitlements owned by the user.
    public var lifetimeEntitlements: [LifetimeEntitlement<Group>]

    /// The list of consumable product balances (e.g., in-app credits or tokens).
    public var consumables: [ConsumableBalance]

    /// A closure executed whenever entitlements are refreshed.
    ///
    /// This callback is invoked after transaction updates or explicit refresh operations.
    public var onRefresh: (() -> Void)?

    // MARK: - Initialization

    /// Creates a new entitlement manager configured with the specified capability set.
    ///
    /// - Parameters:
    ///   - config: The tier-capability configuration defining feature access and limits.
    ///   - defaultTier: An optional fallback tier to apply when no entitlements are active.
    public init(config: Capabilities, defaultTier: Group? = nil) {
        self.expiryTask = nil
        self.defaultTier = defaultTier
        self.config = config
        self.purchasedProductIDs = []
        self.activeSubscription = nil
        self.lifetimeEntitlements = []
        self.consumables = []
        self.startObservingTransactions()
    }

    /// Cancels all running background tasks before the manager is deallocated.
//    deinit {
//        updatesTask?.cancel()
//        expiryTask?.cancel()
//    }

    public func invalidate() {
        updatesTask?.cancel()
        expiryTask?.cancel()
        updatesTask = nil
        expiryTask = nil

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

    /// Refreshes all entitlements by scanning verified StoreKit transactions.
    ///
    /// Updates active subscriptions, lifetime purchases, and purchased product identifiers.
    /// Posts `.entitlementsDidRefresh` when complete.
    ///
    /// - Note: This method should be called at launch and when the app becomes active.
    public func refreshEntitlements() async {
        var activeSub: SubscriptionEntitlement<Group>?
        var lifetimes: [LifetimeEntitlement<Group>] = []
        var activeIDs: Set<String> = []

        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result else { continue }
            if let revoked = t.revocationDate, revoked <= Date() { continue }

            activeIDs.insert(t.productID)
            await handleTransaction(t, activeSub: &activeSub, lifetimes: &lifetimes)
        }

        activeSubscription = activeSub
        lifetimeEntitlements = lifetimes
        purchasedProductIDs = activeIDs

        expiryTask?.cancel()
        if case .cancel(let date?) = activeSub?.renewalAction {
            scheduleExpiryRefresh(at: date)
        }

        onRefresh?()
        NotificationCenter.default.post(
            name: .entitlementsDidRefresh,
            object: self,
            userInfo: ["entitlements": "refreshed"]
        )
    }

    /// Processes a verified StoreKit transaction and updates local entitlement state.
    ///
    /// This method classifies the transaction by product type and updates either the active
    /// subscription, the list of lifetime entitlements, or logs consumable purchases. It
    /// determines the appropriate tier using the `Item.groupedByTier` mapping and ensures that
    /// the highest-priority subscription tier remains active.
    ///
    /// - Parameters:
    ///   - transaction: The verified StoreKit transaction to process.
    ///   - activeSub: An in-out reference to the current active subscription entitlement, updated
    ///   if the transaction represents a higher-tier or initial subscription.
    ///   - lifetimes: An in-out collection of lifetime entitlements, appended to when the
    ///   transaction represents a non-consumable (lifetime) product.
    ///
    /// - Note: Consumable transactions are logged but do not affect entitlement state.
    private func handleTransaction(
        _ transaction: Transaction,
        activeSub: inout SubscriptionEntitlement<Group>?,
        lifetimes: inout [LifetimeEntitlement<Group>]
    ) async {
        guard let group = Item.groupedByTier
            .first(where: { $0.value.contains(where: { $0.rawValue == transaction.productID }) })?.key
        else { return }

        switch transaction.productType {
            case .autoRenewable, .nonRenewable:
                let sub = await buildSubscription(from: transaction, group: group)
                if let existing = activeSub, group.tierLevel < existing.tier.tierLevel {
                    activeSub = sub
                } else if activeSub == nil {
                    activeSub = sub
                }

            case .nonConsumable:
                lifetimes.append(LifetimeEntitlement(productID: transaction.productID, tier: group))

            case .consumable:
                logger.info("Consumable \(transaction.productID) purchased (tip jar style).")

            default:
                break
        }
    }
}

// MARK: - Subscription Building
extension EntitlementManager {

    /// Builds a subscription entitlement model from a verified StoreKit transaction.
    ///
    /// This method extracts renewal and expiration details from the transaction’s
    /// `subscriptionStatus`, determines the appropriate renewal action, and returns a
    /// `SubscriptionEntitlement` instance describing the user’s current subscription state.
    ///
    /// - Parameters:
    ///   - transaction: The verified StoreKit transaction representing a subscription purchase.
    ///   - group: The tier group associated with the transaction’s product.
    ///
    /// - Returns: A `SubscriptionEntitlement` object populated with product, tier, expiration,
    /// and renewal information.
    ///
    /// - Note: Unverified renewal information logs a warning and defaults to a cancelled state.
    private func buildSubscription(
        from transaction: Transaction,
        group: Group
    ) async -> SubscriptionEntitlement<Group> {
        var action: SubscriptionEntitlement<Group>.RenewalAction?

        if let status = await transaction.subscriptionStatus {
            switch status.renewalInfo {
                case .verified(let info):
                    action = renewalAction(for: info, transaction: transaction, group: group)

                case .unverified(let info, let error):
                    logger.warning("Unverified renewal info: \(info.debugDescription), error: \(error)")
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

    /// Determines the product identifier of the next scheduled renewal, if it differs
    /// from the current subscription product.
    ///
    /// This helper examines the renewal information to detect plan upgrades or downgrades
    /// and returns the identifier of the product that will renew next.
    ///
    /// - Parameters:
    ///   - info: The verified subscription renewal information from StoreKit.
    ///   - currentID: The identifier of the currently active subscription product.
    ///
    /// - Returns: The identifier of the next renewal product if different from the current one,
    ///   or `nil` if the subscription will renew under the same product.
    private func nextRenewalProductID(
        from info: Product.SubscriptionInfo.RenewalInfo,
        currentID: String
    ) -> String? {
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

// MARK: - Tier Access

extension EntitlementManager {

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

// MARK: - Capability Access

extension EntitlementManager where Capabilities.CapabilityValue == CapabilityRule {

    /// Checks whether the current user has access to the specified feature.
    public func hasAccess(to feature: Capabilities.Feature) -> Bool {
        let tier = activeTier ?? defaultTier
        guard let tier,
              let capability = config.capability(for: feature, in: tier) else {
            return false
        }
        return config.isAccessible(capability)
    }

    /// Returns the limit value for a feature, if defined.
    ///
    /// For example, the number of months of data visible under a `.limit(Int)` rule.
    public func limit(for feature: Capabilities.Feature) -> Int? {
        let tier = activeTier ?? defaultTier
        guard let tier,
              case .limit(let value)? = config.capability(for: feature, in: tier) else {
            return nil
        }
        return value
    }

    /// Returns the expiry date for a feature, if defined.
    ///
    /// For `.until(Date)` rules, this indicates when access ends.
    public func expiry(for feature: Capabilities.Feature) -> Date? {
        let tier = activeTier ?? defaultTier
        guard let tier,
              case .until(let date)? = config.capability(for: feature, in: tier) else {
            return nil
        }
        return date
    }
}

// MARK: - Metadata

extension EntitlementManager {

    /// A concise summary of the user’s current entitlement state.
    ///
    /// Includes tier name, product ID, renewal action, next tier, and expiration details.
    public var metadataSummary: [String: String] {
        var info: [String: String] = [:]

        if let sub = activeSubscription {
            info["tier"] = String(localized: sub.tier.displayName)
            info["product"] = sub.productID

            if let expiry = sub.expirationDate {
                info["expires"] = expiry.ISO8601Format()
            }

            guard let renewal = sub.renewalAction else { return info }

            switch renewal {
                case .renewSame(let group, let date):
                    info["renewalAction"] = "renew"
                    info["renewsAs"] = String(localized: group.displayName)
                    if let date { info["renewsOn"] = date.ISO8601Format() }

                case .upgrade(let group, _, let date):
                    info["renewalAction"] = "upgrade"
                    info["nextTier"] = String(localized: group.displayName)
                    if let date { info["effectiveOn"] = date.ISO8601Format() }

                case .downgrade(let group, _, let date):
                    info["renewalAction"] = "downgrade"
                    info["nextTier"] = String(localized: group.displayName)
                    if let date { info["effectiveOn"] = date.ISO8601Format() }

                case .cancel(let date):
                    info["renewalAction"] = "cancel"
                    if let date { info["expiresOn"] = date.ISO8601Format() }

                default:
                    break
            }

        } else if let lifetime = lifetimeEntitlements.first {
            info["tier"] = String(localized: lifetime.tier.displayName)
            info["product"] = lifetime.productID
            info["expires"] = "never"

        } else {
            info["tier"] = "none"
            info["product"] = "none"
        }

        return info
    }
}


// MARK: - Notifications

extension Notification.Name {

    /// Posted whenever entitlements finish refreshing.
    public static let entitlementsDidRefresh = Notification.Name("EntitlementsDidRefresh")
}
