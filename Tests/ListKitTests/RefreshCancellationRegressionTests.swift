import UIKit
import XCTest

@testable import ListKit

@MainActor final class RefreshCancellationRegressionTests: XCTestCase {
  func testCollectionCancelQueuedApplyFromActiveCompletion() async throws {
    try await collectionCancellation(mode: 0)
  }
  func testCollectionCancelQueuedApplyBeforeCompletion() async throws {
    try await collectionCancellation(mode: 1)
  }
  func testCollectionCancelAfterCommitWaitsForLayout() async throws {
    try await collectionCancellation(mode: 2)
  }
  private func collectionCancellation(mode: Int) async throws {
    let collection = CancellationHeldCollection(
      frame: CGRect(x: 0, y: 0, width: 320, height: 400),
      collectionViewLayout: UICollectionViewFlowLayout())
    let adapter = CollectionListAdapter<Int>(collectionView: collection)
    let entered = expectation(description: "held layout")
    collection.onHeld = { entered.fulfill() }
    var queued: Task<ListApplySummary, Never>?
    var activeStates: [ListApplyCompletionState] = []
    let options = ListApplyOptions(
      transaction: ListTransaction.disabled.layoutAnimation(.enabled).updatePolicy(.serial),
      applicationMode: .reloadData)
    func section(_ id: Int) -> ListSection<Int> {
      ListSection(id) { Row(0, model: id, cell: UICollectionViewCell.self) { _, _, _ in } }
    }
    if mode == 2 {
      let active = Task { @MainActor in await adapter.apply(options: options) { section(0) } }
      await fulfillment(of: [entered], timeout: 3)
      active.cancel()
      await Task.yield()
      try XCTUnwrap(collection.releaseHeld)(true)
      let result = await active.value
      XCTAssertEqual(result.animation.completionState, .completed)
      XCTAssertEqual(adapter.sectionIdentifier(at: 0), 0)
      return
    }
    adapter.apply(
      options: options,
      completion: { summary in
        activeStates.append(summary.animation.completionState)
        if mode == 0 { queued?.cancel() }
      }
    ) { section(0) }
    await fulfillment(of: [entered], timeout: 3)
    let built = expectation(description: "queued builder")
    queued = Task { @MainActor in
      await adapter.apply(transaction: .disabled.updatePolicy(.serial)) {
        built.fulfill()
        return [section(1)]
      }
    }
    await fulfillment(of: [built], timeout: 3)
    if mode == 1 {
      queued?.cancel()
      let result = await queued!.value
      XCTAssertEqual(result.animation.completionState, .cancelledBeforeCommit)
      try XCTUnwrap(collection.releaseHeld)(true)
    } else {
      try XCTUnwrap(collection.releaseHeld)(true)
      let result = await queued!.value
      XCTAssertEqual(result.animation.completionState, .cancelledBeforeCommit)
    }
    XCTAssertEqual(activeStates, [.completed])
    XCTAssertEqual(
      adapter.sectionIdentifier(at: 0), 0,
      "Cancelled queued model must never become the committed tree")
  }

  func testTableCancelQueuedApplyFromActiveCompletion() async throws {
    try await tableCancellation(mode: 0)
  }
  func testTableCancelQueuedApplyBeforeCompletion() async throws {
    try await tableCancellation(mode: 1)
  }
  func testTableCancelAfterCommitWaitsForLayout() async throws {
    try await tableCancellation(mode: 2)
  }
  private func tableCancellation(mode: Int) async throws {
    let table = CancellationHeldTable(
      frame: CGRect(x: 0, y: 0, width: 320, height: 400), style: .plain)
    let adapter = TableListAdapter<Int>(tableView: table)
    let entered = expectation(description: "held layout")
    table.onHeld = { entered.fulfill() }
    var queued: Task<ListApplySummary, Never>?
    var activeStates: [ListApplyCompletionState] = []
    let options = ListApplyOptions(
      transaction: ListTransaction.disabled.layoutAnimation(.enabled).updatePolicy(.serial),
      applicationMode: .reloadData)
    func section(_ id: Int) -> TableSection<Int> {
      TableSection(id) {
        TableRow(0, model: id, cell: UITableViewCell.self) { _, _, _ in }.height(.fixed(40))
      }
    }
    if mode == 2 {
      let active = Task { @MainActor in await adapter.apply(options: options) { section(0) } }
      await fulfillment(of: [entered], timeout: 3)
      active.cancel()
      await Task.yield()
      try XCTUnwrap(table.releaseHeld)(true)
      let result = await active.value
      XCTAssertEqual(result.animation.completionState, .completed)
      XCTAssertEqual(adapter.sectionIdentifier(at: 0), 0)
      return
    }
    adapter.apply(
      options: options,
      completion: { summary in
        activeStates.append(summary.animation.completionState)
        if mode == 0 { queued?.cancel() }
      }
    ) { section(0) }
    await fulfillment(of: [entered], timeout: 3)
    let built = expectation(description: "queued builder")
    queued = Task { @MainActor in
      await adapter.apply(transaction: .disabled.updatePolicy(.serial)) {
        built.fulfill()
        return [section(1)]
      }
    }
    await fulfillment(of: [built], timeout: 3)
    if mode == 1 {
      queued?.cancel()
      let result = await queued!.value
      XCTAssertEqual(result.animation.completionState, .cancelledBeforeCommit)
      try XCTUnwrap(table.releaseHeld)(true)
    } else {
      try XCTUnwrap(table.releaseHeld)(true)
      let result = await queued!.value
      XCTAssertEqual(result.animation.completionState, .cancelledBeforeCommit)
    }
    XCTAssertEqual(activeStates, [.completed])
    XCTAssertEqual(adapter.sectionIdentifier(at: 0), 0)
  }
}

