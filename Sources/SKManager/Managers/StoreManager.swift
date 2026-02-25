//
// Project: StoreManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import StoreKit
import Foundation
import SimpleLogger

/// A high-level manager that coordinates StoreKit product handling and user entitlements.
///
/// `StoreManager` is responsible for fetching available products, managing purchase states,
/// and responding to entitlement updates. It acts as the bridge between StoreKit and the app’s
/// entitlement layer, ensuring that product visibility and upgrade logic remain consistent
/// with the user’s current subscription or lifetime access.
///
/// - Note: This type is observable and runs on the main actor to ensure UI safety.
@MainActor
@Observable
public final class StoreManager<
    Item: StoreProductRepresentable,
    Group: ProductTierRepresentable,
    E: EntitlementProvider
> where Item.Tier == Group, E.Item == Item, E.Group == Group {

    // MARK: - Typealiases and Nested Types

    /// A convenience alias representing a collection of products grouped by tier.
    private typealias ProductBucket = Bucket<Group, Product>

    /// A container that associates a key with a set of related values.
    ///
    /// Used internally to group StoreKit products under their respective tiers.
    private struct Bucket<Key, Value> {
        /// The grouping key, typically a product tier.
        let key: Key
        /// The set of products belonging to the same group.
        let items: [Value]
    }

    // MARK: - Stored Properties

    /// Logger used for store and transaction-related diagnostics.
    @ObservationIgnored
    private let logger = SimpleLogger(category: .storeKit)

    /// The entitlement manager that provides current user entitlement information.
    @ObservationIgnored
    private let entitlementManager: E

    /// The configuration that defines lifetime tiers, upgrade permissions, and conflict logic.
    @ObservationIgnored
    private let config: StoreConfig<Group, Item>

    /// Optional product-visibility rules controlling which products appear in the storefront.
    @ObservationIgnored
    private let rules: StoreRules<Item>?

    /// The list of currently available StoreKit products.
    private var products: [Product] = []

    /// The grouped product buckets, organised by tier.
    private var buckets: [ProductBucket] = []

    /// The current purchase state for each product identifier.
    private var purchaseStates: [String: PurchaseState] = [:]

    /// The current product-fetch lifecycle state.
    private var fetchState: ProductFetchState = .idle

    /// Indicates whether the offer-code redemption sheet can be displayed.
    public var showOfferCodeRedemption: Bool

    /// Indicates whether the system subscription-management sheet can be shown.
    public var showManageSubscriptionsSheet: Bool

    /// A Boolean value indicating whether the manager is currently fetching product information.
    public var isFetching: Bool { fetchState == .fetching }

    /// The most recent error encountered during entitlement or transaction operations.
    public private(set) var lastError: Error?

    // MARK: - Initialization

    /// Creates a new store manager configured with an entitlement provider and optional store
    /// logic.
    ///
    /// This initializer links the store manager to an existing entitlement system so that
    /// entitlements and purchase states remain synchronised. When entitlements refresh, the
    /// manager automatically delays briefly before syncing its internal purchase state.
    ///
    /// - Parameters:
    ///   - entitlementManager: The entitlement provider responsible for exposing and refreshing
    ///   user entitlements.
    ///   - config: An optional store configuration describing upgrade and conflict rules.
    ///   - rules: Optional visibility rules that determine which products should appear in the
    ///   store UI.
    public init(
        entitlementManager: E,
        config: StoreConfig<Group, Item> = .defaultConfig,
        rules: StoreRules<Item>? = nil
    ) {
        self.entitlementManager = entitlementManager
        self.config = config
        self.rules = rules

        self.showOfferCodeRedemption = false
        self.showManageSubscriptionsSheet = false

        // Automatically resyncs purchase state after entitlements refresh.
        entitlementManager.onRefresh = { [weak self] in
            Task { @MainActor in
                self?.syncPurchaseStates()
            }
        }
    }
}

// MARK: - Product Fetching
extension StoreManager {

    /// Refreshes all store data including product listings and entitlement states.
    public func refreshAll() async {
        await fetchProducts()
        await entitlementManager.refreshEntitlements()
        syncPurchaseStates()
    }

    /// Fetches product metadata from the App Store for all available product identifiers.
    private func fetchProducts() async {
        fetchState = .fetching
        do {
            let ids = Item.allCases.map(\.rawValue)
            let fetched = try await Product.products(for: ids)
            products = fetched
            buckets = groupProducts(from: fetched)
            fetchState = .idle
        } catch {
            lastError = error
            fetchState = .failed(error)
        }
    }

