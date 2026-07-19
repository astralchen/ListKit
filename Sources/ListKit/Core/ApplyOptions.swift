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

/// 连续 async apply 的调度方式。
public enum ListUpdatePolicy: Equatable, Sendable {
    /// 新 apply 立即提交；尚未完成的旧 apply 会以 `.superseded` 结束。
    case coalesceLatest
    /// 等待前一个 async apply 完成后再按调用顺序提交。
    case serial
}

/// 声明式滚动目标。
public struct ListScrollTarget: Hashable, Sendable {
    let rowID: AnyListID
    let sectionID: AnyListID?

    /// 使用业务 Row id 创建目标。
    public init<RowID>(_ rowID: RowID) where RowID: Hashable & Sendable {
        self.rowID = AnyListID(rowID)
        self.sectionID = nil
    }

    /// 使用业务 Row id 和 section id 创建无歧义目标。
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
    case top
    case center
    case bottom
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
    public var snapshotAnimation: ListAnimationPolicy
    public var outlineAnimation: ListAnimationPolicy
    public var layoutAnimation: ListAnimationPolicy
    public var contentAnimation: ListAnimationPolicy
    public var scrollAnimation: ListAnimationPolicy
    public var updatePolicy: ListUpdatePolicy
    public var scrollBehavior: ListScrollBehavior
    public var respectsReduceMotion: Bool

    /// 创建 transaction。未单独指定的作用域继承 `animation`。
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

    public static let automatic = ListTransaction()
    public static let disabled = ListTransaction(animation: .disabled)

    /// 同时设置所有动画作用域。
    public func animation(_ policy: ListAnimationPolicy) -> Self {
        var copy = self
        copy.snapshotAnimation = policy
        copy.outlineAnimation = policy
        copy.layoutAnimation = policy
        copy.contentAnimation = policy
        copy.scrollAnimation = policy
        return copy
    }

    public func snapshotAnimation(_ policy: ListAnimationPolicy) -> Self {
        var copy = self
        copy.snapshotAnimation = policy
        return copy
    }

    public func outlineAnimation(_ policy: ListAnimationPolicy) -> Self {
        var copy = self
        copy.outlineAnimation = policy
        return copy
    }

    public func layoutAnimation(_ policy: ListAnimationPolicy) -> Self {
        var copy = self
        copy.layoutAnimation = policy
        return copy
    }

    public func contentAnimation(_ policy: ListAnimationPolicy) -> Self {
        var copy = self
        copy.contentAnimation = policy
        return copy
    }

    public func scrollAnimation(_ policy: ListAnimationPolicy) -> Self {
        var copy = self
        copy.scrollAnimation = policy
        return copy
    }

    public func updatePolicy(_ policy: ListUpdatePolicy) -> Self {
        var copy = self
        copy.updatePolicy = policy
        return copy
    }

    public func scrollBehavior(_ behavior: ListScrollBehavior) -> Self {
        var copy = self
        copy.scrollBehavior = behavior
        return copy
    }

    public func respectsReduceMotion(_ enabled: Bool = true) -> Self {
        var copy = self
        copy.respectsReduceMotion = enabled
        return copy
    }

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

struct ListResolvedTransaction {
    let snapshotAnimation: Bool
    let outlineAnimation: Bool
    let layoutAnimation: Bool
    let contentAnimation: Bool
    let scrollAnimation: Bool
    let updatePolicy: ListUpdatePolicy
    let scrollBehavior: ListScrollBehavior
    let reduceMotionApplied: Bool
}

// MARK: - Apply Options

/// apply 级刷新策略。
public enum ListApplyRefreshStrategy: Equatable, Sendable {
    /// 按 Row policy 自动选择 diffable 或可见刷新。
    case automatic
    /// 不标记 snapshot refresh，只重配符合 Row policy 的可见节点。
    case visibleOnly
    /// 只执行 `refreshID` 驱动的 diffable refresh，不额外重配可见节点。
    case diffableOnly
    /// 忽略 Row policy，对所有新旧 snapshot 中都存在的 Row 执行 diffable reload。
    case forceReload
}

/// diffable snapshot 的提交方式。
public enum ListSnapshotApplicationMode: Equatable, Sendable {
    case differences
    case reloadData
}

/// `apply` 的完整配置。
public struct ListApplyOptions: Sendable {
    public var transaction: ListTransaction
    public var refreshStrategy: ListApplyRefreshStrategy
    public var applicationMode: ListSnapshotApplicationMode
    public var diagnostics: ListDiagnosticsOptions

