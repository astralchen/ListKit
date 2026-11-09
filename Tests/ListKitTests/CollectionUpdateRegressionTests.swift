import UIKit
import XCTest
@testable import ListKit

@MainActor
final class CollectionUpdateRegressionTests: XCTestCase {
    /// 叶子 disclosure 行遵循普通选择模式，并按顺序通知选中与取消选中。
    func testLeafSelectionModesAndDeselectionCallbacks() async {
        for mode in [ListSelectionMode.automatic, .single, .multiple, .none] {
            let view = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
            let adapter = CollectionListAdapter<Int>(collectionView: view)
            var events: [String] = []
            await adapter.apply(transaction: .disabled) {
                ListSection(0) {
                    DisclosureGroup(
                        Row("parent", model: (), cell: UICollectionViewListCell.self) { _, _, _ in }
                            .outlineDisclosure(),
                        isExpanded: false
                    ) {
                        Row("child", model: (), cell: UICollectionViewListCell.self) { _, _, _ in }
                    }
                    ForEach(["first", "second"], id: \.self) { id in
                        Row(id, model: (), cell: UICollectionViewListCell.self) { _, _, _ in }
                            .outlineDisclosure()
                            .onSelect { context in
                                XCTAssertEqual(context.item(as: String.self), id)
                                events.append("\(id)-selected")
                            }
                            .onDeselect { context in
                                XCTAssertEqual(context.item(as: String.self), id)
                                events.append("\(id)-deselected")
                            }
                            .onSelectionChange { value, context in
                                XCTAssertEqual(context.item(as: String.self), id)
                                events.append("\(id)-changed-\(value)")
                            }
                    }
                    Row("disabled", model: (), cell: UICollectionViewListCell.self) { _, _, _ in }
                        .outlineDisclosure().selectionDisabled()
                }.selectionMode(mode)
                    .onExpansionChange { _, _ in XCTFail("A leaf must not expand") }
                // 两个可选分区使 UIKit 允许全局多选，从而验证 adapter 的分区内单选逻辑。
                // 否则程序化 selectItem 会先静默取消第一项，无法检查 adapter 的取消选择回调。
                ListSection(1) {
                    Row("other-section", model: (), cell: UICollectionViewCell.self) { _, _, _ in }
                }.selectionMode(.single)
            }
            let first = IndexPath(item: 1, section: 0)
            let second = IndexPath(item: 2, section: 0)
            XCTAssertFalse(adapter.collectionView(view, shouldSelectItemAt: IndexPath(item: 3, section: 0)))
            for path in [first, second] {
                XCTAssertEqual(adapter.collectionView(view, shouldSelectItemAt: path), mode != .none)
            }
            XCTAssertTrue(events.isEmpty)
            guard mode != .none else { continue }
            XCTAssertTrue(view.allowsMultipleSelection)
            view.selectItem(at: first, animated: false, scrollPosition: [])
            adapter.collectionView(view, didSelectItemAt: first)
            XCTAssertEqual(view.indexPathsForSelectedItems, [first])
            XCTAssertEqual(events, ["first-selected", "first-changed-true"])

            view.selectItem(at: second, animated: false, scrollPosition: [])
            adapter.collectionView(view, didSelectItemAt: second)
            let expectedSelected = mode == .multiple ? [first, second] : [second]
            let expectedEvents = mode == .multiple
                ? ["first-selected", "first-changed-true", "second-selected", "second-changed-true"]
                : ["first-selected", "first-changed-true", "first-deselected", "first-changed-false",
                   "second-selected", "second-changed-true"]
            XCTAssertEqual(Set(view.indexPathsForSelectedItems ?? []), Set(expectedSelected), "\(mode)")
            XCTAssertEqual(events, expectedEvents, "\(mode)")

            view.deselectItem(at: second, animated: false)
            adapter.collectionView(view, didDeselectItemAt: second)
            XCTAssertEqual(events, expectedEvents + ["second-deselected", "second-changed-false"])
            XCTAssertEqual(Set(view.indexPathsForSelectedItems ?? []), Set(mode == .multiple ? [first] : []))
        }
    }

