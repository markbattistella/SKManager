//
// Project: SKManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import Testing

@testable import SKManager

@Suite("StoreError")
struct StoreErrorTests {

  @Test("Store errors are equatable for app-level handling")
  func storeErrorsAreEquatableForAppLevelHandling() {
    #expect(StoreError.purchasesUnavailable == .purchasesUnavailable)
    #expect(StoreError.transactionNotFound(productID: "a") == .transactionNotFound(productID: "a"))
    #expect(StoreError.transactionNotFound(productID: "a") != .transactionNotFound(productID: "b"))
    #expect(
      StoreError.missingConsumableDeliveryHandler(productID: "credits")
        == .missingConsumableDeliveryHandler(productID: "credits")
    )
  }

  @Test("Missing consumable delivery handler describes unfinished transaction reason")
  func missingConsumableDeliveryHandlerDescribesUnfinishedTransactionReason() throws {
    let description = try #require(
      StoreError.missingConsumableDeliveryHandler(productID: "credits").errorDescription
    )

    #expect(description.contains("credits"))
    #expect(description.contains("delivery handler"))
  }
}
