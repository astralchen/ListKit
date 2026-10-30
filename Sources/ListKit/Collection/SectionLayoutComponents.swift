// Boundary cross-axis sizing adapted from UIKitGridLayouts 0.5.0 (5a5bd744).
// Copyright (c) 2026 Sondra. MIT: ThirdPartyNotices/UIKitGridLayouts-LICENSE.txt.
import UIKit

/// 显式二维尺寸；宽高分别转换为 UIKit dimension，不随布局滚动轴自动互换。
public struct ListLayoutSize: Hashable, Sendable {
    /// 布局对象的宽度尺寸规则，不随滚动方向交换。
    public var width: ListLayoutDimension
    /// 布局对象的高度尺寸规则，不随滚动方向交换。
    public var height: ListLayoutDimension
    /// 使用独立的宽度和高度规则创建布局尺寸。
    ///
    /// - Parameters:
    ///   - width: 宽度尺寸规则。
    ///   - height: 高度尺寸规则。
    public init(width: ListLayoutDimension, height: ListLayoutDimension) {
        self.width = width
        self.height = height
    }
    @MainActor var uiKitSize: NSCollectionLayoutSize {
        .init(widthDimension: width.makeDimension(), heightDimension: height.makeDimension())
    }
}

/// 边界视图指定轴上的尺寸，不支持 Grid 的 uniform、fillGroup 或分页比例。
public struct ListBoundaryMainAxisSize: Hashable, Sendable {
    let measurement: ListGridMeasurement
    private init(_ measurement: ListGridMeasurement) { self.measurement = measurement }
    /// 返回使用固定边界尺寸的规则。
    ///
    /// - Parameter value: 指定尺寸轴上的长度，单位为点，必须为有限正数。
    /// - Returns: 固定尺寸规则。
    public static func fixed(_ value: CGFloat) -> Self { .init(.fixed(value)) }
    /// 返回由边界视图内容测量最终尺寸的规则。
    ///
    /// - Parameter value: 指定尺寸轴上的初始估算长度，单位为点，必须为有限正数。
    /// - Returns: 需要视图提供自适应尺寸的估算规则。
    public static func estimated(_ value: CGFloat) -> Self { .init(.estimated(value)) }
    /// 始终为宽 ÷ 高，方向不改变比例含义。
    public static func aspectRatio(_ value: CGFloat) -> Self { .init(.aspectRatio(value)) }
    var isValid: Bool { measurement.isValid }
}

/// 关联 CustomLayout provider 已创建的边界，不提供框架几何修饰方法。
/// 有对应内容时 provider 须返回恰好一个相同 kind 的边界；位置、尺寸、吸顶由 provider 配置。
public struct CustomLayoutBoundary: Hashable, Sendable {
    /// 与附属视图内容及自定义布局边界对应的元素种类。
    public let kind: String
    fileprivate var optional = false
    /// 声明由自定义布局提供者负责创建的边界。
    ///
    /// - Parameter kind: 提供者返回的边界元素种类，须与内容声明一致。
    public init(kind: String) { self.kind = kind }
    /// 缺少对应 supplementary 内容声明时不要求 provider 提供此边界。
    public func whenContentExists() -> Self {
        var copy = self
        copy.optional = true
        return copy
    }

}

