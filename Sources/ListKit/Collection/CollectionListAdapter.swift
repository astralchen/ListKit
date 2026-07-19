import UIKit

// MARK: - Adapter

/// UICollectionView 列表适配器。
///
/// - Usage:
/// ```swift
/// private lazy var adapter = CollectionListAdapter<Section>(collectionView: collectionView)
///
/// adapter.apply(transaction: .disabled) {
///     ListSection(.users) {
///         ForEach(users, id: \.userID) { user in
///             Row(model: user, cell: UserCell.self) { cell, user, context in
///                 cell.configure(user)
///             }
///         }
///     }
/// }
/// ```
@MainActor
public final class CollectionListAdapter<SectionID>: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UICollectionViewDataSourcePrefetching
where SectionID: Hashable & Sendable {
    /// 滚动回调转发对象。
    ///
    /// `CollectionListAdapter` 会接管 `collectionView.delegate`，页面需要
    /// `scrollViewDidScroll` 等回调时设置此属性。
    public weak var scrollDelegate: UIScrollViewDelegate?

    /// UIKit delegate 逃生口。ListKit 已处理的回调会先执行声明式 Row 行为，再转发到此对象；
    /// 其余可选 delegate 方法会通过 Objective-C forwarding 自动转发。
    public weak var collectionDelegate: UICollectionViewDelegate?

    /// 原生 drag/drop 逃生口；设置后直接安装到 collection view。
    public weak var dragDelegate: UICollectionViewDragDelegate? {
        didSet { collectionView?.dragDelegate = dragDelegate }
    }
    public weak var dropDelegate: UICollectionViewDropDelegate? {
        didSet { collectionView?.dropDelegate = dropDelegate }
    }

    /// flow layout 回调转发对象。
    ///
    /// 仅用于仍在使用 `UICollectionViewDelegateFlowLayout` 的页面；使用
    /// `makeCompositionalLayout()` 的页面通常不需要它。
    public weak var layoutDelegate: UICollectionViewDelegateFlowLayout?

    /// cell/supplementary 展示回调转发对象。
    public weak var displayDelegate: UICollectionViewDelegate?

    /// 最近一次 `apply` 的摘要。
    ///
    /// DEBUG 下 ListKit 也会输出同一份 summary，便于定位 diff、refreshID 和可见刷新问题。
    public private(set) var lastApplySummary = ListApplySummary()
    /// 最近一次 compositional layout provider/helper 产生的 diagnostics。
    public private(set) var lastLayoutDiagnostics: [ListDiagnosticsIssue] = []
    private(set) var layoutInvalidationGeneration = 0
    private(set) var outlineAnimationGeneration = 0

    private weak var collectionView: UICollectionView?
    private var sections: [ListSection<SectionID>] = []
    private var layoutSignature: [ListSectionLayoutSignature] = []
    private var dataSource: CollectionDiffableDataSource<SectionID>!
    var isApplyingSnapshot = false
    private var rowsByIdentity: [AnyListIdentity: AnyListRow] = [:]
    private var supplementariesByKindAndSection: [SupplementaryKey: AnySupplementary] = [:]
    private var displayedRowsByCell: [ObjectIdentifier: AnyListRow] = [:]
    private var displayedSupplementariesByView: [ObjectIdentifier: AnySupplementary] = [:]
    private var prefetchedRowsByIndexPath: [IndexPath: AnyListRow] = [:]
    private var applyGeneration = 0
    private var prefetchItemsHandler: (@MainActor ([ListContext]) -> Void)?
    private var cancelPrefetchingItemsHandler: (@MainActor ([ListContext]) -> Void)?
    private var contextMenuItemsProvider: (@MainActor ([ListContext], CGPoint) -> UIContextMenuConfiguration?)?
    private var activeContextMenu: (row: AnyListRow, indexPath: IndexPath)?
    private var indexTitleEntries: [CollectionIndexTitleEntry] = []
    private var preservedAnchorBottomInsetCompensation: CGFloat = 0
    private var temporaryAnchorBaseBottomInset: CGFloat?
    private var isSerialApplyActive = false
    private var serialApplyWaiters: [CheckedContinuation<Void, Never>] = []
    private let eventRouter = ListEventRouter<ListContext>()

    /// 创建 adapter 并接管 collection view 的 data source、delegate 和 prefetch data source。
    ///
    /// - Parameter collectionView: 由 adapter 管理 diffable data source、delegate 和预取回调的 collection view。
    public init(collectionView: UICollectionView) {
        self.collectionView = collectionView
        super.init()

        dataSource = CollectionDiffableDataSource<SectionID>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, identity in
            guard let self, let row = self.rowsByIdentity[identity] else {
                return UICollectionViewCell()
            }
            return row.cellProvider(collectionView, indexPath, self.context(for: indexPath, identity: identity))
        }
        dataSource.adapter = self

        dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            guard let self else { return nil }
            let sectionID = self.sectionID(at: indexPath.section)
            let key = SupplementaryKey(kind: kind, sectionID: sectionID)
            guard let supplementary = self.supplementariesByKindAndSection[key] else { return nil }
            return supplementary.viewProvider(collectionView, indexPath, self.context(for: indexPath, identity: supplementary.identity))
        }

        dataSource.reorderingHandlers.canReorderItem = { [weak self] identity in
            self?.rowsByIdentity[identity]?.moveHandler != nil
        }
        dataSource.reorderingHandlers.didReorder = { [weak self] transaction in
            self?.didReorder(transaction)
        }
        dataSource.sectionSnapshotHandlers.willExpandItem = { [weak self] identity in
            self?.notifyExpansionChange(identity: identity, isExpanded: true)
        }
        dataSource.sectionSnapshotHandlers.willCollapseItem = { [weak self] identity in
            self?.notifyExpansionChange(identity: identity, isExpanded: false)
        }

        collectionView.dataSource = dataSource
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
    }

    public override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return MainActor.assumeIsolated {
            forwardingDelegates.contains { delegate in
                (delegate as? NSObjectProtocol)?.responds(to: aSelector) == true
            }
        }
    }

    public override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if super.responds(to: aSelector) { return super.forwardingTarget(for: aSelector) }
        let target = MainActor.assumeIsolated {
            ListUnsafeForwardingTarget(
                forwardingDelegates.first { delegate in
                    (delegate as? NSObjectProtocol)?.responds(to: aSelector) == true
                }
            )
        }
        return target.value
    }

    private var forwardingDelegates: [AnyObject] {
        [collectionDelegate, scrollDelegate, layoutDelegate, displayDelegate].compactMap { $0 as AnyObject? }
    }

    private var resolvedLayoutDelegate: UICollectionViewDelegateFlowLayout? {
        layoutDelegate ?? (collectionDelegate as? UICollectionViewDelegateFlowLayout)
    }

    /// 提交一次列表更新。需要等待所有动画和可见刷新完成时使用 async 重载。
    @discardableResult
    public func apply(
        options: ListApplyOptions,
        completion: ((ListApplySummary) -> Void)? = nil,
        @ListSectionBuilder<SectionID> _ content: () -> [ListSection<SectionID>]
    ) -> ListApplyResult<SectionID> {
        _apply(options: options, completion: completion, content)
    }

    /// 以 SwiftUI 风格的 transaction 提交更新。
    @discardableResult
    public func apply(
        transaction: ListTransaction = .automatic,
        completion: ((ListApplySummary) -> Void)? = nil,
        @ListSectionBuilder<SectionID> _ content: () -> [ListSection<SectionID>]
    ) -> ListApplyResult<SectionID> {
        apply(
            options: ListApplyOptions(transaction: transaction),
            completion: completion,
            content
        )
    }

    /// 提交已经构建好的 section 数组。
    @discardableResult
    public func apply(
        _ sections: [ListSection<SectionID>],
        options: ListApplyOptions,
        completion: ((ListApplySummary) -> Void)? = nil
    ) -> ListApplyResult<SectionID> {
        apply(options: options, completion: completion) { sections }
    }

    /// 以 transaction 提交已经构建好的 sections。
    @discardableResult
    public func apply(
        _ sections: [ListSection<SectionID>],
        transaction: ListTransaction = .automatic,
        completion: ((ListApplySummary) -> Void)? = nil
    ) -> ListApplyResult<SectionID> {
        apply(
            sections,
            options: ListApplyOptions(transaction: transaction),
            completion: completion
        )
    }

    private func _apply(
        options: ListApplyOptions,
        completion: ((ListApplySummary) -> Void)?,
        @ListSectionBuilder<SectionID> _ content: () -> [ListSection<SectionID>]
    ) -> ListApplyResult<SectionID> {
        let newSections = content()
        let resolvedTransaction = options.transaction.resolved(
            reduceMotionEnabled: UIAccessibility.isReduceMotionEnabled
        )
        let newLayoutSignature = Self.makeLayoutSignature(from: newSections)
        let shouldInvalidateLayout = layoutSignature != newLayoutSignature
        let diagnosticsIssues = ListDiagnostics.validate(newSections)
        let applyPlan = ListApplyPlanner.makePlan(
            old: Self.makeCoreSnapshots(from: sections),
            new: Self.makeCoreSnapshots(from: newSections),
            options: options,
            diagnosticsIssues: diagnosticsIssues
        )
        let previousDataSourceSnapshot = dataSource.snapshot()
        let outlineSectionsNeedingAnimation = Set(newSections.compactMap { section -> AnyListID? in
            guard section.hasOutlineHierarchy else { return nil }
            let sectionID = AnyListID(section.id)
            guard previousDataSourceSnapshot.sectionIdentifiers.contains(sectionID) else {
                return sectionID
            }
            let previousOutline = dataSource.snapshot(for: sectionID)
            let nextOutline = Self.makeOutlineSnapshot(from: section.outlineRoots)
            return Self.outlineSnapshotsAreEquivalent(previousOutline, nextOutline) ? nil : sectionID
        })

        if !applyPlan.shouldApplyDiffable {
            let summary = applyPlan.initialSummary.replacingAnimation(
                ListAnimationSummary(
                    completionState: .completed,
                    reduceMotionApplied: resolvedTransaction.reduceMotionApplied
                )
            )
            lastApplySummary = summary
            ListApplyLogger.logDiagnostics(issues: diagnosticsIssues, options: options)
            ListApplyLogger.logApplySummary(summary, options: options)
            completion?(summary)
            return ListApplyResult(adapter: self, summary: summary)
        }

        let visibleAnchor: ListVisibleRowAnchor?
        switch resolvedTransaction.scrollBehavior.storage {
        case .preserveVisiblePosition(let target):
            visibleAnchor = captureVisibleRowAnchor(for: target)
            if let visibleAnchor {
                reserveScrollRange(for: visibleAnchor)
            }
        case .none, .scrollTo, .scrollToLast:
            visibleAnchor = nil
            cancelTemporaryAnchorReservation()
        }

        applyGeneration += 1
        let generation = applyGeneration
        sections = newSections
        layoutSignature = newLayoutSignature
        rebuildLookupTables()
        registerBackgroundDecorationsIfNeeded()
        configureSelectionBehavior()

        var snapshot = NSDiffableDataSourceSnapshot<AnyListID, AnyListIdentity>()
        for section in newSections {
            let sectionID = AnyListID(section.id)
            snapshot.appendSections([sectionID])
            if section.hasOutlineHierarchy {
                guard previousDataSourceSnapshot.sectionIdentifiers.contains(sectionID) else { continue }
                let newIdentities = Set(section.rows.map(\.identity))
                let retainedIdentities = previousDataSourceSnapshot
                    .itemIdentifiers(inSection: sectionID)
                    .filter(newIdentities.contains)
                if !retainedIdentities.isEmpty {
                    snapshot.appendItems(retainedIdentities, toSection: sectionID)
                }
            } else {
                snapshot.appendItems(section.rows.map(\.identity), toSection: sectionID)
            }
        }

        let snapshotItems = Set(snapshot.itemIdentifiers)
        let refreshItems = applyPlan.snapshotRefreshItems.filter { snapshotItems.contains($0) }
        if !refreshItems.isEmpty {
            if #available(iOS 15.0, tvOS 15.0, *) {
                snapshot.reconfigureItems(refreshItems)
            } else {
                snapshot.reloadItems(refreshItems)
            }
        }

        let summary = applyPlan.initialSummary.replacingAnimation(
            ListAnimationSummary(reduceMotionApplied: resolvedTransaction.reduceMotionApplied)
        )
        lastApplySummary = summary
        ListApplyLogger.logDiagnostics(issues: diagnosticsIssues, options: options)

        isApplyingSnapshot = true
        let finishApply = { [weak self] in
            guard let self else { return }
            guard self.applyGeneration == generation else {
                let supersededSummary = summary.replacingAnimation(
                    ListAnimationSummary(
                        completionState: .superseded,
                        reduceMotionApplied: resolvedTransaction.reduceMotionApplied
                    )
                )
                ListApplyLogger.logApplySummary(supersededSummary, options: options)
                completion?(supersededSummary)
                return
            }
            self.isApplyingSnapshot = false
            self.reconcileSelection()
            self.performLayoutUpdate(
                invalidating: shouldInvalidateLayout,
                animated: resolvedTransaction.layoutAnimation
            ) { layoutAnimated in
                let metrics = CollectionApplyAnimationMetrics()
                metrics.layoutAnimated = layoutAnimated
                let animationCoordinator = ListAnimationCompletionCoordinator {
                    let snapshotAnimated = options.applicationMode == .differences
                        && resolvedTransaction.snapshotAnimation
                        && (applyPlan.initialSummary.insertedCount > 0
                            || applyPlan.initialSummary.deletedCount > 0
                            || applyPlan.initialSummary.movedCount > 0
                            || applyPlan.initialSummary.snapshotRefreshCount > 0)
                    let completedSummary = applyPlan.completedSummary(
                        visibleRefreshCount: metrics.visibleRefreshCount,
                        visibleSupplementaryRefreshCount: metrics.visibleSupplementaryRefreshCount,
                        animation: ListAnimationSummary(
                            completionState: .completed,
                            snapshotAnimated: snapshotAnimated,
                            animatedSectionCount: snapshotAnimated ? applyPlan.changedSectionCount : 0,
                            outlineAnimatedSectionCount: resolvedTransaction.outlineAnimation
                                ? outlineSectionsNeedingAnimation.count
                                : 0,
                            contentTransitionCount: metrics.contentTransitionCount,
                            layoutInvalidated: shouldInvalidateLayout,
                            layoutAnimated: metrics.layoutAnimated,
                            scrollAnimated: metrics.scrollOutcome.animated,
                            anchorCompensation: metrics.scrollOutcome.anchorCompensation,
                            reduceMotionApplied: resolvedTransaction.reduceMotionApplied
                        )
                    )
                    self.lastApplySummary = completedSummary
                    ListApplyLogger.logApplySummary(completedSummary, options: options)
                    completion?(completedSummary)
                }

                if applyPlan.shouldRunVisibleRefresh {
                    let refresh = self.refreshVisibleRowsIfNeeded(
                        applyPlan: applyPlan,
                        animatingContent: resolvedTransaction.contentAnimation,
                        coordinator: animationCoordinator
                    )
                    metrics.visibleRefreshCount = refresh.refreshedCount
                    metrics.contentTransitionCount = refresh.transitionCount
                    metrics.visibleSupplementaryRefreshCount = self.refreshVisibleSupplementariesIfNeeded(
                        applyPlan: applyPlan
                    )
                }
                metrics.scrollOutcome = self.performScrollBehavior(
                    resolvedTransaction.scrollBehavior,
                    visibleAnchor: visibleAnchor,
                    animated: resolvedTransaction.scrollAnimation
                )
                animationCoordinator.finishScheduling()
            }
        }
        let finishApplyBox = ListMainActorCallbackBox(finishApply)
        // UIKit can invoke this completion from its internal diffing queue before
        // the global snapshot apply has fully unwound. Defer the outline phase to
        // the next main-actor turn so section snapshots are never applied reentrantly.
        let didApplyBox = ListMainActorCallbackBox { [weak self] in
            guard let self else { return }
            guard self.applyGeneration == generation else {
                finishApplyBox.call()
                return
            }
            self.applyOutlineSnapshots(
                generation: generation,
                animatedSectionIDs: resolvedTransaction.outlineAnimation
                    ? outlineSectionsNeedingAnimation
                    : [],
                completion: { finishApplyBox.call() }
            )
        }
        let didApply = { didApplyBox.schedule() }

        switch options.applicationMode {
        case .differences:
            dataSource.apply(
                snapshot,
                animatingDifferences: resolvedTransaction.snapshotAnimation,
                completion: didApply
            )
        case .reloadData:
            if #available(iOS 15.0, tvOS 15.0, *) {
                dataSource.applySnapshotUsingReloadData(snapshot, completion: didApply)
            } else {
                dataSource.apply(snapshot, animatingDifferences: false, completion: didApply)
            }
        }

        return ListApplyResult(adapter: self, summary: summary)
    }

    /// 重建描述树并等待 snapshot、outline、layout 和内容过渡完成。
    @discardableResult
    public func applyAndWait(
        options: ListApplyOptions,
        @ListSectionBuilder<SectionID> _ content: () -> [ListSection<SectionID>]
    ) async -> ListApplyResult<SectionID> {
        let builtSections = content()
        let usesSerialScheduling = options.transaction.updatePolicy == .serial
        if usesSerialScheduling {
            await acquireSerialApplySlot()
        }
        if Task.isCancelled {
            if usesSerialScheduling { releaseSerialApplySlot() }
            let resolved = options.transaction.resolved(
                reduceMotionEnabled: UIAccessibility.isReduceMotionEnabled
            )
            return ListApplyResult(
                adapter: self,
                summary: ListApplySummary(
                    animation: ListAnimationSummary(
                        completionState: .cancelledBeforeCommit,
                        reduceMotionApplied: resolved.reduceMotionApplied
                    )
                )
            )
        }

        let result = await withCheckedContinuation { continuation in
            _ = _apply(options: options, completion: { [weak self] summary in
                continuation.resume(returning: ListApplyResult(adapter: self, summary: summary))
            }) {
                builtSections
            }
        }
        if usesSerialScheduling {
            releaseSerialApplySlot()
        }
        return result
    }

    /// 提交 transaction，并等待 snapshot、outline、layout 和内容过渡完成。
    @discardableResult
    public func applyAndWait(
        transaction: ListTransaction = .automatic,
        @ListSectionBuilder<SectionID> _ content: () -> [ListSection<SectionID>]
    ) async -> ListApplyResult<SectionID> {
        await applyAndWait(options: ListApplyOptions(transaction: transaction), content)
    }

    /// 绑定自定义业务事件。
    ///
    /// 事件可以从 row、header 或 footer 的 configure 闭包中通过 `context.send(...)`
    /// 发出，再由页面在 adapter 或 apply result 上集中处理。
    /// - Parameters:
    ///   - eventType: 要接收的事件类型。
    ///   - handler: 主线程回调的事件处理闭包。
    /// - Returns: 当前 adapter，便于链式配置。
    @discardableResult
    @MainActor public func onEvent<Event>(
        _ eventType: Event.Type = Event.self,
        handler: @escaping @MainActor (Event, ListContext) -> Void
    ) -> Self where Event: ListEvent {
        eventRouter.on(eventType, handler: handler)
        return self
    }

    /// 监听 UIKit 一次批量预取请求。
    @discardableResult
    public func onPrefetchItems(_ handler: @escaping @MainActor ([ListContext]) -> Void) -> Self {
        prefetchItemsHandler = handler
        return self
    }

    /// 监听 UIKit 一次批量取消预取请求。
    @discardableResult
    public func onCancelPrefetchingItems(_ handler: @escaping @MainActor ([ListContext]) -> Void) -> Self {
        cancelPrefetchingItemsHandler = handler
        return self
    }

    /// 为 iOS 16+ 多选 item 提供一个批量 context menu。
    @discardableResult
    public func contextMenuForItems(
        _ provider: @escaping @MainActor ([ListContext], CGPoint) -> UIContextMenuConfiguration?
    ) -> Self {
        contextMenuItemsProvider = provider
        return self
    }

    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        sections.count
    }

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[safe: section]?.rows.count ?? 0
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let row = row(at: indexPath) else { return UICollectionViewCell() }
        return row.cellProvider(collectionView, indexPath, context(for: indexPath, identity: row.identity))
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let row = row(at: indexPath) else { return }
        if toggleOutlineDisclosureIfNeeded(for: row, at: indexPath) {
            collectionView.deselectItem(at: indexPath, animated: false)
            let context = context(for: indexPath, identity: row.identity)
            row.selectHandler?(context)
            collectionDelegate?.collectionView?(collectionView, didSelectItemAt: indexPath)
            return
        }
        if selectionMode(at: indexPath) == .single {
            deselectOtherItems(in: indexPath.section, keeping: indexPath, collectionView: collectionView)
        }
        let context = context(for: indexPath, identity: row.identity)
        row.selectHandler?(context)
        row.selectionChangeHandler?(true, context)
        collectionDelegate?.collectionView?(collectionView, didSelectItemAt: indexPath)
    }

    public func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        guard let row = row(at: indexPath) else { return }
        let context = context(for: indexPath, identity: row.identity)
        row.deselectHandler?(context)
        row.selectionChangeHandler?(false, context)
        collectionDelegate?.collectionView?(collectionView, didDeselectItemAt: indexPath)
    }

    public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard selectionMode(at: indexPath) != .none, row(at: indexPath)?.isSelectionDisabled != true else {
            return false
        }
        return collectionDelegate?.collectionView?(collectionView, shouldSelectItemAt: indexPath) ?? true
    }

    public func collectionView(_ collectionView: UICollectionView, shouldDeselectItemAt indexPath: IndexPath) -> Bool {
        guard selectionMode(at: indexPath) != .none, row(at: indexPath)?.isSelectionDisabled != true else {
            return false
        }
        return collectionDelegate?.collectionView?(collectionView, shouldDeselectItemAt: indexPath) ?? true
    }

    public func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        guard row(at: indexPath)?.isSelectionDisabled != true else { return false }
        return collectionDelegate?.collectionView?(collectionView, shouldHighlightItemAt: indexPath) ?? true
    }

    public func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
        if let row = row(at: indexPath) {
            row.highlightChangeHandler?(true, context(for: indexPath, identity: row.identity))
        }
        collectionDelegate?.collectionView?(collectionView, didHighlightItemAt: indexPath)
    }

    public func collectionView(_ collectionView: UICollectionView, didUnhighlightItemAt indexPath: IndexPath) {
        if let row = row(at: indexPath) {
            row.highlightChangeHandler?(false, context(for: indexPath, identity: row.identity))
        }
        collectionDelegate?.collectionView?(collectionView, didUnhighlightItemAt: indexPath)
    }

    @available(iOS 16.0, tvOS 16.0, *)
    public func collectionView(_ collectionView: UICollectionView, performPrimaryActionForItemAt indexPath: IndexPath) {
        if let row = row(at: indexPath) {
            row.primaryActionHandler?(context(for: indexPath, identity: row.identity))
        }
        collectionDelegate?.collectionView?(collectionView, performPrimaryActionForItemAt: indexPath)
    }

    public func collectionView(_ collectionView: UICollectionView, canFocusItemAt indexPath: IndexPath) -> Bool {
        row(at: indexPath)?.isFocusable
            ?? collectionDelegate?.collectionView?(collectionView, canFocusItemAt: indexPath)
            ?? true
    }

    @available(iOS 15.0, tvOS 15.0, *)
    public func collectionView(_ collectionView: UICollectionView, selectionFollowsFocusForItemAt indexPath: IndexPath) -> Bool {
        row(at: indexPath)?.selectionFollowsFocus
            ?? collectionDelegate?.collectionView?(collectionView, selectionFollowsFocusForItemAt: indexPath)
            ?? collectionView.selectionFollowsFocus
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        shouldSpringLoadItemAt indexPath: IndexPath,
        with context: any UISpringLoadedInteractionContext
    ) -> Bool {
        row(at: indexPath)?.isSpringLoadingEnabled
            ?? collectionDelegate?.collectionView?(collectionView, shouldSpringLoadItemAt: indexPath, with: context)
            ?? true
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath
    ) -> Bool {
        guard sections[safe: indexPath.section]?.allowsMultipleSelectionInteraction == true else { return false }
        return collectionDelegate?.collectionView?(
            collectionView,
            shouldBeginMultipleSelectionInteractionAt: indexPath
        ) ?? true
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        didBeginMultipleSelectionInteractionAt indexPath: IndexPath
    ) {
        collectionDelegate?.collectionView?(collectionView, didBeginMultipleSelectionInteractionAt: indexPath)
    }

    public func collectionViewDidEndMultipleSelectionInteraction(_ collectionView: UICollectionView) {
        collectionDelegate?.collectionViewDidEndMultipleSelectionInteraction?(collectionView)
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        if let row = row(at: indexPath) {
            displayedRowsByCell[ObjectIdentifier(cell)] = row
            row.displayHandler?(cell, context(for: indexPath, identity: row.identity))
        }
        displayDelegate?.collectionView?(collectionView, willDisplay: cell, forItemAt: indexPath)
        if !sameObject(displayDelegate, collectionDelegate) {
            collectionDelegate?.collectionView?(collectionView, willDisplay: cell, forItemAt: indexPath)
        }
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        didEndDisplaying cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        let row = displayedRowsByCell.removeValue(forKey: ObjectIdentifier(cell)) ?? row(at: indexPath)
        if let row {
            row.endDisplayHandler?(cell, context(for: indexPath, identity: row.identity))
        }
        displayDelegate?.collectionView?(collectionView, didEndDisplaying: cell, forItemAt: indexPath)
        if !sameObject(displayDelegate, collectionDelegate) {
            collectionDelegate?.collectionView?(collectionView, didEndDisplaying: cell, forItemAt: indexPath)
        }
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        willDisplaySupplementaryView view: UICollectionReusableView,
        forElementKind elementKind: String,
        at indexPath: IndexPath
    ) {
        if let supplementary = supplementary(kind: elementKind, at: indexPath) {
            displayedSupplementariesByView[ObjectIdentifier(view)] = supplementary
            supplementary.displayHandler?(view, context(for: indexPath, identity: supplementary.identity))
        }
        displayDelegate?.collectionView?(
            collectionView,
            willDisplaySupplementaryView: view,
            forElementKind: elementKind,
            at: indexPath
        )
        if !sameObject(displayDelegate, collectionDelegate) {
            collectionDelegate?.collectionView?(
                collectionView,
                willDisplaySupplementaryView: view,
                forElementKind: elementKind,
                at: indexPath
            )
        }
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        didEndDisplayingSupplementaryView view: UICollectionReusableView,
        forElementOfKind elementKind: String,
        at indexPath: IndexPath
    ) {
        let supplementary = displayedSupplementariesByView.removeValue(forKey: ObjectIdentifier(view))
            ?? supplementary(kind: elementKind, at: indexPath)
        if let supplementary {
            supplementary.endDisplayHandler?(view, context(for: indexPath, identity: supplementary.identity))
        }
        displayDelegate?.collectionView?(
            collectionView,
            didEndDisplayingSupplementaryView: view,
            forElementOfKind: elementKind,
            at: indexPath
        )
        if !sameObject(displayDelegate, collectionDelegate) {
            collectionDelegate?.collectionView?(
                collectionView,
                didEndDisplayingSupplementaryView: view,
                forElementOfKind: elementKind,
                at: indexPath
            )
        }
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        prefetchItemsAt indexPaths: [IndexPath]
    ) {
        var contexts: [ListContext] = []
        for indexPath in indexPaths {
            guard let row = row(at: indexPath) else { continue }
            prefetchedRowsByIndexPath[indexPath] = row
            let rowContext = context(for: indexPath, identity: row.identity)
            contexts.append(rowContext)
            row.prefetchHandler?(rowContext)
        }
        if !contexts.isEmpty { prefetchItemsHandler?(contexts) }
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        cancelPrefetchingForItemsAt indexPaths: [IndexPath]
    ) {
        var contexts: [ListContext] = []
        for indexPath in indexPaths {
            guard let row = prefetchedRowsByIndexPath.removeValue(forKey: indexPath) ?? row(at: indexPath) else {
                continue
            }
            let rowContext = context(for: indexPath, identity: row.identity)
            contexts.append(rowContext)
            row.cancelPrefetchHandler?(rowContext)
        }
        if !contexts.isEmpty { cancelPrefetchingItemsHandler?(contexts) }
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let row = row(at: indexPath) else { return nil }
        let configuration = row.contextMenuProvider?(context(for: indexPath, identity: row.identity))
            ?? collectionDelegate?.collectionView?(
                collectionView,
                contextMenuConfigurationForItemAt: indexPath,
                point: point
            )
        if configuration != nil { activeContextMenu = (row, indexPath) }
        return configuration
    }

    @available(iOS 16.0, tvOS 17.0, *)
    public func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        let targets = indexPaths.compactMap { indexPath -> (row: AnyListRow, context: ListContext)? in
            guard let row = row(at: indexPath) else { return nil }
            return (row, context(for: indexPath, identity: row.identity))
        }
        let rowConfiguration = targets.first.flatMap { target in
            target.row.contextMenuProvider?(target.context)
        }
        let delegateConfiguration = collectionDelegate?.collectionView?(
            collectionView,
            contextMenuConfigurationForItemsAt: indexPaths,
            point: point
        ) ?? indexPaths.first.flatMap { firstIndexPath in
            collectionDelegate?.collectionView?(
                collectionView,
                contextMenuConfigurationForItemAt: firstIndexPath,
                point: point
            )
        }
        let configuration = contextMenuItemsProvider?(targets.map(\.context), point)
            ?? rowConfiguration
            ?? delegateConfiguration
        if configuration != nil, let first = indexPaths.first, let row = row(at: first) {
            activeContextMenu = (row, first)
        }
        return configuration
    }

    @available(iOS 16.0, tvOS 17.0, *)
    public func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfiguration configuration: UIContextMenuConfiguration,
        highlightPreviewForItemAt indexPath: IndexPath
    ) -> UITargetedPreview? {
        guard let row = row(at: indexPath) else { return nil }
        return row.contextMenuHighlightPreviewProvider?(context(for: indexPath, identity: row.identity))
            ?? collectionDelegate?.collectionView?(
                collectionView,
                contextMenuConfiguration: configuration,
                highlightPreviewForItemAt: indexPath
            )
    }

    @available(iOS 16.0, tvOS 17.0, *)
    public func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfiguration configuration: UIContextMenuConfiguration,
        dismissalPreviewForItemAt indexPath: IndexPath
    ) -> UITargetedPreview? {
        guard let row = row(at: indexPath) else { return nil }
        return row.contextMenuDismissalPreviewProvider?(context(for: indexPath, identity: row.identity))
            ?? collectionDelegate?.collectionView?(
                collectionView,
                contextMenuConfiguration: configuration,
                dismissalPreviewForItemAt: indexPath
            )
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
        animator: any UIContextMenuInteractionCommitAnimating
    ) {
        if let activeContextMenu {
            activeContextMenu.row.contextMenuCommitHandler?(
                context(for: activeContextMenu.indexPath, identity: activeContextMenu.row.identity),
                animator
            )
        }
        collectionDelegate?.collectionView?(
            collectionView,
            willPerformPreviewActionForMenuWith: configuration,
            animator: animator
        )
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        guard let activeContextMenu else {
            return collectionDelegate?.collectionView?(
                collectionView,
                previewForHighlightingContextMenuWithConfiguration: configuration
            )
        }
        return activeContextMenu.row.contextMenuHighlightPreviewProvider?(
            context(for: activeContextMenu.indexPath, identity: activeContextMenu.row.identity)
        ) ?? collectionDelegate?.collectionView?(
            collectionView,
            previewForHighlightingContextMenuWithConfiguration: configuration
        )
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        guard let activeContextMenu else {
            return collectionDelegate?.collectionView?(
                collectionView,
                previewForDismissingContextMenuWithConfiguration: configuration
            )
        }
        return activeContextMenu.row.contextMenuDismissalPreviewProvider?(
            context(for: activeContextMenu.indexPath, identity: activeContextMenu.row.identity)
        ) ?? collectionDelegate?.collectionView?(
            collectionView,
            previewForDismissingContextMenuWithConfiguration: configuration
        )
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        leadingSwipeActionsConfigurationForItemAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let row = row(at: indexPath) else { return nil }
        return row.leadingSwipeActionsProvider?(context(for: indexPath, identity: row.identity))
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        trailingSwipeActionsConfigurationForItemAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let row = row(at: indexPath) else { return nil }
        return row.trailingSwipeActionsProvider?(context(for: indexPath, identity: row.identity))
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isApplyingSnapshot else { return }
        scrollDelegate?.scrollViewDidScroll?(scrollView)
        if !sameObject(scrollDelegate, collectionDelegate) {
            collectionDelegate?.scrollViewDidScroll?(scrollView)
        }
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        scrollDelegate?.scrollViewWillBeginDragging?(scrollView)
        if !sameObject(scrollDelegate, collectionDelegate) {
            collectionDelegate?.scrollViewWillBeginDragging?(scrollView)
        }
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        scrollDelegate?.scrollViewDidEndDragging?(scrollView, willDecelerate: decelerate)
        if !sameObject(scrollDelegate, collectionDelegate) {
            collectionDelegate?.scrollViewDidEndDragging?(scrollView, willDecelerate: decelerate)
        }
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        scrollDelegate?.scrollViewDidEndDecelerating?(scrollView)
        if !sameObject(scrollDelegate, collectionDelegate) {
            collectionDelegate?.scrollViewDidEndDecelerating?(scrollView)
        }
    }

    public func indexTitles(for collectionView: UICollectionView) -> [String]? {
        indexTitleEntries = makeIndexTitleEntries()
        let titles = indexTitleEntries.map(\.title)
        return titles.isEmpty ? nil : titles
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        indexPathForIndexTitle title: String,
        at index: Int
    ) -> IndexPath {
        if let entry = indexTitleEntries[safe: index],
           entry.title == title,
           let indexPath = dataSource.indexPath(for: entry.identity) {
            return indexPath
        }

        indexTitleEntries = makeIndexTitleEntries()
        if let entry = indexTitleEntries.first(where: { $0.title == title }),
           let indexPath = dataSource.indexPath(for: entry.identity) {
            return indexPath
        }

        return firstVisibleItemIndexPath() ?? IndexPath(item: 0, section: 0)
    }

    private func makeIndexTitleEntries() -> [CollectionIndexTitleEntry] {
        sections.compactMap { section in
            guard let title = section.indexTitle,
                  let row = section.rows.first,
                  dataSource.indexPath(for: row.identity) != nil else { return nil }
            return CollectionIndexTitleEntry(title: title, identity: row.identity)
        }
    }

    private func firstVisibleItemIndexPath() -> IndexPath? {
        for section in sections {
            for row in section.rows {
                if let indexPath = dataSource.indexPath(for: row.identity) {
                    return indexPath
                }
            }
        }
        return nil
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        resolvedLayoutDelegate?.collectionView?(collectionView, layout: collectionViewLayout, sizeForItemAt: indexPath)
            ?? (collectionViewLayout as? UICollectionViewFlowLayout)?.itemSize
            ?? UICollectionViewFlowLayout.automaticSize
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        insetForSectionAt section: Int
    ) -> UIEdgeInsets {
        resolvedLayoutDelegate?.collectionView?(collectionView, layout: collectionViewLayout, insetForSectionAt: section)
            ?? (collectionViewLayout as? UICollectionViewFlowLayout)?.sectionInset
            ?? .zero
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        minimumLineSpacingForSectionAt section: Int
    ) -> CGFloat {
        resolvedLayoutDelegate?.collectionView?(collectionView, layout: collectionViewLayout, minimumLineSpacingForSectionAt: section)
            ?? (collectionViewLayout as? UICollectionViewFlowLayout)?.minimumLineSpacing
            ?? 0
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        minimumInteritemSpacingForSectionAt section: Int
    ) -> CGFloat {
        resolvedLayoutDelegate?.collectionView?(collectionView, layout: collectionViewLayout, minimumInteritemSpacingForSectionAt: section)
            ?? (collectionViewLayout as? UICollectionViewFlowLayout)?.minimumInteritemSpacing
            ?? 0
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        referenceSizeForHeaderInSection section: Int
    ) -> CGSize {
        resolvedLayoutDelegate?.collectionView?(collectionView, layout: collectionViewLayout, referenceSizeForHeaderInSection: section)
            ?? (collectionViewLayout as? UICollectionViewFlowLayout)?.headerReferenceSize
            ?? .zero
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        referenceSizeForFooterInSection section: Int
    ) -> CGSize {
        resolvedLayoutDelegate?.collectionView?(collectionView, layout: collectionViewLayout, referenceSizeForFooterInSection: section)
            ?? (collectionViewLayout as? UICollectionViewFlowLayout)?.footerReferenceSize
            ?? .zero
    }

    /// 返回指定 section index 当前对应的业务 section id。
    ///
    /// - Parameter sectionIndex: section 在当前 snapshot 中的位置。
    /// - Returns: 越界时返回 `nil`。
    public func sectionIdentifier(at sectionIndex: Int) -> SectionID? {
        sections[safe: sectionIndex]?.id
    }

    /// 返回指定 section index 当前 row 数量，越界时返回 0。
    ///
    /// - Parameter sectionIndex: section 在当前 snapshot 中的位置。
    /// - Returns: section 内 row 数量；越界时返回 0。
    public func sectionItemsCount(at sectionIndex: Int) -> Int {
        sections[safe: sectionIndex]?.rows.count ?? 0
    }

    /// 返回指定业务 section 当前 row 数量。
    ///
    /// - Parameter sectionID: 要查询的业务 section id。
    /// - Returns: section 内 row 数量；不存在时返回 0。
    public func itemCount(in sectionID: SectionID) -> Int {
        sections.first { $0.id == sectionID }?.rows.count ?? 0
    }

    /// 返回业务 section 当前所在位置。
    public func sectionIndex(for sectionID: SectionID) -> Int? {
        sections.firstIndex { $0.id == sectionID }
    }

    /// 返回当前位置对应的稳定展示身份。
    public func itemIdentity(at indexPath: IndexPath) -> AnyListIdentity? {
        row(at: indexPath)?.identity
    }

    /// 返回当前位置对应的强类型 row id。
    public func rowIdentifier<RowID>(
        at indexPath: IndexPath,
        as type: RowID.Type = RowID.self
    ) -> RowID? where RowID: Hashable & Sendable {
        itemIdentity(at: indexPath)?.rowID.typed(type)
    }

    /// 根据完整展示身份查询当前位置。
    public func indexPath(for identity: AnyListIdentity) -> IndexPath? {
        guard
            let sectionIndex = sections.firstIndex(where: { AnyListID($0.id) == identity.sectionID }),
            let itemIndex = sections[sectionIndex].rows.firstIndex(where: { $0.identity == identity })
        else { return nil }
        return IndexPath(item: itemIndex, section: sectionIndex)
    }

    /// 判断当前描述树是否仍包含指定展示身份。
    public func contains(_ identity: AnyListIdentity) -> Bool {
        indexPath(for: identity) != nil
    }

    /// 根据业务 row id 查询当前 indexPath。
    ///
    /// - Parameters:
    ///   - rowID: 业务 row id。
    ///   - sectionID: 可选的业务 section id；为 `nil` 时查询所有 section。
    /// - Returns: 当前描述树中匹配 row id 的 index paths。
    /// - Note: 查询基于 adapter 当前描述树，页面不需要维护第二套 sections。
    public func indexPaths<RowID>(
        forRowID rowID: RowID,
        in sectionID: SectionID? = nil
    ) -> [IndexPath] where RowID: Hashable & Sendable {
        let targetRowID = AnyListID(rowID)
        let targetSectionID = sectionID.map(AnyListID.init)
        var indexPaths: [IndexPath] = []

        for (sectionIndex, section) in sections.enumerated() {
            let currentSectionID = AnyListID(section.id)
            if let targetSectionID, currentSectionID != targetSectionID {
                continue
            }
            for (itemIndex, row) in section.rows.enumerated() where row.identity.rowID == targetRowID {
                indexPaths.append(IndexPath(item: itemIndex, section: sectionIndex))
            }
        }

        return indexPaths
    }

    /// 滚动到指定 section 或全列表的最后一个 row。
    ///
    /// - Parameters:
    ///   - sectionID: 可选的业务 section id；为 `nil` 时滚动到全列表最后一项。
    ///   - scrollPosition: 目标 item 在 collection view 中的滚动位置。
    ///   - animated: 是否使用滚动动画。
    /// - Returns: 找到可滚动目标并发起滚动时返回 `true`。
    @discardableResult
    public func scrollToLastItem(
        in sectionID: SectionID? = nil,
        at scrollPosition: UICollectionView.ScrollPosition = .bottom,
        animated: Bool = true
    ) -> Bool {
        guard let collectionView, let indexPath = lastItemIndexPath(in: sectionID) else {
            return false
        }
        collectionView.scrollToItem(at: indexPath, at: scrollPosition, animated: animated)
        return true
    }

    /// 轻量重配当前可见 row。
    ///
    /// - Parameters:
    ///   - rowID: 业务 row id。
    ///   - sectionID: 可选的业务 section id；为 `nil` 时匹配所有 section。
    /// - Returns: 实际重配的可见 cell 数量。
    /// - Note: 此方法不触发 diffable reload，也不重新计算自适应高度。
    @discardableResult
    public func reconfigureVisibleRows<RowID>(
        forRowID rowID: RowID,
        in sectionID: SectionID? = nil
    ) -> Int where RowID: Hashable & Sendable {
        guard let collectionView else { return 0 }
        var reconfiguredCount = 0

        for indexPath in visibleIndexPaths(matching: rowID, in: sectionID) {
            guard let row = row(at: indexPath), let cell = collectionView.cellForItem(at: indexPath) else {
                continue
            }
            let context = context(for: indexPath, identity: row.identity)
            row.configureVisibleCell(cell, context)
            reconfiguredCount += 1
        }

        return reconfiguredCount
    }

    /// 通过 diffable snapshot reload 当前可见 row。
    ///
    /// - Parameters:
    ///   - rowID: 业务 row id。
    ///   - sectionID: 可选的业务 section id；为 `nil` 时匹配所有 section。
    /// - Returns: 实际 reload 的可见 item 数量。
    /// - Note: 需要重新量高或更新布局时使用此方法。
    @discardableResult
    public func reloadVisibleRows<RowID>(
        forRowID rowID: RowID,
        in sectionID: SectionID? = nil
    ) -> Int where RowID: Hashable & Sendable {
        let identities = visibleIndexPaths(matching: rowID, in: sectionID)
            .compactMap { row(at: $0)?.identity }
        guard !identities.isEmpty else { return 0 }

        var snapshot = dataSource.snapshot()
        snapshot.reloadItems(identities)
        dataSource.apply(snapshot, animatingDifferences: false)
        return identities.count
    }

    /// 轻量重配当前可见 supplementary view。
    ///
    /// - Parameters:
    ///   - kind: supplementary element kind。
    ///   - sectionID: 可选的业务 section id；为 `nil` 时匹配所有 section。
    /// - Returns: 实际重配的可见 supplementary view 数量。
    @discardableResult
    public func reconfigureVisibleSupplementaries(
        ofKind kind: String,
        in sectionID: SectionID? = nil
    ) -> Int {
        reconfigureVisibleSupplementaries(ofKind: kind, in: sectionID, matchingIndexPaths: nil)
    }

    /// 轻量重配当前可见 item-level supplementary view。
    ///
    /// - Parameters:
    ///   - kind: supplementary element kind。
    ///   - rowID: 业务 row id。
    ///   - sectionID: 可选的业务 section id；为 `nil` 时匹配所有 section。
    /// - Returns: 实际重配的可见 supplementary view 数量。
    @discardableResult
    public func reconfigureVisibleSupplementaries<RowID>(
        ofKind kind: String,
        forRowID rowID: RowID,
        in sectionID: SectionID? = nil
    ) -> Int where RowID: Hashable & Sendable {
        let targetIndexPaths = Set(indexPaths(forRowID: rowID, in: sectionID))
        guard !targetIndexPaths.isEmpty else { return 0 }
        return reconfigureVisibleSupplementaries(
            ofKind: kind,
            in: sectionID,
            matchingIndexPaths: targetIndexPaths
        )
    }

    /// 根据当前 sections 生成 compositional layout。
    ///
    /// - Parameters:
    ///   - fallback: legacy `layoutID` section 使用的 layout provider。
    ///   - diagnostics: layout provider 期间发现前置条件不满足时的处理方式。
    /// - Returns: 可直接赋值给 collection view 的 compositional layout。
    /// - Note: 页面仍需要显式把返回的 layout 赋给 `collectionView.collectionViewLayout`。
    public func makeCompositionalLayout(
        configuration: ListCompositionalLayoutConfiguration = .init(),
        fallback: ((
            ListSection<SectionID>,
            Int,
            any NSCollectionLayoutEnvironment
        ) -> NSCollectionLayoutSection?)? = nil,
        diagnostics: ListDiagnosticsOptions = .debugDefault
    ) -> UICollectionViewCompositionalLayout {
        lastLayoutDiagnostics = []
        let sectionProvider: UICollectionViewCompositionalLayoutSectionProvider = { [weak self] sectionIndex, environment in
            MainActor.assumeIsolated {
                guard let self else { return nil }
                return self.makeCompositionalSection(
                    for: sectionIndex,
                    environment: environment,
                    fallback: fallback,
                    diagnostics: diagnostics
                )
            }
        }
        let layout = UICollectionViewCompositionalLayout(
            sectionProvider: sectionProvider,
            configuration: configuration.makeConfiguration()
        )
        registerBackgroundDecorations(on: layout, sections: sections)
        return layout
    }

    /// 根据当前 section 描述生成单个 compositional layout section。
    ///
    /// - Parameter sectionIndex: 当前 layout provider 请求的 section index。
    /// - Returns: 匹配 section 的 compositional layout section；越界时返回 `nil`。
    /// - Note: 仅支持内建 `ListSectionLayout` 和默认 list layout。legacy `layoutID` 或 custom layout
    /// 需要使用 `makeCompositionalLayout(fallback:)`。
    public func makeCompositionalSection(
        for sectionIndex: Int,
        diagnostics: ListDiagnosticsOptions = .debugDefault
    ) -> NSCollectionLayoutSection? {
        lastLayoutDiagnostics = []
        guard let section = sections[safe: sectionIndex] else { return nil }
        if section.layoutID != nil {
            recordLayoutDiagnostics(
                [unresolvedLayoutIDIssue(for: section, sectionIndex: sectionIndex, fallbackWasProvided: false)],
                options: diagnostics
            )
            return nil
        }
        if section.customSectionLayout != nil {
            recordLayoutDiagnostics(
                [
                    ListDiagnosticsIssue(
                        kind: .invalidLayout,
                        message: "ListKit: makeCompositionalSection(for:) only supports built-in ListSectionLayout; section \(AnyListID(section.id)) uses custom layout and should use makeCompositionalLayout(fallback:)"
                    )
                ],
                options: diagnostics
            )
            return nil
        }
        if section.sectionLayout?.uiKitListLayout != nil {
            recordLayoutDiagnostics(
                [
                    ListDiagnosticsIssue(
                        kind: .invalidLayout,
                        message: "ListKit: UIKitListLayout needs a layout environment; use makeCompositionalLayout() instead of makeCompositionalSection(for:)."
                    )
                ],
                options: diagnostics
            )
            return nil
        }
        return section.makeCompositionalLayoutSection()
    }

    private func makeCompositionalSection(
        for sectionIndex: Int,
        environment: any NSCollectionLayoutEnvironment,
        fallback: ((
            ListSection<SectionID>,
            Int,
            any NSCollectionLayoutEnvironment
        ) -> NSCollectionLayoutSection?)?,
        diagnostics: ListDiagnosticsOptions
    ) -> NSCollectionLayoutSection? {
        guard let section = sections[safe: sectionIndex] else { return nil }
        let fallbackSection: NSCollectionLayoutSection?
        if let customSectionLayout = section.customSectionLayout {
            fallbackSection = customSectionLayout.makeSection(section, sectionIndex, environment)
        } else if let listLayout = section.sectionLayout?.uiKitListLayout {
            var configuration = listLayout.makeConfiguration()
            configuration.leadingSwipeActionsConfigurationProvider = { [weak self] indexPath in
                guard let self, let collectionView = self.collectionView else { return nil }
                return self.collectionView(
                    collectionView,
                    leadingSwipeActionsConfigurationForItemAt: indexPath
                )
            }
            configuration.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
                guard let self, let collectionView = self.collectionView else { return nil }
                return self.collectionView(
                    collectionView,
                    trailingSwipeActionsConfigurationForItemAt: indexPath
                )
            }
            fallbackSection = NSCollectionLayoutSection.list(
                using: configuration,
                layoutEnvironment: environment
            )
        } else if section.layoutID != nil {
            fallbackSection = fallback?(section, sectionIndex, environment)
            if fallbackSection == nil {
                recordLayoutDiagnostics(
                    [unresolvedLayoutIDIssue(for: section, sectionIndex: sectionIndex, fallbackWasProvided: fallback != nil)],
                    options: diagnostics
                )
            }
        } else {
            fallbackSection = nil
        }
        let layoutSection = section.makeCompositionalLayoutSection(fallback: fallbackSection)
        if section.visibleItemsInvalidationHandler != nil {
            layoutSection.visibleItemsInvalidationHandler = { [weak self] items, offset, environment in
                MainActor.assumeIsolated {
                    self?.sections[safe: sectionIndex]?.visibleItemsInvalidationHandler?(items, offset, environment)
                }
            }
        }
        return layoutSection
    }

    private func recordLayoutDiagnostics(
        _ issues: [ListDiagnosticsIssue],
        options: ListDiagnosticsOptions
    ) {
        guard !issues.isEmpty, options.mode != .disabled else { return }
        lastLayoutDiagnostics.append(contentsOf: issues)
        logLayoutDiagnostics(issues: issues, options: options)

        if options.mode == .assertion {
            assertionFailure(issues.map(\.message).joined(separator: "\n"))
        }
    }

    private func logLayoutDiagnostics(
        issues: [ListDiagnosticsIssue],
        options: ListDiagnosticsOptions
    ) {
        #if DEBUG
        guard options.mode != .disabled else { return }
        for issue in issues {
            print(issue.message)
        }
        #endif
    }

    private func unresolvedLayoutIDIssue(
        for section: ListSection<SectionID>,
        sectionIndex: Int,
        fallbackWasProvided: Bool
    ) -> ListDiagnosticsIssue {
        let reason = fallbackWasProvided ? "fallback returned nil" : "no fallback was provided"
        return ListDiagnosticsIssue(
            kind: .unresolvedLayoutID,
            message: "ListKit: section \(AnyListID(section.id)) at index \(sectionIndex) uses legacy layoutID \(section.layoutID.map(String.init(describing:)) ?? "<nil>"), but \(reason); makeCompositionalLayout(fallback:) will use the default list layout for this section"
        )
    }

    private func rebuildLookupTables() {
        rowsByIdentity = [:]
        supplementariesByKindAndSection = [:]

        for section in sections {
            let sectionID = AnyListID(section.id)
            for row in section.rows {
                row.register(collectionView!)
                rowsByIdentity[row.identity] = row
            }
            for supplementary in section.supplementaries {
                supplementary.register(collectionView!)
                supplementariesByKindAndSection[SupplementaryKey(kind: supplementary.kind, sectionID: sectionID)] = supplementary
            }
        }
    }

    private func registerBackgroundDecorationsIfNeeded() {
        guard let layout = collectionView?.collectionViewLayout else { return }
        registerBackgroundDecorations(on: layout, sections: sections)
    }

    private func didReorder(
        _ transaction: NSDiffableDataSourceTransaction<AnyListID, AnyListIdentity>
    ) {
        let initialSnapshot = transaction.initialSnapshot
        let finalSnapshot = transaction.finalSnapshot
        let movedIdentities = transaction.difference.compactMap { change -> AnyListIdentity? in
            guard case let .remove(_, identity, associatedWith: destination) = change,
                  destination != nil
            else { return nil }
            return identity
        }
        let moves = movedIdentities.compactMap { identity -> (AnyListRow, IndexPath, IndexPath)? in
            guard
                let row = rowsByIdentity[identity],
                let source = Self.indexPath(for: identity, in: initialSnapshot),
                let destination = Self.indexPath(for: identity, in: finalSnapshot),
                source != destination
            else { return nil }
            return (row, source, destination)
        }

        for sectionIndex in sections.indices {
            let sectionID = AnyListID(sections[sectionIndex].id)
            sections[sectionIndex].rows = finalSnapshot.itemIdentifiers(inSection: sectionID).compactMap {
                rowsByIdentity[$0]
            }
        }
        moves.forEach { row, source, destination in
            row.moveHandler?(source, destination)
        }
    }

    private func applyOutlineSnapshots(
        generation: Int,
        animatedSectionIDs: Set<AnyListID>,
        completion: @escaping @MainActor () -> Void
    ) {
        let applications = sections.compactMap { section -> ListOutlineSnapshotApplication? in
            guard section.hasOutlineHierarchy else { return nil }
            let sectionID = AnyListID(section.id)
            let snapshot = Self.makeOutlineSnapshot(from: section.outlineRoots)
            guard !Self.outlineSnapshotsAreEquivalent(dataSource.snapshot(for: sectionID), snapshot) else {
                return nil
            }
            return ListOutlineSnapshotApplication(
                sectionID: sectionID,
                snapshot: snapshot,
                animatingDifferences: animatedSectionIDs.contains(sectionID)
            )
        }
        guard !applications.isEmpty else {
            completion()
            return
        }
        applyOutlineSnapshots(
            applications,
            at: 0,
            generation: generation,
            completion: completion
        )
    }

    private func applyOutlineSnapshots(
        _ applications: [ListOutlineSnapshotApplication],
        at index: Int,
        generation: Int,
        completion: @escaping @MainActor () -> Void
    ) {
        guard applyGeneration == generation, let application = applications[safe: index] else {
            completion()
            return
        }
        // Each section snapshot must also finish unwinding before the next one starts.
        let nextApply = ListMainActorCallbackBox { [weak self] in
            guard let self else {
                completion()
                return
            }
            self.applyOutlineSnapshots(
                applications,
                at: index + 1,
                generation: generation,
                completion: completion
            )
        }
        if application.animatingDifferences {
            outlineAnimationGeneration += 1
        }
        dataSource.apply(
            application.snapshot,
            to: application.sectionID,
            animatingDifferences: application.animatingDifferences
        ) {
            nextApply.schedule()
        }
    }

    private static func makeOutlineSnapshot(
        from roots: [AnyListOutlineNode]
    ) -> NSDiffableDataSourceSectionSnapshot<AnyListIdentity> {
        var snapshot = NSDiffableDataSourceSectionSnapshot<AnyListIdentity>()

        func append(_ nodes: [AnyListOutlineNode], to parent: AnyListIdentity?) {
            let identities = nodes.map { $0.row.identity }
            snapshot.append(identities, to: parent)
            for node in nodes where !node.children.isEmpty {
                append(node.children, to: node.row.identity)
                if node.isExpanded { snapshot.expand([node.row.identity]) }
            }
        }
        append(roots, to: nil)
        return snapshot
    }

    private static func outlineSnapshotsAreEquivalent(
        _ lhs: NSDiffableDataSourceSectionSnapshot<AnyListIdentity>,
        _ rhs: NSDiffableDataSourceSectionSnapshot<AnyListIdentity>
    ) -> Bool {
        guard lhs.items == rhs.items, lhs.rootItems == rhs.rootItems else { return false }
        return rhs.items.allSatisfy { identity in
            lhs.parent(of: identity) == rhs.parent(of: identity)
                && lhs.isExpanded(identity) == rhs.isExpanded(identity)
        }
    }

    private func notifyExpansionChange(identity: AnyListIdentity, isExpanded: Bool) {
        guard let section = sections.first(where: { AnyListID($0.id) == identity.sectionID }) else { return }
        section.expansionChangeHandler?(identity, isExpanded)
    }

    private func toggleOutlineDisclosureIfNeeded(
        for row: AnyListRow,
        at indexPath: IndexPath
    ) -> Bool {
        guard row.showsOutlineDisclosure,
              let section = sections[safe: indexPath.section],
              section.hasOutlineHierarchy else { return false }

        let sectionID = AnyListID(section.id)
        var snapshot = dataSource.snapshot(for: sectionID)
        guard snapshot.contains(row.identity),
              !snapshot.snapshot(of: row.identity).items.isEmpty else { return false }

        let willExpand = !snapshot.isExpanded(row.identity)
        if willExpand {
            snapshot.expand([row.identity])
        } else {
            snapshot.collapse([row.identity])
        }
        let animatesOutline = ListTransaction(outlineAnimation: row.outlineAnimation)
            .resolved(reduceMotionEnabled: UIAccessibility.isReduceMotionEnabled)
            .outlineAnimation
        if animatesOutline {
            outlineAnimationGeneration += 1
        }
        notifyExpansionChange(identity: row.identity, isExpanded: willExpand)
        dataSource.apply(snapshot, to: sectionID, animatingDifferences: animatesOutline)
        return true
    }

    private static func indexPath(
        for identity: AnyListIdentity,
        in snapshot: NSDiffableDataSourceSnapshot<AnyListID, AnyListIdentity>
    ) -> IndexPath? {
        guard
            let sectionID = snapshot.sectionIdentifier(containingItem: identity),
            let section = snapshot.indexOfSection(sectionID),
            let item = snapshot.itemIdentifiers(inSection: sectionID).firstIndex(of: identity)
        else { return nil }
        return IndexPath(item: item, section: section)
    }

    private func registerBackgroundDecorations(
        on layout: UICollectionViewLayout,
        sections: [ListSection<SectionID>]
    ) {
        for section in sections {
            section.backgroundDecorationItem?.register(on: layout)
        }
    }

    private static func makeLayoutSignature(from sections: [ListSection<SectionID>]) -> [ListSectionLayoutSignature] {
        sections.map { section in
            ListSectionLayoutSignature(
                sectionID: AnyListID(section.id),
                layoutID: section.layoutID,
                sectionLayout: section.sectionLayout,
                customLayoutID: section.customSectionLayout?.id,
                hasVisibleItemsInvalidationHandler: section.visibleItemsInvalidationHandler != nil,
                supplementarySignatures: section.supplementaries.map { supplementary in
                    ListSupplementaryLayoutSignature(
                        identity: supplementary.identity,
                        kind: supplementary.kind,
                        layout: section.resolvedSupplementaryLayouts().first { $0.kind == supplementary.kind }
                    )
                },
                backgroundDecoration: section.backgroundDecorationItem
            )
        }
    }

    private static func makeCoreSnapshots(from sections: [ListSection<SectionID>]) -> [ListSectionSnapshot] {
        sections.map { section in
            ListSectionSnapshot(
                sectionID: AnyListID(section.id),
                rows: section.rows.map { row in
                    ListNodeSnapshot(
                        identity: row.identity,
                        refreshID: row.refreshID,
                        refreshPolicy: row.refreshPolicy,
                        role: .row
                    )
                },
                supplementaries: section.supplementaries.map { supplementary in
                    ListNodeSnapshot(
                        identity: supplementary.identity,
                        refreshID: supplementary.refreshID,
                        refreshPolicy: supplementary.refreshPolicy,
                        role: .supplementary
                    )
                }
            )
        }
    }

    private func performLayoutUpdate(
        invalidating shouldInvalidate: Bool,
        animated: Bool,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        guard shouldInvalidate, let collectionView else {
            completion(false)
            return
        }

        layoutInvalidationGeneration += 1
        if animated {
            collectionView.performBatchUpdates {
                collectionView.collectionViewLayout.invalidateLayout()
                collectionView.layoutIfNeeded()
            } completion: { finished in
                completion(finished)
            }
        } else {
            UIView.performWithoutAnimation {
                collectionView.collectionViewLayout.invalidateLayout()
                collectionView.layoutIfNeeded()
            }
            completion(false)
        }
    }

    private func refreshVisibleRowsIfNeeded(
        applyPlan: ListApplyPlan,
        animatingContent: Bool,
        coordinator: ListAnimationCompletionCoordinator
    ) -> ListVisibleRefreshResult {
        guard let collectionView else { return ListVisibleRefreshResult() }
        var refreshedCount = 0
        var transitionCount = 0
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard
                let row = row(at: indexPath),
                let rowSnapshot = applyPlan.newRowsByIdentity[row.identity],
                let oldRowSnapshot = applyPlan.oldRowsByIdentity[row.identity],
                ListApplyPlanner.shouldRefreshVisibleRow(rowSnapshot)
            else { continue }

            if let cell = collectionView.cellForItem(at: indexPath) {
                let context = context(for: indexPath, identity: row.identity)
                if animatingContent,
                   oldRowSnapshot.refreshID != rowSnapshot.refreshID,
                   case .opacity(let duration) = row.contentTransition.storage,
                   duration > 0 {
                    coordinator.enter()
                    UIView.transition(
                        with: cell.contentView,
                        duration: duration,
                        options: [.transitionCrossDissolve, .beginFromCurrentState, .allowAnimatedContent]
                    ) {
                        row.configureVisibleCell(cell, context)
                    } completion: { _ in
                        coordinator.leave()
                    }
                    transitionCount += 1
                } else {
                    row.configureVisibleCell(cell, context)
                }
                refreshedCount += 1
            }
        }
        return ListVisibleRefreshResult(
            refreshedCount: refreshedCount,
            transitionCount: transitionCount
        )
    }

    private func refreshVisibleSupplementariesIfNeeded(
        applyPlan: ListApplyPlan
    ) -> Int {
        var refreshedCount = 0
        for target in visibleSupplementaryTargets() {
            guard
                let supplementary = supplementary(kind: target.kind, at: target.indexPath),
                let supplementarySnapshot = applyPlan.newSupplementariesByIdentity[supplementary.identity],
                let oldSupplementarySnapshot = applyPlan.oldSupplementariesByIdentity[supplementary.identity],
                ListApplyPlanner.shouldRefreshVisibleSupplementary(
                    supplementarySnapshot,
                    oldSupplementary: oldSupplementarySnapshot
                )
            else { continue }

            refreshedCount += reconfigureVisibleSupplementary(target, supplementary: supplementary)
        }
        return refreshedCount
    }

    private func reconfigureVisibleSupplementaries(
        ofKind kind: String,
        in sectionID: SectionID?,
        matchingIndexPaths: Set<IndexPath>?
    ) -> Int {
        var refreshedCount = 0
        for target in visibleSupplementaryTargets(
            ofKind: kind,
            in: sectionID,
            matchingIndexPaths: matchingIndexPaths
        ) {
            guard let supplementary = supplementary(kind: kind, at: target.indexPath) else { continue }
            refreshedCount += reconfigureVisibleSupplementary(target, supplementary: supplementary)
        }
        return refreshedCount
    }

    private func reconfigureVisibleSupplementary(
        _ target: VisibleSupplementaryTarget,
        supplementary: AnySupplementary
    ) -> Int {
        guard let configureVisibleView = supplementary.configureVisibleView else { return 0 }
        let context = context(for: target.indexPath, identity: supplementary.identity)
        configureVisibleView(target.view, context)
        return 1
    }

    private func visibleSupplementaryTargets(
        ofKind kind: String? = nil,
        in sectionID: SectionID? = nil,
        matchingIndexPaths: Set<IndexPath>? = nil
    ) -> [VisibleSupplementaryTarget] {
        guard let collectionView else { return [] }
        let visibleRect = CGRect(origin: collectionView.contentOffset, size: collectionView.bounds.size)
        let targetSectionID = sectionID.map(AnyListID.init)
        let attributes = collectionView.collectionViewLayout.layoutAttributesForElements(in: visibleRect) ?? []

        return attributes.compactMap { attributes -> VisibleSupplementaryTarget? in
            guard
                attributes.representedElementCategory == .supplementaryView,
                let elementKind = attributes.representedElementKind
            else { return nil }
            let indexPath = attributes.indexPath
            if let kind, elementKind != kind {
                return nil
            }
            if let targetSectionID, self.sectionID(at: indexPath.section) != targetSectionID {
                return nil
            }
            if let matchingIndexPaths {
                guard matchingIndexPaths.contains(indexPath), isItemSupplementary(kind: elementKind, at: indexPath) else {
                    return nil
                }
            }
            guard let view = collectionView.supplementaryView(forElementKind: elementKind, at: indexPath) else {
                return nil
            }
            return VisibleSupplementaryTarget(kind: elementKind, indexPath: indexPath, view: view)
        }
        .sorted { lhs, rhs in
            lhs.indexPath.section == rhs.indexPath.section
                ? lhs.indexPath.item < rhs.indexPath.item
                : lhs.indexPath.section < rhs.indexPath.section
        }
    }

    private func isItemSupplementary(kind: String, at indexPath: IndexPath) -> Bool {
        guard let section = sections[safe: indexPath.section] else { return false }
        return section.resolvedSupplementaryLayouts().first { $0.kind == kind }?.placement.isItem == true
    }

    private func configureSelectionBehavior() {
        guard let collectionView else { return }
        let selectableSections = sections.filter { $0.selectionMode != .none }
        collectionView.allowsSelection = !selectableSections.isEmpty
        collectionView.allowsMultipleSelection = selectableSections.contains { $0.selectionMode == .multiple }
            || selectableSections.count > 1
            || selectableSections.contains { $0.allowsMultipleSelectionInteraction }
    }

    private func reconcileSelection() {
        guard let collectionView else { return }
        let selectedIndexPaths = (collectionView.indexPathsForSelectedItems ?? []).sorted {
            $0.section == $1.section ? $0.item < $1.item : $0.section < $1.section
        }
        var selectedSingleSections = Set<Int>()

        for indexPath in selectedIndexPaths {
            switch selectionMode(at: indexPath) {
            case .none:
                collectionView.deselectItem(at: indexPath, animated: false)
            case .single:
                if !selectedSingleSections.insert(indexPath.section).inserted {
                    collectionView.deselectItem(at: indexPath, animated: false)
                }
            case .multiple:
                break
            }
        }
    }

    private func deselectOtherItems(
        in section: Int,
        keeping selectedIndexPath: IndexPath,
        collectionView: UICollectionView
    ) {
        let indexPaths = collectionView.indexPathsForSelectedItems ?? []
        for indexPath in indexPaths where indexPath.section == section && indexPath != selectedIndexPath {
            collectionView.deselectItem(at: indexPath, animated: false)
            self.collectionView(collectionView, didDeselectItemAt: indexPath)
        }
    }

    private func selectionMode(at indexPath: IndexPath) -> ListSelectionMode {
        sections[safe: indexPath.section]?.selectionMode ?? .none
    }

    private func row(at indexPath: IndexPath) -> AnyListRow? {
        sections[safe: indexPath.section]?.rows[safe: indexPath.item]
    }

    private func captureVisibleRowAnchor(for target: ListScrollTarget) -> ListVisibleRowAnchor? {
        guard let collectionView else { return nil }
        collectionView.layoutIfNeeded()

        let visibleIndexPaths = Set(collectionView.indexPathsForVisibleItems)
        guard
            let indexPath = indexPaths(for: target)
                .first(where: visibleIndexPaths.contains),
            let identity = dataSource.itemIdentifier(for: indexPath),
            let attributes = collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath)
        else { return nil }

        return ListVisibleRowAnchor(
            identity: identity,
            viewportMinY: attributes.frame.minY - collectionView.contentOffset.y,
            horizontalContentOffset: collectionView.contentOffset.x,
            baseBottomInset: temporaryAnchorBaseBottomInset
                ?? collectionView.contentInset.bottom - preservedAnchorBottomInsetCompensation
        )
    }

    private func reserveScrollRange(for anchor: ListVisibleRowAnchor) {
        guard let collectionView else { return }
        temporaryAnchorBaseBottomInset = anchor.baseBottomInset
        let systemBottomInset = collectionView.adjustedContentInset.bottom - collectionView.contentInset.bottom
        let bottomInsetKeepingCurrentOffset = collectionView.contentOffset.y
            + collectionView.bounds.height
            - systemBottomInset
        UIView.performWithoutAnimation {
            collectionView.contentInset.bottom = max(
                collectionView.contentInset.bottom,
                bottomInsetKeepingCurrentOffset,
                anchor.baseBottomInset
            )
        }
    }

    private func cancelTemporaryAnchorReservation() {
        guard let collectionView, let baseBottomInset = temporaryAnchorBaseBottomInset else { return }
        UIView.performWithoutAnimation {
            collectionView.contentInset.bottom = baseBottomInset + preservedAnchorBottomInsetCompensation
        }
        temporaryAnchorBaseBottomInset = nil
    }

    private func restoreVisibleRowAnchor(_ anchor: ListVisibleRowAnchor) -> CGFloat {
        guard let collectionView else { return 0 }
        collectionView.layoutIfNeeded()

        guard
            let indexPath = Self.indexPath(for: anchor.identity, in: dataSource.snapshot()),
            let attributes = collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath)
        else {
            preservedAnchorBottomInsetCompensation = 0
            UIView.performWithoutAnimation {
                collectionView.contentInset.bottom = anchor.baseBottomInset
            }
            temporaryAnchorBaseBottomInset = nil
            return 0
        }

        let minimumOffsetY = -collectionView.adjustedContentInset.top
        let desiredOffsetY = max(minimumOffsetY, attributes.frame.minY - anchor.viewportMinY)
        let systemBottomInset = collectionView.adjustedContentInset.bottom - collectionView.contentInset.bottom
        let maximumOffsetWithoutCompensation = max(
            minimumOffsetY,
            collectionView.contentSize.height
                - collectionView.bounds.height
                + systemBottomInset
                + anchor.baseBottomInset
        )
        let compensation = max(0, desiredOffsetY - maximumOffsetWithoutCompensation)

        preservedAnchorBottomInsetCompensation = compensation
        temporaryAnchorBaseBottomInset = nil
        UIView.performWithoutAnimation {
            collectionView.contentInset.bottom = anchor.baseBottomInset + compensation
            collectionView.layoutIfNeeded()
            collectionView.setContentOffset(
                CGPoint(x: anchor.horizontalContentOffset, y: desiredOffsetY),
                animated: false
            )
        }
        return compensation
    }

    private func normalizeAnchorCompensation() -> CGFloat {
        guard let collectionView else { return 0 }
        guard temporaryAnchorBaseBottomInset != nil || preservedAnchorBottomInsetCompensation > 0 else {
            return 0
        }
        cancelTemporaryAnchorReservation()
        let baseBottomInset = collectionView.contentInset.bottom - preservedAnchorBottomInsetCompensation
        let systemBottomInset = collectionView.adjustedContentInset.bottom - collectionView.contentInset.bottom
        let minimumOffsetY = -collectionView.adjustedContentInset.top
        let maximumOffsetWithoutCompensation = max(
            minimumOffsetY,
            collectionView.contentSize.height
                - collectionView.bounds.height
                + systemBottomInset
                + baseBottomInset
        )
        let compensation = max(0, collectionView.contentOffset.y - maximumOffsetWithoutCompensation)
        preservedAnchorBottomInsetCompensation = compensation
        UIView.performWithoutAnimation {
            collectionView.contentInset.bottom = baseBottomInset + compensation
        }
        return compensation
    }

    private func performScrollBehavior(
        _ behavior: ListScrollBehavior,
        visibleAnchor: ListVisibleRowAnchor?,
        animated: Bool
    ) -> ListScrollOutcome {
        guard let collectionView else { return ListScrollOutcome() }
        collectionView.layoutIfNeeded()

        switch behavior.storage {
        case .none:
            return ListScrollOutcome(anchorCompensation: normalizeAnchorCompensation())
        case .preserveVisiblePosition:
            guard let visibleAnchor else {
                return ListScrollOutcome(anchorCompensation: normalizeAnchorCompensation())
            }
            return ListScrollOutcome(anchorCompensation: restoreVisibleRowAnchor(visibleAnchor))
        case .scrollTo(let target, let position):
            let compensation = normalizeAnchorCompensation()
            guard let indexPath = indexPaths(for: target).first else {
                return ListScrollOutcome(anchorCompensation: compensation)
            }
            collectionView.scrollToItem(
                at: indexPath,
                at: position.collectionViewPosition,
                animated: animated
            )
            return ListScrollOutcome(animated: animated, anchorCompensation: compensation)
        case .scrollToLast(let sectionID, let position):
            let compensation = normalizeAnchorCompensation()
            guard let indexPath = lastItemIndexPath(inAnySectionID: sectionID) else {
                return ListScrollOutcome(anchorCompensation: compensation)
            }
            collectionView.scrollToItem(
                at: indexPath,
                at: position.collectionViewPosition,
                animated: animated
            )
            return ListScrollOutcome(animated: animated, anchorCompensation: compensation)
        }
    }

    private func indexPaths(for target: ListScrollTarget) -> [IndexPath] {
        let snapshot = dataSource.snapshot()
        return snapshot.itemIdentifiers.compactMap { identity in
            guard identity.rowID == target.rowID,
                  target.sectionID == nil || identity.sectionID == target.sectionID else { return nil }
            return Self.indexPath(for: identity, in: snapshot)
        }
    }

    private func acquireSerialApplySlot() async {
        if !isSerialApplyActive {
            isSerialApplyActive = true
            return
        }
        await withCheckedContinuation { continuation in
            serialApplyWaiters.append(continuation)
        }
    }

    private func releaseSerialApplySlot() {
        guard !serialApplyWaiters.isEmpty else {
            isSerialApplyActive = false
            return
        }
        serialApplyWaiters.removeFirst().resume()
    }

    private func lastItemIndexPath(in sectionID: SectionID?) -> IndexPath? {
        if let sectionID {
            guard
                let sectionIndex = sections.firstIndex(where: { $0.id == sectionID }),
                let itemIndex = sections[sectionIndex].rows.indices.last
            else { return nil }
            return IndexPath(item: itemIndex, section: sectionIndex)
        }

        for sectionIndex in sections.indices.reversed() {
            guard let itemIndex = sections[sectionIndex].rows.indices.last else { continue }
            return IndexPath(item: itemIndex, section: sectionIndex)
        }
        return nil
    }

    private func lastItemIndexPath(inAnySectionID sectionID: AnyListID?) -> IndexPath? {
        let snapshot = dataSource.snapshot()
        if let sectionID {
            guard let section = snapshot.indexOfSection(sectionID),
                  let identity = snapshot.itemIdentifiers(inSection: sectionID).last,
                  let item = snapshot.itemIdentifiers(inSection: sectionID).firstIndex(of: identity)
            else { return nil }
            return IndexPath(item: item, section: section)
        }
        guard let identity = snapshot.itemIdentifiers.last else { return nil }
        return Self.indexPath(for: identity, in: snapshot)
    }

    private func visibleIndexPaths<RowID>(
        matching rowID: RowID,
        in sectionID: SectionID?
    ) -> [IndexPath] where RowID: Hashable & Sendable {
        guard let collectionView else { return [] }
        let targetIndexPaths = Set(indexPaths(forRowID: rowID, in: sectionID))
        return collectionView.indexPathsForVisibleItems
            .filter { targetIndexPaths.contains($0) }
            .sorted { lhs, rhs in
                lhs.section == rhs.section ? lhs.item < rhs.item : lhs.section < rhs.section
            }
    }

    private func supplementary(kind: String, at indexPath: IndexPath) -> AnySupplementary? {
        let sectionID = sectionID(at: indexPath.section)
        return supplementariesByKindAndSection[SupplementaryKey(kind: kind, sectionID: sectionID)]
    }

    private func sectionID(at sectionIndex: Int) -> AnyListID {
        guard let section = sections[safe: sectionIndex] else {
            return AnyListID(sectionIndex)
        }
        return AnyListID(section.id)
    }

    private func context(for indexPath: IndexPath, identity: AnyListIdentity) -> ListContext {
        guard let collectionView else {
            fatalError("CollectionListAdapter collectionView was released")
        }
        return ListContext(identity: identity, indexPath: indexPath, collectionView: collectionView) { [weak self] event, context in
            self?.dispatch(event, context: context)
        }
    }

    private func dispatch(_ event: any ListEvent, context: ListContext) {
        eventRouter.dispatch(event, context: context)
    }

    private func sameObject(_ lhs: AnyObject?, _ rhs: AnyObject?) -> Bool {
        guard let lhs, let rhs else { return false }
        return lhs === rhs
    }
}

