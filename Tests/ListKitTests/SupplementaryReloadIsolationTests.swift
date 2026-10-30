import UIKit
import XCTest

@testable import ListKit

@MainActor final class SupplementaryReloadIsolationTests: XCTestCase {
    func testUnchangedSiblingAndRowsAreConfiguredOnceWithoutCrossSectionReuse() async throws {
        for animated in [false, true] {
            let f = ReviewFixture()
            defer { f.close() }
            var configurations: [String: Int] = [:]
            func section(_ id: Int, version: Int) -> ListSection<Int> {
                ListSection(id) {
                    for row in 0..<2 {
                        Row(row, model: version, cell: ReviewCell.self) { cell, model, _ in
                            let key = "row-\(id)-\(row)"
                            configurations[key, default: 0] += 1
                            cell.value = model
                        }.refresh(when: .never)
                    }
                } layout: {
                    GridLayout(tracks: 1).itemMainAxisSize(.fixed(40)).trackSpacing(0).lineSpacing(0).boundarySupplementaries {
                        BoundarySupplementaryLayout(
                            kind: "header",
                            size: .init(width: .fractionalWidth(1), height: .absolute(20)),
                            alignment: .top)
                        BoundarySupplementaryLayout(
                            kind: "footer",
                            size: .init(width: .fractionalWidth(1), height: .absolute(20)),
                            alignment: .bottom)
                    }
                } supplementaries: {
                    SectionSupplementary(ReviewView.self, kind: "header", id: version) { view, _ in
                        configurations["header-\(id)", default: 0] += 1
                        view.value = version
                    }.refresh(when: .never)
                    SectionSupplementary(ReviewView.self, kind: "footer", id: "stable") { view, _ in
                        configurations["footer-\(id)", default: 0] += 1
                        view.value = version
                    }.refreshID(version).refresh(when: .refreshIDChanges)
                }.selectionMode(.multiple)
            }
            await f.adapter.apply(transaction: .disabled) {
                section(0, version: 0)
                section(1, version: 0)
            }
            f.collection.layoutIfNeeded()
            let first = IndexPath(item: 0, section: 0)
            let second = IndexPath(item: 0, section: 1)
            let oldCell = try XCTUnwrap(f.collection.cellForItem(at: first) as? ReviewCell)
            let otherCell = try XCTUnwrap(f.collection.cellForItem(at: second))
            let otherHeader = try XCTUnwrap(
                f.collection.supplementaryView(forElementKind: "header", at: second))
            oldCell.value = -123  // Local transient state must be replaced by the new model configuration.
            f.collection.selectItem(at: first, animated: false, scrollPosition: [])
            f.collection.selectItem(at: second, animated: false, scrollPosition: [])
            configurations = [:]
            let summary = await f.adapter.apply(
                transaction: .init(animation: animated ? .enabled : .disabled)
            ) {
                section(0, version: 1)
                section(1, version: 0)
            }
            f.collection.layoutIfNeeded()
            let newCell = try XCTUnwrap(f.collection.cellForItem(at: first) as? ReviewCell)
            XCTAssertEqual(newCell.value, 1)
            XCTAssertEqual(configurations["row-0-0"], 1)
            XCTAssertEqual(configurations["row-0-1"], 1)
            XCTAssertEqual(configurations["footer-0"], 1)
            XCTAssertEqual(
                (f.collection.supplementaryView(forElementKind: "footer", at: first) as? ReviewView)?
                    .value,
                1)
            XCTAssertNil(configurations["row-1-0"])
            XCTAssertNil(configurations["footer-1"])
            XCTAssertTrue(f.collection.cellForItem(at: second) === otherCell)
            XCTAssertTrue(
                f.collection.supplementaryView(forElementKind: "header", at: second) === otherHeader
            )
            XCTAssertEqual(
                Set(f.collection.indexPathsForSelectedItems ?? []), Set([first, second]))
            XCTAssertEqual(summary.refreshMetrics.visibleReconfiguredSupplementaryCount, 0)
            XCTAssertEqual(summary.refreshMetrics.reloadedSectionCount, 1)
            XCTAssertEqual(summary.refreshMetrics.snapshotReconfiguredRowCount, 0)
            XCTAssertEqual(summary.refreshMetrics.visibleReconfiguredRowCount, 0)
        }
    }

    func testExternalFlowLayoutRetainsIdentityReplacementWithoutDSLGeometry() async throws {
        for changesType in [false, true] {
            let f = ReviewFixture()
            defer { f.close() }
            let flow = UICollectionViewFlowLayout()
            flow.itemSize = CGSize(width: 390, height: 40)
            flow.headerReferenceSize = CGSize(width: 390, height: 30)
            let kind = UICollectionView.elementKindSectionHeader
            func section(_ version: Int) -> ListSection<Int> {
                ListSection(0) {
                    Row(0, model: 0, cell: ReviewCell.self) { _, _, _ in }
                } supplementaries: {
                    if changesType && version > 0 {
                        SectionSupplementary(OtherReviewView.self, kind: kind, id: 0) { view, _ in
                            view.value = version
                        }
                        .refresh(when: .never)
                    } else {
                        SectionSupplementary(
                            ReviewView.self, kind: kind, id: changesType ? 0 : version
                        ) { view, _ in view.value = version }
                        .refresh(when: .never)
                    }
                }
            }
            let path = IndexPath(item: 0, section: 0)
            if changesType {
                // Seed managed-layout metadata, then replace the layout itself with FlowLayout.
                await f.adapter.apply(transaction: .disabled) {
                    ListSection(0) {
                        Row(0, model: 0, cell: ReviewCell.self) { _, _, _ in }
                    } layout: {
                        GridLayout(tracks: 1).itemMainAxisSize(.fixed(40)).trackSpacing(0).lineSpacing(0).boundarySupplementaries {
                            BoundarySupplementaryLayout(
                                kind: kind,
                                size: .init(width: .fractionalWidth(1), height: .absolute(30)),
                                alignment: .top)
                        }
                    } supplementaries: {
                        SectionSupplementary(ReviewView.self, kind: kind, id: 0) { _, _ in }
                    }
                }
                f.collection.layoutIfNeeded()
            }
            f.collection.collectionViewLayout = flow
            await f.adapter.apply(transaction: .disabled) { section(0) }
            f.collection.layoutIfNeeded()
            XCTAssertEqual(
                (f.collection.supplementaryView(forElementKind: kind, at: path) as? ReviewView)?
                    .value, 0)
            let replacement = await f.adapter.apply(transaction: .disabled) { section(1) }
            f.collection.layoutIfNeeded()
            XCTAssertEqual(replacement.refreshMetrics.reloadedSectionCount, 1)
            let header = try XCTUnwrap(
                f.collection.supplementaryView(forElementKind: kind, at: path) as? ReviewView)
            XCTAssertEqual(header.value, 1)
            XCTAssertEqual(header is OtherReviewView, changesType)
        }
    }

