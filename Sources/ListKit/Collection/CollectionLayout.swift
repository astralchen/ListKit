import UIKit

// MARK: - Layout Model

/// Compositional layout 的主滚动方向。
public enum ListLayoutScrollDirection: Hashable, Sendable {
    case vertical
    case horizontal

    var uiKitValue: UICollectionView.ScrollDirection {
        switch self {
        case .vertical: return .vertical
        case .horizontal: return .horizontal
        }
    }
}

/// Compositional layout 计算全局内容区域时采用的系统 inset 来源。
public enum ListContentInsetsReference: Hashable, Sendable {
    case automatic
    case none
    case safeArea
    case layoutMargins
    case readableContent

    var uiKitValue: UIContentInsetsReference {
        switch self {
        case .automatic: return .automatic
        case .none: return .none
        case .safeArea: return .safeArea
        case .layoutMargins: return .layoutMargins
        case .readableContent: return .readableContent
        }
    }
}

/// Compositional layout 全局配置。
public struct ListCompositionalLayoutConfiguration: Hashable, Sendable {
    public var scrollDirection: ListLayoutScrollDirection
    public var interSectionSpacing: CGFloat
    public var contentInsetsReference: ListContentInsetsReference

    public init(
        scrollDirection: ListLayoutScrollDirection = .vertical,
        interSectionSpacing: CGFloat = 0,
        contentInsetsReference: ListContentInsetsReference = .safeArea
    ) {
        self.scrollDirection = scrollDirection
        self.interSectionSpacing = interSectionSpacing
        self.contentInsetsReference = contentInsetsReference
    }

    @MainActor func makeConfiguration() -> UICollectionViewCompositionalLayoutConfiguration {
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.scrollDirection = scrollDirection.uiKitValue
        configuration.interSectionSpacing = interSectionSpacing
        configuration.contentInsetsReference = contentInsetsReference.uiKitValue
        return configuration
    }
}

/// Compositional layout 的尺寸描述。
///
/// - Note: 这里不用直接保存 `NSCollectionLayoutDimension`，因为 UIKit 类型不是 DSL
/// `Hashable & Sendable` 模型。真正生成 layout 时再转换成 UIKit 类型。
public enum ListLayoutDimension: Hashable, Sendable {
    /// 固定点数尺寸。
    case absolute(CGFloat)
    /// 自适应估算尺寸。
    case estimated(CGFloat)
    /// 相对容器宽度的比例尺寸。
    case fractionalWidth(CGFloat)
    /// 相对容器高度的比例尺寸。
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

    /// 用于在 boundary supplementary 前后预留空间。
    ///
    /// - Important: `NSCollectionLayoutBoundarySupplementaryItem` 是贴在 section 边界上的视图，
    /// 需要由 ListKit 为全宽 `.top` / `.bottom` 的 header/footer
    /// 使用 absolute 或 estimated 值补齐 content inset，让 DSL 写法符合“header 在 rows 上方”的直觉。
    var estimatedContentInsetValue: CGFloat? {
        switch self {
        case .absolute(let value), .estimated(let value):
            return value
        case .fractionalWidth, .fractionalHeight:
            return nil
        }
    }

    var isFullWidth: Bool {
        if case .fractionalWidth(let value) = self {
            return value == 1
        }
        return false
    }
}

/// Layout DSL 使用的方向性 inset。
public struct ListLayoutInsets: Hashable, Sendable {
    public var top: CGFloat
    public var leading: CGFloat
    public var bottom: CGFloat
    public var trailing: CGFloat

    /// 创建方向性 inset。
    ///
    /// - Parameters:
    ///   - top: 顶部 inset。
    ///   - leading: leading inset。
    ///   - bottom: 底部 inset。
    ///   - trailing: trailing inset。
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

    var directionalEdgeInsets: NSDirectionalEdgeInsets {
        NSDirectionalEdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing)
    }
}

