import CoreGraphics
import Foundation

// MARK: - Animation Transaction

/// 单个动画作用域的执行策略。
public enum ListAnimationPolicy: Equatable, Sendable {
    /// 使用 UIKit 系统动画，并在 transaction 允许时遵循 Reduce Motion。
    case automatic
    /// 强制使用 UIKit 系统动画；用于明确需要动画的交互反馈。
    case enabled
    /// 禁用该作用域的动画。
    case disabled
}

/// 连续列表 mutation 的调度方式。
public enum ListUpdatePolicy: Equatable, Sendable {
    /// 合并兼容的 pending mutation，并让被更新请求取代的旧请求以 `.superseded` 结束。
    case coalesceLatest
    /// 等待前一个 mutation 完成后再严格按调用顺序提交。
    case serial
}

/// 声明式滚动目标。
public struct ListScrollTarget: Hashable, Sendable {
    let rowID: AnyListID
    let sectionID: AnyListID?

    /// 使用 Row id 创建刷新目标。
    public init<RowID>(_ rowID: RowID) where RowID: Hashable & Sendable {
        self.rowID = AnyListID(rowID)
        self.sectionID = nil
    }

    /// 使用 Row id 和 section id 创建无歧义的刷新目标。
    public init<RowID, SectionID>(
        _ rowID: RowID,
        in sectionID: SectionID
    ) where RowID: Hashable & Sendable, SectionID: Hashable & Sendable {
        self.rowID = AnyListID(rowID)
        self.sectionID = AnyListID(sectionID)
    }
}

/// apply 后目标在 viewport 中的位置。
public enum ListScrollPosition: Equatable, Sendable {
    /// 将目标对齐到 viewport 顶部。
    case top
    /// 将目标对齐到 viewport 中心。
    case center
    /// 将目标对齐到 viewport 底部。
    case bottom
    /// 仅滚动到足以显示目标的最近位置。
    case nearest
}

/// apply 期间的声明式滚动行为。
public struct ListScrollBehavior: Equatable, Sendable {
    enum Storage: Equatable, Sendable {
        case none
        case preserveVisiblePosition(ListScrollTarget)
        case scrollTo(ListScrollTarget, ListScrollPosition)
        case scrollToLast(AnyListID?, ListScrollPosition)
    }

    let storage: Storage

    private init(storage: Storage) {
        self.storage = storage
    }

    /// 不主动改变滚动位置。
    public static let none = ListScrollBehavior(storage: .none)

    /// 保持当前可见 Row 在 viewport 中的位置。
    public static func preserveVisiblePosition(
        of target: ListScrollTarget
    ) -> ListScrollBehavior {
        ListScrollBehavior(storage: .preserveVisiblePosition(target))
    }

    /// apply 后滚动到指定 Row。
    public static func scrollTo(
        _ target: ListScrollTarget,
        position: ListScrollPosition = .nearest
    ) -> ListScrollBehavior {
        ListScrollBehavior(storage: .scrollTo(target, position))
    }

    /// apply 后滚动到全列表最后一个 Row。
    public static func scrollToLast(
        position: ListScrollPosition = .bottom
    ) -> ListScrollBehavior {
        ListScrollBehavior(storage: .scrollToLast(nil, position))
    }

    /// apply 后滚动到指定 section 的最后一个 Row。
    public static func scrollToLast<SectionID>(
        in sectionID: SectionID,
        position: ListScrollPosition = .bottom
    ) -> ListScrollBehavior where SectionID: Hashable & Sendable {
        ListScrollBehavior(storage: .scrollToLast(AnyListID(sectionID), position))
    }
}

