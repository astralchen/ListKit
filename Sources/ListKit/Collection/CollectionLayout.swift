import UIKit

// MARK: - Layout Model

/// 组合布局的主滚动方向。
public enum ListLayoutScrollDirection: Hashable, Sendable {
    /// Section 沿垂直方向排列。
    case vertical
    /// Section 沿水平方向排列。
    case horizontal

    var uiKitValue: UICollectionView.ScrollDirection {
        switch self {
        case .vertical: return .vertical
        case .horizontal: return .horizontal
        }
    }
}

/// 组合布局计算全局内容区域时使用的系统内边距参考。
public enum ListContentInsetsReference: Hashable, Sendable {
    /// 保留 UIKit 创建 `UICollectionViewCompositionalLayoutConfiguration` 时的系统默认值。
    ///
    /// ListKit 不会写入 `contentInsetsReference`。这与显式设置 `.automatic` 不同：
    /// `.automatic` 会主动把 UIKit 属性改为 `UIContentInsetsReference.automatic`。
    case systemDefault
    /// 由 UIKit 根据当前容器自动选择 inset 参考。
    case automatic
    /// 不使用系统内容 inset 参考。
    case none
    /// 以 collection view safe area 为参考。
    case safeArea
    /// 以 collection view layout margins 为参考。
    case layoutMargins
    /// 以 readable content guide 为参考。
    case readableContent

    var uiKitOverride: UIContentInsetsReference? {
        switch self {
        case .systemDefault: return nil
        case .automatic: return .automatic
        case .none: return UIContentInsetsReference.none
        case .safeArea: return .safeArea
        case .layoutMargins: return .layoutMargins
        case .readableContent: return .readableContent
        }
    }
}

/// 组合布局的全局滚动方向、分区间距与内边距参考配置。
public struct ListCompositionalLayoutConfiguration: Hashable, Sendable {
    /// compositional layout 的主滚动方向；`nil` 保留 UIKit 默认值。
    public var scrollDirection: ListLayoutScrollDirection?
    /// 相邻 Section 之间的间距，须为有限非负数；`nil` 保留 UIKit 默认值。
    public var interSectionSpacing: CGFloat?
    /// 全局内容区域采用的系统 inset 参考；默认保留 UIKit 的系统设置。
    public var contentInsetsReference: ListContentInsetsReference

    /// 创建 compositional layout 全局配置。
    ///
    /// - Parameters:
    ///   - scrollDirection: 主滚动方向；`nil` 时不写入 UIKit。
    ///   - interSectionSpacing: 相邻 Section 间距；`nil` 时不写入 UIKit。
    ///   - contentInsetsReference: 全局内容 inset 参考。默认 `.systemDefault`，ListKit
    ///     不主动改写 UIKit；只有传入其他值时才显式覆盖。
    public init(
        scrollDirection: ListLayoutScrollDirection? = nil,
        interSectionSpacing: CGFloat? = nil,
        contentInsetsReference: ListContentInsetsReference = .systemDefault
    ) {
        self.scrollDirection = scrollDirection
        self.interSectionSpacing = interSectionSpacing
        self.contentInsetsReference = contentInsetsReference
    }

    @MainActor func makeConfiguration() -> UICollectionViewCompositionalLayoutConfiguration {
        precondition(
            interSectionSpacing.map { $0.isFinite && $0 >= 0 } ?? true,
            "ListKit: interSectionSpacing must be finite and nonnegative")
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        if let scrollDirection {
            configuration.scrollDirection = scrollDirection.uiKitValue
        }
        if let interSectionSpacing {
            configuration.interSectionSpacing = interSectionSpacing
        }
        if let contentInsetsReference = contentInsetsReference.uiKitOverride {
            configuration.contentInsetsReference = contentInsetsReference
        }
        return configuration
    }
}

