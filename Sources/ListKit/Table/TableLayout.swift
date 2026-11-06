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
    /// 当前分区的默认行高；单行可以通过 TableRow.height(_:) 完整覆盖。
    public private(set) var rowHeight: TableHeight?
    /// 当前分区已声明的自定义或系统标题页眉的高度。
    public private(set) var headerHeight: TableHeight?
    /// 当前分区已声明的自定义或系统标题页脚的高度。
    public private(set) var footerHeight: TableHeight?

    /// 创建未指定任何高度的布局。
    public init() {}

    /// 设置未显式声明高度的行所使用的规则。
    public func rowHeight(_ height: TableHeight) -> Self {
        var copy = self
        copy.rowHeight = height
        return copy
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
