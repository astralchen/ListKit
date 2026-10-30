import UIKit
import XCTest

@testable import ListKit

@MainActor final class RefreshMechanismRegressionTests: XCTestCase {

    func testCoalescedLayoutChangeFinishesBeforeUsingNewSignature() async throws {
        let f = CollectionRefreshRegressionFixture()
        defer { f.close() }
        func section(_ height: CGFloat) -> ListSection<Int> {
            ListSection(0) {
                Row(0, model: 0, cell: RefreshRegressionCell.self) { _, _, _ in }
                    .refresh(when: .never)
            } layout: {
                GridLayout(tracks: 1).itemMainAxisSize(.fixed(height))
            }
        }
        await f.adapter.apply(transaction: .disabled) { section(40) }
        let generation = f.adapter.layoutInvalidationGeneration
        let done = expectation(description: "coalesced layout updates")
        done.expectedFulfillmentCount = 2
        f.adapter.apply(transaction: .disabled, completion: { _ in done.fulfill() }) { section(120) }
        f.adapter.apply(transaction: .disabled, completion: { _ in done.fulfill() }) { section(120) }
        await fulfillment(of: [done], timeout: 5)
        XCTAssertEqual(f.adapter.layoutInvalidationGeneration, generation + 1)
        let cell = try XCTUnwrap(f.collection.cellForItem(at: IndexPath(item: 0, section: 0)))
        XCTAssertEqual(cell.frame.height, 120, accuracy: 1)
    }

    func testTableStableHeaderAndFooterRefreshWithoutReloadingRows() async throws {
        let f = TableRefreshRegressionFixture()
        defer { f.close() }
        var rowConfigurations = 0
        func section(_ version: Int) -> TableSection<Int> {
            TableSection(0) {
                TableRow(0, model: 0, cell: RefreshRegressionTableCell.self) { _, _, _ in
                    rowConfigurations += 1
                }.height(.fixed(40)).refresh(when: .never)
            } header: {
                TableHeader(RefreshRegressionHeader.self, id: "header") { view, _ in view.value = version }
                    .height(.fixed(30)).refreshID(version)
            } footer: {
                TableFooter(RefreshRegressionHeader.self, id: "footer") { view, _ in view.value = version }
                    .height(.fixed(30)).refreshID(version)
            }
        }
        await f.adapter.apply(transaction: .disabled) { section(0) }
        let header = try XCTUnwrap(f.table.headerView(forSection: 0))
        let footer = try XCTUnwrap(f.table.footerView(forSection: 0))
        rowConfigurations = 0
        let summary = await f.adapter.apply(transaction: .disabled) { section(1) }
        XCTAssertEqual(summary.refreshMetrics.reloadedSectionCount, 0)
        XCTAssertEqual(summary.refreshMetrics.visibleReconfiguredSupplementaryCount, 2)
        XCTAssertEqual(rowConfigurations, 0)
        XCTAssertTrue(f.table.headerView(forSection: 0) === header)
        XCTAssertTrue(f.table.footerView(forSection: 0) === footer)
        XCTAssertEqual((header as? RefreshRegressionHeader)?.value, 1)
        XCTAssertEqual((footer as? RefreshRegressionHeader)?.value, 1)
    }

    func testTableSupplementaryPresenceChangesWithNeverTrigger() async throws {
        for animated in [false, true] {
            let f = TableRefreshRegressionFixture()
            defer { f.close() }
            func section(_ hasSupplementaries: Bool) -> TableSection<Int> {
                TableSection(0) {
                    TableRow(0, model: 0, cell: RefreshRegressionTableCell.self) { _, _, _ in }
                        .height(.fixed(40)).refresh(when: .never)
                } header: {
                    if hasSupplementaries {
                        TableHeader(RefreshRegressionHeader.self, id: "header") { view, _ in view.value = 1 }
                            .height(.fixed(30)).refresh(when: .never)
                    }
                } footer: {
                    if hasSupplementaries {
                        TableFooter(RefreshRegressionHeader.self, id: "footer") { view, _ in view.value = 1 }
                            .height(.fixed(30)).refresh(when: .never)
                    }
                }.selectionMode(.single)
            }
            await f.adapter.apply(transaction: .disabled) { section(false) }
            let selected = IndexPath(row: 0, section: 0)
            f.table.selectRow(at: selected, animated: false, scrollPosition: .none)
            let transaction = ListTransaction(animation: animated ? .enabled : .disabled)
            let added = await f.adapter.apply(transaction: transaction) { section(true) }
            XCTAssertEqual(added.refreshMetrics.reloadedSectionCount, 1)
            XCTAssertEqual(added.refreshMetrics.visibleReconfiguredSupplementaryCount, 0)
            XCTAssertEqual((f.table.headerView(forSection: 0) as? RefreshRegressionHeader)?.value, 1)
            XCTAssertEqual((f.table.footerView(forSection: 0) as? RefreshRegressionHeader)?.value, 1)
            XCTAssertEqual(f.table.indexPathForSelectedRow, selected)
            let removed = await f.adapter.apply(transaction: transaction) { section(false) }
            XCTAssertEqual(removed.refreshMetrics.reloadedSectionCount, 1)
            // 移除自定义内容后 UIKit 可以创建系统默认的空 header/footer；
            // 验证旧自定义视图已退出，而不是要求系统连占位视图也必须删除。
            XCTAssertFalse(f.table.headerView(forSection: 0) is RefreshRegressionHeader)
            XCTAssertFalse(f.table.footerView(forSection: 0) is RefreshRegressionHeader)
            XCTAssertEqual(f.table.indexPathForSelectedRow, selected)
        }
    }