/// 组合布局中单个维度的尺寸规则。
///
/// - Note: 这里不用直接保存 `NSCollectionLayoutDimension`，因为 UIKit 类型不是 DSL
/// `Hashable & Sendable` 模型。真正生成 layout 时再转换成 UIKit 类型。
public enum ListLayoutDimension: Hashable, Sendable {
    /// 固定点数尺寸。
    case absolute(CGFloat)
    /// 内容测量的初始估算尺寸；最终尺寸取决于 UIKit 与视图的 self-sizing 实现。
    /// 仅作用于使用此 dimension 的 item、group 或 supplementary，不会自动向父子层级传播。
    case estimated(CGFloat)
    /// 相对 UIKit 所在布局层级的容器宽度的比例，不是固定相对屏幕或 collection view 宽度。
    case fractionalWidth(CGFloat)
    /// 相对 UIKit 所在布局层级的容器高度的比例，不是固定相对屏幕或 collection view 高度。
    case fractionalHeight(CGFloat)

    @MainActor func makeDimension() -> NSCollectionLayoutDimension {
        switch self {
        case .absolute(let value):
            return .absolute(value)
        case .estimated(let value):
            return .estimated(value)
        case .fractionalWidth(let value):
            return .fractionalWidth(value)
        case .fractionalHeight(let value):
            return .fractionalHeight(value)
        }
    }


}

/// 使用逻辑起止方向的布局内边距。
public struct ListLayoutInsets: Hashable, Sendable {
    /// 顶部 inset。
    public var top: CGFloat
    /// 逻辑 leading 方向 inset。
    public var leading: CGFloat
    /// 底部 inset。
    public var bottom: CGFloat
    /// 逻辑 trailing 方向 inset。
    public var trailing: CGFloat

    /// 创建方向性 inset。
    ///
    /// - Parameters:
    ///   - top: 顶部 inset。
    ///   - leading: 逻辑起始侧的内边距。
    ///   - bottom: 底部 inset。
    ///   - trailing: 逻辑结束侧的内边距。
    public init(top: CGFloat = 0, leading: CGFloat = 0, bottom: CGFloat = 0, trailing: CGFloat = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    /// 创建四边相同的 inset。
    ///
    /// - Parameter value: 四边共用的 inset。
    public init(_ value: CGFloat) {
        self.init(top: value, leading: value, bottom: value, trailing: value)
    }

    /// 零 inset。
    public static let zero = ListLayoutInsets()

    /// 与当前值对应的 UIKit 方向性内边距。
    public var directionalEdgeInsets: NSDirectionalEdgeInsets {
        NSDirectionalEdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing)
    }
}

/// 布局中的二维偏移量。
public struct ListLayoutPoint: Hashable, Sendable {
    /// 水平方向偏移。
    public var x: CGFloat
    /// 垂直方向偏移。
    public var y: CGFloat

    /// 创建二维偏移。
    ///
    /// - Parameters:
    ///   - x: 水平方向偏移。
    ///   - y: 垂直方向偏移。
    public init(x: CGFloat = 0, y: CGFloat = 0) {
        self.x = x
        self.y = y
    }

    /// 从 `CGPoint` 创建二维偏移。
    ///
    /// - Parameter point: UIKit 坐标点。
    public init(_ point: CGPoint) {
        self.init(x: point.x, y: point.y)
    }

    /// 零偏移。
    public static let zero = ListLayoutPoint()

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

/// Section 相对于外层 collection 主轴的正交滚动行为，直接映射到 UIKit 对应枚举。
///
/// 外层为纵向时，正交滚动为横向；外层为横向时，正交滚动为纵向。
/// 停靠和分页所指的 group 是创建 Section 时传入的顶层 group，不是单个 item。
public enum ListOrthogonalScrollingBehavior: Hashable, Sendable {
    /// 连续滚动，不按 group 边界停靠。
    case continuous
    /// 连续滚动，在可见 group 的 leading 边界自然停靠，不是逐 item 对齐。
    case continuousGroupLeadingBoundary
    /// 使用 UIKit 的正交分页行为；不指定以 group 为分页单位。
    case paging
    /// 以顶层 group 为单位分页；页的几何由 group 尺寸决定。
    case groupPaging
    /// 以顶层 group 为单位分页，并将 group 居中；不保证单个 item 居中。
    case groupPagingCentered

