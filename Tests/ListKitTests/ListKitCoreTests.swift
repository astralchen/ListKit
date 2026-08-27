import XCTest
import UIKit
@testable import ListKit

@MainActor
final class ListKitCoreTests: XCTestCase {
    func testAsyncMutationBridgeHandlesCancelBeforeRegister() async {
        let cancelled = ListRefreshSummary(
            animation: ListAnimationSummary(completionState: .cancelledBeforeCommit)
        )
        let bridge = ListAsyncMutationBridge(cancelledResult: cancelled)
        bridge.cancel()

        let result = await withCheckedContinuation { continuation in
            XCTAssertFalse(bridge.register(continuation, cancellation: {}))
        }

        XCTAssertEqual(result.animation.completionState, .cancelledBeforeCommit)
    }

    func testAsyncMutationBridgeResumesExactlyOnce() async {
        let bridge = ListAsyncMutationBridge(cancelledResult: 0)
        let result = await withCheckedContinuation { continuation in
            XCTAssertTrue(bridge.register(continuation, cancellation: {}))
            bridge.resume(returning: 1)
            bridge.resume(returning: 2)
        }

        XCTAssertEqual(result, 1)
    }

    func testSchedulerCancelsOnlyMatchingMergedSubscriber() {
        let scheduler = ListMutationScheduler()
        let firstID = UUID()
        let secondID = UUID()
        var firstState: ListApplyCompletionState?
        var secondState: ListApplyCompletionState?
        var executedSubscribers: [ListRowRefreshSubscriber] = []
        let execute: (
            [ListRowRefreshSubscriber],
            AnyListID?,
            ListRefreshScope,
            ListTransaction
        ) -> Void = { subscribers, _, _, _ in
            executedSubscribers = subscribers
            subscribers.forEach { subscriber in
                subscriber.completion?(ListRefreshSummary(
                    requestedTargetCount: subscriber.rowIDs.count,
                    matchedTargetCount: subscriber.rowIDs.count,
                    animation: ListAnimationSummary(completionState: .completed)
                ))
            }
        }
        scheduler.enqueue(ListPendingMutationRequest(
            rowIDs: [AnyListID("first")],
            sectionID: nil,
            scope: .visible,
            action: .reconfigure(layout: .none),
            transaction: .automatic,
            subscriberID: firstID,
            completion: { firstState = $0.animation.completionState },
            execute: execute
        ))
        scheduler.enqueue(ListPendingMutationRequest(
            rowIDs: [AnyListID("second")],
            sectionID: nil,
            scope: .visible,
            action: .reload,
            transaction: .automatic,
            subscriberID: secondID,
            completion: { secondState = $0.animation.completionState },
            execute: execute
        ))

        XCTAssertTrue(scheduler.cancelSubscriber(firstID))
        XCTAssertEqual(firstState, .cancelledBeforeCommit)
        XCTAssertTrue(scheduler.startNext(hasUncommittedUpdates: false))
        XCTAssertEqual(executedSubscribers.map(\.id), [secondID])
        XCTAssertEqual(secondState, .completed)
    }

    func testFireAndForgetSubscriberKeepsMergedRequestExecutable() {
        let scheduler = ListMutationScheduler()
        let cancellableID = UUID()
        var executedSubscribers: [ListRowRefreshSubscriber] = []
        let execute: (
            [ListRowRefreshSubscriber],
            AnyListID?,
            ListRefreshScope,
            ListTransaction
        ) -> Void = { subscribers, _, _, _ in executedSubscribers = subscribers }
        scheduler.enqueue(ListPendingMutationRequest(
            rowIDs: [AnyListID("fire-and-forget")],
            sectionID: nil,
            scope: .visible,
            action: .reconfigure(layout: .none),
            transaction: .automatic,
            completion: nil,
            execute: execute
        ))
        scheduler.enqueue(ListPendingMutationRequest(
            rowIDs: [AnyListID("cancelled")],
            sectionID: nil,
            scope: .visible,
            action: .reload,
            transaction: .automatic,
            subscriberID: cancellableID,
            completion: { _ in },
            execute: execute
        ))

        XCTAssertTrue(scheduler.cancelSubscriber(cancellableID))
        XCTAssertTrue(scheduler.startNext(hasUncommittedUpdates: false))
        XCTAssertEqual(executedSubscribers.count, 1)
        XCTAssertNil(executedSubscribers[0].id)
        XCTAssertEqual(executedSubscribers[0].rowIDs, [AnyListID("fire-and-forget")])
    }

    func testMutationCoordinatorMergesCompatibleRowsAndUpgradesAction() {
        var executionCount = 0
        var executedSubscribers: [ListRowRefreshSubscriber] = []
        var firstCompletion: ListRefreshSummary?
        var secondCompletion: ListRefreshSummary?

        let execute: (
            [ListRowRefreshSubscriber],
            AnyListID?,
            ListRefreshScope,
            ListTransaction
        ) -> Void = { subscribers, _, _, _ in
            executionCount += 1
            executedSubscribers = subscribers
            subscribers.forEach { subscriber in
                subscriber.completion?(ListRefreshSummary(
                    requestedTargetCount: subscriber.rowIDs.count,
                    matchedTargetCount: subscriber.rowIDs.count,
                    refreshMetrics: ListRefreshMetrics(
                        reloadedRowCount: subscriber.action == .reload
                            ? subscriber.rowIDs.count
                            : 0
                    ),
                    animation: ListAnimationSummary(completionState: .completed)
                ))
            }
        }
        let first = ListPendingMutationRequest(
            rowIDs: [AnyListID("first")],
            sectionID: AnyListID(0),
            scope: .allMatching,
            action: .reconfigure(layout: .none),
            transaction: .automatic,
            completion: { firstCompletion = $0 },
            execute: execute
        )
        let second = ListPendingMutationRequest(
            rowIDs: [AnyListID("second")],
            sectionID: AnyListID(0),
            scope: .allMatching,
            action: .reload,
            transaction: .automatic,
            completion: { secondCompletion = $0 },
            execute: execute
        )

        XCTAssertTrue(first.mergeCompatibleRowRefresh(second))
        first.start()

        XCTAssertEqual(executionCount, 1)
        XCTAssertEqual(executedSubscribers.map(\.rowIDs), [
            [AnyListID("first")],
            [AnyListID("second")]
        ])
        XCTAssertEqual(executedSubscribers.map(\.action), [
            .reconfigure(layout: .none),
            .reload
        ])
        XCTAssertEqual(firstCompletion?.requestedTargetCount, 1)
        XCTAssertEqual(secondCompletion?.requestedTargetCount, 1)
        XCTAssertEqual(firstCompletion?.refreshMetrics.reloadedRowCount, 0)
        XCTAssertEqual(secondCompletion?.refreshMetrics.reloadedRowCount, 1)
    }

    func testMutationCoordinatorDoesNotSupersedeSerialActiveMutation() {
        let coordinator = ListMutationCoordinator()
        let serial = coordinator.begin(kind: .apply, updatePolicy: .serial)
        coordinator.supersedeActiveApply()
        XCTAssertFalse(serial.isSuperseded)
        coordinator.finish(serial)

        let targeted = coordinator.begin(kind: .rowRefresh, updatePolicy: .coalesceLatest)
        coordinator.supersedeActiveApply()
        XCTAssertFalse(targeted.isSuperseded)
        coordinator.finish(targeted)

        let coalescing = coordinator.begin(kind: .apply, updatePolicy: .coalesceLatest)
        coordinator.supersedeActiveApply()
        XCTAssertTrue(coalescing.isSuperseded)
        coordinator.finish(coalescing)
    }

    func testSchedulerMarksActiveCoalescingApplyAsSupersededWhenLatestApplyQueues() {
        let scheduler = ListMutationScheduler()
        let active = scheduler.coordinator.begin(kind: .apply, updatePolicy: .coalesceLatest)

        scheduler.enqueue(ListPendingMutationRequest(
            kind: .apply,
            updatePolicy: .coalesceLatest,
            start: {},
            supersede: {}
        ))

        XCTAssertTrue(active.isSuperseded)
        scheduler.coordinator.finish(active)
    }

    func testMutationCoordinatorMergesCompatibleSectionReloads() {
        var executionCount = 0
        var executedSubscribers: [ListSectionReloadSubscriber] = []
        var firstCompletion: ListRefreshSummary?
        var secondCompletion: ListRefreshSummary?
        let execute: ([ListSectionReloadSubscriber], ListTransaction) -> Void = {
            subscribers, _ in
            executionCount += 1
            executedSubscribers = subscribers
            subscribers.forEach { subscriber in
                subscriber.completion?(ListRefreshSummary(
                    requestedTargetCount: subscriber.sectionIDs.count,
                    matchedTargetCount: subscriber.sectionIDs.count,
                    refreshMetrics: ListRefreshMetrics(
                        reloadedSectionCount: subscriber.sectionIDs.count
                    ),
                    animation: ListAnimationSummary(
                        completionState: .completed,
                        layoutInvalidated: true
                    )
                ))
            }
        }
        let first = ListPendingMutationRequest(
            sectionIDs: [AnyListID(0)],
            transaction: .automatic,
            completion: { firstCompletion = $0 },
            execute: execute
        )
        let second = ListPendingMutationRequest(
            sectionIDs: [AnyListID(1), AnyListID(1)],
            transaction: .automatic,
            completion: { secondCompletion = $0 },
            execute: execute
        )

        XCTAssertTrue(first.mergeCompatibleSectionReload(second))
        first.start()

        XCTAssertEqual(executionCount, 1)
        XCTAssertEqual(executedSubscribers.map(\.sectionIDs), [
            [AnyListID(0)],
            [AnyListID(1)]
        ])
        XCTAssertEqual(firstCompletion?.requestedTargetCount, 1)
        XCTAssertEqual(secondCompletion?.requestedTargetCount, 1)
        XCTAssertEqual(firstCompletion?.refreshMetrics.reloadedSectionCount, 1)
        XCTAssertEqual(secondCompletion?.refreshMetrics.reloadedSectionCount, 1)
    }

    func testTransactionResolvesAnimationScopesAndReduceMotion() {
        let transaction = ListTransaction()
            .snapshotAnimation(.enabled)
            .contentAnimation(.disabled)
            .updatePolicy(.serial)
            .scrollBehavior(.scrollTo(ListScrollTarget("message"), position: .bottom))

        let reduced = transaction.resolved(reduceMotionEnabled: true)
        XCTAssertTrue(reduced.snapshotAnimation)
        XCTAssertFalse(reduced.outlineAnimation)
        XCTAssertFalse(reduced.layoutAnimation)
        XCTAssertFalse(reduced.contentAnimation)
        XCTAssertFalse(reduced.scrollAnimation)
        XCTAssertEqual(reduced.updatePolicy, .serial)
        XCTAssertTrue(reduced.reduceMotionApplied)

        let forced = ListTransaction(animation: .enabled).resolved(reduceMotionEnabled: true)
        XCTAssertTrue(forced.snapshotAnimation)
        XCTAssertTrue(forced.outlineAnimation)
        XCTAssertTrue(forced.layoutAnimation)
        XCTAssertTrue(forced.contentAnimation)
        XCTAssertTrue(forced.scrollAnimation)
        XCTAssertFalse(forced.reduceMotionApplied)

        let ignoringReduceMotion = ListTransaction()
            .respectsReduceMotion(false)
            .resolved(reduceMotionEnabled: true)
        XCTAssertTrue(ignoringReduceMotion.snapshotAnimation)
        XCTAssertFalse(ignoringReduceMotion.reduceMotionApplied)
    }

    func testRowAnimationModifiersReachErasedDescriptors() {
        let row = Row(
            "row",
            model: "value",
            cell: UICollectionViewListCell.self
        ) { _, _, _ in }
            .contentTransition(.opacity(duration: 0.35))
            .outlineAnimation(.disabled)
            .eraseToAnyListRow(sectionID: "section")

        XCTAssertEqual(row.contentTransition, .opacity(duration: 0.35))
        XCTAssertEqual(row.outlineAnimation, .disabled)
    }