/// Layout DSL 使用的二维偏移。
public struct ListLayoutPoint: Hashable, Sendable {
    public var x: CGFloat
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

/// Section 背景装饰描述。
///
/// - Important: raw kind 入口不会注册 view；typed view 入口会由 adapter 注册到当前 layout。
public struct ListBackgroundDecoration: Hashable, @unchecked Sendable {
    /// 默认 section 背景 decoration kind。
    public static let defaultKind = "UICollectionView.ElementKindSectionBackgroundDecoration"

    public let kind: String
    public var contentInsets: ListLayoutInsets
    public var zIndex: Int
    let registrationKey: ObjectIdentifier?
    private let registerProvider: (@MainActor (UICollectionViewLayout) -> Void)?

    /// 创建 raw section 背景装饰。
    ///
    /// - Parameters:
    ///   - kind: 已注册的 decoration view kind。
    ///   - contentInsets: 背景相对 section 内容的 inset。
    ///   - zIndex: 背景层级。
    public init(
        kind: String = Self.defaultKind,
        contentInsets: ListLayoutInsets = .zero,
        zIndex: Int = -1
    ) {
        self.kind = kind
        self.contentInsets = contentInsets
        self.zIndex = zIndex
        self.registrationKey = nil
        self.registerProvider = nil
    }

    /// 创建 typed section 背景装饰。
    ///
    /// - Parameters:
    ///   - viewType: 背景 decoration view 类型。
    ///   - kind: decoration view kind。
    ///   - contentInsets: 背景相对 section 内容的 inset。
    ///   - zIndex: 背景层级。
    /// - Note: typed 入口会记录 view 类型，adapter 在 `apply` 或 `makeCompositionalLayout()` 时自动注册。
    public init<View>(
        view viewType: View.Type,
        kind: String = Self.defaultKind,
        contentInsets: ListLayoutInsets = .zero,
        zIndex: Int = -1
    ) where View: UICollectionReusableView {
        self.kind = kind
        self.contentInsets = contentInsets
        self.zIndex = zIndex
        self.registrationKey = ObjectIdentifier(viewType)
        self.registerProvider = { layout in
            layout.registerDecorationView(viewType, forKind: kind)
        }
    }

    @MainActor func register(on layout: UICollectionViewLayout) {
        registerProvider?(layout)
    }

    @MainActor func makeDecorationItem() -> NSCollectionLayoutDecorationItem {
        let item = NSCollectionLayoutDecorationItem.background(elementKind: kind)
        item.contentInsets = contentInsets.directionalEdgeInsets
        item.zIndex = zIndex
        return item
    }

    public static func == (lhs: ListBackgroundDecoration, rhs: ListBackgroundDecoration) -> Bool {
        lhs.kind == rhs.kind
            && lhs.contentInsets == rhs.contentInsets
            && lhs.zIndex == rhs.zIndex
            && lhs.registrationKey == rhs.registrationKey
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(contentInsets)
        hasher.combine(zIndex)
        hasher.combine(registrationKey)
    }
}

public struct ListSectionLayoutConfiguration<SectionID>: Hashable, Sendable where SectionID: Hashable & Sendable {
    var layoutID: AnyListID?
    var sectionLayout: ListSectionLayout?
    var customSectionLayout: ListCustomSectionLayout<SectionID>?

