// MARK: - Shared Apply Core

enum ListNodeRole: Hashable, Sendable {
    case row
    case supplementary
}

/// Planner 使用的最小节点快照，不保留 Cell provider 或 UIKit 对象。
struct ListNodeSnapshot: Sendable {
    /// 包含 Section、Row 和展示变体的稳定 identity。
    let identity: AnyListIdentity
    /// 用于判断内容是否发生可刷新变化的调用方标识。
    let refreshID: AnyListID?
    /// 决定 apply 期间何时触发刷新。
    let refreshPolicy: RowRefreshPolicy
    /// 决定触发后执行 reconfigure、布局重测量还是 reload。
    let refreshAction: ListRefreshAction
    /// 区分普通 Row 与 supplementary，避免两类节点共用刷新规则。
    let role: ListNodeRole

    init(
        identity: AnyListIdentity,
        refreshID: AnyListID?,
        refreshPolicy: RowRefreshPolicy,
        refreshAction: ListRefreshAction = .reconfigure(layout: .none),
        role: ListNodeRole
    ) {
        self.identity = identity
        self.refreshID = refreshID
        self.refreshPolicy = refreshPolicy
        self.refreshAction = refreshAction
        self.role = role
    }
}

/// 一个 Section 在 planner 中参与 diff 和刷新判断的不可变输入。
struct ListSectionSnapshot: Sendable {
    /// Section 在跨次 apply 中保持稳定的类型擦除 identity。
    let sectionID: AnyListID
    /// Section 内参与结构 diff 和自动刷新的 Row 节点。
    let rows: [ListNodeSnapshot]
    /// Section 内参与 refreshID 比较的 supplementary 节点。
    let supplementaries: [ListNodeSnapshot]
}

/// 一次 apply 的结构差异、刷新分组和观测摘要。
struct ListApplyPlan {
    /// Diagnostics 是否允许继续向 diffable data source 提交 snapshot。
    let shouldApplyDiffable: Bool
    /// 使用 `reconfigureItems` 且不要求 ListKit 主动重测量的 identity。
    let snapshotReconfigureItems: [AnyListIdentity]
    /// reconfigure 完成后还需要主动重测量布局的 identity。
    let snapshotLayoutInvalidationItems: [AnyListIdentity]
    /// 使用 `reloadItems` 进入完整 configuration 路径的 identity。
    let snapshotReloadItems: [AnyListIdentity]
    /// snapshot 提交后是否还需检查当前可见 Row 的 policy。
    let shouldRunVisibleRefresh: Bool
    /// 内容或顺序发生变化、需要计入 snapshot 动画的 Section 数量。
    let changedSectionCount: Int
    /// mutation 刚提交时即可返回的 `.submitted` 摘要。
    let initialSummary: ListApplySummary
    /// 新旧节点索引供 adapter 的可见刷新和 supplementary 重配阶段查询。
    let oldRowsByIdentity: [AnyListIdentity: ListNodeSnapshot]
    let newRowsByIdentity: [AnyListIdentity: ListNodeSnapshot]
    let oldSupplementariesByIdentity: [AnyListIdentity: ListNodeSnapshot]
    let newSupplementariesByIdentity: [AnyListIdentity: ListNodeSnapshot]

    /// 是否存在需要 diffable snapshot 处理的结构或内容变化。
    var hasSnapshotChanges: Bool {
        initialSummary.insertedSectionCount > 0
            || initialSummary.deletedSectionCount > 0
            || initialSummary.movedSectionCount > 0
            || initialSummary.insertedRowCount > 0
            || initialSummary.deletedRowCount > 0
            || initialSummary.movedRowCount > 0
            || initialSummary.snapshotRefreshCount > 0
    }

    /// 将执行阶段收集到的可见刷新和动画指标合并成最终摘要。
    func completedSummary(
        visibleRefreshCount: Int,
        visibleSupplementaryRefreshCount: Int,
        animation: ListAnimationSummary = ListAnimationSummary(completionState: .completed)
    ) -> ListApplySummary {
        ListApplySummary(
            insertedSectionCount: initialSummary.insertedSectionCount,
            deletedSectionCount: initialSummary.deletedSectionCount,
            movedSectionCount: initialSummary.movedSectionCount,
            keptSectionCount: initialSummary.keptSectionCount,
            insertedRowCount: initialSummary.insertedRowCount,
            deletedRowCount: initialSummary.deletedRowCount,
            movedRowCount: initialSummary.movedRowCount,
            keptRowCount: initialSummary.keptRowCount,
            refreshIDChangedCount: initialSummary.refreshIDChangedCount,
            snapshotRefreshCount: initialSummary.snapshotRefreshCount,
            visibleRefreshCount: visibleRefreshCount,
            supplementaryRefreshIDChangedCount: initialSummary.supplementaryRefreshIDChangedCount,
            visibleSupplementaryRefreshCount: visibleSupplementaryRefreshCount,
            diagnosticsIssues: initialSummary.diagnosticsIssues,
            animation: animation
        )
    }
}