@MainActor private final class CancellationHeldCollection: UICollectionView {
  var onHeld: (() -> Void)?
  var releaseHeld: ((Bool) -> Void)?
  override func performBatchUpdates(_ updates: (() -> Void)?, completion: ((Bool) -> Void)? = nil) {
    guard let onHeld else {
      super.performBatchUpdates(updates, completion: completion)
      return
    }
    self.onHeld = nil
    updates?()
    releaseHeld = completion
    onHeld()
  }
}
@MainActor private final class CancellationHeldTable: UITableView {
  var onHeld: (() -> Void)?
  var releaseHeld: ((Bool) -> Void)?
  override func performBatchUpdates(_ updates: (() -> Void)?, completion: ((Bool) -> Void)? = nil) {
    guard let onHeld else {
      super.performBatchUpdates(updates, completion: completion)
      return
    }
    self.onHeld = nil
    updates?()
    releaseHeld = completion
    onHeld()
  }
}

extension RefreshCancellationRegressionTests {
  private enum QueuedOperation { case row, section, reloadAll, mergedRow }
  func testCollectionCompletionCancelsRowRefreshBeforeCommit() async throws {
    try await checkCollectionQueuedCancellation(.row)
  }
  func testCollectionCompletionCancelsSectionReloadBeforeCommit() async throws {
    try await checkCollectionQueuedCancellation(.section)
  }
  func testCollectionCompletionCancelsReloadAllBeforeCommit() async throws {
    try await checkCollectionQueuedCancellation(.reloadAll)
  }
  func testCollectionCompletionCancelsMergedRowSubscriberBeforeCommit() async throws {
    try await checkCollectionQueuedCancellation(.mergedRow)
  }
  private func checkCollectionQueuedCancellation(_ operation: QueuedOperation) async throws {
    let collection = CancellationHeldCollection(
      frame: CGRect(x: 0, y: 0, width: 320, height: 400),
      collectionViewLayout: UICollectionViewFlowLayout())
    let adapter = CollectionListAdapter<Int>(collectionView: collection)
    let held = expectation(description: "active layout held")
    collection.onHeld = { held.fulfill() }
    var queued: Task<ListApplyCompletionState, Never>?
    let options = ListApplyOptions(
      transaction: .disabled.layoutAnimation(.enabled).updatePolicy(.serial),
      applicationMode: .reloadData)
    adapter.apply(options: options, completion: { _ in queued?.cancel() }) {
      ListSection(0) { Row(0, model: 0, cell: UICollectionViewCell.self) { _, _, _ in } }
    }
    await fulfillment(of: [held], timeout: 3)
    let queuedStarted = expectation(description: "async request entered")
    var cancelledRefresh: ListRefreshSummary?
    var cancelledApply: ListApplySummary?
    queued = Task { @MainActor in
      queuedStarted.fulfill()
      switch operation {
      case .row, .mergedRow:
        let result = await adapter.reloadRows(
          forRowID: 0,
          transaction: .disabled.updatePolicy(operation == .mergedRow ? .coalesceLatest : .serial))
        cancelledRefresh = result
        return result.animation.completionState
      case .section:
        let result = await adapter.reloadSections([0], transaction: .disabled)
        cancelledRefresh = result
        return result.animation.completionState
      case .reloadAll:
        let result = await adapter.reloadAll(transaction: .disabled)
        cancelledApply = result
        return result.animation.completionState
      }
    }
    await fulfillment(of: [queuedStarted], timeout: 3)
    let survivor = expectation(description: "next subscriber completes exactly once")
    survivor.assertForOverFulfill = true
    var survivorResult: ListRefreshSummary?
    // The merged case shares a target with the cancelled stronger action.
    // Other cases verify that removing the only subscriber still advances the queue.
    adapter.reconfigureRows(
      forRowID: 0, transaction: .disabled,
      completion: { result in
        survivorResult = result
        survivor.fulfill()
      })
    try XCTUnwrap(collection.releaseHeld)(true)
    let state = await queued!.value
    await fulfillment(of: [survivor], timeout: 3)
    XCTAssertEqual(state, .cancelledBeforeCommit)
    if let cancelledRefresh {
      XCTAssertEqual(cancelledRefresh.matchedTargetCount, 0)
      XCTAssertEqual(cancelledRefresh.refreshMetrics, ListRefreshMetrics())
    }
    if let cancelledApply { XCTAssertEqual(cancelledApply.refreshMetrics, ListRefreshMetrics()) }
    let result = try XCTUnwrap(survivorResult)
    XCTAssertEqual(result.animation.completionState, .completed)
    XCTAssertEqual(result.refreshMetrics.snapshotReconfiguredRowCount, 1)
    XCTAssertEqual(result.refreshMetrics.reloadedRowCount, 0)
    XCTAssertEqual(adapter.sectionIdentifier(at: 0), 0)
  }
  func testTableCompletionCancelsRowRefreshBeforeCommit() async throws {
    try await checkTableQueuedCancellation(.row)
  }
  func testTableCompletionCancelsSectionReloadBeforeCommit() async throws {
    try await checkTableQueuedCancellation(.section)
  }
  func testTableCompletionCancelsReloadAllBeforeCommit() async throws {
    try await checkTableQueuedCancellation(.reloadAll)
  }
  func testTableCompletionCancelsMergedRowSubscriberBeforeCommit() async throws {
    try await checkTableQueuedCancellation(.mergedRow)
  }
  private func checkTableQueuedCancellation(_ operation: QueuedOperation) async throws {
    let table = CancellationHeldTable(
      frame: CGRect(x: 0, y: 0, width: 320, height: 400), style: .plain)
    let adapter = TableListAdapter<Int>(tableView: table)
    let held = expectation(description: "active layout held")
    table.onHeld = { held.fulfill() }
    var queued: Task<ListApplyCompletionState, Never>?
    let options = ListApplyOptions(
      transaction: .disabled.layoutAnimation(.enabled).updatePolicy(.serial),
      applicationMode: .reloadData)
    adapter.apply(options: options, completion: { _ in queued?.cancel() }) {
      TableSection(0) { TableRow(0, model: 0, cell: UITableViewCell.self) { _, _, _ in } }
    }
    await fulfillment(of: [held], timeout: 3)
    let queuedStarted = expectation(description: "async request entered")
    var cancelledRefresh: ListRefreshSummary?
    var cancelledApply: ListApplySummary?
    queued = Task { @MainActor in
      queuedStarted.fulfill()
      switch operation {
      case .row, .mergedRow:
        let result = await adapter.reloadRows(
          forRowID: 0,
          transaction: .disabled.updatePolicy(operation == .mergedRow ? .coalesceLatest : .serial))
        cancelledRefresh = result
        return result.animation.completionState
      case .section:
        let result = await adapter.reloadSections([0], transaction: .disabled)
        cancelledRefresh = result
        return result.animation.completionState
      case .reloadAll:
        let result = await adapter.reloadAll(transaction: .disabled)
        cancelledApply = result
        return result.animation.completionState
      }
    }
    await fulfillment(of: [queuedStarted], timeout: 3)
    let survivor = expectation(description: "next subscriber completes exactly once")
    survivor.assertForOverFulfill = true
    var survivorResult: ListRefreshSummary?
    // The merged case shares a target with the cancelled stronger action.
    // Other cases verify that removing the only subscriber still advances the queue.
    adapter.reconfigureRows(
      forRowID: 0, transaction: .disabled,
      completion: { result in
        survivorResult = result
        survivor.fulfill()
      })
    try XCTUnwrap(table.releaseHeld)(true)
    let state = await queued!.value
    await fulfillment(of: [survivor], timeout: 3)
    XCTAssertEqual(state, .cancelledBeforeCommit)
    if let cancelledRefresh {
      XCTAssertEqual(cancelledRefresh.matchedTargetCount, 0)
      XCTAssertEqual(cancelledRefresh.refreshMetrics, ListRefreshMetrics())
    }
    if let cancelledApply { XCTAssertEqual(cancelledApply.refreshMetrics, ListRefreshMetrics()) }
    let result = try XCTUnwrap(survivorResult)
    XCTAssertEqual(result.animation.completionState, .completed)
    XCTAssertEqual(result.refreshMetrics.snapshotReconfiguredRowCount, 1)
    XCTAssertEqual(result.refreshMetrics.reloadedRowCount, 0)
    XCTAssertEqual(adapter.sectionIdentifier(at: 0), 0)
  }
}