    init(
        layoutID: AnyListID? = nil,
        sectionLayout: ListSectionLayout? = nil,
        customSectionLayout: ListCustomSectionLayout<SectionID>? = nil
    ) {
        self.layoutID = layoutID
        self.sectionLayout = sectionLayout
        self.customSectionLayout = customSectionLayout
    }
}

/// 创建 raw section 背景装饰描述。
///
/// - Parameters:
///   - kind: 已注册的 decoration view kind。
///   - contentInsets: 背景相对 section 内容的 inset。
///   - zIndex: 背景层级。
/// - Returns: 可放入 section background builder 的背景装饰描述。
/// - Important: raw kind 需要调用方提前注册 decoration view。
public func BackgroundDecoration(
    kind: String,
    contentInsets: ListLayoutInsets = .zero,
    zIndex: Int = -1
) -> ListBackgroundDecoration {
    ListBackgroundDecoration(kind: kind, contentInsets: contentInsets, zIndex: zIndex)
}

/// 创建 typed section 背景装饰描述。
///
/// - Parameters:
///   - viewType: 背景 decoration view 类型。
///   - kind: decoration view kind。
///   - contentInsets: 背景相对 section 内容的 inset。
///   - zIndex: 背景层级。
/// - Returns: 可放入 section background builder 的背景装饰描述。
public func BackgroundDecoration<View>(
    _ viewType: View.Type,
    kind: String = ListBackgroundDecoration.defaultKind,
    contentInsets: ListLayoutInsets = .zero,
    zIndex: Int = -1
) -> ListBackgroundDecoration where View: UICollectionReusableView {
    ListBackgroundDecoration(view: viewType, kind: kind, contentInsets: contentInsets, zIndex: zIndex)
}

/// 创建 list section layout。
///
/// - Parameters:
///   - itemHeight: item 高度。
///   - spacing: 行间距。
///   - contentInsets: section 内容 inset。
/// - Returns: list section layout 描述。
public func ListLayout(
    itemHeight: ListLayoutDimension = .estimated(44),
    spacing: CGFloat = 0,
    contentInsets: ListLayoutInsets = .zero
) -> ListSectionLayout {
    .list(itemHeight: itemHeight, spacing: spacing, contentInsets: contentInsets)
}

/// 创建 grid section layout。
///
/// - Parameters:
///   - columns: 列数。
///   - spacing: item 间距和行间距。
///   - itemHeight: item 高度；为 `nil` 时使用与列宽一致的比例高度。
///   - contentInsets: section 内容 inset。
/// - Returns: grid section layout 描述。
public func GridLayout(
    columns: Int,
    spacing: CGFloat = 0,
    itemHeight: ListLayoutDimension? = nil,
    contentInsets: ListLayoutInsets = .zero
) -> ListSectionLayout {
    .grid(columns: columns, spacing: spacing, itemHeight: itemHeight, contentInsets: contentInsets)
}

/// 创建横向 section layout。
///
/// - Parameters:
///   - itemWidth: item 宽度。
///   - itemHeight: 横向 group 高度。
///   - spacing: item 间距。
///   - contentInsets: section 内容 inset。
/// - Returns: 横向 section layout 描述。
public func HorizontalLayout(
    itemWidth: ListLayoutDimension = .estimated(44),
    itemHeight: ListLayoutDimension = .estimated(44),
    spacing: CGFloat = 0,
    contentInsets: ListLayoutInsets = .zero,
    scrollingBehavior: ListOrthogonalScrollingBehavior = .continuous
) -> ListSectionLayout {
    .horizontal(
        itemWidth: itemWidth,
        itemHeight: itemHeight,
        spacing: spacing,
        contentInsets: contentInsets,
        scrollingBehavior: scrollingBehavior
    )
}

/// 横向 section 的滚动行为，避免页面直接依赖 UIKit 枚举。
public enum ListOrthogonalScrollingBehavior: Hashable, Sendable {
    case none
    case continuous
    case continuousGroupLeadingBoundary
    case paging
    case groupPaging
    case groupPagingCentered

    var uiKitValue: UICollectionLayoutSectionOrthogonalScrollingBehavior {
        switch self {
        case .none: return .none
        case .continuous: return .continuous
        case .continuousGroupLeadingBoundary: return .continuousGroupLeadingBoundary
        case .paging: return .paging
        case .groupPaging: return .groupPaging
        case .groupPagingCentered: return .groupPagingCentered
        }
    }
}

/// UIKit 原生 list section 的外观。
public enum ListUIKitListAppearance: Hashable, Sendable {
    case plain
    case grouped
    case insetGrouped
    case sidebar
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

/// UIKit 原生 list section 配置。使用该布局时，Row 的 swipe actions 会真正接入
/// `UICollectionLayoutListConfiguration`，同时保留 ListKit 的 diffable identity。
public struct ListUIKitListLayout: Hashable, Sendable {
    public var appearance: ListUIKitListAppearance
    public var showsSeparators: Bool
    public var headerTopPadding: CGFloat?

