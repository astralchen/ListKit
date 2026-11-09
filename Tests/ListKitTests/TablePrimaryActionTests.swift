import UIKit
import XCTest
@testable import ListKit

@available(iOS 16.0, tvOS 16.0, *)
@MainActor
final class TablePrimaryActionTests: XCTestCase {
    private let plain = IndexPath(row: 0, section: 0)
    private let action = IndexPath(row: 1, section: 0)

    private func apply(
        to adapter: TableListAdapter<Int>,
        handler: (@MainActor (TableListContext) -> Void)? = nil
    ) async {
        var row = TableRow("action", model: (), cell: UITableViewCell.self) { _, _, _ in }
        if let handler { row = row.onPrimaryAction(handler) }
        await adapter.apply(transaction: .disabled) {
            TableSection(0) {
                TableRow("plain", model: (), cell: UITableViewCell.self) { _, _, _ in }
                row
            }.selectionMode(.multiple)
        }
    }

    func testCapabilityIsAvailableBeforeApplyAndTracksEachRowsCurrentAction() async {
        let table = UITableView(frame: .zero)
        let adapter = TableListAdapter<Int>(tableView: table)
        XCTAssertTrue(adapter.responds(to: #selector(UITableViewDelegate.tableView(_:canPerformPrimaryActionForRowAt:))))
        XCTAssertFalse(adapter.tableView(table, canPerformPrimaryActionForRowAt: plain))
        var receivedID: String?
        await apply(to: adapter, handler: { receivedID = $0.item(as: String.self) })
        XCTAssertTrue(table.allowsMultipleSelection)
        XCTAssertFalse(adapter.tableView(table, canPerformPrimaryActionForRowAt: plain))
        XCTAssertTrue(adapter.tableView(table, canPerformPrimaryActionForRowAt: action))
        adapter.tableView(table, performPrimaryActionForRowAt: action)
        XCTAssertEqual(receivedID, "action")

        await apply(to: adapter)
        XCTAssertFalse(adapter.tableView(table, canPerformPrimaryActionForRowAt: action))
        XCTAssertFalse(adapter.tableView(table, canPerformPrimaryActionForRowAt: IndexPath(row: 99, section: 0)))
    }

    func testExplicitDelegateCanVetoRowThenAllowItAndPreservesActionOrder() async {
        let table = UITableView(frame: .zero)
        let adapter = TableListAdapter<Int>(tableView: table)
        var events: [String] = []
        await apply(to: adapter, handler: { _ in events.append("row") })
        let delegate = TablePrimaryPolicyDelegate { _ in events.append("delegate") }
        delegate.allowedPath = plain
        adapter.tableDelegate = delegate
        XCTAssertFalse(adapter.tableView(table, canPerformPrimaryActionForRowAt: action))
        XCTAssertTrue(adapter.tableView(table, canPerformPrimaryActionForRowAt: plain))
        adapter.tableView(table, performPrimaryActionForRowAt: plain)
        XCTAssertEqual(events, ["delegate"])

        delegate.allowedPath = action
        XCTAssertFalse(adapter.tableView(table, canPerformPrimaryActionForRowAt: plain))
        XCTAssertTrue(adapter.tableView(table, canPerformPrimaryActionForRowAt: action))
        adapter.tableView(table, performPrimaryActionForRowAt: action)
        XCTAssertEqual(events, ["delegate", "row", "delegate"])
        delegate.allowedPath = nil
        XCTAssertFalse(adapter.tableView(table, canPerformPrimaryActionForRowAt: action))
    }

    func testExternalActionCanBeAttachedAfterApplyAndReleasedWithoutEnablingPlainRows() async {
        let table = UITableView(frame: .zero)
        let adapter = TableListAdapter<Int>(tableView: table)
        var events: [String] = []
        await apply(to: adapter, handler: { _ in events.append("row") })
        var delegate: TablePrimaryDelegate? = TablePrimaryDelegate { _ in events.append("delegate") }
        weak var released = delegate
        adapter.tableDelegate = delegate
        XCTAssertTrue(adapter.tableView(table, canPerformPrimaryActionForRowAt: plain))
        adapter.tableView(table, performPrimaryActionForRowAt: action)
        XCTAssertEqual(events, ["row", "delegate"])

        delegate = nil
        XCTAssertNil(released)
        XCTAssertNil(adapter.tableDelegate)
        XCTAssertFalse(adapter.tableView(table, canPerformPrimaryActionForRowAt: plain))
        XCTAssertTrue(adapter.tableView(table, canPerformPrimaryActionForRowAt: action))
    }
}

@available(iOS 16.0, tvOS 16.0, *)
@MainActor
private class TablePrimaryDelegate: NSObject, UITableViewDelegate {
    let action: (IndexPath) -> Void
    init(action: @escaping (IndexPath) -> Void) { self.action = action }
    func tableView(_ tableView: UITableView, performPrimaryActionForRowAt indexPath: IndexPath) {
        action(indexPath)
    }
}

@available(iOS 16.0, tvOS 16.0, *)
@MainActor
private final class TablePrimaryPolicyDelegate: TablePrimaryDelegate {
    var allowedPath: IndexPath?
    func tableView(_ tableView: UITableView, canPerformPrimaryActionForRowAt indexPath: IndexPath) -> Bool {
        indexPath == allowedPath
    }
}
