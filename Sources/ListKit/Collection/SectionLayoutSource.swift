import UIKit

/// Section 唯一的布局来源；内建值、环境选择与 UIKit provider 互斥。
public enum ListSectionLayoutSource<SectionID>: Hashable where SectionID: Hashable & Sendable {
    /// 使用内建网格或 UIKit 列表布局。
    case builtIn(ListSectionLayout)
    /// 通过自定义提供者创建 UIKit 分区布局。
    case custom(ListCustomLayout<SectionID>)
    /// 根据当前布局环境选择完整的分区布局。
    case environment(ListEnvironmentLayout<SectionID>)
}

/// 自定义 UIKit 布局得到的本次解析上下文。
/// itemSupplementaries 必须挂到自定义 item 上；框架无法安全改写任意 UIKit group 树。
@MainActor public struct ListLayoutContext<SectionID> where SectionID: Hashable & Sendable {
    /// 本次解析使用的分区内容与布局声明。
    public let section: ListSection<SectionID>
    /// 分区在当前列表中的位置，从零开始。
    public let sectionIndex: Int
    /// 本次 provider 的真实环境；使用其容器几何计算布局，不缓存为屏幕尺寸。
    public let environment: any NSCollectionLayoutEnvironment
    /// 显式声明的 Section inset；nil 表示保留 provider 自己的设置。
    /// 非 nil 时，provider 返回的 Section.contentInsets 必须与此值一致，框架不会事后替 provider 覆盖。
    public let sectionInsets: ListLayoutInsets?
    /// 将 SectionDecoration 的逻辑 kind 解析为当前注册的实际 elementKind；未声明时返回 nil。
    /// 创建 provider 自有的装饰几何时使用此值，并关闭框架对同一 elementKind 的几何生成，避免重复。
    public func decorationElementKind(for kind: String) -> String? {
        section.decorations.first { $0.kind == kind }?.elementKind
    }
    /// 已与当前内容声明匹配的 item supplementary 几何，须由 provider 显式安装到 item 上。
    public let itemSupplementaries: [NSCollectionLayoutSupplementaryItem]
}

/// 自定义 UIKit Section provider 的值描述；相等性由 layoutKey 与布局修饰配置决定，不比较闭包。
public struct ListCustomLayout<SectionID>: Hashable where SectionID: Hashable & Sendable {
    /// 标识自定义布局捕获状态的稳定键。
    ///
    /// 影响布局的外部状态变化时应更新此键；仅容器环境变化时无需更新。
    public let layoutKey: AnyListID
    var options = ListSectionLayoutOptions()
    let makeSection: @MainActor (ListLayoutContext<SectionID>) -> NSCollectionLayoutSection
    /// 返回布局键及布局选项是否相同，不比较提供者闭包。
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.layoutKey == rhs.layoutKey && lhs.options == rhs.options
    }
    /// 将布局键及布局选项写入哈希器。
    public func hash(into hasher: inout Hasher) {
        hasher.combine(layoutKey)
        hasher.combine(options)
    }
}

/// 创建由提供者构建 UIKit 分区的自定义布局。
///
/// layoutKey 必须包含影响布局的捕获状态。环境变化不需要改 layoutKey；UIKit 会重新调用 provider。
/// 每次解析应按 context 构建 Section，不缓存可变的 UIKit Section 对象。
/// 显式 sectionInsets 须由 provider 使用；item supplementaries 须挂到自定义 item。
/// 若在 boundarySupplementaries 中关联 provider 自有的边界，使用 CustomLayoutBoundary 声明所有权，避免重复创建同 kind 的边界。
/// provider 自有的 decoration 须避免与框架生成的实际 elementKind 重复；可用 `.decorationItems(.none)` 关闭后者。
///
/// - Parameters:
///   - layoutKey: 标识影响布局的外部状态的稳定键，不用于标识分区内容。
///   - sectionInsets: 提供者须应用的分区内边距；为 `nil` 时由提供者自行决定。
///   - makeSection: 根据当前分区和环境创建布局的闭包，在主执行器上调用。
/// - Returns: 可放入分区布局构建器的自定义布局描述。
public func CustomLayout<SectionID, ID>(
    layoutKey: ID,
    sectionInsets: ListLayoutInsets? = nil,
    _ makeSection: @escaping @MainActor (ListLayoutContext<SectionID>) -> NSCollectionLayoutSection
) -> ListCustomLayout<SectionID>
where SectionID: Hashable & Sendable, ID: Hashable & Sendable {
    ListCustomLayout(layoutKey: AnyListID(layoutKey), options: .init(sectionInsets: sectionInsets), makeSection: makeSection)
}

