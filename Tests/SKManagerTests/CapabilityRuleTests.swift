//
// Project: SKManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import Foundation
import Testing

@testable import SKManager

@Suite("CapabilityRule")
struct CapabilityRuleTests {

  @Test(
    "Accessibility reflects each rule",
    arguments: [
      (CapabilityRule.allowed(true), true),
      (CapabilityRule.allowed(false), false),
      (CapabilityRule.limit(5), true),
      (CapabilityRule.limit(0), true),
      (CapabilityRule.until(.distantFuture), true),
      (CapabilityRule.until(.distantPast), false),
      (CapabilityRule.unrestricted, true),
      (CapabilityRule.unavailable, false),
    ]
  )
  func accessibility(rule: CapabilityRule, expected: Bool) {
    #expect(rule.isAccessible == expected)
  }

  @Test("Expired until rule is inaccessible")
  func expiredUntilRuleIsInaccessible() {
    #expect(!CapabilityRule.until(Date.now.addingTimeInterval(-1)).isAccessible)
  }

  @Test("Expiry returns only until dates")
  func expiryReturnsOnlyUntilDates() {
    let date = Date.distantFuture

    #expect(CapabilityRule.until(date).expiry == date)
    #expect(CapabilityRule.allowed(true).expiry == nil)
    #expect(CapabilityRule.limit(10).expiry == nil)
    #expect(CapabilityRule.unrestricted.expiry == nil)
    #expect(CapabilityRule.unavailable.expiry == nil)
  }

  @Test("Limit returns only limit values")
  func limitReturnsOnlyLimitValues() {
    #expect(CapabilityRule.limit(7).limit == 7)
    #expect(CapabilityRule.allowed(true).limit == nil)
    #expect(CapabilityRule.unrestricted.limit == nil)
    #expect(CapabilityRule.until(.distantFuture).limit == nil)
  }

  @Test("Rules compare by case and associated value")
  func rulesCompareByCaseAndAssociatedValue() {
    #expect(CapabilityRule.allowed(true) == .allowed(true))
    #expect(CapabilityRule.allowed(true) != .allowed(false))
    #expect(CapabilityRule.limit(3) == .limit(3))
    #expect(CapabilityRule.limit(3) != .limit(5))
    #expect(CapabilityRule.unrestricted == .unrestricted)
    #expect(CapabilityRule.unavailable == .unavailable)
    #expect(CapabilityRule.unrestricted != .unavailable)
  }
}
