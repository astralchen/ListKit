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
        XCTAssertEqual(sections[0].selectionMode, .automatic)
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

        adapter.onEvent(MessageEvent.self) { event, _ in
            receivedEvent = event
        }
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
        let indexPath = IndexPath(row: 0, section: 0)
        _ = adapter.tableView(tableView, cellForRowAt: indexPath)
        adapter.tableView(tableView, didSelectRowAt: indexPath)

        XCTAssertTrue(tableView.allowsSelection)
        XCTAssertFalse(tableView.allowsMultipleSelection)
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

        _ = await adapter.apply(transaction: .disabled) {
            TableSection(.messages) {
                TableRow(1, model: "Anchor", cell: MessageTableCell.self) { _, _, _ in }
                    .height(.fixed(44))
            }
        }
        tableView.layoutIfNeeded()

        let result = await adapter.apply(
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

        XCTAssertEqual(result.animation.anchorCompensation, 0)
        XCTAssertEqual(tableView.contentInset.bottom, 0)
    }

    func testCoalesceLatestSupersedesTableApplyDuringContentTransition() async throws {
        let tableView = UITableView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            style: .plain
        )
        let adapter = TableListAdapter<Section>(tableView: tableView)
        let host = UIViewController()
        host.view.frame = tableView.bounds
        host.view.addSubview(tableView)
        let window = UIWindow(frame: tableView.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        _ = await adapter.apply(
            options: .init(transaction: .disabled, applicationMode: .reloadData)
        ) {
            TableSection(.messages) {
                TableRow(1, model: "A", cell: MessageTableCell.self) { cell, value, _ in
                    cell.textValue = value
                }
                .height(.fixed(60))
                .refreshID(1)
                .refreshPolicy(.automaticVisible)
            }
            TableSection(.empty) {
                TableRow(2, model: "Side", cell: MessageTableCell.self) { _, _, _ in }
            }
        }
        tableView.layoutIfNeeded()
        _ = try XCTUnwrap(tableView.cellForRow(at: IndexPath(row: 0, section: 0)))

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(true)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        let transitionStarted = expectation(description: "first table content transition started")
        var didSignalTransition = false
        let firstApply = Task { @MainActor in
            await adapter.apply(
                transaction: ListTransaction(animation: .disabled).contentAnimation(.enabled)
            ) {
                TableSection(.messages) {
                    TableRow(1, model: "B", cell: MessageTableCell.self) { cell, value, _ in
                        cell.textValue = value
                        if !didSignalTransition {
                            didSignalTransition = true
                            transitionStarted.fulfill()
                        }
                    }
                    .height(.fixed(60))
                    .refreshID(2)
                    .refreshPolicy(.automaticVisible)
                    .contentTransition(.opacity(duration: 0.35))
                }
            }
        }

        await fulfillment(of: [transitionStarted], timeout: 2)
        let latestResult = await adapter.apply(transaction: .disabled) {
            TableSection(.messages) {
                TableRow(1, model: "C", cell: MessageTableCell.self) { cell, value, _ in
                    cell.textValue = value
                }
                .height(.fixed(60))
                .refreshID(3)
                .refreshPolicy(.automaticVisible)
            }
            TableSection(.empty) {
                TableRow(2, model: "Side", cell: MessageTableCell.self) { _, _, _ in }
            }
        }
        let supersededResult = await firstApply.value

        XCTAssertEqual(supersededResult.animation.completionState, .superseded)
        XCTAssertEqual(latestResult.animation.completionState, .completed)
        XCTAssertEqual(latestResult.insertedSectionCount, 1)
        XCTAssertEqual(tableView.numberOfSections, 2)
        XCTAssertEqual(adapter.sectionIdentifier(at: 1), .empty)
        XCTAssertEqual(adapter.lastApplySummary, latestResult)
    }

    func testSerialTableApplyCompletesSectionDeletionBeforeReinsertion() async throws {
        let tableView = UITableView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            style: .plain
        )
        let adapter = TableListAdapter<Section>(tableView: tableView)
        let host = UIViewController()
        host.view.frame = tableView.bounds
        host.view.addSubview(tableView)
        let window = UIWindow(frame: tableView.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        _ = await adapter.apply(
            options: .init(transaction: .disabled, applicationMode: .reloadData)
        ) {
            TableSection(.messages) {
                TableRow(1, model: "A", cell: MessageTableCell.self) { cell, value, _ in
                    cell.textValue = value
                }
                .height(.fixed(60))
                .refreshID(1)
                .refreshPolicy(.automaticVisible)
            }
            TableSection(.empty) {
                TableRow(2, model: "Side", cell: MessageTableCell.self) { _, _, _ in }
            }
        }
        tableView.layoutIfNeeded()
        _ = try XCTUnwrap(tableView.cellForRow(at: IndexPath(row: 0, section: 0)))

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(true)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        let transitionStarted = expectation(description: "serial table transition started")
        var didSignalTransition = false
        let serialTransaction = ListTransaction(animation: .disabled)
            .contentAnimation(.enabled)
            .updatePolicy(.serial)
        let deletionApply = Task { @MainActor in
            await adapter.apply(transaction: serialTransaction) {
                TableSection(.messages) {
                    TableRow(1, model: "B", cell: MessageTableCell.self) { cell, value, _ in
                        cell.textValue = value
                        if !didSignalTransition {
                            didSignalTransition = true
                            transitionStarted.fulfill()
                        }
                    }
                    .height(.fixed(60))
                    .refreshID(2)
                    .refreshPolicy(.automaticVisible)
                    .contentTransition(.opacity(duration: 0.35))
                }
            }
        }

        await fulfillment(of: [transitionStarted], timeout: 2)
        let reinsertionApply = Task { @MainActor in
            await adapter.apply(
                transaction: ListTransaction.disabled.updatePolicy(.serial)
            ) {
                TableSection(.messages) {
                    TableRow(1, model: "C", cell: MessageTableCell.self) { cell, value, _ in
                        cell.textValue = value
                    }
                    .height(.fixed(60))
                    .refreshID(3)
                    .refreshPolicy(.automaticVisible)
                }
                TableSection(.empty) {
                    TableRow(2, model: "Side", cell: MessageTableCell.self) { _, _, _ in }
                }
            }
        }

        let deletionResult = await deletionApply.value
        let reinsertionResult = await reinsertionApply.value

        XCTAssertEqual(deletionResult.animation.completionState, .completed)
        XCTAssertEqual(deletionResult.deletedSectionCount, 1)
        XCTAssertEqual(reinsertionResult.animation.completionState, .completed)
        XCTAssertEqual(reinsertionResult.insertedSectionCount, 1)
        XCTAssertEqual(tableView.numberOfSections, 2)
        XCTAssertEqual(adapter.sectionIdentifier(at: 1), .empty)
    }

    func testVisibleOnlyRefreshesTableRowWhenRefreshIDChanges() async throws {
        let tableView = UITableView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            style: .plain
        )
        let adapter = TableListAdapter<Section>(tableView: tableView)
        let host = UIViewController()
        host.view.frame = tableView.bounds
        host.view.addSubview(tableView)
        let window = UIWindow(frame: tableView.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        _ = await adapter.apply(
            options: .init(transaction: .disabled, applicationMode: .reloadData)
        ) {
            TableSection(.messages) {
                TableRow(1, model: "A", cell: MessageTableCell.self) { cell, value, _ in
                    cell.textValue = value
                }
                .height(.fixed(60))
                .refreshID(1)
                .refreshPolicy(.whenRefreshIDChanges)
            }
        }
        tableView.layoutIfNeeded()
        let cell = try XCTUnwrap(
            tableView.cellForRow(at: IndexPath(row: 0, section: 0)) as? MessageTableCell
        )

        let result = await adapter.apply(
            options: .init(transaction: .disabled, refreshStrategy: .visibleOnly)
        ) {
            TableSection(.messages) {
                TableRow(1, model: "B", cell: MessageTableCell.self) { cell, value, _ in
                    cell.textValue = value
                }
                .height(.fixed(60))
                .refreshID(2)
                .refreshPolicy(.whenRefreshIDChanges)
            }
        }

        XCTAssertEqual(result.refreshIDChangedCount, 1)
        XCTAssertEqual(result.snapshotRefreshCount, 0)
        XCTAssertEqual(result.visibleRefreshCount, 1)
        XCTAssertEqual(cell.textValue, "B")
    }

    func testTableApplyDeletesEntireSectionAndClearsIdentityHistory() async throws {
        let tableView = UITableView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            style: .plain
        )
        let adapter = TableListAdapter<Section>(tableView: tableView)

        _ = await adapter.apply(
            options: .init(transaction: .disabled, applicationMode: .reloadData)
        ) {
            TableSection(.messages) {
                TableRow(1, model: "Kept", cell: MessageTableCell.self) { _, _, _ in }
                    .refreshID(1)
                    .refreshPolicy(.whenRefreshIDChanges)
            }
            TableSection(.empty) {
                TableRow(2, model: "Removed", cell: MessageTableCell.self) { _, _, _ in }
                    .refreshID(1)
                    .refreshPolicy(.whenRefreshIDChanges)
            }
        }
        let removedIdentity = try XCTUnwrap(
            adapter.itemIdentity(at: IndexPath(row: 0, section: 1))
        )

        let deletionResult = await adapter.apply(transaction: .disabled) {
            TableSection(.messages) {
                TableRow(1, model: "Kept", cell: MessageTableCell.self) { _, _, _ in }
                    .refreshID(1)
                    .refreshPolicy(.whenRefreshIDChanges)
            }
        }

        XCTAssertEqual(deletionResult.animation.completionState, .completed)
        XCTAssertEqual(deletionResult.deletedSectionCount, 1)
        XCTAssertEqual(deletionResult.keptSectionCount, 1)
        XCTAssertEqual(deletionResult.deletedRowCount, 1)
        XCTAssertEqual(deletionResult.keptRowCount, 1)
        XCTAssertEqual(deletionResult.refreshIDChangedCount, 0)
        XCTAssertEqual(tableView.numberOfSections, 1)
        XCTAssertEqual(adapter.sectionIdentifier(at: 0), .messages)
        XCTAssertNil(adapter.sectionIdentifier(at: 1))
        XCTAssertNil(adapter.sectionIndex(for: .empty))
        XCTAssertEqual(adapter.rowCount(in: .empty), 0)
        XCTAssertTrue(adapter.indexPaths(forRowID: 2, in: .empty).isEmpty)
        XCTAssertFalse(adapter.contains(removedIdentity))

        let reinsertionResult = await adapter.apply(transaction: .disabled) {
            TableSection(.messages) {
                TableRow(1, model: "Kept", cell: MessageTableCell.self) { _, _, _ in }
                    .refreshID(1)
                    .refreshPolicy(.whenRefreshIDChanges)
            }
            TableSection(.empty) {
                TableRow(2, model: "Reinserted", cell: MessageTableCell.self) { _, _, _ in }
                    .refreshID(2)
                    .refreshPolicy(.whenRefreshIDChanges)
            }
        }

        XCTAssertEqual(reinsertionResult.animation.completionState, .completed)
        XCTAssertEqual(reinsertionResult.insertedSectionCount, 1)
        XCTAssertEqual(reinsertionResult.keptSectionCount, 1)
        XCTAssertEqual(reinsertionResult.insertedRowCount, 1)
        XCTAssertEqual(reinsertionResult.refreshIDChangedCount, 0)
        XCTAssertEqual(tableView.numberOfSections, 2)
        XCTAssertEqual(adapter.sectionIndex(for: .empty), 1)
        XCTAssertEqual(
            adapter.indexPaths(forRowID: 2, in: .empty),
            [IndexPath(row: 0, section: 1)]
        )
    }

    func testTableEmptySectionChangesDriveSnapshotAnimationSummary() async {
        let tableView = UITableView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            style: .plain
        )
        let adapter = TableListAdapter<Int>(tableView: tableView)

        _ = await adapter.apply(
            options: .init(transaction: .disabled, applicationMode: .reloadData)
        ) {
            TableSection(0) {}
            TableSection(1) {}
        }

        let reorderResult = await adapter.apply(
            transaction: ListTransaction(animation: .enabled)
        ) {
            TableSection(1) {}
            TableSection(0) {}
        }

        XCTAssertEqual(reorderResult.movedSectionCount, 1)
        XCTAssertEqual(reorderResult.movedRowCount, 0)
        XCTAssertTrue(reorderResult.animation.snapshotAnimated)
        XCTAssertEqual(reorderResult.animation.animatedSectionCount, 1)
        XCTAssertEqual(adapter.sectionIdentifier(at: 0), 1)
        XCTAssertEqual(adapter.sectionIdentifier(at: 1), 0)

        let deleteLeadingResult = await adapter.apply(
            transaction: ListTransaction(animation: .enabled)
        ) {
            TableSection(0) {}
        }

        XCTAssertEqual(deleteLeadingResult.deletedSectionCount, 1)
        XCTAssertEqual(deleteLeadingResult.deletedRowCount, 0)
        XCTAssertTrue(deleteLeadingResult.animation.snapshotAnimated)
        XCTAssertEqual(deleteLeadingResult.animation.animatedSectionCount, 1)
        XCTAssertEqual(tableView.numberOfSections, 1)
        XCTAssertEqual(adapter.sectionIdentifier(at: 0), 0)

        let noSections: [TableSection<Int>] = []
        let deleteAllResult = await adapter.apply(
            options: .init(
                transaction: ListTransaction(animation: .enabled),
                applicationMode: .reloadData
            )
        ) {
            noSections
        }

        XCTAssertEqual(deleteAllResult.deletedSectionCount, 1)
        XCTAssertEqual(deleteAllResult.deletedRowCount, 0)
        XCTAssertFalse(deleteAllResult.animation.snapshotAnimated)
        XCTAssertEqual(deleteAllResult.animation.animatedSectionCount, 0)
        XCTAssertEqual(tableView.numberOfSections, 0)
    }

    func testTableDeletesLeadingAndMiddleSectionsTogether() async {
        let tableView = UITableView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            style: .plain
        )
        let adapter = TableListAdapter<Int>(tableView: tableView)

        _ = await adapter.apply(
            options: .init(transaction: .disabled, applicationMode: .reloadData)
        ) {
            TableSection(0) {
                TableRow("zero", model: "Zero", cell: MessageTableCell.self) { _, _, _ in }
            }
            TableSection(1) {
                TableRow("one", model: "One", cell: MessageTableCell.self) { _, _, _ in }
            }
            TableSection(2) {
                TableRow("two", model: "Two", cell: MessageTableCell.self) { _, _, _ in }
            }
        }

        let result = await adapter.apply(transaction: .disabled) {
            TableSection(2) {
                TableRow("two", model: "Two", cell: MessageTableCell.self) { _, _, _ in }
            }
        }

        XCTAssertEqual(result.deletedSectionCount, 2)
        XCTAssertEqual(result.keptSectionCount, 1)
        XCTAssertEqual(result.deletedRowCount, 2)
        XCTAssertEqual(result.keptRowCount, 1)
        XCTAssertEqual(tableView.numberOfSections, 1)
        XCTAssertEqual(adapter.sectionIdentifier(at: 0), 2)
        XCTAssertEqual(adapter.indexPaths(forRowID: "two", in: 2), [IndexPath(row: 0, section: 0)])
        XCTAssertTrue(adapter.indexPaths(forRowID: "zero").isEmpty)
        XCTAssertTrue(adapter.indexPaths(forRowID: "one").isEmpty)
    }

    func testTablePreservesSelectionAndFocusIdentityWhenLeadingSectionIsDeleted() async throws {
        let tableView = UITableView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            style: .plain
        )
        let adapter = TableListAdapter<Int>(tableView: tableView)
        let host = UIViewController()
        host.view.frame = tableView.bounds
        host.view.addSubview(tableView)
        let window = UIWindow(frame: tableView.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        _ = await adapter.apply(
            options: .init(transaction: .disabled, applicationMode: .reloadData)
        ) {
            TableSection(0) {
                TableRow("removed", model: "Removed", cell: MessageTableCell.self) { _, _, _ in }
            }
            .selectionMode(.single)
            TableSection(1) {
                TableRow("selected", model: "Selected", cell: MessageTableCell.self) { _, _, _ in }
                    .focusable()
            }
            .selectionMode(.single)
        }
        tableView.layoutIfNeeded()
        tableView.selectRow(at: IndexPath(row: 0, section: 1), animated: false, scrollPosition: .none)
        let selectedIdentity = try XCTUnwrap(adapter.itemIdentity(at: IndexPath(row: 0, section: 1)))

        _ = await adapter.apply(transaction: .disabled) {
            TableSection(1) {
                TableRow("selected", model: "Selected", cell: MessageTableCell.self) { _, _, _ in }
                    .focusable()
            }
            .selectionMode(.single)
        }

        let shiftedIndexPath = try XCTUnwrap(tableView.indexPathsForSelectedRows?.first)
        XCTAssertEqual(shiftedIndexPath, IndexPath(row: 0, section: 0))
        XCTAssertEqual(adapter.itemIdentity(at: shiftedIndexPath), selectedIdentity)
        XCTAssertTrue(adapter.tableView(tableView, canFocusRowAt: shiftedIndexPath))

        let noSections: [TableSection<Int>] = []
        _ = await adapter.apply(transaction: .disabled) {
            noSections
        }

        XCTAssertTrue(tableView.indexPathsForSelectedRows?.isEmpty ?? true)
        XCTAssertFalse(tableView.allowsSelection)
    }

    func testTableSectionDeletionPreservesOrReleasesVisibleAnchor() async throws {
        let tableView = UITableView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 220),
            style: .plain
        )
        let adapter = TableListAdapter<Int>(tableView: tableView)
        let host = UIViewController()
        host.view.frame = tableView.bounds
        host.view.addSubview(tableView)
        let window = UIWindow(frame: tableView.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        func section(_ id: Int, rows: Range<Int>) -> TableSection<Int> {
            TableSection(id) {
                TableForEach(rows, id: \.self) { row in
                    TableRow("\(id)-\(row)", model: row, cell: MessageTableCell.self) { _, _, _ in }
                        .height(.fixed(44))
                }
            }
        }

        _ = await adapter.apply(
            options: .init(transaction: .disabled, applicationMode: .reloadData)
        ) {
            section(0, rows: 0..<3)
            section(1, rows: 0..<6)
            TableSection(2) {
                TableRow("anchor", model: 0, cell: MessageTableCell.self) { _, _, _ in }
                    .height(.fixed(44))
                TableForEach(1..<6, id: \.self) { row in
                    TableRow("anchor-trailing-\(row)", model: row, cell: MessageTableCell.self) { _, _, _ in }
                        .height(.fixed(44))
                }
            }
        }
        tableView.layoutIfNeeded()
        let initialAnchorPath = try XCTUnwrap(adapter.indexPaths(forRowID: "anchor", in: 2).first)
        let initialRect = tableView.rectForRow(at: initialAnchorPath)
        tableView.setContentOffset(CGPoint(x: 0, y: initialRect.minY - 80), animated: false)
        tableView.layoutIfNeeded()
        let initialViewportY = initialRect.minY - tableView.contentOffset.y

        let preserveResult = await adapter.apply(
            transaction: ListTransaction.disabled.scrollBehavior(
                .preserveVisiblePosition(of: ListScrollTarget("anchor", in: 2))
            )
        ) {
            section(1, rows: 0..<6)
            TableSection(2) {
                TableRow("anchor", model: 0, cell: MessageTableCell.self) { _, _, _ in }
                    .height(.fixed(44))
                TableForEach(1..<6, id: \.self) { row in
                    TableRow("anchor-trailing-\(row)", model: row, cell: MessageTableCell.self) { _, _, _ in }
                        .height(.fixed(44))
                }
            }
        }
        tableView.layoutIfNeeded()
        let shiftedAnchorPath = try XCTUnwrap(adapter.indexPaths(forRowID: "anchor", in: 2).first)
        let shiftedRect = tableView.rectForRow(at: shiftedAnchorPath)

        XCTAssertEqual(shiftedRect.minY - tableView.contentOffset.y, initialViewportY, accuracy: 0.5)
        XCTAssertEqual(preserveResult.animation.anchorCompensation, 0, accuracy: 0.5)
        XCTAssertEqual(tableView.contentInset.bottom, 0, accuracy: 0.5)

        let removeAnchorResult = await adapter.apply(
            transaction: ListTransaction.disabled.scrollBehavior(
                .preserveVisiblePosition(of: ListScrollTarget("anchor", in: 2))
            )
        ) {
            section(1, rows: 0..<6)
        }

        XCTAssertEqual(removeAnchorResult.deletedSectionCount, 1)
        XCTAssertEqual(removeAnchorResult.animation.anchorCompensation, 0, accuracy: 0.5)
        XCTAssertEqual(tableView.contentInset.bottom, 0, accuracy: 0.5)
        XCTAssertTrue(adapter.indexPaths(forRowID: "anchor", in: 2).isEmpty)
    }

    func testTableDeletesAndReinsertsSectionWithHeaderFooter() async {
        let tableView = UITableView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 260),
            style: .plain
        )
        let adapter = TableListAdapter<Section>(tableView: tableView)

        func decoratedSection(version: Int) -> TableSection<Section> {
            TableSection(.empty) {
                TableRow(2, model: "Decorated", cell: MessageTableCell.self) { _, _, _ in }
                    .height(.fixed(44))
            } header: {
                TableHeader(MessageHeaderView.self, id: "header") { view, _ in
                    view.title = "Header \(version)"
                }
                .height(.fixed(32))
                .refreshID(version)
                .refreshPolicy(.whenRefreshIDChanges)
            } footer: {
                TableFooter(MessageHeaderView.self, id: "footer") { view, _ in
                    view.title = "Footer \(version)"
                }
                .height(.fixed(28))
                .refreshID(version)
                .refreshPolicy(.whenRefreshIDChanges)
            }
        }

        _ = await adapter.apply(
            options: .init(transaction: .disabled, applicationMode: .reloadData)
        ) {
            TableSection(.messages) {
                TableRow(1, model: "Stable", cell: MessageTableCell.self) { _, _, _ in }
            }
            decoratedSection(version: 1)
        }

        let deleteResult = await adapter.apply(transaction: .disabled) {
            TableSection(.messages) {
                TableRow(1, model: "Stable", cell: MessageTableCell.self) { _, _, _ in }
            }
        }

        XCTAssertEqual(deleteResult.deletedSectionCount, 1)
        XCTAssertEqual(deleteResult.deletedRowCount, 1)
        XCTAssertEqual(tableView.numberOfSections, 1)

        let reinsertResult = await adapter.apply(transaction: .disabled) {
            TableSection(.messages) {
                TableRow(1, model: "Stable", cell: MessageTableCell.self) { _, _, _ in }
            }
            decoratedSection(version: 2)
        }
        tableView.reloadData()
        tableView.layoutIfNeeded()

        XCTAssertEqual(reinsertResult.insertedSectionCount, 1)
        XCTAssertEqual(reinsertResult.insertedRowCount, 1)
        XCTAssertEqual(reinsertResult.supplementaryRefreshIDChangedCount, 0)
        XCTAssertEqual((tableView.headerView(forSection: 1) as? MessageHeaderView)?.title, "Header 2")
        XCTAssertEqual((tableView.footerView(forSection: 1) as? MessageHeaderView)?.title, "Footer 2")
    }

    func testTableAdapterDiagnosticsAndRefreshSummary() {
        let tableView = UITableView(frame: .zero, style: .plain)
        let adapter = TableListAdapter<Section>(tableView: tableView)
        let options = ListApplyOptions(
            transaction: .disabled,
            refreshStrategy: .refreshIDChangesOnly,
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

        XCTAssertEqual(refreshResult.insertedRowCount, 1)
        XCTAssertEqual(refreshResult.keptRowCount, 1)
        XCTAssertEqual(refreshResult.refreshIDChangedCount, 1)
        XCTAssertEqual(refreshResult.snapshotRefreshCount, 1)

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

        XCTAssertTrue(duplicateResult.diagnosticsIssues.contains { $0.kind == .duplicateRow })
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

    func testTableLifecycleUsesCapturedRowWhenDeletedSectionIndexPathIsReused() async {
        let tableView = UITableView(frame: .zero, style: .plain)
        let adapter = TableListAdapter<Int>(tableView: tableView)
        var endedRowID: String?
        var cancelledRowID: String?

        _ = await adapter.apply(transaction: .disabled) {
            TableSection(0) {
                TableRow("old", model: "Old", cell: MessageTableCell.self) { _, _, _ in }
                    .onEndDisplay { _, _, _ in endedRowID = "old" }
                    .onCancelPrefetch { _, _ in cancelledRowID = "old" }
            }
            TableSection(1) {
                TableRow("new", model: "New", cell: MessageTableCell.self) { _, _, _ in }
            }
        }

        let reusedIndexPath = IndexPath(row: 0, section: 0)
        let oldCell = MessageTableCell()
        adapter.tableView(tableView, willDisplay: oldCell, forRowAt: reusedIndexPath)
        adapter.tableView(tableView, prefetchRowsAt: [reusedIndexPath])

        _ = await adapter.apply(transaction: .disabled) {
            TableSection(1) {
                TableRow("new", model: "New", cell: MessageTableCell.self) { _, _, _ in }
            }
        }

        adapter.tableView(tableView, didEndDisplaying: oldCell, forRowAt: reusedIndexPath)
        adapter.tableView(tableView, cancelPrefetchingForRowsAt: [reusedIndexPath])

        XCTAssertEqual(endedRowID, "old")
        XCTAssertEqual(cancelledRowID, "old")
        XCTAssertEqual(adapter.rowIdentifier(at: reusedIndexPath, as: String.self), "new")
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
            .multipleSelectionInteraction()
            TableSection(2) {
                TableRow(model: Message(id: 20, text: "C", version: 1), cell: MessageTableCell.self) { _, _, _ in }
            }
            .selectionMode(.multiple)
            .multipleSelectionInteraction()
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
        XCTAssertFalse(
            adapter.tableView(
                tableView,
                shouldBeginMultipleSelectionInteractionAt: firstSingle
            )
        )
        XCTAssertTrue(
            adapter.tableView(
                tableView,
                shouldBeginMultipleSelectionInteractionAt: multiple
            )
        )

        tableView.selectRow(at: firstSingle, animated: false, scrollPosition: .none)
        tableView.selectRow(at: secondSingle, animated: false, scrollPosition: .none)
        adapter.tableView(tableView, didSelectRowAt: secondSingle)

        XCTAssertFalse(tableView.indexPathsForSelectedRows?.contains(firstSingle) ?? false)
        XCTAssertTrue(tableView.indexPathsForSelectedRows?.contains(secondSingle) ?? false)
        XCTAssertEqual(deselectedMessageID, 10)
    }

    func testTableAutomaticSelectionUsesRowIntent() async {
        let tableView = UITableView(frame: .zero, style: .plain)
        let adapter = TableListAdapter<Int>(tableView: tableView)

        _ = await adapter.apply(transaction: .disabled) {
            TableSection(0) {
                TableRow("static", model: "Static", cell: MessageTableCell.self) { _, _, _ in }
            }
        }

        XCTAssertFalse(tableView.allowsSelection)
        XCTAssertNil(adapter.tableView(tableView, willSelectRowAt: IndexPath(row: 0, section: 0)))

        _ = await adapter.apply(transaction: .disabled) {
            TableSection(0) {
                TableRow("static", model: "Static", cell: MessageTableCell.self) { _, _, _ in }
            }
            TableSection(1) {
                TableRow("plain", model: "Plain", cell: MessageTableCell.self) { _, _, _ in }
                TableRow("action", model: "Action", cell: MessageTableCell.self) { _, _, _ in }
                    .onSelect { _ in }
                TableRow("controlled", model: "Controlled", cell: MessageTableCell.self) { _, _, _ in }
                    .selected(false)
                TableRow("disabled", model: "Disabled", cell: MessageTableCell.self) { _, _, _ in }
                    .onSelect { _ in }
                    .selectionDisabled()
            }
            .multipleSelectionInteraction()
        }

        XCTAssertTrue(tableView.allowsSelection)
        XCTAssertFalse(tableView.allowsMultipleSelection)
        XCTAssertNil(adapter.tableView(tableView, willSelectRowAt: IndexPath(row: 0, section: 0)))
        XCTAssertNil(adapter.tableView(tableView, willSelectRowAt: IndexPath(row: 0, section: 1)))
        XCTAssertEqual(
            adapter.tableView(tableView, willSelectRowAt: IndexPath(row: 1, section: 1)),
            IndexPath(row: 1, section: 1)
        )
        XCTAssertEqual(
            adapter.tableView(tableView, willSelectRowAt: IndexPath(row: 2, section: 1)),
            IndexPath(row: 2, section: 1)
        )
        XCTAssertNil(adapter.tableView(tableView, willSelectRowAt: IndexPath(row: 3, section: 1)))
        XCTAssertFalse(
            adapter.tableView(
                tableView,
                shouldBeginMultipleSelectionInteractionAt: IndexPath(row: 1, section: 1)
            )
        )
    }

    func testTableControlledSelectionSynchronizesAcrossApply() async {
        let tableView = UITableView(frame: .zero, style: .plain)
        let adapter = TableListAdapter<Int>(tableView: tableView)
        let indexPath = IndexPath(row: 0, section: 0)

        _ = await adapter.apply(transaction: .disabled) {
            TableSection(0) {
                TableRow("controlled", model: "Controlled", cell: MessageTableCell.self) { _, _, _ in }
                    .selected(true)
            }
        }
        XCTAssertEqual(tableView.indexPathsForSelectedRows, [indexPath])

        _ = await adapter.apply(transaction: .disabled) {
            TableSection(0) {
                TableRow("controlled", model: "Controlled", cell: MessageTableCell.self) { _, _, _ in }
                    .selected(false)
            }
        }
        XCTAssertTrue(tableView.indexPathsForSelectedRows?.isEmpty ?? true)

        _ = await adapter.apply(transaction: .disabled) {
            TableSection(0) {
                TableRow("controlled", model: "Controlled", cell: MessageTableCell.self) { _, _, _ in }
                    .selected(true)
            }
        }
        XCTAssertEqual(tableView.indexPathsForSelectedRows, [indexPath])
    }

    func testTableHighlightIntentDoesNotEnableRowSelection() {
        let tableView = UITableView(frame: .zero, style: .plain)
        let adapter = TableListAdapter<Int>(tableView: tableView)
        let indexPath = IndexPath(row: 0, section: 0)
        var highlightChanges: [Bool] = []

        adapter.apply(transaction: .disabled) {
            TableSection(0) {
                TableRow("highlight", model: "Highlight", cell: MessageTableCell.self) { _, _, _ in }
                    .selectionDisabled()
                    .onHighlightChange { isHighlighted, _ in
                        highlightChanges.append(isHighlighted)
                    }
            }
        }

        XCTAssertTrue(tableView.allowsSelection)
        XCTAssertNil(adapter.tableView(tableView, willSelectRowAt: indexPath))
        XCTAssertTrue(adapter.tableView(tableView, shouldHighlightRowAt: indexPath))
        adapter.tableView(tableView, didHighlightRowAt: indexPath)
        adapter.tableView(tableView, didUnhighlightRowAt: indexPath)
        XCTAssertEqual(highlightChanges, [true, false])
    }

    func testTableAutomaticSelectionUsesExternalDelegateIntent() {
        let tableView = UITableView(frame: .zero, style: .plain)
        let adapter = TableListAdapter<Int>(tableView: tableView)
        let selectionDelegate = TableSelectionDelegateSpy()
        let indexPath = IndexPath(row: 0, section: 0)
        adapter.tableDelegate = selectionDelegate

        adapter.apply(transaction: .disabled) {
            TableSection(0) {
                TableRow("plain", model: "Plain", cell: MessageTableCell.self) { _, _, _ in }
            }
        }

        XCTAssertTrue(tableView.allowsSelection)
        XCTAssertEqual(adapter.tableView(tableView, willSelectRowAt: indexPath), indexPath)
        adapter.tableView(tableView, didSelectRowAt: indexPath)
        XCTAssertEqual(selectionDelegate.selectedIndexPath, indexPath)
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

    func testReloadAllBypassesNeverPolicyAndCompletesAfterLayoutInvalidation() throws {
        let tableView = UITableView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 260),
            style: .plain
        )
        let adapter = TableListAdapter<Section>(tableView: tableView)
        var rowText = "Row 1"
        var headerTitle = "Header 1"
        var footerTitle = "Footer 1"

        let initialApplyCompleted = expectation(description: "initial table apply completed")
        adapter.apply(transaction: .disabled, completion: { _ in
            initialApplyCompleted.fulfill()
        }) {
            TableSection(.messages) {
                TableRow(1, model: (), cell: MessageTableCell.self) { cell, _, _ in
                    cell.textValue = rowText
                }
                .height(.fixed(44))
                .refreshID("stable-row")
                .refreshPolicy(.never)
            } header: {
                TableHeader(MessageHeaderView.self, id: "header") { view, _ in
                    view.title = headerTitle
                }
                .height(.fixed(40))
                .refreshID("stable-header")
                .refreshPolicy(.never)
            } footer: {
                TableFooter(MessageHeaderView.self, id: "footer") { view, _ in
                    view.title = footerTitle
                }
                .height(.fixed(40))
                .refreshID("stable-footer")
                .refreshPolicy(.never)
            }
        }
        wait(for: [initialApplyCompleted], timeout: 1)
        tableView.reloadData()
        tableView.layoutIfNeeded()

        let indexPath = IndexPath(row: 0, section: 0)
        let originalIdentity = try XCTUnwrap(adapter.itemIdentity(at: indexPath))
        XCTAssertEqual((tableView.cellForRow(at: indexPath) as? MessageTableCell)?.textValue, "Row 1")
        XCTAssertEqual((tableView.headerView(forSection: 0) as? MessageHeaderView)?.title, "Header 1")
        XCTAssertEqual((tableView.footerView(forSection: 0) as? MessageHeaderView)?.title, "Footer 1")

        rowText = "Row 2"
        headerTitle = "Header 2"
        footerTitle = "Footer 2"

        let reloadCompleted = expectation(description: "table reload all completed")
        var completedSummary: ListApplySummary?
        adapter.reloadAll(
            transaction: .disabled,
            transition: .identity
        ) { summary in
            completedSummary = summary
            reloadCompleted.fulfill()
        }
        wait(for: [reloadCompleted], timeout: 1)
        tableView.layoutIfNeeded()

        XCTAssertEqual(adapter.itemIdentity(at: indexPath), originalIdentity)
        XCTAssertEqual((tableView.cellForRow(at: indexPath) as? MessageTableCell)?.textValue, "Row 2")
        XCTAssertEqual((tableView.headerView(forSection: 0) as? MessageHeaderView)?.title, "Header 2")
        XCTAssertEqual((tableView.footerView(forSection: 0) as? MessageHeaderView)?.title, "Footer 2")
        XCTAssertEqual(completedSummary?.animation.completionState, .completed)
        XCTAssertEqual(completedSummary?.animation.layoutInvalidated, true)
        XCTAssertEqual(completedSummary?.refreshIDChangedCount, 0)
        XCTAssertEqual(completedSummary?.supplementaryRefreshIDChangedCount, 0)
        XCTAssertEqual(completedSummary?.snapshotRefreshCount, 1)
        XCTAssertEqual(completedSummary?.visibleRefreshCount, 1)
        XCTAssertEqual(completedSummary?.visibleSupplementaryRefreshCount, 2)
        XCTAssertEqual(adapter.lastApplySummary, completedSummary)
    }

    func testTargetedRowRefreshAPIsIgnorePolicyDeduplicateAndComplete() throws {
        let tableView = UITableView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            style: .plain
        )
        let adapter = TableListAdapter<Section>(tableView: tableView)
        let host = UIViewController()
        host.view.frame = tableView.bounds
        host.view.addSubview(tableView)
        let window = UIWindow(frame: tableView.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        var rowTexts = [1: "A", 2: "B"]

        let initialApplyCompleted = expectation(description: "initial targeted row apply completed")
        adapter.apply(transaction: .disabled, completion: { _ in
            initialApplyCompleted.fulfill()
        }) {
            TableSection(.messages) {
                TableForEach([1, 2], id: \.self) { rowID in
                    TableRow(rowID, model: (), cell: MessageTableCell.self) { cell, _, _ in
                        cell.textValue = rowTexts[rowID]
                    }
                    .height(.fixed(44))
                    .refreshID("stable-\(rowID)")
                    .refreshPolicy(.never)
                }
            }
        }
        wait(for: [initialApplyCompleted], timeout: 1)
        tableView.reloadData()
        tableView.layoutIfNeeded()

        let firstIndexPath = IndexPath(row: 0, section: 0)
        let secondIndexPath = IndexPath(row: 1, section: 0)
        let firstCell = try XCTUnwrap(tableView.cellForRow(at: firstIndexPath) as? MessageTableCell)
        let secondCell = try XCTUnwrap(tableView.cellForRow(at: secondIndexPath) as? MessageTableCell)
        let baselinePrepareForReuseCount = firstCell.prepareForReuseCount
        XCTAssertEqual(firstCell.textValue, "A")
        XCTAssertEqual(secondCell.textValue, "B")

        rowTexts[1] = "A2"
        rowTexts[2] = "B2"

        let reconfigureCompleted = expectation(description: "targeted row reconfigure completed")
        let reconfigureSubmission = adapter.reconfigureRows(
            forRowIDs: [1, 1],
            in: .messages,
            transaction: .disabled,
            completion: { summary in
                XCTAssertEqual(summary.matchedTargetCount, 1)
                XCTAssertEqual(summary.visibleReconfiguredCount, 1)
                reconfigureCompleted.fulfill()
            }
        )
        XCTAssertEqual(reconfigureSubmission.requestedTargetCount, 1)
        XCTAssertEqual(reconfigureSubmission.completionState, .submitted)
        wait(for: [reconfigureCompleted], timeout: 1)

        let reconfiguredFirstCell = try XCTUnwrap(
            tableView.cellForRow(at: firstIndexPath) as? MessageTableCell
        )
        XCTAssertTrue(reconfiguredFirstCell === firstCell)
        XCTAssertEqual(reconfiguredFirstCell.prepareForReuseCount, baselinePrepareForReuseCount)
        XCTAssertEqual(reconfiguredFirstCell.textValue, "A2")
        XCTAssertEqual((tableView.cellForRow(at: secondIndexPath) as? MessageTableCell)?.textValue, "B")

        let reloadCompleted = expectation(description: "targeted row reload completed")
        let reloadSubmission = adapter.reloadRows(
            forRowID: 2,
            in: .messages,
            transaction: .disabled,
            completion: { summary in
                XCTAssertEqual(summary.reloadedTargetCount, 1)
                reloadCompleted.fulfill()
            }
        )
        XCTAssertEqual(reloadSubmission.completionState, .submitted)
        wait(for: [reloadCompleted], timeout: 1)

        let reloadedSecondCell = try XCTUnwrap(
            tableView.cellForRow(at: secondIndexPath) as? MessageTableCell
        )
        XCTAssertEqual(reloadedSecondCell.textValue, "B2")

        let emptyReloadCompleted = expectation(description: "empty reload completes next turn")
        let emptyReloadSummary = adapter.reloadRows(
            forRowIDs: [Int](),
            in: .messages,
            transaction: .disabled,
            completion: { summary in
                XCTAssertEqual(summary.completionState, .completed)
                emptyReloadCompleted.fulfill()
            }
        )
        XCTAssertEqual(emptyReloadSummary.requestedTargetCount, 0)
        XCTAssertEqual(emptyReloadSummary.completionState, .completed)
        wait(for: [emptyReloadCompleted], timeout: 1)
    }

    func testReloadSectionsRefreshesRequestedSectionAndReloadsIndexTitles() throws {
        let tableView = ReloadTrackingTableView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 360),
            style: .plain
        )
        let adapter = TableListAdapter<Section>(tableView: tableView)
        var messagesHeader = "Messages 1"
        var emptyHeader = "Empty 1"

        let initialApplyCompleted = expectation(description: "initial section apply completed")
        adapter.apply(transaction: .disabled, completion: { _ in
            initialApplyCompleted.fulfill()
        }) {
            TableSection(.messages) {
                TableRow(1, model: (), cell: MessageTableCell.self) { _, _, _ in }
                    .height(.fixed(44))
            } header: {
                TableHeader(MessageHeaderView.self, id: "messages-header") { view, _ in
                    view.title = messagesHeader
                }
                .height(.fixed(40))
                .refreshID("stable-messages-header")
                .refreshPolicy(.never)
            }
            .indexTitle("M")

            TableSection(.empty) {
                TableRow(2, model: (), cell: MessageTableCell.self) { _, _, _ in }
                    .height(.fixed(44))
            } header: {
                TableHeader(MessageHeaderView.self, id: "empty-header") { view, _ in
                    view.title = emptyHeader
                }
                .height(.fixed(40))
                .refreshID("stable-empty-header")
                .refreshPolicy(.never)
            }
            .indexTitle("E")
        }
        wait(for: [initialApplyCompleted], timeout: 1)
        tableView.reloadData()
        tableView.layoutIfNeeded()
        tableView.reloadSectionIndexTitlesCallCount = 0

        XCTAssertEqual((tableView.headerView(forSection: 0) as? MessageHeaderView)?.title, "Messages 1")
        XCTAssertEqual((tableView.headerView(forSection: 1) as? MessageHeaderView)?.title, "Empty 1")

        messagesHeader = "Messages 2"
        emptyHeader = "Empty 2"

        let reloadCompleted = expectation(description: "targeted section reload completed")
        let sectionReloadSubmission = adapter.reloadSections(
            [.messages, .messages],
            transaction: .disabled,
            completion: { summary in
                XCTAssertEqual(summary.matchedTargetCount, 1)
                XCTAssertEqual(summary.reloadedTargetCount, 1)
                reloadCompleted.fulfill()
            }
        )
        XCTAssertEqual(sectionReloadSubmission.requestedTargetCount, 1)
        XCTAssertEqual(sectionReloadSubmission.completionState, .submitted)
        wait(for: [reloadCompleted], timeout: 1)
        tableView.layoutIfNeeded()

        XCTAssertEqual((tableView.headerView(forSection: 0) as? MessageHeaderView)?.title, "Messages 2")
        XCTAssertEqual(tableView.reloadSectionIndexTitlesCallCount, 1)

        adapter.reloadSectionIndexTitles()
        XCTAssertEqual(tableView.reloadSectionIndexTitlesCallCount, 2)
    }

    func testTableAdapterScopedRefreshAPIsTargetMatchingRows() {
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

        let reconfigured = expectation(description: "visible row reconfigured")
        let reconfigureSubmission = adapter.reconfigureRows(
            forRowID: 1,
            in: .messages,
            scope: .visible,
            transaction: .disabled
        ) { summary in
            XCTAssertEqual(summary.matchedTargetCount, 1)
            XCTAssertEqual(summary.visibleReconfiguredCount, 1)
            XCTAssertEqual(summary.completionState, .completed)
            reconfigured.fulfill()
        }
        XCTAssertEqual(reconfigureSubmission.requestedTargetCount, 1)
        XCTAssertEqual(reconfigureSubmission.completionState, .submitted)
        wait(for: [reconfigured], timeout: 1)

        let reloaded = expectation(description: "visible row reloaded")
        _ = adapter.reloadRows(
            forRowID: 1,
            in: .messages,
            scope: .visible,
            transaction: .disabled
        ) { summary in
            XCTAssertEqual(summary.matchedTargetCount, 1)
            XCTAssertEqual(summary.reloadedTargetCount, 1)
            reloaded.fulfill()
        }
        wait(for: [reloaded], timeout: 1)

        XCTAssertEqual(
            adapter.reconfigureRows(forRowID: 999, in: .messages, scope: .visible).matchedTargetCount,
            0
        )
        XCTAssertEqual(
            adapter.reloadRows(forRowID: 999, in: .messages, scope: .visible).matchedTargetCount,
            0
        )
        XCTAssertTrue(adapter.scrollToLastRow(in: .messages, animated: false))
        XCTAssertFalse(adapter.scrollToLastRow(in: .empty, animated: false))
    }

    func testTableHeaderFooterRefreshIDUpdatesSummaryAndVisibleViews() {
        let tableView = UITableView(frame: CGRect(x: 0, y: 0, width: 320, height: 260), style: .plain)
        let adapter = TableListAdapter<Section>(tableView: tableView)
        var headerTitle = "Header 1"
        var footerTitle = "Footer 1"

        func apply(version: Int) -> ListApplySummary {
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

        XCTAssertEqual(result.supplementaryRefreshIDChangedCount, 2)
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
    var prepareForReuseCount = 0

    override func prepareForReuse() {
        prepareForReuseCount += 1
        super.prepareForReuse()
    }
}

private final class MessageHeaderView: UITableViewHeaderFooterView {
    var title: String?
}

private final class ReloadTrackingTableView: UITableView {
    var reloadSectionIndexTitlesCallCount = 0

    override func reloadSectionIndexTitles() {
        reloadSectionIndexTitlesCallCount += 1
        super.reloadSectionIndexTitles()
    }
}

private final class TableDelegateSpy: NSObject, UITableViewDelegate {
    var didEndDisplayingCount = 0

    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        didEndDisplayingCount += 1
    }
}

private final class TableSelectionDelegateSpy: NSObject, UITableViewDelegate {
    var selectedIndexPath: IndexPath?

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selectedIndexPath = indexPath
    }
}