    func testCollectionReentrantTargetedRefreshWaitsForQueuedApply() async {
        for reloadSection in [false, true] {
            let f = CollectionRefreshRegressionFixture()
            defer { f.close() }
            func section(_ value: Int) -> ListSection<Int> {
                ListSection(0) {
                    Row(0, model: value, cell: RefreshRegressionCell.self) { cell, value, _ in
                        cell.value = value
                    }
                } layout: {
                    GridLayout(tracks: 1).itemMainAxisSize(.fixed(40))
                }
            }
            await f.adapter.apply(transaction: .disabled) { section(0) }
            let transaction = ListTransaction(animation: .disabled, updatePolicy: .serial)
            let done = expectation(description: "queued apply precedes targeted refresh")
            done.expectedFulfillmentCount = 3
            var order: [Int] = []
            f.adapter.apply(
                transaction: transaction,
                completion: { _ in
                    order.append(1)
                    done.fulfill()
                    let complete: (ListRefreshSummary) -> Void = { _ in
                        order.append(3)
                        done.fulfill()
                    }
                    if reloadSection {
                        f.adapter.reloadSections([0], transaction: transaction, completion: complete)
                    } else {
                        f.adapter.reconfigureRows(forRowID: 0, transaction: transaction, completion: complete)
                    }
                }
            ) { section(1) }
            f.adapter.apply(
                transaction: transaction,
                completion: { _ in
                    order.append(2)
                    done.fulfill()
                }
            ) { section(2) }
            await fulfillment(of: [done], timeout: 5)
            XCTAssertEqual(order, [1, 2, 3])
            XCTAssertEqual(
                (f.collection.cellForItem(at: IndexPath(item: 0, section: 0)) as? RefreshRegressionCell)?
                    .value, 2)
        }
    }
    func testTableReentrantTargetedRefreshWaitsForQueuedApply() async {
        for reloadSection in [false, true] {
            let f = TableRefreshRegressionFixture()
            defer { f.close() }
            func section(_ value: Int) -> TableSection<Int> {
                TableSection(0) {
                    TableRow(0, model: value, cell: RefreshRegressionTableCell.self) { cell, value, _ in
                        cell.value = value
                    }.height(.fixed(40))
                }
            }
            await f.adapter.apply(transaction: .disabled) { section(0) }
            let transaction = ListTransaction(animation: .disabled, updatePolicy: .serial)
            let done = expectation(description: "queued apply precedes targeted refresh")
            done.expectedFulfillmentCount = 3
            var order: [Int] = []
            f.adapter.apply(
                transaction: transaction,
                completion: { _ in
                    order.append(1)
                    done.fulfill()
                    let complete: (ListRefreshSummary) -> Void = { _ in
                        order.append(3)
                        done.fulfill()
                    }
                    if reloadSection {
                        f.adapter.reloadSections([0], transaction: transaction, completion: complete)
                    } else {
                        f.adapter.reconfigureRows(forRowID: 0, transaction: transaction, completion: complete)
                    }
                }
            ) { section(1) }
            f.adapter.apply(
                transaction: transaction,
                completion: { _ in
                    order.append(2)
                    done.fulfill()
                }
            ) { section(2) }
            await fulfillment(of: [done], timeout: 5)
            XCTAssertEqual(order, [1, 2, 3])
            XCTAssertEqual(
                (f.table.cellForRow(at: IndexPath(item: 0, section: 0)) as? RefreshRegressionTableCell)?
                    .value, 2)
        }
    }

