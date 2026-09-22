import XCTest
import UIKit
import ListKit

/// 通过公开 API 验证菜单路由、源码兼容和跨 snapshot 的会话生命周期。
@MainActor
final class CollectionContextMenuTests: XCTestCase {
    private typealias MenuRow = Row<Int, String, UICollectionViewCell>
    private let first = IndexPath(item: 0, section: 0)
    private let second = IndexPath(item: 1, section: 0)

    private func row(_ id: Int = 1) -> MenuRow {
        Row(id, model: "Row \(id)", cell: UICollectionViewCell.self) { _, _, _ in }
    }

    private func configuration() -> UIContextMenuConfiguration {
        UIContextMenuConfiguration(identifier: "same-business-id" as NSString, previewProvider: nil) { _ in
            UIMenu(children: [UIAction(title: "Action") { _ in }])
        }
    }

    private func makeList() -> (UICollectionView, CollectionListAdapter<Int>) {
        let view = UICollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), collectionViewLayout: UICollectionViewFlowLayout())
        return (view, CollectionListAdapter(collectionView: view))
    }

    private func apply(_ rows: [MenuRow], to adapter: CollectionListAdapter<Int>) async {
        _ = await adapter.apply(options: .init(transaction: .disabled, applicationMode: .reloadData)) {
            ListSection(0) { rows.map { $0 as any ListRowRepresentable } }
        }
    }

    private func preview() -> UITargetedPreview {
        let container = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let view = UIView(frame: container.bounds)
        container.addSubview(view)
        return UITargetedPreview(view: view, parameters: UIPreviewParameters(), target: UIPreviewTarget(container: container, center: view.center))
    }

    func testPublicOverloadsRemainUnambiguousAndLastSetterWins() async {
        let (view, adapter) = makeList()
        let config = configuration()
        var receivedPoint: CGPoint?
        var events: [String] = []
        let target = preview()
        let item = row()
            .contextMenu { _ in XCTFail("Replaced provider"); return nil }
            .contextMenu { _, point in receivedPoint = point; return config }
            .contextMenuPreview()
            .contextMenuPreview(highlighting: nil)
            .contextMenuPreview(dismissal: nil)
            .contextMenuPreview(highlighting: nil, dismissal: nil)
            .contextMenuPreview(highlighting: { _ in nil }, dismissal: { _ in nil })
            .contextMenuPreview(highlighting: { _, _ in target })
            .contextMenuPreview(dismissal: { _, configuration in
                XCTAssertTrue(configuration === config)
                return target
            })
            .onContextMenuCommit { _, _ in XCTFail("Replaced commit") }
            .onContextMenuCommit { _, configuration, _ in
                XCTAssertTrue(configuration === config)
                events.append("commit")
            }
            .onContextMenuWillDisplay { _, _, _ in XCTFail("Replaced display") }
            .onContextMenuWillDisplay { _, _, _ in events.append("display") }
            .onContextMenuWillEnd { _, _, _ in events.append("end") }
        await apply([item], to: adapter)
        let point = CGPoint(x: 19, y: 28)
        XCTAssertTrue(adapter.collectionView(view, contextMenuConfigurationForItemAt: first, point: point) === config)
        XCTAssertEqual(receivedPoint, point)
        XCTAssertNil(adapter.collectionView(view, previewForHighlightingContextMenuWithConfiguration: config))
        XCTAssertTrue(adapter.collectionView(view, previewForDismissingContextMenuWithConfiguration: config) === target)
        adapter.collectionView(view, willDisplayContextMenu: config, animator: nil)
        adapter.collectionView(view, willPerformPreviewActionForMenuWith: config, animator: MenuAnimator())
        adapter.collectionView(view, willEndContextMenuInteraction: config, animator: nil)
        XCTAssertEqual(events, ["display", "commit", "end"])
        XCTAssertNil(adapter.collectionView(view, previewForDismissingContextMenuWithConfiguration: config))
    }

    func testLegacyClosuresCanReplaceNewClosures() async {
        let (view, adapter) = makeList()
        let config = configuration()
        let target = preview()
        var committed = false
        await apply([row()
            .contextMenu { _, _ in XCTFail(); return nil }
            .contextMenu { _ in config }
            .contextMenuPreview(highlighting: { _, _ in XCTFail(); return nil })
            .contextMenuPreview(highlighting: { _ in target }, dismissal: { _ in target })
            .onContextMenuCommit { _, _, _ in XCTFail() }
            .onContextMenuCommit { _, _ in committed = true }
        ], to: adapter)
        XCTAssertTrue(adapter.collectionView(view, contextMenuConfigurationForItemAt: first, point: .zero) === config)
        XCTAssertTrue(adapter.collectionView(view, previewForHighlightingContextMenuWithConfiguration: config) === target)
        XCTAssertTrue(adapter.collectionView(view, previewForDismissingContextMenuWithConfiguration: config) === target)
        adapter.collectionView(view, willPerformPreviewActionForMenuWith: config, animator: MenuAnimator())
        XCTAssertTrue(committed)
    }

    @available(iOS 16.0, *)
    func testConfigurationPriorityIsLazyAcrossEveryFallback() async {
        let (view, adapter) = makeList()
        let delegate = MenuDelegate()
        adapter.collectionDelegate = delegate
        let config = configuration()
        var stage = 0
        var calls: [String] = []
        adapter.contextMenuForItems { contexts, point in
            calls.append("items")
            XCTAssertEqual(contexts.count, 1)
            XCTAssertEqual(point, CGPoint(x: 3, y: 4))
            return stage == 0 ? config : nil
        }
        await apply([row().contextMenu { _, _ in calls.append("row"); return stage == 1 ? config : nil }], to: adapter)
        delegate.newConfiguration = { calls.append("new"); return stage == 2 ? config : nil }
        delegate.oldConfiguration = { calls.append("old"); return stage == 3 ? config : nil }
        for current in 0...4 {
            stage = current
            calls = []
            let result = adapter.collectionView(view, contextMenuConfigurationForItemsAt: [first], point: CGPoint(x: 3, y: 4))
            XCTAssertEqual(calls, Array(["items", "row", "new", "old"].prefix(min(current + 1, 4))))
            XCTAssertEqual(result === config, current < 4)
        }
    }

    func testLegacyConfigurationFallsBackForMissingRows() async {
        let (view, adapter) = makeList()
        let delegate = MenuDelegate()
        adapter.collectionDelegate = delegate
        let config = configuration()
        var calls = 0
        delegate.oldConfiguration = { calls += 1; return config }
        await apply([row().contextMenu { _, _ in nil }], to: adapter)
        XCTAssertTrue(adapter.collectionView(view, contextMenuConfigurationForItemAt: first, point: .zero) === config)
        XCTAssertTrue(adapter.collectionView(view, contextMenuConfigurationForItemAt: second, point: .zero) === config)
        XCTAssertEqual(calls, 2)
    }

    @available(iOS 16.0, *)
    func testModernPreviewsFallbackToLegacyAndUnknownConfigurationsUseOnlyDelegate() async {
        let (view, adapter) = makeList()
        let delegate = MenuDelegate()
        adapter.collectionDelegate = delegate
        let config = configuration()
        let unknown = configuration()
        let target = preview()
        var stage = 0
        var calls: [String] = []
        await apply([row().contextMenu { _ in config }.contextMenuPreview(
            highlighting: { _, received in
                XCTAssertTrue(received === config)
                calls.append("row"); return stage == 0 ? target : nil
            },
            dismissal: { _, _ in calls.append("row"); return stage == 0 ? target : nil }
        )], to: adapter)
        _ = adapter.collectionView(view, contextMenuConfigurationForItemsAt: [first], point: .zero)
        delegate.newPreview = { calls.append("new"); return stage == 1 ? target : nil }
        delegate.oldPreview = { calls.append("old"); return stage == 2 ? target : nil }
        for current in 0...3 {
            stage = current
            for highlight in [true, false] {
                calls = []
                let result = highlight
                    ? adapter.collectionView(view, contextMenuConfiguration: config, highlightPreviewForItemAt: first)
                    : adapter.collectionView(view, contextMenuConfiguration: config, dismissalPreviewForItemAt: first)
                XCTAssertEqual(calls, Array(["row", "new", "old"].prefix(min(current + 1, 3))))
                XCTAssertEqual(result === target, current < 3)
            }
        }
        calls = []
        _ = adapter.collectionView(view, contextMenuConfiguration: unknown, highlightPreviewForItemAt: first)
        XCTAssertEqual(calls, ["new", "old"])
        calls = []
        _ = adapter.collectionView(view, previewForDismissingContextMenuWithConfiguration: unknown)
        XCTAssertEqual(calls, ["old"])
    }

    func testLifecycleAndCommitForwardSameObjectsInRowThenDelegateOrder() async {
        let (view, adapter) = makeList()
        let delegate = MenuDelegate()
        adapter.collectionDelegate = delegate
        let config = configuration()
        let animator = MenuAnimator()
        var events: [String] = []
        func record(_ label: String, _ received: UIContextMenuConfiguration, _ animation: (any UIContextMenuInteractionAnimating)?) {
            XCTAssertTrue(received === config)
            XCTAssertTrue(animation === animator)
            events.append(label)
        }
        await apply([row().contextMenu { _ in config }
            .onContextMenuWillDisplay { _, c, a in record("row-display", c, a) }
            .onContextMenuCommit { _, c, a in record("row-commit", c, a) }
            .onContextMenuWillEnd { _, c, a in record("row-end", c, a) }
        ], to: adapter)
        delegate.notification = { event, c, a in record("delegate-" + event, c, a) }
        _ = adapter.collectionView(view, contextMenuConfigurationForItemAt: first, point: .zero)
        adapter.collectionView(view, willDisplayContextMenu: config, animator: animator)
        adapter.collectionView(view, willPerformPreviewActionForMenuWith: config, animator: animator)
        adapter.collectionView(view, willEndContextMenuInteraction: config, animator: animator)
        XCTAssertEqual(events, ["row-display", "delegate-display", "row-commit", "delegate-commit", "row-end", "delegate-end"])
        animator.finish()
        events = []
        adapter.collectionView(view, willDisplayContextMenu: config, animator: animator)
        adapter.collectionView(view, willPerformPreviewActionForMenuWith: config, animator: animator)
        adapter.collectionView(view, willEndContextMenuInteraction: config, animator: animator)
        XCTAssertEqual(events, ["delegate-display", "delegate-commit", "delegate-end"])
    }

    func testConfigurationsWithSameIdentifierRemainIndependentUntilAnimationCompletes() async {
        let (view, adapter) = makeList()
        let a = configuration(), b = configuration()
        let target = preview()
        var rows: [Int] = []
        await apply([1, 2].map { id in
            row(id).contextMenu { _ in id == 1 ? a : b }
                .contextMenuPreview(highlighting: { context, _ in
                    rows.append(context.item(as: Int.self)!)
                    return target
                })
        }, to: adapter)
        _ = adapter.collectionView(view, contextMenuConfigurationForItemAt: first, point: .zero)
        _ = adapter.collectionView(view, contextMenuConfigurationForItemAt: second, point: .zero)
        XCTAssertEqual(a.identifier as? NSString, "same-business-id")
        let animator = MenuAnimator()
        adapter.collectionView(view, willEndContextMenuInteraction: a, animator: animator)
        _ = adapter.collectionView(view, previewForHighlightingContextMenuWithConfiguration: a)
        _ = adapter.collectionView(view, previewForHighlightingContextMenuWithConfiguration: b)
        XCTAssertEqual(rows, [1, 2])
        animator.finish()
        XCTAssertNil(adapter.collectionView(view, previewForHighlightingContextMenuWithConfiguration: a))
        XCTAssertTrue(adapter.collectionView(view, previewForHighlightingContextMenuWithConfiguration: b) === target)
    }

    func testOldCompletionCannotRemoveReentrantSessionForSameConfiguration() async {
        for animated in [false, true] {
            let (view, adapter) = makeList()
            let config = configuration()
            let target = preview()
            var reentered = false
            await apply([row().contextMenu { _ in config }
                .contextMenuPreview(highlighting: { _ in target })
                .onContextMenuWillEnd { [weak adapter, weak view] _, _, _ in
                    guard let adapter, let view else { return }
                    reentered = true
                    _ = adapter.collectionView(view, contextMenuConfigurationForItemAt: self.first, point: .zero)
                }
            ], to: adapter)
            _ = adapter.collectionView(view, contextMenuConfigurationForItemAt: first, point: .zero)
            let animator = MenuAnimator()
            adapter.collectionView(view, willEndContextMenuInteraction: config, animator: animated ? animator : nil)
            animator.finish()
            XCTAssertTrue(reentered)
            XCTAssertTrue(adapter.collectionView(view, previewForHighlightingContextMenuWithConfiguration: config) === target)
        }
    }

    @available(iOS 16.0, *)
    func testMovedRowUsesCurrentPositionAndCapturedClosuresDeletedRowOnlyReceivesLifecycle() async {
        let (view, adapter) = makeList()
        let config = configuration()
        let target = preview()
        var positions: [IndexPath] = []
        var commits = 0
        var ended: ListContext?
        await apply([row().contextMenu { _ in config }
            .contextMenuPreview(highlighting: { context, _ in positions.append(context.indexPath); return target })
            .onContextMenuCommit { context, _, _ in positions.append(context.indexPath); commits += 1 }
            .onContextMenuWillEnd { context, _, _ in ended = context }, row(2)
        ], to: adapter)
        _ = adapter.collectionView(view, contextMenuConfigurationForItemsAt: [first], point: .zero)
        await apply([row(2), row().contextMenuPreview(highlighting: { _, _ in XCTFail("Must use captured Row"); return nil })], to: adapter)
        XCTAssertTrue(adapter.collectionView(view, contextMenuConfiguration: config, highlightPreviewForItemAt: second) === target)
        XCTAssertNil(adapter.collectionView(view, contextMenuConfiguration: config, highlightPreviewForItemAt: first))
        adapter.collectionView(view, willPerformPreviewActionForMenuWith: config, animator: MenuAnimator())
        XCTAssertEqual(positions, [second, second])
        await apply([row(2)], to: adapter)
        XCTAssertNil(adapter.collectionView(view, previewForHighlightingContextMenuWithConfiguration: config))
        adapter.collectionView(view, willPerformPreviewActionForMenuWith: config, animator: MenuAnimator())
        XCTAssertEqual(commits, 1)
        adapter.collectionView(view, willEndContextMenuInteraction: config, animator: nil)
        XCTAssertEqual(ended?.item(as: Int.self), 1)
        XCTAssertEqual(ended?.indexPath, first)
    }

    @available(iOS 16.0, *)
    func testMultipleItemsPreviewIndividuallyAndNotifyFirstTarget() async {
        let (view, adapter) = makeList()
        let config = configuration()
        var previews: [Int] = []
        var notifications: [Int] = []
        adapter.contextMenuForItems { contexts, _ in
            XCTAssertEqual(contexts.map { $0.item(as: Int.self)! }, [1, 2])
            return config
        }
        await apply([1, 2].map { id in
            row(id).contextMenuPreview(highlighting: { context, _ in previews.append(context.item(as: Int.self)!); return nil })
                .onContextMenuWillDisplay { context, _, _ in notifications.append(context.item(as: Int.self)!) }
                .onContextMenuCommit { context, _, _ in notifications.append(context.item(as: Int.self)!) }
                .onContextMenuWillEnd { context, _, _ in notifications.append(context.item(as: Int.self)!) }
        }, to: adapter)
        _ = adapter.collectionView(view, contextMenuConfigurationForItemsAt: [first, second], point: .zero)
        _ = adapter.collectionView(view, contextMenuConfiguration: config, highlightPreviewForItemAt: first)
        _ = adapter.collectionView(view, contextMenuConfiguration: config, highlightPreviewForItemAt: second)
        adapter.collectionView(view, willDisplayContextMenu: config, animator: nil)
        adapter.collectionView(view, willPerformPreviewActionForMenuWith: config, animator: MenuAnimator())
        adapter.collectionView(view, willEndContextMenuInteraction: config, animator: nil)
        XCTAssertEqual(previews, [1, 2])
        XCTAssertEqual(notifications, [1, 1, 1])
    }

    @available(iOS 16.0, *)
    func testEmptySpaceUsesItemsProviderAndModernDelegateWithoutRowOrLegacyFallback() async {
        let (view, adapter) = makeList()
        let delegate = MenuDelegate()
        adapter.collectionDelegate = delegate
        let config = configuration()
        var calls: [String] = []
        adapter.contextMenuForItems { contexts, _ in XCTAssertTrue(contexts.isEmpty); calls.append("items"); return nil }
        delegate.newConfiguration = { calls.append("new"); return config }
        delegate.oldConfiguration = { XCTFail("No item for legacy fallback"); return nil }
        await apply([row().contextMenu { _ in XCTFail(); return nil }], to: adapter)
        XCTAssertTrue(adapter.collectionView(view, contextMenuConfigurationForItemsAt: [], point: .zero) === config)
        XCTAssertEqual(calls, ["items", "new"])
    }

    func testEndedAndAbandonedSessionsReleaseCapturedRowResources() async {
        for abandoned in [false, true] {
            let (view, adapter) = makeList()
            var config: UIContextMenuConfiguration? = configuration()
            weak var weakConfig = config
            weak var resource: NSObject?
            do {
                let object = NSObject()
                resource = object
                await apply([row().contextMenu { [weak config] _ in config }
                    .onContextMenuWillEnd { [object] _, _, _ in _ = object.description }
                ], to: adapter)
            }
            _ = adapter.collectionView(view, contextMenuConfigurationForItemAt: first, point: .zero)
            await apply([], to: adapter)
            XCTAssertNotNil(resource)
            if abandoned {
                config = nil
                XCTAssertNil(weakConfig, "Session must not retain configuration")
                _ = adapter.collectionView(view, contextMenuConfigurationForItemAt: first, point: .zero)
            } else {
                let animator = MenuAnimator()
                adapter.collectionView(view, willEndContextMenuInteraction: config!, animator: animator)
                XCTAssertNotNil(resource)
                animator.finish()
            }
            XCTAssertNil(resource)
        }
    }
}

