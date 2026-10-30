// Adapted from UIKitGridLayouts 89aa339cc5651147c3c6265c0c931dd701bb45a7.
// Copyright (c) 2026 Sondra. MIT: ThirdPartyNotices/UIKitGridLayouts-LICENSE.txt.
import XCTest

@testable import ListKit

@MainActor
final class TrackResolutionTests: XCTestCase {
    private var mixed: [ListGridTrack] {
        [
            ListGridTrack(.fixed(70), spacingAfter: 12),
            ListGridTrack(.flexible(minimum: 80, maximum: 140), spacingAfter: 12),
            ListGridTrack(.adaptive(minimumForCount: 60), spacingAfter: 12),
        ]
    }

    func testMixedAdaptiveExpansionThreshold() {
        let below = ListGridLayoutBuilder.resolve(mixed, availableExtent: 357.98)
        XCTAssertEqual(below.count, 3)
        XCTAssertEqual(below[2].extent, 131.99, accuracy: 0.001)
        let at = ListGridLayoutBuilder.resolve(mixed, availableExtent: 358)
        XCTAssertEqual(at.map(\.extent), [70, 132, 60, 60])
        XCTAssertEqual(at.map(\.spacing), [12, 12, 12, 0])
        let above = ListGridLayoutBuilder.resolve(mixed, availableExtent: 358.02)
        XCTAssertEqual(above.count, 4)
        XCTAssertEqual(above[2].extent, 60.005, accuracy: 0.001)
    }

    func testMixedFlexibleMaximumGivesRemainingSpaceToAdaptive() {
        let result = ListGridLayoutBuilder.resolve(mixed, availableExtent: 400)
        XCTAssertEqual(result.map(\.extent), [70, 140, 77, 77])
        XCTAssertEqual(result.reduce(0) { $0 + $1.extent + $1.spacing }, 400)
    }

    func testFixedIsReservedEvenWhenDeclaredLast() {
        let reordered = [mixed[1], mixed[2], mixed[0]]
        let result = ListGridLayoutBuilder.resolve(reordered, availableExtent: 400)
        XCTAssertEqual(result.map(\.extent), [140, 77, 77, 70])
    }

    func testNonFixedDeclarationOrderAffectsAllocation() {
        let adaptiveFirst = [mixed[0], mixed[2], mixed[1]]
        let result = ListGridLayoutBuilder.resolve(adaptiveFirst, availableExtent: 400)
        // adaptive reserves 153 before flexible is capped at 140; 13 pt remains unused.
        XCTAssertEqual(result.map(\.extent), [70, 70.5, 70.5, 140])
        XCTAssertEqual(result.reduce(0) { $0 + $1.extent + $1.spacing }, 387)
    }

    func testMixedNarrowContainerPreservesFixedAndFlexibleMinimum() {
        let result = ListGridLayoutBuilder.resolve(mixed, availableExtent: 200)
        XCTAssertEqual(result.map(\.extent), [70, 80, 26])
        // Exhausted space: package policy keeps a finite positive adaptive extent.
        let overflow = ListGridLayoutBuilder.resolve(mixed, availableExtent: 100)
        XCTAssertEqual(overflow.map(\.extent), [70, 80, 1])
        XCTAssertEqual(overflow.reduce(0) { $0 + $1.extent + $1.spacing }, 175)
    }

    func testMixedMaximumCapsLeaveUnusedSpace() {
        let columns = [
            mixed[0],
            ListGridTrack(.flexible(minimum: 80, maximum: 112), spacingAfter: 12),
            ListGridTrack(.adaptive(minimumForCount: 60, maximum: 64), spacingAfter: 12),
        ]
        let result = ListGridLayoutBuilder.resolve(columns, availableExtent: 340)
        XCTAssertEqual(result.map(\.extent), [70, 112, 61, 61])
        let capped = ListGridLayoutBuilder.resolve(columns, availableExtent: 350)
        XCTAssertEqual(capped.map(\.extent), [70, 112, 64, 64])
        XCTAssertEqual(capped.reduce(0) { $0 + $1.extent + $1.spacing }, 346)
    }

    func testMultipleAdaptiveDefinitionsKeepTheirOwnGaps() {
        let columns = [
            ListGridTrack(.fixed(40), spacingAfter: 4),
            ListGridTrack(.adaptive(minimumForCount: 40), spacingAfter: 8),
            ListGridTrack(.flexible(minimum: 50, maximum: 60), spacingAfter: 12),
            ListGridTrack(.adaptive(minimumForCount: 30), spacingAfter: 6),
        ]
        let result = ListGridLayoutBuilder.resolve(columns, availableExtent: 364)
        XCTAssertEqual(result.map(\.extent), [40, 46, 46, 60, 30.5, 30.5, 30.5, 30.5])
        XCTAssertEqual(result.map(\.spacing), [4, 8, 8, 12, 6, 6, 6, 0])
        XCTAssertEqual(result.reduce(0) { $0 + $1.extent + $1.spacing }, 364)
    }

    func testAdaptiveThresholdIncludesSpacing() {
        let columns = [ListGridTrack(.adaptive(minimumForCount: 80), spacingAfter: 12)]
        XCTAssertEqual(ListGridLayoutBuilder.resolve(columns, availableExtent: 263).count, 2)
        let atThreshold = ListGridLayoutBuilder.resolve(columns, availableExtent: 264)
        XCTAssertEqual(atThreshold.count, 3)
        XCTAssertEqual(atThreshold[0].extent, 80)
        XCTAssertEqual(atThreshold.last?.spacing, 0)
    }

    func testFixedAndFlexibleHaveIndependentBounds() {
        let columns = [
            ListGridTrack(.fixed(100), spacingAfter: 10),
            ListGridTrack(.flexible(minimum: 40, maximum: 70), spacingAfter: 20),
            ListGridTrack(.flexible(minimum: 40)),
        ]
        let result = ListGridLayoutBuilder.resolve(columns, availableExtent: 350)
        XCTAssertEqual(result.map(\.extent), [100, 70, 150])
        XCTAssertEqual(result.map(\.spacing), [10, 20, 0])
    }

    func testAdaptiveMaximumLeavesUnusedSpace() {
        let rows = [ListGridTrack(.adaptive(minimumForCount: 80, maximum: 112), spacingAfter: 12)]
        let result = ListGridLayoutBuilder.resolve(rows, availableExtent: 260)
        XCTAssertEqual(result.map(\.extent), [112, 112])
    }

    func testNarrowContainerPolicy() {
        let adaptive = ListGridLayoutBuilder.resolve(
            [ListGridTrack(.adaptive(minimumForCount: 80))], availableExtent: 40)
        XCTAssertEqual(adaptive.map(\.extent), [40])
        let flexible = ListGridLayoutBuilder.resolve(
            [ListGridTrack(.flexible(minimum: 80))], availableExtent: 40)
        XCTAssertEqual(flexible.map(\.extent), [80])
    }
    func testCheckedResolutionLimitsTotalAdaptiveExpansion() throws {
        let definitions = [ListGridTrack(.adaptive(minimumForCount: 1)), ListGridTrack(.adaptive(minimumForCount: 1))]
        XCTAssertEqual(
            try ListGridLayoutBuilder.checkedResolve(definitions, availableExtent: 10000, defaultSpacing: 0)
                .count, 10000)
        XCTAssertThrowsError(
            try ListGridLayoutBuilder.checkedResolve(definitions, availableExtent: 11000, defaultSpacing: 0)
        ) { error in
            XCTAssertTrue(String(describing: error).contains("track 1"))
        }
    }

}