    func testVisibleInvalidateRemeasuresCell() async throws {
        let f = CollectionRefreshRegressionFixture()
        defer { f.close() }
        func section(_ height: Int) -> ListSection<Int> {
            ListSection(0) {
                Row(0, model: height, cell: RefreshRegressionSizingCell.self) { cell, model, _ in
                    cell.measuredHeight = CGFloat(model)
                }
                .refreshID(height).refresh(
                    when: .refreshIDChanges, scope: .visible, action: .reconfigure(layout: .invalidate))
            } layout: {
                GridLayout(tracks: 1).itemMainAxisSize(.estimated(40))
            }
        }
        await f.adapter.apply(transaction: .disabled) { section(40) }
        f.collection.layoutIfNeeded()
        let path = IndexPath(item: 0, section: 0)
        XCTAssertEqual(try XCTUnwrap(f.collection.cellForItem(at: path)).frame.height, 40, accuracy: 1)
        let result = await f.adapter.apply(transaction: .disabled) { section(120) }
        XCTAssertTrue(result.animation.layoutInvalidated)
        f.collection.layoutIfNeeded()
        XCTAssertEqual(try XCTUnwrap(f.collection.cellForItem(at: path)).frame.height, 120, accuracy: 1)
    }
    func testSerialCompletionReentrancyPreservesCallOrder() async {
        let f = CollectionRefreshRegressionFixture()
        defer { f.close() }
        func section(_ value: Int) -> ListSection<Int> {
            ListSection(0) {
                Row(0, model: value, cell: RefreshRegressionCell.self) { cell, model, _ in
                    cell.value = model
                }
            } layout: {
                GridLayout(tracks: 1).itemMainAxisSize(.fixed(40))
            }
        }
        await f.adapter.apply(transaction: .disabled) { section(0) }
        let done = expectation(description: "three serial completions")
        done.expectedFulfillmentCount = 3
        let transaction = ListTransaction(animation: .disabled, updatePolicy: .serial)
        var order: [Int] = []
        f.adapter.apply(
            transaction: transaction,
            completion: { _ in
                order.append(1)
                done.fulfill()
                f.adapter.apply(
                    transaction: transaction,
                    completion: { _ in
                        order.append(3)
                        done.fulfill()
                    }
                ) { section(3) }
            }
        ) { section(1) }
        f.adapter.apply(
            transaction: transaction,
            completion: { _ in
                order.append(2)
                done.fulfill()
            }
        ) { section(2) }
        await fulfillment(of: [done], timeout: 5)
        XCTAssertEqual(order, [1, 2, 3])
    }
    func testTableSerialCompletionReentrancyPreservesCallOrder() async {
        let f = TableRefreshRegressionFixture()
        defer { f.close() }
        func section(_ value: Int) -> TableSection<Int> {
            TableSection(0) {
                TableRow(0, model: value, cell: RefreshRegressionTableCell.self) { cell, model, _ in
                    cell.value = model
                }.height(.fixed(40))
            }
        }
        await f.adapter.apply(transaction: .disabled) { section(0) }
        let done = expectation(description: "three serial completions")
        done.expectedFulfillmentCount = 3
        let transaction = ListTransaction(animation: .disabled, updatePolicy: .serial)
        var order: [Int] = []
        f.adapter.apply(
            transaction: transaction,
            completion: { _ in
                order.append(1)
                done.fulfill()
                f.adapter.apply(
                    transaction: transaction,
                    completion: { _ in
                        order.append(3)
                        done.fulfill()
                    }
                ) { section(3) }
            }
        ) { section(1) }
        f.adapter.apply(
            transaction: transaction,
            completion: { _ in
                order.append(2)
                done.fulfill()
            }
        ) { section(2) }
        await fulfillment(of: [done], timeout: 5)
        XCTAssertEqual(order, [1, 2, 3])
    }
    func testTableCoalescedVisibleRefreshDoesNotLoseContent() async {
        let f = TableRefreshRegressionFixture()
        defer { f.close() }
        func section(_ version: Int) -> TableSection<Int> {
            TableSection(0) {
                TableRow(0, model: version, cell: RefreshRegressionTableCell.self) { cell, model, _ in
                    cell.value = model
                }
                .height(.fixed(40)).refreshID(version).refresh(when: .refreshIDChanges, scope: .visible)
            } header: {
                TableHeader(RefreshRegressionHeader.self, id: 0) { view, _ in view.value = version }.height(
                    .fixed(30)
                ).refreshID(version)
            } footer: {
                TableFooter(RefreshRegressionHeader.self, id: 0) { view, _ in view.value = version }.height(
                    .fixed(30)
                ).refreshID(version)
            }
        }
        await f.adapter.apply(transaction: .disabled) { section(0) }
        f.table.layoutIfNeeded()
        let done = expectation(description: "two table applies")
        done.expectedFulfillmentCount = 2
        f.adapter.apply(transaction: .disabled, completion: { _ in done.fulfill() }) { section(1) }
        f.adapter.apply(transaction: .disabled, completion: { _ in done.fulfill() }) { section(1) }
        await fulfillment(of: [done], timeout: 5)
        f.table.layoutIfNeeded()
        XCTAssertEqual(
            (f.table.cellForRow(at: IndexPath(row: 0, section: 0)) as? RefreshRegressionTableCell)?.value,
            1)
        XCTAssertEqual((f.table.headerView(forSection: 0) as? RefreshRegressionHeader)?.value, 1)
        XCTAssertEqual((f.table.footerView(forSection: 0) as? RefreshRegressionHeader)?.value, 1)
    }
    func testTableHeaderIdentityReplacement() async throws {
        let f = TableRefreshRegressionFixture()
        defer { f.close() }
        func section(_ version: Int) -> TableSection<Int> {
            TableSection(0) {
                TableRow(0, model: 0, cell: UITableViewCell.self) { _, _, _ in }.height(.fixed(40)).refresh(
                    when: .never)
            } header: {
                TableHeader(RefreshRegressionHeader.self, id: version) { view, _ in view.value = version }
                    .height(.fixed(30)).refresh(when: .never)
            }
        }
        await f.adapter.apply(transaction: .disabled) { section(0) }
        f.table.layoutIfNeeded()
        XCTAssertEqual((f.table.headerView(forSection: 0) as? RefreshRegressionHeader)?.value, 0)
        let result = await f.adapter.apply(transaction: .disabled) { section(1) }
        XCTAssertEqual(result.refreshMetrics.reloadedSectionCount, 1)
        f.table.layoutIfNeeded()
        XCTAssertEqual((f.table.headerView(forSection: 0) as? RefreshRegressionHeader)?.value, 1)
    }
    func testTableHeaderTypeReplacement() async throws {
        let f = TableRefreshRegressionFixture()
        defer { f.close() }
        func section(_ other: Bool) -> TableSection<Int> {
            TableSection(0) {
                TableRow(0, model: 0, cell: UITableViewCell.self) { _, _, _ in }.height(.fixed(40)).refresh(
                    when: .never)
            } header: {
                if other {
                    TableHeader(RefreshRegressionOtherHeader.self, id: 0) { view, _ in view.value = 1 }
                        .height(.fixed(30)).refresh(when: .never)
                } else {
                    TableHeader(RefreshRegressionHeader.self, id: 0) { view, _ in view.value = 0 }.height(
                        .fixed(30))
                }
            }
        }
        await f.adapter.apply(transaction: .disabled) { section(false) }
        f.table.layoutIfNeeded()
        XCTAssertNotNil(f.table.headerView(forSection: 0))
        await f.adapter.apply(transaction: .disabled) { section(true) }
        f.table.layoutIfNeeded()
        XCTAssertTrue(f.table.headerView(forSection: 0) is RefreshRegressionOtherHeader)
    }
    func testTableFooterIdentityReplacement() async throws {
        let f = TableRefreshRegressionFixture()
        defer { f.close() }
        func section(_ version: Int) -> TableSection<Int> {
            TableSection(0) {
                TableRow(0, model: 0, cell: UITableViewCell.self) { _, _, _ in }.height(.fixed(40)).refresh(
                    when: .never)
            } footer: {
                TableFooter(RefreshRegressionHeader.self, id: version) { view, _ in view.value = version }
                    .height(.fixed(30)).refresh(when: .never)
            }
        }
        await f.adapter.apply(transaction: .disabled) { section(0) }
        f.table.layoutIfNeeded()
        XCTAssertEqual((f.table.footerView(forSection: 0) as? RefreshRegressionHeader)?.value, 0)
        let result = await f.adapter.apply(transaction: .disabled) { section(1) }
        XCTAssertEqual(result.refreshMetrics.reloadedSectionCount, 1)
        f.table.layoutIfNeeded()
        XCTAssertEqual((f.table.footerView(forSection: 0) as? RefreshRegressionHeader)?.value, 1)
    }
    func testTableFooterTypeReplacement() async throws {
        let f = TableRefreshRegressionFixture()
        defer { f.close() }
        func section(_ other: Bool) -> TableSection<Int> {
            TableSection(0) {
                TableRow(0, model: 0, cell: UITableViewCell.self) { _, _, _ in }.height(.fixed(40)).refresh(
                    when: .never)
            } footer: {
                if other {
                    TableFooter(RefreshRegressionOtherHeader.self, id: 0) { view, _ in view.value = 1 }
                        .height(.fixed(30)).refresh(when: .never)
                } else {
                    TableFooter(RefreshRegressionHeader.self, id: 0) { view, _ in view.value = 0 }.height(
                        .fixed(30))
                }
            }
        }
        await f.adapter.apply(transaction: .disabled) { section(false) }
        f.table.layoutIfNeeded()
        XCTAssertNotNil(f.table.footerView(forSection: 0))
        await f.adapter.apply(transaction: .disabled) { section(true) }
        f.table.layoutIfNeeded()
        XCTAssertTrue(f.table.footerView(forSection: 0) is RefreshRegressionOtherHeader)
    }
    func testCoalescedVisibleRefreshDoesNotLoseContent() async throws {
        let f = CollectionRefreshRegressionFixture()
        defer { f.close() }
        func section(_ version: Int) -> ListSection<Int> {
            ListSection(0) {
                Row(0, model: version, cell: RefreshRegressionCell.self) { cell, model, _ in
                    cell.value = model
                }
                .refreshID(version).refresh(
                    when: .refreshIDChanges, scope: .visible, action: .reconfigure(layout: .invalidate))
            } layout: {
                GridLayout(tracks: 1).itemMainAxisSize(.fixed(40)).boundarySupplementaries {
                    BoundarySupplementaryLayout(
                        kind: "header", size: .init(width: .fractionalWidth(1), height: .absolute(30)),
                        alignment: .top)
                }
            } supplementaries: {
                SectionSupplementary(RefreshRegressionSupplementary.self, kind: "header", id: 0) {
                    view, _ in view.value = version
                }
                .refreshID(version).refresh(when: .refreshIDChanges)
            }
        }
        await f.adapter.apply(transaction: .disabled) { section(0) }
        f.collection.layoutIfNeeded()
        let done = expectation(description: "both completions")
        done.expectedFulfillmentCount = 2
        f.adapter.apply(
            transaction: .disabled,
            completion: { summary in
                XCTAssertEqual(summary.animation.completionState, .superseded)
                done.fulfill()
            }
        ) { section(1) }
        f.adapter.apply(
            transaction: .disabled,
            completion: { summary in
                XCTAssertEqual(summary.animation.completionState, .completed)
                done.fulfill()
            }
        ) { section(1) }
        await fulfillment(of: [done], timeout: 5)
        f.collection.layoutIfNeeded()
        XCTAssertEqual(
            (f.collection.cellForItem(at: IndexPath(item: 0, section: 0)) as? RefreshRegressionCell)?
                .value, 1)
        XCTAssertEqual(
            (f.collection.supplementaryView(forElementKind: "header", at: IndexPath(item: 0, section: 0))
                as? RefreshRegressionSupplementary)?.value, 1)
    }
    func testExplicitSectionReloadPreservesOrthogonalOffset() async throws {
        try await checkOrthogonalVariants(mode: 0)
    }
    func testSupplementaryRuleReloadPreservesOrthogonalOffset() async throws {
        try await checkOrthogonalVariants(mode: 1)
    }
    func testReloadAllPreservesOrthogonalOffset() async throws { try await checkOrthogonalVariants(mode: 2) }
    private func checkOrthogonalVariants(mode: Int) async throws {
        for animated in [false, true] {
            for behavior: ListOrthogonalScrollingBehavior in [.continuous, .groupPagingCentered] {
                try await checkOrthogonal(mode: mode, animated: animated, behavior: behavior)
            }
        }
    }
    private func checkOrthogonal(mode: Int, animated: Bool, behavior: ListOrthogonalScrollingBehavior)
        async throws
    {
        let f = CollectionRefreshRegressionFixture()
        defer { f.close() }
        func section(_ version: Int) -> ListSection<Int> {
            ListSection(0) {
                for i in 0..<30 {
                    Row(i, model: i, cell: RefreshRegressionCell.self) { cell, model, _ in cell.value = model
                    }.refresh(when: .never)
                }
            } layout: {
                GridLayout(tracks: 1).itemMainAxisSize(.fixed(100)).gridCrossAxisSize(.fixed(80))
                    .orthogonalScrolling(behavior).trackSpacing(0).lineSpacing(0)
                    .boundarySupplementaries {
                        BoundarySupplementaryLayout(
                            kind: "header", size: .init(width: .fractionalWidth(1), height: .absolute(30)),
                            alignment: .top)
                    }
            } supplementaries: {
                SectionSupplementary(RefreshRegressionSupplementary.self, kind: "header", id: 0) {
                    view, _ in view.value = version
                }
                .refreshID(version).refresh(when: .refreshIDChanges, action: .reloadSection)
            }.selectionMode(.single)
        }
        await f.adapter.apply(transaction: .disabled) { section(0) }
        f.collection.layoutIfNeeded()
        let old = try XCTUnwrap(f.scrollViews().first)
        old.setContentOffset(CGPoint(x: 600, y: 0), animated: false)
        old.layoutIfNeeded()
        f.collection.layoutIfNeeded()
        let before = old.contentOffset.x
        XCTAssertGreaterThan(before, 0)
        let selected = IndexPath(item: 7, section: 0)
        f.collection.selectItem(at: selected, animated: false, scrollPosition: [])
        let transaction = ListTransaction(animation: animated ? .enabled : .disabled)
        switch mode {
        case 0: _ = await f.adapter.reloadSections([0], transaction: transaction)
        case 1: _ = await f.adapter.apply(transaction: transaction) { section(1) }
        default: _ = await f.adapter.reloadAll(transaction: transaction)
        }
        f.collection.layoutIfNeeded()
        let after = try XCTUnwrap(f.scrollViews().first).contentOffset.x
        XCTAssertEqual(after, before, accuracy: 1)
        XCTAssertEqual(f.collection.indexPathsForSelectedItems, [selected])
    }
}
@MainActor private final class CollectionRefreshRegressionFixture {
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
        adapter = CollectionListAdapter(collectionView: collection)
        collection.collectionViewLayout = adapter.makeCompositionalLayout()
    }
    func scrollViews() -> [UIScrollView] {
        func visit(_ view: UIView) -> [UIScrollView] {
            view.subviews.flatMap { child -> [UIScrollView] in
                if child is UICollectionViewCell { return [] }
                var found = visit(child)
                if let s = child as? UIScrollView, s.contentSize.width > s.bounds.width {
                    found.insert(s, at: 0)
                }
                return found
            }
        }
        return visit(collection)
    }
    func close() {
        window.isHidden = true
        window.rootViewController = nil
    }
}
@MainActor private final class TableRefreshRegressionFixture {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 400))
    let table: UITableView
    let adapter: TableListAdapter<Int>
    init() {
        let vc = UIViewController()
        window.rootViewController = vc
        window.makeKeyAndVisible()
        table = UITableView(frame: window.bounds, style: .plain)
        table.contentInsetAdjustmentBehavior = .never
        vc.view.addSubview(table)
        adapter = TableListAdapter(tableView: table)
    }
    func close() {
        window.isHidden = true
        window.rootViewController = nil
    }
}
private final class RefreshRegressionCell: UICollectionViewCell { var value = 0 }
private final class RefreshRegressionSupplementary: UICollectionReusableView { var value = 0 }
private class RefreshRegressionHeader: UITableViewHeaderFooterView { var value = 0 }
private final class RefreshRegressionOtherHeader: RefreshRegressionHeader {}