    func testDormantKindReplacementDoesNotReloadVisibleRows() async throws {
        let f = ReviewFixture()
        defer { f.close() }
        var configureCount = 0
        func section(_ version: Int) -> ListSection<Int> {
            ListSection(0) {
                Row(0, model: 0, cell: ReviewCell.self) { _, _, _ in configureCount += 1 }
                    .refresh(when: .never)
            } layout: {
                GridLayout(tracks: 1).itemMainAxisSize(.fixed(40)).trackSpacing(0).lineSpacing(0)
            } supplementaries: {
                SectionSupplementary(ReviewView.self, kind: "unused", id: version) { _, _ in }
                    .refresh(when: .never)
            }
        }
        await f.adapter.apply(transaction: .disabled) { section(0) }
        f.collection.layoutIfNeeded()
        let oldCell = try XCTUnwrap(
            f.collection.cellForItem(at: IndexPath(item: 0, section: 0)) as? ReviewCell)
        oldCell.value = 42
        let reuseCount = oldCell.reuseCount
        configureCount = 0
        let summary = await f.adapter.apply(transaction: .disabled) { section(1) }
        f.collection.layoutIfNeeded()
        XCTAssertEqual(summary.refreshMetrics.reloadedSectionCount, 0, "No layout uses this kind")
        XCTAssertEqual(configureCount, 0, "Unrelated .never Row should not be configured")
        XCTAssertEqual(oldCell.value, 42)
        XCTAssertEqual(oldCell.reuseCount, reuseCount)
        XCTAssertTrue(f.collection.cellForItem(at: IndexPath(item: 0, section: 0)) === oldCell)
    }

    func testEnvironmentDisabledKindDoesNotReloadAndReenableUsesLatestContent() async throws {
        let f = ReviewFixture()
        defer { f.close() }
        func section(_ version: Int) -> ListSection<Int> {
            ListSection(0) {
                for row in 0..<20 {
                    Row(row, model: row, cell: ReviewCell.self) { cell, model, _ in
                        cell.value = model
                    }
                    .refresh(when: .never)
                }
            } layout: {
                EnvironmentLayout(layoutKey: "width") { environment in
                    GridLayout(tracks: 1).itemMainAxisSize(.fixed(40)).trackSpacing(0).lineSpacing(0).boundarySupplementaries {
                        if environment.container.effectiveContentSize.width > 300 {
                            BoundarySupplementaryLayout(
                                kind: "header",
                                size: .init(width: .fractionalWidth(1), height: .absolute(30)),
                                alignment: .top)
                        }
                    }
                }
            } supplementaries: {
                SectionSupplementary(ReviewView.self, kind: "header", id: version) { view, _ in
                    view.value = version
                }
            }
        }
        await f.adapter.apply(transaction: .disabled) { section(0) }
        f.collection.layoutIfNeeded()
        f.collection.frame.size.width = 240
        f.collection.layoutIfNeeded()
        XCTAssertNil(
            f.collection.supplementaryView(
                forElementKind: "header", at: IndexPath(item: 0, section: 0)))
        let row = try XCTUnwrap(
            f.collection.cellForItem(at: IndexPath(item: 0, section: 0)) as? ReviewCell)
        let reuseCount = row.reuseCount
        let hidden = await f.adapter.apply(transaction: .disabled) { section(1) }
        f.collection.layoutIfNeeded()
        XCTAssertEqual(hidden.refreshMetrics.reloadedSectionCount, 0)
        XCTAssertTrue(f.collection.cellForItem(at: IndexPath(item: 0, section: 0)) === row)
        XCTAssertEqual(row.reuseCount, reuseCount)
        f.collection.frame.size.width = 390
        f.collection.layoutIfNeeded()
        XCTAssertEqual(
            (f.collection.supplementaryView(
                forElementKind: "header", at: IndexPath(item: 0, section: 0))
                as? ReviewView)?.value, 1)
        let enabled = await f.adapter.apply(transaction: .disabled) { section(2) }
        f.collection.layoutIfNeeded()
        XCTAssertEqual(enabled.refreshMetrics.reloadedSectionCount, 1)
        XCTAssertEqual(
            (f.collection.supplementaryView(
                forElementKind: "header", at: IndexPath(item: 0, section: 0))
                as? ReviewView)?.value, 2)
    }

    func testCustomBoundaryReplacementAndUnusedKindIsolation() async throws {
        let f = ReviewFixture()
        defer { f.close() }
        func section(header: Int, unused: Int) -> ListSection<Int> {
            ListSection(0) {
                Row(0, model: 0, cell: ReviewCell.self) { _, _, _ in }.refresh(when: .never)
            } layout: {
                CustomLayout(layoutKey: "custom") { _ in
                    let item = NSCollectionLayoutItem(
                        layoutSize: .init(
                            widthDimension: .fractionalWidth(1), heightDimension: .absolute(40)))
                    let group = NSCollectionLayoutGroup.vertical(
                        layoutSize: item.layoutSize, subitems: [item])
                    let layout = NSCollectionLayoutSection(group: group)
                    layout.boundarySupplementaryItems = [
                        NSCollectionLayoutBoundarySupplementaryItem(
                            layoutSize: .init(
                                widthDimension: .fractionalWidth(1), heightDimension: .absolute(30)),
                            elementKind: "header", alignment: .top)
                    ]
                    return layout
                }
            } supplementaries: {
                SectionSupplementary(ReviewView.self, kind: "header", id: header) { view, _ in
                    view.value = header
                }
                SectionSupplementary(ReviewView.self, kind: "unused", id: unused) { _, _ in }
            }
        }
        await f.adapter.apply(transaction: .disabled) { section(header: 0, unused: 0) }
        f.collection.layoutIfNeeded()
        let row = try XCTUnwrap(f.collection.cellForItem(at: IndexPath(item: 0, section: 0)))
        let hidden = await f.adapter.apply(transaction: .disabled) { section(header: 0, unused: 1) }
        f.collection.layoutIfNeeded()
        XCTAssertEqual(hidden.refreshMetrics.reloadedSectionCount, 0)
        XCTAssertTrue(f.collection.cellForItem(at: IndexPath(item: 0, section: 0)) === row)
        let enabled = await f.adapter.apply(transaction: .disabled) {
            section(header: 1, unused: 1)
        }
        f.collection.layoutIfNeeded()
        XCTAssertEqual(enabled.refreshMetrics.reloadedSectionCount, 1)
        XCTAssertEqual(
            (f.collection.supplementaryView(
                forElementKind: "header", at: IndexPath(item: 0, section: 0))
                as? ReviewView)?.value, 1)
    }

    func testDisablingGeometryDuringIdentityReplacementDoesNotReloadRows() async throws {
        for environmentSelected in [false, true] {
            let f = ReviewFixture()
            defer { f.close() }
            func section(_ version: Int, enabled: Bool) -> ListSection<Int> {
                let geometry = GridLayout(tracks: 1).itemMainAxisSize(.fixed(40)).trackSpacing(0).lineSpacing(0).boundarySupplementaries {
                    if enabled {
                        BoundarySupplementaryLayout(
                            kind: "header",
                            size: .init(width: .fractionalWidth(1), height: .absolute(30)),
                            alignment: .top)
                    }
                }
                return ListSection(0) {
                    Row(0, model: 0, cell: ReviewCell.self) { _, _, _ in }.refresh(when: .never)
                } layout: {
                    if environmentSelected {
                        EnvironmentLayout(layoutKey: enabled) { _ in geometry }
                    } else {
                        geometry
                    }
                } supplementaries: {
                    SectionSupplementary(ReviewView.self, kind: "header", id: version) { view, _ in
                        view.value = version
                    }
                }
            }
            let path = IndexPath(item: 0, section: 0)
            await f.adapter.apply(transaction: .disabled) { section(0, enabled: true) }
            f.collection.layoutIfNeeded()
            let row = try XCTUnwrap(f.collection.cellForItem(at: path) as? ReviewCell)
            row.value = 42
            let hidden = await f.adapter.apply(transaction: .disabled) {
                section(1, enabled: false)
            }
            f.collection.layoutIfNeeded()
            XCTAssertEqual(hidden.refreshMetrics.reloadedSectionCount, 0)
            XCTAssertNil(f.collection.supplementaryView(forElementKind: "header", at: path))
            XCTAssertTrue(f.collection.cellForItem(at: path) === row)
            XCTAssertEqual(row.value, 42)
            let enabled = await f.adapter.apply(transaction: .disabled) {
                section(2, enabled: true)
            }
            f.collection.layoutIfNeeded()
            XCTAssertEqual(enabled.refreshMetrics.reloadedSectionCount, 0)
            XCTAssertEqual(
                (f.collection.supplementaryView(forElementKind: "header", at: path) as? ReviewView)?
                    .value,
                2)
        }
    }