/// 一次列表更新的动画、调度和滚动语义。
///
/// `ListTransaction` 只暴露 UIKit 能稳定兑现的系统动画开关；diffable 的 duration 和
/// curve 仍由 UIKit 决定。Row 自身内容过渡通过 `contentTransition(_:)` 单独描述。
public struct ListTransaction: Equatable, Sendable {
    /// diffable snapshot 提交是否请求动画。
    public var snapshotAnimation: ListAnimationPolicy
    /// Collection outline section snapshot 提交是否请求动画。
    public var outlineAnimation: ListAnimationPolicy
    /// 布局失效和自适应尺寸重测量是否请求动画。
    public var layoutAnimation: ListAnimationPolicy
    /// 可见 Row 内容过渡是否允许动画。
    public var contentAnimation: ListAnimationPolicy
    /// transaction 声明的滚动行为是否请求动画。
    public var scrollAnimation: ListAnimationPolicy
    /// 连续 mutation 使用合并还是严格串行调度。
    public var updatePolicy: ListUpdatePolicy
    /// apply 完成结构更新后执行的滚动行为。
    public var scrollBehavior: ListScrollBehavior
    /// `.automatic` 动画策略是否遵循系统 Reduce Motion 设置。
    public var respectsReduceMotion: Bool

    /// 创建 transaction。未单独指定的作用域继承 `animation`。
    ///
    /// - Parameters:
    ///   - animation: 所有未单独指定动画策略的默认值。
    ///   - snapshotAnimation: diffable snapshot 动画策略。
    ///   - outlineAnimation: Collection outline 动画策略。
    ///   - layoutAnimation: 布局更新动画策略。
    ///   - contentAnimation: 可见内容过渡动画策略。
    ///   - scrollAnimation: 滚动动画策略。
    ///   - updatePolicy: 连续 mutation 的调度方式。
    ///   - scrollBehavior: apply 后执行的滚动行为。
    ///   - respectsReduceMotion: 自动动画是否遵循 Reduce Motion。
    public init(
        animation: ListAnimationPolicy = .automatic,
        snapshotAnimation: ListAnimationPolicy? = nil,
        outlineAnimation: ListAnimationPolicy? = nil,
        layoutAnimation: ListAnimationPolicy? = nil,
        contentAnimation: ListAnimationPolicy? = nil,
        scrollAnimation: ListAnimationPolicy? = nil,
        updatePolicy: ListUpdatePolicy = .coalesceLatest,
        scrollBehavior: ListScrollBehavior = .none,
        respectsReduceMotion: Bool = true
    ) {
        self.snapshotAnimation = snapshotAnimation ?? animation
        self.outlineAnimation = outlineAnimation ?? animation
        self.layoutAnimation = layoutAnimation ?? animation
        self.contentAnimation = contentAnimation ?? animation
        self.scrollAnimation = scrollAnimation ?? animation
        self.updatePolicy = updatePolicy
        self.scrollBehavior = scrollBehavior
        self.respectsReduceMotion = respectsReduceMotion
    }

    /// 所有动画作用域均为 `.automatic` 的默认 transaction。
    public static let automatic = ListTransaction()
    /// 禁用所有动画作用域的 transaction。
    public static let disabled = ListTransaction(animation: .disabled)

    /// 同时设置所有动画作用域。
    ///
    /// - Parameter policy: 应用于 snapshot、outline、layout、content 和 scroll 的策略。
    /// - Returns: 更新后的 transaction 副本。
    public func animation(_ policy: ListAnimationPolicy) -> Self {
        var copy = self
        copy.snapshotAnimation = policy
        copy.outlineAnimation = policy
        copy.layoutAnimation = policy
        copy.contentAnimation = policy
        copy.scrollAnimation = policy
        return copy
    }

    /// 设置 diffable snapshot 动画策略并返回更新后的副本。
    public func snapshotAnimation(_ policy: ListAnimationPolicy) -> Self {
        var copy = self
        copy.snapshotAnimation = policy
        return copy
    }

    /// 设置 Collection outline 动画策略并返回更新后的副本。
    public func outlineAnimation(_ policy: ListAnimationPolicy) -> Self {
        var copy = self
        copy.outlineAnimation = policy
        return copy
    }

    /// 设置布局更新动画策略并返回更新后的副本。
    public func layoutAnimation(_ policy: ListAnimationPolicy) -> Self {
        var copy = self
        copy.layoutAnimation = policy
        return copy
    }

    /// 设置可见内容过渡动画策略并返回更新后的副本。
    public func contentAnimation(_ policy: ListAnimationPolicy) -> Self {
        var copy = self
        copy.contentAnimation = policy
        return copy
    }