/// 环境布局选择器；相等性仅比较 layoutKey，不比较 resolve 闭包。
public struct ListEnvironmentLayout<SectionID>: Hashable where SectionID: Hashable & Sendable {
    /// 标识环境选择器捕获状态的稳定键。
    ///
    /// 影响选择结果的外部状态变化时应更新此键；仅容器环境变化时无需更新。
    public let layoutKey: AnyListID
    let resolve: @MainActor (any NSCollectionLayoutEnvironment) -> ListSectionLayoutSource<SectionID>?
    /// 返回两个环境选择器的布局键是否相同，不比较选择闭包。
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.layoutKey == rhs.layoutKey }
    /// 将布局键写入哈希器。
    public func hash(into hasher: inout Hasher) { hasher.combine(layoutKey) }
}

/// 创建根据当前容器环境选择分区布局的描述。
///
/// 使用闭包参数提供的容器尺寸，不使用固定屏幕尺寸。
/// 每次选择返回完整布局，包括该分支的 inset、补充视图和装饰几何，不与上次结果合并。
/// 分支为空或返回 nil 时使用默认单轨道估算布局，不会保留上次选择，也不会隐藏 Section。
/// layoutKey 应包含影响选择结果的外部捕获状态；仅容器环境变化时无需更改 layoutKey。
///
/// - Parameters:
///   - layoutKey: 标识影响选择结果的外部状态的稳定键。
///   - resolve: 在主执行器上根据当前环境返回完整布局的构建闭包。
/// - Returns: 延迟到布局解析时选择具体配置的布局来源。
public func EnvironmentLayout<SectionID, ID>(
    layoutKey: ID,
    @ListSectionLayoutBuilder<SectionID> _ resolve:
    @escaping @MainActor (any NSCollectionLayoutEnvironment) -> ListSectionLayoutSource<SectionID>?
) -> ListSectionLayoutSource<SectionID>
where SectionID: Hashable & Sendable, ID: Hashable & Sendable {
    .environment(ListEnvironmentLayout(layoutKey: AnyListID(layoutKey), resolve: resolve))
}

extension ListSectionLayout {
    var options: ListSectionLayoutOptions {
        switch self {
        case .gridConfiguration(let value): value.options
        case .uiKitListConfiguration(let value): value.options
        }
    }
}
extension ListSectionLayoutSource {
    var options: ListSectionLayoutOptions? {
        switch self {
        case .builtIn(let value): value.options
        case .custom(let value): value.options
        case .environment: nil
        }
    }
}

extension ListSectionGridLayout {
    /// 设置当前 Section 的方向性内边距（UIKit Section.contentInsets），重复调用覆盖，不累加。
    /// 不改变 collection view 的 contentInset、cell padding 或 decoration inset。
    public func sectionInsets(_ value: ListLayoutInsets) -> Self {
        var copy = self
        copy.options.sectionInsets = value
        return copy
    }
    /// 完整替换框架声明的 boundary 集合，不追加；空集合移除这些声明，内容注册不受影响。
    public func boundarySupplementaries(
        @ListLayoutArrayBuilder<BoundarySupplementaryLayout> _ content: () ->
        [BoundarySupplementaryLayout]
    ) -> Self {
        var copy = self
        copy.options.boundaries = content().map(ListBoundaryLayout.generated)
        return copy
    }
    /// 完整替换 item supplementary 几何集合，不追加；空集合清除声明，内容注册不受影响。
    /// Grid 启用时要求解析后的轨道尺寸相等、轨道间距一致。
    /// 异构轨道会被 adapter 拒绝；自适应多 line 使用内部 kind/indexPath 映射，业务内容仍只声明一次。
    public func itemSupplementaries(
        @ListLayoutArrayBuilder<ItemSupplementaryLayout> _ content: () -> [ItemSupplementaryLayout]
    ) -> Self {
        var copy = self
        copy.options.items = content()
        return copy
    }
    /// 显式选择注册背景默认策略，替换此前的几何集合或策略。
    public func decorationItems(_ policy: ListDecorationLayoutPolicy) -> Self {
        var copy = self
        copy.options.decorations = policy == .registeredBackgrounds ? nil : []
        return copy
    }
    /// 完整替换框架生成的 decoration 几何；空集合等价于 .none。
    public func decorationItems(
        @ListLayoutArrayBuilder<DecorationItemLayout> _ content: () -> [DecorationItemLayout]
    ) -> Self {
        var copy = self
        copy.options.decorations = content()
        return copy
    }
    /// 设置所有 item 的主轴尺寸策略：内容纵向时控制高度，横向时控制宽度；不修改交叉轴轨道。
    public func itemMainAxisSize(_ value: ListGridItemMainAxisSize) -> Self {
        var copy = self
        copy.itemMainAxisSize = value
        return copy
    }
}

