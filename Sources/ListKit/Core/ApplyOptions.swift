// MARK: - Apply Options

/// apply 级刷新策略。
public enum ListApplyRefreshStrategy: Equatable, Sendable {
    /// Row 自己的刷新策略生效。
    case automatic
    /// 不触发 diffable reconfigure/reload，只刷新可见 cell。
    case visibleOnly
    /// 只走 diffable reconfigure/reload，不做默认可见重配。
    case diffableOnly
    /// 对新旧 snapshot 都存在的 item 执行 reconfigure/reload。
    case forceReload
}

/// diffable snapshot 的提交方式。
public enum ListSnapshotApplicationMode: Equatable, Sendable {
    /// 计算新旧 snapshot 差异，并按 `animatingDifferences` 决定是否显示动画。
    case differences
    /// 跳过 diff，使用 UIKit 的 reload-data 路径重置列表。
    ///
    /// - Note: UIKit 从 iOS 15 开始提供原生实现；iOS 14 会退化为无动画 diff apply。
    case reloadData
}

/// `apply` 的可选参数，保留旧入口兼容，同时把全局刷新策略和 diagnostics 放到一个对象里。
public struct ListApplyOptions: Sendable {
    public var animatingDifferences: Bool
    public var refreshStrategy: ListApplyRefreshStrategy
    public var applicationMode: ListSnapshotApplicationMode
    public var diagnostics: ListDiagnosticsOptions

    /// 创建 apply options。
    ///
    /// - Parameters:
    ///   - animatingDifferences: 是否使用 diffable 动画应用 snapshot。
    ///   - refreshStrategy: apply 级刷新策略。
    ///   - applicationMode: diff 或 reload-data 提交方式。
    ///   - diagnostics: diagnostics 处理方式。
    public init(
        animatingDifferences: Bool = true,
        refreshStrategy: ListApplyRefreshStrategy = .automatic,
        applicationMode: ListSnapshotApplicationMode = .differences,
        diagnostics: ListDiagnosticsOptions = .debugDefault
    ) {
        self.animatingDifferences = animatingDifferences
        self.refreshStrategy = refreshStrategy
        self.applicationMode = applicationMode
        self.diagnostics = diagnostics
    }
}

/// apply 后的摘要，DEBUG 日志和测试都复用这份数据。
///
/// - Note: row 统计沿用原字段；supplementary 使用独立字段，避免 item badge 等刷新行为被隐藏。
public struct ListApplySummary: Equatable, Sendable {
    public let insertedCount: Int
    public let deletedCount: Int
    public let keptCount: Int
    public let refreshIDChangedCount: Int
    public let snapshotRefreshCount: Int
    public let visibleRefreshCount: Int
    public let supplementaryRefreshIDChangedCount: Int
    public let visibleSupplementaryRefreshCount: Int
    public let diagnosticsIssues: [ListDiagnosticsIssue]

    /// 创建 apply 摘要。
    ///
    /// - Parameters:
    ///   - insertedCount: 本次新增的展示节点数量。
    ///   - deletedCount: 本次删除的展示节点数量。
    ///   - keptCount: identity 保持不变的展示节点数量。
    ///   - refreshIDChangedCount: `refreshID` 变化的展示节点数量。
    ///   - snapshotRefreshCount: 进入 diffable reconfigure/reload 的节点数量。
    ///   - visibleRefreshCount: apply completion 后轻刷的可见 cell 数量。
    ///   - supplementaryRefreshIDChangedCount: `refreshID` 变化的 supplementary 数量。
    ///   - visibleSupplementaryRefreshCount: apply completion 后轻刷的可见 supplementary view 数量。
    ///   - diagnosticsIssues: 本次发现的 diagnostics 问题。
    public init(
        insertedCount: Int = 0,
        deletedCount: Int = 0,
        keptCount: Int = 0,
        refreshIDChangedCount: Int = 0,
        snapshotRefreshCount: Int = 0,
        visibleRefreshCount: Int = 0,
        supplementaryRefreshIDChangedCount: Int = 0,
        visibleSupplementaryRefreshCount: Int = 0,
        diagnosticsIssues: [ListDiagnosticsIssue] = []
    ) {
        self.insertedCount = insertedCount
        self.deletedCount = deletedCount
        self.keptCount = keptCount
        self.refreshIDChangedCount = refreshIDChangedCount
        self.snapshotRefreshCount = snapshotRefreshCount
        self.visibleRefreshCount = visibleRefreshCount
        self.supplementaryRefreshIDChangedCount = supplementaryRefreshIDChangedCount
        self.visibleSupplementaryRefreshCount = visibleSupplementaryRefreshCount
        self.diagnosticsIssues = diagnosticsIssues
    }
}
