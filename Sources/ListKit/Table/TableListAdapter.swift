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

    /// 最近一次 `apply` 的摘要。
    public private(set) var lastApplySummary = ListApplySummary()

    private weak var tableView: UITableView?
    private var sections: [TableSection<SectionID>] = []
    private var dataSource: TableDiffableDataSource<SectionID>!
    private var rowsByIdentity: [AnyListIdentity: AnyTableRow] = [:]
    private var displayedRowsByCell: [ObjectIdentifier: AnyTableRow] = [:]
    private var displayedSupplementariesByView: [ObjectIdentifier: AnyTableSectionSupplementary] = [:]
    private var prefetchedRowsByIndexPath: [IndexPath: AnyTableRow] = [:]
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
            return row.cellProvider(tableView, indexPath, self.context(for: indexPath, sectionID: identity.sectionID))
        }
        dataSource.adapter = self

        tableView.dataSource = dataSource
        tableView.delegate = self
        tableView.prefetchDataSource = self
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
            completion?()
            return TableApplyResult(adapter: self, summary: summary)
        }

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

        dataSource.apply(snapshot, animatingDifferences: options.animatingDifferences) { [weak self] in
            guard let self else { return }
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
            completion?()
        }

        return TableApplyResult(adapter: self, summary: summary)
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

    public func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[safe: section]?.rows.count ?? 0
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let row = row(at: indexPath) else { return UITableViewCell() }
        return row.cellProvider(tableView, indexPath, context(for: indexPath, sectionID: row.identity.sectionID))
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let row = row(at: indexPath) else { return }
        if selectionMode(at: indexPath) == .single {
            deselectOtherRows(in: indexPath.section, keeping: indexPath, tableView: tableView)
        }
        let context = context(for: indexPath, sectionID: row.identity.sectionID)
        row.selectHandler?(context)
        row.selectionChangeHandler?(true, context)
        tableDelegate?.tableView?(tableView, didSelectRowAt: indexPath)
    }

    public func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        guard let row = row(at: indexPath) else { return }
        let context = context(for: indexPath, sectionID: row.identity.sectionID)
        row.deselectHandler?(context)
        row.selectionChangeHandler?(false, context)
        tableDelegate?.tableView?(tableView, didDeselectRowAt: indexPath)
    }

    public func tableView(_ tableView: UITableView, shouldSelectRowAt indexPath: IndexPath) -> IndexPath? {
        selectionMode(at: indexPath) == .none ? nil : indexPath
    }

    public func tableView(_ tableView: UITableView, shouldDeselectRowAt indexPath: IndexPath) -> IndexPath? {
        selectionMode(at: indexPath) == .none ? nil : indexPath
    }

    public func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let row = row(at: indexPath) {
            displayedRowsByCell[ObjectIdentifier(cell)] = row
            row.displayHandler?(cell, context(for: indexPath, sectionID: row.identity.sectionID))
        }
        tableDelegate?.tableView?(tableView, willDisplay: cell, forRowAt: indexPath)
    }

    public func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let row = displayedRowsByCell.removeValue(forKey: ObjectIdentifier(cell)) ?? row(at: indexPath)
        if let row {
            row.endDisplayHandler?(cell, context(for: indexPath, sectionID: row.identity.sectionID))
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
            context(for: IndexPath(row: 0, section: section), sectionID: header.identity.sectionID)
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
            context(for: IndexPath(row: 0, section: section), sectionID: footer.identity.sectionID)
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
            context(for: IndexPath(row: 0, section: section), sectionID: header.identity.sectionID)
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
            context(for: IndexPath(row: 0, section: section), sectionID: footer.identity.sectionID)
        )
        tableDelegate?.tableView?(tableView, didEndDisplayingFooterView: view, forSection: section)
    }

    public func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            guard let row = row(at: indexPath) else { continue }
            prefetchedRowsByIndexPath[indexPath] = row
            row.prefetchHandler?(context(for: indexPath, sectionID: row.identity.sectionID))
        }
    }

    public func tableView(_ tableView: UITableView, cancelPrefetchingForRowsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            guard let row = prefetchedRowsByIndexPath.removeValue(forKey: indexPath) ?? row(at: indexPath) else {
                continue
            }
            row.cancelPrefetchHandler?(context(for: indexPath, sectionID: row.identity.sectionID))
        }
    }

    public func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let header = sections[safe: section]?.header else {
            return tableDelegate?.tableView?(tableView, viewForHeaderInSection: section)
        }
        return header.viewProvider(
            tableView,
            context(for: IndexPath(row: 0, section: section), sectionID: header.identity.sectionID)
        )
    }

    public func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard let footer = sections[safe: section]?.footer else {
            return tableDelegate?.tableView?(tableView, viewForFooterInSection: section)
        }
        return footer.viewProvider(
            tableView,
            context(for: IndexPath(row: 0, section: section), sectionID: footer.identity.sectionID)
        )
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
        return row.contextMenuProvider?(context(for: indexPath, sectionID: row.identity.sectionID))
            ?? tableDelegate?.tableView?(tableView, contextMenuConfigurationForRowAt: indexPath, point: point)
    }

    public func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        guard let row = row(at: indexPath) else { return false }
        return row.commitEditingHandler != nil
            || row.leadingSwipeActionsProvider != nil
            || row.trailingSwipeActionsProvider != nil
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
        row.commitEditingHandler?(editingStyle, context(for: indexPath, sectionID: row.identity.sectionID))
    }

    public func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        guard let row = row(at: indexPath) else { return false }
        return row.moveHandler != nil
    }

    public func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        row(at: sourceIndexPath)?.moveHandler?(sourceIndexPath, destinationIndexPath)
    }

    public func tableView(
        _ tableView: UITableView,
        leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let row = row(at: indexPath) else { return nil }
        return row.leadingSwipeActionsProvider?(context(for: indexPath, sectionID: row.identity.sectionID))
            ?? tableDelegate?.tableView?(tableView, leadingSwipeActionsConfigurationForRowAt: indexPath)
    }

    public func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let row = row(at: indexPath) else { return nil }
        return row.trailingSwipeActionsProvider?(context(for: indexPath, sectionID: row.identity.sectionID))
            ?? tableDelegate?.tableView?(tableView, trailingSwipeActionsConfigurationForRowAt: indexPath)
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        scrollDelegate?.scrollViewDidScroll?(scrollView)
        tableDelegate?.scrollViewDidScroll?(scrollView)
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        scrollDelegate?.scrollViewWillBeginDragging?(scrollView)
        tableDelegate?.scrollViewWillBeginDragging?(scrollView)
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        scrollDelegate?.scrollViewDidEndDragging?(scrollView, willDecelerate: decelerate)
        tableDelegate?.scrollViewDidEndDragging?(scrollView, willDecelerate: decelerate)
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        scrollDelegate?.scrollViewDidEndDecelerating?(scrollView)
        tableDelegate?.scrollViewDidEndDecelerating?(scrollView)
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
            let context = context(for: indexPath, sectionID: row.identity.sectionID)
            if let cell = tableView.cellForRow(at: indexPath) {
                row.configureVisibleCell(cell, context)
                row.displayHandler?(cell, context)
            } else if tableView.window == nil {
                let cell = row.cellProvider(tableView, indexPath, context)
                row.configureVisibleCell(cell, context)
                row.displayHandler?(cell, context)
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

            row.configureVisibleCell(cell, context(for: indexPath, sectionID: row.identity.sectionID))
            row.displayHandler?(cell, context(for: indexPath, sectionID: row.identity.sectionID))
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
            sectionID: supplementary.identity.sectionID
        )
        supplementary.configureVisibleView(view, context)
        supplementary.displayHandler?(view, context)
        return 1
    }

    private func configureSelectionBehavior() {
        guard let tableView else { return }
        let selectableSections = sections.filter { $0.selectionMode != .none }
        tableView.allowsSelection = !selectableSections.isEmpty
        tableView.allowsMultipleSelection = selectableSections.contains { $0.selectionMode == .multiple }
            || selectableSections.count > 1
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

    private func context(for indexPath: IndexPath, sectionID: AnyListID) -> TableListContext {
        guard let tableView else {
            fatalError("TableListAdapter tableView was released")
        }
        return TableListContext(sectionID: sectionID, indexPath: indexPath, tableView: tableView) { [weak self] event, context in
            self?.dispatch(event, context: context)
        }
    }

    private func dispatch(_ event: any ListEvent, context: TableListContext) {
        eventRouter.dispatch(event, context: context)
    }
}

private final class TableDiffableDataSource<SectionID>: UITableViewDiffableDataSource<AnyListID, AnyListIdentity>
where SectionID: Hashable & Sendable {
    weak var adapter: TableListAdapter<SectionID>?

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
