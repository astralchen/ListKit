import UIKit
import XCTest
@testable import ListKit

@MainActor
final class TableLayoutTests: XCTestCase {
    func testChainedHeaderAndFooterReplaceOnlyTheirOwnDeclaration() {
        let layout = TableLayout().headerHeight(.estimated(48)).footerHeight(.fixed(44))
        let original = TableSection(0) {
            TableRow(0, model: (), cell: UITableViewCell.self) { _, _, _ in }
        } layout: {
            layout
        } header: {
            TableHeader(UITableViewHeaderFooterView.self, elementID: "original") { _, _ in }
        } footer: {
            TableFooter(UITableViewHeaderFooterView.self, elementID: "end") { _, _ in }
        }
        .headerTitle("Messages")

        let replacement = original.header {
            TableHeader(UITableViewHeaderFooterView.self, elementID: "replacement") { _, _ in }
        }
        XCTAssertEqual(replacement.header?.identity.rowID.typed(String.self), "replacement")
        XCTAssertEqual(original.header?.identity.rowID.typed(String.self), "original")
        XCTAssertEqual(replacement.footer?.identity, original.footer?.identity)
        XCTAssertEqual(replacement.rows.first?.identity, original.rows.first?.identity)
        XCTAssertEqual(replacement.layout, layout)

        let cleared = replacement.footer {}.header {}
        XCTAssertNil(cleared.header)
        XCTAssertNil(cleared.footer)
        XCTAssertEqual(cleared.headerTitle, "Messages")
        XCTAssertEqual(cleared.effectiveHeaderHeight, .estimated(48))
        XCTAssertNil(cleared.effectiveFooterHeight)
    }

    func testSectionRowHeightAppliesToEveryRowBeforeDelegateAndTableDefaults() async {
        let table = UITableView()
        table.rowHeight = 80
        table.estimatedRowHeight = 81
        let adapter = TableListAdapter<Int>(tableView: table)
        let delegate = HeightDelegate()
        adapter.tableDelegate = delegate

        await adapter.apply(transaction: .disabled) {
            TableSection(0) {
                TableRow(0, model: (), cell: UITableViewCell.self) { _, _, _ in }
                TableRow(1, model: (), cell: UITableViewCell.self) { _, _, _ in }
            }
            .layout { TableLayout().rowHeight(.estimated(64)) }
            TableSection(1) {
                TableRow(0, model: (), cell: UITableViewCell.self) { _, _, _ in }
            }
            .layout { TableLayout().rowHeight(.fixed(28)) }
            TableSection(2) {
                TableRow(0, model: (), cell: UITableViewCell.self) { _, _, _ in }
            }
            .layout { TableLayout().rowHeight(.automatic) }
            TableSection(3) {
                TableRow(0, model: (), cell: UITableViewCell.self) { _, _, _ in }
            }
        }

        func check(_ row: Int, _ section: Int, actual: CGFloat, estimate: CGFloat) {
            let path = IndexPath(row: row, section: section)
            XCTAssertEqual(adapter.tableView(table, heightForRowAt: path), actual)
            XCTAssertEqual(adapter.tableView(table, estimatedHeightForRowAt: path), estimate)
        }
        check(0, 0, actual: UITableView.automaticDimension, estimate: 64)
        check(1, 0, actual: UITableView.automaticDimension, estimate: 64)
        check(0, 1, actual: 28, estimate: 28)
        check(0, 2, actual: UITableView.automaticDimension, estimate: UITableView.automaticDimension)
        check(0, 3, actual: 50, estimate: 51)
        adapter.tableDelegate = nil
        check(0, 3, actual: 80, estimate: 81)
    }

