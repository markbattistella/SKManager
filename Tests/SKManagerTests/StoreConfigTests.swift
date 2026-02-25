//
// Project: SKManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import XCTest
@testable import SKManager

final class StoreConfigTests: XCTestCase {

    // MARK: - Helpers

    private func makeConfig(
        conflictGroups: [MockTier: [MockTier]] = [:],
        conflictProducts: [MockItem: [MockItem]] = [:]
    ) -> StoreConfig<MockTier, MockItem> {
        StoreConfig(conflictGroups: conflictGroups, conflictProducts: conflictProducts)
    }

    // MARK: - defaultConfig

    func testDefaultConfig_noConflicts() {
        let config = StoreConfig<MockTier, MockItem>.defaultConfig
        XCTAssertFalse(config.hasConflicts(
            activeTiers: [.premium, .standard],
            ownedProducts: [MockItem.premiumMonthly.rawValue, MockItem.standardMonthly.rawValue]
        ))
    }

    // MARK: - No conflicts

    func testNoRules_noConflict() {
        let config = makeConfig()
        XCTAssertFalse(config.hasConflicts(
            activeTiers: [.premium, .standard],
            ownedProducts: []
        ))
    }

    func testNoRules_emptyInputs_noConflict() {
        let config = makeConfig()
        XCTAssertFalse(config.hasConflicts(activeTiers: [], ownedProducts: []))
    }

    // MARK: - conflictGroups

    func testTierConflict_detected() {
        let config = makeConfig(conflictGroups: [.premium: [.standard]])
        XCTAssertTrue(config.hasConflicts(
            activeTiers: [.premium, .standard],
            ownedProducts: []
        ))
    }

    func testTierConflict_onlyOneTierOwned_noConflict() {
        let config = makeConfig(conflictGroups: [.premium: [.standard]])
        XCTAssertFalse(config.hasConflicts(
            activeTiers: [.premium],
            ownedProducts: []
        ))
    }

    func testTierConflict_differentTierOwned_noConflict() {
        let config = makeConfig(conflictGroups: [.premium: [.standard]])
        // Owning basic and standard — the rule only fires when premium is active
        XCTAssertFalse(config.hasConflicts(
            activeTiers: [.basic, .standard],
            ownedProducts: []
        ))
    }

    func testTierConflict_multipleConflictsInList_firstMatch() {
        let config = makeConfig(conflictGroups: [.premium: [.standard, .basic]])
        XCTAssertTrue(config.hasConflicts(
            activeTiers: [.premium, .basic],
            ownedProducts: []
        ))
    }

    func testTierConflict_multipleConflictsInList_secondMatch() {
        let config = makeConfig(conflictGroups: [.premium: [.standard, .basic]])
        XCTAssertTrue(config.hasConflicts(
            activeTiers: [.premium, .standard],
            ownedProducts: []
        ))
    }

    func testTierConflict_symmetryIsNotAutomatic() {
        // Rules are one-directional: [.standard: [.premium]] does NOT trigger when only
        // [.premium: [.standard]] is declared
        let config = makeConfig(conflictGroups: [.premium: [.standard]])
        // Conflict triggers because the KEY (.premium) is in activeTiers
        XCTAssertTrue(config.hasConflicts(
            activeTiers: [.premium, .standard],
            ownedProducts: []
        ))
        // No symmetric rule declared, but same tiers still match the one existing rule
        let config2 = makeConfig(conflictGroups: [.standard: [.premium]])
        XCTAssertTrue(config2.hasConflicts(
            activeTiers: [.premium, .standard],
            ownedProducts: []
        ))
    }

    // MARK: - conflictProducts

    func testProductConflict_detected() {
        let config = makeConfig(conflictProducts: [.premiumMonthly: [.standardMonthly]])
        XCTAssertTrue(config.hasConflicts(
            activeTiers: [],
            ownedProducts: [MockItem.premiumMonthly.rawValue, MockItem.standardMonthly.rawValue]
        ))
    }

    func testProductConflict_onlyOneOwned_noConflict() {
        let config = makeConfig(conflictProducts: [.premiumMonthly: [.standardMonthly]])
        XCTAssertFalse(config.hasConflicts(
            activeTiers: [],
            ownedProducts: [MockItem.premiumMonthly.rawValue]
        ))
    }

    func testProductConflict_unrelatedProducts_noConflict() {
        let config = makeConfig(conflictProducts: [.premiumMonthly: [.standardMonthly]])
        XCTAssertFalse(config.hasConflicts(
            activeTiers: [],
            ownedProducts: [MockItem.basicMonthly.rawValue, MockItem.addonPack.rawValue]
        ))
    }

    func testProductConflict_multipleConflictsInList() {
        let config = makeConfig(conflictProducts: [.addonPack: [.basicMonthly, .standardMonthly]])
        XCTAssertTrue(config.hasConflicts(
            activeTiers: [],
            ownedProducts: [MockItem.addonPack.rawValue, MockItem.standardMonthly.rawValue]
        ))
    }

    // MARK: - Mixed tier and product conflicts

    func testMixed_tierConflictOnly_detected() {
        let config = makeConfig(
            conflictGroups: [.premium: [.standard]],
            conflictProducts: [.addonPack: [.basicMonthly]]
        )
        XCTAssertTrue(config.hasConflicts(
            activeTiers: [.premium, .standard],
            ownedProducts: [MockItem.premiumMonthly.rawValue]
        ))
    }

    func testMixed_productConflictOnly_detected() {
        let config = makeConfig(
            conflictGroups: [.premium: [.standard]],
            conflictProducts: [.addonPack: [.basicMonthly]]
        )
        XCTAssertTrue(config.hasConflicts(
            activeTiers: [.premium],
            ownedProducts: [MockItem.addonPack.rawValue, MockItem.basicMonthly.rawValue]
        ))
    }

    func testMixed_neitherConflict_noConflict() {
        let config = makeConfig(
            conflictGroups: [.premium: [.standard]],
            conflictProducts: [.addonPack: [.basicMonthly]]
        )
        XCTAssertFalse(config.hasConflicts(
            activeTiers: [.premium, .basic],
            ownedProducts: [MockItem.addonPack.rawValue, MockItem.standardMonthly.rawValue]
        ))
    }
}