/// Section 边界补充视图的几何声明；需以相同 kind 关联 supplementary 内容。
///
/// 位置由 alignment 决定，kind 不推断 header/footer 角色，也不随滚动轴改变位置。
/// 默认 extendsBoundary 为 true、pinToVisibleBounds 为 false、absoluteOffset 为零、zIndex 为 0。
/// 同侧的多个边界遵循 UIKit 布局规则，不会由 ListKit 自动堆叠或追加 Section inset。
public struct BoundarySupplementaryLayout: Hashable, Sendable {
    enum Sizing: Hashable, Sendable {
        case dimensions(ListLayoutSize)
        case crossAxis(ListBoundaryMainAxisSize, ListLayoutScrollDirection)
    }
    struct Geometry: Hashable, Sendable {
        var sizing: Sizing
        var alignment: ListBoundaryAlignment
        var extendsBoundary = true
        var pinned = false
        var offset = ListLayoutPoint.zero
        var zIndex = 0
    }
    /// 业务 kind；须与 SectionSupplementary 一致，实际 UIKit 地址由 adapter 解析。
    public let kind: String
    var geometry: Geometry
    var optional = false
    /// 使用显式宽高和边界位置；宽高的 fractional dimension 由 UIKit 按所在容器解析。
    ///
    /// - Parameters:
    ///   - kind: 与分区附属视图内容对应的业务元素种类。
    ///   - size: 边界视图的宽度和高度规则。
    ///   - alignment: 边界相对于分区的位置，不随滚动方向自动交换。
    public init(kind: String, size: ListLayoutSize, alignment: ListBoundaryAlignment)
    {
        self.kind = kind
        geometry = .init(sizing: .dimensions(size), alignment: alignment)
    }
    /// 使用指定 sizingAxis 上的尺寸规则；sizingAxis 只决定尺寸计算，不改变 alignment 或滚动方向。
    /// vertical 控制高度、交叉轴使用 `.fractionalWidth(1)`；horizontal 控制宽度、交叉轴使用 `.fractionalHeight(1)`。
    /// 比例计算以 effectiveContentSize 扣除 Section 交叉轴 inset 后的尺寸为基准，至少取 1 点。
    ///
    /// - Parameters:
    ///   - kind: 与分区附属视图内容对应的业务元素种类。
    ///   - mainAxisSize: 指定尺寸轴上的固定、估算或宽高比规则。
    ///   - sizingAxis: 尺寸规则控制的轴，垂直轴控制高度，水平轴控制宽度。
    ///   - alignment: 边界相对于分区的位置，与尺寸轴独立。
    public init(
        kind: String, mainAxisSize: ListBoundaryMainAxisSize, sizingAxis: ListLayoutScrollDirection,
        alignment: ListBoundaryAlignment
    ) {
        self.kind = kind
        geometry = .init(sizing: .crossAxis(mainAxisSize, sizingAxis), alignment: alignment)
    }
    /// 允许当前 Section 缺少相同 kind 的内容声明；缺少时跳过此边界，不代表按屏幕可见性启用。
    /// 其他尺寸、kind 唯一性及 CustomLayout 所有权规则仍需满足。
    public func whenContentExists() -> Self {
        var copy = self
        copy.optional = true
        return copy
    }
    /// 设置 UIKit pinToVisibleBounds；默认不吸顶/吸边，调用时默认开启。
    public func pinToVisibleBounds(_ value: Bool = true) -> Self { changing { $0.pinned = value } }
    /// 设置 UIKit extendsBoundary；默认 true，不会由 ListKit 额外修改 Section inset 来补偿。
    public func extendsBoundary(_ value: Bool) -> Self { changing { $0.extendsBoundary = value } }
    /// 相对 alignment 的绝对偏移，单位为点；不改变 Section inset。
    public func absoluteOffset(_ value: CGPoint) -> Self { changing { $0.offset = ListLayoutPoint(value) } }
    /// 设置边界的 UIKit zIndex，默认 0。
    public func zIndex(_ value: Int) -> Self { changing { $0.zIndex = value } }
    private func changing(_ update: (inout Geometry) -> Void) -> Self {
        var copy = self
        update(&copy.geometry)
        return copy
    }
    @MainActor func resolutionError(
        environment: any NSCollectionLayoutEnvironment, insets: NSDirectionalEdgeInsets
    ) -> String? {
        guard case .crossAxis(let rule, let axis) = geometry.sizing else { return nil }
        let vertical = axis == .vertical
        let container = environment.container.effectiveContentSize
        let inset = vertical ? insets.leading + insets.trailing : insets.top + insets.bottom
        let extent = max(1, (vertical ? container.width : container.height) - inset)
        guard inset.isFinite, rule.measurement.checkedExtent(crossExtent: extent, isVertical: vertical) != nil
                else {
            return "resolved main-axis size must be finite and positive"
        }
        return nil
    }