    var uiKitValue: UICollectionLayoutSectionOrthogonalScrollingBehavior {
        switch self {
        case .continuous: return .continuous
        case .continuousGroupLeadingBoundary: return .continuousGroupLeadingBoundary
        case .paging: return .paging
        case .groupPaging: return .groupPaging
        case .groupPagingCentered: return .groupPagingCentered
        }
    }
}

/// UIKit 原生列表分区的外观样式。
public enum ListUIKitListAppearance: Hashable, Sendable {
    /// 无分组背景的标准列表外观。
    case plain
    /// 使用分组背景的列表外观。
    case grouped
    /// 分组内容向两侧内缩的列表外观。
    case insetGrouped
    /// 用于侧边栏导航的列表外观。
    case sidebar
    /// 不使用侧边栏分组背景的列表外观。
    case sidebarPlain

    var uiKitValue: UICollectionLayoutListConfiguration.Appearance {
        switch self {
        case .plain: return .plain
        case .grouped: return .grouped
        case .insetGrouped: return .insetGrouped
        case .sidebar: return .sidebar
        case .sidebarPlain: return .sidebarPlain
        }
    }
}

/// UIKit 原生列表分区的布局配置。
///
/// 使用此布局时，条目的滑动操作接入
/// `UICollectionLayoutListConfiguration`，同时保留 ListKit 的 diffable identity。
/// 未调用 `.sectionInsets(...)` 时保留 UIKit 生成的 Section inset；显式调用则覆盖它。
/// 不支持 item-level supplementary；已匹配内容的此类声明会被 adapter 拒绝。
public struct ListUIKitListLayout: Hashable, Sendable {
    var options = ListSectionLayoutOptions()
    /// UIKit list section 的视觉样式。
    public var appearance: ListUIKitListAppearance
    /// 是否显示系统分隔线；`nil` 保留 UIKit 根据 appearance 提供的默认值。
    public var showsSeparators: Bool?
    /// 原样传给 UIKit List configuration 的 headerTopPadding；`nil` 保留系统默认值。
    /// 此属性不会创建 header，也不替代 boundary 的尺寸、offset 或 Section inset 配置。
    public var headerTopPadding: CGFloat?

    /// 创建 UIKit 原生 list section 配置。
    ///
    /// - Parameters:
    ///   - appearance: 系统 list 外观。
    ///   - showsSeparators: 是否显示系统分隔线；`nil` 时不写入 UIKit。
    ///   - headerTopPadding: UIKit List 的 headerTopPadding，须为有限非负数；`nil` 保留默认值。
    public init(
        appearance: ListUIKitListAppearance = .plain,
        showsSeparators: Bool? = nil,
        headerTopPadding: CGFloat? = nil
    ) {
        self.appearance = appearance
        self.showsSeparators = showsSeparators
        self.headerTopPadding = headerTopPadding
    }

    @MainActor func makeConfiguration() -> UICollectionLayoutListConfiguration {
        var configuration = UICollectionLayoutListConfiguration(appearance: appearance.uiKitValue)
        if let showsSeparators {
            configuration.showsSeparators = showsSeparators
        }
        if #available(iOS 15.0, tvOS 15.0, *), let headerTopPadding {
            configuration.headerTopPadding = headerTopPadding
        }
        return configuration
    }
}

/// 创建 UIKit 原生列表分区布局。
///
/// 使用 `ListUIKitListLayout` 的系统默认值与限制；需要自定义边界补充视图时显式声明其布局和内容。
/// 本入口保留 UIKit 原生列表能力；普通列表使用单轨道 GridLayout。
///
/// - Parameters:
///   - appearance: 列表外观，默认为 `plain`。
///   - showsSeparators: 是否显示系统分隔线；`nil` 保留当前外观的系统默认值。
///   - headerTopPadding: 页眉顶部间距，须为有限非负数；`nil` 保留系统默认值。
/// - Returns: 可放入分区布局构建器的 UIKit 列表配置。
public func UIKitListLayout(
    appearance: ListUIKitListAppearance = .plain,
    showsSeparators: Bool? = nil,
    headerTopPadding: CGFloat? = nil
) -> ListUIKitListLayout {
    .init(
        appearance: appearance, showsSeparators: showsSeparators, headerTopPadding: headerTopPadding)
}