    func testCoalesceLatestSupersedesApplyDuringContentTransition() async throws {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 320, height: 60)
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            collectionViewLayout: layout
        )
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        let host = UIViewController()
        host.view.frame = collectionView.bounds
        host.view.addSubview(collectionView)
        let window = UIWindow(frame: collectionView.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        _ = await adapter.apply(
            options: .init(transaction: .disabled, applicationMode: .reloadData)
        ) {
            ListSection(0) {
                Row("row", model: "A", cell: NormalUserCell.self) { cell, value, _ in
                    cell.name = value
                }
                .refreshID(1)
                .refresh(when: .automatic)
            }
            ListSection(1) {
                Row("side", model: "Side", cell: NormalUserCell.self) { _, _, _ in }
            }
        }
        collectionView.layoutIfNeeded()
        _ = try XCTUnwrap(collectionView.cellForItem(at: IndexPath(item: 0, section: 0)))

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(true)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        let transitionStarted = expectation(description: "first content transition started")
        var didSignalTransition = false
        let firstApply = Task { @MainActor in
            await adapter.apply(
                transaction: ListTransaction(animation: .disabled).contentAnimation(.enabled)
            ) {
                ListSection(0) {
                    Row("row", model: "B", cell: NormalUserCell.self) { cell, value, _ in
                        cell.name = value
                        if !didSignalTransition {
                            didSignalTransition = true
                            transitionStarted.fulfill()
                        }
                    }
                    .refreshID(2)
                    .refresh(when: .automatic)
                    // Keep the first mutation active long enough for this test to enqueue
                    // the coalescing apply even when the full scheme is under UI-test load.
                    .contentTransition(.opacity(duration: 2))
                }
            }
        }

        await fulfillment(of: [transitionStarted], timeout: 2)
        let latestResult = await adapter.apply(transaction: .disabled) {
            ListSection(0) {
                Row("row", model: "C", cell: NormalUserCell.self) { cell, value, _ in
                    cell.name = value
                }
                .refreshID(3)
                .refresh(when: .automatic)
            }
            ListSection(1) {
                Row("side", model: "Side", cell: NormalUserCell.self) { _, _, _ in }
            }
        }
        let supersededResult = await firstApply.value

        // UIKit may complete a test-host content transition before the awaiting task gets
        // another MainActor turn. The scheduler-level test above deterministically covers
        // the active-apply supersede boundary; this integration test verifies final state.
        XCTAssertTrue(
            [.completed, .superseded].contains(supersededResult.animation.completionState)
        )
        XCTAssertEqual(latestResult.animation.completionState, .completed)
        XCTAssertEqual(latestResult.insertedSectionCount, 1)
        XCTAssertEqual(collectionView.numberOfSections, 2)
        XCTAssertEqual(adapter.sectionIdentifier(at: 1), 1)
        XCTAssertEqual(adapter.lastApplySummary, latestResult)
    }

    func testSerialCollectionApplyCompletesSectionDeletionBeforeReinsertion() async throws {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 320, height: 60)
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            collectionViewLayout: layout
        )
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        let host = UIViewController()
        host.view.frame = collectionView.bounds
        host.view.addSubview(collectionView)
        let window = UIWindow(frame: collectionView.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        _ = await adapter.apply(
            options: .init(transaction: .disabled, applicationMode: .reloadData)
        ) {
            ListSection(0) {
                Row("row", model: "A", cell: NormalUserCell.self) { cell, value, _ in
                    cell.name = value
                }
                .refreshID(1)
                .refresh(when: .automatic)
            }
            ListSection(1) {
                Row("side", model: "Side", cell: NormalUserCell.self) { _, _, _ in }
            }
        }
        collectionView.layoutIfNeeded()
        _ = try XCTUnwrap(collectionView.cellForItem(at: IndexPath(item: 0, section: 0)))

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(true)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        let transitionStarted = expectation(description: "serial collection transition started")
        var didSignalTransition = false
        let serialTransaction = ListTransaction(animation: .disabled)
            .contentAnimation(.enabled)
            .updatePolicy(.serial)
        let deletionApply = Task { @MainActor in
            await adapter.apply(transaction: serialTransaction) {
                ListSection(0) {
                    Row("row", model: "B", cell: NormalUserCell.self) { cell, value, _ in
                        cell.name = value
                        if !didSignalTransition {
                            didSignalTransition = true
                            transitionStarted.fulfill()
                        }
                    }
                    .refreshID(2)
                    .refresh(when: .automatic)
                    .contentTransition(.opacity(duration: 0.35))
                }
            }
        }

        await fulfillment(of: [transitionStarted], timeout: 2)
        let reinsertionApply = Task { @MainActor in
            await adapter.apply(
                transaction: ListTransaction.disabled.updatePolicy(.serial)
            ) {
                ListSection(0) {
                    Row("row", model: "C", cell: NormalUserCell.self) { cell, value, _ in
                        cell.name = value
                    }
                    .refreshID(3)
                    .refresh(when: .automatic)
                }
                ListSection(1) {
                    Row("side", model: "Side", cell: NormalUserCell.self) { _, _, _ in }
                }
            }
        }

        let deletionResult = await deletionApply.value
        let reinsertionResult = await reinsertionApply.value

        XCTAssertEqual(deletionResult.animation.completionState, .completed)
        XCTAssertEqual(deletionResult.deletedSectionCount, 1)
        XCTAssertEqual(reinsertionResult.animation.completionState, .completed)
        XCTAssertEqual(reinsertionResult.insertedSectionCount, 1)
        XCTAssertEqual(collectionView.numberOfSections, 2)
        XCTAssertEqual(adapter.sectionIdentifier(at: 1), 1)
    }

    func testVisibleOnlyRefreshesCollectionRowWhenRefreshIDChanges() async throws {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 320, height: 60)
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            collectionViewLayout: layout
        )
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        let host = UIViewController()
        host.view.frame = collectionView.bounds
        host.view.addSubview(collectionView)
        let window = UIWindow(frame: collectionView.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        _ = await adapter.apply(
            options: .init(transaction: .disabled, applicationMode: .reloadData)
        ) {
            ListSection(0) {
                Row("row", model: "A", cell: NormalUserCell.self) { cell, value, _ in
                    cell.name = value
                }
                .refreshID(1)
                .refresh(when: .refreshIDChanges)
            }
        }
        collectionView.layoutIfNeeded()
        let cell = try XCTUnwrap(
            collectionView.cellForItem(at: IndexPath(item: 0, section: 0)) as? NormalUserCell
        )

        let result = await adapter.apply(
            options: .init(transaction: .disabled)
        ) {
            ListSection(0) {
                Row("row", model: "B", cell: NormalUserCell.self) { cell, value, _ in
                    cell.name = value
                }
                .refreshID(2)
                .refresh(when: .refreshIDChanges)
            }
        }

        XCTAssertEqual(result.rowRefreshIDChangedCount, 1)
        XCTAssertEqual(result.refreshMetrics.snapshotReconfiguredRowCount, 0)
        XCTAssertEqual(result.refreshMetrics.visibleReconfiguredRowCount, 1)
        XCTAssertEqual(cell.name, "B")
    }

    func testCollectionReloadAllRefreshesStableNeverRowAndHeaderAndInvalidatesLayout() async throws {
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            collectionViewLayout: UICollectionViewFlowLayout()
        )
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        let host = UIViewController()
        host.view.frame = collectionView.bounds
        host.view.addSubview(collectionView)
        let window = UIWindow(frame: collectionView.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        var rowText = "English"
        var headerText = "People"
        _ = await adapter.apply(
            options: .init(transaction: .disabled, applicationMode: .reloadData)
        ) {
            ListSection(0) {
                Row("row", model: "stable", cell: NormalUserCell.self) { cell, _, _ in
                    cell.name = rowText
                }
                .refreshID(1)
                .refresh(when: .never)
            } header: {
                Header(HeaderView.self, id: "header") { view, _ in
                    view.title = headerText
                }
                .refreshID(1)
                .refresh(when: .never)
                .layout(height: .absolute(32))
            }
        }
        collectionView.collectionViewLayout = adapter.makeCompositionalLayout()
        collectionView.reloadData()
        collectionView.layoutIfNeeded()

        let indexPath = IndexPath(item: 0, section: 0)
        let stableIdentity = try XCTUnwrap(adapter.itemIdentity(at: indexPath))
        XCTAssertEqual(
            (collectionView.cellForItem(at: indexPath) as? NormalUserCell)?.name,
            "English"
        )
        XCTAssertEqual(
            collectionView.visibleSupplementaryViews(
                ofKind: UICollectionView.elementKindSectionHeader
            ).compactMap { $0 as? HeaderView }.first?.title,
            "People"
        )

        rowText = "Arabic"
        headerText = "Users"
        let baselineLayoutGeneration = adapter.layoutInvalidationGeneration
        let reloadCompleted = expectation(description: "collection reload all")
        var completedSummary: ListApplySummary?
        let submittedResult = adapter.reloadAll(
            transaction: .disabled,
            transition: .identity
        ) { summary in
            completedSummary = summary
            reloadCompleted.fulfill()
        }

        XCTAssertEqual(submittedResult.animation.completionState, .submitted)
        await fulfillment(of: [reloadCompleted], timeout: 2)
        collectionView.layoutIfNeeded()

        XCTAssertEqual(completedSummary?.animation.completionState, .completed)
        XCTAssertEqual(completedSummary?.animation.layoutInvalidated, true)
        XCTAssertEqual(completedSummary?.rowRefreshIDChangedCount, 0)
        XCTAssertEqual(completedSummary?.supplementaryRefreshIDChangedCount, 0)
        XCTAssertEqual(completedSummary?.refreshMetrics.snapshotReconfiguredRowCount, 0)
        XCTAssertEqual(completedSummary?.refreshMetrics.visibleReconfiguredRowCount, 1)
        XCTAssertEqual(completedSummary?.refreshMetrics.visibleReconfiguredSupplementaryCount, 1)
        XCTAssertEqual(adapter.layoutInvalidationGeneration, baselineLayoutGeneration + 1)
        XCTAssertEqual(adapter.itemIdentity(at: indexPath), stableIdentity)
        XCTAssertEqual(
            (collectionView.cellForItem(at: indexPath) as? NormalUserCell)?.name,
            "Arabic"
        )
        XCTAssertEqual(
            collectionView.visibleSupplementaryViews(
                ofKind: UICollectionView.elementKindSectionHeader
            ).compactMap { $0 as? HeaderView }.first?.title,
            "Users"
        )
    }

    func testCollectionTargetedRefreshesStableNeverRowAndSectionContent() async throws {
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            collectionViewLayout: UICollectionViewFlowLayout()
        )
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        let host = UIViewController()
        host.view.frame = collectionView.bounds
        host.view.addSubview(collectionView)
        let window = UIWindow(frame: collectionView.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        var rowText = "Initial row"
        var headerText = "Initial header"
        _ = await adapter.apply(
            options: .init(transaction: .disabled, applicationMode: .reloadData)
        ) {
            ListSection(0) {
                Row("row", model: "stable", cell: NormalUserCell.self) { cell, _, _ in
                    cell.name = rowText
                }
                .refreshID(1)
                .refresh(when: .never)
            } header: {
                Header(HeaderView.self, id: "header") { view, _ in
                    view.title = headerText
                }
                .refreshID(1)
                .refresh(when: .never)
                .layout(height: .absolute(32))
            }
        }
        collectionView.collectionViewLayout = adapter.makeCompositionalLayout()
        collectionView.reloadData()
        collectionView.layoutIfNeeded()

        let indexPath = IndexPath(item: 0, section: 0)
        let stableIdentity = try XCTUnwrap(adapter.itemIdentity(at: indexPath))
        let initialCell = try XCTUnwrap(
            collectionView.cellForItem(at: indexPath) as? NormalUserCell
        )
        let baselinePrepareForReuseCount = initialCell.prepareForReuseCount
        let baselineLayoutGeneration = adapter.layoutInvalidationGeneration

        rowText = "Reconfigured row"
        let reconfigureCompleted = expectation(description: "targeted row reconfigure")
        let reconfigureSubmission = adapter.reconfigureRows(
            forRowIDs: ["row", "row", "missing"],
            in: 0,
            transaction: .disabled
        ) { summary in
            XCTAssertEqual(summary.matchedTargetCount, 1)
            XCTAssertEqual(summary.refreshMetrics.snapshotReconfiguredRowCount, 1)
            XCTAssertEqual(summary.refreshMetrics.visibleReconfiguredRowCount, 0)
            reconfigureCompleted.fulfill()
        }
        XCTAssertEqual(reconfigureSubmission.requestedTargetCount, 2)
        XCTAssertEqual(reconfigureSubmission.animation.completionState, .submitted)
        await fulfillment(of: [reconfigureCompleted], timeout: 2)
        collectionView.layoutIfNeeded()

        let reconfiguredCell = try XCTUnwrap(
            collectionView.cellForItem(at: indexPath) as? NormalUserCell
        )
        XCTAssertTrue(reconfiguredCell === initialCell)
        XCTAssertEqual(reconfiguredCell.prepareForReuseCount, baselinePrepareForReuseCount)
        XCTAssertEqual(reconfiguredCell.name, "Reconfigured row")
        XCTAssertEqual(adapter.itemIdentity(at: indexPath), stableIdentity)
        XCTAssertEqual(adapter.layoutInvalidationGeneration, baselineLayoutGeneration)

        let layoutRefreshCompleted = expectation(description: "targeted row layout invalidation")
        _ = adapter.reconfigureRows(
            forRowID: "row",
            in: 0,
            layout: .invalidate,
            transaction: .disabled
        ) { summary in
            XCTAssertTrue(summary.animation.layoutInvalidated)
            XCTAssertEqual(summary.refreshMetrics.snapshotReconfiguredRowCount, 1)
            XCTAssertEqual(summary.refreshMetrics.visibleReconfiguredRowCount, 0)
            layoutRefreshCompleted.fulfill()
        }
        await fulfillment(of: [layoutRefreshCompleted], timeout: 2)
        XCTAssertEqual(adapter.layoutInvalidationGeneration, baselineLayoutGeneration + 1)

        rowText = "Reloaded row"
        let reloadRowCompleted = expectation(description: "targeted row reload")
        let reloadSubmission = adapter.reloadRows(
            forRowID: "row",
            in: 0,
            transaction: .disabled
        ) { summary in
            XCTAssertEqual(summary.refreshMetrics.reloadedRowCount, 1)
            XCTAssertEqual(summary.refreshMetrics.reloadedSectionCount, 0)
            reloadRowCompleted.fulfill()
        }
        XCTAssertEqual(reloadSubmission.animation.completionState, .submitted)
        await fulfillment(of: [reloadRowCompleted], timeout: 2)
        collectionView.layoutIfNeeded()

        XCTAssertEqual(
            (collectionView.cellForItem(at: indexPath) as? NormalUserCell)?.name,
            "Reloaded row"
        )
        XCTAssertEqual(adapter.itemIdentity(at: indexPath), stableIdentity)

        rowText = "Section row"
        headerText = "Section header"
        let reloadSectionCompleted = expectation(description: "targeted section reload")
        let sectionReloadSubmission = adapter.reloadSections(
            [0, 0, 99],
            transaction: .disabled
        ) { summary in
            XCTAssertEqual(summary.matchedTargetCount, 1)
            XCTAssertEqual(summary.refreshMetrics.reloadedRowCount, 0)
            XCTAssertEqual(summary.refreshMetrics.reloadedSectionCount, 1)
            reloadSectionCompleted.fulfill()
        }
        XCTAssertEqual(sectionReloadSubmission.requestedTargetCount, 2)
        XCTAssertEqual(sectionReloadSubmission.animation.completionState, .submitted)
        await fulfillment(of: [reloadSectionCompleted], timeout: 2)
        collectionView.layoutIfNeeded()

        XCTAssertEqual(
            (collectionView.cellForItem(at: indexPath) as? NormalUserCell)?.name,
            "Section row"
        )
        XCTAssertEqual(
            collectionView.visibleSupplementaryViews(
                ofKind: UICollectionView.elementKindSectionHeader
            ).compactMap { $0 as? HeaderView }.first?.title,
            "Section header"
        )
        XCTAssertEqual(adapter.itemIdentity(at: indexPath), stableIdentity)
    }

    func testCollectionAsyncReloadAllPreservesRuntimeExpandedOutlineState() async throws {
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            collectionViewLayout: UICollectionViewFlowLayout()
        )
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        let host = UIViewController()
        host.view.frame = collectionView.bounds
        host.view.addSubview(collectionView)
        let window = UIWindow(frame: collectionView.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        _ = await adapter.apply(
            options: .init(transaction: .disabled, applicationMode: .reloadData)
        ) {
            ListSection(0) {
                DisclosureGroup(
                    Row("parent", model: "Parent", cell: UICollectionViewListCell.self) { _, _, _ in }
                        .outlineDisclosure()
                        .outlineAnimation(.disabled),
                    isExpanded: false
                ) {
                    Row("child", model: "Child", cell: UICollectionViewListCell.self) { _, _, _ in }
                }
            }
        }
        collectionView.collectionViewLayout = adapter.makeCompositionalLayout()
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        XCTAssertNil(collectionView.cellForItem(at: IndexPath(item: 1, section: 0)))

        adapter.collectionView(
            collectionView,
            didSelectItemAt: IndexPath(item: 0, section: 0)
        )
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
        collectionView.layoutIfNeeded()

        let childIndexPath = IndexPath(item: 1, section: 0)
        let childIdentity = try XCTUnwrap(adapter.itemIdentity(at: childIndexPath))
        XCTAssertNotNil(collectionView.cellForItem(at: childIndexPath))

        let result = await adapter.reloadAll(
            transaction: .disabled,
            transition: .identity
        )
        collectionView.layoutIfNeeded()

        XCTAssertEqual(result.animation.completionState, .completed)
        XCTAssertTrue(result.animation.layoutInvalidated)
        XCTAssertEqual(adapter.itemIdentity(at: childIndexPath), childIdentity)
        XCTAssertNotNil(collectionView.cellForItem(at: childIndexPath))
    }

    func testCollectionApplyDeletesEntireSectionAndClearsIdentityHistory() async throws {
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            collectionViewLayout: UICollectionViewFlowLayout()
        )
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)

        _ = await adapter.apply(
            options: .init(transaction: .disabled, applicationMode: .reloadData)
        ) {
            ListSection(10) {
                Row("kept", model: "Kept", cell: NormalUserCell.self) { _, _, _ in }
                    .refreshID(1)
                    .refresh(when: .refreshIDChanges)
            }
            ListSection(20) {
                Row("removed", model: "Removed", cell: NormalUserCell.self) { _, _, _ in }
                    .refreshID(1)
                    .refresh(when: .refreshIDChanges)
            }
        }
        let removedIdentity = try XCTUnwrap(
            adapter.itemIdentity(at: IndexPath(item: 0, section: 1))
        )

        let deletionResult = await adapter.apply(transaction: .disabled) {
            ListSection(10) {
                Row("kept", model: "Kept", cell: NormalUserCell.self) { _, _, _ in }
                    .refreshID(1)
                    .refresh(when: .refreshIDChanges)
            }
        }

        XCTAssertEqual(deletionResult.animation.completionState, .completed)
        XCTAssertEqual(deletionResult.deletedSectionCount, 1)
        XCTAssertEqual(deletionResult.keptSectionCount, 1)
        XCTAssertEqual(deletionResult.deletedRowCount, 1)
        XCTAssertEqual(deletionResult.keptRowCount, 1)
        XCTAssertEqual(deletionResult.rowRefreshIDChangedCount, 0)
        XCTAssertEqual(collectionView.numberOfSections, 1)
        XCTAssertEqual(adapter.sectionIdentifier(at: 0), 10)
        XCTAssertNil(adapter.sectionIdentifier(at: 1))
        XCTAssertNil(adapter.sectionIndex(for: 20))
        XCTAssertEqual(adapter.itemCount(in: 20), 0)
        XCTAssertTrue(adapter.indexPaths(forRowID: "removed", in: 20).isEmpty)
        XCTAssertFalse(adapter.contains(removedIdentity))

        let reinsertionResult = await adapter.apply(transaction: .disabled) {
            ListSection(10) {
                Row("kept", model: "Kept", cell: NormalUserCell.self) { _, _, _ in }
                    .refreshID(1)
                    .refresh(when: .refreshIDChanges)
            }
            ListSection(20) {
                Row("removed", model: "Reinserted", cell: NormalUserCell.self) { _, _, _ in }
                    .refreshID(2)
                    .refresh(when: .refreshIDChanges)
            }
        }

        XCTAssertEqual(reinsertionResult.animation.completionState, .completed)
        XCTAssertEqual(reinsertionResult.insertedSectionCount, 1)
        XCTAssertEqual(reinsertionResult.keptSectionCount, 1)
        XCTAssertEqual(reinsertionResult.insertedRowCount, 1)
        XCTAssertEqual(reinsertionResult.rowRefreshIDChangedCount, 0)
        XCTAssertEqual(collectionView.numberOfSections, 2)
        XCTAssertEqual(adapter.sectionIndex(for: 20), 1)
        XCTAssertEqual(
            adapter.indexPaths(forRowID: "removed", in: 20),
            [IndexPath(item: 0, section: 1)]
        )
    }

    func testCollectionEmptySectionChangesDriveSnapshotAnimationSummary() async {
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            collectionViewLayout: UICollectionViewFlowLayout()
        )
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)

        _ = await adapter.apply(
            options: .init(transaction: .disabled, applicationMode: .reloadData)
        ) {
            ListSection(0) {}
            ListSection(1) {}
        }

        let reorderResult = await adapter.apply(
            transaction: ListTransaction(animation: .enabled)
        ) {
            ListSection(1) {}
            ListSection(0) {}
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
            ListSection(0) {}
        }

        XCTAssertEqual(deleteLeadingResult.deletedSectionCount, 1)
        XCTAssertEqual(deleteLeadingResult.deletedRowCount, 0)
        XCTAssertTrue(deleteLeadingResult.animation.snapshotAnimated)
        XCTAssertEqual(deleteLeadingResult.animation.animatedSectionCount, 1)
        XCTAssertTrue(deleteLeadingResult.animation.layoutInvalidated)
        XCTAssertEqual(collectionView.numberOfSections, 1)
        XCTAssertEqual(adapter.sectionIdentifier(at: 0), 0)

        let noSections: [ListSection<Int>] = []
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
        XCTAssertEqual(collectionView.numberOfSections, 0)
    }

    func testCollectionDeletesLeadingAndMiddleSectionsTogether() async {
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            collectionViewLayout: UICollectionViewFlowLayout()
        )
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)

        _ = await adapter.apply(
            options: .init(transaction: .disabled, applicationMode: .reloadData)
        ) {
            ListSection(0) {
                Row("zero", model: "Zero", cell: NormalUserCell.self) { _, _, _ in }
            }
            ListSection(1) {
                Row("one", model: "One", cell: NormalUserCell.self) { _, _, _ in }
            }
            ListSection(2) {
                Row("two", model: "Two", cell: NormalUserCell.self) { _, _, _ in }
            }
        }

        let result = await adapter.apply(transaction: .disabled) {
            ListSection(2) {
                Row("two", model: "Two", cell: NormalUserCell.self) { _, _, _ in }
            }
        }

        XCTAssertEqual(result.deletedSectionCount, 2)
        XCTAssertEqual(result.keptSectionCount, 1)
        XCTAssertEqual(result.deletedRowCount, 2)
        XCTAssertEqual(result.keptRowCount, 1)
        XCTAssertEqual(collectionView.numberOfSections, 1)
        XCTAssertEqual(adapter.sectionIdentifier(at: 0), 2)
        XCTAssertEqual(adapter.indexPaths(forRowID: "two", in: 2), [IndexPath(item: 0, section: 0)])
        XCTAssertTrue(adapter.indexPaths(forRowID: "zero").isEmpty)
        XCTAssertTrue(adapter.indexPaths(forRowID: "one").isEmpty)
    }

    func testCollectionPreservesSelectionAndFocusIdentityWhenLeadingSectionIsDeleted() async throws {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 300, height: 44)
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            collectionViewLayout: layout
        )
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        let host = UIViewController()
        host.view.frame = collectionView.bounds
        host.view.addSubview(collectionView)
        let window = UIWindow(frame: collectionView.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        _ = await adapter.apply(
            options: .init(transaction: .disabled, applicationMode: .reloadData)
        ) {
            ListSection(0) {
                Row("removed", model: "Removed", cell: NormalUserCell.self) { _, _, _ in }
            }
            .selectionMode(.single)
            ListSection(1) {
                Row("selected", model: "Selected", cell: NormalUserCell.self) { _, _, _ in }
                    .focusable()
            }
            .selectionMode(.single)
        }
        collectionView.layoutIfNeeded()
        collectionView.selectItem(at: IndexPath(item: 0, section: 1), animated: false, scrollPosition: [])
        let selectedIdentity = try XCTUnwrap(adapter.itemIdentity(at: IndexPath(item: 0, section: 1)))

        _ = await adapter.apply(transaction: .disabled) {
            ListSection(1) {
                Row("selected", model: "Selected", cell: NormalUserCell.self) { _, _, _ in }
                    .focusable()
            }
            .selectionMode(.single)
        }

        let shiftedIndexPath = try XCTUnwrap(collectionView.indexPathsForSelectedItems?.first)
        XCTAssertEqual(shiftedIndexPath, IndexPath(item: 0, section: 0))
        XCTAssertEqual(adapter.itemIdentity(at: shiftedIndexPath), selectedIdentity)
        XCTAssertTrue(adapter.collectionView(collectionView, canFocusItemAt: shiftedIndexPath))

        let noSections: [ListSection<Int>] = []
        _ = await adapter.apply(transaction: .disabled) {
            noSections
        }

        XCTAssertTrue(collectionView.indexPathsForSelectedItems?.isEmpty ?? true)
        XCTAssertFalse(collectionView.allowsSelection)
    }

    func testCollectionSectionDeletionPreservesOrReleasesVisibleAnchor() async throws {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 300, height: 44)
        layout.minimumLineSpacing = 0
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 220),
            collectionViewLayout: layout
        )
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)

        func section(_ id: Int, rows: Range<Int>) -> ListSection<Int> {
            ListSection(id) {
                ForEach(rows, id: \.self) { row in
                    Row("\(id)-\(row)", model: row, cell: NormalUserCell.self) { _, _, _ in }
                }
            }
        }

        _ = await adapter.apply(
            options: .init(transaction: .disabled, applicationMode: .reloadData)
        ) {
            section(0, rows: 0..<3)
            section(1, rows: 0..<6)
            ListSection(2) {
                Row("anchor", model: 0, cell: NormalUserCell.self) { _, _, _ in }
                ForEach(1..<6, id: \.self) { row in
                    Row("anchor-trailing-\(row)", model: row, cell: NormalUserCell.self) { _, _, _ in }
                }
            }
        }
        collectionView.layoutIfNeeded()
        let initialAnchorPath = try XCTUnwrap(adapter.indexPaths(forRowID: "anchor", in: 2).first)
        let initialAttributes = try XCTUnwrap(layout.layoutAttributesForItem(at: initialAnchorPath))
        collectionView.setContentOffset(
            CGPoint(x: 0, y: initialAttributes.frame.minY - 80),
            animated: false
        )
        collectionView.layoutIfNeeded()
        let initialViewportY = initialAttributes.frame.minY - collectionView.contentOffset.y

        let preserveResult = await adapter.apply(
            transaction: ListTransaction.disabled.scrollBehavior(
                .preserveVisiblePosition(of: ListScrollTarget("anchor", in: 2))
            )
        ) {
            section(1, rows: 0..<6)
            ListSection(2) {
                Row("anchor", model: 0, cell: NormalUserCell.self) { _, _, _ in }
                ForEach(1..<6, id: \.self) { row in
                    Row("anchor-trailing-\(row)", model: row, cell: NormalUserCell.self) { _, _, _ in }
                }
            }
        }
        collectionView.layoutIfNeeded()
        let shiftedAnchorPath = try XCTUnwrap(adapter.indexPaths(forRowID: "anchor", in: 2).first)
        let shiftedAttributes = try XCTUnwrap(layout.layoutAttributesForItem(at: shiftedAnchorPath))

        XCTAssertEqual(
            shiftedAttributes.frame.minY - collectionView.contentOffset.y,
            initialViewportY,
            accuracy: 0.5
        )
        XCTAssertEqual(preserveResult.animation.anchorCompensation, 0, accuracy: 0.5)
        XCTAssertEqual(collectionView.contentInset.bottom, 0, accuracy: 0.5)

        let removeAnchorResult = await adapter.apply(
            transaction: ListTransaction.disabled.scrollBehavior(
                .preserveVisiblePosition(of: ListScrollTarget("anchor", in: 2))
            )
        ) {
            section(1, rows: 0..<6)
        }

        XCTAssertEqual(removeAnchorResult.deletedSectionCount, 1)
        XCTAssertEqual(removeAnchorResult.animation.anchorCompensation, 0, accuracy: 0.5)
        XCTAssertEqual(collectionView.contentInset.bottom, 0, accuracy: 0.5)
        XCTAssertTrue(adapter.indexPaths(forRowID: "anchor", in: 2).isEmpty)
    }

    func testCollectionDeletesAndReinsertsOutlineSectionWithSupplementary() async {
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            collectionViewLayout: UICollectionViewFlowLayout()
        )
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)

        func outlineSection(headerVersion: Int) -> ListSection<Int> {
            let header: ListSectionSupplementary<Int> = SectionSupplementary(
                UICollectionView.elementKindSectionHeader,
                HeaderView.self,
                id: "outline-header"
            ) { view, _ in
                view.title = "Header \(headerVersion)"
            }
            .refreshID(headerVersion)
            .refresh(when: .refreshIDChanges)

            return ListSection(1) {
                DisclosureGroup(
                    Row("parent", model: "Parent", cell: UICollectionViewListCell.self) { _, _, _ in }
                        .outlineDisclosure(),
                    isExpanded: true
                ) {
                    Row("child", model: "Child", cell: UICollectionViewListCell.self) { _, _, _ in }
                }
            } supplementaries: {
                header
            }
            .boundarySupplementaryLayout(
                kind: UICollectionView.elementKindSectionHeader,
                height: .absolute(32)
            )
        }

        _ = await adapter.apply(
            options: .init(transaction: .disabled, applicationMode: .reloadData)
        ) {
            ListSection(0) {
                Row("stable", model: "Stable", cell: NormalUserCell.self) { _, _, _ in }
            }
            outlineSection(headerVersion: 1)
        }

        let deleteResult = await adapter.apply(
            transaction: ListTransaction(animation: .enabled)
        ) {
            ListSection(0) {
                Row("stable", model: "Stable", cell: NormalUserCell.self) { _, _, _ in }
            }
        }

        XCTAssertEqual(deleteResult.deletedSectionCount, 1)
        XCTAssertEqual(deleteResult.deletedRowCount, 2)
        XCTAssertEqual(deleteResult.animation.outlineAnimatedSectionCount, 0)
        XCTAssertTrue(deleteResult.animation.layoutInvalidated)
        XCTAssertEqual(collectionView.numberOfSections, 1)

        let reinsertResult = await adapter.apply(
            transaction: ListTransaction(animation: .enabled)
        ) {
            ListSection(0) {
                Row("stable", model: "Stable", cell: NormalUserCell.self) { _, _, _ in }
            }
            outlineSection(headerVersion: 2)
        }

        XCTAssertEqual(reinsertResult.insertedSectionCount, 1)
        XCTAssertEqual(reinsertResult.insertedRowCount, 2)
        XCTAssertEqual(reinsertResult.supplementaryRefreshIDChangedCount, 0)
        XCTAssertEqual(reinsertResult.animation.outlineAnimatedSectionCount, 1)
        XCTAssertTrue(reinsertResult.animation.layoutInvalidated)
        XCTAssertEqual(adapter.indexPaths(forRowID: "parent", in: 1), [IndexPath(item: 0, section: 1)])
        XCTAssertEqual(adapter.indexPaths(forRowID: "child", in: 1), [IndexPath(item: 1, section: 1)])
    }

    func testApplyPlannerReportsMovesAndChangedSections() {
        let first = makeTestListNode("first", refreshID: 1)
        let second = makeTestListNode("second", refreshID: 1)
        let plan = ListApplyPlanner.makePlan(
            old: [ListSectionSnapshot(sectionID: AnyListID(0), rows: [first, second], supplementaries: [])],
            new: [ListSectionSnapshot(sectionID: AnyListID(0), rows: [second, first], supplementaries: [])],
            options: ListApplyOptions(transaction: .disabled, diagnostics: .disabled),
            diagnosticsIssues: []
        )

        XCTAssertEqual(plan.initialSummary.movedRowCount, 1)
        XCTAssertEqual(plan.initialSummary.movedSectionCount, 0)
        XCTAssertEqual(plan.initialSummary.keptSectionCount, 1)
        XCTAssertEqual(plan.changedSectionCount, 1)
    }

    func testApplyPlannerTracksEmptySectionInsertionDeletionAndReordering() {
        let insertionAndDeletion = ListApplyPlanner.makePlan(
            old: [
                ListSectionSnapshot(sectionID: AnyListID(0), rows: [], supplementaries: []),
                ListSectionSnapshot(sectionID: AnyListID(1), rows: [], supplementaries: [])
            ],
            new: [
                ListSectionSnapshot(sectionID: AnyListID(0), rows: [], supplementaries: []),
                ListSectionSnapshot(sectionID: AnyListID(2), rows: [], supplementaries: [])
            ],
            options: ListApplyOptions(transaction: .disabled, diagnostics: .disabled),
            diagnosticsIssues: []
        )

        XCTAssertEqual(insertionAndDeletion.initialSummary.insertedSectionCount, 1)
        XCTAssertEqual(insertionAndDeletion.initialSummary.deletedSectionCount, 1)
        XCTAssertEqual(insertionAndDeletion.initialSummary.movedSectionCount, 0)
        XCTAssertEqual(insertionAndDeletion.initialSummary.keptSectionCount, 1)
        XCTAssertEqual(insertionAndDeletion.initialSummary.insertedRowCount, 0)
        XCTAssertEqual(insertionAndDeletion.initialSummary.deletedRowCount, 0)
        XCTAssertEqual(insertionAndDeletion.changedSectionCount, 2)
        XCTAssertTrue(insertionAndDeletion.hasSnapshotChanges)

        let reordering = ListApplyPlanner.makePlan(
            old: [
                ListSectionSnapshot(sectionID: AnyListID(0), rows: [], supplementaries: []),
                ListSectionSnapshot(sectionID: AnyListID(1), rows: [], supplementaries: [])
            ],
            new: [
                ListSectionSnapshot(sectionID: AnyListID(1), rows: [], supplementaries: []),
                ListSectionSnapshot(sectionID: AnyListID(0), rows: [], supplementaries: [])
            ],
            options: ListApplyOptions(transaction: .disabled, diagnostics: .disabled),
            diagnosticsIssues: []
        )

        XCTAssertEqual(reordering.initialSummary.insertedSectionCount, 0)
        XCTAssertEqual(reordering.initialSummary.deletedSectionCount, 0)
        XCTAssertEqual(reordering.initialSummary.movedSectionCount, 1)
        XCTAssertEqual(reordering.initialSummary.keptSectionCount, 2)
        XCTAssertEqual(reordering.initialSummary.movedRowCount, 0)
        XCTAssertEqual(reordering.changedSectionCount, 1)
        XCTAssertTrue(reordering.hasSnapshotChanges)
    }

    func testApplyPlannerTreatsRowRehomedToAnotherSectionAsDeleteAndInsert() {
        let oldRow = makeTestListNode("row", refreshID: 1, sectionID: 0)
        let rehomedRow = makeTestListNode("row", refreshID: 1, sectionID: 1)
        let plan = ListApplyPlanner.makePlan(
            old: [
                ListSectionSnapshot(sectionID: AnyListID(0), rows: [oldRow], supplementaries: []),
                ListSectionSnapshot(sectionID: AnyListID(1), rows: [], supplementaries: [])
            ],
            new: [
                ListSectionSnapshot(sectionID: AnyListID(0), rows: [], supplementaries: []),
                ListSectionSnapshot(sectionID: AnyListID(1), rows: [rehomedRow], supplementaries: [])
            ],
            options: ListApplyOptions(transaction: .disabled, diagnostics: .disabled),
            diagnosticsIssues: []
        )

        XCTAssertEqual(plan.initialSummary.insertedRowCount, 1)
        XCTAssertEqual(plan.initialSummary.deletedRowCount, 1)
        XCTAssertEqual(plan.initialSummary.movedRowCount, 0)
        XCTAssertEqual(plan.initialSummary.movedSectionCount, 0)
        XCTAssertEqual(plan.changedSectionCount, 2)
    }

    func testApplyWithoutScrollBehaviorDoesNotCreateAnchorInset() async {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 300, height: 44)
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            collectionViewLayout: layout
        )
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)

        let result = await adapter.apply(transaction: .disabled) {
            ListSection(0) {
                Row("only", model: "Only", cell: NormalUserCell.self) { _, _, _ in }
            }
        }

        XCTAssertEqual(result.animation.anchorCompensation, 0)
        XCTAssertEqual(collectionView.contentInset.bottom, 0)
    }

    func testPreservingVisibleRowInShortCollectionDoesNotCreateAnchorInset() async {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 300, height: 44)
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            collectionViewLayout: layout
        )
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)

        _ = await adapter.apply(transaction: .disabled) {
            ListSection(0) {
                Row("anchor", model: "Anchor", cell: NormalUserCell.self) { _, _, _ in }
            }
        }
        collectionView.layoutIfNeeded()

        let result = await adapter.apply(
            transaction: ListTransaction.disabled.scrollBehavior(
                .preserveVisiblePosition(of: ListScrollTarget("anchor", in: 0))
            )
        ) {
            ListSection(0) {
                Row("anchor", model: "Anchor", cell: NormalUserCell.self) { _, _, _ in }
                Row("trailing", model: "Trailing", cell: NormalUserCell.self) { _, _, _ in }
            }
        }

        XCTAssertEqual(result.animation.anchorCompensation, 0)
        XCTAssertEqual(collectionView.contentInset.bottom, 0)
    }

    func testAsyncApplyPreservesVisibleRowPositionWhenTrailingContentShrinks() async throws {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 300, height: 60)
        layout.minimumLineSpacing = 0
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            collectionViewLayout: layout
        )
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)

        func sections(activityCount: Int) -> [ListSection<Int>] {
            ListSectionsBuilder<Int>.build {
                ListSection(0) {
                    ForEach(0..<5, id: \.self) { index in
                        Row("prefix-\(index)", model: index, cell: NormalUserCell.self) { _, _, _ in }
                    }
                    Row("anchor", model: 5, cell: NormalUserCell.self) { _, _, _ in }
                }
                ListSection(1) {
                    ForEach(0..<activityCount, id: \.self) { index in
                        Row("activity-\(index)", model: index, cell: NormalUserCell.self) { _, _, _ in }
                    }
                }
            }
        }

        _ = await adapter.apply(
            options: .init(transaction: .disabled, applicationMode: .reloadData)
        ) {
            sections(activityCount: 4)
        }
        collectionView.layoutIfNeeded()

        let anchorIndexPath = try XCTUnwrap(adapter.indexPaths(forRowID: "anchor", in: 0).first)
        let initialAttributes = try XCTUnwrap(layout.layoutAttributesForItem(at: anchorIndexPath))
        collectionView.setContentOffset(
            CGPoint(x: 0, y: initialAttributes.frame.minY - 40),
            animated: false
        )
        collectionView.layoutIfNeeded()
        let initialViewportY = initialAttributes.frame.minY - collectionView.contentOffset.y

        _ = await adapter.apply(
            options: .init(
                transaction: ListTransaction.disabled.scrollBehavior(
                    .preserveVisiblePosition(of: ListScrollTarget("anchor", in: 0))
                )
            )
        ) {
            sections(activityCount: 0)
        }
        collectionView.layoutIfNeeded()

        let filteredIndexPath = try XCTUnwrap(adapter.indexPaths(forRowID: "anchor", in: 0).first)
        let filteredAttributes = try XCTUnwrap(layout.layoutAttributesForItem(at: filteredIndexPath))
        XCTAssertEqual(
            filteredAttributes.frame.minY - collectionView.contentOffset.y,
            initialViewportY,
            accuracy: 0.5
        )
        XCTAssertGreaterThan(collectionView.contentInset.bottom, 0)

        _ = await adapter.apply(
            options: .init(
                transaction: ListTransaction.disabled.scrollBehavior(
                    .preserveVisiblePosition(of: ListScrollTarget("anchor", in: 0))
                )
            )
        ) {
            sections(activityCount: 4)
        }
        collectionView.layoutIfNeeded()

        let restoredIndexPath = try XCTUnwrap(adapter.indexPaths(forRowID: "anchor", in: 0).first)
        let restoredAttributes = try XCTUnwrap(layout.layoutAttributesForItem(at: restoredIndexPath))
        XCTAssertEqual(
            restoredAttributes.frame.minY - collectionView.contentOffset.y,
            initialViewportY,
            accuracy: 0.5
        )
        XCTAssertEqual(collectionView.contentInset.bottom, 0, accuracy: 0.5)
    }

    func testUnrelatedFlatSectionUpdateDoesNotAnimateOutlineSection() async {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)

        _ = await adapter.apply(
            options: .init(transaction: .disabled, applicationMode: .reloadData)
        ) {
            ListSection(0) {
                DisclosureGroup(
                    Row("parent", model: "Parent", cell: UICollectionViewListCell.self) { _, _, _ in }
                        .outlineDisclosure(),
                    isExpanded: true
                ) {
                    Row("child", model: "Child", cell: UICollectionViewListCell.self) { _, _, _ in }
                }
            }
            ListSection(1) {
                Row("activity-a", model: "A", cell: UICollectionViewCell.self) { _, _, _ in }
                Row("activity-b", model: "B", cell: UICollectionViewCell.self) { _, _, _ in }
            }
        }
        let initialOutlineAnimationGeneration = adapter.outlineAnimationGeneration

        _ = await adapter.apply(
            options: .init(transaction: ListTransaction(animation: .enabled), applicationMode: .differences)
        ) {
            ListSection(0) {
                DisclosureGroup(
                    Row("parent", model: "Parent", cell: UICollectionViewListCell.self) { _, _, _ in }
                        .outlineDisclosure(),
                    isExpanded: true
                ) {
                    Row("child", model: "Child", cell: UICollectionViewListCell.self) { _, _, _ in }
                }
            }
            ListSection(1) {
                Row("activity-b", model: "B", cell: UICollectionViewCell.self) { _, _, _ in }
            }
        }

        XCTAssertEqual(adapter.outlineAnimationGeneration, initialOutlineAnimationGeneration)

        _ = await adapter.apply(
            options: .init(transaction: ListTransaction(animation: .enabled), applicationMode: .differences)
        ) {
            ListSection(0) {
                DisclosureGroup(
                    Row("parent", model: "Parent", cell: UICollectionViewListCell.self) { _, _, _ in }
                        .outlineDisclosure(),
                    isExpanded: false
                ) {
                    Row("child", model: "Child", cell: UICollectionViewListCell.self) { _, _, _ in }
                }
            }
            ListSection(1) {
                Row("activity-b", model: "B", cell: UICollectionViewCell.self) { _, _, _ in }
            }
        }

        // A kept outline section preserves its current runtime expansion state. Changing
        // the description's initial isExpanded value must not collapse it during apply.
        XCTAssertEqual(adapter.outlineAnimationGeneration, initialOutlineAnimationGeneration)
    }

    func testBuilderSupportsForEachAndConditionalRows() {
        let users = [
            User(id: 1, name: "A", isVIP: false, version: 1),
            User(id: 2, name: "B", isVIP: true, version: 1)
        ]

        let sections = ListSectionsBuilder<Int>.build {
            ListSection(0) {
                ForEach(users, id: \.id) { user in
                    if user.isVIP {
                        Row(model: user, cell: VIPUserCell.self) { cell, user, _ in
                            cell.name = user.name
                        }
                        .refreshID(user.version)
                    } else {
                        Row(model: user, cell: NormalUserCell.self) { cell, user, _ in
                            cell.name = user.name
                        }
                        .refreshID(user.version)
                    }
                }
            }
            .header(HeaderView.self, id: "header") { view, _ in
                view.title = "Users"
            }
        }

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].rows.count, 2)
        XCTAssertEqual(sections[0].selectionMode, .automatic)
        XCTAssertEqual(sections[0].supplementaries.count, 1)
        XCTAssertEqual(sections[0].rows[0].identity.rowID.typed(Int.self), 1)
        XCTAssertEqual(sections[0].rows[1].identity.rowID.typed(Int.self), 2)
    }

    func testForEachSupportsClosureIDForFallbackIdentity() {
        let users = [
            UserProfile(userID: "", accountID: "account-1", name: "A"),
            UserProfile(userID: "user-2", accountID: "account-2", name: "B")
        ]

        let sections = ListSectionsBuilder<Int>.build {
            ListSection(0) {
                ForEach(users, id: { user in
                    user.userID.isEmpty ? "account-\(user.accountID)" : user.userID
                }) { user in
                    Row(model: user, cell: NormalUserCell.self) { cell, user, _ in
                        cell.name = user.name
                    }
                }
            }
        }

        XCTAssertEqual(sections[0].rows[0].identity.rowID.typed(String.self), "account-account-1")
        XCTAssertEqual(sections[0].rows[1].identity.rowID.typed(String.self), "user-2")
    }

    func testSingleIdentifiableModelRowUsesModelID() {
        let row = Row(model: IdentifiedUser(id: 7, name: "A"), cell: NormalUserCell.self) { cell, user, _ in
            cell.name = user.name
        }
        .eraseToAnyListRow(sectionID: 0)

        XCTAssertEqual(row.identity.rowID.typed(Int.self), 7)
    }

    func testSingleModelRowSupportsKeyPathID() {
        let row = Row(model: User(id: 9, name: "A", isVIP: false, version: 1), id: \.id, cell: NormalUserCell.self) { cell, user, _ in
            cell.name = user.name
        }
        .eraseToAnyListRow(sectionID: 0)

        XCTAssertEqual(row.identity.rowID.typed(Int.self), 9)
    }

    func testProviderRowUsesExplicitPresentationIdentityAndSelection() {
        let row = ProviderRow("provider", cell: NormalUserCell.self) { collectionView, indexPath, _ in
            let cell = collectionView.lk.dequeue(NormalUserCell.self, for: indexPath)
            cell.name = "provider"
            return cell
        }
        .onSelect { context in
            XCTAssertEqual(context.indexPath.item, 0)
        }
        .eraseToAnyListRows(sectionID: 0)[0]

        XCTAssertEqual(row.identity.rowID.typed(String.self), "provider")
        XCTAssertEqual(row.identity.presentationID, ObjectIdentifier(NormalUserCell.self))
    }

    func testCollectionReusableHelpersExposeCellKitMigrationUtilities() {
        XCTAssertEqual(
            UICollectionView.elementKind(for: HeaderView.self),
            String(reflecting: HeaderView.self)
        )
        XCTAssertEqual(
            UICollectionView.elementKindSectionBackgroundDecoration,
            "UICollectionView.ElementKindSectionBackgroundDecoration"
        )

        let layout = UICollectionViewCompositionalSeparatorLayout(section: NSCollectionLayoutSection(
            group: NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .absolute(44)
                ),
                subitems: [
                    NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(1),
                        heightDimension: .fractionalHeight(1)
                    ))
                ]
            )
        ))
        XCTAssertEqual(layout.separatorInsets, .zero)
        layout.separatorInsets = .init(top: 0, leading: 12, bottom: 0, trailing: 12)
        XCTAssertEqual(layout.separatorInsets.leading, 12)

        let secondLayout = UICollectionViewCompositionalSeparatorLayout(section: NSCollectionLayoutSection(
            group: NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .absolute(44)
                ),
                subitems: [
                    NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(1),
                        heightDimension: .fractionalHeight(1)
                    ))
                ]
            )
        ))
        layout.separatorColor = .systemRed
        secondLayout.separatorColor = .systemBlue

        let firstAttributes = layout.layoutAttributesForDecorationView(
            ofKind: UICollectionView.elementKindSectionSeparatorDecoration,
            at: IndexPath(item: 0, section: 0)
        ) as? SectionSeparatorLayoutAttributes
        let secondAttributes = secondLayout.layoutAttributesForDecorationView(
            ofKind: UICollectionView.elementKindSectionSeparatorDecoration,
            at: IndexPath(item: 0, section: 0)
        ) as? SectionSeparatorLayoutAttributes
        XCTAssertEqual(firstAttributes?.separatorColor, .systemRed)
        XCTAssertEqual(secondAttributes?.separatorColor, .systemBlue)
        XCTAssertEqual(
            (firstAttributes?.copy() as? SectionSeparatorLayoutAttributes)?.separatorColor,
            .systemRed
        )
    }

    func testDefaultReusableNamesAreQualifiedWhileNibNamesStayShort() {
        XCTAssertNotEqual(
            ReuseFeatureA.SharedCell.listReuseIdentifier,
            ReuseFeatureB.SharedCell.listReuseIdentifier
        )
        XCTAssertNotEqual(
            UICollectionView.elementKind(for: ReuseFeatureA.SharedSupplementary.self),
            UICollectionView.elementKind(for: ReuseFeatureB.SharedSupplementary.self)
        )
        XCTAssertEqual(ReuseFeatureA.SharedCell.listNibName, "SharedCell")
        XCTAssertEqual(ReuseFeatureB.SharedCell.listNibName, "SharedCell")
    }

    func testCollectionReusableNamespaceCreatesCellRegistrationWithClassFallback() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let registration: UICollectionView.CellRegistration<NormalUserCell, User> = collectionView.lk.cellRegistration(
            NormalUserCell.self
        ) { cell, _, user in
            cell.name = user.name
        }

        let cell = collectionView.dequeueConfiguredReusableCell(
            using: registration,
            for: IndexPath(item: 0, section: 0),
            item: User(id: 1, name: "A", isVIP: false, version: 1)
        )

        XCTAssertEqual(cell.name, "A")
    }

    func testCollectionReusableNamespaceCreatesSupplementaryRegistrationWithClassFallback() {
        let layout = UICollectionViewCompositionalLayout { _, _ in
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .fractionalHeight(1)
            ))
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .absolute(44)
                ),
                subitems: [item]
            )
            let section = NSCollectionLayoutSection(group: group)
            section.boundarySupplementaryItems = [
                NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(1),
                        heightDimension: .absolute(24)
                    ),
                    elementKind: UICollectionView.elementKindSectionHeader,
                    alignment: .top
                )
            ]
            return section
        }
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 120),
            collectionViewLayout: layout
        )
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewCell, Int> { _, _, _ in }
        let dataSource = UICollectionViewDiffableDataSource<Int, Int>(
            collectionView: collectionView
        ) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(
                using: cellRegistration,
                for: indexPath,
                item: item
            )
        }
        let registration = collectionView.lk.supplementaryRegistration(
            HeaderView.self,
            ofKind: UICollectionView.elementKindSectionHeader
        ) { view, kind, _ in
            view.title = kind
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(
                using: registration,
                for: indexPath
            )
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        snapshot.appendItems([0])
        dataSource.apply(snapshot, animatingDifferences: false)
        collectionView.reloadData()
        collectionView.layoutIfNeeded()

        let view = dataSource.collectionView(
            collectionView,
            viewForSupplementaryElementOfKind: UICollectionView.elementKindSectionHeader,
            at: IndexPath(item: 0, section: 0)
        ) as? HeaderView

        XCTAssertEqual(view?.title, UICollectionView.elementKindSectionHeader)
    }

    func testIdentityUsesCellTypeAndRefreshIDSeparately() {
        let normal = Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
            .refreshID(1)
            .eraseToAnyListRow(sectionID: 0)
        let refreshed = Row(1, model: User(id: 1, name: "B", isVIP: false, version: 2), cell: NormalUserCell.self) { _, _, _ in }
            .refreshID(2)
            .eraseToAnyListRow(sectionID: 0)
        let vip = Row(1, model: User(id: 1, name: "B", isVIP: true, version: 2), cell: VIPUserCell.self) { _, _, _ in }
            .refreshID(2)
            .eraseToAnyListRow(sectionID: 0)

        XCTAssertEqual(normal.identity, refreshed.identity)
        XCTAssertNotEqual(normal.refreshID, refreshed.refreshID)
        XCTAssertNotEqual(normal.identity, vip.identity)
    }

    func testAdapterDispatchesSelectionAndCustomEvents() async {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        var selectedID: Int?
        var receivedEvent: UserEvent?

        adapter.onEvent(UserEvent.self) { event, _ in
            receivedEvent = event
        }
        await adapter.apply(transaction: .disabled) {
            ListSection(0) {
                Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, context in
                    context.send(UserEvent.avatarTap(userID: 1))
                }
                .onSelect { context in
                    selectedID = context.indexPath.item
                }
            }
        }
        adapter.collectionView(collectionView, didSelectItemAt: IndexPath(item: 0, section: 0))
        _ = adapter.collectionView(collectionView, cellForItemAt: IndexPath(item: 0, section: 0))

        XCTAssertTrue(collectionView.allowsSelection)
        XCTAssertFalse(collectionView.allowsMultipleSelection)
        XCTAssertEqual(selectedID, 0)
        XCTAssertEqual(receivedEvent, .avatarTap(userID: 1))
    }

    func testVariantChangesIdentityForSameCellType() {
        let compact = Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
            .variant("compact")
            .eraseToAnyListRow(sectionID: 0)
        let expanded = Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
            .variant("expanded")
            .eraseToAnyListRow(sectionID: 0)

        XCTAssertNotEqual(compact.identity, expanded.identity)
    }

    func testVisibleReconfigureUsesExistingCell() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let context = ListContext(
            identity: AnyListIdentity(
                sectionID: AnyListID(0),
                rowID: AnyListID(1),
                presentationID: ObjectIdentifier(NormalUserCell.self)
            ),
            indexPath: IndexPath(item: 0, section: 0),
            collectionView: collectionView
        ) { _, _ in }
        let row = Row(1, model: User(id: 1, name: "B", isVIP: false, version: 2), cell: NormalUserCell.self) { cell, user, _ in
            cell.name = user.name
        }
        .eraseToAnyListRow(sectionID: 0)
        let existingCell = NormalUserCell()

        row.configureVisibleCell(existingCell, context)

        XCTAssertEqual(existingCell.name, "B")
    }

    func testHeaderTapCanSendCustomEvent() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        var receivedEvent: UserEvent?
        let context = ListContext(
            identity: AnyListIdentity(
                sectionID: AnyListID(0),
                rowID: AnyListID("header"),
                presentationID: ObjectIdentifier(HeaderView.self)
            ),
            indexPath: IndexPath(item: 0, section: 0),
            collectionView: collectionView
        ) { event, _ in
            receivedEvent = event as? UserEvent
        }
        let section = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        }
        .header(HeaderView.self, id: "header") { _, _ in }
        .onHeaderTap { context in
            context.send(UserEvent.headerTap)
        }

        section.supplementaries.first?.tapHandler?(context)

        XCTAssertEqual(receivedEvent, .headerTap)
    }

    func testSupplementaryTapInstallerPreservesExternalTapRecognizers() {
        let view = UICollectionReusableView()
        let externalTap = UITapGestureRecognizer()
        view.addGestureRecognizer(externalTap)

        ListTapHandlerInstaller.install(on: view) {}
        XCTAssertEqual(view.gestureRecognizers?.count, 2)
        XCTAssertTrue(view.gestureRecognizers?.contains(externalTap) == true)

        ListTapHandlerInstaller.install(on: view) {}
        XCTAssertEqual(view.gestureRecognizers?.count, 2)
        XCTAssertTrue(view.gestureRecognizers?.contains(externalTap) == true)

        ListTapHandlerInstaller.install(on: view, handler: nil)
        XCTAssertEqual(view.gestureRecognizers?.count, 1)
        XCTAssertTrue(view.gestureRecognizers?.contains(externalTap) == true)
    }

    func testDiagnosticsReportsDuplicateIdentities() {
        let sections = ListSectionsBuilder<Int>.build {
            ListSection(0) {
                Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
                Row(1, model: User(id: 1, name: "B", isVIP: false, version: 2), cell: NormalUserCell.self) { _, _, _ in }
            }
            .header(HeaderView.self, id: "same-header") { _, _ in }
            .supplementary(UICollectionView.elementKindSectionHeader, HeaderView.self, id: "same-header") { _, _ in }

            ListSection(0) {
                Row(2, model: User(id: 2, name: "C", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
            }
        }

        let issues = ListDiagnostics.validate(sections)

        XCTAssertTrue(issues.contains { $0.kind == .duplicateSection })
        XCTAssertTrue(issues.contains { $0.kind == .duplicateRow })
        XCTAssertTrue(issues.contains { $0.kind == .duplicateSupplementary })
    }

    func testDiagnosticsWarningSkipsDuplicateSectionsWithoutTrapping() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)

        let result = adapter.apply(
            options: ListApplyOptions(
                transaction: .disabled,
                diagnostics: .init(mode: .warning, logsApplySummary: false)
            )
        ) {
            ListSection(0) {
                Row("first", model: "A", cell: NormalUserCell.self) { _, _, _ in }
            }
            ListSection(0) {
                Row("second", model: "B", cell: NormalUserCell.self) { _, _, _ in }
            }
        }

        XCTAssertTrue(result.diagnosticsIssues.contains { $0.kind == .duplicateSection })
        XCTAssertEqual(result.animation.completionState, .completed)
        XCTAssertEqual(collectionView.numberOfSections, 0)
    }

    func testCollectionDiagnosticsRejectionPreservesLastValidSnapshot() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)

        adapter.apply(options: .init(transaction: .disabled, applicationMode: .reloadData)) {
            ListSection(9) {
                Row("valid", model: "Valid", cell: NormalUserCell.self) { _, _, _ in }
            }
        }

        let result = adapter.apply(
            options: ListApplyOptions(
                transaction: .disabled,
                diagnostics: .init(mode: .warning, logsApplySummary: false)
            )
        ) {
            ListSection(1) {
                Row("invalid-a", model: "A", cell: NormalUserCell.self) { _, _, _ in }
            }
            ListSection(1) {
                Row("invalid-b", model: "B", cell: NormalUserCell.self) { _, _, _ in }
            }
        }

        XCTAssertTrue(result.diagnosticsIssues.contains { $0.kind == .duplicateSection })
        XCTAssertEqual(collectionView.numberOfSections, 1)
        XCTAssertEqual(adapter.sectionIdentifier(at: 0), 9)
        XCTAssertEqual(adapter.rowIdentifier(at: IndexPath(item: 0, section: 0), as: String.self), "valid")
        XCTAssertTrue(adapter.indexPaths(forRowID: "invalid-a").isEmpty)
        XCTAssertTrue(adapter.indexPaths(forRowID: "invalid-b").isEmpty)
    }

    func testTableDiagnosticsRejectionPreservesLastValidSnapshot() {
        let tableView = UITableView(frame: .zero, style: .plain)
        let adapter = TableListAdapter<Int>(tableView: tableView)

        adapter.apply(options: .init(transaction: .disabled, applicationMode: .reloadData)) {
            TableSection(9) {
                TableRow("valid", model: "Valid", cell: UITableViewCell.self) { _, _, _ in }
            }
        }

        let result = adapter.apply(
            options: ListApplyOptions(
                transaction: .disabled,
                diagnostics: .init(mode: .warning, logsApplySummary: false)
            )
        ) {
            TableSection(1) {
                TableRow("invalid-a", model: "A", cell: UITableViewCell.self) { _, _, _ in }
            }
            TableSection(1) {
                TableRow("invalid-b", model: "B", cell: UITableViewCell.self) { _, _, _ in }
            }
        }

        XCTAssertTrue(result.diagnosticsIssues.contains { $0.kind == .duplicateSection })
        XCTAssertEqual(tableView.numberOfSections, 1)
        XCTAssertEqual(adapter.sectionIdentifier(at: 0), 9)
        XCTAssertEqual(adapter.rowIdentifier(at: IndexPath(row: 0, section: 0), as: String.self), "valid")
        XCTAssertTrue(adapter.indexPaths(forRowID: "invalid-a").isEmpty)
        XCTAssertTrue(adapter.indexPaths(forRowID: "invalid-b").isEmpty)
    }

    func testApplyOptionsExposeSummaryAndAvoidDuplicateDiffableCrash() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        let options = ListApplyOptions(
            transaction: .disabled,
            diagnostics: .disabled
        )

        _ = adapter.apply(options: options) {
            ListSection(0) {
                Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
                    .refreshID(1)
                    .refresh(when: .refreshIDChanges, scope: .allMatching)
            }
        }

        let result = adapter.apply(options: options) {
            ListSection(0) {
                Row(1, model: User(id: 1, name: "B", isVIP: false, version: 2), cell: NormalUserCell.self) { _, _, _ in }
                    .refreshID(2)
                    .refresh(when: .refreshIDChanges, scope: .allMatching)
                Row(2, model: User(id: 2, name: "C", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
            }
        }

        XCTAssertEqual(result.insertedRowCount, 1)
        XCTAssertEqual(result.keptRowCount, 1)
        XCTAssertEqual(result.rowRefreshIDChangedCount, 1)
        XCTAssertEqual(result.refreshMetrics.snapshotReconfiguredRowCount, 1)

        let duplicateResult = adapter.apply(
            options: ListApplyOptions(
                transaction: .disabled,
                diagnostics: .init(mode: .warning, logsApplySummary: false)
            )
        ) {
            ListSection(0) {
                Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
                Row(1, model: User(id: 1, name: "B", isVIP: false, version: 2), cell: NormalUserCell.self) { _, _, _ in }
            }
        }

        XCTAssertTrue(duplicateResult.diagnosticsIssues.contains { $0.kind == .duplicateRow })
    }

    func testRowRuleOwnsSnapshotRefreshWithoutApplyLevelStrategy() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)

        _ = adapter.apply(
            options: ListApplyOptions(transaction: .disabled)
        ) {
            ListSection(0) {
                Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
                    .refreshID(1)
                    .refresh(when: .refreshIDChanges, scope: .allMatching)
            }
        }

        let result = adapter.apply(
            options: ListApplyOptions(transaction: .disabled)
        ) {
            ListSection(0) {
                Row(1, model: User(id: 1, name: "B", isVIP: false, version: 2), cell: NormalUserCell.self) { _, _, _ in }
                    .refreshID(2)
                    .refresh(when: .refreshIDChanges, scope: .allMatching)
            }
        }

        XCTAssertEqual(result.keptRowCount, 1)
        XCTAssertEqual(result.rowRefreshIDChangedCount, 1)
        XCTAssertEqual(result.refreshMetrics.snapshotReconfiguredRowCount, 1)
        XCTAssertEqual(result.refreshMetrics.visibleReconfiguredRowCount, 0)
    }

    func testModelAwareRowEventsAndPrefetchReceiveModel() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        var selectedUserID: Int?
        var deselectedUserID: Int?
        var prefetchedUserID: Int?
        var cancelledUserID: Int?

        adapter.apply(transaction: .disabled) {
            ListSection(0) {
                Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
                    .onSelect { user, _ in selectedUserID = user.id }
                    .onDeselect { user, _ in deselectedUserID = user.id }
                    .onPrefetch { user, _ in prefetchedUserID = user.id }
                    .onCancelPrefetch { user, _ in cancelledUserID = user.id }
            }
        }
        let indexPath = IndexPath(item: 0, section: 0)
        adapter.collectionView(collectionView, didSelectItemAt: indexPath)
        adapter.collectionView(collectionView, didDeselectItemAt: indexPath)
        adapter.collectionView(collectionView, prefetchItemsAt: [indexPath])
        adapter.collectionView(collectionView, cancelPrefetchingForItemsAt: [indexPath])

        XCTAssertEqual(selectedUserID, 1)
        XCTAssertEqual(deselectedUserID, 1)
        XCTAssertEqual(prefetchedUserID, 1)
        XCTAssertEqual(cancelledUserID, 1)
    }

    func testCollectionLifecycleUsesCapturedRowAfterSnapshotChanges() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        let displayDelegate = CollectionDisplayDelegateSpy()
        var endedUserID: Int?
        var cancelledUserID: Int?
        adapter.displayDelegate = displayDelegate

        adapter.apply(transaction: .disabled) {
            ListSection(0) {
                Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
                    .onEndDisplay { _, _ in endedUserID = 1 }
                    .onCancelPrefetch { user, _ in cancelledUserID = user.id }
            }
        }

        let oldIndexPath = IndexPath(item: 0, section: 0)
        let oldCell = NormalUserCell()
        adapter.collectionView(collectionView, willDisplay: oldCell, forItemAt: oldIndexPath)
        adapter.collectionView(collectionView, prefetchItemsAt: [oldIndexPath])

        adapter.apply(transaction: .disabled) {
            ListSection(0) {
                Row(2, model: User(id: 2, name: "B", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
            }
        }

        adapter.collectionView(collectionView, didEndDisplaying: oldCell, forItemAt: oldIndexPath)
        adapter.collectionView(collectionView, cancelPrefetchingForItemsAt: [oldIndexPath])

        XCTAssertEqual(endedUserID, 1)
        XCTAssertEqual(cancelledUserID, 1)
        XCTAssertEqual(displayDelegate.didEndDisplayingCount, 1)
    }

    func testCollectionLifecycleUsesCapturedRowWhenDeletedSectionIndexPathIsReused() async {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        var endedRowID: String?
        var cancelledRowID: String?

        _ = await adapter.apply(transaction: .disabled) {
            ListSection(0) {
                Row("old", model: "Old", cell: NormalUserCell.self) { _, _, _ in }
                    .onEndDisplay { _, _ in endedRowID = "old" }
                    .onCancelPrefetch { _, _ in cancelledRowID = "old" }
            }
            ListSection(1) {
                Row("new", model: "New", cell: NormalUserCell.self) { _, _, _ in }
            }
        }

        let reusedIndexPath = IndexPath(item: 0, section: 0)
        let oldCell = NormalUserCell()
        adapter.collectionView(collectionView, willDisplay: oldCell, forItemAt: reusedIndexPath)
        adapter.collectionView(collectionView, prefetchItemsAt: [reusedIndexPath])

        _ = await adapter.apply(transaction: .disabled) {
            ListSection(1) {
                Row("new", model: "New", cell: NormalUserCell.self) { _, _, _ in }
            }
        }

        adapter.collectionView(collectionView, didEndDisplaying: oldCell, forItemAt: reusedIndexPath)
        adapter.collectionView(collectionView, cancelPrefetchingForItemsAt: [reusedIndexPath])

        XCTAssertEqual(endedRowID, "old")
        XCTAssertEqual(cancelledRowID, "old")
        XCTAssertEqual(adapter.rowIdentifier(at: reusedIndexPath, as: String.self), "new")
    }

    func testCollectionSelectionModeIsEnforcedPerSection() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        var deselectedUserID: Int?

        adapter.apply(transaction: .disabled) {
            ListSection(0) {
                Row(0, model: User(id: 0, name: "None", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
            }
            .selectionMode(.none)
            ListSection(1) {
                Row(10, model: User(id: 10, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
                    .onDeselect { user, _ in deselectedUserID = user.id }
                Row(11, model: User(id: 11, name: "B", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
            }
            .selectionMode(.single)
            .multipleSelectionInteraction()
            ListSection(2) {
                Row(20, model: User(id: 20, name: "C", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
            }
            .selectionMode(.multiple)
            .multipleSelectionInteraction()
        }

        let disabled = IndexPath(item: 0, section: 0)
        let firstSingle = IndexPath(item: 0, section: 1)
        let secondSingle = IndexPath(item: 1, section: 1)
        let multiple = IndexPath(item: 0, section: 2)

        XCTAssertTrue(collectionView.allowsSelection)
        XCTAssertTrue(collectionView.allowsMultipleSelection)
        XCTAssertFalse(adapter.collectionView(collectionView, shouldSelectItemAt: disabled))
        XCTAssertTrue(adapter.collectionView(collectionView, shouldSelectItemAt: firstSingle))
        XCTAssertTrue(adapter.collectionView(collectionView, shouldSelectItemAt: multiple))
        XCTAssertFalse(
            adapter.collectionView(
                collectionView,
                shouldBeginMultipleSelectionInteractionAt: firstSingle
            )
        )
        XCTAssertTrue(
            adapter.collectionView(
                collectionView,
                shouldBeginMultipleSelectionInteractionAt: multiple
            )
        )

        collectionView.selectItem(at: firstSingle, animated: false, scrollPosition: [])
        collectionView.selectItem(at: secondSingle, animated: false, scrollPosition: [])
        adapter.collectionView(collectionView, didSelectItemAt: secondSingle)

        XCTAssertFalse(collectionView.indexPathsForSelectedItems?.contains(firstSingle) ?? false)
        XCTAssertTrue(collectionView.indexPathsForSelectedItems?.contains(secondSingle) ?? false)
        XCTAssertEqual(deselectedUserID, 10)
    }

    func testCollectionAutomaticSelectionUsesRowIntent() async {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)

        _ = await adapter.apply(transaction: .disabled) {
            ListSection(0) {
                Row("static", model: "Static", cell: NormalUserCell.self) { _, _, _ in }
            }
        }

        XCTAssertFalse(collectionView.allowsSelection)
        XCTAssertFalse(adapter.collectionView(collectionView, shouldSelectItemAt: IndexPath(item: 0, section: 0)))

        _ = await adapter.apply(transaction: .disabled) {
            ListSection(0) {
                Row("static", model: "Static", cell: NormalUserCell.self) { _, _, _ in }
            }
            ListSection(1) {
                Row("plain", model: "Plain", cell: NormalUserCell.self) { _, _, _ in }
                Row("action", model: "Action", cell: NormalUserCell.self) { _, _, _ in }
                    .onSelect { _ in }
                Row("controlled", model: "Controlled", cell: NormalUserCell.self) { _, _, _ in }
                    .selected(false)
                Row("disabled", model: "Disabled", cell: NormalUserCell.self) { _, _, _ in }
                    .onSelect { _ in }
                    .selectionDisabled()
            }
            .multipleSelectionInteraction()
        }

        XCTAssertTrue(collectionView.allowsSelection)
        XCTAssertFalse(collectionView.allowsMultipleSelection)
        XCTAssertFalse(adapter.collectionView(collectionView, shouldSelectItemAt: IndexPath(item: 0, section: 0)))
        XCTAssertFalse(adapter.collectionView(collectionView, shouldSelectItemAt: IndexPath(item: 0, section: 1)))
        XCTAssertTrue(adapter.collectionView(collectionView, shouldSelectItemAt: IndexPath(item: 1, section: 1)))
        XCTAssertTrue(adapter.collectionView(collectionView, shouldSelectItemAt: IndexPath(item: 2, section: 1)))
        XCTAssertFalse(adapter.collectionView(collectionView, shouldSelectItemAt: IndexPath(item: 3, section: 1)))
        XCTAssertFalse(
            adapter.collectionView(
                collectionView,
                shouldBeginMultipleSelectionInteractionAt: IndexPath(item: 1, section: 1)
            )
        )
    }

    func testCollectionControlledSelectionSynchronizesAcrossApply() async {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        let indexPath = IndexPath(item: 0, section: 0)

        _ = await adapter.apply(transaction: .disabled) {
            ListSection(0) {
                Row("controlled", model: "Controlled", cell: NormalUserCell.self) { _, _, _ in }
                    .selected(true)
            }
        }
        XCTAssertEqual(collectionView.indexPathsForSelectedItems, [indexPath])

        _ = await adapter.apply(transaction: .disabled) {
            ListSection(0) {
                Row("controlled", model: "Controlled", cell: NormalUserCell.self) { _, _, _ in }
                    .selected(false)
            }
        }
        XCTAssertTrue(collectionView.indexPathsForSelectedItems?.isEmpty ?? true)

        _ = await adapter.apply(transaction: .disabled) {
            ListSection(0) {
                Row("controlled", model: "Controlled", cell: NormalUserCell.self) { _, _, _ in }
                    .selected(true)
            }
        }
        XCTAssertEqual(collectionView.indexPathsForSelectedItems, [indexPath])
    }

    func testCollectionHighlightIntentDoesNotEnableRowSelection() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        let indexPath = IndexPath(item: 0, section: 0)
        var highlightChanges: [Bool] = []

        adapter.apply(transaction: .disabled) {
            ListSection(0) {
                Row("highlight", model: "Highlight", cell: NormalUserCell.self) { _, _, _ in }
                    .selectionDisabled()
                    .onHighlightChange { isHighlighted, _ in
                        highlightChanges.append(isHighlighted)
                    }
            }
        }

        XCTAssertTrue(collectionView.allowsSelection)
        XCTAssertFalse(adapter.collectionView(collectionView, shouldSelectItemAt: indexPath))
        XCTAssertTrue(adapter.collectionView(collectionView, shouldHighlightItemAt: indexPath))
        adapter.collectionView(collectionView, didHighlightItemAt: indexPath)
        adapter.collectionView(collectionView, didUnhighlightItemAt: indexPath)
        XCTAssertEqual(highlightChanges, [true, false])
    }

    func testCollectionAutomaticSelectionUsesExternalDelegateIntent() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        let selectionDelegate = CollectionSelectionDelegateSpy()
        let indexPath = IndexPath(item: 0, section: 0)
        adapter.collectionDelegate = selectionDelegate

        adapter.apply(transaction: .disabled) {
            ListSection(0) {
                Row("plain", model: "Plain", cell: NormalUserCell.self) { _, _, _ in }
            }
        }

        XCTAssertTrue(collectionView.allowsSelection)
        XCTAssertTrue(adapter.collectionView(collectionView, shouldSelectItemAt: indexPath))
        adapter.collectionView(collectionView, didSelectItemAt: indexPath)
        XCTAssertEqual(selectionDelegate.selectedIndexPath, indexPath)
    }

    func testCellEventBindingSendsTypedEvent() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        var receivedEvent: UserEvent?

        adapter.onEvent(UserEvent.self) { event, _ in
            receivedEvent = event
        }
        adapter.apply(transaction: .disabled) {
            ListSection(0) {
                Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: EventCell.self) { _, _, _ in }
                    .onCellEvent({ cell, send in
                        cell.onButtonTap = send
                    }, send: { user in
                        UserEvent.buttonTap(userID: user.id)
                    })
            }
        }
        let cell = adapter.collectionView(collectionView, cellForItemAt: IndexPath(item: 0, section: 0)) as? EventCell
        cell?.onButtonTap?()

        XCTAssertEqual(receivedEvent, .buttonTap(userID: 1))
    }

    func testStateRowsCreateStableIdentities() {
        let sections = ListSectionsBuilder<Int>.build {
            ListSection(0) {
                ListStateRow.empty(EmptyStateCell.self) { cell, _ in
                    cell.message = "empty"
                }
                ListStateRow.loading(LoadingStateCell.self) { cell, _ in
                    cell.message = "loading"
                }
                ListStateRow.failure(FailureStateCell.self) { cell, _ in
                    cell.message = "failure"
                }
            }
        }

        XCTAssertEqual(sections[0].rows.count, 3)
        XCTAssertEqual(sections[0].rows[0].identity.rowID.typed(ListStateRowKind.self), .empty)
        XCTAssertEqual(sections[0].rows[1].identity.rowID.typed(ListStateRowKind.self), .loading)
        XCTAssertEqual(sections[0].rows[2].identity.rowID.typed(ListStateRowKind.self), .failure)
    }

    func testSectionMetadataSelectionAndSupplementaryEnhancements() {
        let header = Supplementary(
            UICollectionView.elementKindSectionHeader,
            id: "header",
            view: HeaderView.self
        ) { _, _ in }
            .refreshID(2)
            .refresh(when: .refreshIDChanges)

        let section = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
                .selected(true)
        }
        .layout("user-grid")
        .selectionMode(.multiple)
        .stickyHeader()
        .backgroundDecoration("user-background")
        .supplementary(header)
        .supplementary("badge", HeaderView.self, id: "badge") { _, _ in }

        XCTAssertEqual(section.layoutID?.typed(String.self), "user-grid")
        XCTAssertEqual(section.selectionMode, .multiple)
        XCTAssertTrue(section.isHeaderSticky)
        XCTAssertEqual(section.backgroundDecorationKind, "user-background")
        XCTAssertTrue(section.rows[0].isSelected == true)
        XCTAssertEqual(section.supplementaries[0].refreshRule.trigger, .refreshIDChanges)
        XCTAssertEqual(section.supplementaries.map(\.kind), [UICollectionView.elementKindSectionHeader, "badge"])
    }

    func testSelectionChangeAndDelegateForwarding() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        let scrollDelegate = ScrollDelegateSpy()
        let layoutDelegate = FlowLayoutDelegateSpy()
        var selectionChanges: [Bool] = []

        adapter.scrollDelegate = scrollDelegate
        adapter.layoutDelegate = layoutDelegate
        let applyCompleted = expectation(description: "selection apply")
        adapter.apply(transaction: .disabled, completion: { _ in
            applyCompleted.fulfill()
        }) {
            ListSection(0) {
                Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
                    .onSelectionChange { isSelected, _ in
                        selectionChanges.append(isSelected)
                    }
            }
        }
        wait(for: [applyCompleted], timeout: 1)

        let indexPath = IndexPath(item: 0, section: 0)
        adapter.collectionView(collectionView, didSelectItemAt: indexPath)
        adapter.collectionView(collectionView, didDeselectItemAt: indexPath)
        adapter.scrollViewDidScroll(collectionView)
        let size = adapter.collectionView(collectionView, layout: collectionView.collectionViewLayout, sizeForItemAt: indexPath)

        XCTAssertEqual(selectionChanges, [true, false])
        XCTAssertEqual(scrollDelegate.didScrollCount, 1)
        XCTAssertEqual(size, CGSize(width: 44, height: 55))
        XCTAssertEqual(layoutDelegate.sizeRequestCount, 1)
    }

    func testScrollDelegateIsNotForwardedDuringSnapshotApply() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        let scrollDelegate = ScrollDelegateSpy()
        adapter.scrollDelegate = scrollDelegate

        adapter.isApplyingSnapshot = true
        adapter.scrollViewDidScroll(collectionView)
        XCTAssertEqual(scrollDelegate.didScrollCount, 0)

        adapter.isApplyingSnapshot = false
        adapter.scrollViewDidScroll(collectionView)
        XCTAssertEqual(scrollDelegate.didScrollCount, 1)
    }

    func testLayoutDSLKiroSpecFilesExist() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let specRoot = packageRoot
            .appendingPathComponent(".kiro")
            .appendingPathComponent("specs")
            .appendingPathComponent("listkit-layout-dsl")

        let requirements = try String(contentsOf: specRoot.appendingPathComponent("requirements.md"))
        let design = try String(contentsOf: specRoot.appendingPathComponent("design.md"))
        let tasks = try String(contentsOf: specRoot.appendingPathComponent("tasks.md"))

        XCTAssertTrue(requirements.contains(".layout(.grid(columns: 2, spacing: 12))"))
        XCTAssertTrue(design.contains("ListSupplementaryPlacement"))
        XCTAssertTrue(tasks.contains("compositional layout helper"))
    }

    func testSectionLayoutDSLPreservesLegacyLayoutID() {
        let gridSection = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        }
        .layout(.grid(columns: 2, spacing: 12))

        guard case let .gridConfiguration(grid)? = gridSection.sectionLayout else {
            return XCTFail("Expected grid layout")
        }
        XCTAssertEqual(grid.columns, 2)
        XCTAssertEqual(grid.spacing, 12)

        let legacySection = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        }
        .layout("legacy-grid")

        XCTAssertEqual(legacySection.layoutID?.typed(String.self), "legacy-grid")
        XCTAssertNil(legacySection.sectionLayout)
    }

    func testSectionLayoutBuilderSwitchesLayoutConditionally() {
        let gridSection = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        } layout: {
            if true {
                GridLayout(columns: 2, spacing: 12)
            } else {
                ListLayout(spacing: 8)
            }
        }

        let defaultSection = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        } layout: {
            if false {
                GridLayout(columns: 2, spacing: 12)
            }
        }

        XCTAssertEqual(gridSection.sectionLayout, ListSectionLayout.grid(columns: 2, spacing: 12))
        XCTAssertNil(defaultSection.sectionLayout)
    }

    func testSectionLayoutModifiersUseLastLayoutSource() {
        let legacyThenList = ListSection(0) {
            Row(1, model: "A", cell: NormalUserCell.self) { _, _, _ in }
        }
        .layout("legacy")
        .layout(.list(spacing: 8))

        let listThenCustom = ListSection(1) {
            Row(1, model: "A", cell: NormalUserCell.self) { _, _, _ in }
        }
        .layout(.grid(columns: 2, spacing: 12))
        .layout(.custom(id: "manual") { _, _, _ in
            ListSectionLayout.list().makeCompositionalSection(itemSupplementaries: [])
        })

        let customThenLegacy = ListSection(2) {
            Row(1, model: "A", cell: NormalUserCell.self) { _, _, _ in }
        }
        .layout(.custom(id: "manual") { _, _, _ in
            ListSectionLayout.list().makeCompositionalSection(itemSupplementaries: [])
        })
        .layout("legacy")

        XCTAssertNil(legacyThenList.layoutID)
        XCTAssertEqual(legacyThenList.sectionLayout, .list(spacing: 8))
        XCTAssertNil(legacyThenList.customSectionLayout)

        XCTAssertNil(listThenCustom.layoutID)
        XCTAssertNil(listThenCustom.sectionLayout)
        XCTAssertEqual(listThenCustom.customSectionLayout?.id.typed(String.self), "manual")

        XCTAssertEqual(customThenLegacy.layoutID?.typed(String.self), "legacy")
        XCTAssertNil(customThenLegacy.sectionLayout)
        XCTAssertNil(customThenLegacy.customSectionLayout)
    }

    func testSupplementaryLayoutBuilderConfiguresBoundaryAndItemLayoutsConditionally() {
        let section = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        } header: {
            Header(HeaderView.self, id: "header") { _, _ in }
        } supplementaries: {
            SectionSupplementary("dot", HeaderView.self, id: "dot") { _, _ in }
        } supplementaryLayouts: {
            if true {
                BoundarySupplementaryLayout(
                    kind: UICollectionView.elementKindSectionHeader,
                    height: .absolute(36),
                    pinned: true
                )
            }
            if true {
                ItemSupplementaryLayout(
                    kind: "dot",
                    anchor: .topTrailing,
                    width: .absolute(16),
                    height: .absolute(16),
                    fractionalOffset: CGPoint(x: 0.2, y: -0.2)
                )
            }
        }

        let defaultHeaderSection = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        } header: {
            Header(HeaderView.self, id: "header") { _, _ in }
        } supplementaryLayouts: {
            if false {
                BoundarySupplementaryLayout(
                    kind: UICollectionView.elementKindSectionHeader,
                    height: .absolute(36),
                    pinned: true
                )
            }
        }

        let layouts = section.resolvedSupplementaryLayouts()
        let headerLayout = layouts.first { $0.kind == UICollectionView.elementKindSectionHeader }
        let dotLayout = layouts.first { $0.kind == "dot" }
        let defaultHeaderLayout = defaultHeaderSection.resolvedSupplementaryLayouts().first

        XCTAssertEqual(headerLayout?.height, .absolute(36))
        if case let .boundary(_, _, pinned, _)? = headerLayout?.placement {
            XCTAssertTrue(pinned)
        } else {
            XCTFail("Expected boundary header layout")
        }
        XCTAssertTrue(dotLayout?.placement.isItem == true)
        XCTAssertEqual(defaultHeaderLayout?.height, .estimated(44))
    }

    func testSectionSupplementaryUsesExplicitItemSupplementaryLayoutModifier() {
        let section = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        } supplementaries: {
            SectionSupplementary("dot", HeaderView.self, id: "dot") { _, _ in }
                .itemSupplementaryLayout(
                    anchor: .topTrailing,
                    width: .absolute(16),
                    height: .absolute(16),
                    fractionalOffset: CGPoint(x: 0.2, y: -0.2),
                    zIndex: 8
                )
        }

        let layout = section.resolvedSupplementaryLayouts().first { $0.kind == "dot" }

        XCTAssertEqual(layout?.placement, .itemSupplementary(anchor: .topTrailing, fractionalOffset: ListLayoutPoint(x: 0.2, y: -0.2)))
        XCTAssertEqual(layout?.width, .absolute(16))
        XCTAssertEqual(layout?.height, .absolute(16))
        XCTAssertEqual(layout?.zIndex, 8)
    }

    func testSupplementaryDiagnosticsReportOrphanLayoutsAndDuplicateKinds() {
        let orphanBoundary = ListSection(0) {
            Row(1, model: "A", cell: NormalUserCell.self) { _, _, _ in }
        }
        .boundarySupplementaryLayout(kind: "badge", width: .absolute(64), height: .absolute(28))

        let orphanItem = ListSection(1) {
            Row(1, model: "A", cell: NormalUserCell.self) { _, _, _ in }
        }
        .itemSupplementaryLayout(kind: "dot", anchor: .topTrailing, width: .absolute(16), height: .absolute(16))

        let duplicateKind = ListSection(2) {
            Row(1, model: "A", cell: NormalUserCell.self) { _, _, _ in }
        }
        .supplementary("badge", HeaderView.self, id: "first") { _, _ in }
        .supplementary("badge", BadgeView.self, id: "second") { _, _ in }

        let viewOnly = ListSection(3) {
            Row(1, model: "A", cell: NormalUserCell.self) { _, _, _ in }
        }
        .supplementary("plain", HeaderView.self, id: "plain") { _, _ in }

        let issues = ListDiagnostics.validate([orphanBoundary, orphanItem, duplicateKind])

        XCTAssertEqual(issues.filter { $0.kind == .orphanSupplementaryLayout }.count, 2)
        XCTAssertTrue(issues.contains { $0.kind == .duplicateSupplementaryKind })
        XCTAssertTrue(ListDiagnostics.validate([viewOnly]).isEmpty)
    }

    func testHorizontalSectionLayoutStoresConfigurationAndBuildsSection() {
        let section = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        }
        .layout(.horizontal(
            itemWidth: .estimated(20),
            itemHeight: .absolute(20),
            spacing: 8,
            contentInsets: .init(top: 0, leading: 14, bottom: 0, trailing: 14)
        ))

        guard case let .horizontalConfiguration(horizontal)? = section.sectionLayout else {
            return XCTFail("Expected horizontal layout")
        }
        let layoutSection = section.makeCompositionalLayoutSection()

        XCTAssertEqual(horizontal.itemWidth, .estimated(20))
        XCTAssertEqual(horizontal.itemHeight, .absolute(20))
        XCTAssertEqual(horizontal.spacing, 8)
        XCTAssertTrue(layoutSection.boundarySupplementaryItems.isEmpty)
    }

    func testHorizontalSectionPlacesBoundaryHeaderBeforeItems() {
        let collectionView = UICollectionView(frame: CGRect(x: 0, y: 0, width: 390, height: 300), collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)

        adapter.apply(transaction: .disabled) {
            ListSection(0) {
                Row(1, model: "3333", cell: NormalUserCell.self) { _, _, _ in }
                Row(2, model: "800003", cell: NormalUserCell.self) { _, _, _ in }
            }
            .layout(.horizontal(
                itemWidth: .estimated(20),
                itemHeight: .absolute(20),
                spacing: 8,
                contentInsets: .init(top: 0, leading: 14, bottom: 0, trailing: 14)
            ))
            .header(HeaderView.self, id: "history") { _, _ in }
            .boundarySupplementaryLayout(
                kind: UICollectionView.elementKindSectionHeader,
                height: .absolute(62)
            )
        }

        collectionView.collectionViewLayout = adapter.makeCompositionalLayout()
        collectionView.layoutIfNeeded()

        let headerAttributes = collectionView.layoutAttributesForSupplementaryElement(
            ofKind: UICollectionView.elementKindSectionHeader,
            at: IndexPath(item: 0, section: 0)
        )
        let cellAttributes = collectionView.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))

        XCTAssertNotNil(headerAttributes)
        XCTAssertNotNil(cellAttributes)
        XCTAssertLessThanOrEqual(headerAttributes?.frame.maxY ?? .greatestFiniteMagnitude, cellAttributes?.frame.minY ?? -.greatestFiniteMagnitude)
    }

    func testCustomSectionLayoutStoresTypedBuilder() {
        let section = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        }
        .layout(.custom(id: "manual") { section, _, _ in
            XCTAssertEqual(section.id, 0)
            return ListSectionLayout.list().makeCompositionalSection(itemSupplementaries: [])
        })

        XCTAssertEqual(section.customSectionLayout?.id.typed(String.self), "manual")
        XCTAssertNil(section.sectionLayout)
    }

    func testCompositionalLayoutBuildsBoundaryAndItemSupplementaries() {
        let section = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        }
        .layout(.grid(columns: 2, spacing: 12))
        .header(HeaderView.self, id: "header") { _, _ in }
        .footer(HeaderView.self, id: "footer") { _, _ in }
        .supplementary("badge", HeaderView.self, id: "badge") { _, _ in }
        .boundarySupplementaryLayout(
            kind: "badge",
            alignment: .topTrailing,
            width: .absolute(64),
            height: .absolute(28),
            zIndex: 5
        )
        .supplementary("dot", HeaderView.self, id: "dot") { _, _ in }
        .itemSupplementaryLayout(
            kind: "dot",
            anchor: .topTrailing,
            width: .absolute(16),
            height: .absolute(16),
            fractionalOffset: CGPoint(x: 0.2, y: -0.2)
        )
        .stickyHeader()

        let layouts = section.resolvedSupplementaryLayouts()
        let layoutSection = section.makeCompositionalLayoutSection()
        let boundaryKinds = Set(layoutSection.boundarySupplementaryItems.map(\.elementKind))
        let dotItem = layouts.first { $0.kind == "dot" }?.makeItemSupplementaryItem()

        XCTAssertEqual(boundaryKinds, Set([UICollectionView.elementKindSectionHeader, UICollectionView.elementKindSectionFooter, "badge"]))
        XCTAssertEqual(layoutSection.boundarySupplementaryItems.first { $0.elementKind == UICollectionView.elementKindSectionHeader }?.pinToVisibleBounds, true)
        XCTAssertEqual(layoutSection.boundarySupplementaryItems.first { $0.elementKind == "badge" }?.zIndex, 5)
        XCTAssertEqual(dotItem?.elementKind, "dot")
        XCTAssertTrue(layouts.first { $0.kind == "dot" }?.placement.isItem == true)
    }

    func testSupplementaryBuilderAddsAndRemovesBoundaryItems() {
        let shownSection = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        } header: {
            Header(HeaderView.self, id: "header") { _, _ in }
        } footer: {
            Footer(HeaderView.self, id: "footer") { _, _ in }
        } supplementaries: {
            SectionSupplementary("badge", HeaderView.self, id: "badge") { _, _ in }
                .layout(
                    alignment: .topTrailing,
                    width: .absolute(64),
                    height: .absolute(28)
                )
        }

        let hiddenSection = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        } header: {
            if false {
                Header(HeaderView.self, id: "header") { _, _ in }
            }
        } footer: {
            if false {
                Footer(HeaderView.self, id: "footer") { _, _ in }
            }
        } supplementaries: {
            if false {
                SectionSupplementary("badge", HeaderView.self, id: "badge") { _, _ in }
                    .layout(
                        alignment: .topTrailing,
                        width: .absolute(64),
                        height: .absolute(28)
                    )
            }
        }

        XCTAssertEqual(Set(shownSection.makeCompositionalLayoutSection().boundarySupplementaryItems.map(\.elementKind)), [
            UICollectionView.elementKindSectionHeader,
            UICollectionView.elementKindSectionFooter,
            "badge"
        ])
        XCTAssertTrue(hiddenSection.makeCompositionalLayoutSection().boundarySupplementaryItems.isEmpty)
    }

    func testBackgroundDecorationBuildsDecorationItemAndCanBeCleared() {
        let decoratedSection = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        }
        .backgroundDecoration(
            HeaderView.self,
            contentInsets: .init(top: 1, leading: 2, bottom: 3, trailing: 4),
            zIndex: -2
        )

        let clearedSection = decoratedSection.backgroundDecoration(nil as HeaderView.Type?)
        let decorationItem = decoratedSection.makeCompositionalLayoutSection().decorationItems.first

        XCTAssertEqual(decorationItem?.elementKind, decoratedSection.backgroundDecorationItem?.kind)
        XCTAssertNotEqual(decorationItem?.elementKind, UICollectionView.elementKindSectionBackgroundDecoration)
        XCTAssertEqual(decorationItem?.contentInsets.top, 1)
        XCTAssertEqual(decorationItem?.contentInsets.leading, 2)
        XCTAssertEqual(decorationItem?.contentInsets.bottom, 3)
        XCTAssertEqual(decorationItem?.contentInsets.trailing, 4)
        XCTAssertEqual(decorationItem?.zIndex, -2)
        XCTAssertTrue(clearedSection.makeCompositionalLayoutSection().decorationItems.isEmpty)
    }

    func testBackgroundDecorationBuilderAddsAndRemovesDecorationItem() {
        let decoratedSection = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        } background: {
            if true {
                BackgroundDecoration(
                    HeaderView.self,
                    contentInsets: .init(top: 4, leading: 5, bottom: 6, trailing: 7),
                    zIndex: -3
                )
            }
        }

        let hiddenSection = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        } background: {
            if false {
                BackgroundDecoration(HeaderView.self)
            }
        }

        let decorationItem = decoratedSection.makeCompositionalLayoutSection().decorationItems.first
        XCTAssertEqual(decorationItem?.elementKind, decoratedSection.backgroundDecorationItem?.kind)
        XCTAssertNotEqual(decorationItem?.elementKind, UICollectionView.elementKindSectionBackgroundDecoration)
        XCTAssertEqual(decorationItem?.contentInsets.top, 4)
        XCTAssertEqual(decorationItem?.contentInsets.leading, 5)
        XCTAssertEqual(decorationItem?.contentInsets.bottom, 6)
        XCTAssertEqual(decorationItem?.contentInsets.trailing, 7)
        XCTAssertEqual(decorationItem?.zIndex, -3)
        XCTAssertTrue(hiddenSection.makeCompositionalLayoutSection().decorationItems.isEmpty)
    }

    func testTypedBackgroundDecorationsUseViewSpecificDefaultKinds() {
        let headerBackground = ListBackgroundDecoration(view: HeaderView.self)
        let badgeBackground = ListBackgroundDecoration(view: BadgeView.self)

        XCTAssertNotEqual(headerBackground.kind, badgeBackground.kind)
        XCTAssertTrue(headerBackground.kind.hasPrefix(ListBackgroundDecoration.defaultKind))
        XCTAssertTrue(badgeBackground.kind.hasPrefix(ListBackgroundDecoration.defaultKind))
    }

    func testBackgroundDecorationAppendsToCustomLayoutDecorationItems() {
        let section = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        }
        .layout(.custom(id: "manual-background") { _, _, _ in
            let section = ListSectionLayout.list().makeCompositionalSection(itemSupplementaries: [])
            section.decorationItems = [.background(elementKind: "manual-background")]
            return section
        })
        .backgroundDecoration(kind: "listkit-background")

        let fallbackSection = ListSectionLayout.list().makeCompositionalSection(itemSupplementaries: [])
        fallbackSection.decorationItems = [.background(elementKind: "manual-background")]
        let layoutSection = section.makeCompositionalLayoutSection(fallback: fallbackSection)

        XCTAssertEqual(layoutSection.decorationItems.map(\.elementKind), ["manual-background", "listkit-background"])
    }

    func testAdapterInvalidatesLayoutWhenSectionLayoutMetadataChangesOnly() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let layout = InvalidationTrackingCompositionalLayout()
        collectionView.collectionViewLayout = layout
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)

        let initialApply = expectation(description: "initial apply")
        adapter.apply(transaction: .disabled, completion: { _ in
            initialApply.fulfill()
        }) {
            ListSection(0) {
                Row(1, model: "A", cell: NormalUserCell.self) { _, _, _ in }
            }
            .layout(.list(spacing: 8))
        }
        wait(for: [initialApply], timeout: 1)
        let baselineGeneration = adapter.layoutInvalidationGeneration

        let dataOnlyApply = expectation(description: "data only apply")
        adapter.apply(transaction: .disabled, completion: { _ in
            dataOnlyApply.fulfill()
        }) {
            ListSection(0) {
                Row(1, model: "B", cell: NormalUserCell.self) { _, _, _ in }
            }
            .layout(.list(spacing: 8))
        }
        wait(for: [dataOnlyApply], timeout: 1)
        XCTAssertEqual(adapter.layoutInvalidationGeneration, baselineGeneration)

        let layoutApply = expectation(description: "layout apply")
        adapter.apply(transaction: .disabled, completion: { _ in
            layoutApply.fulfill()
        }) {
            ListSection(0) {
                Row(1, model: "C", cell: NormalUserCell.self) { _, _, _ in }
            }
            .layout(.grid(columns: 2, spacing: 12))
        }
        wait(for: [layoutApply], timeout: 1)
        XCTAssertEqual(adapter.layoutInvalidationGeneration, baselineGeneration + 1)
    }

    func testAdapterInvalidatesLayoutWhenSupplementaryOrBackgroundMetadataChanges() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let layout = InvalidationTrackingCompositionalLayout()
        collectionView.collectionViewLayout = layout
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)

        let initialApply = expectation(description: "initial supplementary apply")
        adapter.apply(transaction: .disabled, completion: { _ in
            initialApply.fulfill()
        }) {
            ListSection(0) {
                Row(1, model: "A", cell: NormalUserCell.self) { _, _, _ in }
            } header: {
                if false {
                    Header(HeaderView.self, id: "header") { _, _ in }
                }
            }
            .backgroundDecoration(nil as HeaderView.Type?)
        }
        wait(for: [initialApply], timeout: 1)
        let baselineGeneration = adapter.layoutInvalidationGeneration

        let metadataApply = expectation(description: "metadata apply")
        adapter.apply(transaction: .disabled, completion: { _ in
            metadataApply.fulfill()
        }) {
            ListSection(0) {
                Row(1, model: "A", cell: NormalUserCell.self) { _, _, _ in }
            } header: {
                Header(HeaderView.self, id: "header") { _, _ in }
                    .layout(
                        height: .absolute(36),
                        pinned: true
                    )
            }
            .backgroundDecoration(
                HeaderView.self,
                contentInsets: .init(top: 8, leading: 16, bottom: 8, trailing: 16)
            )
        }
        wait(for: [metadataApply], timeout: 1)

        XCTAssertEqual(adapter.layoutInvalidationGeneration, baselineGeneration + 1)
    }

    func testAdapterCreatesCompositionalLayoutFromCurrentSections() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)

        adapter.apply(transaction: .disabled) {
            ListSection(0) {
                Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
            }
            .layout(.list(spacing: 8))
        }

        let layout = adapter.makeCompositionalLayout()

        XCTAssertEqual(ObjectIdentifier(type(of: layout)), ObjectIdentifier(UICollectionViewCompositionalLayout.self))
        XCTAssertNotNil(adapter.makeCompositionalSection(for: 0))
    }

    func testCompositionalLayoutConfigurationPreservesUIKitDefaultInsetsUnlessOverridden() {
        let nativeDefault = UICollectionViewCompositionalLayoutConfiguration()
        let listKitDefault = ListCompositionalLayoutConfiguration()

        XCTAssertNil(listKitDefault.scrollDirection)
        XCTAssertNil(listKitDefault.interSectionSpacing)
        XCTAssertEqual(listKitDefault.contentInsetsReference, .systemDefault)
        XCTAssertNil(ListContentInsetsReference.systemDefault.uiKitOverride)
        let resolved = listKitDefault.makeConfiguration()
        XCTAssertEqual(resolved.scrollDirection, nativeDefault.scrollDirection)
        XCTAssertEqual(resolved.interSectionSpacing, nativeDefault.interSectionSpacing)
        XCTAssertEqual(resolved.contentInsetsReference, nativeDefault.contentInsetsReference)
    }

    func testCompositionalLayoutConfigurationAppliesExplicitInsetsOverride() {
        let configuration = ListCompositionalLayoutConfiguration(
            scrollDirection: .horizontal,
            interSectionSpacing: 12,
            contentInsetsReference: .automatic
        ).makeConfiguration()

        XCTAssertEqual(configuration.scrollDirection, .horizontal)
        XCTAssertEqual(configuration.interSectionSpacing, 12)
        XCTAssertEqual(configuration.contentInsetsReference, .automatic)
    }

    func testUIKitListLayoutPreservesSystemSeparatorDefaultUnlessOverridden() {
        let nativeDefault = UICollectionLayoutListConfiguration(appearance: .plain)
        let inherited = ListUIKitListLayout().makeConfiguration()
        let hidden = ListUIKitListLayout(showsSeparators: false).makeConfiguration()

        XCTAssertNil(ListUIKitListLayout().showsSeparators)
        XCTAssertEqual(inherited.showsSeparators, nativeDefault.showsSeparators)
        XCTAssertFalse(hidden.showsSeparators)
    }

    func testMakeCompositionalLayoutCanBeCreatedBeforeApplyWithoutDiagnostics() {
        let collectionView = UICollectionView(frame: CGRect(x: 0, y: 0, width: 240, height: 120), collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        collectionView.collectionViewLayout = adapter.makeCompositionalLayout(
            diagnostics: ListDiagnosticsOptions(mode: .warning, logsApplySummary: false)
        )

        adapter.apply(transaction: .disabled) {
            ListSection(0) {
                Row(1, model: "A", cell: NormalUserCell.self) { _, _, _ in }
            }
            .layout(.list(spacing: 8))
        }
        collectionView.reloadData()
        collectionView.layoutIfNeeded()

        XCTAssertTrue(adapter.lastLayoutDiagnostics.isEmpty)
    }

    func testMakeCompositionalLayoutReportsUnresolvedLegacyLayoutID() {
        let collectionView = UICollectionView(frame: CGRect(x: 0, y: 0, width: 240, height: 120), collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        adapter.apply(options: ListApplyOptions(
            transaction: .disabled,
            diagnostics: .disabled
        )) {
            ListSection(0) {
                Row(1, model: "A", cell: NormalUserCell.self) { _, _, _ in }
            }
            .layout("legacy")
        }

        collectionView.collectionViewLayout = adapter.makeCompositionalLayout(
            diagnostics: ListDiagnosticsOptions(mode: .warning, logsApplySummary: false)
        )
        collectionView.reloadData()
        collectionView.layoutIfNeeded()

        XCTAssertTrue(adapter.lastLayoutDiagnostics.contains { $0.kind == .unresolvedLayoutID })

        collectionView.collectionViewLayout = adapter.makeCompositionalLayout(
            fallback: { _, _, _ in nil },
            diagnostics: ListDiagnosticsOptions(mode: .warning, logsApplySummary: false)
        )
        collectionView.layoutIfNeeded()

        XCTAssertTrue(adapter.lastLayoutDiagnostics.contains { $0.kind == .unresolvedLayoutID })
    }

    func testMakeCompositionalSectionForOnlySupportsBuiltInSectionLayouts() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        let diagnostics = ListDiagnosticsOptions(mode: .warning, logsApplySummary: false)

        adapter.apply(options: ListApplyOptions(transaction: .disabled, diagnostics: .disabled)) {
            ListSection(0) {
                Row(1, model: "A", cell: NormalUserCell.self) { _, _, _ in }
            }
            .layout("legacy")
        }
        XCTAssertNil(adapter.makeCompositionalSection(for: 0, diagnostics: diagnostics))
        XCTAssertTrue(adapter.lastLayoutDiagnostics.contains { $0.kind == .unresolvedLayoutID })

        adapter.apply(options: ListApplyOptions(transaction: .disabled, diagnostics: .disabled)) {
            ListSection(0) {
                Row(1, model: "A", cell: NormalUserCell.self) { _, _, _ in }
            }
            .layout(.custom(id: "manual") { _, _, _ in
                ListSectionLayout.list().makeCompositionalSection(itemSupplementaries: [])
            })
        }
        XCTAssertNil(adapter.makeCompositionalSection(for: 0, diagnostics: diagnostics))
        XCTAssertTrue(adapter.lastLayoutDiagnostics.contains { $0.message.contains("makeCompositionalLayout(fallback:)") })
    }

    func testAdapterFindsIndexPathsAndScrollsToLastItemByRowID() {
        let collectionView = UICollectionView(frame: CGRect(x: 0, y: 0, width: 200, height: 200), collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)

        adapter.apply(transaction: .disabled) {
            ListSection(10) {
                Row("first", model: "A", cell: NormalUserCell.self) { cell, model, _ in
                    cell.name = model
                }
                Row("second", model: "B", cell: NormalUserCell.self) { cell, model, _ in
                    cell.name = model
                }
            }
            ListSection(20) {
                Row("second", model: "C", cell: NormalUserCell.self) { cell, model, _ in
                    cell.name = model
                }
            }
        }

        XCTAssertEqual(adapter.itemCount(in: 10), 2)
        XCTAssertEqual(adapter.itemCount(in: 20), 1)
        XCTAssertEqual(adapter.indexPaths(forRowID: "second", in: 10), [IndexPath(item: 1, section: 0)])
        XCTAssertEqual(adapter.indexPaths(forRowID: "second"), [IndexPath(item: 1, section: 0), IndexPath(item: 0, section: 1)])
        XCTAssertTrue(adapter.scrollToLastItem(in: 10, animated: false))
        XCTAssertFalse(adapter.scrollToLastItem(in: 999, animated: false))
    }

    func testAdapterAppliesPrebuiltListSections() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        let sections = ListSectionsBuilder<Int>.build {
            ListSection(0) {
                Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
            }
        }

        adapter.apply(sections, transaction: .disabled)

        XCTAssertEqual(adapter.itemCount(in: 0), 1)
    }

    func testAdapterVisibleRefreshAPIsTargetOnlyMatchingVisibleRows() {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 100, height: 44)
        let collectionView = UICollectionView(frame: CGRect(x: 0, y: 0, width: 120, height: 120), collectionViewLayout: layout)
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        var displayCount = 0

        adapter.apply(transaction: .disabled) {
            ListSection(0) {
                Row("first", model: "A", cell: NormalUserCell.self) { cell, model, _ in
                    cell.name = model
                }
                .onDisplay { _, _ in
                    displayCount += 1
                }
                Row("second", model: "B", cell: NormalUserCell.self) { cell, model, _ in
                    cell.name = model
                }
            }
        }
        collectionView.reloadData()
        collectionView.layoutIfNeeded()

        let displayCountBeforeRefresh = displayCount
        let reconfigured = expectation(description: "collection visible row reconfigured")
        _ = adapter.reconfigureRows(
            forRowID: "first",
            in: 0,
            scope: .visible,
            transaction: .disabled
        ) { summary in
            XCTAssertEqual(summary.refreshMetrics.visibleReconfiguredRowCount, 1)
            reconfigured.fulfill()
        }
        wait(for: [reconfigured], timeout: 1)
        XCTAssertEqual(displayCount, displayCountBeforeRefresh)
        XCTAssertEqual(
            adapter.reconfigureRows(forRowID: "missing", in: 0, scope: .visible).matchedTargetCount,
            0
        )
        let reloaded = expectation(description: "collection visible row reloaded")
        _ = adapter.reloadRows(
            forRowID: "first",
            in: 0,
            scope: .visible,
            transaction: .disabled
        ) { summary in
            XCTAssertEqual(summary.refreshMetrics.reloadedRowCount, 1)
            reloaded.fulfill()
        }
        wait(for: [reloaded], timeout: 1)
        XCTAssertEqual(
            adapter.reloadRows(forRowID: "missing", in: 0, scope: .visible).matchedTargetCount,
            0
        )
    }

    func testAdapterRefreshesVisibleItemSupplementaryWhenRefreshIDChanges() {
        let kind = "badge"
        let collectionView = UICollectionView(frame: CGRect(x: 0, y: 0, width: 240, height: 160), collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        var configuredCount = 0
        var badgePrefix = "one"

        func applyBadge(refreshID: Int) -> ListApplySummary {
            let applyCompleted = expectation(description: "badge apply \(refreshID)")
            let result = adapter.apply(transaction: .disabled, completion: { _ in
                applyCompleted.fulfill()
            }) {
                ListSection(0) {
                    Row("first", model: "First", cell: NormalUserCell.self) { cell, model, _ in
                        cell.name = model
                    }
                    Row("second", model: "Second", cell: NormalUserCell.self) { cell, model, _ in
                        cell.name = model
                    }
                } layout: {
                    GridLayout(columns: 2, itemHeight: .absolute(80))
                } supplementaries: {
                    SectionSupplementary(kind, BadgeView.self, id: "badge") { view, context in
                        configuredCount += 1
                        view.value = "\(badgePrefix)-\(context.indexPath.item)"
                        view.configuredIndexPath = context.indexPath
                    }
                    .refreshID(refreshID)
                    .refresh(when: .refreshIDChanges)
                    .itemSupplementaryLayout(
                        anchor: .topTrailing,
                        width: .absolute(20),
                        height: .absolute(20)
                    )
                }
            }
            wait(for: [applyCompleted], timeout: 1)
            return result
        }

        _ = applyBadge(refreshID: 1)
        collectionView.collectionViewLayout = adapter.makeCompositionalLayout()
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        let initialBadgeCount = visibleBadgeViews(in: collectionView, kind: kind).count
        XCTAssertEqual(initialBadgeCount, 2)

        let countBeforeRefresh = configuredCount
        badgePrefix = "two"
        let result = applyBadge(refreshID: 2)
        collectionView.layoutIfNeeded()
        let refreshedBadges = visibleBadgeViews(in: collectionView, kind: kind)

        XCTAssertEqual(result.supplementaryRefreshIDChangedCount, 1)
        XCTAssertEqual(adapter.lastApplySummary.refreshMetrics.visibleReconfiguredSupplementaryCount, initialBadgeCount)
        XCTAssertEqual(configuredCount, countBeforeRefresh + initialBadgeCount)
        XCTAssertEqual(Set(refreshedBadges.map(\.value)), ["two-0", "two-1"])
    }

    func testAdapterDoesNotRefreshVisibleSupplementaryWhenPolicyIsNever() {
        let kind = "badge"
        let collectionView = UICollectionView(frame: CGRect(x: 0, y: 0, width: 240, height: 160), collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        var configuredCount = 0
        var badgePrefix = "one"

        func applyBadge(refreshID: Int) -> ListApplySummary {
            let applyCompleted = expectation(description: "never badge apply \(refreshID)")
            let result = adapter.apply(transaction: .disabled, completion: { _ in
                applyCompleted.fulfill()
            }) {
                ListSection(0) {
                    Row("first", model: "First", cell: NormalUserCell.self) { cell, model, _ in
                        cell.name = model
                    }
                    Row("second", model: "Second", cell: NormalUserCell.self) { cell, model, _ in
                        cell.name = model
                    }
                } layout: {
                    GridLayout(columns: 2, itemHeight: .absolute(80))
                } supplementaries: {
                    SectionSupplementary(kind, BadgeView.self, id: "badge") { view, context in
                        configuredCount += 1
                        view.value = "\(badgePrefix)-\(context.indexPath.item)"
                        view.configuredIndexPath = context.indexPath
                    }
                    .refreshID(refreshID)
                    .refresh(when: .never)
                    .itemSupplementaryLayout(
                        anchor: .topTrailing,
                        width: .absolute(20),
                        height: .absolute(20)
                    )
                }
            }
            wait(for: [applyCompleted], timeout: 1)
            return result
        }

        _ = applyBadge(refreshID: 1)
        collectionView.collectionViewLayout = adapter.makeCompositionalLayout()
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        let initialBadges = visibleBadgeViews(in: collectionView, kind: kind)
        XCTAssertEqual(Set(initialBadges.map(\.value)), ["one-0", "one-1"])

        let countBeforeRefresh = configuredCount
        badgePrefix = "two"
        let result = applyBadge(refreshID: 2)
        collectionView.layoutIfNeeded()
        let badgesAfterApply = visibleBadgeViews(in: collectionView, kind: kind)

        XCTAssertEqual(result.supplementaryRefreshIDChangedCount, 1)
        XCTAssertEqual(adapter.lastApplySummary.refreshMetrics.visibleReconfiguredSupplementaryCount, 0)
        XCTAssertEqual(configuredCount, countBeforeRefresh)
        XCTAssertEqual(Set(badgesAfterApply.map(\.value)), ["one-0", "one-1"])
    }

    func testAdapterClearsTapHandlerFromVisibleSupplementaryWithoutRefreshingIt() {
        let kind = "badge"
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 240, height: 160),
            collectionViewLayout: UICollectionViewFlowLayout()
        )
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)

        func applyBadge(hasTapHandler: Bool) {
            var supplementary: ListSectionSupplementary<Int> = SectionSupplementary(
                kind,
                BadgeView.self,
                id: "badge"
            ) { _, _ in }
                .refresh(when: .never)
                .itemSupplementaryLayout(
                    anchor: .topTrailing,
                    width: .absolute(20),
                    height: .absolute(20)
                )
            if hasTapHandler {
                supplementary = supplementary.onTap { _ in }
            }

            let applyCompleted = expectation(description: "tap handler apply \(hasTapHandler)")
            adapter.apply(transaction: .disabled, completion: { _ in
                applyCompleted.fulfill()
            }) {
                ListSection(0) {
                    Row("first", model: "First", cell: NormalUserCell.self) { _, _, _ in }
                } layout: {
                    GridLayout(columns: 1, itemHeight: .absolute(80))
                } supplementaries: {
                    supplementary
                }
            }
            wait(for: [applyCompleted], timeout: 1)
        }

        applyBadge(hasTapHandler: true)
        collectionView.collectionViewLayout = adapter.makeCompositionalLayout()
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        let visibleBadge = visibleBadgeViews(in: collectionView, kind: kind).first
        XCTAssertEqual(visibleBadge?.gestureRecognizers?.count, 1)

        applyBadge(hasTapHandler: false)
        collectionView.layoutIfNeeded()

        XCTAssertTrue(visibleBadge === visibleBadgeViews(in: collectionView, kind: kind).first)
        XCTAssertTrue(visibleBadge?.gestureRecognizers?.isEmpty == true)
    }

    func testReconfigureVisibleSupplementariesTargetsKindSectionAndRowID() {
        let kind = "badge"
        let collectionView = UICollectionView(frame: CGRect(x: 0, y: 0, width: 240, height: 160), collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        var badgeValues = [
            "first": "A",
            "second": "B"
        ]

        let applyCompleted = expectation(description: "manual badge apply")
        adapter.apply(transaction: .disabled, completion: { _ in
            applyCompleted.fulfill()
        }) {
            ListSection(0) {
                Row("first", model: "First", cell: NormalUserCell.self) { cell, model, _ in
                    cell.name = model
                }
                Row("second", model: "Second", cell: NormalUserCell.self) { cell, model, _ in
                    cell.name = model
                }
            } layout: {
                GridLayout(columns: 2, itemHeight: .absolute(80))
            } supplementaries: {
                SectionSupplementary(kind, BadgeView.self, id: "badge") { view, context in
                    let rowID = context.indexPath.item == 0 ? "first" : "second"
                    view.value = badgeValues[rowID]
                    view.configuredIndexPath = context.indexPath
                }
                .refresh(when: .never)
                .itemSupplementaryLayout(
                    anchor: .topTrailing,
                    width: .absolute(20),
                    height: .absolute(20)
                )
            }
        }
        wait(for: [applyCompleted], timeout: 1)
        collectionView.collectionViewLayout = adapter.makeCompositionalLayout()
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        XCTAssertEqual(Set(visibleBadgeViews(in: collectionView, kind: kind).map(\.value)), ["A", "B"])

        badgeValues["first"] = "A2"
        badgeValues["second"] = "B2"
        let refreshedCount = adapter.reconfigureVisibleSupplementaries(ofKind: kind, forRowID: "first", in: 0)
        collectionView.layoutIfNeeded()
        let badgesAfterRefresh = visibleBadgeViews(in: collectionView, kind: kind)

        XCTAssertEqual(refreshedCount, 1)
        XCTAssertEqual(badgesAfterRefresh.first { $0.configuredIndexPath?.item == 0 }?.value, "A2")
        XCTAssertEqual(badgesAfterRefresh.first { $0.configuredIndexPath?.item == 1 }?.value, "B")
        XCTAssertEqual(adapter.reconfigureVisibleSupplementaries(ofKind: "missing", in: 0), 0)
        XCTAssertEqual(adapter.reconfigureVisibleSupplementaries(ofKind: kind, forRowID: "missing", in: 0), 0)
    }

    func testAdapterInvalidatesLayoutWhenItemSupplementaryLayoutChanges() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        collectionView.collectionViewLayout = InvalidationTrackingCompositionalLayout()
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)

        func applyBadgeLayout(width: CGFloat) {
            let applyCompleted = expectation(description: "badge layout \(width)")
            adapter.apply(transaction: .disabled, completion: { _ in
                applyCompleted.fulfill()
            }) {
                ListSection(0) {
                    Row(1, model: "A", cell: NormalUserCell.self) { _, _, _ in }
                } supplementaries: {
                    SectionSupplementary("badge", BadgeView.self, id: "badge") { _, _ in }
                        .itemSupplementaryLayout(
                            anchor: .topTrailing,
                            width: .absolute(width),
                            height: .absolute(20)
                        )
                }
            }
            wait(for: [applyCompleted], timeout: 1)
        }

        applyBadgeLayout(width: 20)
        let baselineGeneration = adapter.layoutInvalidationGeneration

        applyBadgeLayout(width: 24)

        XCTAssertEqual(adapter.layoutInvalidationGeneration, baselineGeneration + 1)
    }

    func testLayoutDiagnosticsReportsInvalidColumnsDimensionsSpacingAndPlacementConflict() {
        let section = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        }
        .layout(.grid(columns: 0, spacing: -12, itemHeight: .absolute(0)))
        .supplementary("badge", HeaderView.self, id: "badge") { _, _ in }
        .boundarySupplementaryLayout(kind: "badge", width: .absolute(64), height: .absolute(28))
        .itemSupplementaryLayout(kind: "badge", anchor: .topTrailing, width: .absolute(0), height: .fractionalHeight(-0.5))

        let issues = ListDiagnostics.validate([section])

        XCTAssertTrue(issues.contains { $0.kind == .invalidLayout })
        XCTAssertTrue(issues.contains { $0.kind == .conflictingSupplementaryLayout })
    }

    func testApplyPlannerBuildsSharedSummaryAndRefreshPlan() {
        let keptOld = makeTestListNode("kept", refreshID: 1)
        let deletedOld = makeTestListNode("deleted", refreshID: 1)
        let keptNew = makeTestListNode(
            "kept",
            refreshID: 2,
            policy: .refreshIDChanges,
            scope: .allMatching
        )
        let insertedNew = makeTestListNode("inserted", refreshID: 1)
        let headerOld = makeTestListNode("header", refreshID: 1, role: .supplementary)
        let headerNew = makeTestListNode("header", refreshID: 2, policy: .refreshIDChanges, role: .supplementary)

        let plan = ListApplyPlanner.makePlan(
            old: [
                ListSectionSnapshot(sectionID: AnyListID(0), rows: [keptOld, deletedOld], supplementaries: [headerOld])
            ],
            new: [
                ListSectionSnapshot(sectionID: AnyListID(0), rows: [keptNew, insertedNew], supplementaries: [headerNew])
            ],
            options: ListApplyOptions(
                transaction: .disabled,
                diagnostics: .disabled
            ),
            diagnosticsIssues: []
        )

        XCTAssertTrue(plan.shouldApplyDiffable)
        XCTAssertEqual(plan.snapshotReconfigureItems, [keptNew.identity])
        XCTAssertTrue(plan.snapshotLayoutInvalidationItems.isEmpty)
        XCTAssertTrue(plan.snapshotReloadItems.isEmpty)
        XCTAssertTrue(plan.shouldRunVisibleRefresh)
        XCTAssertEqual(plan.initialSummary.insertedRowCount, 1)
        XCTAssertEqual(plan.initialSummary.deletedRowCount, 1)
        XCTAssertEqual(plan.initialSummary.keptRowCount, 1)
        XCTAssertEqual(plan.initialSummary.rowRefreshIDChangedCount, 1)
        XCTAssertEqual(plan.initialSummary.refreshMetrics.snapshotReconfiguredRowCount, 1)
        XCTAssertEqual(plan.initialSummary.supplementaryRefreshIDChangedCount, 1)
        XCTAssertEqual(
            plan.completedSummary(
                visibleReconfiguredRowCount: 3,
                visibleReloadedRowCount: 1,
                visibleReconfiguredSupplementaryCount: 2
            ).refreshMetrics.visibleReconfiguredSupplementaryCount,
            2
        )
        XCTAssertEqual(
            plan.completedSummary(
                visibleReconfiguredRowCount: 3,
                visibleReloadedRowCount: 1,
                visibleReconfiguredSupplementaryCount: 2
            ).refreshMetrics.reloadedRowCount,
            1
        )
    }

    func testApplyPlannerRoutesEveryTriggerScopeAndRowActionCombination() {
        let triggers: [ListRefreshTrigger] = [
            .automatic,
            .refreshIDChanges,
            .everyApply,
            .never
        ]
        let scopes: [ListRefreshScope] = [.visible, .allMatching]
        let actions: [ListRowRefreshAction] = [
            .reconfigure(layout: .none),
            .reconfigure(layout: .invalidate),
            .reload
        ]

        for trigger in triggers {
            for scope in scopes {
                for action in actions {
                    let old = makeTestListNode(
                        "row",
                        refreshID: 1,
                        policy: trigger,
                        scope: scope,
                        action: action
                    )
                    let new = makeTestListNode(
                        "row",
                        refreshID: 2,
                        policy: trigger,
                        scope: scope,
                        action: action
                    )
                    let plan = ListApplyPlanner.makePlan(
                        old: [ListSectionSnapshot(sectionID: AnyListID(0), rows: [old], supplementaries: [])],
                        new: [ListSectionSnapshot(sectionID: AnyListID(0), rows: [new], supplementaries: [])],
                        options: ListApplyOptions(transaction: .disabled, diagnostics: .disabled),
                        diagnosticsIssues: []
                    )

                    let shouldRefresh = trigger != .never
                    let shouldSnapshot = shouldRefresh && scope == .allMatching
                    let shouldReload = shouldSnapshot && action == .reload
                    let shouldReconfigure = shouldSnapshot && action != .reload
                    let shouldInvalidate = shouldReconfigure
                        && action == .reconfigure(layout: .invalidate)

                    XCTAssertEqual(plan.snapshotReloadItems, shouldReload ? [new.identity] : [])
                    XCTAssertEqual(plan.snapshotReconfigureItems, shouldReconfigure ? [new.identity] : [])
                    XCTAssertEqual(plan.snapshotLayoutInvalidationItems, shouldInvalidate ? [new.identity] : [])
                    XCTAssertEqual(
                        plan.initialSummary.refreshMetrics.snapshotReconfiguredRowCount,
                        shouldReconfigure ? 1 : 0
                    )
                    XCTAssertEqual(
                        plan.initialSummary.refreshMetrics.reloadedRowCount,
                        shouldReload ? 1 : 0
                    )
                    XCTAssertEqual(plan.shouldRunVisibleRefresh, shouldRefresh && scope == .visible)
                }
            }
        }
    }

    func testApplyPlannerResolvesDuplicateActionConflictToStrongestAction() {
        let old = makeTestListNode(
            "row",
            refreshID: 1,
            policy: .refreshIDChanges,
            scope: .allMatching
        )
        let reconfigure = makeTestListNode(
            "row",
            refreshID: 2,
            policy: .refreshIDChanges,
            scope: .allMatching,
            action: .reconfigure(layout: .none)
        )
        let invalidate = makeTestListNode(
            "row",
            refreshID: 2,
            policy: .refreshIDChanges,
            scope: .allMatching,
            action: .reconfigure(layout: .invalidate)
        )
        let reload = makeTestListNode(
            "row",
            refreshID: 2,
            policy: .refreshIDChanges,
            scope: .allMatching,
            action: .reload
        )

        let plan = ListApplyPlanner.makePlan(
            old: [ListSectionSnapshot(sectionID: AnyListID(0), rows: [old], supplementaries: [])],
            new: [ListSectionSnapshot(
                sectionID: AnyListID(0),
                rows: [reconfigure, invalidate, reload],
                supplementaries: []
            )],
            options: ListApplyOptions(transaction: .disabled, diagnostics: .disabled),
            diagnosticsIssues: []
        )

        XCTAssertTrue(plan.snapshotReconfigureItems.isEmpty)
        XCTAssertTrue(plan.snapshotLayoutInvalidationItems.isEmpty)
        XCTAssertEqual(plan.snapshotReloadItems, [reload.identity])
        XCTAssertEqual(plan.initialSummary.refreshMetrics.snapshotReconfiguredRowCount, 0)
        XCTAssertEqual(plan.initialSummary.refreshMetrics.reloadedRowCount, 1)
    }

    func testVisibleRefreshRuleUsesTriggerAndScope() {
        let oldVersion = makeTestListNode("row", refreshID: 1)
        let stableAutomatic = makeTestListNode("row", refreshID: 1)
        let changedAutomatic = makeTestListNode("row", refreshID: 2)
        let unversionedOld = makeTestListNode("row", refreshID: nil)
        let unversionedNew = makeTestListNode("row", refreshID: nil)
        let changedDiffable = makeTestListNode(
            "row",
            refreshID: 2,
            policy: .refreshIDChanges,
            scope: .allMatching
        )
        let changedVisible = makeTestListNode("row", refreshID: 2, policy: .refreshIDChanges)
        let stableAlways = makeTestListNode("row", refreshID: 1, policy: .everyApply)

        XCTAssertFalse(
            ListApplyPlanner.shouldRefreshVisibleRow(
                stableAutomatic,
                oldRow: oldVersion
            )
        )
        XCTAssertTrue(
            ListApplyPlanner.shouldRefreshVisibleRow(
                changedAutomatic,
                oldRow: oldVersion
            )
        )
        XCTAssertTrue(
            ListApplyPlanner.shouldRefreshVisibleRow(
                unversionedNew,
                oldRow: unversionedOld
            )
        )
        XCTAssertFalse(
            ListApplyPlanner.shouldRefreshVisibleRow(
                changedDiffable,
                oldRow: oldVersion
            )
        )
        XCTAssertTrue(
            ListApplyPlanner.shouldRefreshVisibleRow(
                changedVisible,
                oldRow: oldVersion
            )
        )
        XCTAssertTrue(
            ListApplyPlanner.shouldRefreshVisibleRow(
                stableAlways,
                oldRow: oldVersion
            )
        )

        let stableSupplementary = makeTestListNode(
            "header",
            refreshID: 1,
            role: .supplementary
        )
        let changedSupplementary = makeTestListNode(
            "header",
            refreshID: 2,
            role: .supplementary
        )
        XCTAssertFalse(
            ListApplyPlanner.shouldRefreshVisibleSupplementary(
                stableSupplementary,
                oldSupplementary: stableSupplementary
            )
        )
        XCTAssertTrue(
            ListApplyPlanner.shouldRefreshVisibleSupplementary(
                changedSupplementary,
                oldSupplementary: stableSupplementary
            )
        )
    }

    func testApplyPlannerReloadActionOnlyTargetsKeptRows() {
        let oldRows = [
            makeTestListNode("kept", refreshID: 1),
            makeTestListNode("deleted", refreshID: 1)
        ]
        let newRows = [
            makeTestListNode(
                "kept",
                refreshID: 1,
                policy: .everyApply,
                scope: .allMatching,
                action: .reload
            ),
            makeTestListNode(
                "inserted",
                refreshID: 1,
                policy: .everyApply,
                scope: .allMatching,
                action: .reload
            )
        ]

        let plan = ListApplyPlanner.makePlan(
            old: [ListSectionSnapshot(sectionID: AnyListID(0), rows: oldRows, supplementaries: [])],
            new: [ListSectionSnapshot(sectionID: AnyListID(0), rows: newRows, supplementaries: [])],
            options: ListApplyOptions(
                transaction: .disabled,
                diagnostics: .disabled
            ),
            diagnosticsIssues: []
        )

        XCTAssertEqual(plan.snapshotReloadItems, [newRows[0].identity])
        XCTAssertTrue(plan.snapshotReconfigureItems.isEmpty)
        XCTAssertFalse(plan.shouldRunVisibleRefresh)
        XCTAssertEqual(plan.initialSummary.refreshMetrics.snapshotReconfiguredRowCount, 0)
        XCTAssertEqual(plan.initialSummary.refreshMetrics.reloadedRowCount, 1)
    }

    func testApplyPlannerStopsBeforeDiffableForDiagnosticsWarning() {
        let oldRows = [makeTestListNode("kept", refreshID: 1)]
        let newRows = [makeTestListNode(
            "kept",
            refreshID: 2,
            policy: .refreshIDChanges,
            scope: .allMatching
        )]
        let issue = ListDiagnosticsIssue(
            kind: .duplicateRow,
            message: "ListKit: duplicate row identity"
        )

        let plan = ListApplyPlanner.makePlan(
            old: [ListSectionSnapshot(sectionID: AnyListID(0), rows: oldRows, supplementaries: [])],
            new: [ListSectionSnapshot(sectionID: AnyListID(0), rows: newRows, supplementaries: [])],
            options: ListApplyOptions(
                transaction: .disabled,
                diagnostics: .init(mode: .warning, logsApplySummary: false)
            ),
            diagnosticsIssues: [issue]
        )

        XCTAssertFalse(plan.shouldApplyDiffable)
        XCTAssertTrue(plan.snapshotReconfigureItems.isEmpty)
        XCTAssertTrue(plan.snapshotLayoutInvalidationItems.isEmpty)
        XCTAssertTrue(plan.snapshotReloadItems.isEmpty)
        XCTAssertEqual(plan.initialSummary.refreshMetrics.snapshotReconfiguredRowCount, 0)
        XCTAssertEqual(plan.initialSummary.refreshMetrics.visibleReconfiguredRowCount, 0)
        XCTAssertEqual(plan.initialSummary.diagnosticsIssues, [issue])
    }

    func testEventRouterDispatchesTypedEventsOnly() {
        let router = ListEventRouter<Int>()
        var receivedEvent: UserEvent?
        var receivedContext: Int?

        router.on(UserEvent.self) { event, context in
            receivedEvent = event
            receivedContext = context
        }

        router.dispatch(IgnoredEvent(), context: 7)
        XCTAssertNil(receivedEvent)

        router.dispatch(UserEvent.headerTap, context: 9)
        XCTAssertEqual(receivedEvent, .headerTap)
        XCTAssertEqual(receivedContext, 9)
    }
}