/// 一次 `apply` 调用的返回值。
///
/// - Usage:
/// ```swift
/// let result = adapter.apply {
///     ListSection(.users) { ... }
/// }
/// .onEvent(UserListEvent.self) { event, context in
///     router.handle(event, from: context.indexPath)
/// }
///
/// print(result.summary.visibleRefreshCount)
/// ```
/// - Note: 返回值可以读取本次 apply 的 summary，也可以链式绑定事件处理。
@MainActor
public struct ListApplyResult<SectionID> where SectionID: Hashable & Sendable {
    fileprivate weak var adapter: CollectionListAdapter<SectionID>?
    public let summary: ListApplySummary

    /// 在本次 apply 关联的 adapter 上绑定业务事件。
    ///
    /// - Parameters:
    ///   - eventType: 要接收的事件类型。
    ///   - handler: 主线程回调的事件处理闭包。
    /// - Returns: 原始 `ListApplyResult`，便于继续链式调用。
    @discardableResult
    public func onEvent<Event>(
        _ eventType: Event.Type = Event.self,
        handler: @escaping @MainActor (Event, ListContext) -> Void
    ) -> Self where Event: ListEvent {
        adapter?.onEvent(eventType, handler: handler)
        return self
    }
}

private struct SupplementaryKey: Hashable {
    let kind: String
    let sectionID: AnyListID
}