    public init(
        appearance: ListUIKitListAppearance = .plain,
        showsSeparators: Bool = true,
        headerTopPadding: CGFloat? = nil
    ) {
        self.appearance = appearance
        self.showsSeparators = showsSeparators
        self.headerTopPadding = headerTopPadding
    }

    @MainActor func makeConfiguration() -> UICollectionLayoutListConfiguration {
        var configuration = UICollectionLayoutListConfiguration(appearance: appearance.uiKitValue)
        configuration.showsSeparators = showsSeparators
        if #available(iOS 15.0, tvOS 15.0, *), let headerTopPadding {
            configuration.headerTopPadding = headerTopPadding
        }
        return configuration
    }
}

/// 创建 UIKit 原生 list section layout。
public func UIKitListLayout(
    appearance: ListUIKitListAppearance = .plain,
    showsSeparators: Bool = true,
    headerTopPadding: CGFloat? = nil
) -> ListSectionLayout {
    .uiKitListConfiguration(
        ListUIKitListLayout(
            appearance: appearance,
            showsSeparators: showsSeparators,
            headerTopPadding: headerTopPadding
        )
    )
}

/// section 的 list 布局配置。
public struct ListSectionListLayout: Hashable, Sendable {
    /// item 高度。
    public var itemHeight: ListLayoutDimension
    /// 行间距。
    public var spacing: CGFloat
    /// section 内容 inset。
    public var contentInsets: ListLayoutInsets

    /// 创建 list 布局配置。
    ///
    /// - Parameters:
    ///   - itemHeight: item 高度。
    ///   - spacing: 行间距。
    ///   - contentInsets: section 内容 inset。
    public init(
        itemHeight: ListLayoutDimension = .estimated(44),
        spacing: CGFloat = 0,
        contentInsets: ListLayoutInsets = .zero
    ) {
        self.itemHeight = itemHeight
        self.spacing = spacing
        self.contentInsets = contentInsets
    }
}

/// section 的 grid 布局配置。
public struct ListSectionGridLayout: Hashable, Sendable {
    /// 列数。
    public var columns: Int
    /// item 间距和行间距。
    public var spacing: CGFloat
    /// item 高度。
    public var itemHeight: ListLayoutDimension
    /// section 内容 inset。
    public var contentInsets: ListLayoutInsets

    /// 创建 grid 布局配置。`columns < 1` 会被 layout 生成兜底为 1，并由 diagnostics 报告。
    ///
    /// - Parameters:
    ///   - columns: 列数。
    ///   - spacing: item 间距和行间距。
    ///   - itemHeight: item 高度；为 `nil` 时使用与列宽一致的比例高度。
    ///   - contentInsets: section 内容 inset。
    public init(
        columns: Int,
        spacing: CGFloat = 0,
        itemHeight: ListLayoutDimension? = nil,
        contentInsets: ListLayoutInsets = .zero
    ) {
        let safeColumns = max(columns, 1)
        self.columns = columns
        self.spacing = spacing
        self.itemHeight = itemHeight ?? .fractionalWidth(1 / CGFloat(safeColumns))
        self.contentInsets = contentInsets
    }
}

/// section 的横向自适应布局配置。
public struct ListSectionHorizontalLayout: Hashable, Sendable {
    /// item 宽度。
    public var itemWidth: ListLayoutDimension
    /// 横向 group 高度。
    public var itemHeight: ListLayoutDimension
    /// item 间距。
    public var spacing: CGFloat
    /// section 内容 inset。
    public var contentInsets: ListLayoutInsets
    /// section 横向滚动行为。
    public var scrollingBehavior: ListOrthogonalScrollingBehavior