    /// Groups fetched products by their associated tier.
    ///
    /// - Parameter products: The list of fetched `Product` objects.
    /// - Returns: An array of product buckets grouped by tier.
    private func groupProducts(from products: [Product]) -> [ProductBucket] {
        Item.groupedByTier.sorted { $0.key.tierLevel < $1.key.tierLevel }.map { (tier, ids) in
            let matches = products
                .compactMap { p -> (Item, Product)? in
                    guard let id = Item(rawValue: p.id) else { return nil }
                    return ids.contains(id) ? (id, p) : nil
                }
                .sorted { $0.0 < $1.0 }
                .map { $0.1 }
            return ProductBucket(key: tier, items: matches)
        }
    }
}

// MARK: - Purchasing

extension StoreManager {

    /// Initiates a purchase for the specified StoreKit product.
    ///
    /// This method starts the App Store purchase flow and handles all possible StoreKit outcomes,
    /// including success, cancellation, pending approval, and failure. On a successful, verified
    /// transaction, the purchase is finished, entitlements are refreshed, and internal purchase
    /// state is synchronised before returning.
    ///
    /// The returned `PurchaseOutcome` is intended to drive UI flow and control logic (such as
    /// advancing a paywall), and should not be used as a proxy for entitlement state, which is
    /// managed separately by the entitlement system.
    ///
    /// - Parameters:
    ///   - product: The StoreKit `Product` to purchase.
    ///   - options: Optional purchase options such as promotional offers or quantity. Defaults to
    ///   an empty set.
    /// - Returns: A `PurchaseOutcome` value describing the result of the attempted purchase.
    ///
    /// - Note: A `.success` result indicates that the transaction completed successfully and was
    /// verified, but entitlement propagation may still complete asynchronously.
    public func purchase(
        _ product: Product,
        options: Set<Product.PurchaseOption> = []
    ) async -> PurchaseOutcome {
        guard AppStore.canMakePayments else {
            purchaseStates[product.id] = .ready(price: product.displayPrice)
            return .failed(StoreError.purchasesUnavailable)
        }

        purchaseStates[product.id] = .purchasing

        do {
            let result = try await product.purchase(options: options)

            switch result {
                case let .success(.verified(transaction)):
                    await transaction.finish()
                    await entitlementManager.refreshEntitlements()
                    syncPurchaseStates()
                    return .success

                case let .success(.unverified(_, error)):
                    purchaseStates[product.id] = .failed(error)
                    lastError = error
                    return .failed(error)

                case .pending:
                    purchaseStates[product.id] = .pending
                    return .pending

                case .userCancelled:
                    purchaseStates[product.id] = .ready(price: product.displayPrice)
                    return .cancelled

                @unknown default:
                    purchaseStates[product.id] = .ready(price: product.displayPrice)
                    return .cancelled
            }
        } catch {
            lastError = error
            purchaseStates[product.id] = .failed(error)
            return .failed(error)
        }
    }

    /// Restores all previously purchased products and subscriptions from the App Store.
    public func restorePurchases() async {
        try? await AppStore.sync()
        await refreshAll()
    }
}

// MARK: - Product Filtering

extension StoreManager {

    /// Returns the list of visible products for a given tier, applying the visibility rules and
    /// ownership state.
    ///
    /// - Parameter group: The product tier to fetch products for.
    /// - Returns: The filtered array of `Product` instances visible to the user.
    public func products(for group: Group) -> [Product] {
        guard let bucket = buckets.first(where: { $0.key == group }) else { return [] }
        let owned = entitlementManager.purchasedProductIDs
        guard let rules else { return bucket.items }

        if rules.hiddenGroups(for: owned).contains(group) { return [] }

        let hidden = rules.hiddenProducts(for: owned)
        let visible = rules.visibleProducts(for: owned)

        return bucket.items.filter { product in
            guard let item = Item(rawValue: product.id) else { return false }

            if owned.isEmpty { return rules.defaultVisible.contains(item) }
            if visible.contains(item) { return true }
            if hidden.contains(item) { return false }
            if !rules.defaultVisible.contains(item) { return false }
            return true
        }
    }

    /// Retrieves a product by its identifier.
    ///
    /// - Parameter id: The product identifier.
    /// - Returns: The matching `Product`, or `nil` if not found.
    public func product(with id: String) -> Product? {
        self.products.first { $0.id == id }
    }
}

// MARK: - Purchase State Synchronisation

extension StoreManager {

    /// Synchronises the internal purchase state map with the current entitlement state.
    ///
    /// Called after entitlement refreshes or purchase updates to keep UI and logic in sync.
    private func syncPurchaseStates() {
        for product in products {
            purchaseStates[product.id] = .ready(price: product.displayPrice)
        }

        for lifetime in entitlementManager.lifetimeEntitlements {
            purchaseStates[lifetime.productID] = .active(type: .nonConsumable)
        }

        guard let sub = entitlementManager.activeSubscription else { return }

        let activeID = sub.productID
        if let product = products.first(where: { $0.id == activeID }) {
            if case .cancel(let expiry?) = sub.renewalAction {
                let remaining = max(0, expiry.timeIntervalSinceNow)
                if remaining > 0 {
                    purchaseStates[activeID] = .cancelled(timeRemaining: remaining)
                } else {
                    purchaseStates[activeID] = .ready(price: product.displayPrice)
                }
            } else {
                purchaseStates[activeID] = .active(type: product.type)
            }
        }

        switch sub.renewalAction {
            case .upgrade(_, let nextID, let date),
                 .crossgrade(let nextID, let date),
                 .downgrade(_, let nextID, let date):
                if products.contains(where: { $0.id == nextID }) {
                    purchaseStates[nextID] = .upcoming(activationDate: date)
                }

            default: break
        }
    }
}