private struct User: Hashable, Sendable {
    let id: Int
    let name: String
    let isVIP: Bool
    let version: Int
}

private struct UserProfile: Hashable, Sendable {
    let userID: String
    let accountID: String
    let name: String
}

private struct IdentifiedUser: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
}

private enum UserEvent: ListEvent, Equatable {
    case avatarTap(userID: Int)
    case buttonTap(userID: Int)
    case headerTap
}

private struct IgnoredEvent: ListEvent {}

private final class NormalUserCell: UICollectionViewCell {
    var name: String?
    var prepareForReuseCount = 0

    override func prepareForReuse() {
        prepareForReuseCount += 1
        super.prepareForReuse()
    }
}

private final class VIPUserCell: UICollectionViewCell {
    var name: String?
}

private final class HeaderView: UICollectionReusableView {
    var title: String?
}

private final class BadgeView: UICollectionReusableView {
    var value: String?
    var configuredIndexPath: IndexPath?
}

private enum ReuseFeatureA {
    final class SharedCell: UICollectionViewCell {}
    final class SharedSupplementary: UICollectionReusableView {}
}

private enum ReuseFeatureB {
    final class SharedCell: UICollectionViewCell {}
    final class SharedSupplementary: UICollectionReusableView {}
}

private final class EventCell: UICollectionViewCell {
    var onButtonTap: (@MainActor () -> Void)?
}