    func testProviderOwnedItemSupplementaryStillReplacesItsViewType() async throws {
        let f = ReviewFixture()
        defer { f.close() }
        func section(_ version: Int) -> ListSection<Int> {
            ListSection(0) {
                Row(0, model: 0, cell: ReviewCell.self) { _, _, _ in }
            } layout: {
                CustomLayout(layoutKey: "manual-item") { _ in
                    let supplementary = NSCollectionLayoutSupplementaryItem(
                        layoutSize: .init(
                            widthDimension: .absolute(20), heightDimension: .absolute(20)),
                        elementKind: "badge", containerAnchor: .init(edges: [.top, .trailing]))
                    let item = NSCollectionLayoutItem(
                        layoutSize: .init(
                            widthDimension: .fractionalWidth(1), heightDimension: .absolute(40)),
                        supplementaryItems: [supplementary])
                    return NSCollectionLayoutSection(
                        group: .vertical(layoutSize: item.layoutSize, subitems: [item]))
                }
            } supplementaries: {
                if version == 0 {
                    SectionSupplementary(ReviewView.self, kind: "badge", id: 0) { view, _ in
                        view.value = version
                    }
                } else {
                    SectionSupplementary(OtherReviewView.self, kind: "badge", id: 0) { view, _ in
                        view.value = version
                    }
                }
            }
        }
        let path = IndexPath(item: 0, section: 0)
        await f.adapter.apply(transaction: .disabled) { section(0) }
        f.collection.layoutIfNeeded()
        XCTAssertNotNil(
            f.collection.supplementaryView(forElementKind: "badge", at: path) as? ReviewView)
        let replacement = await f.adapter.apply(transaction: .disabled) { section(1) }
        f.collection.layoutIfNeeded()
        XCTAssertEqual(replacement.refreshMetrics.reloadedSectionCount, 1)
        XCTAssertEqual(
            (f.collection.supplementaryView(forElementKind: "badge", at: path) as? OtherReviewView)?
                .value, 1)
    }

    func testReplacementWithRowMutationsPreservesIdentitySelectionAndExplicitAnchor() async throws {
        for animated in [false, true] {
            let f = ReviewFixture()
            defer { f.close() }
            func section(_ version: Int) -> ListSection<Int> {
                ListSection(0) {
                    for row
                        in (version == 0 ? Array(0..<30) : [100, 101] + Array(2..<30).reversed())
                    {
                        Row(row, model: row, cell: ReviewCell.self) { cell, model, _ in
                            cell.value = model
                        }
                        .refresh(when: .everyApply, scope: .allMatching, action: .reload)
                    }
                } layout: {
                    GridLayout(tracks: 1).itemMainAxisSize(.fixed(40)).trackSpacing(0).lineSpacing(0).boundarySupplementaries {
                        BoundarySupplementaryLayout(
                            kind: "header",
                            size: .init(
                                width: .fractionalWidth(1),
                                height: .absolute(version == 0 ? 30 : 70)),
                            alignment: .top
                        ).pinToVisibleBounds()
                    }
                } supplementaries: {
                    SectionSupplementary(ReviewView.self, kind: "header", id: version) { view, _ in
                        view.value = version
                    }
                }.selectionMode(.multiple)
            }
            await f.adapter.apply(transaction: .disabled) { section(0) }
            f.collection.layoutIfNeeded()
            let anchor = try XCTUnwrap(f.adapter.indexPaths(forRowID: 8, in: 0).first)
            f.collection.selectItem(at: anchor, animated: false, scrollPosition: [])
            let deleted = try XCTUnwrap(f.adapter.indexPaths(forRowID: 0, in: 0).first)
            f.collection.selectItem(at: deleted, animated: false, scrollPosition: [])
            let beforeFrame = try XCTUnwrap(f.collection.layoutAttributesForItem(at: anchor)).frame
            f.collection.setContentOffset(CGPoint(x: 0, y: beforeFrame.minY - 100), animated: false)
            f.collection.layoutIfNeeded()
            let beforeY = beforeFrame.minY - f.collection.contentOffset.y
            let summary = await f.adapter.apply(
                transaction: ListTransaction(animation: animated ? .enabled : .disabled)
                    .scrollBehavior(
                        .preserveVisiblePosition(of: ListScrollTarget(8, in: 0)))
            ) { section(1) }
            f.collection.layoutIfNeeded()
            let newAnchor = try XCTUnwrap(f.adapter.indexPaths(forRowID: 8, in: 0).first)
            XCTAssertEqual(f.collection.indexPathsForSelectedItems, [newAnchor])
            XCTAssertEqual(
                try XCTUnwrap(f.collection.layoutAttributesForItem(at: newAnchor)).frame.minY
                    - f.collection.contentOffset.y, beforeY, accuracy: 1)
            XCTAssertEqual((f.collection.cellForItem(at: newAnchor) as? ReviewCell)?.value, 8)
            XCTAssertEqual(summary.refreshMetrics.reloadedSectionCount, 1)
            XCTAssertEqual(summary.refreshMetrics.reloadedRowCount, 0)
            XCTAssertEqual(summary.insertedRowCount, 2)
            XCTAssertEqual(summary.deletedRowCount, 2)
        }
    }

    func testOutlineReplacementPreservesExpansionAndSelectedChild() async throws {
        let f = ReviewFixture()
        defer { f.close() }
        func section(_ version: Int) -> ListSection<Int> {
            ListSection(0) {
                DisclosureGroup(
                    Row("parent", model: 0, cell: UICollectionViewListCell.self) { _, _, _ in }
                        .outlineDisclosure(), isExpanded: true
                ) {
                    Row("child", model: version, cell: ReviewCell.self) { cell, model, _ in
                        cell.value = model
                    }
                }
            } layout: {
                GridLayout(tracks: 1).itemMainAxisSize(.fixed(40)).trackSpacing(0).lineSpacing(0).boundarySupplementaries {
                    BoundarySupplementaryLayout(
                        kind: "header",
                        size: .init(width: .fractionalWidth(1), height: .absolute(30)),
                        alignment: .top)
                }
            } supplementaries: {
                SectionSupplementary(ReviewView.self, kind: "header", id: version) { view, _ in
                    view.value = version
                }
            }.selectionMode(.single)
        }
        await f.adapter.apply(transaction: .disabled) { section(0) }
        f.collection.layoutIfNeeded()
        let child = try XCTUnwrap(f.adapter.indexPaths(forRowID: "child", in: 0).first)
        f.collection.selectItem(at: child, animated: false, scrollPosition: [])
        await f.adapter.apply(transaction: .disabled) { section(1) }
        f.collection.layoutIfNeeded()
        XCTAssertEqual(f.collection.numberOfItems(inSection: 0), 2)
        XCTAssertEqual(f.collection.indexPathsForSelectedItems, [child])
        XCTAssertEqual((f.collection.cellForItem(at: child) as? ReviewCell)?.value, 1)
        XCTAssertEqual(
            (f.collection.supplementaryView(
                forElementKind: "header", at: IndexPath(item: 0, section: 0))
                as? ReviewView)?.value, 1)
    }

