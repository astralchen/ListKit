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

/// 连续列表更新的调度策略。
public enum ListUpdatePolicy: Equatable, Sendable {
    /// 合并兼容的待执行更新，被后续请求取代的旧请求以 `superseded` 状态结束。
    case coalesceLatest
    /// 等待前一个更新完成后，严格按调用顺序提交。
    case serial
}

/// 声明式滚动目标。
public struct ListScrollTarget: Hashable, Sendable {
    let rowID: AnyListID
    let sectionID: AnyListID?

    /// 使用条目标识符创建滚动目标。
    public init<RowID>(_ rowID: RowID) where RowID: Hashable & Sendable {
        self.rowID = AnyListID(rowID)
        self.sectionID = nil
    }

    /// 使用条目与分区标识符创建限定分区的滚动目标。
    public init<RowID, SectionID>(
        _ rowID: RowID,
        in sectionID: SectionID
    ) where RowID: Hashable & Sendable, SectionID: Hashable & Sendable {
        self.rowID = AnyListID(rowID)
        self.sectionID = AnyListID(sectionID)
    }
}

/// 更新完成后，滚动目标在视口中的对齐位置。
///
/// 顶部、居中与底部均沿垂直方向解释，不随集合视图的滚动轴自动交换。
public enum ListScrollPosition: Equatable, Sendable {
    /// 将目标对齐到 viewport 顶部。
    case top
    /// 将目标对齐到视口的垂直中心。
    case center
    /// 将目标对齐到 viewport 底部。
    case bottom
    /// 仅滚动到足以显示目标的最近位置。
    case nearest
}

/// 列表更新期间采用的声明式滚动行为。
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

    /// 保持首个匹配可见条目相对于视口顶部的距离。
    ///
    /// 通过调整垂直偏移并在必要时补偿底部内边距实现，同时恢复原水平偏移。
    /// 目标更新前不可见或更新后不存在时不执行位置恢复；不跟踪横向条目的相对位移。
    public static func preserveVisiblePosition(
        of target: ListScrollTarget
    ) -> ListScrollBehavior {
        ListScrollBehavior(storage: .preserveVisiblePosition(target))
    }

    /// 更新后滚动到快照中首个匹配的条目；未匹配时不发起滚动。
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

/// 控制一次列表更新的动画、调度和滚动行为的事务。
///
/// 事务控制各类系统动画是否启用；差异快照动画的持续时间和
/// 曲线由 UIKit 决定。条目的内容过渡通过 `contentTransition(_:)` 单独配置。
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

/// 自动或主动条目刷新的目标范围。
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
    /// 重配内容，并按指定策略决定是否额外使布局失效。
    /// 可见范围直接调用现有单元格的配置闭包，全部匹配范围使用差异快照重配。
    /// 单独执行重配不调用 `prepareForReuse`；与其他请求合并后可能升级为重载。
    case reconfigure(layout: ListRefreshLayoutPolicy)
    /// 请求完整 reload/configuration 路径；UIKit 不保证最终 Cell 对象地址发生变化。
    case reload
}

/// 条目内容刷新的触发条件、目标范围与执行动作。
public struct ListRowRefreshRule: Equatable, Sendable {
    /// 应用列表更新时触发内容刷新的条件，默认为 `automatic`。
    public var trigger: ListRefreshTrigger
    /// 满足刷新条件后参与更新的条目范围，默认为当前可见条目。
    public var scope: ListRefreshScope
    /// 刷新条目所采用的生命周期，默认重配内容而不额外使布局失效。
    public var action: ListRowRefreshAction

    /// 创建条目的内容刷新规则。
    ///
    /// - Parameters:
    ///   - trigger: 刷新触发条件，默认为 `automatic`。
    ///   - scope: 刷新范围，默认为 `visible`。
    ///   - action: 执行动作，默认重配内容且不额外使布局失效。
    public init(
        trigger: ListRefreshTrigger = .automatic,
        scope: ListRefreshScope = .visible,
        action: ListRowRefreshAction = .reconfigure(layout: .none)
    ) {
        self.trigger = trigger
        self.scope = scope
        self.action = action
    }

    /// 使用自动触发、可见范围和无额外布局失效的内容重配规则。
    public static let automatic = ListRowRefreshRule()
}

/// Supplementary 内容刷新时使用的 UIKit 生命周期。
public enum ListSupplementaryRefreshAction: Equatable, Sendable {
    /// 直接重配当前存在的 supplementary view。
    case reconfigureVisible(layout: ListRefreshLayoutPolicy)
    /// 重载所属 Section，会连带重载其中的 Row。
    case reloadSection
}

/// 附属视图内容刷新的触发条件与执行动作。
public struct ListSupplementaryRefreshRule: Equatable, Sendable {
    /// 应用列表更新时触发附属视图刷新的条件，默认为 `automatic`。
    public var trigger: ListRefreshTrigger
    /// 刷新附属视图所采用的生命周期，默认重配当前可见视图。
    public var action: ListSupplementaryRefreshAction