    @MainActor func makeItem(
        environment: any NSCollectionLayoutEnvironment, insets: NSDirectionalEdgeInsets
    ) -> NSCollectionLayoutBoundarySupplementaryItem {
        let size: NSCollectionLayoutSize
        switch geometry.sizing {
        case .dimensions(let value): size = value.uiKitSize
        case .crossAxis(let rule, let axis):
            let vertical = axis == .vertical
            let container = environment.container.effectiveContentSize
            let extent = max(
                1,
                vertical
                ? container.width - insets.leading - insets.trailing
                : container.height - insets.top - insets.bottom)
            let main = rule.measurement.dimension(crossExtent: extent, isVertical: vertical)
            size = .init(
                widthDimension: vertical ? .fractionalWidth(1) : main,
                heightDimension: vertical ? main : .fractionalHeight(1))
        }
        let item = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: size, elementKind: kind,
            alignment: geometry.alignment.boundaryAlignment, absoluteOffset: geometry.offset.cgPoint)
        item.extendsBoundary = geometry.extendsBoundary
        item.pinToVisibleBounds = geometry.pinned
        item.zIndex = geometry.zIndex
        return item
    }
}

/// 附着于 item 的补充视图几何；需以相同 kind 关联 Section supplementary 内容。
/// Grid 仅在解析出的轨道等尺寸且轨道间距一致时支持；UIKitListLayout 不支持此类视图。
/// CustomLayout 必须将 context.itemSupplementaries 显式安装到自定义 item 上。
public struct ItemSupplementaryLayout: Hashable, Sendable {
    /// 业务 kind；须与 SectionSupplementary 一致，实际 UIKit 地址由 adapter 解析。
    public let kind: String
    /// 附属视图的二维尺寸规则。
    public var size: ListLayoutSize
    /// 相对于所属 item 的 containerAnchor；不是 Section 边界位置。
    public var itemAnchor: ListItemSupplementaryAnchor
    var anchorFractionalOffset = ListLayoutPoint.zero
    var layer = 0
    var optional = false
    /// 创建附着于条目的附属视图布局声明。
    ///
    /// - Parameters:
    ///   - kind: 与分区附属视图内容对应的业务种类。
    ///   - size: 附属视图的宽度和高度。
    ///   - itemAnchor: 相对于所属条目的锚点。
    public init(kind: String, size: ListLayoutSize, itemAnchor: ListItemSupplementaryAnchor) {
        self.kind = kind
        self.size = size
        self.itemAnchor = itemAnchor
    }
    /// 允许当前 Section 缺少相同 kind 的内容声明；缺少时不创建此 item supplementary。
    /// 不按 item 的可见性筛选，也不跳过尺寸与 kind 唯一性校验。
    public func whenContentExists() -> Self {
        var copy = self
        copy.optional = true
        return copy
    }
    /// 传给 UIKit containerAnchor 的比例偏移，默认零；不是以点为单位的绝对偏移。
    public func anchorFractionalOffset(_ value: CGPoint) -> Self {
        var copy = self
        copy.anchorFractionalOffset = .init(value)
        return copy
    }
    /// 设置 item supplementary 的 UIKit zIndex，默认 0。
    public func zIndex(_ value: Int) -> Self {
        var copy = self
        copy.layer = value
        return copy
    }
    @MainActor func makeItem(elementKind: String? = nil) -> NSCollectionLayoutSupplementaryItem {
        let item = NSCollectionLayoutSupplementaryItem(
            layoutSize: size.uiKitSize, elementKind: elementKind ?? kind,
            containerAnchor: .init(
                edges: itemAnchor.directionalEdges, fractionalOffset: anchorFractionalOffset.cgPoint))
        item.zIndex = layer
        return item
    }
}

