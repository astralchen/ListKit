import UIKit

// MARK: - Adapter

/// UICollectionView 列表适配器。
///
/// 适配器弱持有列表。列表释放后，新的更新和尚未提交的排队请求以
/// `.cancelledBeforeCommit` 结束；已经提交的更新仍由原 UIKit 完成回调收尾。
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
    /// `CollectionListAdapter` 会接管 `collectionView.delegate`，调用方需要
    /// `scrollViewDidScroll` 等回调时设置此属性。
    public weak var scrollDelegate: UIScrollViewDelegate?

    /// UIKit delegate 逃生口。ListKit 已处理的回调会先执行声明式 Row 行为，再转发到此对象；
    /// 其余可选 delegate 方法会通过 Objective-C forwarding 自动转发。选择或高亮回调
    /// 会参与 `.automatic` 交互能力推断。
    public weak var collectionDelegate: UICollectionViewDelegate? {
        didSet { configureSelectionBehavior() }
    }

    /// 原生 drag/drop 逃生口；设置后直接安装到 collection view。
    public weak var dragDelegate: UICollectionViewDragDelegate? {
        didSet { collectionView?.dragDelegate = dragDelegate }
    }
    /// 原生 drop delegate 逃生口；设置后直接安装到 collection view。
    public weak var dropDelegate: UICollectionViewDropDelegate? {
        didSet { collectionView?.dropDelegate = dropDelegate }
    }

    /// flow layout 回调转发对象。
    ///
    /// 仅用于仍在使用 `UICollectionViewDelegateFlowLayout` 的调用方；使用
    /// `makeCompositionalLayout()` 时通常不需要它。
    public weak var layoutDelegate: UICollectionViewDelegateFlowLayout?

    /// cell/supplementary 展示回调转发对象。
    public weak var displayDelegate: UICollectionViewDelegate?

    /// 最近一次 `apply` 的摘要。
    ///
    /// 同步 `apply` 提交后会先更新为 `.submitted` 摘要；snapshot、可见刷新、layout
    /// 和滚动处理完成后，会再次更新为最终摘要。DEBUG 下 ListKit 也会输出同一份
    /// summary，便于定位 diff、refreshID 和可见刷新问题。
    public private(set) var lastApplySummary = ListApplySummary()
    /// 最近一次 compositional layout provider/helper 产生的 diagnostics。
    public private(set) var lastLayoutDiagnostics: [ListDiagnosticsIssue] = []
    private(set) var layoutInvalidationGeneration = 0
    private(set) var outlineAnimationGeneration = 0

    /// adapter 管理的 collection view；弱持有以避免 view -> adapter -> view 环。
    private weak var collectionView: UICollectionView?
    /// 最近一次已接受 apply 的声明式 Section 描述树。
    private var sections: [ListSection<SectionID>] = []
    /// 用于判断 compositional layout 元数据是否变化的轻量签名。
    private var layoutSignature: [ListSectionLayoutSignature] = []
    /// 实际持有并提交 diffable snapshot 的 data source。
    private var dataSource: CollectionDiffableDataSource<SectionID>!
    /// 测试和内部生命周期用于判断全局 snapshot 是否仍在提交。
    var isApplyingSnapshot = false
    /// Collection 与 Table 共用同一套 mutation 排队、合并和 UIKit commit gate。
    private let mutationScheduler = ListMutationScheduler()
    private var mutationCoordinator: ListMutationCoordinator { mutationScheduler.coordinator }
    /// 当前描述树按 presentation identity 建立的 Row 查询表。
    private var rowsByIdentity: [AnyListIdentity: AnyListRow] = [:]
    /// 当前描述树按 element kind 和 Section 建立的 supplementary 查询表。
    private var supplementariesByKindAndSection: [SupplementaryKey: AnySupplementary] = [:]
    /// Cell 开始展示时捕获的 Row，确保结束展示回调不受后续 snapshot 复用影响。
    private var displayedRowsByCell: [ObjectIdentifier: AnyListRow] = [:]
    /// reusable view 开始展示时捕获的 supplementary 描述。
    private var displayedSupplementariesByView: [ObjectIdentifier: AnySupplementary] = [:]
    /// 预取开始时捕获的 Row，确保取消预取时仍回调原始对象。
    private var prefetchedRowsByIndexPath: [IndexPath: AnyListRow] = [:]
    /// 每次接受新 apply 时递增，用于拒绝旧异步 completion 写回状态。
    private var applyGeneration = 0
    /// 批量预取和取消预取的 adapter 级回调。
    private var prefetchItemsHandler: (@MainActor ([ListContext]) -> Void)?
    private var cancelPrefetchingItemsHandler: (@MainActor ([ListContext]) -> Void)?
    /// 多选上下文菜单请求的 adapter 级 provider。
    private var contextMenuItemsProvider: (@MainActor ([ListContext], CGPoint) -> UIContextMenuConfiguration?)?
    /// 当前已展示上下文菜单对应的 Row 和原始 index path。
    private var activeContextMenu: (row: AnyListRow, indexPath: IndexPath)?
    /// Section index title 到 Section identity 的稳定映射。
    private var indexTitleEntries: [CollectionIndexTitleEntry] = []
    /// 保持可见锚点时临时添加到 contentInset.bottom 的补偿量。
    private var preservedAnchorBottomInsetCompensation: CGFloat = 0
    /// 应用锚点补偿前调用方设置的原始 bottom inset。
    private var temporaryAnchorBaseBottomInset: CGFloat?
    /// 防止 UIKit 尚有未提交更新时重复安排 reloadAll 重试定时器。
    private var isReloadAllRetryScheduled = false
    /// 按事件类型保存 adapter 级处理闭包。
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
    ) -> ListApplySummary {
        _apply(options: options, completion: completion, content)
    }

    /// 提交一次列表更新，并立即返回提交摘要。
    @discardableResult
    public func apply(
        options: ListApplyOptions,
        @ListSectionBuilder<SectionID> _ content: () -> [ListSection<SectionID>]
    ) -> ListApplySummary {
        _apply(options: options, completion: nil, content)
    }

    /// 以 SwiftUI 风格的 transaction 提交更新。
    @discardableResult
    public func apply(
        transaction: ListTransaction = .automatic,
        completion: ((ListApplySummary) -> Void)? = nil,
        @ListSectionBuilder<SectionID> _ content: () -> [ListSection<SectionID>]
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
        @ListSectionBuilder<SectionID> _ content: () -> [ListSection<SectionID>]
    ) -> ListApplySummary {
        _apply(options: ListApplyOptions(transaction: transaction), completion: nil, content)
    }

    /// 提交已经构建好的 section 数组。
    @discardableResult
    public func apply(
        _ sections: [ListSection<SectionID>],
        options: ListApplyOptions,
        completion: ((ListApplySummary) -> Void)? = nil
    ) -> ListApplySummary {
        apply(options: options, completion: completion) { sections }
    }

    /// 以 transaction 提交已经构建好的 sections。
    @discardableResult
    public func apply(
        _ sections: [ListSection<SectionID>],
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
    /// 此方法不依赖 Row 或 supplementary 的 `identity`、`refreshID` 和刷新策略，
    /// 并始终同步失效布局。适用于语言、LTR/RTL、Dynamic Type、主题等未进入
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
        guard collectionView != nil else {
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
    ///   - layout: 重配完成后是否由 ListKit 主动请求布局重测量。
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
    ///   - layout: 重配后是否主动请求布局重测量。
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

    /// 使用 diffable `reloadSections` 刷新指定 Section。
    ///
    /// Section reload 会同时刷新其中的 Row 和 supplementary；不存在或重复的
    /// section id 会被安全忽略。
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

    /// 执行一次描述树提交；coordinator 忙碌时保存描述树并返回初始 `.submitted` 摘要。
    private func _apply(
        options: ListApplyOptions,
        subscriberID: UUID? = nil,
        completion: ((ListApplySummary) -> Void)?,
        @ListSectionBuilder<SectionID> _ content: () -> [ListSection<SectionID>]
    ) -> ListApplySummary {
        // 只在本次同步提交期间强持有视图；不把页面生命周期延长到异步动画完成后。
        guard let collectionView else {
            return cancelApplyBeforeCommit(transaction: options.transaction, completion: completion)
        }
        let newSections = content()
        let resolvedTransaction = options.transaction.resolved(
            reduceMotionEnabled: UIAccessibility.isReduceMotionEnabled
        )
        let diagnosticsIssues = ListDiagnostics.validate(newSections)
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

        let newLayoutSignature = Self.makeLayoutSignature(from: newSections)
        var shouldInvalidateLayout = options.applicationMode == .reloadData
            || layoutSignature != newLayoutSignature
        let applyPlan = ListApplyPlanner.makePlan(
            old: Self.makeCoreSnapshots(from: sections),
            new: Self.makeCoreSnapshots(from: newSections),
            options: options,
            diagnosticsIssues: diagnosticsIssues
        )
        shouldInvalidateLayout = shouldInvalidateLayout
            || !applyPlan.snapshotLayoutInvalidationItems.isEmpty
        let previousDataSourceSnapshot = dataSource.snapshot()
        let previousOutlineStates: [AnyListID: ListOutlineExpansionState] = Dictionary(
            uniqueKeysWithValues: newSections.compactMap { section -> (AnyListID, ListOutlineExpansionState)? in
            let sectionID = AnyListID(section.id)
            guard section.hasOutlineHierarchy,
                  previousDataSourceSnapshot.sectionIdentifiers.contains(sectionID) else { return nil }
            let snapshot = dataSource.snapshot(for: sectionID)
            return (sectionID, ListOutlineExpansionState(
                existingItems: Set(snapshot.items),
                expandedItems: Set(snapshot.items.filter { snapshot.isExpanded($0) })
            ))
            }
        )
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
            return summary
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
        let selectedItemIdentities = captureSelectedItemIdentities()

        applyGeneration += 1
        let generation = applyGeneration
        sections = newSections
        layoutSignature = newLayoutSignature
        rebuildLookupTables(in: collectionView)
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

        // planner 已保证 action 分组互斥；这里再次与新 snapshot 求交集，避免对已由
        // 结构 diff 删除的 identity 调用 reconfigureItems 或 reloadItems。
        let snapshotItems = Set(snapshot.itemIdentifiers)
        let reconfigureItems = applyPlan.snapshotReconfigureItems.filter(snapshotItems.contains)
        let reloadItems = applyPlan.snapshotReloadItems.filter(snapshotItems.contains)
        let snapshotSectionIDs = Set(snapshot.sectionIdentifiers)
        let reloadSections = applyPlan.snapshotReloadSections.filter(snapshotSectionIDs.contains)
        if !reconfigureItems.isEmpty {
            snapshot.reconfigureItems(reconfigureItems)
        }
        if !reloadItems.isEmpty {
            snapshot.reloadItems(reloadItems)
        }
        if !reloadSections.isEmpty {
            snapshot.reloadSections(reloadSections)
        }

        let summary = applyPlan.initialSummary.replacingAnimation(
            ListAnimationSummary(reduceMotionApplied: resolvedTransaction.reduceMotionApplied)
        )
        lastApplySummary = summary
        ListApplyLogger.logDiagnostics(issues: diagnosticsIssues, options: options)

        let completeAsSuperseded: @MainActor () -> Void = {
            let supersededSummary = summary.replacingAnimation(
                ListAnimationSummary(
                    completionState: .superseded,
                    reduceMotionApplied: resolvedTransaction.reduceMotionApplied
                )
            )
            ListApplyLogger.logApplySummary(supersededSummary, options: options)
            completion?(supersededSummary)
        }

        isApplyingSnapshot = true
        let mutationToken = mutationCoordinator.begin(
            kind: .apply,
            updatePolicy: resolvedTransaction.updatePolicy
        )
        let completionBox = completion.map(ListApplySummaryCompletionBox.init)
        let finishAsSuperseded: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            self.isApplyingSnapshot = false
            self.mutationCoordinator.finish(mutationToken)
            completeAsSuperseded()
            self.performNextPendingMutationIfNeeded()
        }
        let finishApply: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            guard self.applyGeneration == generation, !mutationToken.isSuperseded else {
                finishAsSuperseded()
                return
            }
            self.isApplyingSnapshot = false
            self.restoreSelection(for: selectedItemIdentities)
            self.synchronizeControlledSelection()
            self.reconcileSelection()
            let metrics = CollectionApplyAnimationMetrics()
            let completeAnimation = {
                guard self.applyGeneration == generation, !mutationToken.isSuperseded else {
                    finishAsSuperseded()
                    return
                }
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
                        outlineAnimatedSectionCount: resolvedTransaction.outlineAnimation
                            ? outlineSectionsNeedingAnimation.count
                            : 0,
                        contentTransitionCount: metrics.contentTransitionCount,
                        layoutInvalidated: metrics.layoutInvalidated,
                        layoutAnimated: metrics.layoutAnimated,
                        scrollAnimated: metrics.scrollOutcome.animated,
                        anchorCompensation: metrics.scrollOutcome.anchorCompensation,
                        reduceMotionApplied: resolvedTransaction.reduceMotionApplied
                    )
                )
                self.lastApplySummary = completedSummary
                ListApplyLogger.logApplySummary(completedSummary, options: options)
                self.mutationCoordinator.finish(mutationToken)
                completionBox?.call(with: completedSummary)
                self.performNextPendingMutationIfNeeded()
            }
            let finalAnimationBox = ListMainActorCallbackBox(completeAnimation)
            let animationCoordinator = ListAnimationCompletionCoordinator {
                finalAnimationBox.call()
            }

            self.rebindVisibleSupplementaryTapHandlers()
            metrics.layoutInvalidated = shouldInvalidateLayout
            if applyPlan.shouldRunVisibleRefresh {
                let refresh = self.refreshVisibleRowsIfNeeded(
                    applyPlan: applyPlan,
                    animatingContent: resolvedTransaction.contentAnimation,
                    coordinator: animationCoordinator
                )
                let supplementaryRefresh = self.refreshVisibleSupplementariesIfNeeded(
                    applyPlan: applyPlan
                )
                metrics.visibleReconfiguredRowCount = refresh.reconfiguredCount
                metrics.visibleReloadedRowCount = refresh.reloadedCount
                metrics.contentTransitionCount = refresh.transitionCount
                metrics.visibleReconfiguredSupplementaryCount = supplementaryRefresh.reconfiguredCount
                metrics.layoutInvalidated = metrics.layoutInvalidated
                    || refresh.needsLayoutInvalidation
                    || supplementaryRefresh.needsLayoutInvalidation
            }
            let performFinalScroll = {
                metrics.scrollOutcome = self.performScrollBehavior(
                    resolvedTransaction.scrollBehavior,
                    visibleAnchor: visibleAnchor,
                    animated: resolvedTransaction.scrollAnimation
                )
            }
            if metrics.layoutInvalidated {
                animationCoordinator.enter()
                self.performLayoutUpdate(
                    invalidating: true,
                    animated: resolvedTransaction.layoutAnimation
                ) { layoutAnimated in
                    metrics.layoutAnimated = layoutAnimated
                    performFinalScroll()
                    animationCoordinator.leave()
                }
            } else {
                performFinalScroll()
            }
            animationCoordinator.finishScheduling()
        }
        let finishApplyBox = ListMainActorCallbackBox(finishApply)
        // UIKit 可能在全局 snapshot apply 尚未完全退出内部 diff 栈时调用 completion。
        // 将 outline 阶段延迟到新的 MainActor turn，避免重入提交 section snapshot。
        let didApplyBox = ListMainActorCallbackBox { [weak self] in
            guard let self else { return }
            guard self.applyGeneration == generation else {
                finishApplyBox.call()
                return
            }
            self.applyOutlineSnapshots(
                generation: generation,
                previousExpansionStates: previousOutlineStates,
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
            diagnosticsIssues: ListDiagnostics.validate(sections)
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
        guard collectionView != nil else {
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
        let visibleIdentities = Set(collectionView?.indexPathsForVisibleItems.compactMap { row(at: $0)?.identity } ?? [])
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
            ListMainActorCallbackBox { [weak self] in
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
        let didRefreshBox = ListMainActorCallbackBox { [weak self] in
            guard let self, invalidatesLayout else {
                finish()
                return
            }
            self.performLayoutUpdate(
                invalidating: true,
                animated: resolvedTransaction.layoutAnimation,
                completion: { _ in finish() }
            )
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

    /// 定向 `.visible` 刷新直接操作当前 Cell，不构造虚假的 diffable item mutation。
    private func refreshVisibleRows(
        _ subscribers: [ListRowRefreshSubscriber],
        matchedBySubscriber: [Set<AnyListIdentity>],
        resolvedActions: [AnyListIdentity: ListRowRefreshAction],
        transaction: ListTransaction
    ) -> ListRefreshSummary {
        guard let collectionView else {
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
            self.performLayoutUpdate(
                invalidating: needsLayoutInvalidation,
                animated: resolvedTransaction.layoutAnimation
            ) { layoutAnimated in
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
        }
        for (identity, action) in resolvedActions {
            guard
                let indexPath = dataSource.indexPath(for: identity),
                let row = rowsByIdentity[identity],
                let cell = collectionView.cellForItem(at: indexPath)
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
                let didReloadBox = ListMainActorCallbackBox {
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
        guard collectionView != nil else {
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
            ListMainActorCallbackBox { [weak self] in
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

        let outlineApplications = orderedRefreshSectionIDs.compactMap { sectionID -> ListOutlineSnapshotApplication? in
            guard sections.contains(where: {
                AnyListID($0.id) == sectionID && $0.hasOutlineHierarchy
            }) else { return nil }
            return ListOutlineSnapshotApplication(
                sectionID: sectionID,
                snapshot: dataSource.snapshot(for: sectionID),
                animatingDifferences: false
            )
        }
        snapshot.reloadSections(orderedRefreshSectionIDs)
        let mutationToken = mutationCoordinator.begin(
            kind: .sectionReload,
            updatePolicy: transaction.updatePolicy
        )
        let resolvedTransaction = transaction.resolved(
            reduceMotionEnabled: UIAccessibility.isReduceMotionEnabled
        )
        let finishRefresh: @MainActor () -> Void = { [weak self] in
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
            self.rebindVisibleSupplementaryTapHandlers()
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
        let didRefreshBox = ListMainActorCallbackBox { [weak self] in
            guard let self else {
                finishRefresh()
                return
            }
            guard !outlineApplications.isEmpty else {
                finishRefresh()
                return
            }
            self.applyOutlineSnapshots(
                outlineApplications,
                at: 0,
                generation: self.applyGeneration,
                completion: finishRefresh
            )
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

        guard let collectionView else {
            let completedSummary = applyPlan.completedSummary(
                visibleReconfiguredRowCount: 0,
                visibleReloadedRowCount: 0,
                visibleReconfiguredSupplementaryCount: 0,
                animation: ListAnimationSummary(
                    completionState: .completed,
                    reduceMotionApplied: resolvedTransaction.reduceMotionApplied
                )
            )
            lastApplySummary = completedSummary
            ListApplyLogger.logApplySummary(completedSummary, options: options)
            request.completion?(completedSummary)
            performNextPendingMutationIfNeeded()
            return
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
        let selectedItemIdentities = captureSelectedItemIdentities()

        applyGeneration += 1
        let generation = applyGeneration
        isApplyingSnapshot = true
        let mutationToken = mutationCoordinator.begin(
            kind: .reloadAll,
            updatePolicy: request.transaction.updatePolicy
        )
        let metrics = CollectionApplyAnimationMetrics()

        let completeAsSuperseded = {
            let supersededSummary = summary.replacingAnimation(
                ListAnimationSummary(
                    completionState: .superseded,
                    reduceMotionApplied: resolvedTransaction.reduceMotionApplied
                )
            )
            ListApplyLogger.logApplySummary(supersededSummary, options: options)
            request.completion?(supersededSummary)
        }

        let completeReload = { [weak self] (layoutAnimated: Bool, transitionCount: Int) in
            guard let self else { return }
            guard self.applyGeneration == generation else {
                completeAsSuperseded()
                return
            }

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
            ListApplyLogger.logApplySummary(completedSummary, options: options)
            request.completion?(completedSummary)
            self.performNextPendingMutationIfNeeded()
        }

        let finishReloadedLayout = { [weak self] in
            guard let self else { return }
            guard self.applyGeneration == generation else { return }
            self.restoreSelection(for: selectedItemIdentities)
            self.synchronizeControlledSelection()
            self.reconcileSelection()
            self.rebindVisibleSupplementaryTapHandlers()
            metrics.visibleReconfiguredRowCount = collectionView.indexPathsForVisibleItems.count
            metrics.visibleReconfiguredSupplementaryCount = self.visibleSupplementaryTargets().count
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
                with: collectionView,
                duration: opacityDuration,
                options: [.transitionCrossDissolve, .beginFromCurrentState, .allowAnimatedContent]
            ) {
                self.performSynchronousReloadMutation {
                    self.layoutInvalidationGeneration += 1
                    collectionView.reloadData()
                    collectionView.collectionViewLayout.invalidateLayout()
                    collectionView.layoutIfNeeded()
                    finishReloadedLayout()
                }
            } completion: { _ in
                completeReload(false, 1)
            }
            isApplyingSnapshot = false
        } else {
            performSynchronousReloadMutation {
                collectionView.reloadData()
                layoutInvalidationGeneration += 1
                UIView.performWithoutAnimation {
                    collectionView.collectionViewLayout.invalidateLayout()
                    collectionView.layoutIfNeeded()
                }
                finishReloadedLayout()
            }
            isApplyingSnapshot = false
            completeReload(false, 0)
        }
    }

    private func performSynchronousReloadMutation(_ mutation: () -> Void) {
        mutation()
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
        guard let collectionView else {
            mutationScheduler.cancelPendingRequests()
            return
        }
        let hasUncommittedUpdates = collectionView.hasUncommittedUpdates
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

    /// 重建描述树并等待 snapshot、outline、layout 和内容过渡完成。
    @discardableResult
    public func apply(
        options: ListApplyOptions,
        @ListSectionBuilder<SectionID> _ content: () -> [ListSection<SectionID>]
    ) async -> ListApplySummary {
        guard collectionView != nil else {
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

    /// 提交 transaction，并等待 snapshot、outline、layout 和内容过渡完成。
    @discardableResult
    public func apply(
        transaction: ListTransaction = .automatic,
        @ListSectionBuilder<SectionID> _ content: () -> [ListSection<SectionID>]
    ) async -> ListApplySummary {
        await apply(options: ListApplyOptions(transaction: transaction), content)
    }

    /// 绑定自定义列表事件。
    ///
    /// 事件可以从 row、header 或 footer 的 configure 闭包中通过 `context.send(...)`
    /// 发出，再由调用方在 adapter 上集中处理。
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

    // MARK: - UIKit Protocol Witnesses

    // 以下公开方法实现 UICollectionView data source、delegate、prefetch 与 scroll
    // delegate 契约。方法签名沿用 UIKit 文档；注释重点放在 ListKit 增加的 identity
    // 解析、生命周期捕获、事件转发和 selection 同步逻辑上，避免重复解释系统参数。

    /// 返回当前已接受描述树中的 Section 数量。
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
        guard let row = row(at: indexPath) else { return false }
        let allowsListKitHighlight = row.hasAutomaticHighlightIntent
            || (!row.isSelectionDisabled && selectionMode(at: indexPath) != .none)
        guard allowsListKitHighlight || collectionDelegateHasHighlightIntent else { return false }
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
        guard
            sections[safe: indexPath.section]?.allowsMultipleSelectionInteraction == true,
            selectionMode(at: indexPath) == .multiple,
            row(at: indexPath)?.isSelectionDisabled != true
        else { return false }
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

    /// 返回指定 section index 当前对应的 section id。
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

    /// 返回指定 section 当前的 row 数量。
    ///
    /// - Parameter sectionID: 要查询的 section id。
    /// - Returns: section 内 row 数量；不存在时返回 0。
    public func itemCount(in sectionID: SectionID) -> Int {
        sections.first { $0.id == sectionID }?.rows.count ?? 0
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
            let itemIndex = sections[sectionIndex].rows.firstIndex(where: { $0.identity == identity })
        else { return nil }
        return IndexPath(item: itemIndex, section: sectionIndex)
    }

    /// 判断当前描述树是否仍包含指定展示身份。
    public func contains(_ identity: AnyListIdentity) -> Bool {
        indexPath(for: identity) != nil
    }

    /// 根据 row id 查询当前 indexPath。
    ///
    /// - Parameters:
    ///   - rowID: row 的稳定 id。
    ///   - sectionID: 可选的 section id；为 `nil` 时查询所有 section。
    /// - Returns: 当前描述树中匹配 row id 的 index paths。
    /// - Note: 查询基于 adapter 当前描述树，调用方不需要维护第二套 sections。
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
    ///   - sectionID: 可选的 section id；为 `nil` 时滚动到全列表最后一项。
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

    /// 轻量重配当前可见 supplementary view。
    ///
    /// - Parameters:
    ///   - kind: supplementary element kind。
    ///   - sectionID: 可选的 section id；为 `nil` 时匹配所有 section。
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
    ///   - rowID: row 的稳定 id。
    ///   - sectionID: 可选的 section id；为 `nil` 时匹配所有 section。
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
    ///   - configuration: compositional layout 的全局 Section 间距和 content inset 配置。
    ///   - fallback: legacy `layoutID` section 使用的 layout provider。
    ///   - diagnostics: layout provider 期间发现前置条件不满足时的处理方式。
    /// - Returns: 可直接赋值给 collection view 的 compositional layout。
    /// - Note: 调用方仍需显式把返回的 layout 赋给 `collectionView.collectionViewLayout`。
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
    /// - Parameters:
    ///   - sectionIndex: 当前 layout provider 请求的 section index。
    ///   - diagnostics: Section 描述无法生成布局时的诊断处理方式。
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
        ListApplyLogger.logDiagnostics(issues: issues, options: options)

        if options.mode == .assertion {
            assertionFailure(issues.map(\.message).joined(separator: "\n"))
        }
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

    private func rebuildLookupTables(in collectionView: UICollectionView) {
        rowsByIdentity = [:]
        supplementariesByKindAndSection = [:]

        for section in sections {
            let sectionID = AnyListID(section.id)
            for row in section.rows {
                row.register(collectionView)
                rowsByIdentity[row.identity] = row
            }
            for supplementary in section.supplementaries {
                supplementary.register(collectionView)
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
        previousExpansionStates: [AnyListID: ListOutlineExpansionState],
        animatedSectionIDs: Set<AnyListID>,
        completion: @escaping @MainActor () -> Void
    ) {
        let applications = sections.compactMap { section -> ListOutlineSnapshotApplication? in
            guard section.hasOutlineHierarchy else { return nil }
            let sectionID = AnyListID(section.id)
            let snapshot = Self.makeOutlineSnapshot(
                from: section.outlineRoots,
                previousExpansionState: previousExpansionStates[sectionID]
            )
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
        from roots: [AnyListOutlineNode],
        previousExpansionState: ListOutlineExpansionState? = nil
    ) -> NSDiffableDataSourceSectionSnapshot<AnyListIdentity> {
        var snapshot = NSDiffableDataSourceSectionSnapshot<AnyListIdentity>()

        func append(_ nodes: [AnyListOutlineNode], to parent: AnyListIdentity?) {
            let identities = nodes.map { $0.row.identity }
            snapshot.append(identities, to: parent)
            for node in nodes where !node.children.isEmpty {
                append(node.children, to: node.row.identity)
                let identity = node.row.identity
                let shouldExpand: Bool
                if let previousExpansionState,
                   previousExpansionState.existingItems.contains(identity) {
                    shouldExpand = previousExpansionState.expandedItems.contains(identity)
                } else {
                    shouldExpand = node.isExpanded
                }
                if shouldExpand { snapshot.expand([identity]) }
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
                        refreshRule: .row(row.refreshRule),
                        role: .row
                    )
                },
                supplementaries: section.supplementaries.map { supplementary in
                    ListNodeSnapshot(
                        identity: supplementary.identity,
                        refreshID: supplementary.refreshID,
                        refreshRule: .supplementary(supplementary.refreshRule),
                        role: .supplementary
                    )
                }
            )
        }
    }

    /// 按 transaction 决定是否动画执行 Collection 布局失效，并报告动画是否完成。
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

    /// 根据 planner policy/action 重配或 reload 当前可见 Row，并汇总布局需求。
    private func refreshVisibleRowsIfNeeded(
        applyPlan: ListApplyPlan,
        animatingContent: Bool,
        coordinator: ListAnimationCompletionCoordinator
    ) -> ListVisibleRefreshResult {
        guard let collectionView else { return ListVisibleRefreshResult() }
        var reconfiguredCount = 0
        var reloadedCount = 0
        var transitionCount = 0
        var needsLayoutInvalidation = false
        var reloadIndexPaths: [IndexPath] = []
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard
                let row = row(at: indexPath),
                let rowSnapshot = applyPlan.newRowsByIdentity[row.identity],
                let oldRowSnapshot = applyPlan.oldRowsByIdentity[row.identity],
                !applyPlan.snapshotReloadSections.contains(row.identity.sectionID),
                ListApplyPlanner.shouldRefreshVisibleRow(
                    rowSnapshot,
                    oldRow: oldRowSnapshot
                )
            else { continue }

            if let cell = collectionView.cellForItem(at: indexPath) {
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
        }
        if !reloadIndexPaths.isEmpty {
            var snapshot = dataSource.snapshot()
            let reloadIdentities = reloadIndexPaths.compactMap {
                dataSource.itemIdentifier(for: $0)
            }
            if !reloadIdentities.isEmpty {
                snapshot.reloadItems(reloadIdentities)
                coordinator.enter()
                let didReloadBox = ListMainActorCallbackBox { coordinator.leave() }
                dataSource.apply(snapshot, animatingDifferences: animatingContent) {
                    didReloadBox.schedule()
                }
                if animatingContent {
                    transitionCount += reloadIdentities.count
                }
            }
        }
        return ListVisibleRefreshResult(
            reconfiguredCount: reconfiguredCount,
            reloadedCount: reloadedCount,
            transitionCount: transitionCount,
            needsLayoutInvalidation: needsLayoutInvalidation
        )
    }

    private func refreshVisibleSupplementariesIfNeeded(
        applyPlan: ListApplyPlan
    ) -> ListVisibleRefreshResult {
        var reconfiguredCount = 0
        var needsLayoutInvalidation = false
        for target in visibleSupplementaryTargets() {
            guard
                let supplementary = supplementary(kind: target.kind, at: target.indexPath),
                let supplementarySnapshot = applyPlan.newSupplementariesByIdentity[supplementary.identity],
                let oldSupplementarySnapshot = applyPlan.oldSupplementariesByIdentity[supplementary.identity],
                !applyPlan.snapshotReloadSections.contains(supplementary.identity.sectionID),
                ListApplyPlanner.shouldRefreshVisibleSupplementary(
                    supplementarySnapshot,
                    oldSupplementary: oldSupplementarySnapshot
                )
            else { continue }

            reconfiguredCount += reconfigureVisibleSupplementary(target, supplementary: supplementary)
            if case .supplementary(let rule) = supplementarySnapshot.refreshRule,
               rule.action == .reconfigureVisible(layout: .invalidate) {
                needsLayoutInvalidation = true
            }
        }
        return ListVisibleRefreshResult(
            reconfiguredCount: reconfiguredCount,
            needsLayoutInvalidation: needsLayoutInvalidation
        )
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
        let context = context(for: target.indexPath, identity: supplementary.identity)
        guard let configureVisibleView = supplementary.configureVisibleView else { return 0 }
        configureVisibleView(target.view, context)
        return 1
    }

    private func rebindVisibleSupplementaryTapHandlers() {
        for target in visibleSupplementaryTargets() {
            guard let supplementary = supplementary(kind: target.kind, at: target.indexPath) else { continue }
            let context = context(for: target.indexPath, identity: supplementary.identity)
            ListTapHandlerInstaller.install(
                on: target.view,
                context: context,
                handler: supplementary.tapHandler
            )
        }
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
        let selectionSections = sections.compactMap { section -> (ListSection<SectionID>, ResolvedListSelectionMode)? in
            let mode = selectionMode(for: section)
            return mode == .none ? nil : (section, mode)
        }
        let allowsRowSelection = sections.contains(where: sectionAllowsUserSelection)
        let allowsHighlight = collectionDelegateHasHighlightIntent
            || sections.contains { $0.rows.contains(where: \.hasAutomaticHighlightIntent) }
        collectionView.allowsSelection = allowsRowSelection || allowsHighlight
        collectionView.allowsMultipleSelection = selectionSections.contains { $0.1 == .multiple }
            || selectionSections.count > 1
    }

    private func captureSelectedItemIdentities() -> [AnyListIdentity] {
        guard let collectionView else { return [] }
        return (collectionView.indexPathsForSelectedItems ?? []).compactMap {
            dataSource.itemIdentifier(for: $0)
        }
    }

    private func restoreSelection(for identities: [AnyListIdentity]) {
        guard let collectionView else { return }
        for identity in identities {
            guard
                rowsByIdentity[identity]?.isSelected == nil,
                let indexPath = dataSource.indexPath(for: identity)
            else { continue }
            collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
        }
    }

    private func synchronizeControlledSelection() {
        guard let collectionView else { return }
        for section in sections {
            for row in section.rows {
                guard
                    let isSelected = row.isSelected,
                    let indexPath = dataSource.indexPath(for: row.identity)
                else { continue }
                if isSelected, selectionMode(at: indexPath) != .none {
                    collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
                } else {
                    collectionView.deselectItem(at: indexPath, animated: false)
                }
            }
        }
    }

    private func reconcileSelection() {
        guard let collectionView else { return }
        let selectedIndexPaths = (collectionView.indexPathsForSelectedItems ?? []).sorted {
            if $0.section != $1.section { return $0.section < $1.section }
            let lhsIsControlled = row(at: $0)?.isSelected == true
            let rhsIsControlled = row(at: $1)?.isSelected == true
            if lhsIsControlled != rhsIsControlled { return lhsIsControlled }
            return $0.item < $1.item
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

    private func selectionMode(for section: ListSection<SectionID>) -> ResolvedListSelectionMode {
        section.selectionMode.resolved(
            automaticSelectionEnabled: collectionDelegateHasSelectionIntent
                || section.rows.contains { $0.hasAutomaticSelectionIntent }
        )
    }

    private func selectionMode(at indexPath: IndexPath) -> ResolvedListSelectionMode {
        guard let section = sections[safe: indexPath.section] else { return .none }
        return section.selectionMode.resolved(
            automaticSelectionEnabled: collectionDelegateHasSelectionIntent
                || row(at: indexPath)?.hasAutomaticSelectionIntent == true
        )
    }

    private func sectionAllowsUserSelection(_ section: ListSection<SectionID>) -> Bool {
        switch section.selectionMode {
        case .automatic:
            return section.rows.contains { row in
                !row.isSelectionDisabled
                    && (row.hasAutomaticSelectionIntent || collectionDelegateHasSelectionIntent)
            }
        case .none:
            return false
        case .single, .multiple:
            return true
        }
    }

    private var collectionDelegateHasSelectionIntent: Bool {
        collectionDelegateResponds(to: #selector(UICollectionViewDelegate.collectionView(_:shouldSelectItemAt:)))
            || collectionDelegateResponds(to: #selector(UICollectionViewDelegate.collectionView(_:didSelectItemAt:)))
            || collectionDelegateResponds(to: #selector(UICollectionViewDelegate.collectionView(_:shouldDeselectItemAt:)))
            || collectionDelegateResponds(to: #selector(UICollectionViewDelegate.collectionView(_:didDeselectItemAt:)))
    }

    private var collectionDelegateHasHighlightIntent: Bool {
        collectionDelegateResponds(to: #selector(UICollectionViewDelegate.collectionView(_:shouldHighlightItemAt:)))
            || collectionDelegateResponds(to: #selector(UICollectionViewDelegate.collectionView(_:didHighlightItemAt:)))
            || collectionDelegateResponds(to: #selector(UICollectionViewDelegate.collectionView(_:didUnhighlightItemAt:)))
    }

    private func collectionDelegateResponds(to selector: Selector) -> Bool {
        collectionDelegate?.responds(to: selector) == true
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
    var reconfiguredCount = 0
    var reloadedCount = 0
    var transitionCount = 0
    var needsLayoutInvalidation = false
}

private struct ListScrollOutcome {
    var animated = false
    var anchorCompensation: CGFloat = 0
}

@MainActor
private final class CollectionApplyAnimationMetrics {
    var visibleReconfiguredRowCount = 0
    var visibleReloadedRowCount = 0
    var visibleReconfiguredSupplementaryCount = 0
    var contentTransitionCount = 0
    var layoutInvalidated = false
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

private struct ListOutlineExpansionState: Sendable {
    let existingItems: Set<AnyListIdentity>
    let expandedItems: Set<AnyListIdentity>
}

/// UIKit/Dispatch completion 可能从非主队列触发；这个私有盒子只负责把回调重新排到 MainActor 执行。
private final class ListMainActorCallbackBox: @unchecked Sendable {
    /// 已在 MainActor 创建、只能回到主线程执行的原始回调。
    private let callback: () -> Void

    /// 捕获一个当前 MainActor 隔离的完成回调。
    @MainActor
    init(_ callback: @escaping () -> Void) {
        self.callback = callback
    }

    /// 已位于 MainActor 时立即调用回调。
    @MainActor func call() {
        callback()
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

/// 将 apply 的外部结果回调安全保存在 MainActor 上，避免跨 UIKit completion 发送闭包。
private final class ListApplySummaryCompletionBox: @unchecked Sendable {
    private let callback: (ListApplySummary) -> Void

    @MainActor
    init(_ callback: @escaping (ListApplySummary) -> Void) {
        self.callback = callback
    }

    @MainActor
    func call(with summary: ListApplySummary) {
        callback(summary)
    }
}

private final class ListUnsafeForwardingTarget: @unchecked Sendable {
    /// 仅用于 Objective-C 消息转发的弱 delegate 快照。
    let value: AnyObject?

    /// 在 MainActor 上捕获 selector 对应的转发目标。
    @MainActor
    init(_ value: AnyObject?) {
        MainActor.preconditionIsolated()
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
