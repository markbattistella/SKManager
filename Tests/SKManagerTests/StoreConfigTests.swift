//
// Project: SKManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import Testing

@testable import SKManager

@Suite("StoreConfig")
struct StoreConfigTests {

  @Test("Default config has no conflicts")
  func defaultConfigHasNoConflicts() {
    let config = StoreConfig<MockTier, MockItem>.defaultConfig

    #expect(
      !config.hasConflicts(
        activeTiers: [.premium, .standard],
        ownedProducts: [MockItem.premiumMonthly.rawValue, MockItem.standardMonthly.rawValue]
      ))
  }

  @Test("No rules has no conflict")
  func noRulesHasNoConflict() {
    let config = makeConfig()

    #expect(!config.hasConflicts(activeTiers: [.premium, .standard], ownedProducts: []))
    #expect(!config.hasConflicts(activeTiers: [], ownedProducts: []))
  }

  @Test("Tier conflicts are detected only when both tiers are active")
  func tierConflictsAreDetectedOnlyWhenBothTiersAreActive() {
    let config = makeConfig(conflictGroups: [.premium: [.standard]])

    #expect(config.hasConflicts(activeTiers: [.premium, .standard], ownedProducts: []))
    #expect(!config.hasConflicts(activeTiers: [.premium], ownedProducts: []))
    #expect(!config.hasConflicts(activeTiers: [.basic, .standard], ownedProducts: []))
  }

  @Test("Tier conflict list can match any configured conflict")
  func tierConflictListCanMatchAnyConfiguredConflict() {
    let config = makeConfig(conflictGroups: [.premium: [.standard, .basic]])

    #expect(config.hasConflicts(activeTiers: [.premium, .basic], ownedProducts: []))
    #expect(config.hasConflicts(activeTiers: [.premium, .standard], ownedProducts: []))
  }

  @Test("Tier conflicts can be declared from either side")
  func tierConflictsCanBeDeclaredFromEitherSide() {
    let premiumRule = makeConfig(conflictGroups: [.premium: [.standard]])
    let standardRule = makeConfig(conflictGroups: [.standard: [.premium]])

    #expect(premiumRule.hasConflicts(activeTiers: [.premium, .standard], ownedProducts: []))
    #expect(standardRule.hasConflicts(activeTiers: [.premium, .standard], ownedProducts: []))
  }

  @Test("Product conflicts are detected only when both products are owned")
  func productConflictsAreDetectedOnlyWhenBothProductsAreOwned() {
    let config = makeConfig(conflictProducts: [.premiumMonthly: [.standardMonthly]])

    #expect(
      config.hasConflicts(
        activeTiers: [],
        ownedProducts: [MockItem.premiumMonthly.rawValue, MockItem.standardMonthly.rawValue]
      ))
    #expect(
      !config.hasConflicts(
        activeTiers: [],
        ownedProducts: [MockItem.premiumMonthly.rawValue]
      ))
    #expect(
      !config.hasConflicts(
        activeTiers: [],
        ownedProducts: [MockItem.basicMonthly.rawValue, MockItem.addonPack.rawValue]
      ))
  }

  @Test("Product conflict list can match any configured conflict")
  func productConflictListCanMatchAnyConfiguredConflict() {
    let config = makeConfig(conflictProducts: [.addonPack: [.basicMonthly, .standardMonthly]])

    #expect(
      config.hasConflicts(
        activeTiers: [],
        ownedProducts: [MockItem.addonPack.rawValue, MockItem.standardMonthly.rawValue]
      ))
  }

  @Test("Mixed conflicts report tier or product conflicts independently")
  func mixedConflictsReportTierOrProductConflictsIndependently() {
    let config = makeConfig(
      conflictGroups: [.premium: [.standard]],
      conflictProducts: [.addonPack: [.basicMonthly]]
    )

    #expect(
      config.hasConflicts(
        activeTiers: [.premium, .standard],
        ownedProducts: [MockItem.premiumMonthly.rawValue]
      ))
    #expect(
      config.hasConflicts(
        activeTiers: [.premium],
        ownedProducts: [MockItem.addonPack.rawValue, MockItem.basicMonthly.rawValue]
      ))
    #expect(
      !config.hasConflicts(
        activeTiers: [.premium, .basic],
        ownedProducts: [MockItem.addonPack.rawValue, MockItem.standardMonthly.rawValue]
      ))
  }

  private func makeConfig(
    conflictGroups: [MockTier: [MockTier]] = [:],
    conflictProducts: [MockItem: [MockItem]] = [:]
  ) -> StoreConfig<MockTier, MockItem> {
    StoreConfig(conflictGroups: conflictGroups, conflictProducts: conflictProducts)
  }
}