    /// 设置滚动动画策略并返回更新后的副本。
    public func scrollAnimation(_ policy: ListAnimationPolicy) -> Self {
        var copy = self
        copy.scrollAnimation = policy
        return copy
    }

    /// 设置连续 mutation 的调度方式并返回更新后的副本。
    public func updatePolicy(_ policy: ListUpdatePolicy) -> Self {
        var copy = self
        copy.updatePolicy = policy
        return copy
    }

    /// 设置 apply 后的滚动行为并返回更新后的副本。
    public func scrollBehavior(_ behavior: ListScrollBehavior) -> Self {
        var copy = self
        copy.scrollBehavior = behavior
        return copy
    }

    /// 设置自动动画是否遵循 Reduce Motion，并返回更新后的副本。
    public func respectsReduceMotion(_ enabled: Bool = true) -> Self {
        var copy = self
        copy.respectsReduceMotion = enabled
        return copy
    }

    /// 将声明式动画策略解析为本次提交可直接执行的布尔配置。
    ///
    /// `.automatic` 会同时考虑系统 Reduce Motion 与 `respectsReduceMotion`；显式
    /// `.enabled` / `.disabled` 不受系统设置改写。
    func resolved(reduceMotionEnabled: Bool) -> ListResolvedTransaction {
        func resolve(_ policy: ListAnimationPolicy) -> Bool {
            switch policy {
            case .automatic:
                return !(respectsReduceMotion && reduceMotionEnabled)
            case .enabled:
                return true
            case .disabled:
                return false
            }
        }

        let policies = [
            snapshotAnimation,
            outlineAnimation,
            layoutAnimation,
            contentAnimation,
            scrollAnimation
        ]
        return ListResolvedTransaction(
            snapshotAnimation: resolve(snapshotAnimation),
            outlineAnimation: resolve(outlineAnimation),
            layoutAnimation: resolve(layoutAnimation),
            contentAnimation: resolve(contentAnimation),
            scrollAnimation: resolve(scrollAnimation),
            updatePolicy: updatePolicy,
            scrollBehavior: scrollBehavior,
            reduceMotionApplied: respectsReduceMotion
                && reduceMotionEnabled
                && policies.contains(.automatic)
        )
    }
}

/// `ListTransaction` 结合当前系统环境后得到的不可变执行配置。
struct ListResolvedTransaction {
    /// diffable snapshot 是否使用差异动画。
    let snapshotAnimation: Bool
    /// outline 展开或折叠是否使用动画。
    let outlineAnimation: Bool
    /// layout 更新是否包裹在动画事务中。
    let layoutAnimation: Bool
    /// 可见内容重配是否执行 Row 声明的内容过渡。
    let contentAnimation: Bool
    /// apply 后的滚动或锚点恢复是否使用动画。
    let scrollAnimation: Bool
    /// 连续 mutation 的排队与合并策略。
    let updatePolicy: ListUpdatePolicy
    /// snapshot 完成后的滚动或可见锚点行为。
    let scrollBehavior: ListScrollBehavior
    /// 本次解析是否因 Reduce Motion 关闭了至少一个 `.automatic` 动画。
    let reduceMotionApplied: Bool
}

// MARK: - Apply Options

/// identity 保持不变时，内容刷新的触发条件。
public enum ListRefreshTrigger: Equatable, Sendable {
    /// 未设置 `refreshID` 时每次 apply 刷新；设置后仅在值变化时刷新。
    case automatic
    /// 仅在新旧 `refreshID` 不相等时刷新。
    case refreshIDChanges
    /// identity 保持不变时，每次 apply 都刷新。
    case everyApply
    /// apply 不主动刷新；adapter 定向刷新仍可使用。
    case never
}

/// 主动 Row 刷新的目标范围。
public enum ListRefreshScope: Equatable, Sendable {
    /// 刷新当前已提交 snapshot 中所有匹配的展示身份。
    case allMatching
    /// 只刷新当前可见的匹配展示身份。
    case visible
}

/// Row 重配后的布局处理方式。
public enum ListRefreshLayoutPolicy: Equatable, Sendable {
    /// ListKit 不额外请求布局失效。
    case none
    /// 重配完成后主动请求列表重新测量布局。
    case invalidate
}