extension ListUIKitListLayout {
    /// 设置当前 Section 的方向性内边距（UIKit Section.contentInsets），重复调用覆盖，不累加。
    /// 不改变 collection view 的 contentInset、cell padding 或 decoration inset。
    /// 省略此修饰方法时保留 UIKit List 自身的 inset。
    public func sectionInsets(_ value: ListLayoutInsets) -> Self {
        var copy = self
        copy.options.sectionInsets = value
        return copy
    }
    /// 完整替换框架声明的 boundary 集合，不追加；空集合移除这些声明，内容注册不受影响。
    public func boundarySupplementaries(
        @ListLayoutArrayBuilder<BoundarySupplementaryLayout> _ content: () ->
        [BoundarySupplementaryLayout]
    ) -> Self {
        var copy = self
        copy.options.boundaries = content().map(ListBoundaryLayout.generated)
        return copy
    }
    /// 显式选择注册背景默认策略，替换此前的几何集合或策略。
    public func decorationItems(_ policy: ListDecorationLayoutPolicy) -> Self {
        var copy = self
        copy.options.decorations = policy == .registeredBackgrounds ? nil : []
        return copy
    }
    /// 完整替换框架生成的 decoration 几何；空集合等价于 .none。
    public func decorationItems(
        @ListLayoutArrayBuilder<DecorationItemLayout> _ content: () -> [DecorationItemLayout]
    ) -> Self {
        var copy = self
        copy.options.decorations = content()
        return copy
    }
}

extension ListCustomLayout {
    /// 完整替换框架声明的 boundary 集合，不追加；空集合移除这些声明，内容注册不受影响。
    /// 此集合中关联 provider 已创建的边界时，使用 CustomLayoutBoundary；框架不删除 provider 自有边界。
    public func boundarySupplementaries(
        @ListLayoutArrayBuilder<ListBoundaryLayout> _ content: () ->
        [ListBoundaryLayout]
    ) -> Self {
        var copy = self
        copy.options.boundaries = content()
        return copy
    }
    /// 完整替换 item supplementary 几何集合，不追加；空集合清除声明，内容注册不受影响。
    /// provider 必须将 context.itemSupplementaries 挂到自定义 item 上，框架不会自动改写 group 树。
    public func itemSupplementaries(
        @ListLayoutArrayBuilder<ItemSupplementaryLayout> _ content: () -> [ItemSupplementaryLayout]
    ) -> Self {
        var copy = self
        copy.options.items = content()
        return copy
    }
    /// 显式选择注册背景默认策略，替换此前的几何集合或策略。
    public func decorationItems(_ policy: ListDecorationLayoutPolicy) -> Self {
        var copy = self
        copy.options.decorations = policy == .registeredBackgrounds ? nil : []
        return copy
    }
    /// 完整替换框架生成的 decoration 几何；空集合等价于 .none。
    /// 自定义提供者已有的背景不受此集合控制，实际元素种类不得与框架生成的背景重复。
    public func decorationItems(
        @ListLayoutArrayBuilder<DecorationItemLayout> _ content: () -> [DecorationItemLayout]
    ) -> Self {
        var copy = self
        copy.options.decorations = content()
        return copy
    }
}