private struct VisibleSupplementaryTarget {
    let kind: String
    let indexPath: IndexPath
    let view: UICollectionReusableView
}

private struct ListVisibleRowAnchor {
    let identity: AnyListIdentity
    let viewportMinY: CGFloat
    let horizontalContentOffset: CGFloat
    let baseBottomInset: CGFloat
}

private struct ListVisibleRefreshResult {
    var refreshedCount = 0
    var transitionCount = 0
}

private struct ListScrollOutcome {
    var animated = false
    var anchorCompensation: CGFloat = 0
}

@MainActor
private final class CollectionApplyAnimationMetrics {
    var visibleRefreshCount = 0
    var visibleSupplementaryRefreshCount = 0
    var contentTransitionCount = 0
    var layoutAnimated = false
    var scrollOutcome = ListScrollOutcome()
}

private extension ListScrollPosition {
    var collectionViewPosition: UICollectionView.ScrollPosition {
        switch self {
        case .top: .top
        case .center: .centeredVertically
        case .bottom: .bottom
        case .nearest: []
        }
    }
}

private struct ListSectionLayoutSignature: Hashable {
    let sectionID: AnyListID
    let layoutID: AnyListID?
    let sectionLayout: ListSectionLayout?
    let customLayoutID: AnyListID?
    let hasVisibleItemsInvalidationHandler: Bool
    let supplementarySignatures: [ListSupplementaryLayoutSignature]
    let backgroundDecoration: ListBackgroundDecoration?
}

