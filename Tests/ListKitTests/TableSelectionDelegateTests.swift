import XCTest
import UIKit
@testable import ListKit

@MainActor
final class TableSelectionDelegateTests: XCTestCase {
    private let indexPath = IndexPath(row: 0, section: 0)

    func testDelegateCanVetoSelection() async {
        let delegate = SelectionDecisionDelegate()
        let (tableView, adapter) = await makeTable(delegate: delegate)

        XCTAssertNil(adapter.tableView(tableView, willSelectRowAt: indexPath))
        XCTAssertEqual(delegate.selectionRequests, [indexPath])
        XCTAssertTrue(delegate.receivedTableView === tableView)
    }

    func testDelegateCanVetoDeselection() async {
        let delegate = SelectionDecisionDelegate()
        let (tableView, adapter) = await makeTable(delegate: delegate)

        XCTAssertNil(adapter.tableView(tableView, willDeselectRowAt: indexPath))
        XCTAssertEqual(delegate.deselectionRequests, [indexPath])
        XCTAssertTrue(delegate.receivedTableView === tableView)
    }

    func testDelegateCanRedirectSelectionAndDeselection() async {
        let delegate = SelectionDecisionDelegate()
        let destination = IndexPath(row: 1, section: 0)
        delegate.result = destination
        let (tableView, adapter) = await makeTable(delegate: delegate)

        XCTAssertEqual(adapter.tableView(tableView, willSelectRowAt: indexPath), destination)
        XCTAssertEqual(adapter.tableView(tableView, willDeselectRowAt: indexPath), destination)
        XCTAssertEqual(delegate.selectionRequests, [indexPath])
        XCTAssertEqual(delegate.deselectionRequests, [indexPath])
    }

    func testMissingDelegateUsesOriginalIndexPath() async {
        let (tableView, adapter) = await makeTable()

        XCTAssertEqual(adapter.tableView(tableView, willSelectRowAt: indexPath), indexPath)
        XCTAssertEqual(adapter.tableView(tableView, willDeselectRowAt: indexPath), indexPath)
    }

    func testUnimplementedCallbacksUseOriginalIndexPath() async {
        let delegate = EmptySelectionDelegate()
        let (tableView, adapter) = await makeTable(delegate: delegate)

        XCTAssertEqual(adapter.tableView(tableView, willSelectRowAt: indexPath), indexPath)
        XCTAssertEqual(adapter.tableView(tableView, willDeselectRowAt: indexPath), indexPath)
    }

    func testAutomaticSelectionPreservesDelegateVeto() async {
        let delegate = SelectionDecisionDelegate()
        let (tableView, adapter) = await makeTable(delegate: delegate, selectionMode: .automatic)

        XCTAssertTrue(tableView.allowsSelection)
        XCTAssertNil(adapter.tableView(tableView, willSelectRowAt: indexPath))
        XCTAssertNil(adapter.tableView(tableView, willDeselectRowAt: indexPath))
        XCTAssertEqual(delegate.selectionRequests, [indexPath])
        XCTAssertEqual(delegate.deselectionRequests, [indexPath])
    }

    func testSectionWithSelectionDisabledDoesNotConsultDelegate() async {
        let delegate = SelectionDecisionDelegate()
        delegate.result = indexPath
        let (tableView, adapter) = await makeTable(delegate: delegate, selectionMode: .none)

        XCTAssertNil(adapter.tableView(tableView, willSelectRowAt: indexPath))
        XCTAssertNil(adapter.tableView(tableView, willDeselectRowAt: indexPath))
        XCTAssertTrue(delegate.selectionRequests.isEmpty)
        XCTAssertTrue(delegate.deselectionRequests.isEmpty)
    }

    func testDisabledRowDoesNotConsultDelegate() async {
        let delegate = SelectionDecisionDelegate()
        delegate.result = indexPath
        let (tableView, adapter) = await makeTable(delegate: delegate, selectionDisabled: true)

        XCTAssertNil(adapter.tableView(tableView, willSelectRowAt: indexPath))
        XCTAssertNil(adapter.tableView(tableView, willDeselectRowAt: indexPath))
        XCTAssertTrue(delegate.selectionRequests.isEmpty)
        XCTAssertTrue(delegate.deselectionRequests.isEmpty)
    }

    private func makeTable(
        delegate: UITableViewDelegate? = nil,
        selectionMode: ListSelectionMode = .single,
        selectionDisabled: Bool = false
    ) async -> (UITableView, TableListAdapter<Int>) {
        let tableView = UITableView(frame: .zero, style: .plain)
        let adapter = TableListAdapter<Int>(tableView: tableView)
        adapter.tableDelegate = delegate
        _ = await adapter.apply(transaction: .disabled) {
            TableSection(0) {
                TableRow(0, model: "First", cell: UITableViewCell.self) { _, _, _ in }
                    .selectionDisabled(selectionDisabled)
                TableRow(1, model: "Second", cell: UITableViewCell.self) { _, _, _ in }
            }
            .selectionMode(selectionMode)
        }
        return (tableView, adapter)
    }
}

@MainActor
private final class SelectionDecisionDelegate: NSObject, UITableViewDelegate {
    var result: IndexPath?
    var selectionRequests: [IndexPath] = []
    var deselectionRequests: [IndexPath] = []
    weak var receivedTableView: UITableView?

    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        receivedTableView = tableView
        selectionRequests.append(indexPath)
        return result
    }

    func tableView(_ tableView: UITableView, willDeselectRowAt indexPath: IndexPath) -> IndexPath? {
        receivedTableView = tableView
        deselectionRequests.append(indexPath)
        return result
    }
}

@MainActor
private final class EmptySelectionDelegate: NSObject, UITableViewDelegate {}