/// Row 内容刷新时使用的 UIKit 生命周期。
public enum ListRowRefreshAction: Equatable, Sendable {
    /// 使用 diffable reconfigure 保留现有 Cell，不进入 `prepareForReuse`，并按需请求布局失效。
    case reconfigure(layout: ListRefreshLayoutPolicy)
    /// 请求完整 reload/configuration 路径；UIKit 不保证最终 Cell 对象地址发生变化。
    case reload
}

/// Row 的刷新触发、目标范围和执行动作。
public struct ListRowRefreshRule: Equatable, Sendable {
    public var trigger: ListRefreshTrigger
    public var scope: ListRefreshScope
    public var action: ListRowRefreshAction

    public init(
        trigger: ListRefreshTrigger = .automatic,
        scope: ListRefreshScope = .visible,
        action: ListRowRefreshAction = .reconfigure(layout: .none)
    ) {
        self.trigger = trigger
        self.scope = scope
        self.action = action
    }

    public static let automatic = ListRowRefreshRule()
}

/// Supplementary 内容刷新时使用的 UIKit 生命周期。
public enum ListSupplementaryRefreshAction: Equatable, Sendable {
    /// 直接重配当前存在的 supplementary view。
    case reconfigureVisible(layout: ListRefreshLayoutPolicy)
    /// 重载所属 Section，会连带重载其中的 Row。
    case reloadSection
}

/// Supplementary 的刷新触发和可兑现执行动作。
public struct ListSupplementaryRefreshRule: Equatable, Sendable {
    public var trigger: ListRefreshTrigger
    public var action: ListSupplementaryRefreshAction

    public init(
        trigger: ListRefreshTrigger = .automatic,
        action: ListSupplementaryRefreshAction = .reconfigureVisible(layout: .none)
    ) {
        self.trigger = trigger
        self.action = action
    }

    public static let automatic = ListSupplementaryRefreshRule()
}

/// diffable snapshot 的提交方式。
public enum ListSnapshotApplicationMode: Equatable, Sendable {
    /// 使用 diffable 差异提交；是否显示 snapshot 动画由 transaction 决定。
    case differences
    /// 使用 reload-data 语义提交完整 snapshot，不计算界面差异动画。
    case reloadData
}

/// `apply` 的完整配置。
public struct ListApplyOptions: Sendable {
    /// 控制动画、调度策略、滚动行为和 Reduce Motion 处理。
    public var transaction: ListTransaction
    /// 决定 snapshot 使用差异提交还是 reload-data 提交。
    public var applicationMode: ListSnapshotApplicationMode
    /// 控制重复 identity 等结构问题的检查与报告方式。
    public var diagnostics: ListDiagnosticsOptions

    /// 创建一次 apply 使用的完整配置。
    ///
    /// - Parameters:
    ///   - transaction: 动画、队列、滚动和 Reduce Motion 配置。
    ///   - applicationMode: diffable snapshot 的提交方式。
    ///   - diagnostics: 提交前结构检查配置。
    public init(
        transaction: ListTransaction = .automatic,
        applicationMode: ListSnapshotApplicationMode = .differences,
        diagnostics: ListDiagnosticsOptions = .debugDefault
    ) {
        self.transaction = transaction
        self.applicationMode = applicationMode
        self.diagnostics = diagnostics
    }
}

// MARK: - Apply Diagnostics

/// 一次 apply summary 的提交/完成状态。
public enum ListApplyCompletionState: Equatable, Sendable {
    /// 同步 `apply` 已提交更新请求，但 snapshot、可见刷新、layout 或滚动处理尚未全部完成。
    case submitted
    /// ListKit 已完成本次 apply 负责的 snapshot、可见刷新、layout、滚动和内容过渡处理。
    case completed
    /// 本次 apply 被之后的 `.coalesceLatest` apply 取代。
    case superseded
    /// async 任务在提交更新前已经取消。
    case cancelledBeforeCommit
}

/// ListKit 在一次 mutation 中实际规划或执行的刷新动作。
public struct ListRefreshMetrics: Equatable, Sendable {
    public let snapshotReconfiguredRowCount: Int
    public let visibleReconfiguredRowCount: Int
    public let reloadedRowCount: Int
    public let visibleReconfiguredSupplementaryCount: Int
    public let reloadedSectionCount: Int