    func testOrthogonalScrollPositionSurvivesIdentityReplacement() async throws {
        for animated in [false, true] {
            for changesType in [false, true] {
                for behavior: ListOrthogonalScrollingBehavior in [
                    .continuous, .groupPagingCentered,
                ] {
                    try await checkOrthogonalReplacement(
                        animated: animated, changesType: changesType, behavior: behavior)
                }
            }
        }
    }

    private func checkOrthogonalReplacement(
        animated: Bool, changesType: Bool, behavior: ListOrthogonalScrollingBehavior
    ) async throws {
        let f = ReviewFixture()
        defer { f.close() }
        func section(_ id: Int, stage: Int, refreshID: Int = 0) -> ListSection<Int> {
            ListSection(id) {
                for row in 0..<30 {
                    Row(row, model: row, cell: ReviewCell.self) { cell, value, _ in
                        cell.value = value
                    }
                    .refresh(when: .never)
                }
            } layout: {
                GridLayout(tracks: 1).itemMainAxisSize(.fixed(100)).lineGrouping(.fitting(mainAxisSize: .fractionalViewport(1))).gridCrossAxisSize(.fixed(80)).orthogonalScrolling(behavior).trackSpacing(0).lineSpacing(0)
                .boundarySupplementaries {
                    BoundarySupplementaryLayout(
                        kind: "header",
                        size: .init(width: .fractionalWidth(1), height: .absolute(30)),
                        alignment: .top)
                }
            } supplementaries: {
                if changesType && stage % 2 == 1 {
                    SectionSupplementary(OtherReviewView.self, kind: "header", id: 0) { view, _ in
                        view.value = refreshID
                    }
                    .refreshID(refreshID).refresh(when: .refreshIDChanges)
                } else {
                    SectionSupplementary(
                        ReviewView.self, kind: "header", id: changesType ? 0 : stage
                    ) {
                        view, _ in view.value = refreshID
                    }
                    .refreshID(refreshID).refresh(when: .refreshIDChanges)
                }
            }.selectionMode(.single)
        }
        func scrollViews() -> [UIScrollView] {
            func descendants(_ view: UIView) -> [UIScrollView] {
                var result: [UIScrollView] = []
                for child in view.subviews {
                    if let scroll = child as? UIScrollView,
                        scroll.contentSize.width > scroll.bounds.width
                    {
                        result.append(scroll)
                    }
                    result += descendants(child)
                }
                return result
            }
            return descendants(f.collection).sorted { $0.frame.minY < $1.frame.minY }
        }
        await f.adapter.apply(transaction: .disabled) {
            section(0, stage: 0)
            section(1, stage: 0)
        }
        f.collection.layoutIfNeeded()
        let originalScrollViews = scrollViews()
        XCTAssertEqual(originalScrollViews.count, 2)
        guard originalScrollViews.count == 2 else { return }
        for (scroll, x) in zip(originalScrollViews, [600.0, 300.0]) {
            scroll.setContentOffset(CGPoint(x: x, y: 0), animated: false)
            scroll.layoutIfNeeded()
        }
        f.collection.layoutIfNeeded()
        let paths = [IndexPath(item: 7, section: 0), IndexPath(item: 4, section: 1)]
        let before = try paths.map { path -> CGPoint in
            f.collection.selectItem(at: path, animated: false, scrollPosition: [])
            return try XCTUnwrap(f.collection.cellForItem(at: path)).convert(.zero, to: f.window)
        }
        // Paging may settle a requested offset to a page boundary during layout.
        // Preserve those actual pre-update positions, not the pre-settlement requests.
        let initialOffsets = originalScrollViews.map(\.contentOffset)
        XCTAssertGreaterThan(initialOffsets[0].x, 0)
        XCTAssertGreaterThan(initialOffsets[1].x, 0)
        if behavior == .continuous {
            XCTAssertEqual(initialOffsets[0].x, 600, accuracy: 1)
            XCTAssertEqual(initialOffsets[1].x, 300, accuracy: 1)
        }
        let unchangedCell = try XCTUnwrap(f.collection.cellForItem(at: paths[1]))
        let outerOffset = f.collection.contentOffset
        let summary = await f.adapter.apply(
            transaction: .init(animation: animated ? .enabled : .disabled)
        ) {
            section(0, stage: 1)
            section(1, stage: 0)
        }
        f.collection.layoutIfNeeded()
        let afterScrollViews = scrollViews()
        XCTAssertEqual(afterScrollViews.count, 2)
        guard afterScrollViews.count == 2 else { return }
        XCTAssertEqual(afterScrollViews[0].contentOffset.x, initialOffsets[0].x, accuracy: 1)
        XCTAssertEqual(afterScrollViews[1].contentOffset.x, initialOffsets[1].x, accuracy: 1)
        XCTAssertEqual(f.collection.contentOffset, outerOffset)
        XCTAssertEqual(Set(f.collection.indexPathsForSelectedItems ?? []), Set(paths))
        for (path, point) in zip(paths, before) {
            let cell = try XCTUnwrap(f.collection.cellForItem(at: path))
            XCTAssertEqual(cell.convert(.zero, to: f.window).x, point.x, accuracy: 1)
        }
        XCTAssertTrue(f.collection.cellForItem(at: paths[1]) === unchangedCell)
        XCTAssertEqual(summary.refreshMetrics.reloadedSectionCount, 1)
        let headerPath = IndexPath(item: 0, section: 0)
        let header = try XCTUnwrap(
            f.collection.supplementaryView(forElementKind: "header", at: headerPath) as? ReviewView)
        XCTAssertEqual(header is OtherReviewView, changesType)
        let row = try XCTUnwrap(f.collection.cellForItem(at: paths[0]) as? ReviewCell)
        let reuseCount = row.reuseCount
        let generation = f.adapter.layoutInvalidationGeneration
        let refresh = await f.adapter.apply(
            transaction: .init(animation: animated ? .enabled : .disabled)
        ) {
            section(0, stage: 1, refreshID: 1)
            section(1, stage: 0)
        }
        f.collection.layoutIfNeeded()
        XCTAssertTrue(
            f.collection.supplementaryView(forElementKind: "header", at: headerPath) === header)
        XCTAssertEqual(header.value, 1)
        XCTAssertTrue(f.collection.cellForItem(at: paths[0]) === row)
        XCTAssertEqual(row.reuseCount, reuseCount)
        XCTAssertEqual(scrollViews()[0].contentOffset.x, initialOffsets[0].x, accuracy: 1)
        XCTAssertEqual(scrollViews()[1].contentOffset.x, initialOffsets[1].x, accuracy: 1)
        XCTAssertEqual(refresh.refreshMetrics.reloadedSectionCount, 0)
        XCTAssertGreaterThan(refresh.refreshMetrics.visibleReconfiguredSupplementaryCount, 0)
        XCTAssertEqual(f.adapter.layoutInvalidationGeneration, generation)

        // Section positions can change in the same update; offsets and selection follow IDs.
        let move = await f.adapter.apply(
            transaction: .init(animation: animated ? .enabled : .disabled)
        ) {
            section(1, stage: 0)
            section(0, stage: 2)
        }
        f.collection.layoutIfNeeded()
        XCTAssertEqual(move.refreshMetrics.reloadedSectionCount, 1)
        XCTAssertEqual(scrollViews()[0].contentOffset.x, initialOffsets[1].x, accuracy: 1)
        XCTAssertEqual(scrollViews()[1].contentOffset.x, initialOffsets[0].x, accuracy: 1)
        XCTAssertEqual(
            Set(f.collection.indexPathsForSelectedItems ?? []),
            Set([
                IndexPath(item: 4, section: 0), IndexPath(item: 7, section: 1),
            ]))
    }