private final class EmptyStateCell: UICollectionViewCell {
    var message: String?
}

private final class LoadingStateCell: UICollectionViewCell {
    var message: String?
}

private final class FailureStateCell: UICollectionViewCell {
    var message: String?
}

private final class ScrollDelegateSpy: NSObject, UIScrollViewDelegate {
    var didScrollCount = 0

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        didScrollCount += 1
    }
}

private final class FlowLayoutDelegateSpy: NSObject, UICollectionViewDelegateFlowLayout {
    var sizeRequestCount = 0

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        sizeRequestCount += 1
        return CGSize(width: 44, height: 55)
    }
}

private final class CollectionDisplayDelegateSpy: NSObject, UICollectionViewDelegate {
    var didEndDisplayingCount = 0

    func collectionView(
        _ collectionView: UICollectionView,
        didEndDisplaying cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        didEndDisplayingCount += 1
    }
}

private final class CollectionSelectionDelegateSpy: NSObject, UICollectionViewDelegate {
    var selectedIndexPath: IndexPath?

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        selectedIndexPath = indexPath
    }
}

@MainActor
private func visibleBadgeViews(in collectionView: UICollectionView, kind: String) -> [BadgeView] {
    collectionView.layoutIfNeeded()
    return collectionView.visibleSupplementaryViews(ofKind: kind).compactMap { $0 as? BadgeView }
}