/// 内建 Section 布局；普通列表与网格共用 gridConfiguration。
public enum ListSectionLayout: Hashable, Sendable {
    /// 使用网格配置生成分区布局。
    case gridConfiguration(ListSectionGridLayout)
    /// 使用 UIKit 原生列表配置生成分区布局。
    case uiKitListConfiguration(ListUIKitListLayout)

    /// 未声明布局、空分支及解析失败时使用的单轨道估算布局。
    static var defaultLayout: Self {
        .gridConfiguration(GridLayout(tracks: 1))
    }

    @MainActor func makeCompositionalSection(
        environment: any NSCollectionLayoutEnvironment,
        itemSupplementaries: [NSCollectionLayoutSupplementaryItem],
        scrollDirection: ListLayoutScrollDirection = .vertical
    ) -> NSCollectionLayoutSection {
        switch self {
        case .gridConfiguration(let configuration):
            return configuration.makeSection(
                environment: environment,
                itemSupplementaries: itemSupplementaries, scrollDirection: scrollDirection)
        case .uiKitListConfiguration:
            preconditionFailure("ListKit: UIKitListLayout requires adapter configuration")
        }
    }

    var gridLayout: ListSectionGridLayout? {
        guard case .gridConfiguration(let value) = self else { return nil }
        return value
    }

    var uiKitListLayout: ListUIKitListLayout? {
        guard case .uiKitListConfiguration(let configuration) = self else { return nil }
        return configuration
    }
}

/// 附属视图相对于所属条目的锚点。
/// leading / trailing 使用 UIKit 的方向性语义，不表示固定左侧或右侧；top / bottom 不随滚动轴互换。
public enum ListItemSupplementaryAnchor: Hashable, Sendable {
    /// 顶部与 leading 边缘的交点。
    case topLeading
    /// 顶部居中。
    case top
    /// 顶部与 trailing 边缘的交点。
    case topTrailing
    /// leading 边缘居中。
    case leading
    /// item 使用无边缘的中心锚点。
    case center
    /// trailing 边缘居中。
    case trailing
    /// 底部与 leading 边缘的交点。
    case bottomLeading
    /// 底部居中。
    case bottom
    /// 底部与 trailing 边缘的交点。
    case bottomTrailing

    var directionalEdges: NSDirectionalRectEdge {
        switch self {
        case .topLeading:
            return [.top, .leading]
        case .top:
            return [.top]
        case .topTrailing:
            return [.top, .trailing]
        case .leading:
            return [.leading]
        case .center:
            return []
        case .trailing:
            return [.trailing]
        case .bottomLeading:
            return [.bottom, .leading]
        case .bottom:
            return [.bottom]
        case .bottomTrailing:
            return [.bottom, .trailing]
        }
    }
}

/// Section 边界位置，直接映射 UIKit alignment；不随内容轴转置。
/// none 保留 UIKit 的无边界对齐语义，不承诺居中。item 居中使用 ListItemSupplementaryAnchor.center。
public enum ListBoundaryAlignment: Hashable, Sendable {
    /// 边界视图在容器中的对齐位置。
    ///
    /// `top` 和 `bottom` 表示上下边缘，`leading` 和 `trailing` 表示逻辑起始侧与结束侧；组合值表示角点。
    /// `none` 不指定对齐边缘。
    case topLeading, top, topTrailing, leading, none, trailing, bottomLeading, bottom, bottomTrailing
    var boundaryAlignment: NSRectAlignment {
        switch self {
        case .topLeading:
            return .topLeading
        case .top:
            return .top
        case .topTrailing:
            return .topTrailing
        case .leading:
            return .leading
        case .none:
            return .none
        case .trailing:
            return .trailing
        case .bottomLeading:
            return .bottomLeading
        case .bottom:
            return .bottom
        case .bottomTrailing:
            return .bottomTrailing
        }
    }

}