/// Section 背景 decoration 的几何声明；需关联相同逻辑 kind 的 SectionDecoration 注册。
/// 通过 UIKit background decoration 创建，默认 inset 为零、zIndex 为 -1。
public struct DecorationItemLayout: Hashable, Sendable {
    /// 与 SectionDecoration 共享的逻辑 kind；实际 UIKit elementKind 在解析时从注册声明取得。
    public let kind: String
    /// 背景 decoration 自身的 inset，须为有限非负数；不改变 Section 或 cell 的布局 inset。
    public var backgroundInsets: ListLayoutInsets
    var layer: Int
    var optional = false
    /// 创建分区背景装饰视图的布局声明。
    ///
    /// - Parameters:
    ///   - kind: 与装饰视图注册对应的逻辑种类。
    ///   - backgroundInsets: 背景内边距，默认全部为零；各值须为有限非负数。
    ///   - zIndex: 背景的层叠顺序，默认为 -1。
    public init(kind: String, backgroundInsets: ListLayoutInsets = .zero, zIndex: Int = -1) {
        self.kind = kind
        self.backgroundInsets = backgroundInsets
        layer = zIndex
    }
    /// 允许当前 Section 缺少相同逻辑 kind 的 decoration 注册；缺少时跳过此背景几何。
    /// 不代表按屏幕可见性启用，也不会代替注册视图。
    public func whenContentExists() -> Self {
        var copy = self
        copy.optional = true
        return copy
    }
    /// 设置背景 decoration 的 UIKit zIndex，默认 -1。
    public func zIndex(_ value: Int) -> Self {
        var copy = self
        copy.layer = value
        return copy
    }
    @MainActor func makeItem(kind: String) -> NSCollectionLayoutDecorationItem {
        let item = NSCollectionLayoutDecorationItem.background(elementKind: kind)
        item.contentInsets = backgroundInsets.directionalEdgeInsets
        item.zIndex = layer
        return item
    }
}

/// Section decoration 的注册声明，几何由布局的 decorationItems 管理。
///
/// 未调用 decorationItems 时，每个注册声明自动获得默认背景几何（零 inset、zIndex -1）。
/// 显式 `.decorationItems { }` 关闭框架生成的背景几何，仍保留注册声明。
public struct SectionDecoration: Hashable {
    /// Section 内的逻辑 kind；不代表 UIKit 注册标识。
    public let kind: String
    /// 实际 UIKit element kind。typed 注册包含视图类型身份，防止替换类型时复用旧实例。
    /// 手动注册入口原样使用传入的 elementKind，由调用方负责注册。
    public let elementKind: String
    let registrationKey: ObjectIdentifier?
    private let registerProvider: (@MainActor (UICollectionViewLayout) -> Void)?
    /// 声明由 adapter 自动注册的视图类型；kind 为 Section 内的逻辑名称，不是最终 elementKind。
    public init<View>(_ view: View.Type, kind: String)
    where View: UICollectionReusableView {
        self.kind = kind
        registrationKey = ObjectIdentifier(view)
        elementKind =
        "ListKit.TypedDecoration.\(self.kind.utf8.count):\(self.kind):\(NSStringFromClass(view))"
        let resolvedKind = elementKind
        registerProvider = { $0.registerDecorationView(view, forKind: resolvedKind) }
    }
    /// 调用方负责注册实际 elementKind；kind 是稳定的逻辑名称。
    public init(kind: String, elementKind: String) {
        self.kind = kind
        self.elementKind = elementKind
        registrationKey = nil
        registerProvider = nil
    }
    /// 在布局上注册声明的视图类型；手动注册声明不执行额外操作。
    @MainActor func register(on layout: UICollectionViewLayout) { registerProvider?(layout) }
    /// 返回两个声明的逻辑种类、实际元素种类和注册类型是否相同。
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.kind == rhs.kind && lhs.elementKind == rhs.elementKind
        && lhs.registrationKey == rhs.registrationKey
    }
    /// 将逻辑种类、实际元素种类和注册类型写入哈希器。
    public func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(elementKind)
        hasher.combine(registrationKey)
    }
}

/// 各类分区布局共享的内边距、附属视图和装饰视图几何选项。
struct ListSectionLayoutOptions: Hashable, Sendable {
    var sectionInsets: ListLayoutInsets?
    var boundaries: [ListBoundaryLayout] = []
    var items: [ItemSupplementaryLayout] = []
    // 未指定时为已注册装饰视图生成默认背景；空数组显式关闭框架生成的背景。
    var decorations: [DecorationItemLayout]?
}

