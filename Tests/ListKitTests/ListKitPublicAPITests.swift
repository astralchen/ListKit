import XCTest
import UIKit
import ListKit

/// 只使用公开模块接口编译，防止公共 DSL 或只读描述树能力意外退回 internal。
@MainActor
final class ListKitPublicAPITests: XCTestCase {
    func testExtendingBoundariesKeepOnlyExplicitSectionInsets() {
        for height in [ListLayoutDimension.estimated(64), .absolute(64)] {
            let section = makeBoundarySpacingSection(height: height, extendsBoundary: true)
                .makeCompositionalLayoutSection()

            XCTAssertEqual(section.contentInsets.top, 8)
            XCTAssertEqual(section.contentInsets.bottom, 12)
            XCTAssertEqual(section.contentInsets.leading, 16)
            XCTAssertEqual(section.contentInsets.trailing, 20)
            XCTAssertEqual(section.boundarySupplementaryItems.count, 2)
            XCTAssertTrue(section.boundarySupplementaryItems.allSatisfy(\.extendsBoundary))
        }
    }

    func testNonExtendingBoundariesRetainReservedSpace() {
        let section = makeBoundarySpacingSection(height: .estimated(64), extendsBoundary: false)
            .makeCompositionalLayoutSection()

        XCTAssertEqual(section.contentInsets.top, 72)
        XCTAssertEqual(section.contentInsets.bottom, 76)
        XCTAssertEqual(section.contentInsets.leading, 16)
        XCTAssertEqual(section.contentInsets.trailing, 20)
        XCTAssertFalse(section.boundarySupplementaryItems.contains(where: \.extendsBoundary))
    }

    private func makeBoundarySpacingSection(
        height: ListLayoutDimension,
        extendsBoundary: Bool
    ) -> ListSection<Int> {
        ListSection(0) {
            Row(1, model: "Content", cell: UICollectionViewCell.self) { _, _, _ in }
        } header: {
            Header(UICollectionReusableView.self, id: "header") { _, _ in }
                .layout(height: height, extendsBoundary: extendsBoundary)
        } footer: {
            Footer(UICollectionReusableView.self, id: "footer") { _, _ in }
                .layout(height: height, extendsBoundary: extendsBoundary)
        }
        .layout(.list(contentInsets: .init(top: 8, leading: 16, bottom: 12, trailing: 20)))
    }

    func testRefreshRulesGroupsAndDescriptionStorageArePublic() {
        let rowRule = ListRowRefreshRule(
            trigger: .refreshIDChanges,
            scope: .allMatching,
            action: .reconfigure(layout: .invalidate)
        )
        let supplementaryRule = ListSupplementaryRefreshRule(
            trigger: .everyApply,
            action: .reloadSection
        )

        let rowGroup = RowGroup {
            Row(1, model: "Collection", cell: UICollectionViewCell.self) { _, _, _ in }
                .refresh(rowRule)
        }
        let section = ListSection(0) { rowGroup }

        let tableGroup = TableRowGroup {
            TableRow(1, model: "Table", cell: UITableViewCell.self) { _, _, _ in }
                .refresh(rowRule)
        }
        let tableSection = TableSection(0) { tableGroup }

        XCTAssertEqual(section.rows.count, 1)
        XCTAssertEqual(section.outlineRoots.count, 1)
        XCTAssertTrue(section.supplementaries.isEmpty)
        XCTAssertEqual(tableSection.rows.count, 1)
        XCTAssertNil(tableSection.header)
        XCTAssertNil(tableSection.footer)
        XCTAssertEqual(supplementaryRule.action, .reloadSection)
    }

    func testPublicSummaryMetricsExposeOrthogonalActions() {
        let metrics = ListRefreshMetrics(
            snapshotReconfiguredRowCount: 1,
            visibleReconfiguredRowCount: 2,
            reloadedRowCount: 3,
            visibleReconfiguredSupplementaryCount: 4,
            reloadedSectionCount: 5
        )
        let summary = ListRefreshSummary(
            requestedTargetCount: 8,
            matchedTargetCount: 7,
            refreshMetrics: metrics,
            animation: ListAnimationSummary(completionState: .completed)
        )

        XCTAssertEqual(summary.refreshMetrics, metrics)
        XCTAssertEqual(summary.animation.completionState, .completed)
    }

    func testLayoutInsetsCanPreserveOrExplicitlyOverrideUIKitDefaults() {
        let inherited = ListCompositionalLayoutConfiguration()
        let explicit = ListCompositionalLayoutConfiguration(
            scrollDirection: .horizontal,
            interSectionSpacing: 8,
            contentInsetsReference: .safeArea
        )
        let inheritedList = ListUIKitListLayout()
        let explicitList = ListUIKitListLayout(showsSeparators: false)

        XCTAssertNil(inherited.scrollDirection)
        XCTAssertNil(inherited.interSectionSpacing)
        XCTAssertEqual(inherited.contentInsetsReference, .systemDefault)
        XCTAssertEqual(explicit.scrollDirection, .horizontal)
        XCTAssertEqual(explicit.interSectionSpacing, 8)
        XCTAssertEqual(explicit.contentInsetsReference, .safeArea)
        XCTAssertNil(inheritedList.showsSeparators)
        XCTAssertEqual(explicitList.showsSeparators, false)
    }
}