    public init(
        snapshotReconfiguredRowCount: Int = 0,
        visibleReconfiguredRowCount: Int = 0,
        reloadedRowCount: Int = 0,
        visibleReconfiguredSupplementaryCount: Int = 0,
        reloadedSectionCount: Int = 0
    ) {
        self.snapshotReconfiguredRowCount = snapshotReconfiguredRowCount
        self.visibleReconfiguredRowCount = visibleReconfiguredRowCount
        self.reloadedRowCount = reloadedRowCount
        self.visibleReconfiguredSupplementaryCount = visibleReconfiguredSupplementaryCount
        self.reloadedSectionCount = reloadedSectionCount
    }

    public static let zero = ListRefreshMetrics()
}

/// ListKit 在本次 apply 中调度和观测到的动画、布局与滚动摘要。
///
/// 这些值用于 diagnostics、日志和测试断言；它们描述 ListKit 请求或完成的操作，
/// 不承诺等同 UIKit 内部动画事务的逐帧状态。
public struct ListAnimationSummary: Equatable, Sendable {
    /// 本次 apply summary 对应的提交/完成状态。
    public let completionState: ListApplyCompletionState
    /// ListKit 是否按 transaction 和 snapshot 变化请求了 diffable snapshot 动画。
    public let snapshotAnimated: Bool
    /// 请求 snapshot 动画时，ListKit 判断内容发生变化的 Section 数量。
    public let animatedSectionCount: Int
    /// Collection outline hierarchy 发生变化并请求动画的 Section 数量；Table 始终为 0。
    public let outlineAnimatedSectionCount: Int
    /// 可见 Row 内容过渡动画数量。
    public let contentTransitionCount: Int
    /// 本次 apply 是否触发布局失效或重新计算。
    public let layoutInvalidated: Bool
    /// ListKit 是否请求了布局动画。
    public let layoutAnimated: Bool
    /// ListKit 是否请求了滚动动画。
    public let scrollAnimated: Bool
    /// 为保持可见锚点位置而补偿的 content inset/offset 距离。
    public let anchorCompensation: CGFloat
    /// 是否因为系统 Reduce Motion 设置关闭了动画。
    public let reduceMotionApplied: Bool

    /// 创建一次 apply 的动画与完成状态摘要。
    public init(
        completionState: ListApplyCompletionState = .submitted,
        snapshotAnimated: Bool = false,
        animatedSectionCount: Int = 0,
        outlineAnimatedSectionCount: Int = 0,
        contentTransitionCount: Int = 0,
        layoutInvalidated: Bool = false,
        layoutAnimated: Bool = false,
        scrollAnimated: Bool = false,
        anchorCompensation: CGFloat = 0,
        reduceMotionApplied: Bool = false
    ) {
        self.completionState = completionState
        self.snapshotAnimated = snapshotAnimated
        self.animatedSectionCount = animatedSectionCount
        self.outlineAnimatedSectionCount = outlineAnimatedSectionCount
        self.contentTransitionCount = contentTransitionCount
        self.layoutInvalidated = layoutInvalidated
        self.layoutAnimated = layoutAnimated
        self.scrollAnimated = scrollAnimated
        self.anchorCompensation = anchorCompensation
        self.reduceMotionApplied = reduceMotionApplied
    }
}

