import UIKit
import XCTest
@testable import ListKit

@available(iOS 16.0, tvOS 16.0, *)
@MainActor
final class CollectionPrimaryActionTests: XCTestCase {
    private let plain = IndexPath(item: 1, section: 0)
    private let action = IndexPath(item: 2, section: 0)

    private func makeList() -> (UICollectionView, CollectionListAdapter<Int>) {
        let view = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        return (view, CollectionListAdapter(collectionView: view))
    }

    private func apply(
        to adapter: CollectionListAdapter<Int>,
        actionHandler: (@MainActor (ListContext) -> Void)? = nil
    ) async {
        var row = Row("action", model: (), cell: UICollectionViewListCell.self) { _, _, _ in }
        if let actionHandler { row = row.onPrimaryAction(actionHandler) }
        await adapter.apply(transaction: .disabled) {
            ListSection(0) {
                DisclosureGroup(
                    Row("parent", model: (), cell: UICollectionViewListCell.self) { _, _, _ in }
                        .outlineDisclosure(),
                    isExpanded: false
                ) {
                    Row("hidden", model: (), cell: UICollectionViewListCell.self) { _, _, _ in }
                        .onPrimaryAction { _ in XCTFail("Hidden child must not receive the visible row's action") }
                }
                Row("plain", model: (), cell: UICollectionViewListCell.self) { _, _, _ in }
                    .outlineDisclosure()
                row
            }.selectionMode(.multiple)
        }
    }

    func testCapabilityIsAvailableBeforeApplyAndTracksCurrentVisibleRow() async {
        let (view, adapter) = makeList()
        // UIKit 在绑定 delegate 时缓存可选方法能力，不能等第一次 apply 后才暴露此判断。
        XCTAssertTrue(adapter.responds(to: #selector(UICollectionViewDelegate.collectionView(_:canPerformPrimaryActionForItemAt:))))
        XCTAssertFalse(adapter.collectionView(view, canPerformPrimaryActionForItemAt: plain))
        await apply(to: adapter)
        XCTAssertFalse(adapter.collectionView(view, canPerformPrimaryActionForItemAt: plain))
        XCTAssertFalse(adapter.collectionView(view, canPerformPrimaryActionForItemAt: action))

        var receivedID: String?
        await apply(to: adapter, actionHandler: { receivedID = $0.item(as: String.self) })
        XCTAssertFalse(adapter.collectionView(view, canPerformPrimaryActionForItemAt: plain))
        XCTAssertTrue(adapter.collectionView(view, canPerformPrimaryActionForItemAt: action))
        adapter.collectionView(view, performPrimaryActionForItemAt: action)
        XCTAssertEqual(receivedID, "action")

        await apply(to: adapter)
        XCTAssertFalse(adapter.collectionView(view, canPerformPrimaryActionForItemAt: action))
        XCTAssertFalse(adapter.collectionView(view, canPerformPrimaryActionForItemAt: IndexPath(item: 99, section: 0)))
    }

    func testExternalActionAddedAfterApplyPreservesRowThenDelegateOrder() async {
        let (view, adapter) = makeList()
        var events: [String] = []
        await apply(to: adapter, actionHandler: { _ in events.append("row") })
        let delegate = ActionDelegate { path in
            XCTAssertEqual(path, self.action)
            events.append("delegate")
        }
        adapter.collectionDelegate = delegate
        XCTAssertTrue(adapter.collectionView(view, canPerformPrimaryActionForItemAt: plain))
        XCTAssertTrue(adapter.collectionView(view, canPerformPrimaryActionForItemAt: action))
        adapter.collectionView(view, performPrimaryActionForItemAt: action)
        XCTAssertEqual(events, ["row", "delegate"])
        adapter.collectionDelegate = nil
        XCTAssertFalse(adapter.collectionView(view, canPerformPrimaryActionForItemAt: plain))
        XCTAssertTrue(adapter.collectionView(view, canPerformPrimaryActionForItemAt: action))
    }

    func testExplicitDelegatePolicyCanVetoRowAndAllowPlainRow() async {
        let (view, adapter) = makeList()
        await apply(to: adapter, actionHandler: { _ in XCTFail("Vetoed Row must not run") })
        var performed: [IndexPath] = []
        let delegate = PolicyDelegate { performed.append($0) }
        delegate.allowedPath = plain
        adapter.collectionDelegate = delegate
        XCTAssertFalse(adapter.collectionView(view, canPerformPrimaryActionForItemAt: action))
        XCTAssertTrue(adapter.collectionView(view, canPerformPrimaryActionForItemAt: plain))
        adapter.collectionView(view, performPrimaryActionForItemAt: plain)
        XCTAssertEqual(performed, [plain])
        XCTAssertEqual(delegate.queries, [action, plain])
        delegate.allowedPath = nil
        XCTAssertFalse(adapter.collectionView(view, canPerformPrimaryActionForItemAt: plain))
    }

    func testReleasedExternalDelegateNoLongerEnablesPlainRows() async {
        let (view, adapter) = makeList()
        await apply(to: adapter)
        var delegate: ActionDelegate? = ActionDelegate { _ in }
        weak var released = delegate
        adapter.collectionDelegate = delegate
        XCTAssertTrue(adapter.collectionView(view, canPerformPrimaryActionForItemAt: plain))
        delegate = nil
        XCTAssertNil(released)
        XCTAssertFalse(adapter.collectionView(view, canPerformPrimaryActionForItemAt: plain))
    }

    func testPrimaryActionDoesNotRequireRowSelection() async {
        let (view, adapter) = makeList()
        var calls = 0
        await adapter.apply(transaction: .disabled) {
            ListSection(0) {
                Row("button", model: (), cell: UICollectionViewCell.self) { _, _, _ in }
                    .selectionDisabled()
                    .onPrimaryAction { _ in calls += 1 }
            }
        }
        let path = IndexPath(item: 0, section: 0)
        XCTAssertFalse(adapter.collectionView(view, shouldSelectItemAt: path))
        XCTAssertTrue(adapter.collectionView(view, canPerformPrimaryActionForItemAt: path))
        adapter.collectionView(view, performPrimaryActionForItemAt: path)
        XCTAssertEqual(calls, 1)
    }
}

@available(iOS 16.0, tvOS 16.0, *)
@MainActor
private class ActionDelegate: NSObject, UICollectionViewDelegate {
    let action: (IndexPath) -> Void
    init(action: @escaping (IndexPath) -> Void) { self.action = action }
    func collectionView(_ collectionView: UICollectionView, performPrimaryActionForItemAt indexPath: IndexPath) {
        action(indexPath)
    }
}

@available(iOS 16.0, tvOS 16.0, *)
@MainActor
private final class PolicyDelegate: ActionDelegate {
    var allowedPath: IndexPath?
    var queries: [IndexPath] = []
    func collectionView(_ collectionView: UICollectionView, canPerformPrimaryActionForItemAt indexPath: IndexPath) -> Bool {
        queries.append(indexPath)
        return indexPath == allowedPath
    }
}