/// 手动控制动画结束时机，确定性覆盖延迟清理和重入。
@MainActor
private final class MenuAnimator: NSObject, UIContextMenuInteractionCommitAnimating {
    var previewViewController: UIViewController? { nil }
    var preferredCommitStyle: UIContextMenuInteractionCommitStyle = .dismiss
    private var completions: [() -> Void] = []
    func addAnimations(_ animations: @escaping () -> Void) { animations() }
    func addCompletion(_ completion: @escaping () -> Void) { completions.append(completion) }
    func finish() {
        let pending = completions
        completions.removeAll()
        pending.forEach { $0() }
    }
}

/// 同时实现新旧代理入口，记录惰性回退和通知顺序。
@MainActor
private final class MenuDelegate: NSObject, UICollectionViewDelegate {
    var oldConfiguration: (() -> UIContextMenuConfiguration?)?
    var newConfiguration: (() -> UIContextMenuConfiguration?)?
    var oldPreview: (() -> UITargetedPreview?)?
    var newPreview: (() -> UITargetedPreview?)?
    var notification: ((String, UIContextMenuConfiguration, (any UIContextMenuInteractionAnimating)?) -> Void)?
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? { oldConfiguration?() }
    @available(iOS 16.0, *)
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? { newConfiguration?() }
    func collectionView(_ collectionView: UICollectionView, previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? { oldPreview?() }
    func collectionView(_ collectionView: UICollectionView, previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? { oldPreview?() }
    @available(iOS 16.0, *)
    func collectionView(_ collectionView: UICollectionView, contextMenuConfiguration configuration: UIContextMenuConfiguration, highlightPreviewForItemAt indexPath: IndexPath) -> UITargetedPreview? { newPreview?() }
    @available(iOS 16.0, *)
    func collectionView(_ collectionView: UICollectionView, contextMenuConfiguration configuration: UIContextMenuConfiguration, dismissalPreviewForItemAt indexPath: IndexPath) -> UITargetedPreview? { newPreview?() }
    func collectionView(_ collectionView: UICollectionView, willDisplayContextMenu configuration: UIContextMenuConfiguration, animator: (any UIContextMenuInteractionAnimating)?) { notification?("display", configuration, animator) }
    func collectionView(_ collectionView: UICollectionView, willEndContextMenuInteraction configuration: UIContextMenuConfiguration, animator: (any UIContextMenuInteractionAnimating)?) { notification?("end", configuration, animator) }
    func collectionView(_ collectionView: UICollectionView, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: any UIContextMenuInteractionCommitAnimating) { notification?("commit", configuration, animator) }
}
