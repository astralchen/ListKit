import XCTest
import UIKit
@testable import ListKit

/// 验证列表释放后，已保活的 adapter 不再提交更新，且排队调用都能正常结束。
@MainActor
final class CollectionListAdapterLifecycleTests: XCTestCase {
    /// 页面已释放时，新的同步及异步 apply 都应取消，且不执行内容构建闭包。
    func testApplyAfterViewReleaseCancelsWithoutBuildingContent() async {
        var view: UICollectionView? = makeCollectionView()
        let adapter = CollectionListAdapter<Int>(collectionView: view!)
        weak let releasedView = view
        view = nil
        XCTAssertNil(releasedView)

        var callbacks: [ListApplyCompletionState] = []
        var didBuildContent = false
        let result = adapter.apply(transaction: .disabled, completion: {
            callbacks.append($0.animation.completionState)
        }) {
            didBuildContent = true
            return self.sections()
        }
        XCTAssertFalse(didBuildContent)
        XCTAssertEqual(result.animation.completionState, .cancelledBeforeCommit)
        XCTAssertEqual(callbacks, [.cancelledBeforeCommit])
        XCTAssertEqual(adapter.lastApplySummary, result)

        let asyncResult = await adapter.apply(transaction: .disabled) {
            didBuildContent = true
            return self.sections()
        }
        XCTAssertFalse(didBuildContent)
        XCTAssertEqual(asyncResult.animation.completionState, .cancelledBeforeCommit)
    }

    /// 列表释放后的完整刷新、行刷新及 Section 刷新都必须完成取消回调。
    func testRefreshEntryPointsCancelAfterViewRelease() async {
        var view: UICollectionView? = makeCollectionView()
        let adapter = CollectionListAdapter<Int>(collectionView: view!)
        weak let releasedView = view
        view = nil
        XCTAssertNil(releasedView)
        var states: [ListApplyCompletionState] = []
        let reload = adapter.reloadAll(transaction: .disabled) {
            states.append($0.animation.completionState)
        }
        let reconfigure = adapter.reconfigureRows(forRowIDs: [1, 1, 2], transaction: .disabled) {
            states.append($0.animation.completionState)
        }
        let rows = adapter.reloadRows(forRowID: 1, transaction: .disabled) {
            states.append($0.animation.completionState)
        }
        let sections = adapter.reloadSections([0, 0], transaction: .disabled) {
            states.append($0.animation.completionState)
        }
        XCTAssertEqual(states, Array(repeating: .cancelledBeforeCommit, count: 4))
        XCTAssertEqual(reload.animation.completionState, .cancelledBeforeCommit)
        XCTAssertEqual(reconfigure.animation.completionState, .cancelledBeforeCommit)
        XCTAssertEqual(rows.animation.completionState, .cancelledBeforeCommit)
        XCTAssertEqual(sections.animation.completionState, .cancelledBeforeCommit)
        XCTAssertEqual(reconfigure.requestedTargetCount, 2)
        XCTAssertEqual(rows.requestedTargetCount, 1)
        XCTAssertEqual(sections.requestedTargetCount, 1)
        let asyncResult = await adapter.reloadRows(forRowID: 1, transaction: .disabled)
        XCTAssertEqual(asyncResult.animation.completionState, .cancelledBeforeCommit)
    }

    /// 在真实 apply 的布局完成回调之前释放视图，确定性覆盖原崩溃的队列推进路径。
    func testLayoutCompletionCancelsQueuedMutationsAfterViewRelease() async throws {
        let capturedLayout = expectation(description: "layout completion captured")
        var delayedCompletion: ((Bool) -> Void)?
        var view: DelayedLayoutCollectionView? = DelayedLayoutCollectionView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            collectionViewLayout: UICollectionViewFlowLayout()
        )
        view?.captureCompletion = { completion in
            delayedCompletion = completion
            capturedLayout.fulfill()
        }
        var adapter: CollectionListAdapter<Int>? = CollectionListAdapter(collectionView: view!)
        weak let releasedView = view
        weak let releasedAdapter = adapter
        var firstStates: [ListApplyCompletionState] = []
        adapter!.apply(
            options: .init(
                transaction: ListTransaction.disabled.layoutAnimation(.enabled).updatePolicy(.serial),
                applicationMode: .reloadData
            ),
            completion: { firstStates.append($0.animation.completionState) }
        ) { self.sections() }
        await fulfillment(of: [capturedLayout], timeout: 3)
        XCTAssertNotNil(delayedCompletion)
        XCTAssertTrue(firstStates.isEmpty)