/// 按声明顺序合并元素、数组、可选值和条件/循环分支；不去重。
/// 同一次 builder 内合并元素；多次调用布局的集合修饰方法则由后一次完整替换前一次。
@resultBuilder public enum ListLayoutArrayBuilder<Element> {
    /// 将表达式转换为构建器的元素集合。
    public static func buildExpression(_ value: Element) -> [Element] { [value] }
    /// 将表达式转换为构建器的元素集合。可选值为 `nil` 时返回空集合。
    public static func buildExpression(_ value: Element?) -> [Element] { value.map { [$0] } ?? [] }
    /// 按原顺序接收表达式数组。
    public static func buildExpression(_ values: [Element]) -> [Element] { values }
    /// 按声明顺序合并构建块中的元素集合。
    public static func buildBlock(_ values: [Element]...) -> [Element] { values.flatMap { $0 } }
    /// 返回可选分支的元素；分支不存在时返回空集合。
    public static func buildOptional(_ values: [Element]?) -> [Element] { values ?? [] }
    /// 返回条件表达式第一个分支的构建结果。
    public static func buildEither(first values: [Element]) -> [Element] { values }
    /// 返回条件表达式第二个分支的构建结果。
    public static func buildEither(second values: [Element]) -> [Element] { values }
    /// 按迭代顺序合并循环各次生成的元素集合。
    public static func buildArray(_ values: [[Element]]) -> [Element] { values.flatMap { $0 } }
    /// 传递通过系统可用性检查的分支结果。
    public static func buildLimitedAvailability(_ values: [Element]) -> [Element] { values }
}

extension ListSectionLayoutOptions {
    /// 返回显式装饰几何，或为每个注册声明生成默认背景规则。
    func decorationRules(_ content: [SectionDecoration]) -> [DecorationItemLayout] {
        decorations ?? content.map { .init(kind: $0.kind) }
    }
    /// 验证元素种类唯一性、尺寸合法性，以及几何声明与内容注册之间的对应关系。
    func issues<SectionID>(in section: ListSection<SectionID>, custom: Bool) -> [ListDiagnosticsIssue]
    {
        var messages: [String] = []
        func unique<T: Hashable>(_ values: [T], _ label: String) {
            if Set(values).count != values.count { messages.append("duplicate \(label)") }
        }
        func finite(_ values: [CGFloat], _ label: String, nonnegative: Bool = false) {
            if values.contains(where: { !$0.isFinite || (nonnegative && $0 < 0) }) {
                messages.append("invalid \(label)")
            }
        }
        func dimensions(_ value: ListLayoutSize, _ label: String) {
            for dimension in [value.width, value.height] {
                let value: CGFloat
                switch dimension {
                case .absolute(let x), .estimated(let x), .fractionalWidth(let x), .fractionalHeight(let x):
                    value = x
                }
                if !value.isFinite || value <= 0 { messages.append("invalid dimensions for \(label)") }
            }
        }
        func insets(_ value: ListLayoutInsets, _ label: String) {
            finite([value.top, value.leading, value.bottom, value.trailing], label, nonnegative: true)
        }
        let kinds = Set(section.supplementaries.map(\.kind))
        unique(boundaries.map(\.kind) + items.map(\.kind), "supplementary layout kind")
        unique(section.decorations.map(\.kind), "decoration logical kind")
        let rules = decorationRules(section.decorations)
        unique(rules.map(\.kind), "decoration layout kind")
        // 仅对有匹配注册声明的装饰几何检查实际元素种类冲突。
        var kindsByElementKind: [String: String] = [:]
        for rule in rules {
            guard let content = section.decorations.first(where: { $0.kind == rule.kind }) else {
                continue
            }
            if let previous = kindsByElementKind[content.elementKind], previous != rule.kind {
                messages.append(
                    "duplicate decoration elementKind \(content.elementKind) for logical kinds \(previous), \(rule.kind)"
                )
            }
            kindsByElementKind[content.elementKind] = rule.kind
        }
        for value in section.supplementaries {
            if value.kind.isEmpty {
                messages.append("empty supplementary kind")
            }
        }
        for value in section.decorations {
            if value.kind.isEmpty || value.elementKind.isEmpty {
                messages.append("empty decoration logical kind or elementKind")
            }
        }
        if let sectionInsets { insets(sectionInsets, "section insets") }
        for rule in boundaries {
            if rule.kind.isEmpty { messages.append("empty boundary kind") }
            if !kinds.contains(rule.kind) && !rule.optional {
                messages.append("missing content for kind \(rule.kind)")
            }
            guard let geometry = rule.geometry else {
                if !custom {
                    messages.append("provider-owned boundary \(rule.kind) requires CustomLayout")
                }
                continue
            }
            finite(
                [geometry.offset.cgPoint.x, geometry.offset.cgPoint.y], "boundary offset \(rule.kind)")
            switch geometry.sizing {
            case .dimensions(let size): dimensions(size, rule.kind)
            case .crossAxis(let size, _):
                if !size.isValid { messages.append("invalid boundary size for \(rule.kind)") }
            }
        }
        for rule in items {
            if rule.kind.isEmpty { messages.append("empty item supplementary kind") }
            if !kinds.contains(rule.kind) && !rule.optional {
                messages.append("missing content for kind \(rule.kind)")
            }
            dimensions(rule.size, rule.kind)
            finite(
                [rule.anchorFractionalOffset.cgPoint.x, rule.anchorFractionalOffset.cgPoint.y],
                "item supplementary offset")
        }
        for rule in rules {
            if rule.kind.isEmpty { messages.append("empty decoration kind") }
            if !section.decorations.contains(where: { $0.kind == rule.kind }) && !rule.optional {
                messages.append("missing decoration content for kind \(rule.kind)")
            }
            insets(rule.backgroundInsets, "decoration insets \(rule.kind)")
        }
        return messages.map {
            .init(kind: .invalidLayout, message: "ListKit: section \(section.id): \($0)")
        }
    }
}