/// 等待 coordinator 执行的全量刷新请求。
struct ListReloadAllRequest {
    /// 全量刷新使用的 mutation 调度与动画配置。
    let transaction: ListTransaction
    /// reloadData 后重配可见内容时使用的过渡方式。
    let transition: ListContentTransition
    /// 内部状态、布局和滚动锚点恢复后调用的最终回调。
    let completion: ((ListApplySummary) -> Void)?
}

/// 在一个 adapter 内串行化所有会提交 UIKit 列表状态的 mutation。
@MainActor
final class ListMutationCoordinator {
    /// 标识当前唯一正在执行的 UIKit mutation，并记录其是否被后续请求逻辑取代。
    final class Token {
        /// 当前 mutation 使用的排队策略；`.serial` token 不允许被 supersede。
        let updatePolicy: ListUpdatePolicy
        /// mutation 不会被强行取消，但完成时需要报告 `.superseded`。
        var isSuperseded = false

        init(updatePolicy: ListUpdatePolicy) {
            self.updatePolicy = updatePolicy
        }
    }

    /// 当前正在操作 UIKit 的 token；非空即表示新请求必须入队。
    private(set) var activeToken: Token?

    /// 是否已有 mutation 占用 UIKit 提交阶段。
    var isExecuting: Bool { activeToken != nil }

    /// 开始一次 UIKit mutation，并验证没有重叠提交。
    func begin(updatePolicy: ListUpdatePolicy) -> Token {
        precondition(activeToken == nil, "ListKit attempted to start overlapping UIKit mutations")
        let token = Token(updatePolicy: updatePolicy)
        activeToken = token
        return token
    }

    /// 将正在执行的 `.coalesceLatest` mutation 标记为已被更新请求取代。
    ///
    /// 已提交给 UIKit 的工作仍会自然结束；adapter 在完成边界读取 token 并返回
    /// `.superseded`，避免尝试取消无法安全撤回的 diffable 更新。
    func supersedeActive() {
        guard activeToken?.updatePolicy == .coalesceLatest else { return }
        activeToken?.isSuperseded = true
    }

    /// 释放当前 mutation。传入非当前 token 表示 adapter 的完成时序发生错误。
    func finish(_ token: Token) {
        precondition(activeToken === token, "ListKit finished a mutation that was not active")
        activeToken = nil
    }
}

/// pending 队列中可合并或可替代的 mutation 类型。
enum ListPendingMutationKind: Equatable {
    case apply
    case rowRefresh
    case sectionReload
}

@MainActor
final class ListPendingMutationRequest {
    /// 请求类型决定队列合并和 reloadAll 覆盖规则。
    let kind: ListPendingMutationKind
    /// `.serial` 保留每个请求；`.coalesceLatest` 允许合并或替代。
    let updatePolicy: ListUpdatePolicy
    /// apply 等不可结构化合并请求的实际执行入口。
    private let startHandler: () -> Void
    /// 请求尚未执行即被替代时使用的最终回调。
    private let supersedeHandler: () -> Void
    /// Row/Section payload 在同类型请求相邻入队时参与合并。
    private var rowRefresh: RowRefreshPayload?
    private var sectionReload: SectionReloadPayload?

    init(
        kind: ListPendingMutationKind,
        updatePolicy: ListUpdatePolicy,
        start: @escaping () -> Void,
        supersede: @escaping () -> Void
    ) {
        self.kind = kind
        self.updatePolicy = updatePolicy
        self.startHandler = start
        self.supersedeHandler = supersede
    }

    init(
        rowIDs: [AnyListID],
        sectionID: AnyListID?,
        scope: ListRefreshScope,
        action: ListRefreshAction,
        transaction: ListTransaction,
        completion: ((ListRefreshSummary) -> Void)?,
        execute: @escaping (
            [AnyListID],
            AnyListID?,
            ListRefreshScope,
            ListRefreshAction,
            ListTransaction,
            ((ListRefreshSummary) -> Void)?
        ) -> Void
    ) {
        let requestedTargetCount = Set(rowIDs).count
        self.kind = .rowRefresh
        self.updatePolicy = transaction.updatePolicy
        self.startHandler = {}
        self.supersedeHandler = {}
        self.rowRefresh = RowRefreshPayload(
            rowIDs: Set(rowIDs),
            sectionID: sectionID,
            scope: scope,
            action: action,
            transaction: transaction,
            completions: completion.map { [(requestedTargetCount, $0)] } ?? [],
            execute: execute
        )
    }

