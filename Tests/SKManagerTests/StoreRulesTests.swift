//
// Project: SKManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import Testing

@testable import SKManager

@Suite("StoreRules")
struct StoreRulesTests {

  @Test("No owned products returns default visible products")
  func noOwnedProductsReturnsDefaultVisibleProducts() {
    let rules = makeRules(defaultVisible: [.basicMonthly, .standardMonthly])

    #expect(rules.visibleProducts(for: []) == [.basicMonthly, .standardMonthly])
  }

  @Test("Empty default visibility returns empty products")
  func emptyDefaultVisibilityReturnsEmptyProducts() {
    let rules = makeRules(defaultVisible: [])

    #expect(rules.visibleProducts(for: []).isEmpty)
  }

  @Test("Owned product applies show map")
  func ownedProductAppliesShowMap() {
    let rules = makeRules(
      defaultVisible: [.basicMonthly],
      showMap: [.basicMonthly: [.standardMonthly]]
    )

    #expect(rules.visibleProducts(for: [MockItem.basicMonthly.rawValue]).contains(.standardMonthly))
  }

  @Test("Multiple owned products merge show-map entries")
  func multipleOwnedProductsMergeShowMapEntries() {
    let rules = makeRules(
      defaultVisible: [],
      showMap: [
        .basicMonthly: [.standardMonthly],
        .standardMonthly: [.premiumMonthly],
      ]
    )
    let owned: Set<String> = [MockItem.basicMonthly.rawValue, MockItem.standardMonthly.rawValue]
    let visible = rules.visibleProducts(for: owned)

    #expect(visible.contains(.standardMonthly))
    #expect(visible.contains(.premiumMonthly))
  }

  @Test("Unrelated owned product does not apply show map")
  func unrelatedOwnedProductDoesNotApplyShowMap() {
    let rules = makeRules(
      defaultVisible: [.basicMonthly],
      showMap: [.addonPack: [.premiumMonthly]]
    )

    #expect(!rules.visibleProducts(for: [MockItem.basicMonthly.rawValue]).contains(.premiumMonthly))
  }

  @Test("Owned product applies hide map")
  func ownedProductAppliesHideMap() {
    let rules = makeRules(
      defaultVisible: [.basicMonthly, .standardMonthly],
      hideMap: [.basicMonthly: [.standardMonthly]]
    )

    #expect(rules.hiddenProducts(for: [MockItem.basicMonthly.rawValue]).contains(.standardMonthly))
  }

  @Test("No owned products does not apply hide map")
  func noOwnedProductsDoesNotApplyHideMap() {
    let rules = makeRules(
      defaultVisible: [.basicMonthly],
      hideMap: [.basicMonthly: [.standardMonthly]]
    )

    #expect(rules.hiddenProducts(for: []).isEmpty)
  }

  @Test("Multiple owned products merge hide-map entries")
  func multipleOwnedProductsMergeHideMapEntries() {
    let rules = makeRules(
      defaultVisible: [.basicMonthly, .standardMonthly, .premiumMonthly],
      hideMap: [
        .basicMonthly: [.standardMonthly],
        .standardMonthly: [.premiumMonthly],
      ]
    )
    let owned: Set<String> = [MockItem.basicMonthly.rawValue, MockItem.standardMonthly.rawValue]
    let hidden = rules.hiddenProducts(for: owned)

    #expect(hidden.contains(.standardMonthly))
    #expect(hidden.contains(.premiumMonthly))
  }

  @Test("Show map can intentionally overlap with hide map")
  func showMapCanIntentionallyOverlapWithHideMap() {
    let rules = makeRules(
      defaultVisible: [.basicMonthly],
      hideMap: [.basicMonthly: [.standardMonthly]],
      showMap: [.premiumMonthly: [.standardMonthly]]
    )
    let owned: Set<String> = [MockItem.basicMonthly.rawValue, MockItem.premiumMonthly.rawValue]

    #expect(rules.visibleProducts(for: owned).contains(.standardMonthly))
    #expect(rules.hiddenProducts(for: owned).contains(.standardMonthly))
  }

  @Test("Group hide map hides configured groups")
  func groupHideMapHidesConfiguredGroups() {
    let rules = makeRules(groupHideMap: [.addonPack: [.premium, .standard]])

    #expect(rules.hiddenGroups(for: [MockItem.addonPack.rawValue]) == [.premium, .standard])
  }

  @Test("Group hide map ignores unowned and unrelated products")
  func groupHideMapIgnoresUnownedAndUnrelatedProducts() {
    let rules = makeRules(groupHideMap: [.addonPack: [.premium]])

    #expect(rules.hiddenGroups(for: []).isEmpty)
    #expect(rules.hiddenGroups(for: [MockItem.basicMonthly.rawValue]).isEmpty)
  }

  @Test("Default group hide map is empty")
  func defaultGroupHideMapIsEmpty() {
    let rules = makeRules()

    #expect(rules.hiddenGroups(for: [MockItem.addonPack.rawValue]).isEmpty)
  }

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
}