/// ListKit 对一次 apply 的观测摘要。
///
/// 同步 `apply` 立即返回的 summary 描述本次提交计划，`animation.completionState`
/// 通常为 `.submitted`。completion、async `apply` 和完成后的 `lastApplySummary`
/// 返回最终状态，才包含实际执行的可见刷新、layout、滚动和内容过渡统计。
///
/// 这些字段用于 diagnostics、日志、性能观察和测试断言；不应作为数据源状态的唯一依据。
public struct ListApplySummary: Equatable, Sendable {
    /// 新插入的 Section 数量。
    public let insertedSectionCount: Int
    /// 被删除的 Section 数量。
    public let deletedSectionCount: Int
    /// 保持 identity、但顺序发生变化的 Section 数量。
    public let movedSectionCount: Int
    /// 新旧 snapshot 中都存在的 Section 数量。
    public let keptSectionCount: Int
    /// 新插入的 Row 数量。
    public let insertedRowCount: Int
    /// 被删除的 Row 数量。
    public let deletedRowCount: Int
    /// 在同一 Section 内发生移动的 Row 数量；跨 Section 迁移按删除 + 插入统计。
    public let movedRowCount: Int
    /// 新旧 snapshot 中都存在的 Row 数量。
    public let keptRowCount: Int
    /// 新旧 snapshot 中都存在、且 `refreshID` 发生变化的 Row 数量。
    public let rowRefreshIDChangedCount: Int
    /// 新旧 snapshot 中都存在、且 `refreshID` 发生变化的 supplementary 数量。
    ///
    /// Collection supplementary view，以及 Table header/footer，都会按 supplementary 统计。
    public let supplementaryRefreshIDChangedCount: Int
    /// 本次 apply 规划或实际执行的刷新动作。
    public let refreshMetrics: ListRefreshMetrics
    /// 本次 apply 在 diffable 提交前发现的 diagnostics 问题。
    public let diagnosticsIssues: [ListDiagnosticsIssue]
    /// 本次 apply 的提交/完成与动画观测摘要。
    public let animation: ListAnimationSummary

    /// 创建一次 apply 的结构、刷新、诊断和动画摘要。
    public init(
        insertedSectionCount: Int = 0,
        deletedSectionCount: Int = 0,
        movedSectionCount: Int = 0,
        keptSectionCount: Int = 0,
        insertedRowCount: Int = 0,
        deletedRowCount: Int = 0,
        movedRowCount: Int = 0,
        keptRowCount: Int = 0,
        rowRefreshIDChangedCount: Int = 0,
        supplementaryRefreshIDChangedCount: Int = 0,
        refreshMetrics: ListRefreshMetrics = .zero,
        diagnosticsIssues: [ListDiagnosticsIssue] = [],
        animation: ListAnimationSummary = ListAnimationSummary()
    ) {
        self.insertedSectionCount = insertedSectionCount
        self.deletedSectionCount = deletedSectionCount
        self.movedSectionCount = movedSectionCount
        self.keptSectionCount = keptSectionCount
        self.insertedRowCount = insertedRowCount
        self.deletedRowCount = deletedRowCount
        self.movedRowCount = movedRowCount
        self.keptRowCount = keptRowCount
        self.rowRefreshIDChangedCount = rowRefreshIDChangedCount
        self.supplementaryRefreshIDChangedCount = supplementaryRefreshIDChangedCount
        self.refreshMetrics = refreshMetrics
        self.diagnosticsIssues = diagnosticsIssues
        self.animation = animation
    }
}

extension ListApplySummary {
    func replacingAnimation(_ animation: ListAnimationSummary) -> ListApplySummary {
        ListApplySummary(
            insertedSectionCount: insertedSectionCount,
            deletedSectionCount: deletedSectionCount,
            movedSectionCount: movedSectionCount,
            keptSectionCount: keptSectionCount,
            insertedRowCount: insertedRowCount,
            deletedRowCount: deletedRowCount,
            movedRowCount: movedRowCount,
            keptRowCount: keptRowCount,
            rowRefreshIDChangedCount: rowRefreshIDChangedCount,
            supplementaryRefreshIDChangedCount: supplementaryRefreshIDChangedCount,
            refreshMetrics: refreshMetrics,
            diagnosticsIssues: diagnosticsIssues,
            animation: animation
        )
    }
}

/// 一次主动 Row 或 Section 刷新的提交与完成摘要。
public struct ListRefreshSummary: Equatable, Sendable {
    public let requestedTargetCount: Int
    public let matchedTargetCount: Int
    public let refreshMetrics: ListRefreshMetrics
    public let animation: ListAnimationSummary

    public init(
        requestedTargetCount: Int = 0,
        matchedTargetCount: Int = 0,
        refreshMetrics: ListRefreshMetrics = .zero,
        animation: ListAnimationSummary = ListAnimationSummary()
    ) {
        self.requestedTargetCount = requestedTargetCount
        self.matchedTargetCount = matchedTargetCount
        self.refreshMetrics = refreshMetrics
        self.animation = animation
    }
}