    init(
        sectionIDs: [AnyListID],
        transaction: ListTransaction,
        completion: ((ListRefreshSummary) -> Void)?,
        execute: @escaping (
            [AnyListID],
            ListTransaction,
            ((ListRefreshSummary) -> Void)?
        ) -> Void
    ) {
        let requestedTargetCount = Set(sectionIDs).count
        self.kind = .sectionReload
        self.updatePolicy = transaction.updatePolicy
        self.startHandler = {}
        self.supersedeHandler = {}
        self.sectionReload = SectionReloadPayload(
            sectionIDs: Set(sectionIDs),
            transaction: transaction,
            completions: completion.map { [(requestedTargetCount, $0)] } ?? [],
            execute: execute
        )
    }

    /// 执行最终合并后的请求，并把同一次执行结果分别映射回原始调用方。
    func start() {
        if let rowRefresh {
            let completions = rowRefresh.completions
            rowRefresh.execute(
                Array(rowRefresh.rowIDs),
                rowRefresh.sectionID,
                rowRefresh.scope,
                rowRefresh.action,
                rowRefresh.transaction,
                completions.isEmpty ? nil : { summary in
                    // 合并请求共享 matched/reload 等执行指标，但每个调用方仍应看到
                    // 自己输入去重后的 requestedTargetCount。
                    for (requestedTargetCount, completion) in completions {
                        completion(summary.replacingRequestedTargetCount(requestedTargetCount))
                    }
                }
            )
            return
        }
        if let sectionReload {
            let completions = sectionReload.completions
            sectionReload.execute(
                Array(sectionReload.sectionIDs),
                sectionReload.transaction,
                completions.isEmpty ? nil : { summary in
                    for (requestedTargetCount, completion) in completions {
                        completion(summary.replacingRequestedTargetCount(requestedTargetCount))
                    }
                }
            )
            return
        }
        startHandler()
    }

    /// 在请求开始前以 `.superseded` 完成所有原始调用方。
    func supersede() {
        if let rowRefresh {
            for (requestedTargetCount, completion) in rowRefresh.completions {
                completion(ListRefreshSummary(
                    requestedTargetCount: requestedTargetCount,
                    completionState: .superseded
                ))
            }
            return
        }
        if let sectionReload {
            for (requestedTargetCount, completion) in sectionReload.completions {
                completion(ListRefreshSummary(
                    requestedTargetCount: requestedTargetCount,
                    completionState: .superseded
                ))
            }
            return
        }
        supersedeHandler()
    }

    /// 合并兼容的 Row 刷新；action 冲突按 reload > invalidate > reconfigure 升级。
    ///
    /// Section、scope 或 transaction 不同会影响目标和动画语义，因此不允许合并。
    func mergeCompatibleRowRefresh(_ request: ListPendingMutationRequest) -> Bool {
        guard updatePolicy == .coalesceLatest,
              request.updatePolicy == .coalesceLatest,
              var current = rowRefresh,
              let incoming = request.rowRefresh,
              current.sectionID == incoming.sectionID,
              current.scope == incoming.scope,
              current.transaction == incoming.transaction else { return false }

        current.rowIDs.formUnion(incoming.rowIDs)
        current.action = ListRefreshAction.stronger(current.action, incoming.action)
        current.completions.append(contentsOf: incoming.completions)
        rowRefresh = current
        return true
    }

    /// 合并 transaction 相同的 pending Section reload，并保留所有完成回调。
    func mergeCompatibleSectionReload(_ request: ListPendingMutationRequest) -> Bool {
        guard updatePolicy == .coalesceLatest,
              request.updatePolicy == .coalesceLatest,
              var current = sectionReload,
              let incoming = request.sectionReload,
              current.transaction == incoming.transaction else { return false }

        current.sectionIDs.formUnion(incoming.sectionIDs)
        current.completions.append(contentsOf: incoming.completions)
        sectionReload = current
        return true
    }

