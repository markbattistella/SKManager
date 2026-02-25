//
// Project: SKManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import XCTest
@testable import SKManager

final class StoreRulesTests: XCTestCase {

    // MARK: - Helpers

    private func makeRules(
        defaultVisible: Set<MockItem> = [.basicMonthly],
        hideMap: [MockItem: Set<MockItem>] = [:],
        showMap: [MockItem: Set<MockItem>] = [:],
        groupHideMap: [MockItem: Set<MockTier>] = [:]
    ) -> StoreRules<MockItem> {
        StoreRules(
            defaultVisible: defaultVisible,
            hideMap: hideMap,
            showMap: showMap,
            groupHideMap: groupHideMap
        )
    }

    // MARK: - defaultVisible (no owned products)

    func testNoOwned_returnsDefaultVisible() {
        let rules = makeRules(defaultVisible: [.basicMonthly, .standardMonthly])
        let visible = rules.visibleProducts(for: [])
        XCTAssertEqual(visible, [.basicMonthly, .standardMonthly])
    }

    func testNoOwned_emptyDefaultVisible_returnsEmpty() {
        let rules = makeRules(defaultVisible: [])
        let visible = rules.visibleProducts(for: [])
        XCTAssertEqual(visible, [])
    }

    // MARK: - showMap

    func testOwned_showMapApplied() {
        let rules = makeRules(
            defaultVisible: [.basicMonthly],
            showMap: [.basicMonthly: [.standardMonthly]]
        )
        let visible = rules.visibleProducts(for: [MockItem.basicMonthly.rawValue])
        XCTAssertTrue(visible.contains(.standardMonthly))
    }

    func testOwned_multipleShowMapEntries() {
        let rules = makeRules(
            defaultVisible: [],
            showMap: [
                .basicMonthly: [.standardMonthly],
                .standardMonthly: [.premiumMonthly]
            ]
        )
        // Owning both basic and standard should reveal both standard and premium
        let owned: Set<String> = [MockItem.basicMonthly.rawValue, MockItem.standardMonthly.rawValue]
        let visible = rules.visibleProducts(for: owned)
        XCTAssertTrue(visible.contains(.standardMonthly))
        XCTAssertTrue(visible.contains(.premiumMonthly))
    }

    func testOwned_unrelatedProduct_showMapNotApplied() {
        let rules = makeRules(
            defaultVisible: [.basicMonthly],
            showMap: [.addonPack: [.premiumMonthly]]
        )
        let visible = rules.visibleProducts(for: [MockItem.basicMonthly.rawValue])
        XCTAssertFalse(visible.contains(.premiumMonthly))
    }

    // MARK: - hideMap

    func testOwned_hideMapApplied() {
        let rules = makeRules(
            defaultVisible: [.basicMonthly, .standardMonthly],
            hideMap: [.basicMonthly: [.standardMonthly]]
        )
        let hidden = rules.hiddenProducts(for: [MockItem.basicMonthly.rawValue])
        XCTAssertTrue(hidden.contains(.standardMonthly))
    }

    func testNoOwned_hideMapNotApplied() {
        let rules = makeRules(
            defaultVisible: [.basicMonthly],
            hideMap: [.basicMonthly: [.standardMonthly]]
        )
        let hidden = rules.hiddenProducts(for: [])
        XCTAssertTrue(hidden.isEmpty)
    }

    func testOwned_multipleHideEntries() {
        let rules = makeRules(
            defaultVisible: [.basicMonthly, .standardMonthly, .premiumMonthly],
            hideMap: [
                .basicMonthly: [.standardMonthly],
                .standardMonthly: [.premiumMonthly]
            ]
        )
        let owned: Set<String> = [MockItem.basicMonthly.rawValue, MockItem.standardMonthly.rawValue]
        let hidden = rules.hiddenProducts(for: owned)
        XCTAssertTrue(hidden.contains(.standardMonthly))
        XCTAssertTrue(hidden.contains(.premiumMonthly))
    }

    // MARK: - showMap takes precedence over hideMap in products(for:) evaluation
    // The filter in StoreManager checks `visible` before `hidden`, so explicitly visible
    // items are never suppressed by the hide map.

    func testShowPrecedesHide_itemInBothMaps() {
        let rules = makeRules(
            defaultVisible: [.basicMonthly],
            hideMap: [.basicMonthly: [.standardMonthly]],    // owning basic hides standard
            showMap: [.premiumMonthly: [.standardMonthly]]   // owning premium shows standard
        )
        // Owning both: standard should appear in show set and hide set simultaneously.
        let owned: Set<String> = [MockItem.basicMonthly.rawValue, MockItem.premiumMonthly.rawValue]
        let visible = rules.visibleProducts(for: owned)
        let hidden = rules.hiddenProducts(for: owned)
        // visible wins in the StoreManager filter (checked first)
        XCTAssertTrue(visible.contains(.standardMonthly))
        XCTAssertTrue(hidden.contains(.standardMonthly))
    }

    // MARK: - groupHideMap

    func testGroupHideMap_hiddenGroupReturnsEmptySet() {
        let rules = makeRules(
            groupHideMap: [.addonPack: [.premium]]
        )
        let hidden = rules.hiddenGroups(for: [MockItem.addonPack.rawValue])
        XCTAssertTrue(hidden.contains(.premium))
    }

    func testGroupHideMap_notOwned_noGroupsHidden() {
        let rules = makeRules(
            groupHideMap: [.addonPack: [.premium]]
        )
        let hidden = rules.hiddenGroups(for: [])
        XCTAssertTrue(hidden.isEmpty)
    }

    func testGroupHideMap_multipleGroupsHidden() {
        let rules = makeRules(
            groupHideMap: [.addonPack: [.premium, .standard]]
        )
        let hidden = rules.hiddenGroups(for: [MockItem.addonPack.rawValue])
        XCTAssertEqual(hidden, [.premium, .standard])
    }

    func testGroupHideMap_unrelatedOwned_noGroupsHidden() {
        let rules = makeRules(
            groupHideMap: [.addonPack: [.premium]]
        )
        let hidden = rules.hiddenGroups(for: [MockItem.basicMonthly.rawValue])
        XCTAssertTrue(hidden.isEmpty)
    }

    func testGroupHideMap_defaultIsEmpty() {
        // Default groupHideMap is [:], so no groups are ever hidden
        let rules = makeRules()
        let hidden = rules.hiddenGroups(for: [MockItem.addonPack.rawValue])
        XCTAssertTrue(hidden.isEmpty)
    }
}
