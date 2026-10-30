import ListKit
import UIKit
import XCTest

/// 只使用公开模块接口编译，防止公共 DSL 或只读描述树能力意外退回 internal。
@MainActor
final class ListKitPublicAPITests: XCTestCase {
    func testExtendingBoundariesKeepOnlyExplicitSectionInsets() {
        for height in [ListLayoutDimension.estimated(64), .absolute(64)] {
            let section = makeBoundarySpacingSection(height: height, extendsBoundary: true)
                .resolvedForTesting()

            XCTAssertEqual(section.contentInsets.top, 8)
            XCTAssertEqual(section.contentInsets.bottom, 12)
            XCTAssertEqual(section.contentInsets.leading, 16)
            XCTAssertEqual(section.contentInsets.trailing, 20)
            XCTAssertEqual(section.boundarySupplementaryItems.count, 2)
            XCTAssertTrue(section.boundarySupplementaryItems.allSatisfy(\.extendsBoundary))
        }
    }

    func testNonExtendingBoundariesDoNotAddHiddenInsets() {
        let section = makeBoundarySpacingSection(height: .estimated(64), extendsBoundary: false)
            .resolvedForTesting()

        XCTAssertEqual(section.contentInsets.top, 8)
        XCTAssertEqual(section.contentInsets.bottom, 12)
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
        } layout: {
            GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0).sectionInsets(
                .init(top: 8, leading: 16, bottom: 12, trailing: 20)
            )
                .boundarySupplementaries {
                    BoundarySupplementaryLayout(
                        kind: UICollectionView.elementKindSectionHeader,
                        size: .init(width: .fractionalWidth(1), height: height), alignment: .top
                    ).extendsBoundary(extendsBoundary).whenContentExists()
                    BoundarySupplementaryLayout(
                        kind: UICollectionView.elementKindSectionFooter,
                        size: .init(width: .fractionalWidth(1), height: height), alignment: .bottom
                    ).extendsBoundary(extendsBoundary).whenContentExists()
                }
        } supplementaries: {
            SectionSupplementary(
                UICollectionReusableView.self,
                kind: UICollectionView.elementKindSectionHeader, id: "header"
            ) { _, _ in }

            SectionSupplementary(
                UICollectionReusableView.self,
                kind: UICollectionView.elementKindSectionFooter, id: "footer"
            ) { _, _ in }
        }
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

    func testProviderSupplementaryCanDeclareItemGeometry() {
        let provider = ProviderSupplementary("custom", id: 1, view: UICollectionReusableView.self) {
            _, _, _ in
            UICollectionReusableView()
        }
        let section = ListSection(0) {
        } layout: {
            GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0).itemSupplementaries {
                ItemSupplementaryLayout(
                    kind: "custom",
                    size: .init(width: .absolute(12), height: .absolute(12)), itemAnchor: .topTrailing)
            }
        } supplementaries: {
            SectionSupplementary(provider)
        }
        XCTAssertEqual(section.supplementaries.first?.kind, "custom")
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