private final class RefreshRegressionTableCell: UITableViewCell { var value = 0 }
private final class RefreshRegressionSizingCell: UICollectionViewCell {
    var measuredHeight: CGFloat = 40
    override func preferredLayoutAttributesFitting(_ attributes: UICollectionViewLayoutAttributes)
        -> UICollectionViewLayoutAttributes
    {
        let result = attributes.copy() as! UICollectionViewLayoutAttributes
        result.size.height = measuredHeight
        return result
    }
}

extension RefreshMechanismRegressionTests {
  func testSupersededCollectionSummaryIncludesPerformedWork() async throws {
    let f = CollectionRefreshRegressionFixture()
    defer { f.close() }
    var rows = 0
    var headers = 0
    func section(_ version: Int) -> ListSection<Int> {
      ListSection(0) {
        Row(0, model: version, cell: RefreshRegressionCell.self) { cell, model, _ in
          rows += 1
          cell.value = model
        }.refreshID(version).refresh(
          when: .refreshIDChanges, scope: .visible, action: .reconfigure(layout: .invalidate))
      } layout: {
        GridLayout(tracks: 1).itemMainAxisSize(.fixed(40)).boundarySupplementaries {
          BoundarySupplementaryLayout(
            kind: "header", size: .init(width: .fractionalWidth(1), height: .absolute(30)),
            alignment: .top)
        }
      } supplementaries: {
        SectionSupplementary(RefreshRegressionSupplementary.self, kind: "header", id: 0) {
          view, _ in
          headers += 1
          view.value = version
        }.refreshID(version)
      }
    }
    await f.adapter.apply(transaction: .disabled) { section(0) }
    f.collection.layoutIfNeeded()
    rows = 0
    headers = 0
    let before = f.adapter.layoutInvalidationGeneration
    let done = expectation(description: "two coalesced callbacks")
    done.expectedFulfillmentCount = 2
    var first: ListApplySummary?
    f.adapter.apply(
      transaction: .disabled,
      completion: {
        first = $0
        XCTAssertEqual(f.adapter.lastApplySummary, $0)
        done.fulfill()
      }
    ) { section(1) }
    f.adapter.apply(transaction: .disabled, completion: { _ in done.fulfill() }) { section(1) }
    await fulfillment(of: [done], timeout: 4)
    let result = try XCTUnwrap(first)
    XCTAssertEqual(result.animation.completionState, .superseded)
    XCTAssertEqual(rows, 1)
    XCTAssertEqual(headers, 1)
    XCTAssertEqual(f.adapter.layoutInvalidationGeneration, before + 1)
    XCTAssertEqual(result.refreshMetrics.visibleReconfiguredRowCount, rows)
    XCTAssertEqual(result.refreshMetrics.visibleReconfiguredSupplementaryCount, headers)
    XCTAssertTrue(result.animation.layoutInvalidated)
  }
  func testSupersededTableSummaryIncludesPerformedWork() async throws {
    let f = TableRefreshRegressionFixture()
    defer { f.close() }
    var rows = 0
    var headers = 0
    func section(_ version: Int) -> TableSection<Int> {
      TableSection(0) {
        TableRow(0, model: version, cell: RefreshRegressionTableCell.self) { cell, model, _ in
          rows += 1
          cell.value = model
        }.height(.fixed(version == 0 ? 40 : 80)).refreshID(version)
          .refresh(
            when: .refreshIDChanges, scope: .visible, action: .reconfigure(layout: .invalidate))
      } header: {
        TableHeader(RefreshRegressionHeader.self, id: 0) { view, _ in
          headers += 1
          view.value = version
        }
        .height(.fixed(30)).refreshID(version)
      }
    }
    await f.adapter.apply(transaction: .disabled) { section(0) }
    f.table.layoutIfNeeded()
    rows = 0
    headers = 0
    let done = expectation(description: "two table callbacks")
    done.expectedFulfillmentCount = 2
    var first: ListApplySummary?
    f.adapter.apply(
      transaction: .disabled,
      completion: {
        first = $0
        XCTAssertEqual(f.adapter.lastApplySummary, $0)
        done.fulfill()
      }
    ) { section(1) }
    f.adapter.apply(transaction: .disabled, completion: { _ in done.fulfill() }) { section(1) }
    await fulfillment(of: [done], timeout: 4)
    let result = try XCTUnwrap(first)
    XCTAssertEqual(result.animation.completionState, .superseded)
    XCTAssertEqual(rows, 1)
    XCTAssertEqual(headers, 1)
    XCTAssertEqual(f.table.rectForRow(at: IndexPath(row: 0, section: 0)).height, 80, accuracy: 1)
    XCTAssertEqual(result.refreshMetrics.visibleReconfiguredRowCount, rows)
    XCTAssertEqual(result.refreshMetrics.visibleReconfiguredSupplementaryCount, headers)
    XCTAssertTrue(result.animation.layoutInvalidated)
  }
}