    private struct RowRefreshPayload {
        /// 合并后仍待执行的类型擦除 Row ID 集合。
        var rowIDs: Set<AnyListID>
        /// 可选 Section 过滤条件；不同过滤条件的请求不能合并。
        let sectionID: AnyListID?
        /// 执行前解析目标时使用的可见性范围。
        let scope: ListRefreshScope
        /// 合并冲突后得到的最强刷新动作。
        var action: ListRefreshAction
        /// 动画和队列语义；仅完全相同的 transaction 可以合并。
        let transaction: ListTransaction
        /// 每个原始请求的去重目标数和最终回调。
        var completions: [(Int, (ListRefreshSummary) -> Void)]
        /// 由具体 adapter 提供的执行入口，出队时才解析 snapshot identity。
        let execute: (
            [AnyListID],
            AnyListID?,
            ListRefreshScope,
            ListRefreshAction,
            ListTransaction,
            ((ListRefreshSummary) -> Void)?
        ) -> Void
    }

    private struct SectionReloadPayload {
        /// 合并后仍待执行的类型擦除 Section ID 集合。
        var sectionIDs: Set<AnyListID>
        /// 动画和队列语义；仅完全相同的 transaction 可以合并。
        let transaction: ListTransaction
        /// 每个原始请求的去重目标数和最终回调。
        var completions: [(Int, (ListRefreshSummary) -> Void)]
        /// 由具体 adapter 提供的执行入口。
        let execute: (
            [AnyListID],
            ListTransaction,
            ((ListRefreshSummary) -> Void)?
        ) -> Void
    }
}

extension ListRefreshAction {
    /// 返回生命周期影响更强的 action，用于合并重复 presentation identity。
    static func stronger(_ lhs: Self, _ rhs: Self) -> Self {
        func rank(_ action: Self) -> Int {
            switch action {
            case .reconfigure(layout: .none): 0
            case .reconfigure(layout: .invalidate): 1
            case .reload: 2
            }
        }
        return rank(lhs) >= rank(rhs) ? lhs : rhs
    }
}

private extension ListRefreshSummary {
    func replacingRequestedTargetCount(_ requestedTargetCount: Int) -> Self {
        ListRefreshSummary(
            requestedTargetCount: requestedTargetCount,
            matchedTargetCount: matchedTargetCount,
            visibleReconfiguredCount: visibleReconfiguredCount,
            reloadedTargetCount: reloadedTargetCount,
            layoutInvalidated: layoutInvalidated,
            completionState: completionState
        )
    }
}

private struct ListSnapshotRefreshPlan {
    /// 使用 `reconfigureItems` 的 identity；与 `reloadItems` 互斥。
    var reconfigureItems: [AnyListIdentity] = []
    /// `reconfigureItems` 中还需在完成后主动重新测量布局的 identity。
    var layoutInvalidationItems: [AnyListIdentity] = []
    /// 使用 `reloadItems` 的 identity；冲突时优先级高于 reconfigure。
    var reloadItems: [AnyListIdentity] = []

    /// 实际提交给 snapshot 的唯一刷新 identity 数量。
    var count: Int {
        reconfigureItems.count + reloadItems.count
    }
}

enum ListApplyPlanner {
    /// 根据新旧描述树生成结构 diff、刷新分组和初始 summary。
    static func makePlan(
        old oldSections: [ListSectionSnapshot],
        new newSections: [ListSectionSnapshot],
        options: ListApplyOptions,
        diagnosticsIssues: [ListDiagnosticsIssue]
    ) -> ListApplyPlan {
        let oldRows = oldSections.flatMap(\.rows)
        let newRows = newSections.flatMap(\.rows)
        let oldSupplementaries = oldSections.flatMap(\.supplementaries)
        let newSupplementaries = newSections.flatMap(\.supplementaries)
        let movedRowCount = inferredRowMoveCount(old: oldSections, new: newSections)
        let sectionChanges = sectionChanges(old: oldSections, new: newSections)
        let oldRowsByIdentity = lookup(from: oldRows)
        let newRowsByIdentity = lookup(from: newRows)
        let oldSupplementariesByIdentity = lookup(from: oldSupplementaries)
        let newSupplementariesByIdentity = lookup(from: newSupplementaries)

        let shouldApplyDiffable = !shouldStopBeforeDiffableApply(
            issues: diagnosticsIssues,
            options: options
        )
        let snapshotRefresh = shouldApplyDiffable
            ? itemsNeedingSnapshotRefresh(
                oldRowsByIdentity: oldRowsByIdentity,
                newRows: newRows,
                strategy: options.refreshStrategy
            )
            : ListSnapshotRefreshPlan()
        let initialSummary = makeSummary(
            oldRowsByIdentity: oldRowsByIdentity,
            newRowsByIdentity: newRowsByIdentity,
            oldSupplementariesByIdentity: oldSupplementariesByIdentity,
            newSupplementariesByIdentity: newSupplementariesByIdentity,
            snapshotRefreshCount: snapshotRefresh.count,
            visibleRefreshCount: 0,
            visibleSupplementaryRefreshCount: 0,
            diagnosticsIssues: diagnosticsIssues,
            movedRowCount: movedRowCount,
            sectionChanges: sectionChanges
        )

        return ListApplyPlan(
            shouldApplyDiffable: shouldApplyDiffable,
            snapshotReconfigureItems: snapshotRefresh.reconfigureItems,
            snapshotLayoutInvalidationItems: snapshotRefresh.layoutInvalidationItems,
            snapshotReloadItems: snapshotRefresh.reloadItems,
            shouldRunVisibleRefresh: shouldRunVisibleRefresh(strategy: options.refreshStrategy),
            changedSectionCount: sectionChanges.changedCount,
            initialSummary: initialSummary,
            oldRowsByIdentity: oldRowsByIdentity,
            newRowsByIdentity: newRowsByIdentity,
            oldSupplementariesByIdentity: oldSupplementariesByIdentity,
            newSupplementariesByIdentity: newSupplementariesByIdentity
        )
    }