    func testOffscreenOrthogonalSectionKeepsOffsetAfterReplacement() async throws {
        let f = ReviewFixture()
        defer { f.close() }
        func horizontal(_ version: Int) -> ListSection<Int> {
            ListSection(0) {
                for row in 0..<30 { Row(row, model: row, cell: ReviewCell.self) { _, _, _ in } }
            } layout: {
                GridLayout(tracks: 1).itemMainAxisSize(.fixed(100)).lineGrouping(.fitting(mainAxisSize: .fractionalViewport(1))).gridCrossAxisSize(.fixed(80)).orthogonalScrolling(.continuous).trackSpacing(0).lineSpacing(0)
                    .boundarySupplementaries {
                        BoundarySupplementaryLayout(
                            kind: "header",
                            size: .init(width: .fractionalWidth(1), height: .absolute(30)),
                            alignment: .top)
                    }
            } supplementaries: {
                SectionSupplementary(ReviewView.self, kind: "header", id: version) { view, _ in
                    view.value = version
                }
            }
        }
        func vertical() -> ListSection<Int> {
            ListSection(1) {
                for row in 0..<30 { Row(row, model: row, cell: ReviewCell.self) { _, _, _ in } }
            } layout: {
                GridLayout(tracks: 1).itemMainAxisSize(.fixed(40)).trackSpacing(0).lineSpacing(0)
            }
        }
        func inner(_ view: UIView) -> UIScrollView? {
            for child in view.subviews {
                if let scroll = child as? UIScrollView,
                    scroll.contentSize.width > scroll.bounds.width
                {
                    return scroll
                }
                if let result = inner(child) { return result }
            }
            return nil
        }
        await f.adapter.apply(transaction: .disabled) {
            horizontal(0)
            vertical()
        }
        f.collection.layoutIfNeeded()
        let original = try XCTUnwrap(inner(f.collection))
        original.setContentOffset(CGPoint(x: 600, y: 0), animated: false)
        original.layoutIfNeeded()
        f.collection.setContentOffset(CGPoint(x: 0, y: 500), animated: false)
        f.collection.layoutIfNeeded()
        let summary = await f.adapter.apply(transaction: .disabled) {
            horizontal(1)
            vertical()
        }
        f.collection.layoutIfNeeded()
        XCTAssertEqual(f.collection.contentOffset.y, 500, accuracy: 1)
        XCTAssertEqual(summary.refreshMetrics.reloadedSectionCount, 1)
        f.collection.setContentOffset(.zero, animated: false)
        f.collection.layoutIfNeeded()
        await Task.yield()
        f.collection.layoutIfNeeded()
        XCTAssertEqual(try XCTUnwrap(inner(f.collection)).contentOffset.x, 600, accuracy: 1)
        XCTAssertEqual(
            (f.collection.supplementaryView(
                forElementKind: "header", at: IndexPath(item: 0, section: 0))
                as? ReviewView)?.value, 1)
    }

    func testOrthogonalTrackingDoesNotKeepTheCollectionAlive() async throws {
        var fixture: ReviewFixture? = ReviewFixture()
        let adapter = try XCTUnwrap(fixture?.adapter)
        weak var collection = fixture?.collection
        await adapter.apply(transaction: .disabled) {
            ListSection(0) {
                for row in 0..<10 { Row(row, model: row, cell: ReviewCell.self) { _, _, _ in } }
            } layout: {
                GridLayout(tracks: 1).itemMainAxisSize(.fixed(100)).lineGrouping(.fitting(mainAxisSize: .fractionalViewport(1))).gridCrossAxisSize(.fixed(80)).orthogonalScrolling(.continuous).trackSpacing(0).lineSpacing(0)
            }
        }
        fixture?.collection.layoutIfNeeded()
        await Task.yield()
        autoreleasepool {
            fixture?.close()
            fixture = nil
        }
        // UIKit releases window/display transaction references at the end of the run loop.
        let teardown = expectation(description: "UIKit window teardown")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { teardown.fulfill() }
        await fulfillment(of: [teardown], timeout: 2)
        XCTAssertNil(
            collection, "The adapter must keep its documented weak ownership of the collection")
        _ = adapter  // Keep the adapter alive through the weak-reference assertion.
    }

    func testOffscreenReplacementAndEmptySectionRenderLatestContent() async throws {
        let f = ReviewFixture()
        defer { f.close() }
        func section(_ id: Int, version: Int, count: Int) -> ListSection<Int> {
            ListSection(id) {
                for row in 0..<count { Row(row, model: row, cell: ReviewCell.self) { _, _, _ in } }
            } layout: {
                GridLayout(tracks: 1).itemMainAxisSize(.fixed(40)).trackSpacing(0).lineSpacing(0).boundarySupplementaries {
                    BoundarySupplementaryLayout(
                        kind: "header",
                        size: .init(width: .fractionalWidth(1), height: .absolute(30)),
                        alignment: .top)
                }
            } supplementaries: {
                if version == 0 {
                    SectionSupplementary(ReviewView.self, kind: "header", id: 0) { view, _ in
                        view.value = version
                    }
                } else {
                    SectionSupplementary(OtherReviewView.self, kind: "header", id: 0) { view, _ in
                        view.value = version
                    }
                }
            }
        }
        await f.adapter.apply(transaction: .disabled) {
            section(0, version: 0, count: 30)
            section(1, version: 0, count: 0)
        }
        f.collection.layoutIfNeeded()
        await f.adapter.apply(transaction: .disabled) {
            section(0, version: 0, count: 30)
            section(1, version: 1, count: 0)
        }
        f.collection.layoutIfNeeded()
        f.collection.setContentOffset(
            CGPoint(x: 0, y: f.collection.contentSize.height - f.collection.bounds.height),
            animated: false)
        f.collection.layoutIfNeeded()
        XCTAssertEqual(
            (f.collection.supplementaryView(
                forElementKind: "header", at: IndexPath(item: 0, section: 1))
                as? OtherReviewView)?.value, 1)
    }
}

@MainActor private final class ReviewFixture {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 400))
    let collection: UICollectionView
    let adapter: CollectionListAdapter<Int>
    init() {
        let vc = UIViewController()
        window.rootViewController = vc
        window.makeKeyAndVisible()
        collection = UICollectionView(
            frame: window.bounds, collectionViewLayout: UICollectionViewFlowLayout())
        collection.contentInsetAdjustmentBehavior = .never
        vc.view.addSubview(collection)
        adapter = CollectionListAdapter<Int>(collectionView: collection)
        collection.collectionViewLayout = adapter.makeCompositionalLayout()
    }
    func close() {
        window.isHidden = true
        window.rootViewController = nil
    }
}
private final class ReviewCell: UICollectionViewCell {
    var value = 0
    var reuseCount = 0
    override func prepareForReuse() {
        super.prepareForReuse()
        reuseCount += 1
        value = -1
    }
}
private class ReviewView: UICollectionReusableView { var value = 0 }
private final class OtherReviewView: ReviewView {}

