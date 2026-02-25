//
// Project: SKManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import StoreKit
import Foundation
import SimpleLogger

/// A manager responsible for fetching, purchasing, and delivering consumable in-app products.
///
/// `ConsumableManager` handles the full StoreKit lifecycle for consumable products — products
/// that can be purchased multiple times and whose effect must be applied by the app on each
/// delivery (e.g. credits, hearts, tokens, or tip-jar purchases).
///
/// Unlike subscriptions and non-consumables, consumable transactions are **not** persisted by
/// StoreKit after `transaction.finish()` is called. `ConsumableManager` guarantees that
/// `onDeliver` is always called before `finish()`, so that if the app crashes between purchase
/// and delivery the transaction re-delivers on the next launch.
///
/// ### Usage
/// ```swift
/// let consumableManager = ConsumableManager<StoreItem>()
/// consumableManager.onDeliver = { transaction in
///     guard let item = StoreItem(rawValue: transaction.productID) else { return }
///     await livesManager.addHearts(item.hearts)
/// }
/// await consumableManager.fetchProducts()
/// ```
///
/// - Note: This manager only processes transactions whose `productType` is `.consumable`.
///   Subscriptions and non-consumables are handled by `EntitlementManager`.
@MainActor
@Observable
public final class ConsumableManager<Item: StoreProductRepresentable> {

    // MARK: - Stored Properties

    /// Logger used for consumable purchase diagnostics.
    @ObservationIgnored
    private let logger = SimpleLogger(category: .storeKit)

    /// Background task observing `Transaction.updates` for consumable re-deliveries.
    @ObservationIgnored
    private var updatesTask: Task<Void, Never>?

    /// Tracks transaction IDs already handled this session to prevent double-delivery.
    ///
    /// StoreKit 2's `transaction.finish()` normally prevents re-delivery across sessions.
    /// This set guards against duplicate emissions within a single session (e.g. rapid retries).
    @ObservationIgnored
    private var handledTransactionIDs: Set<String> = []

    /// The fetched consumable products available for purchase.
    public private(set) var products: [Product] = []

    /// Whether product metadata is currently being fetched.
    public private(set) var isFetching: Bool = false

    /// The most recent error encountered during fetching or purchasing.
    public private(set) var lastError: Error?

    /// Called with a verified consumable transaction immediately before `transaction.finish()`.
    ///
    /// **This is where you apply the consumable's effect** (add credits, unlock content, etc.).
    /// The transaction is finished only after this handler returns, so if the app crashes during
    /// handling the transaction re-delivers on the next launch.
    ///
    /// The handler is called on the main actor. Keep it fast; offload heavy work asynchronously.
    ///
    /// - Important: Your handler must be idempotent. If `onDeliver` is called, the transaction
    ///   will always be finished afterward, but the app is responsible for ensuring that
    ///   duplicate deliveries (e.g. crash-recovery re-deliveries) don't credit the user twice.
    @ObservationIgnored
    public var onDeliver: ((Transaction) async -> Void)?

    // MARK: - Initialization

    /// Creates a new consumable manager and immediately begins observing `Transaction.updates`
    /// for any pending consumable re-deliveries.
    public init() {
        startObservingTransactions()
    }

    /// Cancels the background transaction observer.
    ///
    /// - Warning: Temporary workaround for a Swift 6.2 compiler issue where `deinit` containing
    /// task cancellation causes build or archive failures. Call this explicitly when tearing down
    /// the manager. Remove and restore standard `deinit` cleanup once the compiler bug is resolved.
    public func invalidate() {
        logger.info("ConsumableManager invalidated")
        updatesTask?.cancel()
        updatesTask = nil
    }
}

// MARK: - Product Fetching

extension ConsumableManager {

    /// Fetches consumable product metadata from the App Store.
    ///
    /// Products are filtered automatically to those whose `productType` is `.consumable`,
    /// derived from `Item.allCases`. Calling this again replaces any previously fetched products.
    public func fetchProducts() async {
        isFetching = true
        defer { isFetching = false }

        let ids = Item.allCases
            .filter { $0.productType == .consumable }
            .map(\.rawValue)

        guard !ids.isEmpty else {
            logger.warning("No consumable products defined in \(Item.self)")
            return
        }

        do {
            products = try await Product.products(for: ids)
            logger.info("Fetched \(self.products.count) consumable product(s)")
        } catch {
            lastError = error
            logger.error("Failed to fetch consumable products: \(error)")
        }
    }
}

// MARK: - Purchasing

extension ConsumableManager {

    /// Initiates a purchase for the specified consumable product.
    ///
    /// On a verified transaction, `onDeliver` is called before `transaction.finish()` to ensure
    /// the effect is applied before StoreKit considers the transaction complete.
    ///
    /// - Parameters:
    ///   - product: The consumable `Product` to purchase.
    ///   - options: Optional purchase options such as promotional offers. Defaults to an empty set.
    /// - Returns: A `PurchaseOutcome` describing the result of the purchase attempt.
    public func purchase(
        _ product: Product,
        options: Set<Product.PurchaseOption> = []
    ) async -> PurchaseOutcome {
        guard AppStore.canMakePayments else {
            logger.warning("Purchases are not available on this device")
            return .failed(StoreError.purchasesUnavailable)
        }

        do {
            let result = try await product.purchase(options: options)

            switch result {
                case let .success(.verified(transaction)):
                    await deliver(transaction)
                    return .success

                case let .success(.unverified(_, error)):
                    lastError = error
                    logger.warning("Unverified consumable transaction: \(error)")
                    return .failed(error)

                case .pending:
                    return .pending

                case .userCancelled:
                    return .cancelled

                @unknown default:
                    return .cancelled
            }
        } catch {
            lastError = error
            logger.error("Consumable purchase error: \(error)")
            return .failed(error)
        }
    }
}

// MARK: - Transaction Observation

extension ConsumableManager {

    /// Begins observing `Transaction.updates` for consumable re-deliveries.
    ///
    /// Only `.consumable` transactions are processed here. Subscriptions and non-consumables
    /// are left for `EntitlementManager` to handle.
    private func startObservingTransactions() {
        updatesTask?.cancel()
        updatesTask = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }

            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                guard transaction.productType == .consumable else { continue }

                // Hop to MainActor for delivery so onDeliver runs on the main actor
                // and handledTransactionIDs is accessed without data races.
                Task { @MainActor [weak self] in
                    await self?.deliver(transaction)
                }
            }
        }
    }
}

// MARK: - Delivery

extension ConsumableManager {

    /// Delivers a verified consumable transaction to the app and finishes it.
    ///
    /// Deduplication is applied using the transaction ID to guard against duplicate
    /// deliveries within a session. `onDeliver` is always called before `transaction.finish()`.
    private func deliver(_ transaction: Transaction) async {
        guard handledTransactionIDs.insert(transaction.id.description).inserted else {
            logger.debug("Skipping already-handled consumable transaction \(transaction.id)")
            return
        }

        if onDeliver == nil {
            logger.warning("Consumable \(transaction.productID) finished with no delivery — set onDeliver to apply the effect")
        }

        logger.info("Delivering consumable transaction: \(transaction.productID)")
        await onDeliver?(transaction)
        await transaction.finish()
        logger.info("Finished consumable transaction: \(transaction.productID)")
    }
}