    /// 判断 kept Row 是否应在 snapshot 提交后进行可见原地重配。
    static func shouldRefreshVisibleRow(
        _ row: ListNodeSnapshot,
        oldRow: ListNodeSnapshot,
        strategy: ListApplyRefreshStrategy
    ) -> Bool {
        switch row.refreshPolicy {
        case .automaticVisible:
            return row.refreshID == nil || oldRow.refreshID != row.refreshID
        case .alwaysVisible:
            return true
        case .whenRefreshIDChanges:
            return strategy == .visibleOnly && oldRow.refreshID != row.refreshID
        case .never:
            return false
        }
    }

    /// 根据 supplementary policy 与 refreshID 变化判断是否重配可见视图。
    static func shouldRefreshVisibleSupplementary(
        _ supplementary: ListNodeSnapshot,
        oldSupplementary: ListNodeSnapshot
    ) -> Bool {
        switch supplementary.refreshPolicy {
        case .automaticVisible:
            return supplementary.refreshID == nil
                || oldSupplementary.refreshID != supplementary.refreshID
        case .alwaysVisible:
            return true
        case .whenRefreshIDChanges:
            return oldSupplementary.refreshID != supplementary.refreshID
        case .never:
            return false
        }
    }

    /// 根据 diagnostics 模式决定结构问题是否阻止本次 diffable 提交。
    private static func shouldStopBeforeDiffableApply(
        issues: [ListDiagnosticsIssue],
        options: ListApplyOptions
    ) -> Bool {
        guard !issues.isEmpty else { return false }

        switch options.diagnostics.mode {
        case .disabled:
            return false
        case .warning:
            return true
        case .assertion:
            assertionFailure(issues.map(\.message).joined(separator: "\n"))
            return true
        }
    }

    /// 对 kept Row 解析 snapshot 级 action，并按生命周期强度消解 identity 冲突。
    private static func itemsNeedingSnapshotRefresh(
        oldRowsByIdentity: [AnyListIdentity: ListNodeSnapshot],
        newRows: [ListNodeSnapshot],
        strategy: ListApplyRefreshStrategy
    ) -> ListSnapshotRefreshPlan {
        switch strategy {
        case .visibleOnly:
            return ListSnapshotRefreshPlan()
        case .reloadKeptRows:
            var seen: Set<AnyListIdentity> = []
            return ListSnapshotRefreshPlan(
                reloadItems: newRows.compactMap { row in
                    guard oldRowsByIdentity[row.identity] != nil,
                          seen.insert(row.identity).inserted else { return nil }
                    return row.identity
                }
            )
        case .automatic, .refreshIDChangesOnly:
            break
        }

        // 同一 presentation identity 可能由重复展示描述命中。先按 identity 汇总最强
        // action，再统一输出，保证三类 snapshot 操作互斥且不会重复提交。
        var resolvedActions: [AnyListIdentity: ListRefreshAction] = [:]
        for row in newRows {
            guard
                let oldRow = oldRowsByIdentity[row.identity],
                row.refreshPolicy == .whenRefreshIDChanges,
                oldRow.refreshID != row.refreshID
            else { continue }

            if let existing = resolvedActions[row.identity] {
                resolvedActions[row.identity] = ListRefreshAction.stronger(existing, row.refreshAction)
            } else {
                resolvedActions[row.identity] = row.refreshAction
            }
        }

        var result = ListSnapshotRefreshPlan()
        var emitted: Set<AnyListIdentity> = []
        for row in newRows {
            guard emitted.insert(row.identity).inserted,
                  let action = resolvedActions[row.identity] else { continue }
            switch action {
            case .reconfigure(let layout):
                result.reconfigureItems.append(row.identity)
                if layout == .invalidate {
                    result.layoutInvalidationItems.append(row.identity)
                }
            case .reload:
                result.reloadItems.append(row.identity)
            }
        }
        return result
    }