    /// 创建横向布局配置。
    ///
    /// - Parameters:
    ///   - itemWidth: item 宽度。
    ///   - itemHeight: 横向 group 高度。
    ///   - spacing: item 间距。
    ///   - contentInsets: section 内容 inset。
    public init(
        itemWidth: ListLayoutDimension = .estimated(44),
        itemHeight: ListLayoutDimension = .estimated(44),
        spacing: CGFloat = 0,
        contentInsets: ListLayoutInsets = .zero,
        scrollingBehavior: ListOrthogonalScrollingBehavior = .continuous
    ) {
        self.itemWidth = itemWidth
        self.itemHeight = itemHeight
        self.spacing = spacing
        self.contentInsets = contentInsets
        self.scrollingBehavior = scrollingBehavior
    }
}

/// 自定义 section layout 的类型安全逃生口。
///
/// - Important: `id` 只描述自定义布局的稳定身份；真正的布局由 `makeSection` 在主线程生成。
public struct ListCustomSectionLayout<SectionID>: @unchecked Sendable where SectionID: Hashable & Sendable {
    /// 自定义布局的稳定身份，用于 layout metadata diff 和诊断。
    public let id: AnyListID
    let makeSection: @MainActor (
        ListSection<SectionID>,
        Int,
        any NSCollectionLayoutEnvironment
    ) -> NSCollectionLayoutSection

    /// 创建自定义 compositional layout。
    ///
    /// - Parameters:
    ///   - id: 自定义布局的稳定身份。
    ///   - makeSection: 根据当前 section、index 和 layout environment 创建 layout section 的闭包。
    public init<ID>(
        id: ID,
        makeSection: @escaping @MainActor (
            ListSection<SectionID>,
            Int,
            any NSCollectionLayoutEnvironment
        ) -> NSCollectionLayoutSection
    ) where ID: Hashable & Sendable {
        self.id = AnyListID(id)
        self.makeSection = makeSection
    }

    /// 创建自定义 compositional layout。
    ///
    /// - Parameters:
    ///   - id: 自定义布局的稳定身份。
    ///   - makeSection: 根据当前 section、index 和 layout environment 创建 layout section 的闭包。
    /// - Returns: 自定义 layout 描述。
    public static func custom<ID>(
        id: ID,
        makeSection: @escaping @MainActor (
            ListSection<SectionID>,
            Int,
            any NSCollectionLayoutEnvironment
        ) -> NSCollectionLayoutSection
    ) -> ListCustomSectionLayout<SectionID> where ID: Hashable & Sendable {
        ListCustomSectionLayout(id: id, makeSection: makeSection)
    }
}

extension ListCustomSectionLayout: Hashable {
    public static func == (lhs: ListCustomSectionLayout<SectionID>, rhs: ListCustomSectionLayout<SectionID>) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Section 主布局描述。
///
/// - Usage:
/// ```swift
/// ListSection(.users) { ... }
///     .layout(.grid(columns: 2, spacing: 12))
/// ```
public enum ListSectionLayout: Hashable, Sendable {
    /// list 布局配置。
    case listConfiguration(ListSectionListLayout)
    /// grid 布局配置。
    case gridConfiguration(ListSectionGridLayout)
    /// 横向布局配置。
    case horizontalConfiguration(ListSectionHorizontalLayout)
    /// UIKit 原生 list 配置。
    case uiKitListConfiguration(ListUIKitListLayout)

    /// 创建 list 布局枚举值。
    ///
    /// - Parameters:
    ///   - itemHeight: item 高度。
    ///   - spacing: 行间距。
    ///   - contentInsets: section 内容 inset。
    /// - Returns: list layout 描述。
    public static func list(
        itemHeight: ListLayoutDimension = .estimated(44),
        spacing: CGFloat = 0,
        contentInsets: ListLayoutInsets = .zero
    ) -> ListSectionLayout {
        .listConfiguration(
            ListSectionListLayout(
                itemHeight: itemHeight,
                spacing: spacing,
                contentInsets: contentInsets
            )
        )
    }