extension RefreshMechanismRegressionTests {
  func testSupersededCollectionFooterSummaryIncludesPerformedWork() async throws {
    let f = CollectionRefreshRegressionFixture()
    defer { f.close() }
    var rows = 0
    var footers = 0
    func section(_ version: Int) -> ListSection<Int> {
      ListSection(0) {
        Row(0, model: version, cell: RefreshRegressionCell.self) { cell, model, _ in
          rows += 1
          cell.value = model
        }.refreshID(version).refresh(
          when: .refreshIDChanges, scope: .visible, action: .reconfigure(layout: .invalidate))
      } layout: {
        GridLayout(tracks: 1).itemMainAxisSize(.fixed(40)).boundarySupplementaries {
          BoundarySupplementaryLayout(
            kind: "footer", size: .init(width: .fractionalWidth(1), height: .absolute(30)),
            alignment: .bottom)
        }
      } supplementaries: {
        SectionSupplementary(RefreshRegressionSupplementary.self, kind: "footer", id: 0) {
          view, _ in
          footers += 1
          view.value = version
        }.refreshID(version)
      }
    }
    await f.adapter.apply(transaction: .disabled) { section(0) }
    f.collection.layoutIfNeeded()
    rows = 0
    footers = 0
    let before = f.adapter.layoutInvalidationGeneration
    let done = expectation(description: "two coalesced callbacks")
    done.expectedFulfillmentCount = 2
    var first: ListApplySummary?
    f.adapter.apply(
      transaction: .disabled,
      completion: {
        first = $0
        XCTAssertEqual(f.adapter.lastApplySummary, $0)
        done.fulfill()
      }
    ) { section(1) }
    f.adapter.apply(transaction: .disabled, completion: { _ in done.fulfill() }) { section(1) }
    await fulfillment(of: [done], timeout: 4)
    let result = try XCTUnwrap(first)
    XCTAssertEqual(result.animation.completionState, .superseded)
    XCTAssertEqual(rows, 1)
    XCTAssertEqual(footers, 1)
    XCTAssertEqual(f.adapter.layoutInvalidationGeneration, before + 1)
    XCTAssertEqual(result.refreshMetrics.visibleReconfiguredRowCount, rows)
    XCTAssertEqual(result.refreshMetrics.visibleReconfiguredSupplementaryCount, footers)
    XCTAssertTrue(result.animation.layoutInvalidated)
  }
  func testSupersededTableFooterSummaryIncludesPerformedWork() async throws {
    let f = TableRefreshRegressionFixture()
    defer { f.close() }
    var rows = 0
    var footers = 0
    func section(_ version: Int) -> TableSection<Int> {
      TableSection(0) {
        TableRow(0, model: version, cell: RefreshRegressionTableCell.self) { cell, model, _ in
          rows += 1
          cell.value = model
        }.height(.fixed(version == 0 ? 40 : 80)).refreshID(version)
          .refresh(
            when: .refreshIDChanges, scope: .visible, action: .reconfigure(layout: .invalidate))
      } footer: {
        TableFooter(RefreshRegressionHeader.self, id: 0) { view, _ in
          footers += 1
          view.value = version
        }
        .height(.fixed(30)).refreshID(version)
      }
    }
    await f.adapter.apply(transaction: .disabled) { section(0) }
    f.table.layoutIfNeeded()
    rows = 0
    footers = 0
    let done = expectation(description: "two table callbacks")
    done.expectedFulfillmentCount = 2
    var first: ListApplySummary?
    f.adapter.apply(
      transaction: .disabled,
      completion: {
        first = $0
        XCTAssertEqual(f.adapter.lastApplySummary, $0)
        done.fulfill()
      }
    ) { section(1) }
    f.adapter.apply(transaction: .disabled, completion: { _ in done.fulfill() }) { section(1) }
    await fulfillment(of: [done], timeout: 4)
    let result = try XCTUnwrap(first)
    XCTAssertEqual(result.animation.completionState, .superseded)
    XCTAssertEqual(rows, 1)
    XCTAssertEqual(footers, 1)
    XCTAssertEqual(f.table.rectForRow(at: IndexPath(row: 0, section: 0)).height, 80, accuracy: 1)
    XCTAssertEqual(result.refreshMetrics.visibleReconfiguredRowCount, rows)
    XCTAssertEqual(result.refreshMetrics.visibleReconfiguredSupplementaryCount, footers)
    XCTAssertTrue(result.animation.layoutInvalidated)
  }
}