private struct ListSupplementaryLayoutSignature: Hashable {
    let identity: AnyListIdentity
    let kind: String
    let layout: ListSupplementaryLayout?
}

private struct ListOutlineSnapshotApplication: Sendable {
    let sectionID: AnyListID
    let snapshot: NSDiffableDataSourceSectionSnapshot<AnyListIdentity>
    let animatingDifferences: Bool
}

private final class ListMainActorCallbackBox: @unchecked Sendable {
    private let callback: () -> Void

    init(_ callback: @escaping () -> Void) {
        self.callback = callback
    }

    @MainActor func call() {
        callback()
    }

    nonisolated func schedule() {
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated {
                callback()
            }
        }
    }
}

private final class ListUnsafeForwardingTarget: @unchecked Sendable {
    let value: AnyObject?

    init(_ value: AnyObject?) {
        self.value = value
    }
}

private struct CollectionIndexTitleEntry {
    let title: String
    let identity: AnyListIdentity
}

private final class CollectionDiffableDataSource<SectionID>:
    UICollectionViewDiffableDataSource<AnyListID, AnyListIdentity>
where SectionID: Hashable & Sendable {
    weak var adapter: CollectionListAdapter<SectionID>?

    override func indexTitles(for collectionView: UICollectionView) -> [String]? {
        adapter?.indexTitles(for: collectionView)
    }

    override func collectionView(
        _ collectionView: UICollectionView,
        indexPathForIndexTitle title: String,
        at index: Int
    ) -> IndexPath {
        adapter?.collectionView(collectionView, indexPathForIndexTitle: title, at: index)
            ?? IndexPath(item: 0, section: 0)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