private final class InvalidationTrackingCompositionalLayout: UICollectionViewCompositionalLayout {
    var invalidateCount = 0

    init() {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(44)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: itemSize, subitem: item, count: 1)
        super.init(section: NSCollectionLayoutSection(group: group))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func invalidateLayout() {
        invalidateCount += 1
        super.invalidateLayout()
    }
}

private func makeTestListNode(
    _ id: String,
    refreshID: Int?,
    sectionID: Int = 0,
    policy: ListRefreshTrigger = .automatic,
    scope: ListRefreshScope = .visible,
    action: ListRowRefreshAction = .reconfigure(layout: .none),
    supplementaryAction: ListSupplementaryRefreshAction = .reconfigureVisible(layout: .none),
    role: ListNodeRole = .row
) -> ListNodeSnapshot {
    ListNodeSnapshot(
        identity: AnyListIdentity(
            sectionID: AnyListID(sectionID),
            rowID: AnyListID(id),
            presentationID: role == .row ? ObjectIdentifier(NormalUserCell.self) : ObjectIdentifier(HeaderView.self),
            variant: role == .row ? nil : AnyListID("supplementary")
        ),
        refreshID: refreshID.map(AnyListID.init),
        refreshRule: role == .row
            ? .row(ListRowRefreshRule(trigger: policy, scope: scope, action: action))
            : .supplementary(ListSupplementaryRefreshRule(
                trigger: policy,
                action: supplementaryAction
            )),
        role: role
    )
}