@MainActor final class OrthogonalRefreshRegressionTests: XCTestCase {
  private func horizontal(_ version: Int, count: Int = 30, id: Int = 0) -> ListSection<Int> {
    ListSection(id) {
      for row in 0..<count {
        Row(row, model: row, cell: ReviewCell.self) { _, _, _ in }.refresh(when: .never)
      }
    } layout: {
      GridLayout(tracks: 1).itemMainAxisSize(.fixed(100)).gridCrossAxisSize(.fixed(80))
        .orthogonalScrolling(.continuous).trackSpacing(0).lineSpacing(0).boundarySupplementaries {
          BoundarySupplementaryLayout(
            kind: "header", size: .init(width: .fractionalWidth(1), height: .absolute(30)),
            alignment: .top)
        }
    } supplementaries: {
      SectionSupplementary(ReviewView.self, kind: "header", id: 0) { view, _ in view.value = version
      }
      .refreshID(version).refresh(when: .refreshIDChanges, action: .reloadSection)
    }
  }
  private func vertical() -> ListSection<Int> {
    ListSection(1) {
      for row in 0..<40 {
        Row(row, model: row, cell: ReviewCell.self) { _, _, _ in }.refresh(when: .never)
      }
    } layout: {
      GridLayout(tracks: 1).itemMainAxisSize(.fixed(40))
    }
  }
  private func inner(_ view: UIView) -> UIScrollView? {
    for child in view.subviews {
      if child is UICollectionViewCell { continue }
      if let scroll = child as? UIScrollView { return scroll }
      if let found = inner(child) { return found }
    }
    return nil
  }
  private func seed(_ f: ReviewFixture) async throws {
    await f.adapter.apply(transaction: .disabled) {
      horizontal(0)
      vertical()
    }
    f.collection.layoutIfNeeded()
    let scroll = try XCTUnwrap(inner(f.collection))
    scroll.setContentOffset(CGPoint(x: 600, y: 0), animated: false)
    scroll.layoutIfNeeded()
    f.collection.layoutIfNeeded()
    XCTAssertEqual(scroll.contentOffset.x, 600, accuracy: 1)
  }
  func testOffscreenReloadThenImmediateVisibleReloadRetainsPendingOffset() async throws {
    let f = ReviewFixture()
    defer { f.close() }
    try await seed(f)
    f.collection.setContentOffset(CGPoint(x: 0, y: 500), animated: false)
    f.collection.layoutIfNeeded()
    XCTAssertFalse(f.collection.indexPathsForVisibleItems.contains { $0.section == 0 })
    _ = await f.adapter.reloadSections([0], transaction: .disabled)
    f.collection.setContentOffset(.zero, animated: false)
    f.collection.layoutIfNeeded()
    _ = await f.adapter.reloadSections([0], transaction: .disabled)
    await Task.yield()
    f.collection.layoutIfNeeded()
    XCTAssertEqual(try XCTUnwrap(inner(f.collection)).contentOffset.x, 600, accuracy: 1)
  }
  func testOffscreenReloadRestoresOffsetWithoutSecondReload() async throws {
    let f = ReviewFixture()
    defer { f.close() }
    try await seed(f)
    f.collection.setContentOffset(CGPoint(x: 0, y: 500), animated: false)
    f.collection.layoutIfNeeded()
    XCTAssertFalse(f.collection.indexPathsForVisibleItems.contains { $0.section == 0 })
    _ = await f.adapter.reloadSections([0], transaction: .disabled)
    f.collection.setContentOffset(.zero, animated: false)
    f.collection.layoutIfNeeded()
    let restored = expectation(description: "deferred restoration turn")
    DispatchQueue.main.async { restored.fulfill() }
    await fulfillment(of: [restored], timeout: 3)
    f.collection.layoutIfNeeded()
    XCTAssertEqual(try XCTUnwrap(inner(f.collection)).contentOffset.x, 600, accuracy: 1)
  }
  func testOffscreenReloadThenVisibleReloadAfterRestorationRetainsOffset() async throws {
    let f = ReviewFixture()
    defer { f.close() }
    try await seed(f)
    f.collection.setContentOffset(CGPoint(x: 0, y: 500), animated: false)
    f.collection.layoutIfNeeded()
    _ = await f.adapter.reloadSections([0], transaction: .disabled)
    f.collection.setContentOffset(.zero, animated: false)
    f.collection.layoutIfNeeded()
    let restored = expectation(description: "deferred restoration turn")
    DispatchQueue.main.async { restored.fulfill() }
    await fulfillment(of: [restored], timeout: 3)
    XCTAssertEqual(try XCTUnwrap(inner(f.collection)).contentOffset.x, 600, accuracy: 1)
    _ = await f.adapter.reloadSections([0], transaction: .disabled)
    f.collection.layoutIfNeeded()
    XCTAssertEqual(try XCTUnwrap(inner(f.collection)).contentOffset.x, 600, accuracy: 1)
  }
  func testOffscreenReloadThenImmediateApplyReloadRetainsPendingOffset() async throws {
    let f = ReviewFixture()
    defer { f.close() }
    try await seed(f)
    f.collection.setContentOffset(CGPoint(x: 0, y: 500), animated: false)
    f.collection.layoutIfNeeded()
    _ = await f.adapter.reloadSections([0], transaction: .disabled)
    f.collection.setContentOffset(.zero, animated: false)
    f.collection.layoutIfNeeded()
    await f.adapter.apply(transaction: .disabled) {
      horizontal(1)
      vertical()
    }
    f.collection.layoutIfNeeded()
    XCTAssertEqual(try XCTUnwrap(inner(f.collection)).contentOffset.x, 600, accuracy: 1)
  }
  func testRestoredOffsetDoesNotOverrideSubsequentScrolling() async throws {
    let f = ReviewFixture()
    defer { f.close() }
    try await seed(f)
    f.collection.setContentOffset(CGPoint(x: 0, y: 500), animated: false)
    f.collection.layoutIfNeeded()
    _ = await f.adapter.reloadSections([0], transaction: .disabled)
    f.collection.setContentOffset(.zero, animated: false)
    f.collection.layoutIfNeeded()
    let restored = expectation(description: "restoration finished")
    DispatchQueue.main.async { restored.fulfill() }
    await fulfillment(of: [restored], timeout: 3)
    let scroll = try XCTUnwrap(inner(f.collection))
    XCTAssertEqual(scroll.contentOffset.x, 600, accuracy: 1)
    scroll.setContentOffset(CGPoint(x: 900, y: scroll.contentOffset.y), animated: false)
    scroll.layoutIfNeeded()
    _ = await f.adapter.reloadSections([0], transaction: .disabled)
    f.collection.layoutIfNeeded()
    XCTAssertEqual(try XCTUnwrap(inner(f.collection)).contentOffset.x, 900, accuracy: 1)
  }
  func testOffscreenPendingOffsetDoesNotLeakIntoReinsertedSection() async throws {
    let f = ReviewFixture()
    defer { f.close() }
    try await seed(f)
    f.collection.setContentOffset(CGPoint(x: 0, y: 500), animated: false)
    f.collection.layoutIfNeeded()
    _ = await f.adapter.reloadSections([0], transaction: .disabled)
    await f.adapter.apply(transaction: .disabled) { vertical() }
    await f.adapter.apply(transaction: .disabled) {
      horizontal(0)
      vertical()
    }
    f.collection.setContentOffset(.zero, animated: false)
    f.collection.layoutIfNeeded()
    await Task.yield()
    f.collection.layoutIfNeeded()
    XCTAssertEqual(try XCTUnwrap(inner(f.collection)).contentOffset.x, 0, accuracy: 1)
  }
  func testReloadClampsOffsetWhenContentShrinks() async throws {
    for animated in [false, true] {
      let f = ReviewFixture()
      defer { f.close() }
      try await seed(f)
      await f.adapter.apply(transaction: .init(animation: animated ? .enabled : .disabled)) {
        horizontal(1, count: 3)
        vertical()
      }
      f.collection.layoutIfNeeded()
      let scroll = try XCTUnwrap(inner(f.collection))
      let maxX = max(
        -scroll.adjustedContentInset.left,
        scroll.contentSize.width - scroll.bounds.width + scroll.adjustedContentInset.right)
      XCTAssertLessThanOrEqual(scroll.contentOffset.x, maxX + 1)
      XCTAssertGreaterThanOrEqual(scroll.contentOffset.x, -scroll.adjustedContentInset.left - 1)
    }
  }
  func testCoalescedSectionReloadPreservesOrthogonalOffset() async throws {
    let f = ReviewFixture()
    defer { f.close() }
    try await seed(f)
    let done = expectation(description: "coalesced section reloads")
    done.expectedFulfillmentCount = 2
    f.adapter.apply(transaction: .disabled, completion: { _ in done.fulfill() }) {
      horizontal(1)
      vertical()
    }
    f.adapter.apply(transaction: .disabled, completion: { _ in done.fulfill() }) {
      horizontal(1)
      vertical()
    }
    await fulfillment(of: [done], timeout: 4)
    f.collection.layoutIfNeeded()
    XCTAssertEqual(try XCTUnwrap(inner(f.collection)).contentOffset.x, 600, accuracy: 1)
  }
}

