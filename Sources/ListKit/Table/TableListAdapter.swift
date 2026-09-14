import UIKit

// MARK: - Table Adapter

/// UITableView 列表适配器。
///
/// 适配器弱持有列表。列表释放后，新的更新和尚未提交的排队请求以
/// `.cancelledBeforeCommit` 结束；已经提交的更新仍由原 UIKit 完成回调收尾。
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
    /// 原生 drop delegate 逃生口；设置后直接安装到 table view。
    public weak var dropDelegate: UITableViewDropDelegate? {
        didSet { tableView?.dropDelegate = dropDelegate }
    }

    /// 最近一次 `apply` 的摘要。
    ///
    /// 同步 `apply` 提交后会先更新为 `.submitted` 摘要；snapshot、可见刷新、layout
    /// 和滚动处理完成后，会再次更新为最终摘要。
    public private(set) var lastApplySummary = ListApplySummary()

    /// Table diffable data source 在差异提交时使用的默认行动画。
    public var defaultRowAnimation: UITableView.RowAnimation {
        get { dataSource.defaultRowAnimation }
        set { dataSource.defaultRowAnimation = newValue }
    }

    /// adapter 管理的 table view；弱持有以避免 view -> adapter -> view 环。
    private weak var tableView: UITableView?
    /// 最近一次已接受 apply 的声明式 Section 描述树。
    private var sections: [TableSection<SectionID>] = []
    /// 实际持有并提交 diffable snapshot 的 data source。
    private var dataSource: TableDiffableDataSource<SectionID>!
    /// 当前描述树按 presentation identity 建立的 Row 查询表。
    private var rowsByIdentity: [AnyListIdentity: AnyTableRow] = [:]
    /// Cell 开始展示时捕获的 Row，确保结束展示回调不受后续 snapshot 复用影响。
    private var displayedRowsByCell: [ObjectIdentifier: AnyTableRow] = [:]
    /// header/footer 开始展示时捕获的 supplementary 描述。
    private var displayedSupplementariesByView: [ObjectIdentifier: TableDisplayedSupplementary] = [:]
    /// 预取开始时捕获的 Row，确保取消预取时仍回调原始对象。
    private var prefetchedRowsByIndexPath: [IndexPath: AnyTableRow] = [:]
    /// 每次接受新 apply 时递增，用于拒绝旧异步 completion 写回状态。
    private var applyGeneration = 0
    /// 批量预取和取消预取的 adapter 级回调。
    private var prefetchRowsHandler: (@MainActor ([TableListContext]) -> Void)?
    private var cancelPrefetchingRowsHandler: (@MainActor ([TableListContext]) -> Void)?
    /// 当前已展示上下文菜单对应的 Row 和原始 index path。
    private var activeContextMenu: (row: AnyTableRow, indexPath: IndexPath)?
    /// 保持可见锚点时临时添加到 contentInset.bottom 的补偿量。
    private var preservedAnchorBottomInsetCompensation: CGFloat = 0
    /// 应用锚点补偿前调用方设置的原始 bottom inset。
    private var temporaryAnchorBaseBottomInset: CGFloat?
    /// Collection 与 Table 共用同一套 mutation 排队、合并和 UIKit commit gate。
    private let mutationScheduler = ListMutationScheduler()
    private var mutationCoordinator: ListMutationCoordinator { mutationScheduler.coordinator }
    /// 防止 UIKit 尚有未提交更新时重复安排 reloadAll 重试定时器。
    private var isReloadAllRetryScheduled = false
    /// 按事件类型保存 adapter 级处理闭包。
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

    /// 同时报告 adapter 和已配置转发 delegate 支持的 Objective-C selector。
    public override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return MainActor.assumeIsolated {
            forwardingDelegates.contains { delegate in
                (delegate as? NSObjectProtocol)?.responds(to: aSelector) == true
            }
        }
    }

    /// 将 ListKit 未实现的可选 UIKit delegate selector 转发给第一个匹配对象。
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
    ) -> ListApplySummary {
        _apply(options: options, completion: completion, content)
    }

    /// 提交一次 table 更新，并立即返回提交摘要。
    @discardableResult
    public func apply(
        options: ListApplyOptions,
        @TableSectionBuilder<SectionID> _ content: () -> [TableSection<SectionID>]
    ) -> ListApplySummary {
        _apply(options: options, completion: nil, content)
    }

    /// 以 SwiftUI 风格的 transaction 提交更新。
    @discardableResult
    public func apply(
        transaction: ListTransaction = .automatic,
        completion: ((ListApplySummary) -> Void)? = nil,
        @TableSectionBuilder<SectionID> _ content: () -> [TableSection<SectionID>]
    ) -> ListApplySummary {
        apply(
            options: ListApplyOptions(transaction: transaction),
            completion: completion,
            content
        )
    }

    /// 以 SwiftUI 风格的 transaction 提交更新，并立即返回提交摘要。
    @discardableResult
    public func apply(
        transaction: ListTransaction = .automatic,
        @TableSectionBuilder<SectionID> _ content: () -> [TableSection<SectionID>]
    ) -> ListApplySummary {
        _apply(options: ListApplyOptions(transaction: transaction), completion: nil, content)
    }

    /// 提交已经构建好的 table sections。
    @discardableResult
    public func apply(
        _ sections: [TableSection<SectionID>],
        options: ListApplyOptions,
        completion: ((ListApplySummary) -> Void)? = nil
    ) -> ListApplySummary {
        apply(options: options, completion: completion) { sections }
    }

    /// 以 transaction 提交已经构建好的 sections。
    @discardableResult
    public func apply(
        _ sections: [TableSection<SectionID>],
        transaction: ListTransaction = .automatic,
        completion: ((ListApplySummary) -> Void)? = nil
    ) -> ListApplySummary {
        apply(
            sections,
            options: ListApplyOptions(transaction: transaction),
            completion: completion
        )
    }

    /// 使用当前已提交的描述树和 snapshot 强制重新加载整个列表。
    ///
    /// 此方法不依赖 Row、header 或 footer 的 `identity`、`refreshID` 和刷新策略，
    /// 并始终同步重新计算布局。适用于语言、LTR/RTL、Dynamic Type、主题等未进入
    /// 刷新标识的全局环境变化。
    ///
    /// - Important: 此方法不会重建描述树。配置闭包应在执行时读取最新环境；
    ///   如果本地化文案已作为值保存在旧 model 中，请先更新数据并使用 `apply`。
    /// - Returns: 本次强制刷新的初始结果；最终摘要可从 `lastApplySummary` 获取。
    @discardableResult
    public func reloadAll(
        transaction: ListTransaction = .automatic,
        transition: ListContentTransition = .opacity
    ) -> ListApplySummary {
        _reloadAll(
            transaction: transaction,
            transition: transition,
            completion: nil
        )
    }

    /// 使用当前已提交状态强刷整个列表，并在过渡和布局完成后回调。
    @discardableResult
    public func reloadAll(
        transaction: ListTransaction = .automatic,
        transition: ListContentTransition = .opacity,
        completion: @escaping (ListApplySummary) -> Void
    ) -> ListApplySummary {
        _reloadAll(
            transaction: transaction,
            transition: transition,
            completion: completion
        )
    }

    private func _reloadAll(
        transaction: ListTransaction,
        transition: ListContentTransition,
        subscriberID: UUID? = nil,
        completion: ((ListApplySummary) -> Void)?
    ) -> ListApplySummary {
        guard tableView != nil else {
            return cancelApplyBeforeCommit(transaction: transaction, completion: completion)
        }
        let request = ListReloadAllRequest(
            transaction: transaction,
            transition: transition,
            subscriberID: subscriberID,
            completion: completion
        )
        let summary = makeReloadAllPlan(transaction: transaction).initialSummary.replacingAnimation(
            ListAnimationSummary(
                reduceMotionApplied: transaction.resolved(
                    reduceMotionEnabled: UIAccessibility.isReduceMotionEnabled
                ).reduceMotionApplied
            )
        )
        lastApplySummary = summary

        enqueueReloadAll(request)

        return summary
    }

    /// 强制刷新当前已提交列表，并等待内容过渡和布局完成。
    @discardableResult
    public func reloadAll(
        transaction: ListTransaction = .automatic,
        transition: ListContentTransition = .opacity
    ) async -> ListApplySummary {
        let resolved = transaction.resolved(
            reduceMotionEnabled: UIAccessibility.isReduceMotionEnabled
        )
        let cancelled = ListApplySummary(animation: ListAnimationSummary(
            completionState: .cancelledBeforeCommit,
            reduceMotionApplied: resolved.reduceMotionApplied
        ))
        let bridge = ListAsyncMutationBridge(cancelledResult: cancelled)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let subscriberID = UUID()
                guard bridge.register(continuation, cancellation: { [weak self] in
                    Task { @MainActor in
                        guard let self else {
                            bridge.resume(returning: cancelled)
                            return
                        }
                        if self.mutationScheduler.cancelSubscriber(subscriberID) {
                            self.performNextPendingMutationIfNeeded()
                        }
                    }
                }) else { return }
                _ = _reloadAll(
                    transaction: transaction,
                    transition: transition,
                    subscriberID: subscriberID,
                    completion: { bridge.resume(returning: $0) }
                )
            }
        } onCancel: {
            bridge.cancel()
        }
    }

    /// 保留现有 Cell，并重配单个 Row ID 对应的展示 identity。
    ///
    /// - Parameters:
    ///   - rowID: Row 的业务稳定 ID。
    ///   - sectionID: 可选的 Section 过滤条件；传入 `nil` 时允许跨 Section 匹配。
    ///   - scope: 刷新全部匹配 identity，或只刷新当前可见目标。
    ///   - layout: 重配完成后是否由 ListKit 主动请求自适应尺寸重测量。
    ///   - transaction: snapshot、布局动画和 mutation 排队策略。
    ///   - completion: mutation 完成、被替代或提交前取消后的最终摘要。
    /// - Returns: 已正常入队时返回 `.submitted` 摘要；最终结果以 completion 为准。
    @discardableResult
    public func reconfigureRows<RowID>(
        forRowID rowID: RowID,
        in sectionID: SectionID? = nil,
        scope: ListRefreshScope = .allMatching,
        layout: ListRefreshLayoutPolicy = .none,
        transaction: ListTransaction = .automatic,
        completion: ((ListRefreshSummary) -> Void)? = nil
    ) -> ListRefreshSummary where RowID: Hashable & Sendable {
        reconfigureRows(
            forRowIDs: [rowID],
            in: sectionID,
            scope: scope,
            layout: layout,
            transaction: transaction,
            completion: completion
        )
    }

    /// 重配单个 Row，并等待配置和布局处理完成。
    ///
    /// - Returns: mutation 完成、被替代或提交前取消后的最终摘要。
    public func reconfigureRows<RowID>(
        forRowID rowID: RowID,
        in sectionID: SectionID? = nil,
        scope: ListRefreshScope = .allMatching,
        layout: ListRefreshLayoutPolicy = .none,
        transaction: ListTransaction = .automatic
    ) async -> ListRefreshSummary where RowID: Hashable & Sendable {
        await reconfigureRows(
            forRowIDs: [rowID],
            in: sectionID,
            scope: scope,
            layout: layout,
            transaction: transaction
        )
    }

    /// 保留现有 Cell，并批量重配匹配 Row ID 的展示 identity。
    ///
    /// 输入 ID 会先去重；请求真正出队时再从最新已提交 snapshot 解析目标，因此排队
    /// 期间发生的 apply 不会留下陈旧 index path。空输入或零匹配也会在下一次
    /// MainActor turn 调用一次 completion。
    ///
    /// - Parameters:
    ///   - rowIDs: 要刷新的 Row ID；同一 ID 可以匹配多个 Section 或展示变体。
    ///   - sectionID: 可选的 Section 过滤条件。
    ///   - scope: 刷新全部匹配 identity，或只刷新当前可见目标。
    ///   - layout: 重配后是否主动请求自适应尺寸重测量。
    ///   - transaction: snapshot、布局动画和 mutation 排队策略。
    ///   - completion: mutation 的最终摘要。
    /// - Returns: 包含去重输入数量的 `.submitted` 摘要。
    @discardableResult
    public func reconfigureRows<RowID>(
        forRowIDs rowIDs: [RowID],
        in sectionID: SectionID? = nil,
        scope: ListRefreshScope = .allMatching,
        layout: ListRefreshLayoutPolicy = .none,
        transaction: ListTransaction = .automatic,
        completion: ((ListRefreshSummary) -> Void)? = nil
    ) -> ListRefreshSummary where RowID: Hashable & Sendable {
        refreshRows(
            matching: rowIDs.map(AnyListID.init),
            in: sectionID.map(AnyListID.init),
            scope: scope,
            action: .reconfigure(layout: layout),
            transaction: transaction,
            completion: completion
        )
    }

    /// 重配匹配 Row，并等待配置和布局处理完成。
    ///
    /// - Returns: 包含最终匹配、可见重配、布局和 completion state 的摘要。
    public func reconfigureRows<RowID>(
        forRowIDs rowIDs: [RowID],
        in sectionID: SectionID? = nil,
        scope: ListRefreshScope = .allMatching,
        layout: ListRefreshLayoutPolicy = .none,
        transaction: ListTransaction = .automatic
    ) async -> ListRefreshSummary where RowID: Hashable & Sendable {
        await awaitRowRefresh(
            rowIDs: rowIDs.map(AnyListID.init),
            sectionID: sectionID.map(AnyListID.init),
            scope: scope,
            action: .reconfigure(layout: layout),
            transaction: transaction
        )
    }

    /// 通过完整 reload/configuration 路径刷新单个 Row ID。
    ///
    /// reload 会请求 UIKit 重新执行 provider/configuration，但不保证最终 Cell 对象
    /// 地址发生变化。Cell 类型变化必须改用 presentation identity 的 delete + insert。
    ///
    /// - Returns: 已正常入队时返回 `.submitted` 摘要；最终结果以 completion 为准。
    @discardableResult
    public func reloadRows<RowID>(
        forRowID rowID: RowID,
        in sectionID: SectionID? = nil,
        scope: ListRefreshScope = .allMatching,
        transaction: ListTransaction = .automatic,
        completion: ((ListRefreshSummary) -> Void)? = nil
    ) -> ListRefreshSummary where RowID: Hashable & Sendable {
        reloadRows(
            forRowIDs: [rowID],
            in: sectionID,
            scope: scope,
            transaction: transaction,
            completion: completion
        )
    }

    /// Reload 单个 Row，并等待 UIKit 更新完成。
    ///
    /// - Returns: mutation 的最终摘要。
    public func reloadRows<RowID>(
        forRowID rowID: RowID,
        in sectionID: SectionID? = nil,
        scope: ListRefreshScope = .allMatching,
        transaction: ListTransaction = .automatic
    ) async -> ListRefreshSummary where RowID: Hashable & Sendable {
        await reloadRows(
            forRowIDs: [rowID],
            in: sectionID,
            scope: scope,
            transaction: transaction
        )
    }

    /// 通过完整 reload/configuration 路径批量刷新匹配 Row ID 的展示 identity。
    ///
    /// 输入 ID 会去重，scope 和 Section 过滤在请求真正执行时应用。
    ///
    /// - Parameters:
    ///   - rowIDs: 要 reload 的 Row ID。
    ///   - sectionID: 可选的 Section 过滤条件。
    ///   - scope: reload 全部匹配 identity，或只 reload 当前可见目标。
    ///   - transaction: snapshot 动画和 mutation 排队策略。
    ///   - completion: mutation 的最终摘要。
    /// - Returns: 包含去重输入数量的 `.submitted` 摘要。
    @discardableResult
    public func reloadRows<RowID>(
        forRowIDs rowIDs: [RowID],
        in sectionID: SectionID? = nil,
        scope: ListRefreshScope = .allMatching,
        transaction: ListTransaction = .automatic,
        completion: ((ListRefreshSummary) -> Void)? = nil
    ) -> ListRefreshSummary where RowID: Hashable & Sendable {
        refreshRows(
            matching: rowIDs.map(AnyListID.init),
            in: sectionID.map(AnyListID.init),
            scope: scope,
            action: .reload,
            transaction: transaction,
            completion: completion
        )
    }

    /// Reload 匹配 Row，并等待 UIKit 更新完成。
    ///
    /// - Returns: 包含最终匹配和 reload 数量的摘要。
    public func reloadRows<RowID>(
        forRowIDs rowIDs: [RowID],
        in sectionID: SectionID? = nil,
        scope: ListRefreshScope = .allMatching,
        transaction: ListTransaction = .automatic
    ) async -> ListRefreshSummary where RowID: Hashable & Sendable {
        await awaitRowRefresh(
            rowIDs: rowIDs.map(AnyListID.init),
            sectionID: sectionID.map(AnyListID.init),
            scope: scope,
            action: .reload,
            transaction: transaction
        )
    }

    /// 使用 diffable `reloadSections` 刷新指定 Section 及其 header/footer。
    ///
    /// 不存在或重复的 section id 会被安全忽略。
    ///
    /// - Parameters:
    ///   - sectionIDs: 要 reload 的 Section ID；重复值只计作一个请求目标。
    ///   - transaction: snapshot 动画和 mutation 排队策略。
    ///   - completion: mutation 的最终摘要。
    /// - Returns: 包含去重输入数量的 `.submitted` 摘要。
    @discardableResult
    public func reloadSections(
        _ sectionIDs: [SectionID],
        transaction: ListTransaction = .automatic,
        completion: ((ListRefreshSummary) -> Void)? = nil
    ) -> ListRefreshSummary {
        refreshSections(
            sectionIDs.map(AnyListID.init),
            transaction: transaction,
            completion: completion
        )
    }

    /// Reload 指定 Section，并等待 UIKit 更新完成。
    ///
    /// - Returns: 包含最终匹配、reload 数量和 completion state 的摘要。
    public func reloadSections(
        _ sectionIDs: [SectionID],
        transaction: ListTransaction = .automatic
    ) async -> ListRefreshSummary {
        let ids = sectionIDs.map(AnyListID.init)
        let cancelled = ListRefreshSummary(
            requestedTargetCount: Set(ids).count,
            animation: ListAnimationSummary(completionState: .cancelledBeforeCommit)
        )
        let bridge = ListAsyncMutationBridge(cancelledResult: cancelled)
        let subscriberID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard bridge.register(continuation, cancellation: { [weak self] in
                    Task { @MainActor in
                        guard let self else { return }
                        _ = self.mutationScheduler.cancelSubscriber(subscriberID)
                        self.performNextPendingMutationIfNeeded()
                    }
                }) else { return }
                _ = refreshSections(
                    ids,
                    transaction: transaction,
                    subscriberID: subscriberID,
                    completion: { bridge.resume(returning: $0) }
                )
            }
        } onCancel: {
            bridge.cancel()
        }
    }

    private func awaitRowRefresh(
        rowIDs: [AnyListID],
        sectionID: AnyListID?,
        scope: ListRefreshScope,
        action: ListRowRefreshAction,
        transaction: ListTransaction
    ) async -> ListRefreshSummary {
        let cancelled = ListRefreshSummary(
            requestedTargetCount: Set(rowIDs).count,
            animation: ListAnimationSummary(completionState: .cancelledBeforeCommit)
        )
        let bridge = ListAsyncMutationBridge(cancelledResult: cancelled)
        let subscriberID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard bridge.register(continuation, cancellation: { [weak self] in
                    Task { @MainActor in
                        guard let self else { return }
                        _ = self.mutationScheduler.cancelSubscriber(subscriberID)
                        self.performNextPendingMutationIfNeeded()
                    }
                }) else { return }
                _ = refreshRows(
                    matching: rowIDs,
                    in: sectionID,
                    scope: scope,
                    action: action,
                    transaction: transaction,
                    subscriberID: subscriberID,
                    completion: { bridge.resume(returning: $0) }
                )
            }
        } onCancel: {
            bridge.cancel()
        }
    }

    /// 重新查询并刷新 table view 的 section index 标题。
    public func reloadSectionIndexTitles() {
        tableView?.reloadSectionIndexTitles()
    }

    /// 执行一次描述树提交；coordinator 忙碌时保存描述树并返回初始 `.submitted` 摘要。
    private func _apply(
        options: ListApplyOptions,
        subscriberID: UUID? = nil,
        completion: ((ListApplySummary) -> Void)?,
        @TableSectionBuilder<SectionID> _ content: () -> [TableSection<SectionID>]
    ) -> ListApplySummary {
        // 只在本次同步提交期间强持有视图，不延长到异步动画完成之后。
        guard let tableView else {
            return cancelApplyBeforeCommit(transaction: options.transaction, completion: completion)
        }
        let newSections = content()
        let resolvedTransaction = options.transaction.resolved(
            reduceMotionEnabled: UIAccessibility.isReduceMotionEnabled
        )
        let diagnosticsIssues = ListDiagnostics.validate(Self.makeCoreSnapshots(from: newSections))
        if mutationCoordinator.isExecuting {
            let deferredPlan = ListApplyPlanner.makePlan(
                old: Self.makeCoreSnapshots(from: sections),
                new: Self.makeCoreSnapshots(from: newSections),
                options: options,
                diagnosticsIssues: diagnosticsIssues
            )
            let deferredSummary = deferredPlan.initialSummary.replacingAnimation(
                ListAnimationSummary(reduceMotionApplied: resolvedTransaction.reduceMotionApplied)
            )
            lastApplySummary = deferredSummary
            ListApplyLogger.logDiagnostics(issues: diagnosticsIssues, options: options)
            enqueuePendingMutation(ListPendingMutationRequest(
                kind: .apply,
                updatePolicy: resolvedTransaction.updatePolicy,
                subscriberID: subscriberID,
                onCancel: {
                    completion?(deferredSummary.replacingAnimation(
                        ListAnimationSummary(
                            completionState: .cancelledBeforeCommit,
                            reduceMotionApplied: resolvedTransaction.reduceMotionApplied
                        )
                    ))
                },
                start: { [weak self] in
                    guard let self else {
                        completion?(deferredSummary.replacingAnimation(
                            ListAnimationSummary(
                                completionState: .cancelledBeforeCommit,
                                reduceMotionApplied: resolvedTransaction.reduceMotionApplied
                            )
                        ))
                        return
                    }
                    _ = self._apply(options: options, completion: completion) { newSections }
                },
                supersede: {
                    completion?(deferredSummary.replacingAnimation(
                        ListAnimationSummary(
                            completionState: .superseded,
                            reduceMotionApplied: resolvedTransaction.reduceMotionApplied
                        )
                    ))
                }
            ))
            return deferredSummary
        }

        let applyPlan = ListApplyPlanner.makePlan(
            old: Self.makeCoreSnapshots(from: sections),
            new: Self.makeCoreSnapshots(from: newSections),
            options: options,
            diagnosticsIssues: diagnosticsIssues
        )

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
            return summary
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
        rebuildLookupTables(in: tableView)
        configureSelectionBehavior()

        var snapshot = NSDiffableDataSourceSnapshot<AnyListID, AnyListIdentity>()
        for section in newSections {
            let sectionID = AnyListID(section.id)
            snapshot.appendSections([sectionID])
            snapshot.appendItems(section.rows.map(\.identity), toSection: sectionID)
        }

        // planner 已保证 reconfigure 与 reload 分组互斥；presentation identity 变化
        // 已由结构 diff 处理，不会进入以下内容刷新路径。
        if !applyPlan.snapshotReconfigureItems.isEmpty {
            snapshot.reconfigureItems(applyPlan.snapshotReconfigureItems)
        }
        if !applyPlan.snapshotReloadItems.isEmpty {
            snapshot.reloadItems(applyPlan.snapshotReloadItems)
        }
        if !applyPlan.snapshotReloadSections.isEmpty {
            snapshot.reloadSections(applyPlan.snapshotReloadSections)
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
        let mutationToken = mutationCoordinator.begin(
            kind: .apply,
            updatePolicy: resolvedTransaction.updatePolicy
        )
        let finishAsSuperseded = { [weak self] in
            guard let self else { return }
            self.mutationCoordinator.finish(mutationToken)
            completeAsSuperseded()
            self.performNextPendingMutationIfNeeded()
        }

        // 将 UIKit 的 diffable completion 统一延迟到新的 MainActor turn，避免在
        // UIKit 尚未退出内部提交栈时继续执行选择、布局或下一次 mutation。
        let didApplyBox = TableMainActorCallbackBox { [weak self] in
            guard let self else { return }
            guard self.applyGeneration == generation, !mutationToken.isSuperseded else {
                finishAsSuperseded()
                return
            }
            self.tableView?.reloadSectionIndexTitles()
            self.restoreSelection(for: selectedItemIdentities)
            self.synchronizeControlledSelection()
            self.reconcileSelection()
            let metrics = TableApplyAnimationMetrics()
            let animationCoordinator = ListAnimationCompletionCoordinator {
                guard self.applyGeneration == generation, !mutationToken.isSuperseded else {
                    finishAsSuperseded()
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
                    visibleReconfiguredRowCount: metrics.visibleReconfiguredRowCount,
                    visibleReloadedRowCount: metrics.visibleReloadedRowCount,
                    visibleReconfiguredSupplementaryCount: metrics.visibleReconfiguredSupplementaryCount,
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
                self.mutationCoordinator.finish(mutationToken)
                ListApplyLogger.logApplySummary(
                    completedSummary,
                    options: options,
                    prefix: "ListKit table apply summary"
                )
                completion?(completedSummary)
                self.performNextPendingMutationIfNeeded()
            }

            var needsLayoutInvalidation = options.applicationMode == .reloadData
                || !applyPlan.snapshotLayoutInvalidationItems.isEmpty
            if applyPlan.shouldRunVisibleRefresh {
                let refresh = self.refreshVisibleRowsIfNeeded(
                    applyPlan: applyPlan,
                    animatingContent: resolvedTransaction.contentAnimation,
                    coordinator: animationCoordinator
                )
                metrics.visibleReconfiguredRowCount = refresh.reconfiguredCount
                metrics.visibleReloadedRowCount = refresh.reloadedCount
                metrics.contentTransitionCount = refresh.transitionCount
                let supplementaryRefresh = self.refreshVisibleSupplementariesIfNeeded(
                    applyPlan: applyPlan
                )
                metrics.visibleReconfiguredSupplementaryCount = supplementaryRefresh.reconfiguredCount
                needsLayoutInvalidation = needsLayoutInvalidation
                    || refresh.needsLayoutInvalidation
                    || supplementaryRefresh.needsLayoutInvalidation
            }
            metrics.layoutInvalidated = needsLayoutInvalidation
            metrics.layoutAnimated = self.performLayoutUpdate(
                invalidating: metrics.layoutInvalidated,
                animated: resolvedTransaction.layoutAnimation,
                coordinator: animationCoordinator
            )
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
            dataSource.applySnapshotUsingReloadData(snapshot, completion: didApply)
        }

        return summary
    }

    /// 使用当前描述树生成 reloadAll summary，不重新执行调用方 builder。
    private func makeReloadAllPlan(transaction: ListTransaction) -> ListApplyPlan {
        let currentSnapshots = Self.makeCoreSnapshots(from: sections)
        let options = ListApplyOptions(
            transaction: transaction,
            applicationMode: .reloadData
        )
        return ListApplyPlanner.makePlan(
            old: currentSnapshots,
            new: currentSnapshots,
            options: options,
            diagnosticsIssues: ListDiagnostics.validate(currentSnapshots)
        )
    }

    /// 在真正执行时根据 Row ID、Section 和 scope 解析当前 snapshot 中的目标 identity。
    private func refreshRows(
        matching rowIDs: [AnyListID],
        in sectionID: AnyListID?,
        scope: ListRefreshScope,
        action: ListRowRefreshAction,
        transaction: ListTransaction,
        subscriberID: UUID? = nil,
        completion: ((ListRefreshSummary) -> Void)?
    ) -> ListRefreshSummary {
        let requestedTargetCount = Set(rowIDs).count
        guard tableView != nil else {
            return cancelRefreshBeforeCommit(requestedTargetCount: requestedTargetCount, completion: completion)
        }
        let subscriber = ListRowRefreshSubscriber(
            id: subscriberID,
            rowIDs: Set(rowIDs),
            action: action,
            completion: completion
        )
        if mutationCoordinator.isExecuting {
            enqueuePendingMutation(ListPendingMutationRequest(
                rowIDs: rowIDs,
                sectionID: sectionID,
                scope: scope,
                action: action,
                transaction: transaction,
                subscriberID: subscriberID,
                completion: completion,
                execute: { [weak self] subscribers, sectionID, scope, transaction in
                    guard let self else {
                        subscribers.forEach { subscriber in
                            subscriber.completion?(ListRefreshSummary(
                                requestedTargetCount: subscriber.rowIDs.count,
                                animation: ListAnimationSummary(completionState: .cancelledBeforeCommit)
                            ))
                        }
                        return
                    }
                    _ = self.refreshRows(
                        subscribers,
                        in: sectionID,
                        scope: scope,
                        transaction: transaction
                    )
                }
            ))
            return ListRefreshSummary(requestedTargetCount: requestedTargetCount)
        }

        return refreshRows([subscriber], in: sectionID, scope: scope, transaction: transaction)
    }

    /// 从最新 snapshot 解析合并 subscriber，并只在相同 identity 上消解最强 action。
    private func refreshRows(
        _ subscribers: [ListRowRefreshSubscriber],
        in sectionID: AnyListID?,
        scope: ListRefreshScope,
        transaction: ListTransaction
    ) -> ListRefreshSummary {
        var snapshot = dataSource.snapshot()
        let visibleIdentities = Set((tableView?.indexPathsForVisibleRows ?? []).compactMap { row(at: $0)?.identity })
        var matchedBySubscriber: [Set<AnyListIdentity>] = []
        var resolvedActions: [AnyListIdentity: ListRowRefreshAction] = [:]
        for subscriber in subscribers {
            let matched = Set(snapshot.itemIdentifiers.filter { identity in
                subscriber.rowIDs.contains(identity.rowID)
                    && (sectionID.map { identity.sectionID == $0 } ?? true)
                    && rowsByIdentity[identity] != nil
                    && (scope == .allMatching || visibleIdentities.contains(identity))
            })
            matchedBySubscriber.append(matched)
            for identity in matched {
                resolvedActions[identity] = resolvedActions[identity].map {
                    ListRowRefreshAction.stronger($0, subscriber.action)
                } ?? subscriber.action
            }
        }
        guard !resolvedActions.isEmpty else {
            TableMainActorCallbackBox { [weak self] in
                subscribers.forEach { subscriber in
                    subscriber.completion?(ListRefreshSummary(
                        requestedTargetCount: subscriber.rowIDs.count,
                        animation: ListAnimationSummary(completionState: .completed)
                    ))
                }
                self?.performNextPendingMutationIfNeeded()
            }.schedule()
            return ListRefreshSummary(requestedTargetCount: subscribers.first?.rowIDs.count ?? 0)
        }
        if scope == .visible {
            return refreshVisibleRows(
                subscribers,
                matchedBySubscriber: matchedBySubscriber,
                resolvedActions: resolvedActions,
                transaction: transaction
            )
        }
        let reconfigureItems = resolvedActions.compactMap { identity, action -> AnyListIdentity? in
            if case .reconfigure = action { return identity }
            return nil
        }
        let reloadItems = resolvedActions.compactMap { identity, action -> AnyListIdentity? in
            action == .reload ? identity : nil
        }
        let invalidatesLayout = resolvedActions.values.contains {
            $0 == .reconfigure(layout: .invalidate)
        }
        snapshot.reconfigureItems(reconfigureItems)
        snapshot.reloadItems(reloadItems)

        let mutationToken = mutationCoordinator.begin(
            kind: .rowRefresh,
            updatePolicy: transaction.updatePolicy
        )
        let resolvedTransaction = transaction.resolved(
            reduceMotionEnabled: UIAccessibility.isReduceMotionEnabled
        )
        let finish = { [weak self] in
            guard let self else {
                subscribers.enumerated().forEach { index, subscriber in
                    subscriber.completion?(Self.makeRefreshSummary(
                        subscriber: subscriber,
                        matched: matchedBySubscriber[index],
                        resolvedActions: resolvedActions,
                        scope: scope,
                        layoutInvalidated: invalidatesLayout,
                        completionState: .completed
                    ))
                }
                return
            }
            // 先恢复内部可执行状态，再调用外部 completion，使 completion 内发起的
            // 下一次刷新不会与当前 UIKit mutation 重叠。
            self.mutationCoordinator.finish(mutationToken)
            subscribers.enumerated().forEach { index, subscriber in
                subscriber.completion?(Self.makeRefreshSummary(
                    subscriber: subscriber,
                    matched: matchedBySubscriber[index],
                    resolvedActions: resolvedActions,
                    scope: scope,
                    layoutInvalidated: invalidatesLayout,
                    completionState: .completed
                ))
            }
            self.performNextPendingMutationIfNeeded()
        }
        let didRefreshBox = TableMainActorCallbackBox { [weak self] in
            guard let self else {
                finish()
                return
            }
            guard invalidatesLayout, let tableView = self.tableView else {
                finish()
                return
            }
            if resolvedTransaction.layoutAnimation {
                tableView.performBatchUpdates(nil) { _ in finish() }
            } else {
                UIView.performWithoutAnimation {
                    tableView.beginUpdates()
                    tableView.endUpdates()
                    tableView.layoutIfNeeded()
                }
                finish()
            }
        }
        dataSource.apply(
            snapshot,
            animatingDifferences: resolvedTransaction.snapshotAnimation
        ) {
            didRefreshBox.schedule()
        }
        return ListRefreshSummary(requestedTargetCount: subscribers.first?.rowIDs.count ?? 0)
    }

    private static func makeRefreshSummary(
        subscriber: ListRowRefreshSubscriber,
        matched: Set<AnyListIdentity>,
        resolvedActions: [AnyListIdentity: ListRowRefreshAction],
        scope: ListRefreshScope,
        layoutInvalidated: Bool,
        completionState: ListApplyCompletionState
    ) -> ListRefreshSummary {
        let reconfigured = matched.filter {
            if case .reconfigure = resolvedActions[$0] { return true }
            return false
        }.count
        let reloaded = matched.filter { resolvedActions[$0] == .reload }.count
        return ListRefreshSummary(
            requestedTargetCount: subscriber.rowIDs.count,
            matchedTargetCount: matched.count,
            refreshMetrics: ListRefreshMetrics(
                snapshotReconfiguredRowCount: scope == .allMatching ? reconfigured : 0,
                visibleReconfiguredRowCount: scope == .visible ? reconfigured : 0,
                reloadedRowCount: reloaded
            ),
            animation: ListAnimationSummary(
                completionState: completionState,
                layoutInvalidated: layoutInvalidated
            )
        )
    }

    /// 定向 `.visible` 刷新直接操作当前 Cell，不构造 diffable item mutation。
    private func refreshVisibleRows(
        _ subscribers: [ListRowRefreshSubscriber],
        matchedBySubscriber: [Set<AnyListIdentity>],
        resolvedActions: [AnyListIdentity: ListRowRefreshAction],
        transaction: ListTransaction
    ) -> ListRefreshSummary {
        guard let tableView else {
            subscribers.forEach { subscriber in
                subscriber.completion?(ListRefreshSummary(
                    requestedTargetCount: subscriber.rowIDs.count,
                    animation: ListAnimationSummary(completionState: .cancelledBeforeCommit)
                ))
            }
            return ListRefreshSummary(requestedTargetCount: subscribers.first?.rowIDs.count ?? 0)
        }
        let resolvedTransaction = transaction.resolved(
            reduceMotionEnabled: UIAccessibility.isReduceMotionEnabled
        )
        let mutationToken = mutationCoordinator.begin(
            kind: .rowRefresh,
            updatePolicy: transaction.updatePolicy
        )
        var reloadIndexPaths: [IndexPath] = []
        var needsLayoutInvalidation = false
        var contentTransitionCount = 0
        let animationCoordinator = ListAnimationCompletionCoordinator { [weak self] in
            guard let self else { return }
            let complete = { (layoutAnimated: Bool) in
                self.mutationCoordinator.finish(mutationToken)
                subscribers.enumerated().forEach { index, subscriber in
                    let matched = matchedBySubscriber[index]
                    let reconfigured = matched.filter {
                        if case .reconfigure = resolvedActions[$0] { return true }
                        return false
                    }.count
                    let reloaded = matched.filter { resolvedActions[$0] == .reload }.count
                    let subscriberInvalidatesLayout = matched.contains {
                        resolvedActions[$0] == .reconfigure(layout: .invalidate)
                    }
                    subscriber.completion?(ListRefreshSummary(
                        requestedTargetCount: subscriber.rowIDs.count,
                        matchedTargetCount: matched.count,
                        refreshMetrics: ListRefreshMetrics(
                            visibleReconfiguredRowCount: reconfigured,
                            reloadedRowCount: reloaded
                        ),
                        animation: ListAnimationSummary(
                            completionState: .completed,
                            contentTransitionCount: contentTransitionCount,
                            layoutInvalidated: subscriberInvalidatesLayout,
                            layoutAnimated: subscriberInvalidatesLayout && layoutAnimated,
                            reduceMotionApplied: resolvedTransaction.reduceMotionApplied
                        )
                    ))
                }
                self.performNextPendingMutationIfNeeded()
            }
            guard needsLayoutInvalidation else {
                complete(false)
                return
            }
            if resolvedTransaction.layoutAnimation {
                tableView.performBatchUpdates(nil) { _ in complete(true) }
            } else {
                UIView.performWithoutAnimation {
                    tableView.beginUpdates()
                    tableView.endUpdates()
                    tableView.layoutIfNeeded()
                }
                complete(false)
            }
        }
        for (identity, action) in resolvedActions {
            guard
                let indexPath = dataSource.indexPath(for: identity),
                let row = rowsByIdentity[identity],
                let cell = tableView.cellForRow(at: indexPath)
            else { continue }
            switch action {
            case .reload:
                reloadIndexPaths.append(indexPath)
            case .reconfigure(let layout):
                let configure = {
                    row.configureVisibleCell(cell, self.context(for: indexPath, identity: identity))
                }
                if resolvedTransaction.contentAnimation,
                   case .opacity(let duration) = row.contentTransition.storage,
                   duration > 0 {
                    animationCoordinator.enter()
                    UIView.transition(
                        with: cell.contentView,
                        duration: duration,
                        options: [.transitionCrossDissolve, .beginFromCurrentState, .allowAnimatedContent],
                        animations: configure,
                        completion: { _ in animationCoordinator.leave() }
                    )
                    contentTransitionCount += 1
                } else {
                    configure()
                }
                needsLayoutInvalidation = needsLayoutInvalidation || layout == .invalidate
            }
        }
        if !reloadIndexPaths.isEmpty {
            var snapshot = dataSource.snapshot()
            let reloadIdentities = reloadIndexPaths.compactMap {
                dataSource.itemIdentifier(for: $0)
            }
            if !reloadIdentities.isEmpty {
                snapshot.reloadItems(reloadIdentities)
                animationCoordinator.enter()
                let didReloadBox = TableMainActorCallbackBox {
                    animationCoordinator.leave()
                }
                dataSource.apply(
                    snapshot,
                    animatingDifferences: resolvedTransaction.contentAnimation
                ) {
                    didReloadBox.schedule()
                }
                if resolvedTransaction.contentAnimation {
                    contentTransitionCount += reloadIdentities.count
                }
            }
        }
        animationCoordinator.finishScheduling()
        return ListRefreshSummary(requestedTargetCount: subscribers.first?.rowIDs.count ?? 0)
    }

    /// 在执行时过滤并去重当前 snapshot 中仍存在的 Section，然后提交 reloadSections。
    private func refreshSections(
        _ sectionIDs: [AnyListID],
        transaction: ListTransaction,
        subscriberID: UUID? = nil,
        completion: ((ListRefreshSummary) -> Void)?
    ) -> ListRefreshSummary {
        guard tableView != nil else {
            return cancelRefreshBeforeCommit(requestedTargetCount: Set(sectionIDs).count, completion: completion)
        }
        let subscriber = ListSectionReloadSubscriber(
            id: subscriberID,
            sectionIDs: Set(sectionIDs),
            completion: completion
        )
        if mutationCoordinator.isExecuting {
            enqueuePendingMutation(ListPendingMutationRequest(
                sectionIDs: sectionIDs,
                transaction: transaction,
                subscriberID: subscriberID,
                completion: completion,
                execute: { [weak self] subscribers, transaction in
                    guard let self else {
                        subscribers.forEach { subscriber in
                            subscriber.completion?(ListRefreshSummary(
                                requestedTargetCount: subscriber.sectionIDs.count,
                                animation: ListAnimationSummary(completionState: .cancelledBeforeCommit)
                            ))
                        }
                        return
                    }
                    _ = self.refreshSections(subscribers, transaction: transaction)
                }
            ))
            return ListRefreshSummary(requestedTargetCount: subscriber.sectionIDs.count)
        }
        return refreshSections([subscriber], transaction: transaction)
    }

    private func refreshSections(
        _ subscribers: [ListSectionReloadSubscriber],
        transaction: ListTransaction
    ) -> ListRefreshSummary {
        var snapshot = dataSource.snapshot()
        let currentSectionIDs = Set(snapshot.sectionIdentifiers)
        let matchedBySubscriber = subscribers.map { $0.sectionIDs.intersection(currentSectionIDs) }
        let refreshSectionIDs = Set(matchedBySubscriber.flatMap { $0 })
        guard !refreshSectionIDs.isEmpty else {
            TableMainActorCallbackBox { [weak self] in
                subscribers.forEach { subscriber in
                    subscriber.completion?(ListRefreshSummary(
                        requestedTargetCount: subscriber.sectionIDs.count,
                        animation: ListAnimationSummary(completionState: .completed)
                    ))
                }
                self?.performNextPendingMutationIfNeeded()
            }.schedule()
            return ListRefreshSummary(requestedTargetCount: subscribers.first?.sectionIDs.count ?? 0)
        }

        let orderedRefreshSectionIDs = snapshot.sectionIdentifiers.filter(refreshSectionIDs.contains)
        snapshot.reloadSections(orderedRefreshSectionIDs)
        let mutationToken = mutationCoordinator.begin(
            kind: .sectionReload,
            updatePolicy: transaction.updatePolicy
        )
        let resolvedTransaction = transaction.resolved(
            reduceMotionEnabled: UIAccessibility.isReduceMotionEnabled
        )
        let didRefreshBox = TableMainActorCallbackBox { [weak self] in
            guard let self else {
                subscribers.enumerated().forEach { index, subscriber in
                    subscriber.completion?(ListRefreshSummary(
                        requestedTargetCount: subscriber.sectionIDs.count,
                        matchedTargetCount: matchedBySubscriber[index].count,
                        refreshMetrics: ListRefreshMetrics(
                            reloadedSectionCount: matchedBySubscriber[index].count
                        ),
                        animation: ListAnimationSummary(
                            completionState: .completed,
                            layoutInvalidated: true
                        )
                    ))
                }
                return
            }
            self.mutationCoordinator.finish(mutationToken)
            self.tableView?.reloadSectionIndexTitles()
            subscribers.enumerated().forEach { index, subscriber in
                subscriber.completion?(ListRefreshSummary(
                    requestedTargetCount: subscriber.sectionIDs.count,
                    matchedTargetCount: matchedBySubscriber[index].count,
                    refreshMetrics: ListRefreshMetrics(
                        reloadedSectionCount: matchedBySubscriber[index].count
                    ),
                    animation: ListAnimationSummary(
                        completionState: .completed,
                        layoutInvalidated: true
                    )
                ))
            }
            self.performNextPendingMutationIfNeeded()
        }
        dataSource.apply(
            snapshot,
            animatingDifferences: resolvedTransaction.snapshotAnimation
        ) {
            didRefreshBox.schedule()
        }
        return ListRefreshSummary(requestedTargetCount: subscribers.first?.sectionIDs.count ?? 0)
    }

    /// 执行完整 reloadData、布局、selection、supplementary 和滚动锚点恢复流程。
    private func performReloadAll(_ request: ListReloadAllRequest) {
        guard let tableView else {
            _ = cancelApplyBeforeCommit(transaction: request.transaction, completion: request.completion)
            return
        }
        let resolvedTransaction = request.transaction.resolved(
            reduceMotionEnabled: UIAccessibility.isReduceMotionEnabled
        )
        let options = ListApplyOptions(
            transaction: request.transaction,
            applicationMode: .reloadData
        )
        let applyPlan = makeReloadAllPlan(transaction: request.transaction)
        let summary = applyPlan.initialSummary.replacingAnimation(
            ListAnimationSummary(reduceMotionApplied: resolvedTransaction.reduceMotionApplied)
        )
        lastApplySummary = summary
        ListApplyLogger.logDiagnostics(issues: summary.diagnosticsIssues, options: options)

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
        let mutationToken = mutationCoordinator.begin(
            kind: .reloadAll,
            updatePolicy: request.transaction.updatePolicy
        )
        let metrics = TableApplyAnimationMetrics()

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
                prefix: "ListKit table reload summary"
            )
            request.completion?(supersededSummary)
        }

        let completeReload = { [weak self] (layoutAnimated: Bool, transitionCount: Int) in
            guard let self else { return }
            guard self.applyGeneration == generation else {
                completeAsSuperseded()
                return
            }

            metrics.layoutInvalidated = true
            metrics.layoutAnimated = layoutAnimated
            metrics.contentTransitionCount = transitionCount
            let completedSummary = applyPlan.completedSummary(
                visibleReconfiguredRowCount: metrics.visibleReconfiguredRowCount,
                visibleReloadedRowCount: 0,
                visibleReconfiguredSupplementaryCount: metrics.visibleReconfiguredSupplementaryCount,
                animation: ListAnimationSummary(
                    completionState: .completed,
                    contentTransitionCount: metrics.contentTransitionCount,
                    layoutInvalidated: true,
                    layoutAnimated: metrics.layoutAnimated,
                    scrollAnimated: metrics.scrollOutcome.animated,
                    anchorCompensation: metrics.scrollOutcome.anchorCompensation,
                    reduceMotionApplied: resolvedTransaction.reduceMotionApplied
                )
            )
            self.lastApplySummary = completedSummary
            self.mutationCoordinator.finish(mutationToken)
            ListApplyLogger.logApplySummary(
                completedSummary,
                options: options,
                prefix: "ListKit table reload summary"
            )
            request.completion?(completedSummary)
            self.performNextPendingMutationIfNeeded()
        }

        let finishReloadedLayout = { [weak self] in
            guard let self, self.applyGeneration == generation else { return }
            self.restoreSelection(for: selectedItemIdentities)
            self.synchronizeControlledSelection()
            self.reconcileSelection()
            metrics.visibleReconfiguredRowCount = tableView.indexPathsForVisibleRows?.count ?? 0
            metrics.visibleReconfiguredSupplementaryCount = self.visibleTableSupplementaryCount()
            metrics.scrollOutcome = self.performScrollBehavior(
                resolvedTransaction.scrollBehavior,
                visibleAnchor: visibleAnchor,
                animated: resolvedTransaction.scrollAnimation
            )
        }

        let opacityDuration: TimeInterval?
        switch request.transition.storage {
        case .opacity(let duration) where resolvedTransaction.contentAnimation && duration > 0:
            opacityDuration = duration
        case .identity, .opacity:
            opacityDuration = nil
        }

        if let opacityDuration {
            UIView.transition(
                with: tableView,
                duration: opacityDuration,
                options: [.transitionCrossDissolve, .beginFromCurrentState, .allowAnimatedContent]
            ) {
                self.performSynchronousReloadMutation {
                    tableView.reloadData()
                    tableView.reloadSectionIndexTitles()
                    tableView.beginUpdates()
                    tableView.endUpdates()
                    tableView.layoutIfNeeded()
                    finishReloadedLayout()
                }
            } completion: { _ in
                completeReload(false, 1)
            }
        } else {
            performSynchronousReloadMutation {
                tableView.reloadData()
                tableView.reloadSectionIndexTitles()
                UIView.performWithoutAnimation {
                    tableView.beginUpdates()
                    tableView.endUpdates()
                    tableView.layoutIfNeeded()
                }
                finishReloadedLayout()
            }
            completeReload(false, 0)
        }
    }

    private func performSynchronousReloadMutation(_ mutation: () -> Void) {
        mutation()
    }

    private func visibleTableSupplementaryCount() -> Int {
        guard let tableView else { return 0 }
        return sections.indices.reduce(into: 0) { count, section in
            if tableView.headerView(forSection: section) != nil { count += 1 }
            if tableView.footerView(forSection: section) != nil { count += 1 }
        }
    }

    /// 将 mutation 放入共享队列，并按 `.coalesceLatest` 规则合并或替代旧请求。
    private func enqueuePendingMutation(_ request: ListPendingMutationRequest) {
        mutationScheduler.enqueue(request)
    }

    /// reloadAll 作为普通队列节点；UIKit 有未提交更新时保持在队首重试。
    private func enqueueReloadAll(_ request: ListReloadAllRequest) {
        let resolved = request.transaction.resolved(
            reduceMotionEnabled: UIAccessibility.isReduceMotionEnabled
        )
        let supersededSummary = makeReloadAllPlan(transaction: request.transaction)
            .initialSummary
            .replacingAnimation(ListAnimationSummary(
                completionState: .superseded,
                reduceMotionApplied: resolved.reduceMotionApplied
            ))
        let cancelledSummary = ListApplySummary(animation: ListAnimationSummary(
            completionState: .cancelledBeforeCommit,
            reduceMotionApplied: resolved.reduceMotionApplied
        ))
        mutationScheduler.enqueue(ListPendingMutationRequest(
            kind: .reloadAll,
            updatePolicy: request.transaction.updatePolicy,
            requiresCommittedUpdates: true,
            subscriberID: request.subscriberID,
            onCancel: { request.completion?(cancelledSummary) },
            start: { [weak self] in
                guard let self else {
                    request.completion?(cancelledSummary)
                    return
                }
                self.performReloadAll(request)
            },
            supersede: { request.completion?(supersededSummary) }
        ))
        performNextPendingMutationIfNeeded()
    }

    /// 列表已释放时，拒绝新的 apply 或 reloadAll，并完成尚未提交的排队请求。
    private func cancelApplyBeforeCommit(
        transaction: ListTransaction,
        completion: ((ListApplySummary) -> Void)?
    ) -> ListApplySummary {
        let summary = ListApplySummary(animation: ListAnimationSummary(
            completionState: .cancelledBeforeCommit,
            reduceMotionApplied: transaction.resolved(
                reduceMotionEnabled: UIAccessibility.isReduceMotionEnabled
            ).reduceMotionApplied
        ))
        lastApplySummary = summary
        mutationScheduler.cancelPendingRequests()
        completion?(summary)
        return summary
    }

    /// 列表已释放时，保留刷新请求的目标数量并以取消状态完成回调。
    private func cancelRefreshBeforeCommit(
        requestedTargetCount: Int,
        completion: ((ListRefreshSummary) -> Void)?
    ) -> ListRefreshSummary {
        let summary = ListRefreshSummary(
            requestedTargetCount: requestedTargetCount,
            animation: ListAnimationSummary(completionState: .cancelledBeforeCommit)
        )
        mutationScheduler.cancelPendingRequests()
        completion?(summary)
        return summary
    }

    /// scheduler 空闲且列表仍存在时启动队首节点；列表释放后取消全部待提交请求。
    private func performNextPendingMutationIfNeeded() {
        guard let tableView else {
            mutationScheduler.cancelPendingRequests()
            return
        }
        let hasUncommittedUpdates = tableView.hasUncommittedUpdates
        if mutationScheduler.startNext(hasUncommittedUpdates: hasUncommittedUpdates) { return }
        if !mutationScheduler.isExecuting,
           mutationScheduler.hasPendingRequests,
           hasUncommittedUpdates {
            scheduleReloadAllRetry()
        }
    }

    /// UIKit 正在提交内部更新时短暂退避，避免 reloadData 与未完成更新交错。
    private func scheduleReloadAllRetry() {
        guard !isReloadAllRetryScheduled else { return }
        isReloadAllRetryScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isReloadAllRetryScheduled = false
                self.performNextPendingMutationIfNeeded()
            }
        }
    }

    /// 重建描述树并等待 snapshot、layout 和内容过渡完成。
    @discardableResult
    public func apply(
        options: ListApplyOptions,
        @TableSectionBuilder<SectionID> _ content: () -> [TableSection<SectionID>]
    ) async -> ListApplySummary {
        guard tableView != nil else {
            return cancelApplyBeforeCommit(transaction: options.transaction, completion: nil)
        }
        let builtSections = content()
        let resolved = options.transaction.resolved(
            reduceMotionEnabled: UIAccessibility.isReduceMotionEnabled
        )
        let cancelled = ListApplySummary(animation: ListAnimationSummary(
            completionState: .cancelledBeforeCommit,
            reduceMotionApplied: resolved.reduceMotionApplied
        ))
        let bridge = ListAsyncMutationBridge(cancelledResult: cancelled)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let subscriberID = UUID()
                guard bridge.register(continuation, cancellation: { [weak self] in
                    Task { @MainActor in
                        guard let self else {
                            bridge.resume(returning: cancelled)
                            return
                        }
                        if self.mutationScheduler.cancelSubscriber(subscriberID) {
                            self.performNextPendingMutationIfNeeded()
                        }
                    }
                }) else { return }
                _ = _apply(
                    options: options,
                    subscriberID: subscriberID,
                    completion: { bridge.resume(returning: $0) }
                ) {
                    builtSections
                }
            }
        } onCancel: {
            bridge.cancel()
        }
    }

    /// 提交 transaction，并等待 snapshot、layout 和内容过渡完成。
    @discardableResult
    public func apply(
        transaction: ListTransaction = .automatic,
        @TableSectionBuilder<SectionID> _ content: () -> [TableSection<SectionID>]
    ) async -> ListApplySummary {
        await apply(options: ListApplyOptions(transaction: transaction), content)
    }

    /// 绑定自定义列表事件。
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

    // MARK: - UIKit Protocol Witnesses

    // 以下公开方法实现 UITableView data source、delegate、prefetch 与 scroll delegate
    // 契约。方法签名沿用 UIKit 文档；注释重点放在 ListKit 增加的 identity 解析、
    // 生命周期捕获、事件转发、编辑和 selection 同步逻辑上。

    /// 返回当前已接受描述树中的 Section 数量。
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

    /// 返回指定 section index 当前对应的 section id。
    ///
    /// - Parameter sectionIndex: 当前 table section index。
    /// - Returns: 匹配的 section id；越界时返回 `nil`。
    public func sectionIdentifier(at sectionIndex: Int) -> SectionID? {
        sections[safe: sectionIndex]?.id
    }

    /// 返回指定 section 当前的 row 数量。
    ///
    /// - Parameter sectionID: section 的稳定 id。
    /// - Returns: 当前 row 数量。
    public func rowCount(in sectionID: SectionID) -> Int {
        sections.first { $0.id == sectionID }?.rows.count ?? 0
    }

    /// 返回指定 section 当前的 item 数量。
    ///
    /// - Parameter sectionID: section 的稳定 id。
    /// - Returns: 当前 item 数量。UITableView 中 item 等同于 row。
    public func itemCount(in sectionID: SectionID) -> Int {
        rowCount(in: sectionID)
    }

    /// 返回 section 当前所在位置。
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

    /// 根据 row id 查询当前 indexPath。
    ///
    /// - Parameters:
    ///   - rowID: row 的稳定 id。
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

    private func rebuildLookupTables(in tableView: UITableView) {
        rowsByIdentity = [:]

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
                        refreshRule: .supplementary(header.refreshRule),
                        role: .supplementary
                    )
                )
            }
            if let footer = section.footer {
                supplementaries.append(
                    ListNodeSnapshot(
                        identity: footer.identity,
                        refreshID: footer.refreshID,
                        refreshRule: .supplementary(footer.refreshRule),
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
                        refreshRule: .row(row.refreshRule),
                        role: .row
                    )
                },
                supplementaries: supplementaries
            )
        }
    }

    private func refreshVisibleRowsIfNeeded(
        applyPlan: ListApplyPlan,
        animatingContent: Bool,
        coordinator: ListAnimationCompletionCoordinator
    ) -> TableVisibleRefreshResult {
        guard let tableView else { return TableVisibleRefreshResult() }
        var reconfiguredCount = 0
        var reloadedCount = 0
        var transitionCount = 0
        var needsLayoutInvalidation = false
        var reloadIndexPaths: [IndexPath] = []
        for indexPath in tableView.indexPathsForVisibleRows ?? [] {
            guard
                let row = row(at: indexPath),
                let rowSnapshot = applyPlan.newRowsByIdentity[row.identity],
                let oldRowSnapshot = applyPlan.oldRowsByIdentity[row.identity],
                !applyPlan.snapshotReloadSections.contains(row.identity.sectionID),
                ListApplyPlanner.shouldRefreshVisibleRow(
                    rowSnapshot,
                    oldRow: oldRowSnapshot
                ),
                let cell = tableView.cellForRow(at: indexPath)
            else { continue }

            guard case .row(let refreshRule) = rowSnapshot.refreshRule else { continue }
            switch refreshRule.action {
            case .reload:
                reloadIndexPaths.append(indexPath)
                reloadedCount += 1
            case .reconfigure(let layout):
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
                needsLayoutInvalidation = needsLayoutInvalidation || layout == .invalidate
                reconfiguredCount += 1
            }
        }
        if !reloadIndexPaths.isEmpty {
            var snapshot = dataSource.snapshot()
            let reloadIdentities = reloadIndexPaths.compactMap {
                dataSource.itemIdentifier(for: $0)
            }
            if !reloadIdentities.isEmpty {
                snapshot.reloadItems(reloadIdentities)
                coordinator.enter()
                let didReloadBox = TableMainActorCallbackBox { coordinator.leave() }
                dataSource.apply(snapshot, animatingDifferences: animatingContent) {
                    didReloadBox.schedule()
                }
                if animatingContent {
                    transitionCount += reloadIdentities.count
                }
            }
        }
        return TableVisibleRefreshResult(
            reconfiguredCount: reconfiguredCount,
            reloadedCount: reloadedCount,
            transitionCount: transitionCount,
            needsLayoutInvalidation: needsLayoutInvalidation
        )
    }

    /// 按 transaction 决定是否动画触发 Table 自适应尺寸重测量。
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

    private func refreshVisibleSupplementariesIfNeeded(
        applyPlan: ListApplyPlan
    ) -> TableVisibleRefreshResult {
        guard let tableView else { return TableVisibleRefreshResult() }
        var reconfiguredCount = 0
        var needsLayoutInvalidation = false

        for sectionIndex in sections.indices {
            let header = refreshVisibleSupplementary(
                sections[sectionIndex].header,
                view: tableView.headerView(forSection: sectionIndex),
                sectionIndex: sectionIndex,
                applyPlan: applyPlan
            )
            let footer = refreshVisibleSupplementary(
                sections[sectionIndex].footer,
                view: tableView.footerView(forSection: sectionIndex),
                sectionIndex: sectionIndex,
                applyPlan: applyPlan
            )
            reconfiguredCount += header.reconfiguredCount + footer.reconfiguredCount
            needsLayoutInvalidation = needsLayoutInvalidation
                || header.needsLayoutInvalidation
                || footer.needsLayoutInvalidation
        }

        return TableVisibleRefreshResult(
            reconfiguredCount: reconfiguredCount,
            needsLayoutInvalidation: needsLayoutInvalidation
        )
    }

    private func refreshVisibleSupplementary(
        _ supplementary: AnyTableSectionSupplementary?,
        view: UITableViewHeaderFooterView?,
        sectionIndex: Int,
        applyPlan: ListApplyPlan
    ) -> TableVisibleRefreshResult {
        guard
            let supplementary,
            let view,
            let supplementarySnapshot = applyPlan.newSupplementariesByIdentity[supplementary.identity],
            let oldSupplementarySnapshot = applyPlan.oldSupplementariesByIdentity[supplementary.identity],
            !applyPlan.snapshotReloadSections.contains(supplementary.identity.sectionID),
            ListApplyPlanner.shouldRefreshVisibleSupplementary(
                supplementarySnapshot,
                oldSupplementary: oldSupplementarySnapshot
            )
        else { return TableVisibleRefreshResult() }

        let context = context(
            for: IndexPath(row: 0, section: sectionIndex),
            identity: supplementary.identity
        )
        supplementary.configureVisibleView(view, context)
        let needsLayoutInvalidation: Bool
        if case .supplementary(let rule) = supplementarySnapshot.refreshRule,
           rule.action == .reconfigureVisible(layout: .invalidate) {
            needsLayoutInvalidation = true
        } else {
            needsLayoutInvalidation = false
        }
        return TableVisibleRefreshResult(
            reconfiguredCount: 1,
            needsLayoutInvalidation: needsLayoutInvalidation
        )
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
    var reconfiguredCount = 0
    var reloadedCount = 0
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
    var visibleReconfiguredRowCount = 0
    var visibleReloadedRowCount = 0
    var visibleReconfiguredSupplementaryCount = 0
    var contentTransitionCount = 0
    var layoutInvalidated = false
    var layoutAnimated = false
    var scrollOutcome = TableScrollOutcome()
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
    /// 仅用于 Objective-C 消息转发的弱 delegate 快照。
    let value: AnyObject?

    /// 在 MainActor 上捕获 selector 对应的转发目标。
    @MainActor
    init(_ value: AnyObject?) {
        MainActor.preconditionIsolated()
        self.value = value
    }
}

/// UIKit/Dispatch completion 可能从非主队列触发；这个私有盒子只负责把回调重新排到 MainActor 执行。
private final class TableMainActorCallbackBox: @unchecked Sendable {
    /// 已在 MainActor 创建、只能回到主线程执行的原始回调。
    private let callback: () -> Void

    /// 捕获一个当前 MainActor 隔离的完成回调。
    @MainActor
    init(_ callback: @escaping () -> Void) {
        self.callback = callback
    }

    /// 从任意完成队列异步切回主队列，再恢复 MainActor 隔离。
    nonisolated func schedule() {
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated {
                callback()
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
