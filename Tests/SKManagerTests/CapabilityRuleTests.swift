//
// Project: SKManager
// Author: Mark Battistella
// Website: https://markbattistella.com
//

import XCTest
@testable import SKManager

final class CapabilityRuleTests: XCTestCase {

    // MARK: - isAccessible

    func testAllowedTrue_isAccessible() {
        XCTAssertTrue(CapabilityRule.allowed(true).isAccessible)
    }

    func testAllowedFalse_isNotAccessible() {
        XCTAssertFalse(CapabilityRule.allowed(false).isAccessible)
    }

    func testLimitPositive_isAccessible() {
        XCTAssertTrue(CapabilityRule.limit(5).isAccessible)
    }

    func testLimitZero_isAccessible() {
        // A limit of 0 still counts as accessible (caller checks the limit value separately)
        XCTAssertTrue(CapabilityRule.limit(0).isAccessible)
    }

    func testUntilFutureDate_isAccessible() {
        XCTAssertTrue(CapabilityRule.until(.distantFuture).isAccessible)
    }

    func testUntilPastDate_isNotAccessible() {
        XCTAssertFalse(CapabilityRule.until(.distantPast).isAccessible)
    }

    func testUntilNow_isNotAccessible() {
        // A date set just before now should fail the > check
        let slightlyPast = Date.now.addingTimeInterval(-1)
        XCTAssertFalse(CapabilityRule.until(slightlyPast).isAccessible)
    }

    func testUnrestricted_isAccessible() {
        XCTAssertTrue(CapabilityRule.unrestricted.isAccessible)
    }

    func testUnavailable_isNotAccessible() {
        XCTAssertFalse(CapabilityRule.unavailable.isAccessible)
    }

    // MARK: - expiry

    func testExpiry_returnsDateForUntilRule() {
        let date = Date.distantFuture
        XCTAssertEqual(CapabilityRule.until(date).expiry, date)
    }

    func testExpiry_isNilForAllowedRule() {
        XCTAssertNil(CapabilityRule.allowed(true).expiry)
    }

    func testExpiry_isNilForLimitRule() {
        XCTAssertNil(CapabilityRule.limit(10).expiry)
    }

    func testExpiry_isNilForUnrestricted() {
        XCTAssertNil(CapabilityRule.unrestricted.expiry)
    }

    func testExpiry_isNilForUnavailable() {
        XCTAssertNil(CapabilityRule.unavailable.expiry)
    }

    // MARK: - limit

    func testLimit_returnsValueForLimitRule() {
        XCTAssertEqual(CapabilityRule.limit(7).limit, 7)
    }

    func testLimit_isNilForAllowedRule() {
        XCTAssertNil(CapabilityRule.allowed(true).limit)
    }

    func testLimit_isNilForUnrestricted() {
        XCTAssertNil(CapabilityRule.unrestricted.limit)
    }

    func testLimit_isNilForUntilRule() {
        XCTAssertNil(CapabilityRule.until(.distantFuture).limit)
    }

    // MARK: - Equatable

    func testEquality_sameAllowed() {
        XCTAssertEqual(CapabilityRule.allowed(true), CapabilityRule.allowed(true))
    }

    func testEquality_differentAllowed() {
        XCTAssertNotEqual(CapabilityRule.allowed(true), CapabilityRule.allowed(false))
    }

    func testEquality_sameLimit() {
        XCTAssertEqual(CapabilityRule.limit(3), CapabilityRule.limit(3))
    }

    func testEquality_differentLimit() {
        XCTAssertNotEqual(CapabilityRule.limit(3), CapabilityRule.limit(5))
    }

    func testEquality_unrestricted() {
        XCTAssertEqual(CapabilityRule.unrestricted, CapabilityRule.unrestricted)
    }

    func testEquality_unavailable() {
        XCTAssertEqual(CapabilityRule.unavailable, CapabilityRule.unavailable)
    }

    func testEquality_differentCases() {
        XCTAssertNotEqual(CapabilityRule.unrestricted, CapabilityRule.unavailable)
    }
}