    func testRowHeightUsesStableIDsOncePerRowAcrossApplies() async {
        let table = UITableView()
        let adapter = TableListAdapter<Int>(tableView: table)
        var resolvedIDs: [AnyListID] = []

        func section(_ ids: [Int]) -> TableSection<Int> {
            TableSection(0) {
                TableRow("1", model: (), cell: UITableViewCell.self) { _, _, _ in }
                    .refresh(when: .never)
                TableForEach(ids, id: \.self) { id in
                    TableRow(model: id, cell: UITableViewCell.self) { _, _, _ in }
                        .refresh(when: .never)
                }
            }
            .layout {
                TableLayout().rowHeight(.fixed(99)).rowHeight { id in
                    resolvedIDs.append(id)
                    if id.typed(String.self) == "1" { return .fixed(28) }
                    if id.typed(Int.self) == 1 { return .estimated(68) }
                    return .automatic
                }
            }
        }

        func check(_ row: Int, actual: CGFloat, estimate: CGFloat) {
            let path = IndexPath(row: row, section: 0)
            XCTAssertEqual(adapter.tableView(table, heightForRowAt: path), actual)
            XCTAssertEqual(adapter.tableView(table, estimatedHeightForRowAt: path), estimate)
        }

        await adapter.apply(transaction: .disabled) { section([1, 2]) }
        check(0, actual: 28, estimate: 28)
        check(1, actual: UITableView.automaticDimension, estimate: 68)
        check(2, actual: UITableView.automaticDimension, estimate: UITableView.automaticDimension)
        XCTAssertEqual(resolvedIDs, [AnyListID("1"), AnyListID(1), AnyListID(2)])

        resolvedIDs.removeAll()
        await adapter.apply(transaction: .disabled) { section([3, 2, 1]) }
        check(1, actual: UITableView.automaticDimension, estimate: UITableView.automaticDimension)
        check(3, actual: UITableView.automaticDimension, estimate: 68)
        XCTAssertEqual(resolvedIDs, [AnyListID("1"), AnyListID(3), AnyListID(2), AnyListID(1)])

        let unchanged = await adapter.apply(transaction: .disabled) { section([3, 2, 1]) }
        XCTAssertFalse(unchanged.animation.layoutInvalidated)
    }

    func testExplicitChatRowIDTakesPrecedenceOverIdentifiableModelID() async {
        enum ChatRowID: Hashable, Sendable { case divider, message(Int) }
        struct Message: Identifiable { let id: Int }

        let table = UITableView()
        let adapter = TableListAdapter<Int>(tableView: table)
        var ids: [ChatRowID?] = []
        await adapter.apply(transaction: .disabled) {
            TableSection(0) {
                TableRow(ChatRowID.divider, model: (), cell: UITableViewCell.self) { _, _, _ in }
                for message in [Message(id: 7)] {
                    TableRow(ChatRowID.message(message.id), model: message, cell: UITableViewCell.self) { _, _, _ in }
                }
            }.layout {
                TableLayout().rowHeight { id in
                    ids.append(id.typed(ChatRowID.self))
                    return id.typed(ChatRowID.self) == .message(7) ? .estimated(68) : .fixed(28)
                }
            }
        }
        XCTAssertEqual(ids, [.divider, .message(7)])
        XCTAssertEqual(adapter.tableView(table, heightForRowAt: IndexPath(row: 0, section: 0)), 28)
        XCTAssertEqual(adapter.tableView(table, estimatedHeightForRowAt: IndexPath(row: 1, section: 0)), 68)
    }

    func testApplyFromHeightResolverQueuesBehindCurrentApply() async {
        for policy in [ListUpdatePolicy.serial, .coalesceLatest] {
            let table = UITableView()
            let adapter = TableListAdapter<Int>(tableView: table)
            let transaction = ListTransaction.disabled.updatePolicy(policy)
            let outer = expectation(description: "outer apply")
            let inner = expectation(description: "queued apply")
            adapter.apply(transaction: transaction, completion: { summary in
                XCTAssertEqual(summary.animation.completionState, policy == .serial ? .completed : .superseded)
                XCTAssertEqual(adapter.sectionIdentifier(at: 0), 0)
                outer.fulfill()
            }) {
                TableSection(0) {
                    TableRow(1, model: (), cell: UITableViewCell.self) { _, _, _ in }
                }.layout {
                    TableLayout().rowHeight { _ in
                        let submitted = adapter.apply(transaction: transaction, completion: { summary in
                            XCTAssertEqual(summary.animation.completionState, .completed)
                            inner.fulfill()
                        }) { TableSection(1) {} }
                        XCTAssertEqual(submitted.animation.completionState, .submitted)
                        XCTAssertEqual(adapter.sectionIdentifier(at: 0), 0)
                        return .fixed(44)
                    }
                }
            }
            await fulfillment(of: [outer, inner], timeout: 5, enforceOrder: true)
            XCTAssertEqual(adapter.sectionIdentifier(at: 0), 1)
        }
    }