extension RefreshCancellationRegressionTests {
  func testCollectionCancelledQueuedRefreshPlanReportsNoWork() async throws {
    let collection = CancellationHeldCollection(
      frame: CGRect(x: 0, y: 0, width: 320, height: 400),
      collectionViewLayout: UICollectionViewFlowLayout())
    let adapter = CollectionListAdapter<Int>(collectionView: collection)
    let held = expectation(description: "active apply held")
    collection.onHeld = { held.fulfill() }
    func section(_ version: Int) -> ListSection<Int> {
      ListSection(0) {
        Row(0, model: version, cell: UICollectionViewCell.self) { _, _, _ in }
          .refreshID(version).refresh(when: .refreshIDChanges, scope: .allMatching)
      }
    }
    adapter.apply(
      options: .init(
        transaction: .disabled.layoutAnimation(.enabled).updatePolicy(.serial),
        applicationMode: .reloadData), completion: { _ in }
    ) { section(0) }
    await fulfillment(of: [held], timeout: 3)
    let queuedStarted = expectation(description: "changed refresh plan queued")
    let queued = Task { @MainActor in
      await adapter.apply(transaction: .disabled.updatePolicy(.serial)) {
        queuedStarted.fulfill()
        return [section(1)]
      }
    }
    await fulfillment(of: [queuedStarted], timeout: 3)
    queued.cancel()
    let result = await queued.value
    try XCTUnwrap(collection.releaseHeld)(true)
    XCTAssertEqual(result.animation.completionState, .cancelledBeforeCommit)
    XCTAssertEqual(result.refreshMetrics, ListRefreshMetrics())
  }
  func testTableCancelledQueuedRefreshPlanReportsNoWork() async throws {
    let table = CancellationHeldTable(
      frame: CGRect(x: 0, y: 0, width: 320, height: 400), style: .plain)
    let adapter = TableListAdapter<Int>(tableView: table)
    let held = expectation(description: "active apply held")
    table.onHeld = { held.fulfill() }
    func section(_ version: Int) -> TableSection<Int> {
      TableSection(0) {
        TableRow(0, model: version, cell: UITableViewCell.self) { _, _, _ in }
          .refreshID(version).refresh(when: .refreshIDChanges, scope: .allMatching)
      }
    }
    adapter.apply(
      options: .init(
        transaction: .disabled.layoutAnimation(.enabled).updatePolicy(.serial),
        applicationMode: .reloadData), completion: { _ in }
    ) { section(0) }
    await fulfillment(of: [held], timeout: 3)
    let queuedStarted = expectation(description: "changed refresh plan queued")
    let queued = Task { @MainActor in
      await adapter.apply(transaction: .disabled.updatePolicy(.serial)) {
        queuedStarted.fulfill()
        return [section(1)]
      }
    }
    await fulfillment(of: [queuedStarted], timeout: 3)
    queued.cancel()
    let result = await queued.value
    try XCTUnwrap(table.releaseHeld)(true)
    XCTAssertEqual(result.animation.completionState, .cancelledBeforeCommit)
    XCTAssertEqual(result.refreshMetrics, ListRefreshMetrics())
  }
}