/// CustomLayout 中的边界声明，保留几何生成方。包装后不提供几何修饰方法。
/// 在包装前配置 BoundarySupplementaryLayout；provider 自有边界在 provider 内配置。
public enum ListBoundaryLayout: Hashable, Sendable {
    /// 由 ListKit 根据几何声明创建边界视图布局。
    case generated(BoundarySupplementaryLayout)
    /// 关联自定义布局提供者已经创建的边界视图布局。
    case provided(CustomLayoutBoundary)

    var kind: String {
        switch self { case .generated(let value): value.kind; case .provided(let value): value.kind }
    }
    var optional: Bool {
        switch self { case .generated(let value): value.optional; case .provided(let value): value.optional }
    }
    var geometry: BoundarySupplementaryLayout.Geometry? {
        if case .generated(let value) = self { return value.geometry }
        return nil
    }
    @MainActor func resolutionError(
        environment: any NSCollectionLayoutEnvironment, insets: NSDirectionalEdgeInsets
    ) -> String? {
        guard case .generated(let value) = self else { return nil }
        return value.resolutionError(environment: environment, insets: insets)
    }
    @MainActor func makeItem(
        environment: any NSCollectionLayoutEnvironment, insets: NSDirectionalEdgeInsets
    ) -> NSCollectionLayoutBoundarySupplementaryItem? {
        guard case .generated(let value) = self else { return nil }
        return value.makeItem(environment: environment, insets: insets)
    }
}

extension ListLayoutArrayBuilder where Element == ListBoundaryLayout {
    /// 将框架生成的边界声明转换为构建器的元素集合。
    public static func buildExpression(_ value: BoundarySupplementaryLayout) -> [Element] { [.generated(value)] }
    /// 将框架生成的边界声明转换为构建器的元素集合。可选值为 `nil` 时返回空集合。
    public static func buildExpression(_ value: BoundarySupplementaryLayout?) -> [Element] { value.map { [.generated($0)] } ?? [] }
    /// 按原顺序接收框架生成的边界声明数组。
    public static func buildExpression(_ values: [BoundarySupplementaryLayout]) -> [Element] { values.map(Element.generated) }
    /// 将提供者自有的边界声明转换为构建器的元素集合。
    public static func buildExpression(_ value: CustomLayoutBoundary) -> [Element] { [.provided(value)] }
    /// 将提供者自有的边界声明转换为构建器的元素集合。可选值为 `nil` 时返回空集合。
    public static func buildExpression(_ value: CustomLayoutBoundary?) -> [Element] { value.map { [.provided($0)] } ?? [] }
    /// 按原顺序接收提供者自有的边界声明数组。
    public static func buildExpression(_ values: [CustomLayoutBoundary]) -> [Element] { values.map(Element.provided) }
}

/// 布局未提供显式 decoration 几何集合时的背景策略。
public enum ListDecorationLayoutPolicy: Hashable, Sendable {
    /// 每个 SectionDecoration 注册生成一个默认背景（零 inset、zIndex -1）。
    case registeredBackgrounds
    /// 关闭框架生成的背景；CustomLayout provider 自有的背景不受影响。
    case none
}