    /// 节点或整个分区在排队期间被删除时，跳过过期展开请求并继续后续刷新。
    func testRemovedNodeOrSectionDoesNotBlockQueuedReload() async throws {
        for removeSection in [false, true] {
            let view = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
            let adapter = CollectionListAdapter<Int>(collectionView: view)
            let source = try XCTUnwrap(view.dataSource as? UICollectionViewDiffableDataSource<AnyListID, AnyListIdentity>)
            let serial = ListTransaction.disabled.updatePolicy(.serial)
            let path = IndexPath(item: 0, section: 0)
            var notifications = 0
            await adapter.apply(transaction: serial) {
                ListSection(0) {
                    DisclosureGroup(
                        Row("parent", model: (), cell: UICollectionViewListCell.self) { _, _, _ in }
                            .outlineDisclosure().outlineAnimation(.disabled),
                        isExpanded: false
                    ) {
                        Row("child", model: (), cell: UICollectionViewListCell.self) { _, _, _ in }
                    }
                }.onExpansionChange { _, _ in
                    notifications += 1
                    adapter.apply(transaction: serial, completion: { _ in }) {
                        ListSection(removeSection ? 1 : 0) {
                            Row("replacement", model: (), cell: UICollectionViewListCell.self) { _, _, _ in }
                        }.onExpansionChange { _, _ in XCTFail("Stale expansion") }
                    }
                    adapter.collectionView(view, didSelectItemAt: path)
                }
            }
            adapter.collectionView(view, didSelectItemAt: path)
            let done = expectation(description: "later reload finishes")
            adapter.reloadAll(transaction: serial, transition: .identity) { _ in done.fulfill() }
            await fulfillment(of: [done], timeout: 5)
            XCTAssertEqual(notifications, 1)
            XCTAssertEqual(source.snapshot().sectionIdentifiers, [AnyListID(removeSection ? 1 : 0)])
            XCTAssertEqual(source.snapshot().itemIdentifiers.map { $0.rowID.typed(String.self) }, ["replacement"])
            XCTAssertFalse(adapter.isApplyingSnapshot)
        }
    }

    func testLeafDisclosureKeepsSelectionAndNotifiesSelectionChange() async {
        for expanded in [false, true] {
            let view = UICollectionView(
                frame: CGRect(x: 0, y: 0, width: 320, height: 480),
                collectionViewLayout: UICollectionViewFlowLayout())
            let adapter = CollectionListAdapter<Int>(collectionView: view)
            var selectionChanges: [Bool] = []
            var selectedIDs: [String?] = []
            var expansionChanges = 0
            await adapter.apply(transaction: .disabled) {
                ListSection(0) {
                    DisclosureGroup(
                        Row("parent", model: (), cell: UICollectionViewListCell.self) { _, _, _ in }
                            .outlineDisclosure(),
                        isExpanded: expanded
                    ) {
                        Row("child", model: (), cell: UICollectionViewListCell.self) { _, _, _ in }
                    }
                    Row("leaf", model: (), cell: UICollectionViewListCell.self) { _, _, _ in }
                        .outlineDisclosure()
                        .onSelectionChange { selected, context in
                            selectionChanges.append(selected)
                            selectedIDs.append(context.item(as: String.self))
                        }
                }.selectionMode(.single)
                    .onExpansionChange { _, _ in expansionChanges += 1 }
            }
            let path = IndexPath(item: expanded ? 2 : 1, section: 0)
            view.selectItem(at: path, animated: false, scrollPosition: [])
            adapter.collectionView(view, didSelectItemAt: path)
            XCTAssertEqual(selectionChanges, [true])
            XCTAssertEqual(selectedIDs, ["leaf"])
            XCTAssertEqual(view.indexPathsForSelectedItems, [path])

            await adapter.reloadAll(transaction: .disabled, transition: .identity)
            XCTAssertEqual(view.indexPathsForSelectedItems, [path])
            XCTAssertEqual(expansionChanges, 0)
        }
    }