@MainActor final class RefreshQueueBoundaryRegressionTests: XCTestCase {
  func testCollectionRejectedQueuedApplyAdvancesSerialQueue() async throws {
    let collection = CancellationHeldCollection(
      frame: CGRect(x: 0, y: 0, width: 320, height: 400),
      collectionViewLayout: UICollectionViewFlowLayout())
    let adapter = CollectionListAdapter<Int>(collectionView: collection)
    let held = expectation(description: "held active mutation")
    collection.onHeld = { held.fulfill() }
    func section(_ id: Int, version: Int = 0) -> ListSection<Int> {
      ListSection(id) {
        Row(0, model: version, cell: UICollectionViewCell.self) { _, _, _ in }.refreshID(version)
          .refresh(when: .refreshIDChanges, scope: .allMatching)
      }
    }

    adapter.apply(
      options: .init(
        transaction: .disabled.layoutAnimation(.enabled).updatePolicy(.serial),
        applicationMode: .reloadData), completion: { _ in }
    ) { section(0) }
    await fulfillment(of: [held], timeout: 3)
    let rejected = expectation(description: "invalid apply rejected")
    let survivor = expectation(description: "valid queued apply completes")
    adapter.apply(
      options: .init(
        transaction: .disabled.updatePolicy(.serial),
        diagnostics: .init(mode: .warning, logsApplySummary: false)),
      completion: { result in
        XCTAssertTrue(result.diagnosticsIssues.contains { $0.kind == .duplicateSection })
        rejected.fulfill()
      }
    ) {
      section(1)
      section(1)
    }
    adapter.apply(
      transaction: .disabled.updatePolicy(.serial), completion: { _ in survivor.fulfill() }
    ) { section(2) }
    try XCTUnwrap(collection.releaseHeld)(true)
    await fulfillment(of: [rejected, survivor], timeout: 1)
    XCTAssertEqual(adapter.sectionIdentifier(at: 0), 2)
  }
  func testCollectionQueuedSupersededSummaryReportsNoExecutedRefresh() async throws {
    let collection = CancellationHeldCollection(
      frame: CGRect(x: 0, y: 0, width: 320, height: 400),
      collectionViewLayout: UICollectionViewFlowLayout())
    let adapter = CollectionListAdapter<Int>(collectionView: collection)
    let held = expectation(description: "held active mutation")
    collection.onHeld = { held.fulfill() }
    func section(_ id: Int, version: Int = 0) -> ListSection<Int> {
      ListSection(id) {
        Row(0, model: version, cell: UICollectionViewCell.self) { _, _, _ in }.refreshID(version)
          .refresh(when: .refreshIDChanges, scope: .allMatching)
      }
    }

    adapter.apply(
      options: .init(
        transaction: .disabled.layoutAnimation(.enabled).updatePolicy(.serial),
        applicationMode: .reloadData), completion: { _ in }
    ) { section(0) }
    await fulfillment(of: [held], timeout: 3)
    let superseded = expectation(description: "pending request superseded before commit")
    adapter.apply(
      transaction: .disabled,
      completion: { result in
        XCTAssertEqual(result.animation.completionState, .superseded)
        XCTAssertEqual(result.refreshMetrics, ListRefreshMetrics())
        superseded.fulfill()
      }
    ) { section(0, version: 1) }
    let completed = expectation(description: "latest request commits")
    adapter.apply(
      transaction: .disabled,
      completion: { result in
        XCTAssertEqual(result.animation.completionState, .completed)
        completed.fulfill()
      }
    ) { section(0, version: 2) }
    await fulfillment(of: [superseded], timeout: 1)
    try XCTUnwrap(collection.releaseHeld)(true)
    await fulfillment(of: [completed], timeout: 3)
  }
  func testCollectionMergedSectionCancellationAndReentrantCompletion() async throws {
    let collection = CancellationHeldCollection(
      frame: CGRect(x: 0, y: 0, width: 320, height: 400),
      collectionViewLayout: UICollectionViewFlowLayout())
    let adapter = CollectionListAdapter<Int>(collectionView: collection)
    let held = expectation(description: "held active mutation")
    collection.onHeld = { held.fulfill() }
    func section(_ id: Int, version: Int = 0) -> ListSection<Int> {
      ListSection(id) {
        Row(0, model: version, cell: UICollectionViewCell.self) { _, _, _ in }.refreshID(version)
          .refresh(when: .refreshIDChanges, scope: .allMatching)
      }
    }

    var cancelled: Task<ListRefreshSummary, Never>?
    adapter.apply(
      options: .init(
        transaction: .disabled.layoutAnimation(.enabled).updatePolicy(.serial),
        applicationMode: .reloadData), completion: { _ in cancelled?.cancel() }
    ) {
      section(0)
      section(1)
      section(2)
    }
    await fulfillment(of: [held], timeout: 3)
    let entered = expectation(description: "async section subscriber enqueued")
    cancelled = Task { @MainActor in
      entered.fulfill()
      return await adapter.reloadSections([0, 1], transaction: .disabled)
    }
    await fulfillment(of: [entered], timeout: 3)
    var order: [Int] = []
    let done = expectation(description: "surviving and reentrant completions")
    done.expectedFulfillmentCount = 3
    done.assertForOverFulfill = true
    adapter.reloadSections(
      [1, 2], transaction: .disabled,
      completion: { result in
        XCTAssertEqual(result.refreshMetrics.reloadedSectionCount, 2)
        order.append(1)
        done.fulfill()
        adapter.apply(
          transaction: .disabled.updatePolicy(.serial),
          completion: { _ in
            order.append(4)
            done.fulfill()
          }
        ) { section(4) }
      })
    adapter.apply(
      transaction: .disabled.updatePolicy(.serial),
      completion: { _ in
        order.append(3)
        done.fulfill()
      }
    ) { section(3) }
    try XCTUnwrap(collection.releaseHeld)(true)
    let result = await cancelled!.value
    XCTAssertEqual(result.animation.completionState, .cancelledBeforeCommit)
    XCTAssertEqual(result.refreshMetrics, ListRefreshMetrics())
    await fulfillment(of: [done], timeout: 3)
    XCTAssertEqual(order, [1, 3, 4])
    XCTAssertEqual(adapter.sectionIdentifier(at: 0), 4)
  }
  func testTableRejectedQueuedApplyAdvancesSerialQueue() async throws {
    let table = CancellationHeldTable(
      frame: CGRect(x: 0, y: 0, width: 320, height: 400), style: .plain)
    let adapter = TableListAdapter<Int>(tableView: table)
    let held = expectation(description: "held active mutation")
    table.onHeld = { held.fulfill() }
    func section(_ id: Int, version: Int = 0) -> TableSection<Int> {
      TableSection(id) {
        TableRow(0, model: version, cell: UITableViewCell.self) { _, _, _ in }.refreshID(version)
          .refresh(when: .refreshIDChanges, scope: .allMatching)
      }
    }

    adapter.apply(
      options: .init(
        transaction: .disabled.layoutAnimation(.enabled).updatePolicy(.serial),
        applicationMode: .reloadData), completion: { _ in }
    ) { section(0) }
    await fulfillment(of: [held], timeout: 3)
    let rejected = expectation(description: "invalid apply rejected")
    let survivor = expectation(description: "valid queued apply completes")
    adapter.apply(
      options: .init(
        transaction: .disabled.updatePolicy(.serial),
        diagnostics: .init(mode: .warning, logsApplySummary: false)),
      completion: { result in
        XCTAssertTrue(result.diagnosticsIssues.contains { $0.kind == .duplicateSection })
        rejected.fulfill()
      }
    ) {
      section(1)
      section(1)
    }
    adapter.apply(
      transaction: .disabled.updatePolicy(.serial), completion: { _ in survivor.fulfill() }
    ) { section(2) }
    try XCTUnwrap(table.releaseHeld)(true)
    await fulfillment(of: [rejected, survivor], timeout: 1)
    XCTAssertEqual(adapter.sectionIdentifier(at: 0), 2)
  }
  func testTableQueuedSupersededSummaryReportsNoExecutedRefresh() async throws {
    let table = CancellationHeldTable(
      frame: CGRect(x: 0, y: 0, width: 320, height: 400), style: .plain)
    let adapter = TableListAdapter<Int>(tableView: table)
    let held = expectation(description: "held active mutation")
    table.onHeld = { held.fulfill() }
    func section(_ id: Int, version: Int = 0) -> TableSection<Int> {
      TableSection(id) {
        TableRow(0, model: version, cell: UITableViewCell.self) { _, _, _ in }.refreshID(version)
          .refresh(when: .refreshIDChanges, scope: .allMatching)
      }
    }

    adapter.apply(
      options: .init(
        transaction: .disabled.layoutAnimation(.enabled).updatePolicy(.serial),
        applicationMode: .reloadData), completion: { _ in }
    ) { section(0) }
    await fulfillment(of: [held], timeout: 3)
    let superseded = expectation(description: "pending request superseded before commit")
    adapter.apply(
      transaction: .disabled,
      completion: { result in
        XCTAssertEqual(result.animation.completionState, .superseded)
        XCTAssertEqual(result.refreshMetrics, ListRefreshMetrics())
        superseded.fulfill()
      }
    ) { section(0, version: 1) }
    let completed = expectation(description: "latest request commits")
    adapter.apply(
      transaction: .disabled,
      completion: { result in
        XCTAssertEqual(result.animation.completionState, .completed)
        completed.fulfill()
      }
    ) { section(0, version: 2) }
    await fulfillment(of: [superseded], timeout: 1)
    try XCTUnwrap(table.releaseHeld)(true)
    await fulfillment(of: [completed], timeout: 3)
  }
  func testTableMergedSectionCancellationAndReentrantCompletion() async throws {
    let table = CancellationHeldTable(
      frame: CGRect(x: 0, y: 0, width: 320, height: 400), style: .plain)
    let adapter = TableListAdapter<Int>(tableView: table)
    let held = expectation(description: "held active mutation")
    table.onHeld = { held.fulfill() }
    func section(_ id: Int, version: Int = 0) -> TableSection<Int> {
      TableSection(id) {
        TableRow(0, model: version, cell: UITableViewCell.self) { _, _, _ in }.refreshID(version)
          .refresh(when: .refreshIDChanges, scope: .allMatching)
      }
    }

    var cancelled: Task<ListRefreshSummary, Never>?
    adapter.apply(
      options: .init(
        transaction: .disabled.layoutAnimation(.enabled).updatePolicy(.serial),
        applicationMode: .reloadData), completion: { _ in cancelled?.cancel() }
    ) {
      section(0)
      section(1)
      section(2)
    }
    await fulfillment(of: [held], timeout: 3)
    let entered = expectation(description: "async section subscriber enqueued")
    cancelled = Task { @MainActor in
      entered.fulfill()
      return await adapter.reloadSections([0, 1], transaction: .disabled)
    }
    await fulfillment(of: [entered], timeout: 3)
    var order: [Int] = []
    let done = expectation(description: "surviving and reentrant completions")
    done.expectedFulfillmentCount = 3
    done.assertForOverFulfill = true
    adapter.reloadSections(
      [1, 2], transaction: .disabled,
      completion: { result in
        XCTAssertEqual(result.refreshMetrics.reloadedSectionCount, 2)
        order.append(1)
        done.fulfill()
        adapter.apply(
          transaction: .disabled.updatePolicy(.serial),
          completion: { _ in
            order.append(4)
            done.fulfill()
          }
        ) { section(4) }
      })
    adapter.apply(
      transaction: .disabled.updatePolicy(.serial),
      completion: { _ in
        order.append(3)
        done.fulfill()
      }
    ) { section(3) }
    try XCTUnwrap(table.releaseHeld)(true)
    let result = await cancelled!.value
    XCTAssertEqual(result.animation.completionState, .cancelledBeforeCommit)
    XCTAssertEqual(result.refreshMetrics, ListRefreshMetrics())
    await fulfillment(of: [done], timeout: 3)
    XCTAssertEqual(order, [1, 3, 4])
    XCTAssertEqual(adapter.sectionIdentifier(at: 0), 4)
  }
  func testBeginCommitRacesCancellationAcrossThreads() async {
    for _ in 0..<250 {
      let bridge = ListAsyncMutationBridge(cancelledResult: 0)
      var winningCommit: Task<Bool, Never>!
      let result = await withCheckedContinuation { continuation in
        XCTAssertTrue(bridge.register(continuation, cancellation: { bridge.resume(returning: 0) }))
        winningCommit = Task.detached {
          let committed = bridge.beginCommit()
          if committed { bridge.resume(returning: 1) }
          return committed
        }
        Task.detached { bridge.cancel() }
      }
      let committed = await winningCommit.value
      XCTAssertEqual(result, committed ? 1 : 0)
      bridge.resume(returning: 99)
    }
  }
}