extension OrthogonalRefreshRegressionTests {
  func testDirectScrollWinsOverPendingRestore() async throws {
    let f = ReviewFixture()
    defer { f.close() }
    try await seed(f)
    f.collection.setContentOffset(CGPoint(x: 0, y: 500), animated: false)
    f.collection.layoutIfNeeded()
    _ = await f.adapter.reloadSections([0], transaction: .disabled)
    f.collection.setContentOffset(.zero, animated: false)
    f.collection.layoutIfNeeded()
    XCTAssertTrue(f.adapter.scrollToLastItem(in: 0, at: .right, animated: false))
    f.collection.layoutIfNeeded()
    let immediate = try XCTUnwrap(inner(f.collection)).contentOffset.x
    XCTAssertGreaterThan(immediate, 2000)
    let turn = expectation(description: "pending restoration executed")
    DispatchQueue.main.async { turn.fulfill() }
    await fulfillment(of: [turn], timeout: 3)
    XCTAssertEqual(try XCTUnwrap(inner(f.collection)).contentOffset.x, immediate, accuracy: 1)
  }
  func testDirectScrollAfterRestorationWins() async throws {
    let f = ReviewFixture()
    defer { f.close() }
    try await seed(f)
    f.collection.setContentOffset(CGPoint(x: 0, y: 500), animated: false)
    f.collection.layoutIfNeeded()
    _ = await f.adapter.reloadSections([0], transaction: .disabled)
    f.collection.setContentOffset(.zero, animated: false)
    f.collection.layoutIfNeeded()
    let restored = expectation(description: "pending restoration executed")
    DispatchQueue.main.async { restored.fulfill() }
    await fulfillment(of: [restored], timeout: 3)
    XCTAssertTrue(f.adapter.scrollToLastItem(in: 0, at: .right, animated: false))
    f.collection.layoutIfNeeded()
    let immediate = try XCTUnwrap(inner(f.collection)).contentOffset.x
    XCTAssertGreaterThan(immediate, 2000)
    await Task.yield()
    XCTAssertEqual(try XCTUnwrap(inner(f.collection)).contentOffset.x, immediate, accuracy: 1)
  }
  func testMissingScrollTargetKeepsPendingOffset() async throws {
    let f = ReviewFixture()
    defer { f.close() }
    try await seed(f)
    f.collection.setContentOffset(CGPoint(x: 0, y: 500), animated: false)
    f.collection.layoutIfNeeded()
    _ = await f.adapter.reloadSections([0], transaction: .disabled)
    await f.adapter.apply(
      transaction: .disabled.scrollBehavior(.scrollTo(ListScrollTarget(999), position: .bottom))
    ) {
      horizontal(0)
      vertical()
    }
    f.collection.setContentOffset(.zero, animated: false)
    f.collection.layoutIfNeeded()
    let restored = expectation(description: "pending restoration executed")
    DispatchQueue.main.async { restored.fulfill() }
    await fulfillment(of: [restored], timeout: 3)
    XCTAssertEqual(try XCTUnwrap(inner(f.collection)).contentOffset.x, 600, accuracy: 1)
  }
}

extension OrthogonalRefreshRegressionTests {
  func testMissingLastItemTargetsKeepPendingOffset() async throws {
    for useTransaction in [false, true] {
      let f = ReviewFixture()
      defer { f.close() }
      try await seed(f)
      f.collection.setContentOffset(CGPoint(x: 0, y: 500), animated: false)
      f.collection.layoutIfNeeded()
      _ = await f.adapter.reloadSections([0], transaction: .disabled)
      if useTransaction {
        await f.adapter.apply(transaction: .disabled.scrollBehavior(.scrollToLast(in: 999))) {
          horizontal(0)
          vertical()
        }
      } else {
        XCTAssertFalse(f.adapter.scrollToLastItem(in: 999, animated: false))
      }
      f.collection.setContentOffset(.zero, animated: false)
      f.collection.layoutIfNeeded()
      let restored = expectation(description: "pending restoration completed")
      DispatchQueue.main.async { restored.fulfill() }
      await fulfillment(of: [restored], timeout: 3)
      XCTAssertEqual(try XCTUnwrap(inner(f.collection)).contentOffset.x, 600, accuracy: 1)
    }
  }
  func testTransactionScrollWinsOverPendingOffset() async throws {
    let f = ReviewFixture()
    defer { f.close() }
    try await seed(f)
    f.collection.setContentOffset(CGPoint(x: 0, y: 500), animated: false)
    f.collection.layoutIfNeeded()
    _ = await f.adapter.reloadSections([0], transaction: .disabled)
    await f.adapter.apply(
      transaction: .disabled.scrollBehavior(.scrollToLast(in: 0, position: .nearest))
    ) {
      horizontal(0)
      vertical()
    }
    f.collection.layoutIfNeeded()
    let targetOffset = try XCTUnwrap(inner(f.collection)).contentOffset.x
    XCTAssertGreaterThan(targetOffset, 2000)
    let restored = expectation(description: "scheduled restoration turn")
    DispatchQueue.main.async { restored.fulfill() }
    await fulfillment(of: [restored], timeout: 3)
    XCTAssertEqual(try XCTUnwrap(inner(f.collection)).contentOffset.x, targetOffset, accuracy: 1)
  }
  func testScrollToOtherSectionKeepsPendingOrthogonalOffset() async throws {
    for useTransaction in [false, true] {
      let f = ReviewFixture()
      defer { f.close() }
      try await seed(f)
      f.collection.setContentOffset(CGPoint(x: 0, y: 500), animated: false)
      f.collection.layoutIfNeeded()
      _ = await f.adapter.reloadSections([0], transaction: .disabled)
      if useTransaction {
        await f.adapter.apply(transaction: .disabled.scrollBehavior(.scrollToLast(in: 1))) {
          horizontal(0)
          vertical()
        }
      } else {
        XCTAssertTrue(f.adapter.scrollToLastItem(in: 1, animated: false))
      }
      f.collection.setContentOffset(.zero, animated: false)
      f.collection.layoutIfNeeded()
      let restored = expectation(description: "unrelated section restoration completed")
      DispatchQueue.main.async { restored.fulfill() }
      await fulfillment(of: [restored], timeout: 3)
      XCTAssertEqual(try XCTUnwrap(inner(f.collection)).contentOffset.x, 600, accuracy: 1)
    }
  }
}

