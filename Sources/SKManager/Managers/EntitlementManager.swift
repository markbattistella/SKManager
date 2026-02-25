//
// Project: StoreManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import Foundation
import Observation
import StoreKit
import SimpleLogger

/// A manager responsible for tracking and updating the user's App Store entitlements.
///
/// `EntitlementManager` observes StoreKit transactions, validates entitlements, and determines
/// the user's current access tier based on active subscriptions or lifetime purchases. It serves
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

    /// Prevents `_performRefresh()` from overlapping with itself.
    @ObservationIgnored
    private var isRefreshing = false

    @ObservationIgnored
    private var lastRefreshTime = Date.distantPast

    @ObservationIgnored
    private let refreshCooldown: TimeInterval = 5

    @ObservationIgnored
    private let appLaunchTime = Date.now

    /// The configuration describing the app's capability rules and tier mappings.
    @ObservationIgnored
    private let config: Capabilities

    /// The continuation used to yield values into the `entitlementUpdates` stream.
    @ObservationIgnored
    private var entitlementContinuation: AsyncStream<Void>.Continuation?

    /// The fallback tier applied when no active entitlement or lifetime access exists.
    ///
    /// For example, an app may use a `.free` tier to represent users without a subscription.
    public var defaultTier: Group?

    /// The set of all product identifiers currently owned by the user.
    public var purchasedProductIDs: Set<String>

    /// The user's currently active subscription entitlement, if any.
    public var activeSubscription: SubscriptionEntitlement<Group>?

    /// The list of lifetime entitlements owned by the user.
    public var lifetimeEntitlements: [LifetimeEntitlement<Group>]

    /// The most recent error encountered during entitlement or transaction operations.
    public private(set) var lastError: Error?

    /// A closure executed whenever entitlements are refreshed.
    ///
    /// This callback is invoked after transaction updates or explicit refresh operations.
    @ObservationIgnored
    public var onRefresh: (() -> Void)?

    /// An asynchronous stream that emits a value whenever entitlements are refreshed.
    ///
    /// Use this stream in SwiftUI `.task` or background tasks to reactively handle entitlement
    /// updates without relying on callbacks.
    ///
    /// - Note: The stream and `onRefresh` callback are independent. Accessing this property
    ///   does not affect the callback, and vice versa. The stream is initialised once at creation.
    @ObservationIgnored
    public private(set) var entitlementUpdates: AsyncStream<Void>

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

        let (stream, continuation) = AsyncStream<Void>.makeStream()
        self.entitlementUpdates = stream
        self.entitlementContinuation = continuation

        // Start observing transactions early, but asynchronously.
        self.startObservingTransactions()

        // Perform initial entitlement refresh once StoreKit is ready.
        Task { @MainActor in
            await self.bootstrapEntitlements()
        }
    }

    /// - Warning: Temporary workaround for a Swift 6.2 compiler issue where `deinit` containing
    /// task cancellation causes build or archive failures. This method manually cancels the
    /// background StoreKit observation and expiry tasks (`updatesTask` and `expiryTask`) and
    /// should be called explicitly when tearing down the `EntitlementManager`. Remove this method
    /// and restore the standard `deinit` cleanup once the compiler bug is resolved.
    public func invalidate() {
        logger.info("EntitlementManager invalidated")
        updatesTask?.cancel()
        expiryTask?.cancel()
        updatesTask = nil
        expiryTask = nil
        entitlementContinuation?.finish()
        entitlementContinuation = nil
    }
}

// MARK: - Transaction Observation

extension EntitlementManager {

    /// Begins observing StoreKit transaction updates.
    ///
    /// This task listens for verified transactions and triggers an entitlement refresh
    /// whenever a purchase or renewal event occurs.
    private func startObservingTransactions() {
        updatesTask?.cancel()
        updatesTask = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }

