import UIKit

// MARK: - Adapter

/// UICollectionView 列表适配器。
///
/// - Usage:
/// ```swift
/// private lazy var adapter = CollectionListAdapter<Section>(collectionView: collectionView)
///
/// adapter.apply(animatingDifferences: false) {
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

    private weak var collectionView: UICollectionView?
    private var sections: [ListSection<SectionID>] = []
    private var layoutSignature: [ListSectionLayoutSignature] = []
    private var dataSource: UICollectionViewDiffableDataSource<AnyListID, AnyListIdentity>!
    var isApplyingSnapshot = false
    private var rowsByIdentity: [AnyListIdentity: AnyListRow] = [:]
    private var supplementariesByKindAndSection: [SupplementaryKey: AnySupplementary] = [:]
    private var displayedRowsByCell: [ObjectIdentifier: AnyListRow] = [:]
    private var displayedSupplementariesByView: [ObjectIdentifier: AnySupplementary] = [:]
    private var prefetchedRowsByIndexPath: [IndexPath: AnyListRow] = [:]
    private let eventRouter = ListEventRouter<ListContext>()

    /// 创建 adapter 并接管 collection view 的 data source、delegate 和 prefetch data source。
    ///
    /// - Parameter collectionView: 由 adapter 管理 diffable data source、delegate 和预取回调的 collection view。
    public init(collectionView: UICollectionView) {
        self.collectionView = collectionView
        super.init()

        dataSource = UICollectionViewDiffableDataSource<AnyListID, AnyListIdentity>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, identity in
            guard let self, let row = self.rowsByIdentity[identity] else {
                return UICollectionViewCell()
            }
            return row.cellProvider(collectionView, indexPath, self.context(for: indexPath, sectionID: identity.sectionID))
        }

        dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            guard let self else { return nil }
            let sectionID = self.sectionID(at: indexPath.section)
            let key = SupplementaryKey(kind: kind, sectionID: sectionID)
            guard let supplementary = self.supplementariesByKindAndSection[key] else { return nil }
            return supplementary.viewProvider(collectionView, indexPath, self.context(for: indexPath, sectionID: sectionID))
        }

        collectionView.dataSource = dataSource
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
    }

    /// 重建列表描述树并应用到 diffable data source。
    ///
    /// - Important: identity 变化由 diffable 处理插入/删除；identity 不变时按 Row refresh policy 决定是否重配。
    /// - Parameters:
    ///   - animatingDifferences: 是否使用 diffable 动画应用 snapshot。
    ///   - content: 生成当前 section 描述树的 builder。
    /// - Returns: 本次 apply 的摘要和事件绑定入口。
    @discardableResult
    public func apply(
        animatingDifferences: Bool = true,
        @ListSectionBuilder<SectionID> _ content: () -> [ListSection<SectionID>]
    ) -> ListApplyResult<SectionID> {
        apply(animatingDifferences: animatingDifferences, completion: nil, content)
    }

    /// 重建列表描述树并在 diffable apply 完成后执行回调。
    ///
    /// - Usage:
    /// ```swift
    /// adapter.apply(animatingDifferences: false, completion: { [weak adapter] in
    ///     adapter?.scrollToLastItem(in: .messages, animated: true)
    /// }) {
    ///     ListSection(.messages) {
    ///         ForEach(messages, id: \.messageID) { message in
    ///             Row(model: message, cell: MessageCell.self) { cell, message, _ in
    ///                 cell.configure(message)
    ///             }
    ///         }
    ///     }
    /// }
    /// ```
    /// - Parameters:
    ///   - animatingDifferences: 是否使用 diffable 动画应用 snapshot。
    ///   - completion: diffable apply 完成后的回调，常用于滚动到最新消息。
    ///   - content: 生成当前 section 描述树的 builder。
    /// - Returns: 本次 apply 的摘要和事件绑定入口。
    @discardableResult
    public func apply(
        animatingDifferences: Bool = true,
        completion: (() -> Void)?,
        @ListSectionBuilder<SectionID> _ content: () -> [ListSection<SectionID>]
    ) -> ListApplyResult<SectionID> {
        apply(
            options: ListApplyOptions(animatingDifferences: animatingDifferences),
            completion: completion,
            content
        )
    }

    /// 应用已经构建好的 section 数组。
    ///
    /// - Parameters:
    ///   - sections: 原生 `ListSection` 数组。
    ///   - animatingDifferences: 是否使用 diffable 动画应用 snapshot。
    ///   - completion: diffable apply 完成后的回调。
    /// - Returns: 本次 apply 的摘要和事件绑定入口。
    /// - Important: 旧 provider section 使用 deprecated 迁移入口，不要传入此方法。
    @discardableResult
    public func apply(
        _ sections: [ListSection<SectionID>],
        animatingDifferences: Bool = true,
        completion: (() -> Void)? = nil
    ) -> ListApplyResult<SectionID> {
        apply(animatingDifferences: animatingDifferences, completion: completion) {
            sections
        }
    }

    /// 使用 apply 级刷新策略重建列表描述树。
    ///
    /// - Parameters:
    ///   - refreshStrategy: 覆盖 Row 自身 refresh policy 的全局刷新策略。
    ///   - animatingDifferences: 是否使用 diffable 动画应用 snapshot。
    ///   - content: 生成当前 section 描述树的 builder。
    /// - Returns: 本次 apply 的摘要和事件绑定入口。
    @discardableResult
    public func apply(
        refresh refreshStrategy: ListApplyRefreshStrategy,
        animatingDifferences: Bool = true,
        @ListSectionBuilder<SectionID> _ content: () -> [ListSection<SectionID>]
    ) -> ListApplyResult<SectionID> {
        apply(
            options: ListApplyOptions(
                animatingDifferences: animatingDifferences,
                refreshStrategy: refreshStrategy
            ),
            completion: nil,
            content
        )
    }

    /// 使用完整 options 重建列表描述树。
    ///
    /// - Parameters:
    ///   - options: diffable 动画、刷新策略和诊断策略。
    ///   - content: 生成当前 section 描述树的 builder。
    /// - Returns: 本次 apply 的摘要和事件绑定入口。
    @discardableResult
    public func apply(
        options: ListApplyOptions,
        @ListSectionBuilder<SectionID> _ content: () -> [ListSection<SectionID>]
    ) -> ListApplyResult<SectionID> {
        apply(options: options, completion: nil, content)
    }

    /// 使用完整 options 重建列表描述树，并在 diffable apply 完成后执行回调。
    ///
    /// - Parameters:
    ///   - options: diffable 动画、刷新策略和诊断策略。
    ///   - completion: diffable apply 完成后的回调。
    ///   - content: 生成当前 section 描述树的 builder。
    /// - Returns: 本次 apply 的摘要和事件绑定入口。
    @discardableResult
    public func apply(
        options: ListApplyOptions,
        completion: (() -> Void)?,
        @ListSectionBuilder<SectionID> _ content: () -> [ListSection<SectionID>]
    ) -> ListApplyResult<SectionID> {
        let newSections = content()
        let newLayoutSignature = Self.makeLayoutSignature(from: newSections)
        let shouldInvalidateLayout = layoutSignature != newLayoutSignature
        let diagnosticsIssues = ListDiagnostics.validate(newSections)
        let applyPlan = ListApplyPlanner.makePlan(
            old: Self.makeCoreSnapshots(from: sections),
            new: Self.makeCoreSnapshots(from: newSections),
            options: options,
            diagnosticsIssues: diagnosticsIssues
        )

        if !applyPlan.shouldApplyDiffable {
            let summary = applyPlan.initialSummary
            lastApplySummary = summary
            ListApplyLogger.logDiagnostics(issues: diagnosticsIssues, options: options)
            ListApplyLogger.logApplySummary(summary, options: options)
            completion?()
            return ListApplyResult(adapter: self, summary: summary)
        }

        sections = newSections
        layoutSignature = newLayoutSignature
        rebuildLookupTables()
        registerBackgroundDecorationsIfNeeded()
        configureSelectionBehavior()

        var snapshot = NSDiffableDataSourceSnapshot<AnyListID, AnyListIdentity>()
        for section in newSections {
            let sectionID = AnyListID(section.id)
            snapshot.appendSections([sectionID])
            snapshot.appendItems(section.rows.map(\.identity), toSection: sectionID)
        }

        let refreshItems = applyPlan.snapshotRefreshItems
        if !refreshItems.isEmpty {
            if #available(iOS 15.0, tvOS 15.0, *) {
                snapshot.reconfigureItems(refreshItems)
            } else {
                snapshot.reloadItems(refreshItems)
            }
        }

        let summary = applyPlan.initialSummary
        lastApplySummary = summary
        ListApplyLogger.logDiagnostics(issues: diagnosticsIssues, options: options)

        isApplyingSnapshot = true
        dataSource.apply(snapshot, animatingDifferences: options.animatingDifferences) { [weak self] in
            guard let self else { return }
            self.isApplyingSnapshot = false
            self.reconcileSelection()
            if shouldInvalidateLayout {
                self.layoutInvalidationGeneration += 1
                self.collectionView?.collectionViewLayout.invalidateLayout()
            }
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
            ListApplyLogger.logApplySummary(completedSummary, options: options)
            completion?()
        }

        return ListApplyResult(adapter: self, summary: summary)
    }

    /// 迁移兼容入口：新页面优先使用 `apply { ListSection { Row(...) } }`。
    @available(*, deprecated, message: "Migration-only compatibility. Prefer apply { ListSection { Row(...) } }.")
    @discardableResult
    public func apply(
        _ providerSections: [ListProviderSection<SectionID>],
        animatingDifferences: Bool = true,
        completion: (() -> Void)? = nil
    ) -> ListApplyResult<SectionID> {
        apply(animatingDifferences: animatingDifferences, completion: completion) {
            providerSections.map { $0.makeListSection() }
        }
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

    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        sections.count
    }

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[safe: section]?.rows.count ?? 0
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let row = row(at: indexPath) else { return UICollectionViewCell() }
        return row.cellProvider(collectionView, indexPath, context(for: indexPath, sectionID: row.identity.sectionID))
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let row = row(at: indexPath) else { return }
        if selectionMode(at: indexPath) == .single {
            deselectOtherItems(in: indexPath.section, keeping: indexPath, collectionView: collectionView)
        }
        let context = context(for: indexPath, sectionID: row.identity.sectionID)
        row.selectHandler?(context)
        row.selectionChangeHandler?(true, context)
    }

    public func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        guard let row = row(at: indexPath) else { return }
        let context = context(for: indexPath, sectionID: row.identity.sectionID)
        row.deselectHandler?(context)
        row.selectionChangeHandler?(false, context)
    }

    public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        selectionMode(at: indexPath) != .none
    }

    public func collectionView(_ collectionView: UICollectionView, shouldDeselectItemAt indexPath: IndexPath) -> Bool {
        selectionMode(at: indexPath) != .none
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        if let row = row(at: indexPath) {
            displayedRowsByCell[ObjectIdentifier(cell)] = row
            row.displayHandler?(cell, context(for: indexPath, sectionID: row.identity.sectionID))
        }
        displayDelegate?.collectionView?(collectionView, willDisplay: cell, forItemAt: indexPath)
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        didEndDisplaying cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        let row = displayedRowsByCell.removeValue(forKey: ObjectIdentifier(cell)) ?? row(at: indexPath)
        if let row {
            row.endDisplayHandler?(cell, context(for: indexPath, sectionID: row.identity.sectionID))
        }
        displayDelegate?.collectionView?(collectionView, didEndDisplaying: cell, forItemAt: indexPath)
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        willDisplaySupplementaryView view: UICollectionReusableView,
        forElementKind elementKind: String,
        at indexPath: IndexPath
    ) {
        if let supplementary = supplementary(kind: elementKind, at: indexPath) {
            displayedSupplementariesByView[ObjectIdentifier(view)] = supplementary
            supplementary.displayHandler?(view, context(for: indexPath, sectionID: supplementary.identity.sectionID))
        }
        displayDelegate?.collectionView?(
            collectionView,
            willDisplaySupplementaryView: view,
            forElementKind: elementKind,
            at: indexPath
        )
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
            supplementary.endDisplayHandler?(view, context(for: indexPath, sectionID: supplementary.identity.sectionID))
        }
        displayDelegate?.collectionView?(
            collectionView,
            didEndDisplayingSupplementaryView: view,
            forElementOfKind: elementKind,
            at: indexPath
        )
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        prefetchItemsAt indexPaths: [IndexPath]
    ) {
        for indexPath in indexPaths {
            guard let row = row(at: indexPath) else { continue }
            prefetchedRowsByIndexPath[indexPath] = row
            row.prefetchHandler?(context(for: indexPath, sectionID: row.identity.sectionID))
        }
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        cancelPrefetchingForItemsAt indexPaths: [IndexPath]
    ) {
        for indexPath in indexPaths {
            guard let row = prefetchedRowsByIndexPath.removeValue(forKey: indexPath) ?? row(at: indexPath) else {
                continue
            }
            row.cancelPrefetchHandler?(context(for: indexPath, sectionID: row.identity.sectionID))
        }
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let row = row(at: indexPath) else { return nil }
        return row.contextMenuProvider?(context(for: indexPath, sectionID: row.identity.sectionID))
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        leadingSwipeActionsConfigurationForItemAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let row = row(at: indexPath) else { return nil }
        return row.leadingSwipeActionsProvider?(context(for: indexPath, sectionID: row.identity.sectionID))
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        trailingSwipeActionsConfigurationForItemAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let row = row(at: indexPath) else { return nil }
        return row.trailingSwipeActionsProvider?(context(for: indexPath, sectionID: row.identity.sectionID))
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isApplyingSnapshot else { return }
        scrollDelegate?.scrollViewDidScroll?(scrollView)
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        scrollDelegate?.scrollViewWillBeginDragging?(scrollView)
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        scrollDelegate?.scrollViewDidEndDragging?(scrollView, willDecelerate: decelerate)
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        scrollDelegate?.scrollViewDidEndDecelerating?(scrollView)
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        layoutDelegate?.collectionView?(collectionView, layout: collectionViewLayout, sizeForItemAt: indexPath)
            ?? (collectionViewLayout as? UICollectionViewFlowLayout)?.itemSize
            ?? UICollectionViewFlowLayout.automaticSize
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        insetForSectionAt section: Int
    ) -> UIEdgeInsets {
        layoutDelegate?.collectionView?(collectionView, layout: collectionViewLayout, insetForSectionAt: section)
            ?? (collectionViewLayout as? UICollectionViewFlowLayout)?.sectionInset
            ?? .zero
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        minimumLineSpacingForSectionAt section: Int
    ) -> CGFloat {
        layoutDelegate?.collectionView?(collectionView, layout: collectionViewLayout, minimumLineSpacingForSectionAt: section)
            ?? (collectionViewLayout as? UICollectionViewFlowLayout)?.minimumLineSpacing
            ?? 0
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        minimumInteritemSpacingForSectionAt section: Int
    ) -> CGFloat {
        layoutDelegate?.collectionView?(collectionView, layout: collectionViewLayout, minimumInteritemSpacingForSectionAt: section)
            ?? (collectionViewLayout as? UICollectionViewFlowLayout)?.minimumInteritemSpacing
            ?? 0
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        referenceSizeForHeaderInSection section: Int
    ) -> CGSize {
        layoutDelegate?.collectionView?(collectionView, layout: collectionViewLayout, referenceSizeForHeaderInSection: section)
            ?? (collectionViewLayout as? UICollectionViewFlowLayout)?.headerReferenceSize
            ?? .zero
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        referenceSizeForFooterInSection section: Int
    ) -> CGSize {
        layoutDelegate?.collectionView?(collectionView, layout: collectionViewLayout, referenceSizeForFooterInSection: section)
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
            let context = context(for: indexPath, sectionID: row.identity.sectionID)
            row.configureVisibleCell(cell, context)
            row.displayHandler?(cell, context)
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
        fallback: ((
            ListSection<SectionID>,
            Int,
            any NSCollectionLayoutEnvironment
        ) -> NSCollectionLayoutSection?)? = nil,
        diagnostics: ListDiagnosticsOptions = .debugDefault
    ) -> UICollectionViewCompositionalLayout {
        lastLayoutDiagnostics = []
        let layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, environment in
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
        return section.makeCompositionalLayoutSection(fallback: fallbackSection)
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

    private func refreshVisibleRowsIfNeeded(applyPlan: ListApplyPlan) -> Int {
        guard let collectionView else { return 0 }
        var refreshedCount = 0
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard
                let row = row(at: indexPath),
                let rowSnapshot = applyPlan.newRowsByIdentity[row.identity],
                applyPlan.oldRowsByIdentity[row.identity] != nil,
                ListApplyPlanner.shouldRefreshVisibleRow(rowSnapshot)
            else { continue }

            if let cell = collectionView.cellForItem(at: indexPath) {
                row.configureVisibleCell(cell, context(for: indexPath, sectionID: row.identity.sectionID))
                row.displayHandler?(cell, context(for: indexPath, sectionID: row.identity.sectionID))
                refreshedCount += 1
            }
        }
        return refreshedCount
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
        let context = context(for: target.indexPath, sectionID: supplementary.identity.sectionID)
        configureVisibleView(target.view, context)
        supplementary.displayHandler?(target.view, context)
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

    private func context(for indexPath: IndexPath, sectionID: AnyListID) -> ListContext {
        guard let collectionView else {
            fatalError("CollectionListAdapter collectionView was released")
        }
        return ListContext(sectionID: sectionID, indexPath: indexPath, collectionView: collectionView) { [weak self] event, context in
            self?.dispatch(event, context: context)
        }
    }

    private func dispatch(_ event: any ListEvent, context: ListContext) {
        eventRouter.dispatch(event, context: context)
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

private struct ListSectionLayoutSignature: Hashable {
    let sectionID: AnyListID
    let layoutID: AnyListID?
    let sectionLayout: ListSectionLayout?
    let customLayoutID: AnyListID?
    let supplementarySignatures: [ListSupplementaryLayoutSignature]
    let backgroundDecoration: ListBackgroundDecoration?
}

private struct ListSupplementaryLayoutSignature: Hashable {
    let identity: AnyListIdentity
    let kind: String
    let layout: ListSupplementaryLayout?
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