    public init(
        transaction: ListTransaction = .automatic,
        refreshStrategy: ListApplyRefreshStrategy = .automatic,
        applicationMode: ListSnapshotApplicationMode = .differences,
        diagnostics: ListDiagnosticsOptions = .debugDefault
    ) {
        self.transaction = transaction
        self.refreshStrategy = refreshStrategy
        self.applicationMode = applicationMode
        self.diagnostics = diagnostics
    }
}

// MARK: - Apply Diagnostics

/// async apply 的最终状态。
public enum ListApplyCompletionState: Equatable, Sendable {
    case submitted
    case completed
    case superseded
    case cancelledBeforeCommit
}

/// 本次 apply 实际执行的动画诊断。
public struct ListAnimationSummary: Equatable, Sendable {
    public let completionState: ListApplyCompletionState
    public let snapshotAnimated: Bool
    public let animatedSectionCount: Int
    public let outlineAnimatedSectionCount: Int
    public let contentTransitionCount: Int
    public let layoutInvalidated: Bool
    public let layoutAnimated: Bool
    public let scrollAnimated: Bool
    public let anchorCompensation: CGFloat
    public let reduceMotionApplied: Bool

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

/// apply 后的摘要，DEBUG 日志和测试都复用这份数据。
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
    public let insertedCount: Int
    /// 被删除的 Row 数量。
    public let deletedCount: Int
    /// 在同一 Section 内发生移动的 Row 数量。
    public let movedCount: Int
    /// 新旧 snapshot 中都存在的 Row 数量。
    public let keptCount: Int
    public let refreshIDChangedCount: Int
    public let snapshotRefreshCount: Int
    public let visibleRefreshCount: Int
    public let supplementaryRefreshIDChangedCount: Int
    public let visibleSupplementaryRefreshCount: Int
    public let diagnosticsIssues: [ListDiagnosticsIssue]
    public let animation: ListAnimationSummary

    public init(
        insertedSectionCount: Int = 0,
        deletedSectionCount: Int = 0,
        movedSectionCount: Int = 0,
        keptSectionCount: Int = 0,
        insertedCount: Int = 0,
        deletedCount: Int = 0,
        movedCount: Int = 0,
        keptCount: Int = 0,
        refreshIDChangedCount: Int = 0,
        snapshotRefreshCount: Int = 0,
        visibleRefreshCount: Int = 0,
        supplementaryRefreshIDChangedCount: Int = 0,
        visibleSupplementaryRefreshCount: Int = 0,
        diagnosticsIssues: [ListDiagnosticsIssue] = [],
        animation: ListAnimationSummary = ListAnimationSummary()
    ) {
        self.insertedSectionCount = insertedSectionCount
        self.deletedSectionCount = deletedSectionCount
        self.movedSectionCount = movedSectionCount
        self.keptSectionCount = keptSectionCount
        self.insertedCount = insertedCount
        self.deletedCount = deletedCount
        self.movedCount = movedCount
        self.keptCount = keptCount
        self.refreshIDChangedCount = refreshIDChangedCount
        self.snapshotRefreshCount = snapshotRefreshCount
        self.visibleRefreshCount = visibleRefreshCount
        self.supplementaryRefreshIDChangedCount = supplementaryRefreshIDChangedCount
        self.visibleSupplementaryRefreshCount = visibleSupplementaryRefreshCount
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
            insertedCount: insertedCount,
            deletedCount: deletedCount,
            movedCount: movedCount,
            keptCount: keptCount,
            refreshIDChangedCount: refreshIDChangedCount,
            snapshotRefreshCount: snapshotRefreshCount,
            visibleRefreshCount: visibleRefreshCount,
            supplementaryRefreshIDChangedCount: supplementaryRefreshIDChangedCount,
            visibleSupplementaryRefreshCount: visibleSupplementaryRefreshCount,
            diagnosticsIssues: diagnosticsIssues,
            animation: animation
        )
    }
}