            // Track processed transaction IDs to prevent acting on re-delivered updates.
            // StoreKit 2's transaction.finish() normally prevents re-delivery, but this
            // provides a safety net for rapid duplicate emissions within a session.
            var handledTransactionIDs = Set<String>()

            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }

                // Consumables are ephemeral and must be delivered before finishing.
                // Leave them for ConsumableManager to handle.
                guard transaction.productType != .consumable else { continue }

                guard handledTransactionIDs.insert(transaction.id.description).inserted else {
                    continue
                }

                await transaction.finish()
                Task { @MainActor in
                    await self.refreshEntitlements()
                }
            }
        }
    }
}

// MARK: - Bootstrapping

extension EntitlementManager {

    /// Attempts to load entitlements with retries to avoid StoreKit race conditions on launch.
    ///
    /// Calls `_performRefresh()` directly, bypassing the cooldown guard, so that all retry
    /// attempts execute regardless of how quickly they are scheduled.
    ///
    /// - Performs up to 5 attempts spaced 2 seconds apart.
    /// - Exits early if a valid entitlement is found.
    private func bootstrapEntitlements() async {
        let maxAttempts = 5
        let retryDelay: UInt64 = 2_000_000_000 // 2 seconds

        for attempt in 1...maxAttempts {
            await _performRefresh()

            if activeSubscription != nil || !lifetimeEntitlements.isEmpty {
                logger.info("Bootstrap succeeded on attempt \(attempt)")
                return
            }

            logger.info("Bootstrap attempt \(attempt) found no entitlements, retrying…")
            try? await Task.sleep(nanoseconds: retryDelay)
        }

        logger.warning("Bootstrap completed with no entitlements after \(maxAttempts) attempts")
    }
}

// MARK: - Entitlement Refresh

extension EntitlementManager {

    /// Refreshes all entitlements by scanning verified StoreKit transactions.
    ///
    /// Applies a cooldown to prevent rapid successive refreshes. For forced refreshes without
    /// the cooldown (e.g. during bootstrap), use `_performRefresh()` directly.
    ///
    /// - Note: This method should be called at launch and when the app becomes active.
    public func refreshEntitlements() async {
        if isRefreshing { return }
        let now = Date.now
        guard now.timeIntervalSince(lastRefreshTime) > refreshCooldown else {
            logger.debug("Skipping refresh within cooldown window")
            return
        }
        lastRefreshTime = now
        await _performRefresh()
    }