extension OrthogonalRefreshRegressionTests {
    func testScrollDuringSectionReloadKeepsLatestOffset() async throws {
        let f = ReviewFixture(); defer { f.close() }; try await seed(f)
        let done = expectation(description: "reload finishes")
        f.adapter.reloadSections([0], transaction: .disabled, completion: { _ in done.fulfill() })
        XCTAssertTrue(f.adapter.scrollToLastItem(in: 0, at: .right, animated: false))
        f.collection.layoutIfNeeded()
        let scrolled = try XCTUnwrap(inner(f.collection)).contentOffset.x
        XCTAssertGreaterThan(scrolled, 2000)
        await fulfillment(of: [done], timeout: 3)
        XCTAssertEqual(try XCTUnwrap(inner(f.collection)).contentOffset.x, scrolled, accuracy: 1)
    }
    func testScrollDuringApplyReloadKeepsLatestOffset() async throws {
        let f = ReviewFixture(); defer { f.close() }; try await seed(f)
        let done = expectation(description: "apply finishes")
        f.adapter.apply(transaction: .disabled, completion: { _ in done.fulfill() }) {
            horizontal(1); vertical()
        }
        XCTAssertTrue(f.adapter.scrollToLastItem(in: 0, at: .right, animated: false))
        f.collection.layoutIfNeeded()
        let scrolled = try XCTUnwrap(inner(f.collection)).contentOffset.x
        XCTAssertGreaterThan(scrolled, 2000)
        await fulfillment(of: [done], timeout: 3)
        XCTAssertEqual(try XCTUnwrap(inner(f.collection)).contentOffset.x, scrolled, accuracy: 1)
    }
    func testScrollFromReloadCompletionKeepsLatestOffset() async throws {
        let f = ReviewFixture(); defer { f.close() }; try await seed(f)
        let done = expectation(description: "reload and explicit scroll finish")
        var scrolled: CGFloat = 0
        f.adapter.reloadSections([0], transaction: .disabled, completion: { _ in
            XCTAssertTrue(f.adapter.scrollToLastItem(in: 0, at: .right, animated: false))
            f.collection.layoutIfNeeded()
            scrolled = self.inner(f.collection)?.contentOffset.x ?? 0
            done.fulfill()
        })
        await fulfillment(of: [done], timeout: 3)
        XCTAssertGreaterThan(scrolled, 2000)
        XCTAssertEqual(try XCTUnwrap(inner(f.collection)).contentOffset.x, scrolled, accuracy: 1)
    }
    func testTransactionScrollOverridesCapturedReloadOffset() async throws {
        let f = ReviewFixture(); defer { f.close() }; try await seed(f)
        await f.adapter.apply(transaction: .disabled.scrollBehavior(.scrollToLast(in: 0, position: .nearest))) {
            horizontal(1); vertical()
        }
        f.collection.layoutIfNeeded()
        XCTAssertGreaterThan(try XCTUnwrap(inner(f.collection)).contentOffset.x, 2000)
    }

    func testScrollDuringRefreshOnlyInvalidatesTargetSectionSnapshot() async throws {
        for useApply in [false, true] {
            let f = ReviewFixture(); defer { f.close() }
            await f.adapter.apply(transaction: .disabled) {
                horizontal(0); horizontal(0, id: 2)
            }
            f.collection.layoutIfNeeded()
            func scroll(in section: Int) throws -> UIScrollView {
                let path = try XCTUnwrap(f.collection.indexPathsForVisibleItems.first { $0.section == section })
                var view = try XCTUnwrap(f.collection.cellForItem(at: path)).superview
                while let current = view, current !== f.collection {
                    if let scroll = current as? UIScrollView { return scroll }
                    view = current.superview
                }
                return try XCTUnwrap(nil as UIScrollView?, "Orthogonal scroll container unavailable")
            }
            for (section, offset) in [(0, 600.0), (1, 300.0)] {
                let view = try scroll(in: section)
                view.setContentOffset(CGPoint(x: offset, y: 0), animated: false)
                view.layoutIfNeeded()
                XCTAssertEqual(view.contentOffset.x, offset, accuracy: 1)
            }
            let done = expectation(description: "both sections refreshed")
            if useApply {
                f.adapter.apply(transaction: .disabled, completion: { _ in done.fulfill() }) {
                    horizontal(1); horizontal(1, id: 2)
                }
            } else {
                f.adapter.reloadSections([0, 2], transaction: .disabled, completion: { _ in done.fulfill() })
            }
            XCTAssertTrue(f.adapter.scrollToLastItem(in: 0, at: .right, animated: false))
            f.collection.layoutIfNeeded()
            let targetOffset = try scroll(in: 0).contentOffset.x
            XCTAssertGreaterThan(targetOffset, 2000)
            // Force the unrelated container to need its captured restoration.
            try scroll(in: 1).setContentOffset(.zero, animated: false)
            await fulfillment(of: [done], timeout: 3)
            XCTAssertEqual(try scroll(in: 0).contentOffset.x, targetOffset, accuracy: 1)
            XCTAssertEqual(try scroll(in: 1).contentOffset.x, 300, accuracy: 1)
            // A later capture must still preserve the new explicit position.
            _ = await f.adapter.reloadSections([0, 2], transaction: .disabled)
            XCTAssertEqual(try scroll(in: 0).contentOffset.x, targetOffset, accuracy: 1)
            XCTAssertEqual(try scroll(in: 1).contentOffset.x, 300, accuracy: 1)
        }
    }

    func testInvalidScrollDuringRefreshKeepsCapturedOffset() async throws {
        for useApply in [false, true] {
            let f = ReviewFixture(); defer { f.close() }
            try await seed(f)
            await f.adapter.apply(transaction: .disabled) {
                horizontal(0); vertical(); ListSection(2) {}
            }
            let done = expectation(description: "refresh with invalid scroll finishes")
            if useApply {
                f.adapter.apply(transaction: .disabled, completion: { _ in done.fulfill() }) {
                    horizontal(1); vertical(); ListSection(2) {}
                }
            } else {
                f.adapter.reloadSections([0], transaction: .disabled, completion: { _ in done.fulfill() })
            }
            XCTAssertFalse(f.adapter.scrollToLastItem(in: 999, animated: false))
            XCTAssertFalse(f.adapter.scrollToLastItem(in: 2, animated: false))
            // Restoration must actually run, rather than merely leave an unchanged offset.
            try XCTUnwrap(inner(f.collection)).setContentOffset(.zero, animated: false)
            await fulfillment(of: [done], timeout: 3)
            XCTAssertEqual(try XCTUnwrap(inner(f.collection)).contentOffset.x, 600, accuracy: 1)
        }
    }
}