    /// 创建 grid 布局枚举值。
    ///
    /// - Parameters:
    ///   - columns: 列数。
    ///   - spacing: item 间距和行间距。
    ///   - itemHeight: item 高度；为 `nil` 时使用与列宽一致的比例高度。
    ///   - contentInsets: section 内容 inset。
    /// - Returns: grid layout 描述。
    public static func grid(
        columns: Int,
        spacing: CGFloat = 0,
        itemHeight: ListLayoutDimension? = nil,
        contentInsets: ListLayoutInsets = .zero
    ) -> ListSectionLayout {
        .gridConfiguration(
            ListSectionGridLayout(
                columns: columns,
                spacing: spacing,
                itemHeight: itemHeight,
                contentInsets: contentInsets
            )
        )
    }

    /// 创建 horizontal 布局枚举值。
    ///
    /// - Parameters:
    ///   - itemWidth: item 宽度。
    ///   - itemHeight: 横向 group 高度。
    ///   - spacing: item 间距。
    ///   - contentInsets: section 内容 inset。
    /// - Returns: 横向 layout 描述。
    public static func horizontal(
        itemWidth: ListLayoutDimension = .estimated(44),
        itemHeight: ListLayoutDimension = .estimated(44),
        spacing: CGFloat = 0,
        contentInsets: ListLayoutInsets = .zero,
        scrollingBehavior: ListOrthogonalScrollingBehavior = .continuous
    ) -> ListSectionLayout {
        .horizontalConfiguration(
            ListSectionHorizontalLayout(
                itemWidth: itemWidth,
                itemHeight: itemHeight,
                spacing: spacing,
                contentInsets: contentInsets,
                scrollingBehavior: scrollingBehavior
            )
        )
    }

    @MainActor func makeCompositionalSection(
        itemSupplementaries: [NSCollectionLayoutSupplementaryItem]
    ) -> NSCollectionLayoutSection {
        switch self {
        case .listConfiguration(let configuration):
            return configuration.makeCompositionalSection(itemSupplementaries: itemSupplementaries)
        case .gridConfiguration(let configuration):
            return configuration.makeCompositionalSection(itemSupplementaries: itemSupplementaries)
        case .horizontalConfiguration(let configuration):
            return configuration.makeCompositionalSection(itemSupplementaries: itemSupplementaries)
        case .uiKitListConfiguration:
            preconditionFailure("ListKit: UIKitListLayout requires a compositional layout environment; use CollectionListAdapter.makeCompositionalLayout().")
        }
    }

    var uiKitListLayout: ListUIKitListLayout? {
        guard case .uiKitListConfiguration(let configuration) = self else { return nil }
        return configuration
    }
}

private extension ListSectionListLayout {
    @MainActor func makeCompositionalSection(
        itemSupplementaries: [NSCollectionLayoutSupplementaryItem]
    ) -> NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: itemHeight.makeDimension()
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize, supplementaryItems: itemSupplementaries)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: itemSize, subitem: item, count: 1)
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = spacing
        section.contentInsets = contentInsets.directionalEdgeInsets
        return section
    }
}

private extension ListSectionGridLayout {
    @MainActor func makeCompositionalSection(
        itemSupplementaries: [NSCollectionLayoutSupplementaryItem]
    ) -> NSCollectionLayoutSection {
        let safeColumns = max(columns, 1)
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .fractionalHeight(1)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize, supplementaryItems: itemSupplementaries)
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: itemHeight.makeDimension()
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitem: item, count: safeColumns)
        group.interItemSpacing = .fixed(spacing)

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = spacing
        section.contentInsets = contentInsets.directionalEdgeInsets
        return section
    }
}

private extension ListSectionHorizontalLayout {
    @MainActor func makeCompositionalSection(
        itemSupplementaries: [NSCollectionLayoutSupplementaryItem]
    ) -> NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: itemWidth.makeDimension(),
            heightDimension: .fractionalHeight(1)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize, supplementaryItems: itemSupplementaries)
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: itemHeight.makeDimension()
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
        group.interItemSpacing = .fixed(spacing)

        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = scrollingBehavior.uiKitValue
        section.interGroupSpacing = spacing
        section.contentInsets = contentInsets.directionalEdgeInsets
        return section
    }
}