// MARK: - Helpers

extension StoreManager {

    /// Returns the current purchase state for a product.
    ///
    /// - Parameter product: The product to check.
    /// - Returns: Its corresponding `PurchaseState`.
    public func purchaseState(for product: Product) -> PurchaseState {
        purchaseStates[product.id] ?? .ready(price: product.displayPrice)
    }

    /// Determines whether a product is currently active (purchased or not yet expired).
    public func isCurrentlyActive(_ product: Product) -> Bool {
        if case .active = purchaseState(for: product) { return true }
        if case .cancelled(let remaining) = purchaseState(for: product), remaining > 0 { return true }
        return false
    }

    /// Checks whether a product has any purchase-related activity such as active, cancelled, or
    /// upcoming state.
    public func hasAnyActivity(_ product: Product) -> Bool {
        switch purchaseState(for: product) {
            case .active, .cancelled, .upcoming:
                return true
            default:
                return false
        }
    }

    /// Returns whether the user can initiate a purchase for the given product.
    ///
    /// Returns `false` when purchases are device-restricted, or when the product is already
    /// active, upcoming, or currently being purchased.
    public func canPurchase(_ product: Product) -> Bool {
        guard AppStore.canMakePayments else { return false }
        switch purchaseState(for: product) {
            case .active, .upcoming, .purchasing: return false
            default: return true
        }
    }
}

// MARK: - Conflict Detection

extension StoreManager {

    /// Indicates whether the user owns conflicting products or tiers.
    ///
    /// Evaluates both tier-level and product-level conflicts as defined in `StoreConfig`.
    /// The underlying conflict logic lives on `StoreConfig.hasConflicts(activeTiers:ownedProducts:)`
    /// and can be tested independently.
    public var hasConflictingPlans: Bool {
        var activeTiers: Set<Group> = []
        for lifetime in entitlementManager.lifetimeEntitlements {
            activeTiers.insert(lifetime.tier)
        }
        if let tier = entitlementManager.activeSubscription?.tier {
            activeTiers.insert(tier)
        }
        return config.hasConflicts(
            activeTiers: activeTiers,
            ownedProducts: entitlementManager.purchasedProductIDs
        )
    }
}

// MARK: - Transaction History

extension StoreManager {

    /// Returns all verified transactions for the current account, regardless of product type.
    ///
    /// Useful for building a purchase history screen, auditing owned items, or providing
    /// a "Request Refund" flow where the app needs a transaction identifier.
    ///
    /// - Returns: All currently verified transactions from `Transaction.all`.
    public func allTransactions() async -> [Transaction] {
        var result: [Transaction] = []
        for await item in Transaction.all {
            if case .verified(let transaction) = item {
                result.append(transaction)
            }
        }
        return result
    }

    /// Returns the most recent verified transaction for the given product identifier, or `nil`
    /// if no transaction exists.
    ///
    /// - Parameter productID: The product identifier to look up.
    /// - Returns: The latest verified transaction, or `nil`.
    public func latestTransaction(for productID: String) async -> Transaction? {
        for await item in Transaction.all {
            if case .verified(let transaction) = item, transaction.productID == productID {
                return transaction
            }
        }
        return nil
    }
}

// MARK: - Supporting Types

extension StoreManager {

    /// Represents the fetch state of store products.
    internal enum ProductFetchState: Equatable {
        case idle, fetching, failed(Error)
        static func ==(l: Self, r: Self) -> Bool {
            switch (l, r) {
                case (.idle, .idle), (.fetching, .fetching), (.failed, .failed): return true
                default: return false
            }
        }
    }

    /// Represents the current purchase state of a specific product.
    public enum PurchaseState {

        /// Product is available for purchase.
        case ready(price: String)

        /// Purchase flow is in progress.
        case purchasing

        /// Purchase is awaiting user or App Store confirmation.
        case pending

        /// Purchase failed with an error.
        case failed(Error)

        /// Product is actively owned (non-consumable or subscription).
        case active(type: Product.ProductType)

        /// Subscription was cancelled but remains active for the remaining duration.
        case cancelled(timeRemaining: TimeInterval)

        /// Subscription is scheduled to activate or change in the future.
        case upcoming(activationDate: Date?)
    }
}