    /// 判断当前 apply strategy 是否还需要执行 snapshot 后的可见刷新阶段。
    private static func shouldRunVisibleRefresh(strategy: ListApplyRefreshStrategy) -> Bool {
        switch strategy {
        case .automatic, .visibleOnly:
            return true
        case .refreshIDChangesOnly, .reloadKeptRows:
            return false
        }
    }

    /// 将结构集合差异与刷新指标汇总为同步提交阶段的 summary。
    private static func makeSummary(
        oldRowsByIdentity: [AnyListIdentity: ListNodeSnapshot],
        newRowsByIdentity: [AnyListIdentity: ListNodeSnapshot],
        oldSupplementariesByIdentity: [AnyListIdentity: ListNodeSnapshot],
        newSupplementariesByIdentity: [AnyListIdentity: ListNodeSnapshot],
        snapshotRefreshCount: Int,
        visibleRefreshCount: Int,
        visibleSupplementaryRefreshCount: Int,
        diagnosticsIssues: [ListDiagnosticsIssue],
        movedRowCount: Int,
        sectionChanges: ListSectionChanges
    ) -> ListApplySummary {
        let oldIDs = Set(oldRowsByIdentity.keys)
        let newIDs = Set(newRowsByIdentity.keys)
        let keptIDs = oldIDs.intersection(newIDs)
        let refreshIDChangedCount = keptIDs.reduce(into: 0) { count, identity in
            guard oldRowsByIdentity[identity]?.refreshID != newRowsByIdentity[identity]?.refreshID else { return }
            count += 1
        }

        let oldSupplementaryIDs = Set(oldSupplementariesByIdentity.keys)
        let newSupplementaryIDs = Set(newSupplementariesByIdentity.keys)
        let keptSupplementaryIDs = oldSupplementaryIDs.intersection(newSupplementaryIDs)
        let supplementaryRefreshIDChangedCount = keptSupplementaryIDs.reduce(into: 0) { count, identity in
            guard oldSupplementariesByIdentity[identity]?.refreshID != newSupplementariesByIdentity[identity]?.refreshID else { return }
            count += 1
        }

        return ListApplySummary(
            insertedSectionCount: sectionChanges.insertedCount,
            deletedSectionCount: sectionChanges.deletedCount,
            movedSectionCount: sectionChanges.movedCount,
            keptSectionCount: sectionChanges.keptCount,
            insertedRowCount: newIDs.subtracting(oldIDs).count,
            deletedRowCount: oldIDs.subtracting(newIDs).count,
            movedRowCount: movedRowCount,
            keptRowCount: keptIDs.count,
            refreshIDChangedCount: refreshIDChangedCount,
            snapshotRefreshCount: snapshotRefreshCount,
            visibleRefreshCount: visibleRefreshCount,
            supplementaryRefreshIDChangedCount: supplementaryRefreshIDChangedCount,
            visibleSupplementaryRefreshCount: visibleSupplementaryRefreshCount,
            diagnosticsIssues: diagnosticsIssues
        )
    }

    /// 通过 CollectionDifference 的 move association 计算稳定 identity 的移动集合。
    private static func inferredMovedIdentities<ID>(old: [ID], new: [ID]) -> Set<ID>
    where ID: Hashable {
        new.difference(from: old)
            .inferringMoves()
            .reduce(into: Set<ID>()) { identities, change in
                guard case .insert(_, let identity, associatedWith: .some) = change else { return }
                identities.insert(identity)
            }
    }