    func testReloadAllResolvesCurrentHeightsBeforeLayoutAndQueuesReentrantApply() async {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        let controller = UIViewController()
        let table = UITableView(frame: window.bounds)
        controller.view = table
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }

        let adapter = TableListAdapter<Int>(tableView: table)
        var expanded = false
        var resolvedIDs: [AnyListID] = []
        let reloaded = expectation(description: "reload with updated geometry")
        let applied = expectation(description: "apply queued during reload")
        await adapter.apply(transaction: .disabled) {
            TableSection(0) {
                for id in 0..<2 {
                    TableRow(id, model: (), cell: UITableViewCell.self) { _, _, _ in }
                }
            }.layout {
                TableLayout().rowHeight { id in
                    resolvedIDs.append(id)
                    if id.typed(Int.self) == 1 { return .estimated(expanded ? 68 : 44) }
                    if expanded {
                        adapter.apply(transaction: .disabled, completion: { _ in applied.fulfill() }) {
                            TableSection(1) {}
                        }
                        XCTAssertEqual(adapter.sectionIdentifier(at: 0), 0)
                    }
                    return .fixed(expanded ? 80 : 40)
                }
            }
        }
        let first = IndexPath(row: 0, section: 0)
        table.layoutIfNeeded()
        XCTAssertEqual(table.rectForRow(at: first).height, 40, accuracy: 1)
        XCTAssertEqual(resolvedIDs, [AnyListID(0), AnyListID(1)])
        resolvedIDs.removeAll()
        expanded = true
        adapter.reloadAll(transaction: .disabled, transition: .identity) { summary in
            XCTAssertEqual(summary.animation.completionState, .completed)
            XCTAssertEqual(table.rectForRow(at: first).height, 80, accuracy: 1)
            XCTAssertEqual(adapter.tableView(table, heightForRowAt: first), 80)
            XCTAssertEqual(adapter.tableView(table, estimatedHeightForRowAt: IndexPath(row: 1, section: 0)), 68)
            XCTAssertEqual(resolvedIDs, [AnyListID(0), AnyListID(1)])
            reloaded.fulfill()
        }
        await fulfillment(of: [reloaded, applied], timeout: 5, enforceOrder: true)
        XCTAssertEqual(adapter.sectionIdentifier(at: 0), 1)
    }

    func testChangingResolvedHeightRemeasuresOnlyWhenTheRuleChanges() async {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        let controller = UIViewController()
        let table = UITableView(frame: window.bounds)
        controller.view = table
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        let adapter = TableListAdapter<Int>(tableView: table)
        var expanded = false
        let layout = TableLayout().rowHeight { id in
            id.typed(Int.self) == 1 && expanded ? .fixed(80) : .fixed(40)
        }
        let section = TableSection(0) {
            for id in 0..<2 {
                TableRow(id, model: (), cell: UITableViewCell.self) { _, _, _ in }
                    .refresh(when: .never)
            }
        }.layout { layout }
        let second = IndexPath(row: 1, section: 0)
        await adapter.apply(transaction: .disabled) { section }
        table.layoutIfNeeded()
        expanded = true
        XCTAssertEqual(adapter.tableView(table, heightForRowAt: second), 40)
        let resized = await adapter.apply(transaction: .disabled) { section }
        table.layoutIfNeeded()
        XCTAssertTrue(resized.animation.layoutInvalidated)
        XCTAssertEqual(resized.refreshMetrics.visibleReconfiguredRowCount, 0)
        XCTAssertEqual(table.rectForRow(at: second).height, 80, accuracy: 1)
        XCTAssertEqual(table.rectForRow(at: IndexPath(row: 0, section: 0)).height, 40, accuracy: 1)

        let uniform = section.layout { layout.rowHeight(.estimated(68)) }
        let replaced = await adapter.apply(transaction: .disabled) { uniform }
        XCTAssertTrue(replaced.animation.layoutInvalidated)
        XCTAssertEqual(adapter.tableView(table, heightForRowAt: second), UITableView.automaticDimension)
        XCTAssertEqual(adapter.tableView(table, estimatedHeightForRowAt: second), 68)
    }

    func testInteractiveMoveUsesDestinationSectionsHeightRule() async {
        let table = UITableView()
        let adapter = TableListAdapter<Int>(tableView: table)
        let queued = expectation(description: "apply queued during move")
        await adapter.apply(transaction: .disabled) {
            TableSection(0) {
                TableRow("divider", model: (), cell: UITableViewCell.self) { _, _, _ in }
            }.layout { TableLayout().rowHeight(.fixed(28)) }
            TableSection(1) {}
                .layout {
                    TableLayout().rowHeight { id in
                        adapter.apply(transaction: .disabled, completion: { _ in queued.fulfill() }) {
                            TableSection(2) {}
                        }
                        XCTAssertEqual(adapter.sectionIdentifier(at: 1), 1)
                        return id.typed(String.self) == "divider" ? .estimated(68) : .automatic
                    }
                }
        }

        let destination = IndexPath(row: 0, section: 1)
        adapter.tableView(table, moveRowAt: IndexPath(row: 0, section: 0), to: destination)
        XCTAssertEqual(adapter.tableView(table, heightForRowAt: destination), UITableView.automaticDimension)
        XCTAssertEqual(adapter.tableView(table, estimatedHeightForRowAt: destination), 68)
        await fulfillment(of: [queued], timeout: 5)
        XCTAssertEqual(adapter.sectionIdentifier(at: 0), 2)
    }

    func testCrossSectionMoveFinishesBothCallbacksBeforeDrainingHeightApply() async {
        let table = UITableView()
        let adapter = TableListAdapter<Int>(tableView: table)
        let serial = ListTransaction.disabled.updatePolicy(.serial)
        let applied = expectation(description: "height apply")
        let rowReloaded = expectation(description: "onMove reload")
        let dataSourceReloaded = expectation(description: "data source reload")
        let source = IndexPath(row: 0, section: 0)
        let destination = IndexPath(row: 0, section: 1)
        var callbacks: [String] = []

        let dataSource = MoveDataSource { from, to in
            XCTAssertEqual(from, source)
            XCTAssertEqual(to, destination)
            callbacks.append("dataSource")
            adapter.reloadAll(transaction: serial, transition: .identity) { _ in dataSourceReloaded.fulfill() }
            XCTAssertEqual(adapter.sectionIdentifier(at: to.section), 1)
        }
        adapter.tableDataSource = dataSource
        await adapter.apply(transaction: serial) {
            TableSection(0) {
                TableRow("divider", model: (), cell: UITableViewCell.self) { _, _, _ in }
                    .onMove { _, to in
                        callbacks.append("onMove")
                        adapter.reloadAll(transaction: serial, transition: .identity) { _ in rowReloaded.fulfill() }
                        XCTAssertEqual(adapter.sectionIdentifier(at: to.section), 1)
                    }
            }
            TableSection(1) {}.layout {
                TableLayout().rowHeight { _ in
                    callbacks.append("height")
                    adapter.apply(transaction: serial, completion: { _ in applied.fulfill() }) { TableSection(2) {} }
                    return .fixed(28)
                }
            }
        }

        withExtendedLifetime(dataSource) {
            table.dataSource?.tableView?(table, moveRowAt: source, to: destination)
        }
        XCTAssertEqual(callbacks, ["height", "onMove", "dataSource"])
        XCTAssertEqual(adapter.sectionIdentifier(at: destination.section), 1)
        await fulfillment(of: [applied, rowReloaded, dataSourceReloaded], timeout: 5, enforceOrder: true)
        XCTAssertEqual(adapter.sectionIdentifier(at: 0), 2)
    }

    func testQueuedReloadDataApplyWaitsForCrossSectionMoveBeforeReloadAll() async {
        let table = PendingMoveTableView()
        let adapter = TableListAdapter<Int>(tableView: table)
        let serial = ListTransaction.disabled.updatePolicy(.serial)
        let options = ListApplyOptions(transaction: serial, applicationMode: .reloadData)
        let applied = expectation(description: "reload-data apply completed")
        let reloaded = expectation(description: "subsequent reloadAll completed")
        await adapter.apply(transaction: serial) {
            TableSection(0) {
                TableRow(7, model: (), cell: UITableViewCell.self) { _, _, _ in }
                    .onMove { _, _ in
                        adapter.reloadAll(transaction: serial, transition: .identity) { summary in
                            XCTAssertEqual(summary.animation.completionState, .completed)
                            XCTAssertEqual(adapter.sectionIdentifier(at: 0), 2)
                            reloaded.fulfill()
                        }
                    }
            }
            TableSection(1) {}.layout {
                TableLayout().rowHeight { _ in
                    adapter.apply(options: options, completion: { summary in
                        XCTAssertEqual(summary.animation.completionState, .completed)
                        XCTAssertFalse(table.holdMoveOpen)
                        applied.fulfill()
                    }) { TableSection(2) {} }
                    return .fixed(40)
                }
            }
        }

        table.holdMoveOpen = true
        table.dataSource?.tableView?(table, moveRowAt: IndexPath(row: 0, section: 0), to: IndexPath(row: 0, section: 1))
        let checked = expectation(description: "queue checked UIKit after the move callbacks")
        table.nextUpdateCheck = checked
        await fulfillment(of: [checked], timeout: 5)
        XCTAssertEqual(adapter.sectionIdentifier(at: 0), 0)
        XCTAssertEqual(table.reloadsDuringMove, 0)

        table.holdMoveOpen = false
        await fulfillment(of: [applied, reloaded], timeout: 5, enforceOrder: true)
    }

    func testLayoutSizesOnlyDeclaredHeadersAndFooters() async {
        let table = UITableView()
        table.sectionHeaderHeight = 10
        table.estimatedSectionHeaderHeight = 11
        table.sectionFooterHeight = 12
        table.estimatedSectionFooterHeight = 13
        let adapter = TableListAdapter<Int>(tableView: table)
        let layout = TableLayout().headerHeight(.estimated(48)).footerHeight(.fixed(44))

        func render(showFooter: Bool) async {
            await adapter.apply(transaction: .disabled) {
                TableSection(0) {
                    TableRow(0, model: (), cell: UITableViewCell.self) { _, _, _ in }
                }
                .footer {
                    if showFooter {
                        TableFooter(UITableViewHeaderFooterView.self, elementID: "footer") { _, _ in }
                    }
                }
                .headerTitle("Messages")
                .layout { layout }
                TableSection(1) {}
                    .footerTitle("End")
                    .layout { layout }
            }
        }
        await render(showFooter: true)
        XCTAssertEqual(adapter.tableView(table, heightForHeaderInSection: 0), UITableView.automaticDimension)
        XCTAssertEqual(adapter.tableView(table, estimatedHeightForHeaderInSection: 0), 48)
        XCTAssertEqual(adapter.tableView(table, heightForFooterInSection: 0), 44)
        XCTAssertEqual(adapter.tableView(table, estimatedHeightForFooterInSection: 0), 44)
        XCTAssertEqual(adapter.tableView(table, heightForHeaderInSection: 1), 10)
        XCTAssertEqual(adapter.tableView(table, estimatedHeightForHeaderInSection: 1), 11)
        XCTAssertEqual(adapter.tableView(table, heightForFooterInSection: 1), 44)

        await render(showFooter: false)
        XCTAssertNil(adapter.tableView(table, viewForFooterInSection: 0))
        XCTAssertEqual(adapter.tableView(table, heightForFooterInSection: 0), 12)
        XCTAssertEqual(adapter.tableView(table, estimatedHeightForFooterInSection: 0), 13)
    }

    private func texts(in view: UIView?) -> [String] {
        guard let view else { return [] }
        if let label = view as? UILabel { return [label.text].compactMap { $0 } }
        return view.subviews.flatMap { texts(in: $0) }
    }

    func testSystemTitleChangesUpdateVisibleText() async {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        let controller = UIViewController()
        let table = UITableView(frame: window.bounds, style: .plain)
        controller.view = table
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        let adapter = TableListAdapter<Int>(tableView: table)

        let delegate = TitleDelegate()
        delegate.providesHeader = false
        delegate.providesFooter = false
        adapter.tableDelegate = delegate
        defer { withExtendedLifetime(delegate) {} }

        func render(header: String?, footer: String?) async {
            await adapter.apply(transaction: .disabled) {
                TableSection(0) {
                    TableRow(0, model: (), cell: UITableViewCell.self) { _, _, _ in }
                }
                .headerTitle(header)
                .footerTitle(footer)
                .layout { TableLayout().headerHeight(.fixed(40)).footerHeight(.fixed(32)) }
            }
            table.layoutIfNeeded()
        }

        await render(header: "HEADER ONE", footer: "FOOTER ONE")
        XCTAssertTrue(texts(in: table.headerView(forSection: 0)).contains("HEADER ONE"))
        XCTAssertTrue(texts(in: table.footerView(forSection: 0)).contains("FOOTER ONE"))

        await render(header: "HEADER TWO", footer: "FOOTER ONE")
        XCTAssertTrue(texts(in: table.headerView(forSection: 0)).contains("HEADER TWO"))
        await render(header: "HEADER TWO", footer: "FOOTER TWO")
        XCTAssertTrue(texts(in: table.footerView(forSection: 0)).contains("FOOTER TWO"))

        await render(header: nil, footer: nil)
        XCTAssertFalse(texts(in: table.headerView(forSection: 0)).contains("HEADER TWO"))
        XCTAssertFalse(texts(in: table.footerView(forSection: 0)).contains("FOOTER TWO"))

        await render(header: "HEADER THREE", footer: "FOOTER THREE")
        XCTAssertTrue(texts(in: table.headerView(forSection: 0)).contains("HEADER THREE"))
        XCTAssertTrue(texts(in: table.footerView(forSection: 0)).contains("FOOTER THREE"))
    }

    func testDelegateHeaderAndFooterMaskOnlyTheirOwnFallbackTitles() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        let controller = UIViewController()
        let table = UITableView(frame: window.bounds)
        controller.view = table
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        let adapter = TableListAdapter<Int>(tableView: table)
        let delegate = TitleDelegate()
        adapter.tableDelegate = delegate
        var rowsConfigured = 0

        func render(_ header: String, _ footer: String) async -> ListApplySummary {
            let summary = await adapter.apply(transaction: .disabled) {
                TableSection(0) {
                    TableRow(0, model: (), cell: UITableViewCell.self) { _, _, _ in rowsConfigured += 1 }
                        .refresh(when: .never)
                }
                .headerTitle(header).footerTitle(footer)
                .layout { TableLayout().headerHeight(.fixed(36)).footerHeight(.fixed(32)) }
            }
            table.layoutIfNeeded()
            return summary
        }

        _ = await render("Header A", "Footer A")
        let header = try XCTUnwrap(table.headerView(forSection: 0))
        let footer = try XCTUnwrap(table.footerView(forSection: 0))
        XCTAssertEqual(header.accessibilityIdentifier, "delegate.header")
        XCTAssertEqual(footer.accessibilityIdentifier, "delegate.footer")
        let requests = delegate.requests
        rowsConfigured = 0
        let masked = await render("Header B", "Footer B")
        XCTAssertEqual(masked.refreshMetrics.reloadedSectionCount, 0)
        XCTAssertEqual(rowsConfigured, 0)
        XCTAssertEqual(delegate.requests, requests)
        XCTAssertTrue(table.headerView(forSection: 0) === header)
        XCTAssertTrue(table.footerView(forSection: 0) === footer)

        // 替换外部代理后，页脚回退到系统标题；页眉继续由代理提供。
        let headerOnly = TitleDelegate()
        headerOnly.providesFooter = false
        adapter.tableDelegate = headerOnly
        let unmasked = await render("Header B", "Footer C")
        XCTAssertEqual(unmasked.refreshMetrics.reloadedSectionCount, 1)
        XCTAssertTrue(texts(in: table.footerView(forSection: 0)).contains("Footer C"))
        let headerChange = await render("Header C", "Footer C")
        XCTAssertEqual(headerChange.refreshMetrics.reloadedSectionCount, 0)
    }

    func testTitlesMaskedByCustomViewsDoNotReloadSection() async {
        let table = UITableView()
        let adapter = TableListAdapter<Int>(tableView: table)
        func render(_ title: String) async -> ListApplySummary {
            await adapter.apply(transaction: .disabled) {
                TableSection(0) {}
                    .header { TableHeader(UITableViewHeaderFooterView.self) { _, _ in } }
                    .footer { TableFooter(UITableViewHeaderFooterView.self) { _, _ in } }
                    .headerTitle(title)
                    .footerTitle(title)
            }
        }
        _ = await render("Before")
        let summary = await render("After")
        XCTAssertEqual(summary.refreshMetrics.reloadedSectionCount, 0)
    }

    func testChangingOnlyLayoutRemeasuresExistingContent() async {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        let controller = UIViewController()
        let table = UITableView(frame: window.bounds)
        controller.view = table
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        let adapter = TableListAdapter<Int>(tableView: table)

        func section(rowHeight: CGFloat, headerHeight: CGFloat, footerHeight: CGFloat) -> TableSection<Int> {
            TableSection(0) {
                TableRow(0, model: (), cell: UITableViewCell.self) { _, _, _ in }
                    .refresh(when: .never)
                TableRow(1, model: (), cell: UITableViewCell.self) { _, _, _ in }
                    .refresh(when: .never)
            }
            .headerTitle("Messages")
            .footerTitle("End")
            .layout {
                TableLayout()
                    .rowHeight(.fixed(rowHeight))
                    .headerHeight(.fixed(headerHeight))
                    .footerHeight(.fixed(footerHeight))
            }
        }

        await adapter.apply(transaction: .disabled) { section(rowHeight: 40, headerHeight: 30, footerHeight: 20) }
        table.layoutIfNeeded()
        let updated = await adapter.apply(transaction: .disabled) { section(rowHeight: 72, headerHeight: 30, footerHeight: 20) }
        table.layoutIfNeeded()
        XCTAssertTrue(updated.animation.layoutInvalidated)
        XCTAssertEqual(table.rectForRow(at: IndexPath(row: 0, section: 0)).height, 72, accuracy: 1)
        XCTAssertEqual(table.rectForRow(at: IndexPath(row: 1, section: 0)).height, 72, accuracy: 1)
        XCTAssertEqual(updated.refreshMetrics.visibleReconfiguredRowCount, 0)

        let resized = await adapter.apply(transaction: .disabled) { section(rowHeight: 72, headerHeight: 48, footerHeight: 36) }
        table.layoutIfNeeded()
        XCTAssertTrue(resized.animation.layoutInvalidated)
        XCTAssertEqual(table.rectForHeader(inSection: 0).height, 48, accuracy: 1)
        XCTAssertEqual(table.rectForFooter(inSection: 0).height, 36, accuracy: 1)
        XCTAssertEqual(resized.refreshMetrics.visibleReconfiguredRowCount, 0)
    }
}