    /// 创建附属视图的内容刷新规则。
    ///
    /// - Parameters:
    ///   - trigger: 刷新触发条件，默认为 `automatic`。
    ///   - action: 执行动作，默认重配可见视图且不额外使布局失效。
    public init(
        trigger: ListRefreshTrigger = .automatic,
        action: ListSupplementaryRefreshAction = .reconfigureVisible(layout: .none)
    ) {
        self.trigger = trigger
        self.action = action
    }

    /// 使用自动触发和可见视图内容重配的规则，不额外使布局失效。
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

/// 列表更新摘要中的提交与完成状态。
public enum ListApplyCompletionState: Equatable, Sendable {
    /// 请求已接受或进入队列，尚未返回最终处理结果。
    case submitted
    /// 请求已处理结束，包括因诊断问题而跳过提交的情况。
    /// 正常提交时等待快照、布局和内容过渡处理，但不等待已发起的滚动动画结束。
    case completed
    /// 请求被后续可合并的更新取代，未作为独立请求执行完成。
    case superseded
    /// 请求在提交前取消，例如异步任务取消，或列表及适配器已释放。
    case cancelledBeforeCommit
}

/// 一次列表更新中规划或执行的刷新动作计数。
public struct ListRefreshMetrics: Equatable, Sendable {
    /// 通过差异快照请求重配的条目数量。
    public let snapshotReconfiguredRowCount: Int
    /// 直接重配可见单元格的条目数量。
    public let visibleReconfiguredRowCount: Int
    /// 请求重新加载的条目数量。
    public let reloadedRowCount: Int
    /// 重配的可见附属视图数量。
    public let visibleReconfiguredSupplementaryCount: Int
    /// 请求重新加载的分区数量。
    public let reloadedSectionCount: Int

    /// 使用各类刷新动作的计数创建指标。
    ///
    /// - Parameters:
    ///   - snapshotReconfiguredRowCount: 通过差异快照请求重配的条目数量。默认值为 0。
    ///   - visibleReconfiguredRowCount: 直接重配可见单元格的条目数量。默认值为 0。
    ///   - reloadedRowCount: 请求重新加载的条目数量。默认值为 0。
    ///   - visibleReconfiguredSupplementaryCount: 重配的可见附属视图数量。默认值为 0。
    ///   - reloadedSectionCount: 请求重新加载的分区数量。默认值为 0。
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

    /// 所有刷新动作计数均为零的指标。
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
    /// 内容过渡计数；条目过渡或可见条目重载按条目计数，全量淡入淡出按整列表一次计数。
    public let contentTransitionCount: Int
    /// 本次 apply 是否触发布局失效或重新计算。
    public let layoutInvalidated: Bool
    /// ListKit 是否请求了布局动画。
    public let layoutAnimated: Bool
    /// ListKit 是否请求了滚动动画。
    public let scrollAnimated: Bool
    /// 为维持可见锚点而额外保留的底部内容内边距，单位为点，不是滚动偏移变化量。
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
/// 返回最终状态，并补充可见刷新、布局、滚动请求和内容过渡统计。
/// 插入、删除和移动计数描述新旧声明的差异；即使诊断阻止提交，也可能非零。
///
/// 这些字段用于 diagnostics、日志、性能观察和测试断言；不应作为数据源状态的唯一依据。
public struct ListApplySummary: Equatable, Sendable {
    /// 新插入的 Section 数量。
    public let insertedSectionCount: Int
    /// 被删除的 Section 数量。
    public let deletedSectionCount: Int
    /// 由新旧分区顺序的差异推断出的移动数量，不统计因前方插入或删除而产生的索引平移。
    public let movedSectionCount: Int
    /// 新旧 snapshot 中都存在的 Section 数量。
    public let keptSectionCount: Int
    /// 新插入的 Row 数量。
    public let insertedRowCount: Int
    /// 被删除的 Row 数量。
    public let deletedRowCount: Int
    /// 差异算法推断出的分区内条目移动数量；跨分区迁移按删除和插入统计。
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

/// 一次主动条目或分区刷新的提交与完成摘要。
public struct ListRefreshSummary: Equatable, Sendable {
    /// 请求中去重后的业务条目标识符或分区标识符数量。
    public let requestedTargetCount: Int
    /// 在执行时的快照与刷新范围内匹配到的展示身份或分区数量。
    /// 一个业务条目标识符可匹配多个展示身份，因此此值可能大于请求目标数。
    public let matchedTargetCount: Int
    /// 本次刷新规划或执行的各类动作计数。
    public let refreshMetrics: ListRefreshMetrics
    /// 本次刷新的提交状态与动画执行摘要。
    public let animation: ListAnimationSummary

    /// 创建一次主动刷新的结果摘要。
    ///
    /// - Parameters:
    ///   - requestedTargetCount: 请求目标数量，默认为 0。
    ///   - matchedTargetCount: 匹配目标数量，默认为 0。
    ///   - refreshMetrics: 刷新动作计数，默认全部为零。
    ///   - animation: 提交状态与动画摘要，默认使用空摘要。
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