    /// 统计同一 Section 内的 Row 移动；跨 Section 迁移由删除和插入表示。
    private static func inferredRowMoveCount(
        old: [ListSectionSnapshot],
        new: [ListSectionSnapshot]
    ) -> Int {
        let oldRowsBySection = old.reduce(into: [AnyListID: [AnyListIdentity]]()) { result, section in
            result[section.sectionID] = section.rows.map(\.identity)
        }
        let newRowsBySection = new.reduce(into: [AnyListID: [AnyListIdentity]]()) { result, section in
            result[section.sectionID] = section.rows.map(\.identity)
        }
        return Set(oldRowsBySection.keys).intersection(newRowsBySection.keys).reduce(into: 0) { count, sectionID in
            count += inferredMovedIdentities(
                old: oldRowsBySection[sectionID] ?? [],
                new: newRowsBySection[sectionID] ?? []
            ).count
        }
    }

    /// 计算 Section 的插入、删除、移动、保留和内容变化数量。
    private static func sectionChanges(
        old: [ListSectionSnapshot],
        new: [ListSectionSnapshot]
    ) -> ListSectionChanges {
        let oldIDs = old.map(\.sectionID)
        let newIDs = new.map(\.sectionID)
        let oldIDSet = Set(oldIDs)
        let newIDSet = Set(newIDs)
        let movedIDs = inferredMovedIdentities(old: oldIDs, new: newIDs)
        let oldFingerprints = sectionFingerprints(from: old)
        let newFingerprints = sectionFingerprints(from: new)
        let contentChangedIDs = Set(oldFingerprints.keys).union(newFingerprints.keys).filter { sectionID in
            oldFingerprints[sectionID] != newFingerprints[sectionID]
        }
        return ListSectionChanges(
            insertedCount: newIDSet.subtracting(oldIDSet).count,
            deletedCount: oldIDSet.subtracting(newIDSet).count,
            movedCount: movedIDs.count,
            keptCount: oldIDSet.intersection(newIDSet).count,
            changedCount: contentChangedIDs.union(movedIDs).count
        )
    }

    /// 为每个 Section 生成轻量内容指纹，供 changed section 统计使用。
    ///
    /// Diagnostics 可能因重复 Section ID 主动阻止 apply，因此这里先生成可覆盖的
    /// 字典以完成 summary，而不在 planner 内再次触发异常。
    private static func sectionFingerprints(
        from sections: [ListSectionSnapshot]
    ) -> [AnyListID: ListSectionChangeFingerprint] {
        sections.reduce(into: [:]) { fingerprints, section in
            fingerprints[section.sectionID] = ListSectionChangeFingerprint(section: section)
        }
    }

    /// 将节点数组转换为按 presentation identity 查询的最新值字典。
    private static func lookup(from nodes: [ListNodeSnapshot]) -> [AnyListIdentity: ListNodeSnapshot] {
        nodes.reduce(into: [:]) { result, node in
            result[node.identity] = node
        }
    }
}

private struct ListSectionChangeFingerprint: Equatable {
    /// 保留 Row 顺序的内容指纹。
    let rows: [ListNodeChangeFingerprint]
    /// 保留 supplementary 顺序的内容指纹。
    let supplementaries: [ListNodeChangeFingerprint]

    /// 从 planner 的 Section 快照提取结构与 refreshID 指纹。
    init(section: ListSectionSnapshot) {
        rows = section.rows.map(ListNodeChangeFingerprint.init)
        supplementaries = section.supplementaries.map(ListNodeChangeFingerprint.init)
    }
}

private struct ListSectionChanges {
    /// 新增 Section 数量。
    let insertedCount: Int
    /// 删除 Section 数量。
    let deletedCount: Int
    /// 保持 identity 但顺序变化的 Section 数量。
    let movedCount: Int
    /// 新旧描述树中均存在的 Section 数量。
    let keptCount: Int
    /// 内容指纹变化或发生移动、需要计入动画观测的 Section 数量。
    let changedCount: Int
}

private struct ListNodeChangeFingerprint: Equatable {
    /// 节点的 presentation identity。
    let identity: AnyListIdentity
    /// 调用方提供的内容版本标识。
    let refreshID: AnyListID?

    /// 从 planner 节点提取内容变化所需的最小字段。
    init(node: ListNodeSnapshot) {
        identity = node.identity
        refreshID = node.refreshID
    }
}

@MainActor
final class ListAnimationCompletionCoordinator {
    /// 初始哨兵表示“调度阶段尚未结束”，防止同步动画提前触发最终 completion。
    private var pendingCount = 1
    /// 所有已登记动画结束后调用一次的最终回调。
    private let completion: @MainActor () -> Void

    /// 创建带初始调度哨兵的完成协调器。
    init(completion: @escaping @MainActor () -> Void) {
        self.completion = completion
    }

    /// 登记一个异步内容或布局动画。
    func enter() {
        pendingCount += 1
    }