/// supplementary 相对 section 或 item 的锚点。
public enum ListSupplementaryAnchor: Hashable, Sendable {
    /// 左上角。
    case topLeading
    /// 顶部居中。
    case top
    /// 右上角。
    case topTrailing
    /// 左侧居中。
    case leading
    /// 中心。
    case center
    /// 右侧居中。
    case trailing
    /// 左下角。
    case bottomLeading
    /// 底部居中。
    case bottom
    /// 右下角。
    case bottomTrailing

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
        case .center:
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

/// supplementary 是 section boundary 还是 item-level。
public enum ListSupplementaryPlacement: Hashable, Sendable {
    /// section boundary supplementary。
    case boundary(
        alignment: ListSupplementaryAnchor,
        extendsBoundary: Bool,
        pinToVisibleBounds: Bool,
        offset: ListLayoutPoint
    )
    /// item-level supplementary。
    case itemSupplementary(anchor: ListSupplementaryAnchor, fractionalOffset: ListLayoutPoint)

    /// 是否为 item-level supplementary。
    public var isItem: Bool {
        if case .itemSupplementary = self { return true }
        return false
    }

    var placementKind: ListSupplementaryPlacementKind {
        switch self {
        case .boundary:
            return .boundary
        case .itemSupplementary:
            return .item
        }
    }
}

enum ListSupplementaryPlacementKind: Hashable, Sendable {
    case boundary
    case item
}

/// supplementary 的 compositional layout 描述。
public struct ListSupplementaryLayout: Hashable, Sendable {
    /// supplementary kind。
    public var kind: String
    /// supplementary 放置方式。
    public var placement: ListSupplementaryPlacement
    /// supplementary 宽度。
    public var width: ListLayoutDimension
    /// supplementary 高度。
    public var height: ListLayoutDimension
    /// supplementary zIndex。
    public var zIndex: Int

    /// 创建 supplementary layout 描述。
    ///
    /// - Parameters:
    ///   - kind: supplementary element kind。
    ///   - placement: boundary 或 item-level placement。
    ///   - width: supplementary 宽度。
    ///   - height: supplementary 高度。
    ///   - zIndex: supplementary 层级。
    /// - Note: 业务代码通常优先使用 `BoundarySupplementaryLayout` 或 `ItemSupplementaryLayout`。
    public init(
        kind: String,
        placement: ListSupplementaryPlacement,
        width: ListLayoutDimension = .fractionalWidth(1),
        height: ListLayoutDimension = .estimated(44),
        zIndex: Int = 0
    ) {
        self.kind = kind
        self.placement = placement
        self.width = width
        self.height = height
        self.zIndex = zIndex
    }

    @MainActor var layoutSize: NSCollectionLayoutSize {
        NSCollectionLayoutSize(widthDimension: width.makeDimension(), heightDimension: height.makeDimension())
    }

    @MainActor func makeBoundarySupplementaryItem() -> NSCollectionLayoutBoundarySupplementaryItem? {
        guard case let .boundary(alignment, extendsBoundary, pinToVisibleBounds, offset) = placement else {
            return nil
        }

        let item = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: layoutSize,
            elementKind: kind,
            alignment: alignment.boundaryAlignment,
            absoluteOffset: offset.cgPoint
        )
        item.extendsBoundary = extendsBoundary
        item.pinToVisibleBounds = pinToVisibleBounds
        item.zIndex = zIndex
        return item
    }

    @MainActor func makeItemSupplementaryItem() -> NSCollectionLayoutSupplementaryItem? {
        guard case let .itemSupplementary(anchor, fractionalOffset) = placement else {
            return nil
        }

        let layoutAnchor = NSCollectionLayoutAnchor(
            edges: anchor.directionalEdges,
            fractionalOffset: fractionalOffset.cgPoint
        )
        let item = NSCollectionLayoutSupplementaryItem(
            layoutSize: layoutSize,
            elementKind: kind,
            containerAnchor: layoutAnchor
        )
        item.zIndex = zIndex
        return item
    }