    /// Performs the actual entitlement refresh without cooldown or reentrancy guards.
    ///
    /// Updates active subscriptions, lifetime purchases, and purchased product identifiers.
    /// Notifies both the `onRefresh` callback and the `entitlementUpdates` stream when complete,
    /// and posts `.entitlementsDidRefresh`.
    private func _performRefresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        var activeSub: SubscriptionEntitlement<Group>?
        var lifetimes: [LifetimeEntitlement<Group>] = []
        var activeIDs: Set<String> = []

        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result else { continue }
            if let revoked = t.revocationDate, revoked <= Date.now {
                // These direct mutations serve the early-boot early-return path below,
                // where we return before reaching the bulk state assignments at the end
                // of this method. In the normal path they are overwritten by those
                // assignments and are therefore redundant but harmless.
                logger.info("Revoked entitlement detected for \(t.productID)")
                purchasedProductIDs.remove(t.productID)
                lifetimeEntitlements.removeAll { $0.productID == t.productID }
                if activeSubscription?.productID == t.productID {
                    activeSubscription = nil
                }
                continue
            }
            activeIDs.insert(t.productID)
            await handleTransaction(t, activeSub: &activeSub, lifetimes: &lifetimes)
        }

        // Guard against StoreKit returning an empty response during early boot.
        let hasPreviousEntitlements = !purchasedProductIDs.isEmpty
        let noCurrentEntitlements = activeSub == nil && lifetimes.isEmpty

        if noCurrentEntitlements && hasPreviousEntitlements {
            let bootElapsed = Date.now.timeIntervalSince(appLaunchTime)
            if bootElapsed < 10 {
                logger.info("Refresh ignored (early boot empty response)")
                return
            } else {
                logger.info("Entitlements cleared (user likely unsubscribed or expired)")
            }
        }

        activeSubscription = activeSub
        lifetimeEntitlements = lifetimes
        purchasedProductIDs = activeIDs

        expiryTask?.cancel()
        if let expiry = activeSub?.expirationDate {
            scheduleExpiryRefresh(at: expiry)
        }

        onRefresh?()
        entitlementContinuation?.yield()

        logger.info(
            "Entitlement refresh complete. Active tier: \(String(localized: self.activeTier?.displayName ?? "none")) | Expiry: \(self.activeSubscription?.expirationDate?.ISO8601Format() ?? "none")"
        )

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
    /// determines the appropriate tier using the `Item.groupedByTier` mapping and keeps the
    /// highest-tier subscription active when multiple subscriptions are present.
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
                lifetimes.append(LifetimeEntitlement(
                    productID: transaction.productID,
                    tier: group,
                    ownershipType: transaction.ownershipType
                ))

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
    /// This method extracts renewal and expiration details from the transaction's
    /// `subscriptionStatus`, determines the appropriate renewal action, and returns a
    /// `SubscriptionEntitlement` instance describing the user's current subscription state.
    ///
    /// - Parameters:
    ///   - transaction: The verified StoreKit transaction representing a subscription purchase.
    ///   - group: The tier group associated with the transaction's product.
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
                    lastError = error
                    action = .cancel(date: transaction.expirationDate)
            }
        }

        return SubscriptionEntitlement(
            productID: transaction.productID,
            tier: group,
            expirationDate: transaction.expirationDate,
            renewalAction: action,
            ownershipType: transaction.ownershipType
        )
    }

    /// Determines the product identifier of the next scheduled renewal, if it differs
    /// from the current subscription product.
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
            expiryTask = Task { @MainActor in await self.refreshEntitlements() }
            return
        }
        expiryTask = Task(priority: .background) { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            Task { @MainActor in
                await self.refreshEntitlements()
            }
        }
    }
}

// MARK: - Tier Access

extension EntitlementManager {

    /// The currently active tier, accounting for subscriptions and lifetime entitlements.
    ///
    /// Returns the raw active tier without applying the `defaultTier` fallback. For UI
    /// and capability checks that should fall back to `defaultTier`, use `effectiveTier`.
    private var activeTier: Group? {

        // Lifetime entitlements always override. Pick the most premium (lowest tierLevel)
        // in case the user owns multiple lifetime products across different tiers.
        if let lifetime = lifetimeEntitlements.min(by: { $0.tier.tierLevel < $1.tier.tierLevel }) {
            return lifetime.tier
        }

        // Active subscription handling
        if let sub = activeSubscription {
            if let expiry = sub.expirationDate {

                // If the expiry is in the future, user still has access (even if .cancelled)
                if expiry > Date.now { return sub.tier }
                return nil
            }
            // Subscriptions with no expiry (lifetime, promo, etc.)
            return sub.tier
        }

        // Nothing active
        return nil
    }

    /// The user's effective tier used to determine feature availability.
    ///
    /// Equivalent to the active tier with a fallback to `defaultTier` when no entitlement
    /// is active.
    public var effectiveTier: Group? {
        activeTier ?? defaultTier
    }
}

// MARK: - Access Level Abstraction

extension EntitlementManager {

    /// Represents a simplified abstraction of user access level.
    ///
    /// This type provides a minimal representation of access state derived from the effective
    /// tier. It is intended for high-level gating of features or UI presentation logic.
    public enum AccessLevel {
        case free
        case tier(Int)
    }

    /// The user's current access level, mapped to a simplified tier abstraction.
    ///
    /// Converts the effective entitlement tier into an `AccessLevel` for convenience in UI and
    /// capability checks.
    public var currentAccessLevel: AccessLevel {
        if let tier = effectiveTier {
            return .tier(tier.tierLevel)
        }
        return .free
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

    /// A concise summary of the user's current entitlement state.
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