@MainActor
private final class PendingMoveTableView: UITableView {
    var holdMoveOpen = false
    var nextUpdateCheck: XCTestExpectation?
    private(set) var reloadsDuringMove = 0

    override var hasUncommittedUpdates: Bool {
        nextUpdateCheck?.fulfill()
        nextUpdateCheck = nil
        return holdMoveOpen || super.hasUncommittedUpdates
    }

    override func reloadData() {
        if holdMoveOpen { reloadsDuringMove += 1 }
        super.reloadData()
    }
}

@MainActor
private final class MoveDataSource: NSObject, UITableViewDataSource {
    let didMove: (IndexPath, IndexPath) -> Void

    init(didMove: @escaping (IndexPath, IndexPath) -> Void) { self.didMove = didMove }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 0 }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell { UITableViewCell() }
    func tableView(_ tableView: UITableView, moveRowAt source: IndexPath, to destination: IndexPath) {
        didMove(source, destination)
    }
}

@MainActor
private final class TitleDelegate: NSObject, UITableViewDelegate {
    var providesHeader = true
    var providesFooter = true
    var requests = 0

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        requests += 1
        guard providesHeader else { return nil }
        let view = UITableViewHeaderFooterView()
        view.accessibilityIdentifier = "delegate.header"
        return view
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        requests += 1
        guard providesFooter else { return nil }
        let view = UITableViewHeaderFooterView()
        view.accessibilityIdentifier = "delegate.footer"
        return view
    }
}

@MainActor
private final class HeightDelegate: NSObject, UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 50 }
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat { 51 }
}
