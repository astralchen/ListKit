import UIKit

/// 表格条目、页眉或页脚的高度规则。
public enum TableHeight: Equatable, Sendable {
    /// 固定高度。
    case fixed(CGFloat)
    /// 由 UIKit 测量内容并自动估算高度。
    case automatic
    /// 自动高度，并使用指定估算高度。
    case estimated(CGFloat)

    @MainActor var resolvedHeight: CGFloat {
        switch self {
        case .fixed(let height):
            return height
        case .automatic, .estimated:
            return UITableView.automaticDimension
        }
    }

    @MainActor var resolvedEstimatedHeight: CGFloat {
        switch self {
        case .fixed(let height):
            return height
        case .automatic:
            return UITableView.automaticDimension
        case .estimated(let height):
            return height
        }
    }
}

/// 一个 TableSection 的高度配置。省略的规则依次回退到外部代理及 UITableView 默认值。
public struct TableLayout: Equatable, Sendable {
    /// 统一设置的行高。按 ID 配置或省略行高时为 `nil`。
    public private(set) var rowHeight: TableHeight?
    private var rowHeightProvider: RowHeightProvider?
    /// 当前分区已声明的自定义或系统标题页眉的高度。
    public private(set) var headerHeight: TableHeight?
    /// 当前分区已声明的自定义或系统标题页脚的高度。
    public private(set) var footerHeight: TableHeight?

    /// 创建未指定任何高度的布局。
    public init() {}

    /// 设置当前分区所有行的高度规则。
    public func rowHeight(_ height: TableHeight) -> Self {
        var copy = self
        copy.rowHeight = height
        copy.rowHeightProvider = nil
        return copy
    }

    /// 按稳定行 ID 设置高度规则。每次 `apply` 或 `reloadAll` 执行时为每行求值，实际高度与估算高度共用该结果。
    /// 闭包收到 `TableRow` 声明或从 `TableForEach` 继承的 ID，可用 `typed(_:)` 取出原始值。
    /// 两个 `rowHeight` 重载都替换先前的行高配置。
    public func rowHeight(_ resolve: @escaping @MainActor @Sendable (AnyListID) -> TableHeight) -> Self {
        var copy = self
        copy.rowHeight = nil
        copy.rowHeightProvider = RowHeightProvider(resolve)
        return copy
    }

    @MainActor func height(for rowID: AnyListID) -> TableHeight? {
        rowHeightProvider?.resolve(rowID) ?? rowHeight
    }

    // 布局副本共享同一声明。adapter 按每行实际解析出的规则判断是否需要重新测量。
    private final class RowHeightProvider: Equatable, Sendable {
        let resolve: @MainActor @Sendable (AnyListID) -> TableHeight

        init(_ resolve: @escaping @MainActor @Sendable (AnyListID) -> TableHeight) {
            self.resolve = resolve
        }

        static func == (lhs: RowHeightProvider, rhs: RowHeightProvider) -> Bool { lhs === rhs }
    }

    /// 设置已有页眉的高度；此规则本身不会创建页眉。
    public func headerHeight(_ height: TableHeight) -> Self {
        var copy = self
        copy.headerHeight = height
        return copy
    }

    /// 设置已有页脚的高度；此规则本身不会创建页脚。
    public func footerHeight(_ height: TableHeight) -> Self {
        var copy = self
        copy.footerHeight = height
        return copy
    }
}