    /// 完成一个已登记任务；计数归零时只调用一次最终 completion。
    func leave() {
        pendingCount -= 1
        if pendingCount == 0 {
            completion()
        }
    }

    /// 释放初始哨兵，表示本轮不会再登记新的动画任务。
    func finishScheduling() {
        leave()
    }
}

extension ListDiagnostics {
    /// 检查 Section、Row 和 supplementary presentation identity 是否重复。
    static func validate(_ sections: [ListSectionSnapshot]) -> [ListDiagnosticsIssue] {
        var issues: [ListDiagnosticsIssue] = []
        var seenSections: Set<AnyListID> = []
        var seenRows: Set<AnyListIdentity> = []
        var seenSupplementaries: Set<AnyListIdentity> = []

        for section in sections {
            if !seenSections.insert(section.sectionID).inserted {
                issues.append(
                    ListDiagnosticsIssue(
                        kind: .duplicateSection,
                        message: "ListKit: duplicate section identity \(section.sectionID)"
                    )
                )
            }

            for row in section.rows where !seenRows.insert(row.identity).inserted {
                issues.append(
                    ListDiagnosticsIssue(
                        kind: .duplicateRow,
                        message: "ListKit: duplicate row identity in section \(section.sectionID), row \(row.identity.rowID)"
                    )
                )
            }

            for supplementary in section.supplementaries where !seenSupplementaries.insert(supplementary.identity).inserted {
                issues.append(
                    ListDiagnosticsIssue(
                        kind: .duplicateSupplementary,
                        message: "ListKit: duplicate supplementary identity in section \(section.sectionID)"
                    )
                )
            }
        }

        return issues
    }
}

enum ListApplyLogger {
    /// DEBUG 下按 diagnostics 配置输出结构问题。
    static func logDiagnostics(issues: [ListDiagnosticsIssue], options: ListApplyOptions) {
        #if DEBUG
        guard options.diagnostics.mode != .disabled else { return }
        for issue in issues {
            print(issue.message)
        }
        #endif
    }

    /// DEBUG 下输出一次 apply 的结构、刷新、动画和诊断统计。
    static func logApplySummary(
        _ summary: ListApplySummary,
        options: ListApplyOptions,
        prefix: String = "ListKit apply summary"
    ) {
        #if DEBUG
        guard options.diagnostics.logsApplySummary else { return }
        print(
            "\(prefix): sectionInserted=\(summary.insertedSectionCount), sectionDeleted=\(summary.deletedSectionCount), sectionMoved=\(summary.movedSectionCount), sectionKept=\(summary.keptSectionCount), rowInserted=\(summary.insertedRowCount), rowDeleted=\(summary.deletedRowCount), rowMoved=\(summary.movedRowCount), rowKept=\(summary.keptRowCount), refreshIDChanged=\(summary.refreshIDChangedCount), snapshotRefresh=\(summary.snapshotRefreshCount), visibleRefresh=\(summary.visibleRefreshCount), supplementaryRefreshIDChanged=\(summary.supplementaryRefreshIDChangedCount), visibleSupplementaryRefresh=\(summary.visibleSupplementaryRefreshCount), animation=\(summary.animation.completionState), snapshotAnimated=\(summary.animation.snapshotAnimated), outlineAnimated=\(summary.animation.outlineAnimatedSectionCount), contentTransitions=\(summary.animation.contentTransitionCount), layoutAnimated=\(summary.animation.layoutAnimated), scrollAnimated=\(summary.animation.scrollAnimated), anchorCompensation=\(summary.animation.anchorCompensation), reduceMotion=\(summary.animation.reduceMotionApplied), diagnostics=\(summary.diagnosticsIssues.count)"
        )
        #endif
    }
}

@MainActor
final class ListEventRouter<Context> {
    /// 事件具体类型到类型安全处理闭包的擦除映射。
    private var handlers: [ObjectIdentifier: @MainActor (any ListEvent, Context) -> Void] = [:]

    /// 注册或替换一种事件类型的 adapter 级处理闭包。
    func on<Event>(
        _ eventType: Event.Type = Event.self,
        handler: @escaping @MainActor (Event, Context) -> Void
    ) where Event: ListEvent {
        handlers[ObjectIdentifier(eventType)] = { event, context in
            guard let typedEvent = event as? Event else { return }
            handler(typedEvent, context)
        }
    }

    /// 按事件的动态类型分发，并携带触发位置的最新列表上下文。
    func dispatch(_ event: any ListEvent, context: Context) {
        handlers[ObjectIdentifier(type(of: event))]?(event, context)
    }
}