        var states: [String: [ListApplyCompletionState]] = [:]
        let serial = ListTransaction.disabled.updatePolicy(.serial)
        adapter!.apply(transaction: serial, completion: {
            states["apply", default: []].append($0.animation.completionState)
        }) { self.sections(value: "next") }
        adapter!.reconfigureRows(forRowID: 1, transaction: serial) {
            states["row1", default: []].append($0.animation.completionState)
        }
        adapter!.reconfigureRows(forRowID: 2, transaction: serial) {
            states["row2", default: []].append($0.animation.completionState)
        }
        adapter!.reloadSections([0], transaction: serial) {
            states["section", default: []].append($0.animation.completionState)
        }
        adapter!.reloadAll(transaction: serial) {
            states["reload", default: []].append($0.animation.completionState)
        }
        XCTAssertTrue(states.isEmpty)

        view = nil
        XCTAssertNil(releasedView, "排队和动画完成回调不应保活已退出页面的列表")
        var completion = try XCTUnwrap(delayedCompletion)
        delayedCompletion = nil
        completion(true)
        // 解除外部测试控制器对动画回调的持有，以验证 adapter 能最终释放。
        completion = { _ in }

        XCTAssertEqual(firstStates, [.completed], "已经提交的首项保留完成语义")
        for key in ["apply", "row1", "row2", "section", "reload"] {
            XCTAssertEqual(states[key], [.cancelledBeforeCommit], key)
        }
        XCTAssertFalse(adapter!.isApplyingSnapshot)
        adapter = nil
        XCTAssertNil(releasedAdapter)
        XCTAssertEqual(states.values.reduce(0) { $0 + $1.count }, 5)
    }

    /// 批量取消必须先清空队列，再回调；回调重入调度器不能启动或二次取消旧请求。
    func testSchedulerCancellationIsReentrantAndCompletesEachRequestOnce() {
        let scheduler = ListMutationScheduler()
        var callbacks: [Int] = []
        for index in 0..<2 {
            scheduler.enqueue(ListPendingMutationRequest(
                kind: .apply,
                updatePolicy: .serial,
                onCancel: {
                    callbacks.append(index)
                    XCTAssertFalse(scheduler.hasPendingRequests)
                    XCTAssertFalse(scheduler.startNext(hasUncommittedUpdates: false))
                    scheduler.cancelPendingRequests()
                },
                start: { XCTFail("取消期间不应执行排队请求") },
                supersede: { XCTFail("取消不应被报告为替代") }
            ))
        }
        scheduler.cancelPendingRequests()
        scheduler.cancelPendingRequests()
        XCTAssertEqual(callbacks, [0, 1])
    }

    /// 创建无需窗口宿主的列表，用于单独验证所有权和提交入口。
    private func makeCollectionView() -> UICollectionView {
        UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            collectionViewLayout: UICollectionViewFlowLayout()
        )
    }

    /// 构造具有稳定身份、可更换内容的最小列表快照。
    private func sections(value: String = "initial") -> [ListSection<Int>] {
        [ListSection(0) {
            Row(1, model: value, cell: UICollectionViewCell.self) { _, _, _ in }
        }]
    }
}

/// 将 ListKit 发起的布局完成回调交给测试控制，避免用固定 sleep 猜测动画时序。
@MainActor
private final class DelayedLayoutCollectionView: UICollectionView {
    /// 第一次布局更新时交付 UIKit 完成回调；不捕获列表本身。
    var captureCompletion: ((((Bool) -> Void)?) -> Void)?

    /// 执行真实布局失效闭包，延迟完成通知以构造“视图先释放、回调后到达”的场景。
    override func performBatchUpdates(_ updates: (() -> Void)?, completion: ((Bool) -> Void)? = nil) {
        updates?()
        captureCompletion?(completion)
    }
}
