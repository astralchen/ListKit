import XCTest
import UIKit
@testable import ListKit

@MainActor
final class TableListAdapterTests: XCTestCase {
    func testTableSectionBuilderCreatesRowsHeaderAndFooter() {
        let messages = [
            Message(id: 1, text: "A", version: 1),
            Message(id: 2, text: "B", version: 1)
        ]

        let sections = TableSectionsBuilder<Section>.build {
            TableSection(.messages) {
                TableForEach(messages, id: \.id) { message in
                    TableRow(model: message, cell: MessageTableCell.self) { cell, message, _ in
                        cell.textValue = message.text
                    }
                    .refreshID(message.version)
                    .contentTransition(.opacity)
                    .height(.fixed(64))
            }
        } header: {
            TableHeader(MessageHeaderView.self, id: "chrome") { view, _ in
                view.title = "Messages"
            }
            .height(.estimated(32))
        } footer: {
            TableFooter(MessageHeaderView.self, id: "chrome") { view, _ in
                view.title = "Footer"
            }
            .height(.automatic(estimated: 24))
        }
        }

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].rows.count, 2)
        XCTAssertEqual(sections[0].rows[0].identity.rowID.typed(Int.self), 1)
        XCTAssertEqual(sections[0].rows[0].contentTransition, .opacity)
        XCTAssertEqual(sections[0].header?.identity.rowID.typed(String.self), "chrome")
        XCTAssertEqual(sections[0].footer?.identity.rowID.typed(String.self), "chrome")
        XCTAssertNotEqual(sections[0].header?.identity, sections[0].footer?.identity)
    }

    func testTableAdapterApplyQueriesSelectionAndEvents() {
        let tableView = UITableView(frame: CGRect(x: 0, y: 0, width: 320, height: 240), style: .plain)
        let adapter = TableListAdapter<Section>(tableView: tableView)
        var selectedMessageID: Int?
        var receivedEvent: MessageEvent?

        adapter.apply(transaction: .disabled) {
            TableSection(.messages) {
                TableRow(
                    model: Message(id: 1, text: "A", version: 1),
                    cell: MessageTableCell.self
                ) { cell, message, context in
                    cell.textValue = message.text
                    context.send(MessageEvent.configure(messageID: message.id))
                }
                .onSelect { message, _ in
                    selectedMessageID = message.id
                }
            }
        }
        .onEvent(MessageEvent.self) { event, _ in
            receivedEvent = event
        }

        let indexPath = IndexPath(row: 0, section: 0)
        _ = adapter.tableView(tableView, cellForRowAt: indexPath)
        adapter.tableView(tableView, didSelectRowAt: indexPath)

        XCTAssertEqual(adapter.sectionIdentifier(at: 0), .messages)
        XCTAssertEqual(adapter.rowCount(in: .messages), 1)
        XCTAssertEqual(adapter.itemCount(in: .messages), 1)
        XCTAssertEqual(adapter.indexPaths(forRowID: 1, in: .messages), [indexPath])
        XCTAssertEqual(selectedMessageID, 1)
        XCTAssertEqual(receivedEvent, .configure(messageID: 1))
    }

    func testPreservingVisibleRowInShortTableDoesNotCreateAnchorInset() async {
        let tableView = UITableView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            style: .plain
        )
        let adapter = TableListAdapter<Section>(tableView: tableView)

        _ = await adapter.applyAndWait(transaction: .disabled) {
            TableSection(.messages) {
                TableRow(1, model: "Anchor", cell: MessageTableCell.self) { _, _, _ in }
                    .height(.fixed(44))
            }
        }
        tableView.layoutIfNeeded()

        let result = await adapter.applyAndWait(
            transaction: ListTransaction.disabled.scrollBehavior(
                .preserveVisiblePosition(of: ListScrollTarget(1, in: Section.messages))
            )
        ) {
            TableSection(.messages) {
                TableRow(1, model: "Anchor", cell: MessageTableCell.self) { _, _, _ in }
                    .height(.fixed(44))
                TableRow(2, model: "Trailing", cell: MessageTableCell.self) { _, _, _ in }
                    .height(.fixed(44))
            }
        }

        XCTAssertEqual(result.summary.animation.anchorCompensation, 0)
        XCTAssertEqual(tableView.contentInset.bottom, 0)
    }

    func testTableAdapterDiagnosticsAndRefreshSummary() {
        let tableView = UITableView(frame: .zero, style: .plain)
        let adapter = TableListAdapter<Section>(tableView: tableView)
        let options = ListApplyOptions(
            transaction: .disabled,
            refreshStrategy: .diffableOnly,
            diagnostics: .disabled
        )

        _ = adapter.apply(options: options) {
            TableSection(.messages) {
                TableRow(
                    model: Message(id: 1, text: "A", version: 1),
                    cell: MessageTableCell.self
                ) { _, _, _ in }
                .refreshID(1)
                .refreshPolicy(.whenRefreshIDChanges)
            }
        }

        let refreshResult = adapter.apply(options: options) {
            TableSection(.messages) {
                TableRow(
                    model: Message(id: 1, text: "B", version: 2),
                    cell: MessageTableCell.self
                ) { _, _, _ in }
                .refreshID(2)
                .refreshPolicy(.whenRefreshIDChanges)
                TableRow(
                    model: Message(id: 2, text: "C", version: 1),
                    cell: MessageTableCell.self
                ) { _, _, _ in }
            }
        }

        XCTAssertEqual(refreshResult.summary.insertedCount, 1)
        XCTAssertEqual(refreshResult.summary.keptCount, 1)
        XCTAssertEqual(refreshResult.summary.refreshIDChangedCount, 1)
        XCTAssertEqual(refreshResult.summary.snapshotRefreshCount, 1)

        let duplicateResult = adapter.apply(
            options: ListApplyOptions(
                transaction: .disabled,
                diagnostics: .init(mode: .warning, logsApplySummary: false)
            )
        ) {
            TableSection(.messages) {
                TableRow(1, model: "A", cell: MessageTableCell.self) { _, _, _ in }
                TableRow(1, model: "B", cell: MessageTableCell.self) { _, _, _ in }
            }
        }

        XCTAssertTrue(duplicateResult.summary.diagnosticsIssues.contains { $0.kind == .duplicateRow })
    }

    func testTableRowDelegateSurface() {
        let tableView = UITableView(frame: .zero, style: .plain)
        let adapter = TableListAdapter<Section>(tableView: tableView)
        var displayedID: Int?
        var endedID: Int?
        var prefetchedID: Int?
        var cancelledID: Int?
        var committedDeleteID: Int?
        var moved: (source: Int, destination: Int)?

        adapter.apply(transaction: .disabled) {
            TableSection(.messages) {
                TableRow(
                    model: Message(id: 1, text: "A", version: 1),
                    cell: MessageTableCell.self
                ) { _, _, _ in }
                .height(.fixed(72))
                .estimatedHeight(70)
                .onDisplay { message, _, _ in displayedID = message.id }
                .onEndDisplay { message, _, _ in endedID = message.id }
                .onPrefetch { message, _ in prefetchedID = message.id }
                .onCancelPrefetch { message, _ in cancelledID = message.id }
                .editing(.delete) { message, _, _ in committedDeleteID = message.id }
                .onMove { _, source, destination in
                    moved = (source.row, destination.row)
                }
                .leadingSwipeActions { _ in UISwipeActionsConfiguration(actions: []) }
                .trailingSwipeActions { _ in UISwipeActionsConfiguration(actions: []) }
                .contextMenu { _ in UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: nil) }
            }
        }

        let indexPath = IndexPath(row: 0, section: 0)
        let cell = MessageTableCell()
        adapter.tableView(tableView, willDisplay: cell, forRowAt: indexPath)
        adapter.tableView(tableView, didEndDisplaying: cell, forRowAt: indexPath)
        adapter.tableView(tableView, prefetchRowsAt: [indexPath])
        adapter.tableView(tableView, cancelPrefetchingForRowsAt: [indexPath])
        adapter.tableView(tableView, commit: .delete, forRowAt: indexPath)
        adapter.tableView(tableView, moveRowAt: indexPath, to: IndexPath(row: 1, section: 0))

        XCTAssertEqual(adapter.tableView(tableView, heightForRowAt: indexPath), 72)
        XCTAssertEqual(adapter.tableView(tableView, estimatedHeightForRowAt: indexPath), 70)
        XCTAssertTrue(adapter.tableView(tableView, canEditRowAt: indexPath))
        XCTAssertTrue(adapter.tableView(tableView, canMoveRowAt: indexPath))
        XCTAssertNotNil(adapter.tableView(tableView, leadingSwipeActionsConfigurationForRowAt: indexPath))
        XCTAssertNotNil(adapter.tableView(tableView, trailingSwipeActionsConfigurationForRowAt: indexPath))
        XCTAssertNotNil(adapter.tableView(tableView, contextMenuConfigurationForRowAt: indexPath, point: .zero))
        XCTAssertEqual(displayedID, 1)
        XCTAssertEqual(endedID, 1)
        XCTAssertEqual(prefetchedID, 1)
        XCTAssertEqual(cancelledID, 1)
        XCTAssertEqual(committedDeleteID, 1)
        XCTAssertEqual(moved?.source, 0)
        XCTAssertEqual(moved?.destination, 1)
    }

    func testTableLifecycleUsesCapturedRowAfterSnapshotChanges() {
        let tableView = UITableView(frame: .zero, style: .plain)
        let adapter = TableListAdapter<Section>(tableView: tableView)
        let tableDelegate = TableDelegateSpy()
        var endedMessageID: Int?
        var cancelledMessageID: Int?
        adapter.tableDelegate = tableDelegate

        adapter.apply(transaction: .disabled) {
            TableSection(.messages) {
                TableRow(model: Message(id: 1, text: "A", version: 1), cell: MessageTableCell.self) { _, _, _ in }
                    .onEndDisplay { message, _, _ in endedMessageID = message.id }
                    .onCancelPrefetch { message, _ in cancelledMessageID = message.id }
            }
        }

        let oldIndexPath = IndexPath(row: 0, section: 0)
        let oldCell = MessageTableCell()
        adapter.tableView(tableView, willDisplay: oldCell, forRowAt: oldIndexPath)
        adapter.tableView(tableView, prefetchRowsAt: [oldIndexPath])

        adapter.apply(transaction: .disabled) {
            TableSection(.messages) {
                TableRow(model: Message(id: 2, text: "B", version: 1), cell: MessageTableCell.self) { _, _, _ in }
            }
        }

        adapter.tableView(tableView, didEndDisplaying: oldCell, forRowAt: oldIndexPath)
        adapter.tableView(tableView, cancelPrefetchingForRowsAt: [oldIndexPath])

        XCTAssertEqual(endedMessageID, 1)
        XCTAssertEqual(cancelledMessageID, 1)
        XCTAssertEqual(tableDelegate.didEndDisplayingCount, 1)
    }

    func testTableSelectionModeIsEnforcedPerSection() {
        let tableView = UITableView(frame: .zero, style: .plain)
        let adapter = TableListAdapter<Int>(tableView: tableView)
        var deselectedMessageID: Int?

        adapter.apply(transaction: .disabled) {
            TableSection(0) {
                TableRow(model: Message(id: 0, text: "None", version: 1), cell: MessageTableCell.self) { _, _, _ in }
            }
            .selectionMode(.none)
            TableSection(1) {
                TableRow(model: Message(id: 10, text: "A", version: 1), cell: MessageTableCell.self) { _, _, _ in }
                    .onDeselect { message, _ in deselectedMessageID = message.id }
                TableRow(model: Message(id: 11, text: "B", version: 1), cell: MessageTableCell.self) { _, _, _ in }
            }
            .selectionMode(.single)
            TableSection(2) {
                TableRow(model: Message(id: 20, text: "C", version: 1), cell: MessageTableCell.self) { _, _, _ in }
            }
            .selectionMode(.multiple)
        }

        let disabled = IndexPath(row: 0, section: 0)
        let firstSingle = IndexPath(row: 0, section: 1)
        let secondSingle = IndexPath(row: 1, section: 1)
        let multiple = IndexPath(row: 0, section: 2)

        XCTAssertTrue(tableView.allowsSelection)
        XCTAssertTrue(tableView.allowsMultipleSelection)
        XCTAssertNil(adapter.tableView(tableView, willSelectRowAt: disabled))
        XCTAssertEqual(adapter.tableView(tableView, willSelectRowAt: firstSingle), firstSingle)
        XCTAssertEqual(adapter.tableView(tableView, willSelectRowAt: multiple), multiple)

        tableView.selectRow(at: firstSingle, animated: false, scrollPosition: .none)
        tableView.selectRow(at: secondSingle, animated: false, scrollPosition: .none)
        adapter.tableView(tableView, didSelectRowAt: secondSingle)

        XCTAssertFalse(tableView.indexPathsForSelectedRows?.contains(firstSingle) ?? false)
        XCTAssertTrue(tableView.indexPathsForSelectedRows?.contains(secondSingle) ?? false)
        XCTAssertEqual(deselectedMessageID, 10)
    }

    func testTableDataSourceForwardsEditingAndMoveCallbacks() {
        let tableView = UITableView(frame: .zero, style: .plain)
        let adapter = TableListAdapter<Section>(tableView: tableView)
        var committedDeleteID: Int?
        var moved: (source: Int, destination: Int)?

        adapter.apply(transaction: .disabled) {
            TableSection(.messages) {
                TableRow(
                    model: Message(id: 1, text: "A", version: 1),
                    cell: MessageTableCell.self
                ) { _, _, _ in }
                .editing(.delete) { message, _, _ in
                    committedDeleteID = message.id
                }
                .onMove { _, source, destination in
                    moved = (source.row, destination.row)
                }
            }
        }

        let indexPath = IndexPath(row: 0, section: 0)
        let dataSource = tableView.dataSource

        XCTAssertTrue(dataSource?.tableView?(tableView, canEditRowAt: indexPath) ?? false)
        XCTAssertTrue(dataSource?.tableView?(tableView, canMoveRowAt: indexPath) ?? false)

        dataSource?.tableView?(tableView, commit: .delete, forRowAt: indexPath)
        dataSource?.tableView?(tableView, moveRowAt: indexPath, to: IndexPath(row: 1, section: 0))

        XCTAssertEqual(committedDeleteID, 1)
        XCTAssertEqual(moved?.source, 0)
        XCTAssertEqual(moved?.destination, 1)
    }

    func testTableAdapterProvidesHeaderFooterViewsAndDisplayHandlers() {
        let tableView = UITableView(frame: .zero, style: .plain)
        let adapter = TableListAdapter<Section>(tableView: tableView)
        var displayedHeader = false
        var endedFooter = false

        let applyCompleted = expectation(description: "table supplementary lifecycle apply")
        adapter.apply(transaction: .disabled, completion: { _ in
            applyCompleted.fulfill()
        }) {
            TableSection(.messages) {
                TableRow(
                    model: Message(id: 1, text: "A", version: 1),
                    cell: MessageTableCell.self
                ) { _, _, _ in }
            } header: {
                TableHeader(MessageHeaderView.self, id: "header") { view, _ in
                    view.title = "Header"
                }
                .height(.fixed(30))
                .onDisplay { _, _ in
                    displayedHeader = true
                }
            } footer: {
                TableFooter(MessageHeaderView.self, id: "footer") { view, _ in
                    view.title = "Footer"
                }
                .height(.estimated(18))
                .onEndDisplay { _, _ in
                    endedFooter = true
                }
            }
        }
        wait(for: [applyCompleted], timeout: 1)

        let header = adapter.tableView(tableView, viewForHeaderInSection: 0) as? MessageHeaderView
        let footer = adapter.tableView(tableView, viewForFooterInSection: 0) as? MessageHeaderView
        adapter.tableView(tableView, willDisplayHeaderView: MessageHeaderView(), forSection: 0)
        adapter.tableView(tableView, didEndDisplayingFooterView: MessageHeaderView(), forSection: 0)

        XCTAssertEqual(header?.title, "Header")
        XCTAssertEqual(footer?.title, "Footer")
        XCTAssertEqual(adapter.tableView(tableView, heightForHeaderInSection: 0), 30)
        XCTAssertEqual(adapter.tableView(tableView, estimatedHeightForFooterInSection: 0), 18)
        XCTAssertTrue(displayedHeader)
        XCTAssertTrue(endedFooter)
    }

    func testTableReusableNamespaceRegistersAndDequeuesTypedViews() {
        let tableView = UITableView(frame: .zero, style: .plain)

        tableView.lk.register(MessageTableCell.self)
        tableView.lk.registerHeaderFooter(MessageHeaderView.self)

        let cell: MessageTableCell = tableView.lk.dequeue(MessageTableCell.self, for: IndexPath(row: 0, section: 0))
        let header: MessageHeaderView = tableView.lk.dequeueHeaderFooter(MessageHeaderView.self)

        XCTAssertTrue(type(of: cell) == MessageTableCell.self)
        XCTAssertTrue(type(of: header) == MessageHeaderView.self)
    }

    func testTableAdapterVisibleRefreshAPIsTargetMatchingRows() {
        let tableView = UITableView(frame: CGRect(x: 0, y: 0, width: 320, height: 240), style: .plain)
        let adapter = TableListAdapter<Section>(tableView: tableView)
        var configuredText = "A"

        adapter.apply(transaction: .disabled) {
            TableSection(.messages) {
                TableRow(1, model: configuredText, cell: MessageTableCell.self) { cell, text, _ in
                    cell.textValue = text
                }
                TableRow(2, model: "B", cell: MessageTableCell.self) { cell, text, _ in
                    cell.textValue = text
                }
            }
        }
        tableView.reloadData()
        tableView.layoutIfNeeded()

        configuredText = "A2"

        XCTAssertEqual(adapter.reconfigureVisibleRows(forRowID: 1, in: .messages), 1)
        XCTAssertEqual(adapter.reloadVisibleRows(forRowID: 1, in: .messages), 1)
        XCTAssertEqual(adapter.reconfigureVisibleRows(forRowID: 999, in: .messages), 0)
        XCTAssertEqual(adapter.reloadVisibleRows(forRowID: 999, in: .messages), 0)
        XCTAssertTrue(adapter.scrollToLastRow(in: .messages, animated: false))
        XCTAssertFalse(adapter.scrollToLastRow(in: .empty, animated: false))
    }

    func testTableHeaderFooterRefreshIDUpdatesSummaryAndVisibleViews() {
        let tableView = UITableView(frame: CGRect(x: 0, y: 0, width: 320, height: 260), style: .plain)
        let adapter = TableListAdapter<Section>(tableView: tableView)
        var headerTitle = "Header 1"
        var footerTitle = "Footer 1"

        func apply(version: Int) -> TableApplyResult<Section> {
            let applyCompleted = expectation(description: "table supplementary apply \(version)")
            let result = adapter.apply(transaction: .disabled, completion: { _ in
                applyCompleted.fulfill()
            }) {
                TableSection(.messages) {
                    TableRow(1, model: "Row", cell: MessageTableCell.self) { cell, text, _ in
                        cell.textValue = text
                    }
                    .height(.fixed(44))
                } header: {
                    TableHeader(MessageHeaderView.self, id: "header") { view, _ in
                        view.title = headerTitle
                    }
                    .height(.fixed(40))
                    .refreshID(version)
                    .refreshPolicy(.whenRefreshIDChanges)
                } footer: {
                    TableFooter(MessageHeaderView.self, id: "footer") { view, _ in
                        view.title = footerTitle
                    }
                    .height(.fixed(40))
                    .refreshID(version)
                    .refreshPolicy(.whenRefreshIDChanges)
                }
            }
            wait(for: [applyCompleted], timeout: 1)
            return result
        }

        _ = apply(version: 1)
        tableView.reloadData()
        tableView.layoutIfNeeded()
        XCTAssertEqual((tableView.headerView(forSection: 0) as? MessageHeaderView)?.title, "Header 1")
        XCTAssertEqual((tableView.footerView(forSection: 0) as? MessageHeaderView)?.title, "Footer 1")

        headerTitle = "Header 2"
        footerTitle = "Footer 2"
        let result = apply(version: 2)
        tableView.layoutIfNeeded()

        XCTAssertEqual(result.summary.supplementaryRefreshIDChangedCount, 2)
        XCTAssertEqual(adapter.lastApplySummary.visibleSupplementaryRefreshCount, 2)
        XCTAssertEqual((tableView.headerView(forSection: 0) as? MessageHeaderView)?.title, "Header 2")
        XCTAssertEqual((tableView.footerView(forSection: 0) as? MessageHeaderView)?.title, "Footer 2")
    }
}

private enum Section: Hashable, Sendable {
    case messages
    case empty
}

private struct Message: Identifiable, Hashable, Sendable {
    let id: Int
    let text: String
    let version: Int
}

private enum MessageEvent: ListEvent, Equatable {
    case configure(messageID: Int)
}

private final class MessageTableCell: UITableViewCell {
    var textValue: String?
}

private final class MessageHeaderView: UITableViewHeaderFooterView {
    var title: String?
}

private final class TableDelegateSpy: NSObject, UITableViewDelegate {
    var didEndDisplayingCount = 0

    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        didEndDisplayingCount += 1
    }
}