    func testQueuedOutlineChangeRechecksChildrenAfterApply() async throws {
        let view = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: view)
        let source = try XCTUnwrap(view.dataSource as? UICollectionViewDiffableDataSource<AnyListID, AnyListIdentity>)
        let serial = ListTransaction.disabled.updatePolicy(.serial)
        let parentPath = IndexPath(item: 0, section: 0)
        var expansionChanges = 0
        await adapter.apply(transaction: serial) {
            ListSection(0) {
                DisclosureGroup(
                    Row("parent", model: (), cell: UICollectionViewListCell.self) { _, _, _ in }
                        .outlineDisclosure().outlineAnimation(.disabled),
                    isExpanded: false
                ) {
                    Row("child", model: (), cell: UICollectionViewListCell.self) { _, _, _ in }
                }
            }.onExpansionChange { _, _ in
                expansionChanges += 1
                adapter.apply(transaction: serial, completion: { _ in }) {
                    ListSection(0) {
                        Row("parent", model: (), cell: UICollectionViewListCell.self) { _, _, _ in }
                            .outlineDisclosure()
                    }.onExpansionChange { _, _ in expansionChanges += 1 }
                }
                // 当前快照仍有子项，但此前排队的 apply 会在这次点击执行前移除子项。
                adapter.collectionView(view, didSelectItemAt: parentPath)
            }
        }
        adapter.collectionView(view, didSelectItemAt: parentPath)
        let completed = expectation(description: "queue resumes after stale outline request")
        adapter.reloadAll(transaction: serial, transition: .identity) { _ in completed.fulfill() }
        await fulfillment(of: [completed], timeout: 5)
        XCTAssertEqual(expansionChanges, 1)
        XCTAssertEqual(source.snapshot(for: AnyListID(0)).items.map { $0.rowID.typed(String.self) }, ["parent"])
        XCTAssertFalse(adapter.isApplyingSnapshot)
    }

    func testQueuedReloadDataWaitsForUIKitBeforeFollowingReloadAll() async {
        let view = PendingCollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: view)
        let serial = ListTransaction.disabled.updatePolicy(.serial)
        let applied = expectation(description: "new snapshot committed")
        let reloaded = expectation(description: "subsequent reload")
        adapter.apply(transaction: serial, completion: { _ in }) { ListSection(0) {} }
        view.holdUpdates = true
        adapter.apply(options: .init(transaction: serial, applicationMode: .reloadData), completion: { summary in
            XCTAssertEqual(summary.animation.completionState, .completed)
            XCTAssertFalse(view.holdUpdates)
            applied.fulfill()
        }) { ListSection(1) {} }
        adapter.reloadAll(transaction: serial, transition: .identity) { summary in
            XCTAssertEqual(summary.animation.completionState, .completed)
            XCTAssertEqual(adapter.sectionIdentifier(at: 0), 1)
            reloaded.fulfill()
        }
        let checked = expectation(description: "queue checked UIKit")
        view.nextCheck = checked
        await fulfillment(of: [checked], timeout: 5)
        XCTAssertEqual(adapter.sectionIdentifier(at: 0), 0)
        XCTAssertEqual(view.earlyReloads, 0)
        view.holdUpdates = false
        await fulfillment(of: [applied, reloaded], timeout: 5, enforceOrder: true)
    }

    func testProviderRegistrationQueuesReentrantApply() async {
        for policy in [ListUpdatePolicy.serial, .coalesceLatest] {
            let view = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
            let adapter = CollectionListAdapter<Int>(collectionView: view)
            let transaction = ListTransaction.disabled.updatePolicy(policy)
            let outer = expectation(description: "outer apply")
            let inner = expectation(description: "queued apply")
            adapter.apply(transaction: transaction, completion: { summary in
                XCTAssertEqual(summary.animation.completionState, policy == .serial ? .completed : .superseded)
                XCTAssertEqual(adapter.sectionIdentifier(at: 0), 0)
                outer.fulfill()
            }) {
                ListSection(0) {}.supplementaries {
                    SectionSupplementary(ProviderSupplementary("badge", view: UICollectionReusableView.self, register: { _ in
                        let submitted = adapter.apply(transaction: transaction, completion: { summary in
                            XCTAssertEqual(summary.animation.completionState, .completed)
                            inner.fulfill()
                        }) { ListSection(1) {} }
                        XCTAssertEqual(submitted.animation.completionState, .submitted)
                        XCTAssertEqual(adapter.sectionIdentifier(at: 0), 0)
                    }) { _, _, _ in UICollectionReusableView() })
                }
            }
            await fulfillment(of: [outer, inner], timeout: 5, enforceOrder: true)
            XCTAssertEqual(adapter.sectionIdentifier(at: 0), 1)
        }
    }

    func testExpansionObserverCanRemoveSectionFromRowAndAccessory() async throws {
        for accessory in [false, true] {
            let view = UICollectionView(
                frame: CGRect(x: 0, y: 0, width: 320, height: 480),
                collectionViewLayout: UICollectionViewFlowLayout())
            let controller = UIViewController()
            controller.view = view
            let window = UIWindow(frame: view.bounds)
            window.rootViewController = controller
            window.isHidden = false
            defer { window.isHidden = true }
            let adapter = CollectionListAdapter<Int>(collectionView: view)
            let source = try XCTUnwrap(view.dataSource as? UICollectionViewDiffableDataSource<AnyListID, AnyListIdentity>)
            let updated = expectation(description: "observer update")
            var notifications = 0
            await adapter.apply(transaction: .disabled) {
                ListSection(0) {
                    DisclosureGroup(
                        Row("parent", model: (), cell: UICollectionViewListCell.self) { _, _, _ in }
                            .outlineDisclosure().outlineAnimation(.disabled),
                        isExpanded: false
                    ) {
                        Row("child", model: (), cell: UICollectionViewListCell.self) { _, _, _ in }
                    }
                }.onExpansionChange { _, expanded in
                    notifications += 1
                    XCTAssertTrue(expanded)
                    adapter.apply(transaction: .disabled, completion: { _ in updated.fulfill() }) { ListSection(1) {} }
                    XCTAssertEqual(adapter.sectionIdentifier(at: 0), 0)
                }
            }
            let parentPath = IndexPath(item: 0, section: 0)
            if accessory {
                let parent = try XCTUnwrap(source.itemIdentifier(for: parentPath))
                XCTAssertEqual(adapter.makeOutlineInteractionHandlers().shouldExpandItem?(parent), false)
            } else {
                adapter.collectionView(view, didSelectItemAt: parentPath)
            }
            await fulfillment(of: [updated], timeout: 5)
            XCTAssertEqual(source.snapshot().sectionIdentifiers, [AnyListID(1)])
            XCTAssertEqual(notifications, 1)
            view.layoutIfNeeded()
        }
    }

    func testCollapsedOutlineUsesCurrentSnapshotForSelectionAndPrefetch() async throws {
        let view = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: view)
        let source = try XCTUnwrap(view.dataSource as? UICollectionViewDiffableDataSource<AnyListID, AnyListIdentity>)
        var selected: [String] = []
        var prefetched: [String?] = []
        var cancelled: [String?] = []
        let collapsed = expectation(description: "accessory collapsed the parent")
        await adapter.apply(transaction: .disabled) {
            ListSection(0) {
                DisclosureGroup(
                    Row("parent", model: (), cell: UICollectionViewListCell.self) { _, _, _ in }
                        .outlineDisclosure().outlineAnimation(.disabled),
                    isExpanded: false
                ) {
                    Row("child", model: (), cell: UICollectionViewListCell.self) { _, _, _ in }
                        .onSelect { _ in selected.append("child") }
                        .onPrefetch { context in prefetched.append(context.item(as: String.self)) }
                }
                Row("sibling", model: (), cell: UICollectionViewListCell.self) { _, _, _ in }
                    .onSelect { _ in selected.append("sibling") }
                    .onPrefetch { context in prefetched.append(context.item(as: String.self)) }
                    .onCancelPrefetch { context in cancelled.append(context.item(as: String.self)) }
            }.onExpansionChange { _, expanded in
                if !expanded { collapsed.fulfill() }
            }
        }
        let first = IndexPath(item: 0, section: 0)
        let second = IndexPath(item: 1, section: 0)
        let sibling = try XCTUnwrap(source.itemIdentifier(for: second))
        let child = try XCTUnwrap(source.snapshot(for: AnyListID(0)).items.first { $0.rowID.typed(String.self) == "child" })
        XCTAssertEqual(adapter.collectionView(view, numberOfItemsInSection: 0), 2)
        XCTAssertEqual(adapter.rowIdentifier(at: second, as: String.self), "sibling")
        XCTAssertEqual(adapter.indexPath(for: sibling), second)
        XCTAssertEqual(adapter.indexPaths(forRowID: "sibling"), [second])
        XCTAssertNil(adapter.indexPath(for: child))
        XCTAssertTrue(adapter.indexPaths(forRowID: "child").isEmpty)
        XCTAssertTrue(adapter.contains(child))
        adapter.collectionView(view, didSelectItemAt: second)
        adapter.collectionView(view, prefetchItemsAt: [second])
        XCTAssertEqual(selected, ["sibling"])
        XCTAssertEqual(prefetched, ["sibling"])

        adapter.collectionView(view, didSelectItemAt: first)
        await adapter.reloadAll(transaction: .disabled, transition: .identity)
        XCTAssertEqual(adapter.rowIdentifier(at: second, as: String.self), "child")
        XCTAssertEqual(adapter.indexPath(for: child), second)
        XCTAssertEqual(adapter.indexPath(for: sibling), IndexPath(item: 2, section: 0))
        adapter.collectionView(view, cancelPrefetchingForItemsAt: [second])
        XCTAssertEqual(cancelled, ["sibling"])
        adapter.collectionView(view, didSelectItemAt: second)
        adapter.collectionView(view, prefetchItemsAt: [second])
        XCTAssertEqual(selected, ["sibling", "child"])
        XCTAssertEqual(prefetched, ["sibling", "child"])

        let parent = try XCTUnwrap(source.itemIdentifier(for: first))
        XCTAssertEqual(adapter.makeOutlineInteractionHandlers().shouldCollapseItem?(parent), false)
        await fulfillment(of: [collapsed], timeout: 5)
        await adapter.reloadAll(transaction: .disabled, transition: .identity)
        XCTAssertEqual(adapter.rowIdentifier(at: second, as: String.self), "sibling")
        XCTAssertNil(adapter.indexPath(for: child))
    }
}

@MainActor
private final class PendingCollectionView: UICollectionView {
    var holdUpdates = false
    var earlyReloads = 0
    var nextCheck: XCTestExpectation?

    override var hasUncommittedUpdates: Bool {
        nextCheck?.fulfill()
        nextCheck = nil
        return holdUpdates || super.hasUncommittedUpdates
    }

    override func reloadData() {
        if holdUpdates { earlyReloads += 1 }
        super.reloadData()
    }
}