extension RefreshQueueBoundaryRegressionTests {
  func testCollectionAllMergedRowSubscribersCancelAndQueueContinues() async throws {
    let collection = CancellationHeldCollection(
      frame: CGRect(x: 0, y: 0, width: 320, height: 400),
      collectionViewLayout: UICollectionViewFlowLayout())
    let adapter = CollectionListAdapter<Int>(collectionView: collection)
    let held = expectation(description: "held")
    collection.onHeld = { held.fulfill() }
    func section(_ id: Int) -> ListSection<Int> {
      ListSection(id) {
        Row(0, model: 0, cell: UICollectionViewCell.self) { _, _, _ in }
        Row(1, model: 0, cell: UICollectionViewCell.self) { _, _, _ in }
      }
    }
    var tasks: [Task<ListRefreshSummary, Never>] = []
    adapter.apply(
      options: .init(
        transaction: .disabled.layoutAnimation(.enabled).updatePolicy(.serial),
        applicationMode: .reloadData), completion: { _ in tasks.forEach { $0.cancel() } }
    ) {
      section(0)
      section(1)
    }
    await fulfillment(of: [held], timeout: 3)
    let entered = expectation(description: "two async subscribers queued")
    entered.expectedFulfillmentCount = 2
    for id in 0..<2 {
      tasks.append(
        Task { @MainActor in
          entered.fulfill()
          return await adapter.reloadRows(forRowID: id, transaction: .disabled)
        })
    }
    await fulfillment(of: [entered], timeout: 3)
    let done = expectation(description: "survivor completes once")
    done.assertForOverFulfill = true
    adapter.apply(
      transaction: .disabled.updatePolicy(.serial),
      completion: { result in
        XCTAssertEqual(result.animation.completionState, .completed)
        done.fulfill()
      }
    ) { section(3) }
    try XCTUnwrap(collection.releaseHeld)(true)
    for task in tasks {
      let result = await task.value
      XCTAssertEqual(result.animation.completionState, .cancelledBeforeCommit)
      XCTAssertEqual(result.refreshMetrics, ListRefreshMetrics())
    }
    await fulfillment(of: [done], timeout: 3)
    XCTAssertEqual(adapter.sectionIdentifier(at: 0), 3)
  }
  func testCollectionAllMergedSectionSubscribersCancelAndQueueContinues() async throws {
    let collection = CancellationHeldCollection(
      frame: CGRect(x: 0, y: 0, width: 320, height: 400),
      collectionViewLayout: UICollectionViewFlowLayout())
    let adapter = CollectionListAdapter<Int>(collectionView: collection)
    let held = expectation(description: "held")
    collection.onHeld = { held.fulfill() }
    func section(_ id: Int) -> ListSection<Int> {
      ListSection(id) {
        Row(0, model: 0, cell: UICollectionViewCell.self) { _, _, _ in }
        Row(1, model: 0, cell: UICollectionViewCell.self) { _, _, _ in }
      }
    }
    var tasks: [Task<ListRefreshSummary, Never>] = []
    adapter.apply(
      options: .init(
        transaction: .disabled.layoutAnimation(.enabled).updatePolicy(.serial),
        applicationMode: .reloadData), completion: { _ in tasks.forEach { $0.cancel() } }
    ) {
      section(0)
      section(1)
    }
    await fulfillment(of: [held], timeout: 3)
    let entered = expectation(description: "two async subscribers queued")
    entered.expectedFulfillmentCount = 2
    for id in 0..<2 {
      tasks.append(
        Task { @MainActor in
          entered.fulfill()
          return await adapter.reloadSections([id], transaction: .disabled)
        })
    }
    await fulfillment(of: [entered], timeout: 3)
    let done = expectation(description: "survivor completes once")
    done.assertForOverFulfill = true
    adapter.apply(
      transaction: .disabled.updatePolicy(.serial),
      completion: { result in
        XCTAssertEqual(result.animation.completionState, .completed)
        done.fulfill()
      }
    ) { section(3) }
    try XCTUnwrap(collection.releaseHeld)(true)
    for task in tasks {
      let result = await task.value
      XCTAssertEqual(result.animation.completionState, .cancelledBeforeCommit)
      XCTAssertEqual(result.refreshMetrics, ListRefreshMetrics())
    }
    await fulfillment(of: [done], timeout: 3)
    XCTAssertEqual(adapter.sectionIdentifier(at: 0), 3)
  }
  func testTableAllMergedRowSubscribersCancelAndQueueContinues() async throws {
    let table = CancellationHeldTable(
      frame: CGRect(x: 0, y: 0, width: 320, height: 400), style: .plain)
    let adapter = TableListAdapter<Int>(tableView: table)
    let held = expectation(description: "held")
    table.onHeld = { held.fulfill() }
    func section(_ id: Int) -> TableSection<Int> {
      TableSection(id) {
        TableRow(0, model: 0, cell: UITableViewCell.self) { _, _, _ in }
        TableRow(1, model: 0, cell: UITableViewCell.self) { _, _, _ in }
      }
    }
    var tasks: [Task<ListRefreshSummary, Never>] = []
    adapter.apply(
      options: .init(
        transaction: .disabled.layoutAnimation(.enabled).updatePolicy(.serial),
        applicationMode: .reloadData), completion: { _ in tasks.forEach { $0.cancel() } }
    ) {
      section(0)
      section(1)
    }
    await fulfillment(of: [held], timeout: 3)
    let entered = expectation(description: "two async subscribers queued")
    entered.expectedFulfillmentCount = 2
    for id in 0..<2 {
      tasks.append(
        Task { @MainActor in
          entered.fulfill()
          return await adapter.reloadRows(forRowID: id, transaction: .disabled)
        })
    }
    await fulfillment(of: [entered], timeout: 3)
    let done = expectation(description: "survivor completes once")
    done.assertForOverFulfill = true
    adapter.apply(
      transaction: .disabled.updatePolicy(.serial),
      completion: { result in
        XCTAssertEqual(result.animation.completionState, .completed)
        done.fulfill()
      }
    ) { section(3) }
    try XCTUnwrap(table.releaseHeld)(true)
    for task in tasks {
      let result = await task.value
      XCTAssertEqual(result.animation.completionState, .cancelledBeforeCommit)
      XCTAssertEqual(result.refreshMetrics, ListRefreshMetrics())
    }
    await fulfillment(of: [done], timeout: 3)
    XCTAssertEqual(adapter.sectionIdentifier(at: 0), 3)
  }
  func testTableAllMergedSectionSubscribersCancelAndQueueContinues() async throws {
    let table = CancellationHeldTable(
      frame: CGRect(x: 0, y: 0, width: 320, height: 400), style: .plain)
    let adapter = TableListAdapter<Int>(tableView: table)
    let held = expectation(description: "held")
    table.onHeld = { held.fulfill() }
    func section(_ id: Int) -> TableSection<Int> {
      TableSection(id) {
        TableRow(0, model: 0, cell: UITableViewCell.self) { _, _, _ in }
        TableRow(1, model: 0, cell: UITableViewCell.self) { _, _, _ in }
      }
    }
    var tasks: [Task<ListRefreshSummary, Never>] = []
    adapter.apply(
      options: .init(
        transaction: .disabled.layoutAnimation(.enabled).updatePolicy(.serial),
        applicationMode: .reloadData), completion: { _ in tasks.forEach { $0.cancel() } }
    ) {
      section(0)
      section(1)
    }
    await fulfillment(of: [held], timeout: 3)
    let entered = expectation(description: "two async subscribers queued")
    entered.expectedFulfillmentCount = 2
    for id in 0..<2 {
      tasks.append(
        Task { @MainActor in
          entered.fulfill()
          return await adapter.reloadSections([id], transaction: .disabled)
        })
    }
    await fulfillment(of: [entered], timeout: 3)
    let done = expectation(description: "survivor completes once")
    done.assertForOverFulfill = true
    adapter.apply(
      transaction: .disabled.updatePolicy(.serial),
      completion: { result in
        XCTAssertEqual(result.animation.completionState, .completed)
        done.fulfill()
      }
    ) { section(3) }
    try XCTUnwrap(table.releaseHeld)(true)
    for task in tasks {
      let result = await task.value
      XCTAssertEqual(result.animation.completionState, .cancelledBeforeCommit)
      XCTAssertEqual(result.refreshMetrics, ListRefreshMetrics())
    }
    await fulfillment(of: [done], timeout: 3)
    XCTAssertEqual(adapter.sectionIdentifier(at: 0), 3)
  }
}

