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

    /// table delegate 转发对象。
    public weak var tableDelegate: UITableViewDelegate?

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
    private var displayedSupplementariesByView: [ObjectIdentifier: AnyTableSectionSupplementary] = [:]
    private var prefetchedRowsByIndexPath: [IndexPath: AnyTableRow] = [:]
    private var applyGeneration = 0
    private var prefetchRowsHandler: (@MainActor ([TableListContext]) -> Void)?
    private var cancelPrefetchingRowsHandler: (@MainActor ([TableListContext]) -> Void)?
    private var activeContextMenu: (row: AnyTableRow, indexPath: IndexPath)?
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

    /// 重建 table 描述树并应用到 diffable data source。
    ///
    /// - Parameters:
    ///   - animatingDifferences: 是否启用 diffable 动画。
    ///   - content: section builder。
    /// - Returns: 本次 apply 的摘要和事件绑定入口。
    @discardableResult
    public func apply(
        animatingDifferences: Bool = true,
        @TableSectionBuilder<SectionID> _ content: () -> [TableSection<SectionID>]
    ) -> TableApplyResult<SectionID> {
        apply(animatingDifferences: animatingDifferences, completion: nil, content)
    }

    /// 重建 table 描述树并在 diffable apply 完成后执行回调。
    ///
    /// - Parameters:
    ///   - animatingDifferences: 是否启用 diffable 动画。
    ///   - completion: diffable apply 完成后的回调。
    ///   - content: section builder。
    /// - Returns: 本次 apply 的摘要和事件绑定入口。
    @discardableResult
    public func apply(
        animatingDifferences: Bool = true,
        completion: (() -> Void)?,
        @TableSectionBuilder<SectionID> _ content: () -> [TableSection<SectionID>]
    ) -> TableApplyResult<SectionID> {
        apply(
            options: ListApplyOptions(animatingDifferences: animatingDifferences),
            completion: completion,
            content
        )
    }

    /// 应用已经构建好的 table section 数组。
    ///
    /// - Parameters:
    ///   - sections: section 数组。
    ///   - animatingDifferences: 是否启用 diffable 动画。
    ///   - completion: diffable apply 完成后的回调。
    /// - Returns: 本次 apply 的摘要和事件绑定入口。
    @discardableResult
    public func apply(
        _ sections: [TableSection<SectionID>],
        animatingDifferences: Bool = true,
        completion: (() -> Void)? = nil
    ) -> TableApplyResult<SectionID> {
        apply(animatingDifferences: animatingDifferences, completion: completion) {
            sections
        }
    }

    /// 使用 apply 级刷新策略重建 table 描述树。
    ///
    /// - Parameters:
    ///   - refreshStrategy: 本次 apply 的刷新策略。
    ///   - animatingDifferences: 是否启用 diffable 动画。
    ///   - content: section builder。
    /// - Returns: 本次 apply 的摘要和事件绑定入口。
    @discardableResult
    public func apply(
        refresh refreshStrategy: ListApplyRefreshStrategy,
        animatingDifferences: Bool = true,
        @TableSectionBuilder<SectionID> _ content: () -> [TableSection<SectionID>]
    ) -> TableApplyResult<SectionID> {
        apply(
            options: ListApplyOptions(
                animatingDifferences: animatingDifferences,
                refreshStrategy: refreshStrategy
            ),
            completion: nil,
            content
        )
    }

    /// 使用完整 options 重建 table 描述树。
    ///
    /// - Parameters:
    ///   - options: apply 行为、刷新和 diagnostics 配置。
    ///   - content: section builder。
    /// - Returns: 本次 apply 的摘要和事件绑定入口。
    @discardableResult
    public func apply(
        options: ListApplyOptions,
        @TableSectionBuilder<SectionID> _ content: () -> [TableSection<SectionID>]
    ) -> TableApplyResult<SectionID> {
        apply(options: options, completion: nil, content)
    }

    /// 使用完整 options 重建 table 描述树，并在 diffable apply 完成后执行回调。
    ///
    /// - Parameters:
    ///   - options: apply 行为、刷新和 diagnostics 配置。
    ///   - completion: diffable apply 完成后的回调。
    ///   - content: section builder。
    /// - Returns: 本次 apply 的摘要和事件绑定入口。
    @discardableResult
    public func apply(
        options: ListApplyOptions,
        completion: (() -> Void)?,
        @TableSectionBuilder<SectionID> _ content: () -> [TableSection<SectionID>]
    ) -> TableApplyResult<SectionID> {
        _apply(options: options, completion: { _ in completion?() }, content)
    }

    private func _apply(
        options: ListApplyOptions,
        completion: ((ListApplySummary) -> Void)?,
        @TableSectionBuilder<SectionID> _ content: () -> [TableSection<SectionID>]
    ) -> TableApplyResult<SectionID> {
        let newSections = content()
        let applyPlan = ListApplyPlanner.makePlan(
            old: Self.makeCoreSnapshots(from: sections),
            new: Self.makeCoreSnapshots(from: newSections),
            options: options,
            diagnosticsIssues: ListDiagnostics.validate(Self.makeCoreSnapshots(from: newSections))
        )
        let diagnosticsIssues = applyPlan.initialSummary.diagnosticsIssues

        if !applyPlan.shouldApplyDiffable {
            let summary = applyPlan.initialSummary
            lastApplySummary = summary
            ListApplyLogger.logDiagnostics(issues: diagnosticsIssues, options: options)
            ListApplyLogger.logApplySummary(summary, options: options, prefix: "ListKit table apply summary")
            completion?(summary)
            return TableApplyResult(adapter: self, summary: summary)
        }

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

        let summary = applyPlan.initialSummary
        lastApplySummary = summary
        ListApplyLogger.logDiagnostics(issues: diagnosticsIssues, options: options)

        // Normalize UIKit's diffable completion onto a fresh main-actor turn.
        let didApplyBox = TableMainActorCallbackBox { [weak self] in
            guard let self else { return }
            guard self.applyGeneration == generation else {
                completion?(summary)
                return
            }
            self.reconcileSelection()
            let visibleRefreshCount = applyPlan.shouldRunVisibleRefresh
                ? self.refreshVisibleRowsIfNeeded(applyPlan: applyPlan)
                : 0
            let visibleSupplementaryRefreshCount = applyPlan.shouldRunVisibleRefresh
                ? self.refreshVisibleSupplementariesIfNeeded(applyPlan: applyPlan)
                : 0
            let completedSummary = applyPlan.completedSummary(
                visibleRefreshCount: visibleRefreshCount,
                visibleSupplementaryRefreshCount: visibleSupplementaryRefreshCount
            )
            self.lastApplySummary = completedSummary
            ListApplyLogger.logApplySummary(completedSummary, options: options, prefix: "ListKit table apply summary")
            completion?(completedSummary)
        }
        let didApply = { didApplyBox.schedule() }

        switch options.applicationMode {
        case .differences:
            dataSource.apply(
                snapshot,
                animatingDifferences: options.animatingDifferences,
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

    /// 重建描述树并等待 UIKit 完成 snapshot、selection 和可见刷新。
    @discardableResult
    public func apply(
        options: ListApplyOptions = ListApplyOptions(),
        @TableSectionBuilder<SectionID> _ content: () -> [TableSection<SectionID>]
    ) async -> TableApplyResult<SectionID> {
        let builtSections = content()
        return await withCheckedContinuation { continuation in
            _ = _apply(options: options, completion: { [weak self] summary in
                continuation.resume(returning: TableApplyResult(adapter: self, summary: summary))
            }) {
                builtSections
            }
        }
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
        guard row(at: indexPath)?.isSelectionDisabled != true else { return false }
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
        guard sections[safe: indexPath.section]?.allowsMultipleSelectionInteraction == true else { return false }
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
        displayedSupplementariesByView[ObjectIdentifier(view)] = header
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
        displayedSupplementariesByView[ObjectIdentifier(view)] = footer
        footer.displayHandler?(
            footerView,
            context(for: IndexPath(row: 0, section: section), identity: footer.identity)
        )
        tableDelegate?.tableView?(tableView, willDisplayFooterView: view, forSection: section)
    }

    public func tableView(_ tableView: UITableView, didEndDisplayingHeaderView view: UIView, forSection section: Int) {
        let header = displayedSupplementariesByView.removeValue(forKey: ObjectIdentifier(view))
            ?? sections[safe: section]?.header
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
        let footer = displayedSupplementariesByView.removeValue(forKey: ObjectIdentifier(view))
            ?? sections[safe: section]?.footer
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

    private func refreshVisibleRowsIfNeeded(applyPlan: ListApplyPlan) -> Int {
        guard let tableView else { return 0 }
        var refreshedCount = 0
        for indexPath in tableView.indexPathsForVisibleRows ?? [] {
            guard
                let row = row(at: indexPath),
                let rowSnapshot = applyPlan.newRowsByIdentity[row.identity],
                applyPlan.oldRowsByIdentity[row.identity] != nil,
                ListApplyPlanner.shouldRefreshVisibleRow(rowSnapshot),
                let cell = tableView.cellForRow(at: indexPath)
            else { continue }

            row.configureVisibleCell(cell, context(for: indexPath, identity: row.identity))
            refreshedCount += 1
        }
        return refreshedCount
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
        let selectableSections = sections.filter { $0.selectionMode != .none }
        tableView.allowsSelection = !selectableSections.isEmpty
        tableView.allowsMultipleSelection = selectableSections.contains { $0.selectionMode == .multiple }
            || selectableSections.count > 1
            || selectableSections.contains { $0.allowsMultipleSelectionInteraction }
    }

    private func reconcileSelection() {
        guard let tableView else { return }
        let selectedIndexPaths = (tableView.indexPathsForSelectedRows ?? []).sorted {
            $0.section == $1.section ? $0.row < $1.row : $0.section < $1.section
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

    private func selectionMode(at indexPath: IndexPath) -> ListSelectionMode {
        sections[safe: indexPath.section]?.selectionMode ?? .none
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