extension RefreshMechanismRegressionTests {
  func testSupersededCollectionApplyDoesNotExecutePendingScroll() async throws {
    let f = CollectionRefreshRegressionFixture()
    defer { f.close() }
    func section(_ version: Int) -> ListSection<Int> {
      ListSection(0) {
        for id in 0..<30 {
          Row(id, model: version, cell: RefreshRegressionCell.self) { cell, model, _ in
            cell.value = model
          }
          .refreshID(version).refresh(
            when: .refreshIDChanges, scope: .visible, action: .reconfigure(layout: .invalidate))
        }
      } layout: {
        GridLayout(tracks: 1).itemMainAxisSize(.fixed(40))
      }
    }
    await f.adapter.apply(transaction: .disabled) { section(0) }
    f.collection.layoutIfNeeded()
    let originalOffset = f.collection.contentOffset
    let done = expectation(description: "both coalesced requests complete")
    done.expectedFulfillmentCount = 2
    done.assertForOverFulfill = true
    f.adapter.apply(
      transaction: .disabled.scrollBehavior(.scrollTo(ListScrollTarget(29), position: .bottom)),
      completion: { result in
        XCTAssertEqual(result.animation.completionState, .superseded)
        XCTAssertTrue(result.animation.layoutInvalidated)
        XCTAssertFalse(result.animation.scrollAnimated)
        XCTAssertEqual(f.collection.contentOffset.y, originalOffset.y, accuracy: 1)
        done.fulfill()
      }
    ) { section(1) }
    f.adapter.apply(
      transaction: .disabled,
      completion: { result in
        XCTAssertEqual(result.animation.completionState, .completed)
        done.fulfill()
      }
    ) { section(1) }
    await fulfillment(of: [done], timeout: 4)
    XCTAssertEqual(f.collection.contentOffset.y, originalOffset.y, accuracy: 1)
  }
  func testSupersededTableApplyDoesNotExecutePendingScroll() async throws {
    let f = TableRefreshRegressionFixture()
    defer { f.close() }
    func section(_ version: Int) -> TableSection<Int> {
      TableSection(0) {
        for id in 0..<30 {
          TableRow(id, model: version, cell: RefreshRegressionTableCell.self) { cell, model, _ in
            cell.value = model
          }.height(.fixed(40))
            .refreshID(version).refresh(
              when: .refreshIDChanges, scope: .visible, action: .reconfigure(layout: .invalidate))
        }
      }
    }
    await f.adapter.apply(transaction: .disabled) { section(0) }
    f.table.layoutIfNeeded()
    let originalOffset = f.table.contentOffset
    let done = expectation(description: "both coalesced requests complete")
    done.expectedFulfillmentCount = 2
    done.assertForOverFulfill = true
    f.adapter.apply(
      transaction: .disabled.scrollBehavior(.scrollTo(ListScrollTarget(29), position: .bottom)),
      completion: { result in
        XCTAssertEqual(result.animation.completionState, .superseded)
        XCTAssertTrue(result.animation.layoutInvalidated)
        XCTAssertFalse(result.animation.scrollAnimated)
        XCTAssertEqual(f.table.contentOffset.y, originalOffset.y, accuracy: 1)
        done.fulfill()
      }
    ) { section(1) }
    f.adapter.apply(
      transaction: .disabled,
      completion: { result in
        XCTAssertEqual(result.animation.completionState, .completed)
        done.fulfill()
      }
    ) { section(1) }
    await fulfillment(of: [done], timeout: 4)
    XCTAssertEqual(f.table.contentOffset.y, originalOffset.y, accuracy: 1)
  }
}