    var boundaryReservedContentInsets: ListLayoutInsets {
        guard width.isFullWidth, let inset = height.estimatedContentInsetValue else {
            return .zero
        }

        switch placement {
        case .boundary(let alignment, _, _, _):
            switch alignment {
            case .top:
                return ListLayoutInsets(top: inset)
            case .bottom:
                return ListLayoutInsets(bottom: inset)
            default:
                return .zero
            }
        case .itemSupplementary:
            return .zero
        }
    }

    func pinningBoundaryToVisibleBounds(_ isPinned: Bool = true) -> ListSupplementaryLayout {
        guard case let .boundary(alignment, extendsBoundary, _, offset) = placement else {
            return self
        }

        var copy = self
        copy.placement = .boundary(
            alignment: alignment,
            extendsBoundary: extendsBoundary,
            pinToVisibleBounds: isPinned,
            offset: offset
        )
        return copy
    }
}

/// 创建 supplementary layout 描述。
///
/// - Parameters:
///   - kind: supplementary element kind。
///   - placement: boundary 或 item-level placement。
///   - width: supplementary 宽度。
///   - height: supplementary 高度。
///   - zIndex: supplementary 层级。
/// - Returns: supplementary layout 描述。
public func SupplementaryLayout(
    kind: String,
    placement: ListSupplementaryPlacement,
    width: ListLayoutDimension = .fractionalWidth(1),
    height: ListLayoutDimension = .estimated(44),
    zIndex: Int = 0
) -> ListSupplementaryLayout {
    ListSupplementaryLayout(
        kind: kind,
        placement: placement,
        width: width,
        height: height,
        zIndex: zIndex
    )
}

/// 创建 section boundary supplementary layout。
///
/// - Parameters:
///   - kind: supplementary element kind。
///   - alignment: boundary 对齐方式。
///   - width: supplementary 宽度。
///   - height: supplementary 高度。
///   - extendsBoundary: 是否延伸到 section 边界外。
///   - pinned: 是否随滚动吸顶或吸底。
///   - offset: boundary 偏移。
///   - zIndex: supplementary 层级。
/// - Returns: boundary supplementary layout 描述。
public func BoundarySupplementaryLayout(
    kind: String,
    alignment: ListSupplementaryAnchor = .top,
    width: ListLayoutDimension = .fractionalWidth(1),
    height: ListLayoutDimension = .estimated(44),
    extendsBoundary: Bool = false,
    pinned: Bool = false,
    offset: CGPoint = .zero,
    zIndex: Int = 0
) -> ListSupplementaryLayout {
    SupplementaryLayout(
        kind: kind,
        placement: .boundary(
            alignment: alignment,
            extendsBoundary: extendsBoundary,
            pinToVisibleBounds: pinned,
            offset: ListLayoutPoint(offset)
        ),
        width: width,
        height: height,
        zIndex: zIndex
    )
}

/// 创建 item-level supplementary layout。
///
/// - Parameters:
///   - kind: supplementary element kind。
///   - anchor: item 上的锚点。
///   - width: supplementary 宽度。
///   - height: supplementary 高度。
///   - fractionalOffset: 相对 item 的偏移。
///   - zIndex: supplementary 层级。
/// - Returns: item-level supplementary layout 描述。
public func ItemSupplementaryLayout(
    kind: String,
    anchor: ListSupplementaryAnchor,
    width: ListLayoutDimension,
    height: ListLayoutDimension,
    fractionalOffset: CGPoint = .zero,
    zIndex: Int = 0
) -> ListSupplementaryLayout {
    SupplementaryLayout(
        kind: kind,
        placement: .itemSupplementary(anchor: anchor, fractionalOffset: ListLayoutPoint(fractionalOffset)),
        width: width,
        height: height,
        zIndex: zIndex
    )
}