extension RefreshQueueBoundaryRegressionTests {
  func testCollectionRejectedApplyCompletionReentryPreservesQueueOrder() async throws {
    let collection = CancellationHeldCollection(
      frame: CGRect(x: 0, y: 0, width: 320, height: 400),
      collectionViewLayout: UICollectionViewFlowLayout())
    let adapter = CollectionListAdapter<Int>(collectionView: collection)
    let held = expectation(description: "held active mutation")
    collection.onHeld = { held.fulfill() }
    func section(_ id: Int) -> ListSection<Int> {
      ListSection(id) {
        Row(0, model: 0, cell: UICollectionViewCell.self) { _, _, _ in }.refresh(
          when: .everyApply, scope: .allMatching, action: .reload)
      }
    }
    adapter.apply(
      options: .init(
        transaction: .disabled.layoutAnimation(.enabled).updatePolicy(.serial),
        applicationMode: .reloadData), completion: { _ in }
    ) { section(0) }
    await fulfillment(of: [held], timeout: 3)

    var order: [Int] = []
    let done = expectation(description: "rejection, queued and reentrant callbacks")
    done.expectedFulfillmentCount = 3
    done.assertForOverFulfill = true
    adapter.apply(
      options: .init(
        transaction: .disabled.updatePolicy(.serial),
        diagnostics: .init(mode: .warning, logsApplySummary: false)),
      completion: { result in
        XCTAssertTrue(result.diagnosticsIssues.contains { $0.kind == .duplicateSection })
        order.append(1)
        done.fulfill()
        adapter.apply(
          transaction: .disabled.updatePolicy(.serial),
          completion: { _ in
            order.append(3)
            done.fulfill()
          }
        ) { section(3) }
      }
    ) {
      section(1)
      section(1)
    }
    adapter.apply(
      transaction: .disabled.updatePolicy(.serial),
      completion: { _ in
        order.append(2)
        done.fulfill()
      }
    ) { section(2) }
    try XCTUnwrap(collection.releaseHeld)(true)
    await fulfillment(of: [done], timeout: 3)
    XCTAssertEqual(order, [1, 2, 3])
    XCTAssertEqual(adapter.sectionIdentifier(at: 0), 3)
  }
  func testCollectionSupersededQueuedReloadAllReportsNoWork() async throws {
    let collection = CancellationHeldCollection(
      frame: CGRect(x: 0, y: 0, width: 320, height: 400),
      collectionViewLayout: UICollectionViewFlowLayout())
    let adapter = CollectionListAdapter<Int>(collectionView: collection)
    let held = expectation(description: "held active mutation")
    collection.onHeld = { held.fulfill() }
    func section(_ id: Int) -> ListSection<Int> {
      ListSection(id) {
        Row(0, model: 0, cell: UICollectionViewCell.self) { _, _, _ in }.refresh(
          when: .everyApply, scope: .allMatching, action: .reload)
      }
    }
    adapter.apply(
      options: .init(
        transaction: .disabled.layoutAnimation(.enabled).updatePolicy(.serial),
        applicationMode: .reloadData), completion: { _ in }
    ) { section(0) }
    await fulfillment(of: [held], timeout: 3)

    let skipped = expectation(description: "pending reloadAll superseded")
    adapter.reloadAll(
      transaction: .disabled,
      completion: { result in
        XCTAssertEqual(result.animation.completionState, .superseded)
        XCTAssertEqual(result.refreshMetrics, .zero)
        XCTAssertFalse(result.animation.layoutInvalidated)
        skipped.fulfill()
      })
    let done = expectation(description: "latest reloadAll completes")
    adapter.reloadAll(
      transaction: .disabled,
      completion: { result in
        XCTAssertEqual(result.animation.completionState, .completed)
        done.fulfill()
      })
    await fulfillment(of: [skipped], timeout: 3)
    try XCTUnwrap(collection.releaseHeld)(true)
    await fulfillment(of: [done], timeout: 3)
  }
  func testTableRejectedApplyCompletionReentryPreservesQueueOrder() async throws {
    let table = CancellationHeldTable(
      frame: CGRect(x: 0, y: 0, width: 320, height: 400), style: .plain)
    let adapter = TableListAdapter<Int>(tableView: table)
    let held = expectation(description: "held active mutation")
    table.onHeld = { held.fulfill() }
    func section(_ id: Int) -> TableSection<Int> {
      TableSection(id) {
        TableRow(0, model: 0, cell: UITableViewCell.self) { _, _, _ in }.refresh(
          when: .everyApply, scope: .allMatching, action: .reload)
      }
    }
    adapter.apply(
      options: .init(
        transaction: .disabled.layoutAnimation(.enabled).updatePolicy(.serial),
        applicationMode: .reloadData), completion: { _ in }
    ) { section(0) }
    await fulfillment(of: [held], timeout: 3)

    var order: [Int] = []
    let done = expectation(description: "rejection, queued and reentrant callbacks")
    done.expectedFulfillmentCount = 3
    done.assertForOverFulfill = true
    adapter.apply(
      options: .init(
        transaction: .disabled.updatePolicy(.serial),
        diagnostics: .init(mode: .warning, logsApplySummary: false)),
      completion: { result in
        XCTAssertTrue(result.diagnosticsIssues.contains { $0.kind == .duplicateSection })
        order.append(1)
        done.fulfill()
        adapter.apply(
          transaction: .disabled.updatePolicy(.serial),
          completion: { _ in
            order.append(3)
            done.fulfill()
          }
        ) { section(3) }
      }
    ) {
      section(1)
      section(1)
    }
    adapter.apply(
      transaction: .disabled.updatePolicy(.serial),
      completion: { _ in
        order.append(2)
        done.fulfill()
      }
    ) { section(2) }
    try XCTUnwrap(table.releaseHeld)(true)
    await fulfillment(of: [done], timeout: 3)
    XCTAssertEqual(order, [1, 2, 3])
    XCTAssertEqual(adapter.sectionIdentifier(at: 0), 3)
  }
  func testTableSupersededQueuedReloadAllReportsNoWork() async throws {
    let table = CancellationHeldTable(
      frame: CGRect(x: 0, y: 0, width: 320, height: 400), style: .plain)
    let adapter = TableListAdapter<Int>(tableView: table)
    let held = expectation(description: "held active mutation")
    table.onHeld = { held.fulfill() }
    func section(_ id: Int) -> TableSection<Int> {
      TableSection(id) {
        TableRow(0, model: 0, cell: UITableViewCell.self) { _, _, _ in }.refresh(
          when: .everyApply, scope: .allMatching, action: .reload)
      }
    }
    adapter.apply(
      options: .init(
        transaction: .disabled.layoutAnimation(.enabled).updatePolicy(.serial),
        applicationMode: .reloadData), completion: { _ in }
    ) { section(0) }
    await fulfillment(of: [held], timeout: 3)

    let skipped = expectation(description: "pending reloadAll superseded")
    adapter.reloadAll(
      transaction: .disabled,
      completion: { result in
        XCTAssertEqual(result.animation.completionState, .superseded)
        XCTAssertEqual(result.refreshMetrics, .zero)
        XCTAssertFalse(result.animation.layoutInvalidated)
        skipped.fulfill()
      })
    let done = expectation(description: "latest reloadAll completes")
    adapter.reloadAll(
      transaction: .disabled,
      completion: { result in
        XCTAssertEqual(result.animation.completionState, .completed)
        done.fulfill()
      })
    await fulfillment(of: [skipped], timeout: 3)
    try XCTUnwrap(table.releaseHeld)(true)
    await fulfillment(of: [done], timeout: 3)
  }
}
