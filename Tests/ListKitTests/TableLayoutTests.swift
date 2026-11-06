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

    func testSectionDefaultAndWholeRowOverridesTakePrecedenceOverDelegate() async {
        let table = UITableView()
        table.rowHeight = 80
        table.estimatedRowHeight = 81
        let adapter = TableListAdapter<Int>(tableView: table)
        let delegate = HeightDelegate()
        adapter.tableDelegate = delegate

        await adapter.apply(transaction: .disabled) {
            TableSection(0) {
                TableRow(0, model: (), cell: UITableViewCell.self) { _, _, _ in }
                TableRow(1, model: (), cell: UITableViewCell.self) { _, _, _ in }.height(.fixed(28))
                TableRow(2, model: (), cell: UITableViewCell.self) { _, _, _ in }.height(.automatic)
            }
            .layout { TableLayout().rowHeight(.estimated(64)) }
            TableSection(1) {
                TableRow(0, model: (), cell: UITableViewCell.self) { _, _, _ in }
            }
        }

        func check(_ row: Int, _ section: Int, actual: CGFloat, estimate: CGFloat) {
            let path = IndexPath(row: row, section: section)
            XCTAssertEqual(adapter.tableView(table, heightForRowAt: path), actual)
            XCTAssertEqual(adapter.tableView(table, estimatedHeightForRowAt: path), estimate)
        }
        check(0, 0, actual: UITableView.automaticDimension, estimate: 64)
        check(1, 0, actual: 28, estimate: 28)
        check(2, 0, actual: UITableView.automaticDimension, estimate: UITableView.automaticDimension)
        check(0, 1, actual: 50, estimate: 51)
        adapter.tableDelegate = nil
        check(0, 1, actual: 80, estimate: 81)
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
                    .height(.fixed(28))
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
        let updated = await adapter.apply(transaction: .disabled) { section(rowHeight: 72, headerHeight: 48, footerHeight: 36) }
        table.layoutIfNeeded()
        XCTAssertTrue(updated.animation.layoutInvalidated)
        XCTAssertEqual(table.rectForRow(at: IndexPath(row: 0, section: 0)).height, 72, accuracy: 1)
        XCTAssertEqual(table.rectForRow(at: IndexPath(row: 1, section: 0)).height, 28, accuracy: 1)
        XCTAssertEqual(table.rectForHeader(inSection: 0).height, 48, accuracy: 1)
        XCTAssertEqual(table.rectForFooter(inSection: 0).height, 36, accuracy: 1)
        XCTAssertEqual(updated.refreshMetrics.visibleReconfiguredRowCount, 0)
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
