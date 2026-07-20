import UIKit

// MARK: - Table Adapter

/// UITableView 列表适配器。
///
/// `TableListAdapter` 使用独立的 Table DSL 描述内容，并复用 ListKit 的 identity、
/// refresh、diagnostics、apply options 和事件语义。
///
/// ```swift
/// adapter.apply {
///     TableSection(.messages) {
///         TableForEach(messages, id: \.id) { message in
///             TableRow(model: message, cell: MessageCell.self) { cell, message, _ in
///                 cell.configure(message)
///             }
///             .refreshID(message.version)
///         }
///     }
/// }
/// ```
@MainActor
public final class TableListAdapter<SectionID>: NSObject, UITableViewDelegate, UITableViewDataSource, UITableViewDataSourcePrefetching
where SectionID: Hashable & Sendable {
    /// 滚动回调转发对象。
    public weak var scrollDelegate: UIScrollViewDelegate?

    /// table delegate 转发对象；选择或高亮回调会参与 `.automatic` 交互能力推断。
    public weak var tableDelegate: UITableViewDelegate? {
        didSet { configureSelectionBehavior() }
    }

    /// UIKit data source 逃生口，仅用于 ListKit 未声明的可选能力。
    public weak var tableDataSource: UITableViewDataSource?

    /// 原生 drag/drop 逃生口；设置后直接安装到 table view。
    public weak var dragDelegate: UITableViewDragDelegate? {
        didSet { tableView?.dragDelegate = dragDelegate }
    }
    public weak var dropDelegate: UITableViewDropDelegate? {
        didSet { tableView?.dropDelegate = dropDelegate }
    }

    /// 最近一次 `apply` 的摘要。
    public private(set) var lastApplySummary = ListApplySummary()

    /// Table diffable data source 在差异提交时使用的默认行动画。
    public var defaultRowAnimation: UITableView.RowAnimation {
        get { dataSource.defaultRowAnimation }
        set { dataSource.defaultRowAnimation = newValue }
    }

    private weak var tableView: UITableView?
    private var sections: [TableSection<SectionID>] = []
    private var dataSource: TableDiffableDataSource<SectionID>!
    private var rowsByIdentity: [AnyListIdentity: AnyTableRow] = [:]
    private var displayedRowsByCell: [ObjectIdentifier: AnyTableRow] = [:]
    private var displayedSupplementariesByView: [ObjectIdentifier: TableDisplayedSupplementary] = [:]
    private var prefetchedRowsByIndexPath: [IndexPath: AnyTableRow] = [:]
    private var applyGeneration = 0
    private var prefetchRowsHandler: (@MainActor ([TableListContext]) -> Void)?
    private var cancelPrefetchingRowsHandler: (@MainActor ([TableListContext]) -> Void)?
    private var activeContextMenu: (row: AnyTableRow, indexPath: IndexPath)?
    private var preservedAnchorBottomInsetCompensation: CGFloat = 0
    private var temporaryAnchorBaseBottomInset: CGFloat?
    private var isSerialApplyActive = false
    private var serialApplyWaiters: [CheckedContinuation<Void, Never>] = []
    private let eventRouter = ListEventRouter<TableListContext>()

    /// 创建 adapter 并接管 table view 的 data source、delegate 和 prefetch data source。
    ///
    /// - Parameter tableView: 由 adapter 管理 diffable data source、delegate 和预取回调的 table view。
    public init(tableView: UITableView) {
        self.tableView = tableView
        super.init()

        dataSource = TableDiffableDataSource<SectionID>(
            tableView: tableView
        ) { [weak self] tableView, indexPath, identity in
            guard let self, let row = self.rowsByIdentity[identity] else {
                return UITableViewCell()
            }
            return row.cellProvider(tableView, indexPath, self.context(for: indexPath, identity: identity))
        }
        dataSource.adapter = self

        tableView.dataSource = dataSource
        tableView.delegate = self
        tableView.prefetchDataSource = self
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
            TableUnsafeForwardingTarget(
                forwardingDelegates.first { delegate in
                    (delegate as? NSObjectProtocol)?.responds(to: aSelector) == true
                }
            )
        }
        return target.value
    }

    private var forwardingDelegates: [AnyObject] {
        [tableDelegate, tableDataSource, scrollDelegate].compactMap { $0 as AnyObject? }
    }

    /// 提交一次 table 更新。需要等待动画完成时使用 async 重载。
    @discardableResult
    public func apply(
        options: ListApplyOptions,
        completion: ((ListApplySummary) -> Void)? = nil,
        @TableSectionBuilder<SectionID> _ content: () -> [TableSection<SectionID>]
    ) -> TableApplyResult<SectionID> {
        _apply(options: options, completion: completion, content)
    }

    /// 以 SwiftUI 风格的 transaction 提交更新。
    @discardableResult
    public func apply(
        transaction: ListTransaction = .automatic,
        completion: ((ListApplySummary) -> Void)? = nil,
        @TableSectionBuilder<SectionID> _ content: () -> [TableSection<SectionID>]
    ) -> TableApplyResult<SectionID> {
        apply(
            options: ListApplyOptions(transaction: transaction),
            completion: completion,
            content
        )
    }

    /// 提交已经构建好的 table sections。
    @discardableResult
    public func apply(
        _ sections: [TableSection<SectionID>],
        options: ListApplyOptions,
        completion: ((ListApplySummary) -> Void)? = nil
    ) -> TableApplyResult<SectionID> {
        apply(options: options, completion: completion) { sections }
    }

    /// 以 transaction 提交已经构建好的 sections。
    @discardableResult
    public func apply(
        _ sections: [TableSection<SectionID>],
        transaction: ListTransaction = .automatic,
        completion: ((ListApplySummary) -> Void)? = nil
    ) -> TableApplyResult<SectionID> {
        apply(
            sections,
            options: ListApplyOptions(transaction: transaction),
            completion: completion
        )
    }

    private func _apply(
        options: ListApplyOptions,
        completion: ((ListApplySummary) -> Void)?,
        @TableSectionBuilder<SectionID> _ content: () -> [TableSection<SectionID>]
    ) -> TableApplyResult<SectionID> {
        let newSections = content()
        let resolvedTransaction = options.transaction.resolved(
            reduceMotionEnabled: UIAccessibility.isReduceMotionEnabled
        )
        let applyPlan = ListApplyPlanner.makePlan(
            old: Self.makeCoreSnapshots(from: sections),
            new: Self.makeCoreSnapshots(from: newSections),
            options: options,
            diagnosticsIssues: ListDiagnostics.validate(Self.makeCoreSnapshots(from: newSections))
        )
        let diagnosticsIssues = applyPlan.initialSummary.diagnosticsIssues

        if !applyPlan.shouldApplyDiffable {
            let summary = applyPlan.initialSummary.replacingAnimation(
                ListAnimationSummary(
                    completionState: .completed,
                    reduceMotionApplied: resolvedTransaction.reduceMotionApplied
                )
            )
            lastApplySummary = summary
            ListApplyLogger.logDiagnostics(issues: diagnosticsIssues, options: options)
            ListApplyLogger.logApplySummary(summary, options: options, prefix: "ListKit table apply summary")
            completion?(summary)
            return TableApplyResult(adapter: self, summary: summary)
        }

        let visibleAnchor: TableVisibleRowAnchor?
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
        let selectedItemIdentities = captureSelectedItemIdentities()

        applyGeneration += 1
        let generation = applyGeneration
        sections = newSections
        rebuildLookupTables()
        configureSelectionBehavior()

        var snapshot = NSDiffableDataSourceSnapshot<AnyListID, AnyListIdentity>()
        for section in newSections {
            let sectionID = AnyListID(section.id)
            snapshot.appendSections([sectionID])
            snapshot.appendItems(section.rows.map(\.identity), toSection: sectionID)
        }

        let refreshItems = applyPlan.snapshotRefreshItems
        if !refreshItems.isEmpty {
            snapshot.reloadItems(refreshItems)
        }

        let summary = applyPlan.initialSummary.replacingAnimation(
            ListAnimationSummary(reduceMotionApplied: resolvedTransaction.reduceMotionApplied)
        )
        lastApplySummary = summary
        ListApplyLogger.logDiagnostics(issues: diagnosticsIssues, options: options)

        let completeAsSuperseded = {
            let supersededSummary = summary.replacingAnimation(
                ListAnimationSummary(
                    completionState: .superseded,
                    reduceMotionApplied: resolvedTransaction.reduceMotionApplied
                )
            )
            ListApplyLogger.logApplySummary(
                supersededSummary,
                options: options,
                prefix: "ListKit table apply summary"
            )
            completion?(supersededSummary)
        }

        // Normalize UIKit's diffable completion onto a fresh main-actor turn.
        let didApplyBox = TableMainActorCallbackBox { [weak self] in
            guard let self else { return }
            guard self.applyGeneration == generation else {
                completeAsSuperseded()
                return
            }
            self.restoreSelection(for: selectedItemIdentities)
            self.synchronizeControlledSelection()
            self.reconcileSelection()
            let metrics = TableApplyAnimationMetrics()
            let animationCoordinator = ListAnimationCompletionCoordinator {
                guard self.applyGeneration == generation else {
                    completeAsSuperseded()
                    return
                }
                let scrollOutcome = self.performScrollBehavior(
                    resolvedTransaction.scrollBehavior,
                    visibleAnchor: visibleAnchor,
                    animated: resolvedTransaction.scrollAnimation
                )
                let snapshotAnimated = options.applicationMode == .differences
                    && resolvedTransaction.snapshotAnimation
                    && applyPlan.hasSnapshotChanges
                let completedSummary = applyPlan.completedSummary(
                    visibleRefreshCount: metrics.visibleRefreshCount,
                    visibleSupplementaryRefreshCount: metrics.visibleSupplementaryRefreshCount,
                    animation: ListAnimationSummary(
                        completionState: .completed,
                        snapshotAnimated: snapshotAnimated,
                        animatedSectionCount: snapshotAnimated ? applyPlan.changedSectionCount : 0,
                        contentTransitionCount: metrics.contentTransitionCount,
                        layoutInvalidated: metrics.layoutInvalidated,
                        layoutAnimated: metrics.layoutAnimated,
                        scrollAnimated: scrollOutcome.animated,
                        anchorCompensation: scrollOutcome.anchorCompensation,
                        reduceMotionApplied: resolvedTransaction.reduceMotionApplied
                    )
                )
                self.lastApplySummary = completedSummary
                ListApplyLogger.logApplySummary(
                    completedSummary,
                    options: options,
                    prefix: "ListKit table apply summary"
                )
                completion?(completedSummary)
            }

            if applyPlan.shouldRunVisibleRefresh {
                let refresh = self.refreshVisibleRowsIfNeeded(
                    applyPlan: applyPlan,
                    strategy: options.refreshStrategy,
                    animatingContent: resolvedTransaction.contentAnimation,
                    coordinator: animationCoordinator
                )
                metrics.visibleRefreshCount = refresh.refreshedCount
                metrics.contentTransitionCount = refresh.transitionCount
                metrics.visibleSupplementaryRefreshCount = self.refreshVisibleSupplementariesIfNeeded(
                    applyPlan: applyPlan
                )
                metrics.layoutInvalidated = refresh.needsLayoutInvalidation
                metrics.layoutAnimated = self.performLayoutUpdate(
                    invalidating: metrics.layoutInvalidated,
                    animated: resolvedTransaction.layoutAnimation,
                    coordinator: animationCoordinator
                )
            }
            animationCoordinator.finishScheduling()
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

        return TableApplyResult(adapter: self, summary: summary)
    }

    /// 重建描述树并等待 snapshot、layout 和内容过渡完成。
    @discardableResult
    public func applyAndWait(
        options: ListApplyOptions,
        @TableSectionBuilder<SectionID> _ content: () -> [TableSection<SectionID>]
    ) async -> TableApplyResult<SectionID> {
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
            return TableApplyResult(
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
                continuation.resume(returning: TableApplyResult(adapter: self, summary: summary))
            }) {
                builtSections
            }
        }
        if usesSerialScheduling {
            releaseSerialApplySlot()
        }
        return result
    }

    /// 提交 transaction，并等待 snapshot、layout 和内容过渡完成。
    @discardableResult
    public func applyAndWait(
        transaction: ListTransaction = .automatic,
        @TableSectionBuilder<SectionID> _ content: () -> [TableSection<SectionID>]
    ) async -> TableApplyResult<SectionID> {
        await applyAndWait(options: ListApplyOptions(transaction: transaction), content)
    }

    /// 绑定自定义业务事件。
    ///
    /// - Parameters:
    ///   - eventType: 事件类型。
    ///   - handler: 事件处理闭包。
    /// - Returns: 当前 adapter，便于链式调用。
    @discardableResult
    public func onEvent<Event>(
        _ eventType: Event.Type = Event.self,
        handler: @escaping @MainActor (Event, TableListContext) -> Void
    ) -> Self where Event: ListEvent {
        eventRouter.on(eventType, handler: handler)
        return self
    }

    /// 监听 UIKit 一次批量预取请求。
    @discardableResult
    public func onPrefetchRows(_ handler: @escaping @MainActor ([TableListContext]) -> Void) -> Self {
        prefetchRowsHandler = handler
        return self
    }

    /// 监听 UIKit 一次批量取消预取请求。
    @discardableResult
    public func onCancelPrefetchingRows(_ handler: @escaping @MainActor ([TableListContext]) -> Void) -> Self {
        cancelPrefetchingRowsHandler = handler
        return self
    }

    public func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[safe: section]?.rows.count ?? 0
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let row = row(at: indexPath) else { return UITableViewCell() }
        return row.cellProvider(tableView, indexPath, context(for: indexPath, identity: row.identity))
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let row = row(at: indexPath) else { return }
        if selectionMode(at: indexPath) == .single {
            deselectOtherRows(in: indexPath.section, keeping: indexPath, tableView: tableView)
        }
        let context = context(for: indexPath, identity: row.identity)
        row.selectHandler?(context)
        row.selectionChangeHandler?(true, context)
        tableDelegate?.tableView?(tableView, didSelectRowAt: indexPath)
    }

    public func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        guard let row = row(at: indexPath) else { return }
        let context = context(for: indexPath, identity: row.identity)
        row.deselectHandler?(context)
        row.selectionChangeHandler?(false, context)
        tableDelegate?.tableView?(tableView, didDeselectRowAt: indexPath)
    }

    public func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        guard selectionMode(at: indexPath) != .none, row(at: indexPath)?.isSelectionDisabled != true else {
            return nil
        }
        return tableDelegate?.tableView?(tableView, willSelectRowAt: indexPath) ?? indexPath
    }

    public func tableView(_ tableView: UITableView, willDeselectRowAt indexPath: IndexPath) -> IndexPath? {
        guard selectionMode(at: indexPath) != .none, row(at: indexPath)?.isSelectionDisabled != true else {
            return nil
        }
        return tableDelegate?.tableView?(tableView, willDeselectRowAt: indexPath) ?? indexPath
    }

    @available(*, deprecated, renamed: "tableView(_:willSelectRowAt:)")
    public func tableView(_ tableView: UITableView, shouldSelectRowAt indexPath: IndexPath) -> IndexPath? {
        self.tableView(tableView, willSelectRowAt: indexPath)
    }

    @available(*, deprecated, renamed: "tableView(_:willDeselectRowAt:)")
    public func tableView(_ tableView: UITableView, shouldDeselectRowAt indexPath: IndexPath) -> IndexPath? {
        self.tableView(tableView, willDeselectRowAt: indexPath)
    }

    public func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        guard let row = row(at: indexPath) else { return false }
        let allowsListKitHighlight = row.hasAutomaticHighlightIntent
            || (!row.isSelectionDisabled && selectionMode(at: indexPath) != .none)
        guard allowsListKitHighlight || tableDelegateHasHighlightIntent else { return false }
        return tableDelegate?.tableView?(tableView, shouldHighlightRowAt: indexPath) ?? true
    }

    public func tableView(_ tableView: UITableView, didHighlightRowAt indexPath: IndexPath) {
        if let row = row(at: indexPath) {
            row.highlightChangeHandler?(true, context(for: indexPath, identity: row.identity))
        }
        tableDelegate?.tableView?(tableView, didHighlightRowAt: indexPath)
    }

    public func tableView(_ tableView: UITableView, didUnhighlightRowAt indexPath: IndexPath) {
        if let row = row(at: indexPath) {
            row.highlightChangeHandler?(false, context(for: indexPath, identity: row.identity))
        }
        tableDelegate?.tableView?(tableView, didUnhighlightRowAt: indexPath)
    }

    @available(iOS 16.0, tvOS 16.0, *)
    public func tableView(_ tableView: UITableView, performPrimaryActionForRowAt indexPath: IndexPath) {
        if let row = row(at: indexPath) {
            row.primaryActionHandler?(context(for: indexPath, identity: row.identity))
        }
        tableDelegate?.tableView?(tableView, performPrimaryActionForRowAt: indexPath)
    }

    public func tableView(_ tableView: UITableView, canFocusRowAt indexPath: IndexPath) -> Bool {
        row(at: indexPath)?.isFocusable
            ?? tableDelegate?.tableView?(tableView, canFocusRowAt: indexPath)
            ?? true
    }

    @available(iOS 15.0, tvOS 15.0, *)
    public func tableView(_ tableView: UITableView, selectionFollowsFocusForRowAt indexPath: IndexPath) -> Bool {
        row(at: indexPath)?.selectionFollowsFocus
            ?? tableDelegate?.tableView?(tableView, selectionFollowsFocusForRowAt: indexPath)
            ?? tableView.selectionFollowsFocus
    }

    public func tableView(
        _ tableView: UITableView,
        shouldSpringLoadRowAt indexPath: IndexPath,
        with context: any UISpringLoadedInteractionContext
    ) -> Bool {
        row(at: indexPath)?.isSpringLoadingEnabled
            ?? tableDelegate?.tableView?(tableView, shouldSpringLoadRowAt: indexPath, with: context)
            ?? true
    }

    public func tableView(
        _ tableView: UITableView,
        shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath
    ) -> Bool {
        guard
            sections[safe: indexPath.section]?.allowsMultipleSelectionInteraction == true,
            selectionMode(at: indexPath) == .multiple,
            row(at: indexPath)?.isSelectionDisabled != true
        else { return false }
        return tableDelegate?.tableView?(
            tableView,
            shouldBeginMultipleSelectionInteractionAt: indexPath
        ) ?? true
    }

    public func tableView(
        _ tableView: UITableView,
        didBeginMultipleSelectionInteractionAt indexPath: IndexPath
    ) {
        tableDelegate?.tableView?(tableView, didBeginMultipleSelectionInteractionAt: indexPath)
    }

    public func tableViewDidEndMultipleSelectionInteraction(_ tableView: UITableView) {
        tableDelegate?.tableViewDidEndMultipleSelectionInteraction?(tableView)
    }

    public func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let row = row(at: indexPath) {
            displayedRowsByCell[ObjectIdentifier(cell)] = row
            row.displayHandler?(cell, context(for: indexPath, identity: row.identity))
        }
        tableDelegate?.tableView?(tableView, willDisplay: cell, forRowAt: indexPath)
    }

    public func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let row = displayedRowsByCell.removeValue(forKey: ObjectIdentifier(cell)) ?? row(at: indexPath)
        if let row {
            row.endDisplayHandler?(cell, context(for: indexPath, identity: row.identity))
        }
        tableDelegate?.tableView?(tableView, didEndDisplaying: cell, forRowAt: indexPath)
    }

    public func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard let header = sections[safe: section]?.header, let headerView = view as? UITableViewHeaderFooterView else {
            tableDelegate?.tableView?(tableView, willDisplayHeaderView: view, forSection: section)
            return
        }
        displayedSupplementariesByView[ObjectIdentifier(view)] = TableDisplayedSupplementary(
            role: .header,
            supplementary: header
        )
        header.displayHandler?(
            headerView,
            context(for: IndexPath(row: 0, section: section), identity: header.identity)
        )
        tableDelegate?.tableView?(tableView, willDisplayHeaderView: view, forSection: section)
    }

    public func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        guard let footer = sections[safe: section]?.footer, let footerView = view as? UITableViewHeaderFooterView else {
            tableDelegate?.tableView?(tableView, willDisplayFooterView: view, forSection: section)
            return
        }
        displayedSupplementariesByView[ObjectIdentifier(view)] = TableDisplayedSupplementary(
            role: .footer,
            supplementary: footer
        )
        footer.displayHandler?(
            footerView,
            context(for: IndexPath(row: 0, section: section), identity: footer.identity)
        )
        tableDelegate?.tableView?(tableView, willDisplayFooterView: view, forSection: section)
    }

    public func tableView(_ tableView: UITableView, didEndDisplayingHeaderView view: UIView, forSection section: Int) {
        let displayed = displayedSupplementariesByView.removeValue(forKey: ObjectIdentifier(view))
        let header = displayed?.role == .header
            ? displayed?.supplementary
            : sections[safe: section]?.header
        guard let header, let headerView = view as? UITableViewHeaderFooterView else {
            tableDelegate?.tableView?(tableView, didEndDisplayingHeaderView: view, forSection: section)
            return
        }
        header.endDisplayHandler?(
            headerView,
            context(for: IndexPath(row: 0, section: section), identity: header.identity)
        )
        tableDelegate?.tableView?(tableView, didEndDisplayingHeaderView: view, forSection: section)
    }

    public func tableView(_ tableView: UITableView, didEndDisplayingFooterView view: UIView, forSection section: Int) {
        let displayed = displayedSupplementariesByView.removeValue(forKey: ObjectIdentifier(view))
        let footer = displayed?.role == .footer
            ? displayed?.supplementary
            : sections[safe: section]?.footer
        guard let footer, let footerView = view as? UITableViewHeaderFooterView else {
            tableDelegate?.tableView?(tableView, didEndDisplayingFooterView: view, forSection: section)
            return
        }
        footer.endDisplayHandler?(
            footerView,
            context(for: IndexPath(row: 0, section: section), identity: footer.identity)
        )
        tableDelegate?.tableView?(tableView, didEndDisplayingFooterView: view, forSection: section)
    }

    public func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        var contexts: [TableListContext] = []
        for indexPath in indexPaths {
            guard let row = row(at: indexPath) else { continue }
            prefetchedRowsByIndexPath[indexPath] = row
            let rowContext = context(for: indexPath, identity: row.identity)
            contexts.append(rowContext)
            row.prefetchHandler?(rowContext)
        }
        if !contexts.isEmpty { prefetchRowsHandler?(contexts) }
    }

    public func tableView(_ tableView: UITableView, cancelPrefetchingForRowsAt indexPaths: [IndexPath]) {
        var contexts: [TableListContext] = []
        for indexPath in indexPaths {
            guard let row = prefetchedRowsByIndexPath.removeValue(forKey: indexPath) ?? row(at: indexPath) else {
                continue
            }
            let rowContext = context(for: indexPath, identity: row.identity)
            contexts.append(rowContext)
            row.cancelPrefetchHandler?(rowContext)
        }
        if !contexts.isEmpty { cancelPrefetchingRowsHandler?(contexts) }
    }

    public func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let header = sections[safe: section]?.header else {
            return tableDelegate?.tableView?(tableView, viewForHeaderInSection: section)
        }
        return header.viewProvider(
            tableView,
            context(for: IndexPath(row: 0, section: section), identity: header.identity)
        )
    }

    public func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard let footer = sections[safe: section]?.footer else {
            return tableDelegate?.tableView?(tableView, viewForFooterInSection: section)
        }
        return footer.viewProvider(
            tableView,
            context(for: IndexPath(row: 0, section: section), identity: footer.identity)
        )
    }

    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard sections[safe: section]?.header == nil else { return nil }
        return sections[safe: section]?.headerTitle
            ?? tableDataSource?.tableView?(tableView, titleForHeaderInSection: section)
    }

    public func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard sections[safe: section]?.footer == nil else { return nil }
        return sections[safe: section]?.footerTitle
            ?? tableDataSource?.tableView?(tableView, titleForFooterInSection: section)
    }

    public func sectionIndexTitles(for tableView: UITableView) -> [String]? {
        let titles = sections.compactMap(\.indexTitle)
        return titles.isEmpty ? tableDataSource?.sectionIndexTitles?(for: tableView) : titles
    }

    public func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
        let titledSections = sections.indices.filter { sections[$0].indexTitle != nil }
        return titledSections[safe: index]
            ?? tableDataSource?.tableView?(tableView, sectionForSectionIndexTitle: title, at: index)
            ?? 0
    }

    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        row(at: indexPath)?.height?.resolvedHeight
            ?? tableDelegate?.tableView?(tableView, heightForRowAt: indexPath)
            ?? tableView.rowHeight
    }

    public func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        if let row = row(at: indexPath) {
            return row.estimatedHeight ?? row.height?.resolvedEstimatedHeight ?? tableView.estimatedRowHeight
        }
        return tableDelegate?.tableView?(tableView, estimatedHeightForRowAt: indexPath)
            ?? tableView.estimatedRowHeight
    }

    public func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        sections[safe: section]?.header?.height?.resolvedHeight
            ?? tableDelegate?.tableView?(tableView, heightForHeaderInSection: section)
            ?? tableView.sectionHeaderHeight
    }

    public func tableView(_ tableView: UITableView, estimatedHeightForHeaderInSection section: Int) -> CGFloat {
        sections[safe: section]?.header?.height?.resolvedEstimatedHeight
            ?? tableDelegate?.tableView?(tableView, estimatedHeightForHeaderInSection: section)
            ?? tableView.estimatedSectionHeaderHeight
    }

    public func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        sections[safe: section]?.footer?.height?.resolvedHeight
            ?? tableDelegate?.tableView?(tableView, heightForFooterInSection: section)
            ?? tableView.sectionFooterHeight
    }

    public func tableView(_ tableView: UITableView, estimatedHeightForFooterInSection section: Int) -> CGFloat {
        sections[safe: section]?.footer?.height?.resolvedEstimatedHeight
            ?? tableDelegate?.tableView?(tableView, estimatedHeightForFooterInSection: section)
            ?? tableView.estimatedSectionFooterHeight
    }

    public func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let row = row(at: indexPath) else { return nil }
        let configuration = row.contextMenuProvider?(context(for: indexPath, identity: row.identity))
            ?? tableDelegate?.tableView?(tableView, contextMenuConfigurationForRowAt: indexPath, point: point)
        if configuration != nil { activeContextMenu = (row, indexPath) }
        return configuration
    }

    public func tableView(
        _ tableView: UITableView,
        previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        guard let activeContextMenu else {
            return tableDelegate?.tableView?(
                tableView,
                previewForHighlightingContextMenuWithConfiguration: configuration
            )
        }
        return activeContextMenu.row.contextMenuHighlightPreviewProvider?(
            context(for: activeContextMenu.indexPath, identity: activeContextMenu.row.identity)
        ) ?? tableDelegate?.tableView?(
            tableView,
            previewForHighlightingContextMenuWithConfiguration: configuration
        )
    }

    public func tableView(
        _ tableView: UITableView,
        previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        guard let activeContextMenu else {
            return tableDelegate?.tableView?(
                tableView,
                previewForDismissingContextMenuWithConfiguration: configuration
            )
        }
        return activeContextMenu.row.contextMenuDismissalPreviewProvider?(
            context(for: activeContextMenu.indexPath, identity: activeContextMenu.row.identity)
        ) ?? tableDelegate?.tableView?(
            tableView,
            previewForDismissingContextMenuWithConfiguration: configuration
        )
    }

    public func tableView(
        _ tableView: UITableView,
        willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
        animator: any UIContextMenuInteractionCommitAnimating
    ) {
        if let activeContextMenu {
            activeContextMenu.row.contextMenuCommitHandler?(
                context(for: activeContextMenu.indexPath, identity: activeContextMenu.row.identity),
                animator
            )
        }
        tableDelegate?.tableView?(
            tableView,
            willPerformPreviewActionForMenuWith: configuration,
            animator: animator
        )
    }

    public func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        guard let row = row(at: indexPath) else { return false }
        return row.commitEditingHandler != nil
            || row.leadingSwipeActionsProvider != nil
            || row.trailingSwipeActionsProvider != nil
            || tableDataSource?.tableView?(tableView, canEditRowAt: indexPath) == true
    }

    public func tableView(
        _ tableView: UITableView,
        editingStyleForRowAt indexPath: IndexPath
    ) -> UITableViewCell.EditingStyle {
        row(at: indexPath)?.editingStyle
            ?? tableDelegate?.tableView?(tableView, editingStyleForRowAt: indexPath)
            ?? .none
    }

    public func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        guard let row = row(at: indexPath) else { return }
        row.commitEditingHandler?(editingStyle, context(for: indexPath, identity: row.identity))
        tableDataSource?.tableView?(tableView, commit: editingStyle, forRowAt: indexPath)
    }

    public func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        guard let row = row(at: indexPath) else { return false }
        return row.moveHandler != nil || tableDataSource?.tableView?(tableView, canMoveRowAt: indexPath) == true
    }

    public func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        guard let movedRow = row(at: sourceIndexPath) else { return }
        moveRowDescription(from: sourceIndexPath, to: destinationIndexPath)
        movedRow.moveHandler?(sourceIndexPath, destinationIndexPath)
        tableDataSource?.tableView?(tableView, moveRowAt: sourceIndexPath, to: destinationIndexPath)
    }

    public func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath
    ) -> IndexPath {
        row(at: sourceIndexPath)?.moveTargetProvider?(sourceIndexPath, proposedDestinationIndexPath)
            ?? tableDelegate?.tableView?(
                tableView,
                targetIndexPathForMoveFromRowAt: sourceIndexPath,
                toProposedIndexPath: proposedDestinationIndexPath
            )
            ?? proposedDestinationIndexPath
    }

    public func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        if let row = row(at: indexPath) {
            row.accessoryButtonHandler?(context(for: indexPath, identity: row.identity))
        }
        tableDelegate?.tableView?(tableView, accessoryButtonTappedForRowWith: indexPath)
    }

    public func tableView(_ tableView: UITableView, willBeginEditingRowAt indexPath: IndexPath) {
        if let row = row(at: indexPath) {
            row.editingChangeHandler?(true, context(for: indexPath, identity: row.identity))
        }
        tableDelegate?.tableView?(tableView, willBeginEditingRowAt: indexPath)
    }

    public func tableView(_ tableView: UITableView, didEndEditingRowAt indexPath: IndexPath?) {
        if let indexPath, let row = row(at: indexPath) {
            row.editingChangeHandler?(false, context(for: indexPath, identity: row.identity))
        }
        tableDelegate?.tableView?(tableView, didEndEditingRowAt: indexPath)
    }

    public func tableView(
        _ tableView: UITableView,
        leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let row = row(at: indexPath) else { return nil }
        return row.leadingSwipeActionsProvider?(context(for: indexPath, identity: row.identity))
            ?? tableDelegate?.tableView?(tableView, leadingSwipeActionsConfigurationForRowAt: indexPath)
    }

    public func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let row = row(at: indexPath) else { return nil }
        return row.trailingSwipeActionsProvider?(context(for: indexPath, identity: row.identity))
            ?? tableDelegate?.tableView?(tableView, trailingSwipeActionsConfigurationForRowAt: indexPath)
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        scrollDelegate?.scrollViewDidScroll?(scrollView)
        if !sameObject(scrollDelegate, tableDelegate) { tableDelegate?.scrollViewDidScroll?(scrollView) }
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        scrollDelegate?.scrollViewWillBeginDragging?(scrollView)
        if !sameObject(scrollDelegate, tableDelegate) { tableDelegate?.scrollViewWillBeginDragging?(scrollView) }
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        scrollDelegate?.scrollViewDidEndDragging?(scrollView, willDecelerate: decelerate)
        if !sameObject(scrollDelegate, tableDelegate) {
            tableDelegate?.scrollViewDidEndDragging?(scrollView, willDecelerate: decelerate)
        }
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        scrollDelegate?.scrollViewDidEndDecelerating?(scrollView)
        if !sameObject(scrollDelegate, tableDelegate) { tableDelegate?.scrollViewDidEndDecelerating?(scrollView) }
    }

    /// 返回指定 section index 当前对应的业务 section id。
    ///
    /// - Parameter sectionIndex: 当前 table section index。
    /// - Returns: 匹配的业务 section id；越界时返回 `nil`。
    public func sectionIdentifier(at sectionIndex: Int) -> SectionID? {
        sections[safe: sectionIndex]?.id
    }

    /// 返回指定业务 section 当前 row 数量。
    ///
    /// - Parameter sectionID: 业务 section id。
    /// - Returns: 当前 row 数量。
    public func rowCount(in sectionID: SectionID) -> Int {
        sections.first { $0.id == sectionID }?.rows.count ?? 0
    }

    /// 返回指定业务 section 当前 item 数量。
    ///
    /// - Parameter sectionID: 业务 section id。
    /// - Returns: 当前 item 数量。UITableView 中 item 等同于 row。
    public func itemCount(in sectionID: SectionID) -> Int {
        rowCount(in: sectionID)
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
            let rowIndex = sections[sectionIndex].rows.firstIndex(where: { $0.identity == identity })
        else { return nil }
        return IndexPath(row: rowIndex, section: sectionIndex)
    }

    /// 判断当前描述树是否仍包含指定展示身份。
    public func contains(_ identity: AnyListIdentity) -> Bool {
        indexPath(for: identity) != nil
    }

    /// 根据业务 row id 查询当前 indexPath。
    ///
    /// - Parameters:
    ///   - rowID: 业务 row id。
    ///   - sectionID: 可选 section 范围。
    /// - Returns: 当前匹配的 index path 列表。
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
            for (rowIndex, row) in section.rows.enumerated() where row.identity.rowID == targetRowID {
                indexPaths.append(IndexPath(row: rowIndex, section: sectionIndex))
            }
        }

        return indexPaths
    }

    /// 滚动到指定 section 或全 table 的最后一个 row。
    ///
    /// - Parameters:
    ///   - sectionID: 可选 section 范围；为 `nil` 时使用全 table。
    ///   - scrollPosition: UITableView 滚动位置。
    ///   - animated: 是否启用滚动动画。
    /// - Returns: 找到并触发滚动时返回 `true`。
    @discardableResult
    public func scrollToLastRow(
        in sectionID: SectionID? = nil,
        at scrollPosition: UITableView.ScrollPosition = .bottom,
        animated: Bool = true
    ) -> Bool {
        guard let tableView, let indexPath = lastRowIndexPath(in: sectionID) else {
            return false
        }
        tableView.scrollToRow(at: indexPath, at: scrollPosition, animated: animated)
        return true
    }

    /// 轻量重配当前可见 row。
    ///
    /// - Parameters:
    ///   - rowID: 业务 row id。
    ///   - sectionID: 可选 section 范围。
    /// - Returns: 被重配的可见 row 数量。
    @discardableResult
    public func reconfigureVisibleRows<RowID>(
        forRowID rowID: RowID,
        in sectionID: SectionID? = nil
    ) -> Int where RowID: Hashable & Sendable {
        guard let tableView else { return 0 }
        var reconfiguredCount = 0

        for indexPath in visibleIndexPaths(matching: rowID, in: sectionID) {
            guard let row = row(at: indexPath) else { continue }
            let context = context(for: indexPath, identity: row.identity)
            if let cell = tableView.cellForRow(at: indexPath) {
                row.configureVisibleCell(cell, context)
            } else if tableView.window == nil {
                let cell = row.cellProvider(tableView, indexPath, context)
                row.configureVisibleCell(cell, context)
            } else {
                continue
            }
            reconfiguredCount += 1
        }

        return reconfiguredCount
    }

    /// 通过 diffable snapshot reload 当前可见 row。
    ///
    /// - Parameters:
    ///   - rowID: 业务 row id。
    ///   - sectionID: 可选 section 范围。
    /// - Returns: 被 reload 的可见 row 数量。
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

    private func rebuildLookupTables() {
        rowsByIdentity = [:]

        guard let tableView else { return }
        for section in sections {
            section.header?.register(tableView)
            section.footer?.register(tableView)
            for row in section.rows {
                row.register(tableView)
                rowsByIdentity[row.identity] = row
            }
        }
    }

    private static func makeCoreSnapshots(from sections: [TableSection<SectionID>]) -> [ListSectionSnapshot] {
        sections.map { section in
            var supplementaries: [ListNodeSnapshot] = []
            if let header = section.header {
                supplementaries.append(
                    ListNodeSnapshot(
                        identity: header.identity,
                        refreshID: header.refreshID,
                        refreshPolicy: header.refreshPolicy,
                        role: .supplementary
                    )
                )
            }
            if let footer = section.footer {
                supplementaries.append(
                    ListNodeSnapshot(
                        identity: footer.identity,
                        refreshID: footer.refreshID,
                        refreshPolicy: footer.refreshPolicy,
                        role: .supplementary
                    )
                )
            }

            return ListSectionSnapshot(
                sectionID: AnyListID(section.id),
                rows: section.rows.map { row in
                    ListNodeSnapshot(
                        identity: row.identity,
                        refreshID: row.refreshID,
                        refreshPolicy: row.refreshPolicy,
                        role: .row
                    )
                },
                supplementaries: supplementaries
            )
        }
    }

    private func refreshVisibleRowsIfNeeded(
        applyPlan: ListApplyPlan,
        strategy: ListApplyRefreshStrategy,
        animatingContent: Bool,
        coordinator: ListAnimationCompletionCoordinator
    ) -> TableVisibleRefreshResult {
        guard let tableView else { return TableVisibleRefreshResult() }
        var refreshedCount = 0
        var transitionCount = 0
        var needsLayoutInvalidation = false
        for indexPath in tableView.indexPathsForVisibleRows ?? [] {
            guard
                let row = row(at: indexPath),
                let rowSnapshot = applyPlan.newRowsByIdentity[row.identity],
                let oldRowSnapshot = applyPlan.oldRowsByIdentity[row.identity],
                ListApplyPlanner.shouldRefreshVisibleRow(
                    rowSnapshot,
                    oldRow: oldRowSnapshot,
                    strategy: strategy
                ),
                let cell = tableView.cellForRow(at: indexPath)
            else { continue }

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
            if oldRowSnapshot.refreshID != rowSnapshot.refreshID,
               row.height?.isFixed != true {
                needsLayoutInvalidation = true
            }
            refreshedCount += 1
        }
        return TableVisibleRefreshResult(
            refreshedCount: refreshedCount,
            transitionCount: transitionCount,
            needsLayoutInvalidation: needsLayoutInvalidation
        )
    }

    private func performLayoutUpdate(
        invalidating shouldInvalidate: Bool,
        animated: Bool,
        coordinator: ListAnimationCompletionCoordinator
    ) -> Bool {
        guard shouldInvalidate, let tableView else { return false }
        if animated {
            coordinator.enter()
            tableView.performBatchUpdates(nil) { _ in
                coordinator.leave()
            }
            return true
        }
        UIView.performWithoutAnimation {
            tableView.beginUpdates()
            tableView.endUpdates()
            tableView.layoutIfNeeded()
        }
        return false
    }

    private func refreshVisibleSupplementariesIfNeeded(applyPlan: ListApplyPlan) -> Int {
        guard let tableView else { return 0 }
        var refreshedCount = 0

        for sectionIndex in sections.indices {
            refreshedCount += refreshVisibleSupplementary(
                sections[sectionIndex].header,
                view: tableView.headerView(forSection: sectionIndex),
                sectionIndex: sectionIndex,
                applyPlan: applyPlan
            )
            refreshedCount += refreshVisibleSupplementary(
                sections[sectionIndex].footer,
                view: tableView.footerView(forSection: sectionIndex),
                sectionIndex: sectionIndex,
                applyPlan: applyPlan
            )
        }

        return refreshedCount
    }

    private func refreshVisibleSupplementary(
        _ supplementary: AnyTableSectionSupplementary?,
        view: UITableViewHeaderFooterView?,
        sectionIndex: Int,
        applyPlan: ListApplyPlan
    ) -> Int {
        guard
            let supplementary,
            let view,
            let supplementarySnapshot = applyPlan.newSupplementariesByIdentity[supplementary.identity],
            let oldSupplementarySnapshot = applyPlan.oldSupplementariesByIdentity[supplementary.identity],
            ListApplyPlanner.shouldRefreshVisibleSupplementary(
                supplementarySnapshot,
                oldSupplementary: oldSupplementarySnapshot
            )
        else { return 0 }

        let context = context(
            for: IndexPath(row: 0, section: sectionIndex),
            identity: supplementary.identity
        )
        supplementary.configureVisibleView(view, context)
        return 1
    }

    private func configureSelectionBehavior() {
        guard let tableView else { return }
        let selectionSections = sections.compactMap { section -> (TableSection<SectionID>, ResolvedListSelectionMode)? in
            let mode = selectionMode(for: section)
            return mode == .none ? nil : (section, mode)
        }
        let allowsRowSelection = sections.contains(where: sectionAllowsUserSelection)
        let allowsHighlight = tableDelegateHasHighlightIntent
            || sections.contains { $0.rows.contains(where: \.hasAutomaticHighlightIntent) }
        tableView.allowsSelection = allowsRowSelection || allowsHighlight
        tableView.allowsMultipleSelection = selectionSections.contains { $0.1 == .multiple }
            || selectionSections.count > 1
    }

    private func captureSelectedItemIdentities() -> [AnyListIdentity] {
        guard let tableView else { return [] }
        return (tableView.indexPathsForSelectedRows ?? []).compactMap {
            dataSource.itemIdentifier(for: $0)
        }
    }

    private func restoreSelection(for identities: [AnyListIdentity]) {
        guard let tableView else { return }
        for identity in identities {
            guard
                rowsByIdentity[identity]?.isSelected == nil,
                let indexPath = dataSource.indexPath(for: identity)
            else { continue }
            tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
        }
    }

    private func synchronizeControlledSelection() {
        guard let tableView else { return }
        for section in sections {
            for row in section.rows {
                guard
                    let isSelected = row.isSelected,
                    let indexPath = dataSource.indexPath(for: row.identity)
                else { continue }
                if isSelected, selectionMode(at: indexPath) != .none {
                    tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
                } else {
                    tableView.deselectRow(at: indexPath, animated: false)
                }
            }
        }
    }

    private func reconcileSelection() {
        guard let tableView else { return }
        let selectedIndexPaths = (tableView.indexPathsForSelectedRows ?? []).sorted {
            if $0.section != $1.section { return $0.section < $1.section }
            let lhsIsControlled = row(at: $0)?.isSelected == true
            let rhsIsControlled = row(at: $1)?.isSelected == true
            if lhsIsControlled != rhsIsControlled { return lhsIsControlled }
            return $0.row < $1.row
        }
        var selectedSingleSections = Set<Int>()

        for indexPath in selectedIndexPaths {
            switch selectionMode(at: indexPath) {
            case .none:
                tableView.deselectRow(at: indexPath, animated: false)
            case .single:
                if !selectedSingleSections.insert(indexPath.section).inserted {
                    tableView.deselectRow(at: indexPath, animated: false)
                }
            case .multiple:
                break
            }
        }
    }

    private func deselectOtherRows(
        in section: Int,
        keeping selectedIndexPath: IndexPath,
        tableView: UITableView
    ) {
        let indexPaths = tableView.indexPathsForSelectedRows ?? []
        for indexPath in indexPaths where indexPath.section == section && indexPath != selectedIndexPath {
            tableView.deselectRow(at: indexPath, animated: false)
            self.tableView(tableView, didDeselectRowAt: indexPath)
        }
    }

    private func selectionMode(for section: TableSection<SectionID>) -> ResolvedListSelectionMode {
        section.selectionMode.resolved(
            automaticSelectionEnabled: tableDelegateHasSelectionIntent
                || section.rows.contains { $0.hasAutomaticSelectionIntent }
        )
    }

    private func selectionMode(at indexPath: IndexPath) -> ResolvedListSelectionMode {
        guard let section = sections[safe: indexPath.section] else { return .none }
        return section.selectionMode.resolved(
            automaticSelectionEnabled: tableDelegateHasSelectionIntent
                || row(at: indexPath)?.hasAutomaticSelectionIntent == true
        )
    }

    private func sectionAllowsUserSelection(_ section: TableSection<SectionID>) -> Bool {
        switch section.selectionMode {
        case .automatic:
            return section.rows.contains { row in
                !row.isSelectionDisabled
                    && (row.hasAutomaticSelectionIntent || tableDelegateHasSelectionIntent)
            }
        case .none:
            return false
        case .single, .multiple:
            return true
        }
    }

    private var tableDelegateHasSelectionIntent: Bool {
        tableDelegateResponds(to: #selector(UITableViewDelegate.tableView(_:willSelectRowAt:)))
            || tableDelegateResponds(to: #selector(UITableViewDelegate.tableView(_:didSelectRowAt:)))
            || tableDelegateResponds(to: #selector(UITableViewDelegate.tableView(_:willDeselectRowAt:)))
            || tableDelegateResponds(to: #selector(UITableViewDelegate.tableView(_:didDeselectRowAt:)))
    }

    private var tableDelegateHasHighlightIntent: Bool {
        tableDelegateResponds(to: #selector(UITableViewDelegate.tableView(_:shouldHighlightRowAt:)))
            || tableDelegateResponds(to: #selector(UITableViewDelegate.tableView(_:didHighlightRowAt:)))
            || tableDelegateResponds(to: #selector(UITableViewDelegate.tableView(_:didUnhighlightRowAt:)))
    }

    private func tableDelegateResponds(to selector: Selector) -> Bool {
        tableDelegate?.responds(to: selector) == true
    }

    private func moveRowDescription(from source: IndexPath, to destination: IndexPath) {
        guard
            sections.indices.contains(source.section),
            sections[source.section].rows.indices.contains(source.row),
            sections.indices.contains(destination.section)
        else { return }
        let movedRow = sections[source.section].rows.remove(at: source.row)
        let insertionIndex = min(destination.row, sections[destination.section].rows.count)
        sections[destination.section].rows.insert(movedRow, at: insertionIndex)
    }

    private func row(at indexPath: IndexPath) -> AnyTableRow? {
        sections[safe: indexPath.section]?.rows[safe: indexPath.row]
    }

    private func captureVisibleRowAnchor(for target: ListScrollTarget) -> TableVisibleRowAnchor? {
        guard let tableView else { return nil }
        tableView.layoutIfNeeded()
        let visibleIndexPaths = Set(tableView.indexPathsForVisibleRows ?? [])
        guard let indexPath = indexPaths(for: target).first(where: visibleIndexPaths.contains),
              let identity = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return TableVisibleRowAnchor(
            identity: identity,
            viewportMinY: tableView.rectForRow(at: indexPath).minY - tableView.contentOffset.y,
            horizontalContentOffset: tableView.contentOffset.x,
            baseBottomInset: temporaryAnchorBaseBottomInset
                ?? tableView.contentInset.bottom - preservedAnchorBottomInsetCompensation
        )
    }

    private func reserveScrollRange(for anchor: TableVisibleRowAnchor) {
        guard let tableView else { return }
        temporaryAnchorBaseBottomInset = anchor.baseBottomInset
        let systemBottomInset = tableView.adjustedContentInset.bottom - tableView.contentInset.bottom
        let bottomInsetKeepingCurrentOffset = tableView.contentOffset.y
            + tableView.bounds.height
            - systemBottomInset
        UIView.performWithoutAnimation {
            tableView.contentInset.bottom = max(
                tableView.contentInset.bottom,
                bottomInsetKeepingCurrentOffset,
                anchor.baseBottomInset
            )
        }
    }

    private func cancelTemporaryAnchorReservation() {
        guard let tableView, let baseBottomInset = temporaryAnchorBaseBottomInset else { return }
        UIView.performWithoutAnimation {
            tableView.contentInset.bottom = baseBottomInset + preservedAnchorBottomInsetCompensation
        }
        temporaryAnchorBaseBottomInset = nil
    }

    private func restoreVisibleRowAnchor(_ anchor: TableVisibleRowAnchor) -> CGFloat {
        guard let tableView else { return 0 }
        tableView.layoutIfNeeded()
        let snapshot = dataSource.snapshot()
        guard let indexPath = Self.indexPath(for: anchor.identity, in: snapshot) else {
            preservedAnchorBottomInsetCompensation = 0
            temporaryAnchorBaseBottomInset = nil
            UIView.performWithoutAnimation {
                tableView.contentInset.bottom = anchor.baseBottomInset
            }
            return 0
        }

        let minimumOffsetY = -tableView.adjustedContentInset.top
        let desiredOffsetY = max(
            minimumOffsetY,
            tableView.rectForRow(at: indexPath).minY - anchor.viewportMinY
        )
        let systemBottomInset = tableView.adjustedContentInset.bottom - tableView.contentInset.bottom
        let maximumOffsetWithoutCompensation = max(
            minimumOffsetY,
            tableView.contentSize.height
                - tableView.bounds.height
                + systemBottomInset
                + anchor.baseBottomInset
        )
        let compensation = max(0, desiredOffsetY - maximumOffsetWithoutCompensation)

        preservedAnchorBottomInsetCompensation = compensation
        temporaryAnchorBaseBottomInset = nil
        UIView.performWithoutAnimation {
            tableView.contentInset.bottom = anchor.baseBottomInset + compensation
            tableView.layoutIfNeeded()
            tableView.setContentOffset(
                CGPoint(x: anchor.horizontalContentOffset, y: desiredOffsetY),
                animated: false
            )
        }
        return compensation
    }

    private func normalizeAnchorCompensation() -> CGFloat {
        guard let tableView else { return 0 }
        guard temporaryAnchorBaseBottomInset != nil || preservedAnchorBottomInsetCompensation > 0 else {
            return 0
        }
        cancelTemporaryAnchorReservation()
        let baseBottomInset = tableView.contentInset.bottom - preservedAnchorBottomInsetCompensation
        let systemBottomInset = tableView.adjustedContentInset.bottom - tableView.contentInset.bottom
        let minimumOffsetY = -tableView.adjustedContentInset.top
        let maximumOffsetWithoutCompensation = max(
            minimumOffsetY,
            tableView.contentSize.height
                - tableView.bounds.height
                + systemBottomInset
                + baseBottomInset
        )
        let compensation = max(0, tableView.contentOffset.y - maximumOffsetWithoutCompensation)
        preservedAnchorBottomInsetCompensation = compensation
        UIView.performWithoutAnimation {
            tableView.contentInset.bottom = baseBottomInset + compensation
        }
        return compensation
    }

    private func performScrollBehavior(
        _ behavior: ListScrollBehavior,
        visibleAnchor: TableVisibleRowAnchor?,
        animated: Bool
    ) -> TableScrollOutcome {
        guard let tableView else { return TableScrollOutcome() }
        tableView.layoutIfNeeded()

        switch behavior.storage {
        case .none:
            return TableScrollOutcome(anchorCompensation: normalizeAnchorCompensation())
        case .preserveVisiblePosition:
            guard let visibleAnchor else {
                return TableScrollOutcome(anchorCompensation: normalizeAnchorCompensation())
            }
            return TableScrollOutcome(anchorCompensation: restoreVisibleRowAnchor(visibleAnchor))
        case .scrollTo(let target, let position):
            let compensation = normalizeAnchorCompensation()
            guard let indexPath = indexPaths(for: target).first else {
                return TableScrollOutcome(anchorCompensation: compensation)
            }
            tableView.scrollToRow(at: indexPath, at: position.tableViewPosition, animated: animated)
            return TableScrollOutcome(animated: animated, anchorCompensation: compensation)
        case .scrollToLast(let sectionID, let position):
            let compensation = normalizeAnchorCompensation()
            guard let indexPath = lastRowIndexPath(inAnySectionID: sectionID) else {
                return TableScrollOutcome(anchorCompensation: compensation)
            }
            tableView.scrollToRow(at: indexPath, at: position.tableViewPosition, animated: animated)
            return TableScrollOutcome(animated: animated, anchorCompensation: compensation)
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

    private func lastRowIndexPath(in sectionID: SectionID?) -> IndexPath? {
        if let sectionID {
            guard
                let sectionIndex = sections.firstIndex(where: { $0.id == sectionID }),
                let rowIndex = sections[sectionIndex].rows.indices.last
            else { return nil }
            return IndexPath(row: rowIndex, section: sectionIndex)
        }

        for sectionIndex in sections.indices.reversed() {
            guard let rowIndex = sections[sectionIndex].rows.indices.last else { continue }
            return IndexPath(row: rowIndex, section: sectionIndex)
        }
        return nil
    }

    private func lastRowIndexPath(inAnySectionID sectionID: AnyListID?) -> IndexPath? {
        let snapshot = dataSource.snapshot()
        if let sectionID {
            guard let section = snapshot.indexOfSection(sectionID),
                  let item = snapshot.itemIdentifiers(inSection: sectionID).indices.last
            else { return nil }
            return IndexPath(row: item, section: section)
        }
        guard let identity = snapshot.itemIdentifiers.last else { return nil }
        return Self.indexPath(for: identity, in: snapshot)
    }

    private static func indexPath(
        for identity: AnyListIdentity,
        in snapshot: NSDiffableDataSourceSnapshot<AnyListID, AnyListIdentity>
    ) -> IndexPath? {
        guard let sectionID = snapshot.sectionIdentifier(containingItem: identity),
              let section = snapshot.indexOfSection(sectionID),
              let row = snapshot.itemIdentifiers(inSection: sectionID).firstIndex(of: identity)
        else { return nil }
        return IndexPath(row: row, section: section)
    }

    private func visibleIndexPaths<RowID>(
        matching rowID: RowID,
        in sectionID: SectionID?
    ) -> [IndexPath] where RowID: Hashable & Sendable {
        let targetIndexPaths = Set(indexPaths(forRowID: rowID, in: sectionID))
        guard let tableView else { return [] }
        let visibleRows = tableView.indexPathsForVisibleRows ?? []
        let candidates = visibleRows.isEmpty && tableView.window == nil
            ? Array(targetIndexPaths)
            : visibleRows

        return candidates
            .filter { targetIndexPaths.contains($0) }
            .sorted { lhs, rhs in
                lhs.section == rhs.section ? lhs.row < rhs.row : lhs.section < rhs.section
            }
    }

    private func context(for indexPath: IndexPath, identity: AnyListIdentity) -> TableListContext {
        guard let tableView else {
            fatalError("TableListAdapter tableView was released")
        }
        return TableListContext(identity: identity, indexPath: indexPath, tableView: tableView) { [weak self] event, context in
            self?.dispatch(event, context: context)
        }
    }

    private func dispatch(_ event: any ListEvent, context: TableListContext) {
        eventRouter.dispatch(event, context: context)
    }

    private func sameObject(_ lhs: AnyObject?, _ rhs: AnyObject?) -> Bool {
        guard let lhs, let rhs else { return false }
        return lhs === rhs
    }
}

private struct TableVisibleRowAnchor {
    let identity: AnyListIdentity
    let viewportMinY: CGFloat
    let horizontalContentOffset: CGFloat
    let baseBottomInset: CGFloat
}

private struct TableVisibleRefreshResult {
    var refreshedCount = 0
    var transitionCount = 0
    var needsLayoutInvalidation = false
}

private enum TableSupplementaryRole {
    case header
    case footer
}

private struct TableDisplayedSupplementary {
    let role: TableSupplementaryRole
    let supplementary: AnyTableSectionSupplementary
}

private struct TableScrollOutcome {
    var animated = false
    var anchorCompensation: CGFloat = 0
}

@MainActor
private final class TableApplyAnimationMetrics {
    var visibleRefreshCount = 0
    var visibleSupplementaryRefreshCount = 0
    var contentTransitionCount = 0
    var layoutInvalidated = false
    var layoutAnimated = false
}

private extension ListScrollPosition {
    var tableViewPosition: UITableView.ScrollPosition {
        switch self {
        case .top: .top
        case .center: .middle
        case .bottom: .bottom
        case .nearest: .none
        }
    }
}

private final class TableDiffableDataSource<SectionID>: UITableViewDiffableDataSource<AnyListID, AnyListIdentity>
where SectionID: Hashable & Sendable {
    weak var adapter: TableListAdapter<SectionID>?

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        adapter?.tableView(tableView, titleForHeaderInSection: section)
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        adapter?.tableView(tableView, titleForFooterInSection: section)
    }

    override func sectionIndexTitles(for tableView: UITableView) -> [String]? {
        adapter?.sectionIndexTitles(for: tableView)
    }

    override func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
        adapter?.tableView(tableView, sectionForSectionIndexTitle: title, at: index) ?? 0
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        adapter?.tableView(tableView, canEditRowAt: indexPath) ?? false
    }

    override func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        adapter?.tableView(tableView, commit: editingStyle, forRowAt: indexPath)
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        adapter?.tableView(tableView, canMoveRowAt: indexPath) ?? false
    }

    override func tableView(
        _ tableView: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath
    ) {
        adapter?.tableView(tableView, moveRowAt: sourceIndexPath, to: destinationIndexPath)
    }
}

private final class TableUnsafeForwardingTarget: @unchecked Sendable {
    let value: AnyObject?

    init(_ value: AnyObject?) {
        self.value = value
    }
}

private final class TableMainActorCallbackBox: @unchecked Sendable {
    private let callback: () -> Void

    init(_ callback: @escaping () -> Void) {
        self.callback = callback
    }

    nonisolated func schedule() {
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated {
                callback()
            }
        }
    }
}

/// 一次 table `apply` 调用的返回值。
@MainActor
public struct TableApplyResult<SectionID> where SectionID: Hashable & Sendable {
    fileprivate weak var adapter: TableListAdapter<SectionID>?
    /// 本次 apply 的统计摘要。
    public let summary: ListApplySummary

    /// 在本次 apply 关联的 adapter 上绑定业务事件。
    ///
    /// - Parameters:
    ///   - eventType: 事件类型。
    ///   - handler: 事件处理闭包。
    /// - Returns: 当前结果，便于链式调用。
    @discardableResult
    public func onEvent<Event>(
        _ eventType: Event.Type = Event.self,
        handler: @escaping @MainActor (Event, TableListContext) -> Void
    ) -> Self where Event: ListEvent {
        adapter?.onEvent(eventType, handler: handler)
        return self
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
