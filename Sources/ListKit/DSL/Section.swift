import UIKit

// MARK: - Section DSL

/// 一个 ListKit section 的完整描述。
///
/// - Note: `ListSection` 同时承载 rows、header/footer/supplementary、layout、selection 和
/// section 背景装饰。页面每次数据变化后重新构建描述树，adapter 根据 identity 和
/// refresh policy 判断 diff、重配或保持不动。
///
/// - Usage:
/// ```swift
/// ListSection(.users) {
///     ForEach(users, id: \.userID) { user in
///         Row(model: user, cell: UserCell.self) { cell, user, _ in
///             cell.configure(user)
///         }
///         .refreshID(user.profileVersion)
///     }
/// } layout: {
///     ListLayout(spacing: 8)
/// } header: {
///     Header(TitleHeaderView.self, id: "users-title") { view, _ in
///         view.titleLabel.text = "用户"
///     }
///     .layout(height: .estimated(44), pinned: true)
/// } background: {
///     BackgroundDecoration(GroupBackgroundView.self, contentInsets: .init(12))
/// }
/// ```
public struct ListSection<SectionID> where SectionID: Hashable & Sendable {
    /// 业务 section id。
    public let id: SectionID
    /// 类型擦除后的 row 描述。
    public var rows: [AnyListRow]
    /// 层级 section snapshot 的根节点；普通 section 中每个节点都是叶子。
    public var outlineRoots: [AnyListOutlineNode]
    /// 是否包含父子层级。
    public var hasOutlineHierarchy: Bool {
        outlineRoots.contains { !$0.children.isEmpty }
    }
    /// 类型擦除后的 supplementary 描述。
    public var supplementaries: [AnySupplementary]
    /// 旧 custom layout provider 用的布局标识。
    public var layoutID: AnyListID?
    /// ListKit 内建 section layout。
    public var sectionLayout: ListSectionLayout?
    /// 自定义 compositional layout 逃生口。
    public var customSectionLayout: ListCustomSectionLayout<SectionID>?
    /// supplementary kind 到 layout 描述的映射。
    public var supplementaryLayouts: [String: ListSupplementaryLayout]
    /// section 选择模式。
    public var selectionMode: ListSelectionMode
    /// 侧边索引中展示的标题。
    public var indexTitle: String?
    /// 是否允许通过二指平移等系统交互进入多选。
    public var allowsMultipleSelectionInteraction: Bool
    /// 旧 sticky header 快捷标记。
    public var isHeaderSticky: Bool
    /// section 背景装饰描述。
    public var backgroundDecorationItem: ListBackgroundDecoration?
    /// section 背景 decoration kind 快捷读取。
    public var backgroundDecorationKind: String? { backgroundDecorationItem?.kind }
    var layoutDiagnostics: [ListDiagnosticsIssue]
    var expansionChangeHandler: (@MainActor (AnyListIdentity, Bool) -> Void)?
    var visibleItemsInvalidationHandler: (@MainActor (
        [any NSCollectionLayoutVisibleItem],
        CGPoint,
        any NSCollectionLayoutEnvironment
    ) -> Void)?

    /// 创建 section，并用 builder 同时声明 rows、layout、supplementary 和背景。
    ///
    /// - Parameters:
    ///   - id: 业务 section id。
    ///   - rows: 生成当前 section rows 的 builder。
    ///   - layout: 生成当前 section 主 layout 的 builder。
    ///   - header: 生成 header supplementary 的 builder。
    ///   - footer: 生成 footer supplementary 的 builder。
    ///   - supplementaries: 生成自定义 supplementary 的 builder。
    ///   - supplementaryLayouts: 生成 supplementary layout 元数据的 builder。
    ///   - background: 生成 section 背景装饰的 builder。
    @MainActor public init(
        _ id: SectionID,
        @ListRowBuilder rows: () -> [any ListRowRepresentable],
        @ListSectionLayoutBuilder<SectionID> layout: () -> ListSectionLayoutConfiguration<SectionID>? = { nil },
        @ListSectionSupplementaryBuilder<SectionID> header: () -> [ListSectionSupplementary<SectionID>] = { [] },
        @ListSectionSupplementaryBuilder<SectionID> footer: () -> [ListSectionSupplementary<SectionID>] = { [] },
        @ListSectionSupplementaryBuilder<SectionID> supplementaries: () -> [ListSectionSupplementary<SectionID>] = { [] },
        @ListSupplementaryLayoutBuilder supplementaryLayouts: () -> [ListSupplementaryLayout] = { [] },
        @ListSectionBackgroundBuilder background: () -> ListBackgroundDecoration? = { nil }
    ) {
        self.id = id
        let outlineRoots = rows().flatMap { $0.eraseToAnyListOutlineNodes(sectionID: id) }
        self.outlineRoots = outlineRoots
        self.rows = outlineRoots.flatMap(\.flattenedRows)
        self.supplementaries = []
        self.layoutID = nil
        self.sectionLayout = nil
        self.customSectionLayout = nil
        self.supplementaryLayouts = [:]
        self.selectionMode = .none
        self.indexTitle = nil
        self.allowsMultipleSelectionInteraction = false
        self.isHeaderSticky = false
        self.backgroundDecorationItem = background()
        self.layoutDiagnostics = []
        self.expansionChangeHandler = nil
        self.visibleItemsInvalidationHandler = nil
        applyLayoutConfiguration(layout())
        appendSectionSupplementaries(header() + footer() + supplementaries())
        appendSupplementaryLayouts(supplementaryLayouts())
    }

    /// 设置 section 在 collection view 侧边索引中的标题。
    public func indexTitle(_ title: String?) -> Self {
        var copy = self
        copy.indexTitle = title
        return copy
    }

    /// 允许系统的多选手势从当前 section 开始。
    public func multipleSelectionInteraction(_ enabled: Bool = true) -> Self {
        var copy = self
        copy.allowsMultipleSelectionInteraction = enabled
        return copy
    }

    /// 监听 disclosure 节点展开状态变化。
    public func onExpansionChange(
        _ handler: @escaping @MainActor (AnyListIdentity, Bool) -> Void
    ) -> Self {
        var copy = self
        copy.expansionChangeHandler = handler
        return copy
    }

    /// 监听 orthogonal scrolling 或 bounds 变化引起的可见 item 失效。
    ///
    /// - Important: UIKit 当前不允许 invalidation handler 修改可见 item，只要同一个
    ///   compositional layout 中包含 estimated item。此时该闭包应仅用于观察；需要修改
    ///   `transform`、`alpha` 等属性时，请确保整个 layout 都使用确定尺寸。
    public func onVisibleItemsInvalidation(
        _ handler: @escaping @MainActor (
            [any NSCollectionLayoutVisibleItem],
            CGPoint,
            any NSCollectionLayoutEnvironment
        ) -> Void
    ) -> Self {
        var copy = self
        copy.visibleItemsInvalidationHandler = handler
        return copy
    }

    /// 添加默认 top boundary header。
    ///
    /// - Parameters:
    ///   - viewType: header reusable view 类型。
    ///   - id: header 身份。
    ///   - configure: 配置 header view 的闭包。
    /// - Returns: 添加 header 后的 section。
    /// - Note: 条件展示或自定义 layout 优先使用 `header:` builder。
    @MainActor public func header<ID, View>(
        _ viewType: View.Type,
        id: ID,
        configure: @escaping @MainActor (View, ListContext) -> Void
    ) -> Self where ID: Hashable & Sendable, View: UICollectionReusableView {
        supplementary(UICollectionView.elementKindSectionHeader, viewType, id: id, configure: configure)
    }

    /// 添加默认 bottom boundary footer。
    ///
    /// - Parameters:
    ///   - viewType: footer reusable view 类型。
    ///   - id: footer 身份。
    ///   - configure: 配置 footer view 的闭包。
    /// - Returns: 添加 footer 后的 section。
    @MainActor public func footer<ID, View>(
        _ viewType: View.Type,
        id: ID,
        configure: @escaping @MainActor (View, ListContext) -> Void
    ) -> Self where ID: Hashable & Sendable, View: UICollectionReusableView {
        supplementary(UICollectionView.elementKindSectionFooter, viewType, id: id, configure: configure)
    }

    /// 添加自定义 kind 的 supplementary view。
    ///
    /// - Parameters:
    ///   - kind: supplementary element kind。
    ///   - viewType: reusable view 类型。
    ///   - id: supplementary 身份。
    ///   - configure: 配置 reusable view 的闭包。
    /// - Returns: 添加 supplementary 后的 section。
    @MainActor public func supplementary<ID, View>(
        _ kind: String,
        _ viewType: View.Type,
        id: ID,
        configure: @escaping @MainActor (View, ListContext) -> Void
    ) -> Self where ID: Hashable & Sendable, View: UICollectionReusableView {
        var copy = self
        let item = Supplementary(kind, id: id, view: viewType, configure: configure)
        copy.supplementaries.append(item.eraseToAnySupplementary(sectionID: self.id))
        return copy
    }

    /// 添加已经构建好的 `Supplementary`。
    ///
    /// - Parameter supplementary: 已构建的 supplementary 描述。
    /// - Returns: 添加 supplementary 后的 section。
    @MainActor public func supplementary<ID, View>(_ supplementary: Supplementary<ID, View>) -> Self
        where ID: Hashable & Sendable, View: UICollectionReusableView
    {
        var copy = self
        copy.supplementaries.append(supplementary.eraseToAnySupplementary(sectionID: self.id))
        return copy
    }

    /// 追加 SwiftUI-like supplementary builder 内容。
    ///
    /// - Parameter content: 生成 header/footer/custom supplementary 的 builder。
    /// - Returns: 追加 supplementary 后的 section。
    @MainActor public func sectionSupplementaries(
        @ListSectionSupplementaryBuilder<SectionID> _ content: () -> [ListSectionSupplementary<SectionID>]
    ) -> Self {
        var copy = self
        copy.appendSectionSupplementaries(content())
        return copy
    }

    /// 添加 Provider-backed supplementary。
    ///
    /// - Parameter supplementary: provider-backed supplementary 描述。
    /// - Returns: 添加 supplementary 后的 section。
    /// - Important: 此入口只用于迁移期保留旧 provider 配置。
    @MainActor public func supplementary<ID>(_ supplementary: ProviderSupplementary<ID>) -> Self
        where ID: Hashable & Sendable
    {
        var copy = self
        copy.supplementaries.append(supplementary.eraseToAnySupplementary(sectionID: self.id))
        return copy
    }

    /// 绑定 section 布局标识，页面可用它在 compositional layout provider 里查找布局。
    ///
    /// - Parameter layoutID: 外部 layout provider 使用的稳定布局 id。
    /// - Returns: 绑定布局 id 后的 section。
    public func layout<LayoutID>(_ layoutID: LayoutID) -> Self where LayoutID: Hashable & Sendable {
        var copy = self
        copy.layoutID = AnyListID(layoutID)
        copy.sectionLayout = nil
        copy.customSectionLayout = nil
        return copy
    }

    /// 绑定 ListKit Layout DSL。
    ///
    /// - Parameter sectionLayout: ListKit 内建 section layout。
    /// - Returns: 绑定 layout 后的 section。
    public func layout(_ sectionLayout: ListSectionLayout) -> Self {
        var copy = self
        copy.layoutID = nil
        copy.sectionLayout = sectionLayout
        copy.customSectionLayout = nil
        return copy
    }

    /// 绑定自定义 compositional layout。
    ///
    /// - Parameter customLayout: 生成 `NSCollectionLayoutSection` 的自定义 layout 描述。
    /// - Returns: 绑定自定义 layout 后的 section。
    /// - Important: 自定义布局生成闭包和 section DSL 放在一起，避免旧的 `.custom(id:)`
    /// 只留下一个标识、再到外部 provider 二次 switch。
    public func layout(_ customLayout: ListCustomSectionLayout<SectionID>) -> Self {
        var copy = self
        copy.layoutID = nil
        copy.sectionLayout = nil
        copy.customSectionLayout = customLayout
        return copy
    }

    /// 通过 `ListSectionLayoutBuilder` 配置 section 主布局。
    ///
    /// - Parameter content: 生成当前 section 主 layout 的 builder。
    /// - Returns: 应用 layout builder 后的 section。
    public func layout(
        @ListSectionLayoutBuilder<SectionID> _ content: () -> ListSectionLayoutConfiguration<SectionID>?
    ) -> Self {
        var copy = self
        copy.applyLayoutConfiguration(content())
        return copy
    }

    /// 配置任意 supplementary 的 layout placement。
    ///
    /// - Parameters:
    ///   - kind: supplementary element kind。
    ///   - placement: boundary 或 item-level placement。
    ///   - width: supplementary 宽度。
    ///   - height: supplementary 高度。
    ///   - zIndex: supplementary 层级。
    /// - Returns: 应用 supplementary layout 后的 section。
    public func supplementaryLayout(
        kind: String,
        placement: ListSupplementaryPlacement,
        width: ListLayoutDimension = .fractionalWidth(1),
        height: ListLayoutDimension = .estimated(44),
        zIndex: Int = 0
    ) -> Self {
        settingSupplementaryLayout(
            ListSupplementaryLayout(
                kind: kind,
                placement: placement,
                width: width,
                height: height,
                zIndex: zIndex
            )
        )
    }

    /// 把 supplementary 放到 section boundary，例如 header/footer 或 section 角标。
    ///
    /// - Parameters:
    ///   - kind: supplementary element kind。
    ///   - alignment: boundary 对齐方式。
    ///   - width: supplementary 宽度。
    ///   - height: supplementary 高度。
    ///   - extendsBoundary: 是否延伸到 section 边界外。
    ///   - pinToVisibleBounds: 是否随滚动吸顶或吸底。
    ///   - offset: boundary 偏移。
    ///   - zIndex: supplementary 层级。
    /// - Returns: 应用 boundary layout 后的 section。
    public func boundarySupplementaryLayout(
        kind: String,
        alignment: ListSupplementaryAnchor = .top,
        width: ListLayoutDimension = .fractionalWidth(1),
        height: ListLayoutDimension = .estimated(44),
        extendsBoundary: Bool = false,
        pinToVisibleBounds: Bool = false,
        offset: CGPoint = .zero,
        zIndex: Int = 0
    ) -> Self {
        supplementaryLayout(
            kind: kind,
            placement: .boundary(
                alignment: alignment,
                extendsBoundary: extendsBoundary,
                pinToVisibleBounds: pinToVisibleBounds,
                offset: ListLayoutPoint(offset)
            ),
            width: width,
            height: height,
            zIndex: zIndex
        )
    }

    /// 把 custom supplementary 挂到每个 item 上。
    ///
    /// - Parameters:
    ///   - kind: supplementary element kind。
    ///   - anchor: item 上的锚点。
    ///   - width: supplementary 宽度。
    ///   - height: supplementary 高度。
    ///   - fractionalOffset: 相对 item 的偏移。
    ///   - zIndex: supplementary 层级。
    /// - Returns: 应用 item-level layout 后的 section。
    public func itemSupplementaryLayout(
        kind: String,
        anchor: ListSupplementaryAnchor,
        width: ListLayoutDimension,
        height: ListLayoutDimension,
        fractionalOffset: CGPoint = .zero,
        zIndex: Int = 0
    ) -> Self {
        supplementaryLayout(
            kind: kind,
            placement: .itemSupplementary(anchor: anchor, fractionalOffset: ListLayoutPoint(fractionalOffset)),
            width: width,
            height: height,
            zIndex: zIndex
        )
    }

    /// 通过 builder 批量配置 supplementary layout。
    ///
    /// - Parameter content: 生成 supplementary layout 元数据的 builder。
    /// - Returns: 应用 supplementary layouts 后的 section。
    /// - Note: 新页面优先把 header/footer 的布局写在 `Header(...).layout(...)` 上。
    public func supplementaryLayouts(
        @ListSupplementaryLayoutBuilder _ content: () -> [ListSupplementaryLayout]
    ) -> Self {
        var copy = self
        copy.appendSupplementaryLayouts(content())
        return copy
    }

    /// 设置 section 的选择模式。
    ///
    /// - Parameter mode: 当前 section 使用的选择模式。
    /// - Returns: 应用选择模式后的 section。
    public func selectionMode(_ mode: ListSelectionMode) -> Self {
        var copy = self
        copy.selectionMode = mode
        return copy
    }

    /// 快捷开启默认 header 的 sticky 行为。
    ///
    /// - Parameter isSticky: 是否让默认 header 吸顶。
    /// - Returns: 应用 sticky header 状态后的 section。
    /// - Note: 新写法优先在 `Header(...).layout(..., pinned: true)` 中声明。
    public func stickyHeader(_ isSticky: Bool = true) -> Self {
        var copy = self
        copy.isHeaderSticky = isSticky
        return copy
    }

    /// 使用 raw decoration kind 配置 section 背景。
    ///
    /// - Parameter kind: 已注册的 decoration view kind；传 `nil` 会清除背景。
    /// - Returns: 应用背景配置后的 section。
    /// - Important: raw kind 需要调用方提前注册 decoration view。
    public func backgroundDecoration(_ kind: String?) -> Self {
        var copy = self
        copy.backgroundDecorationItem = kind.map { ListBackgroundDecoration(kind: $0) }
        return copy
    }

    /// 使用 raw decoration kind 配置 section 背景，并设置 inset 与 zIndex。
    ///
    /// - Parameters:
    ///   - kind: 已注册的 decoration view kind。
    ///   - contentInsets: 背景相对 section 内容的 inset。
    ///   - zIndex: 背景层级。
    /// - Returns: 应用背景配置后的 section。
    public func backgroundDecoration(
        kind: String,
        contentInsets: ListLayoutInsets = .zero,
        zIndex: Int = -1
    ) -> Self {
        var copy = self
        copy.backgroundDecorationItem = ListBackgroundDecoration(
            kind: kind,
            contentInsets: contentInsets,
            zIndex: zIndex
        )
        return copy
    }

    /// 使用 typed decoration view 配置 section 背景。
    ///
    /// - Parameters:
    ///   - viewType: 背景 decoration view 类型；传 `nil` 会清除背景。
    ///   - kind: decoration view kind。
    ///   - contentInsets: 背景相对 section 内容的 inset。
    ///   - zIndex: 背景层级。
    /// - Returns: 应用背景配置后的 section。
    /// - Note: typed 入口会由 `CollectionListAdapter` 自动向当前 layout 注册 decoration view。
    public func backgroundDecoration<View>(
        _ viewType: View.Type?,
        kind: String = ListBackgroundDecoration.defaultKind,
        contentInsets: ListLayoutInsets = .zero,
        zIndex: Int = -1
    ) -> Self where View: UICollectionReusableView {
        var copy = self
        guard let viewType else {
            copy.backgroundDecorationItem = nil
            return copy
        }
        copy.backgroundDecorationItem = ListBackgroundDecoration(
            view: viewType,
            kind: kind,
            contentInsets: contentInsets,
            zIndex: zIndex
        )
        return copy
    }

    /// 通过 builder 条件配置 section 背景装饰。
    ///
    /// - Parameter content: 生成可选背景装饰的 builder。
    /// - Returns: 应用背景 builder 后的 section。
    public func background(
        @ListSectionBackgroundBuilder _ content: () -> ListBackgroundDecoration?
    ) -> Self {
        var copy = self
        copy.backgroundDecorationItem = content()
        return copy
    }

    /// 绑定 header 点击事件。
    ///
    /// - Parameter handler: header 被点击时调用的闭包。
    /// - Returns: 绑定事件后的 section。
    /// - Note: 如果 header 内部已有按钮，也可以在 header configure 闭包内调用 `context.send(...)`。
    @MainActor public func onHeaderTap(_ handler: @escaping @MainActor (ListContext) -> Void) -> Self {
        onSupplementaryTap(kind: UICollectionView.elementKindSectionHeader, handler)
    }

    /// 绑定 footer 点击事件。
    ///
    /// - Parameter handler: footer 被点击时调用的闭包。
    /// - Returns: 绑定事件后的 section。
    @MainActor public func onFooterTap(_ handler: @escaping @MainActor (ListContext) -> Void) -> Self {
        onSupplementaryTap(kind: UICollectionView.elementKindSectionFooter, handler)
    }

    @MainActor private func onSupplementaryTap(
        kind: String,
        _ handler: @escaping @MainActor (ListContext) -> Void
    ) -> Self {
        var copy = self
        guard let index = copy.supplementaries.lastIndex(where: { $0.kind == kind }) else {
            return copy
        }
        let base = copy.supplementaries[index]
        copy.supplementaries[index] = AnySupplementary(
            identity: base.identity,
            kind: base.kind,
            refreshID: base.refreshID,
            refreshPolicy: base.refreshPolicy,
            register: base.register,
            viewProvider: { collectionView, indexPath, context in
                let view = base.viewProvider(collectionView, indexPath, context)
                ListTapHandlerInstaller.install(on: view) {
                    handler(context)
                }
                return view
            },
            configureVisibleView: base.configureVisibleView,
            tapHandler: handler,
            displayHandler: base.displayHandler,
            endDisplayHandler: base.endDisplayHandler
        )
        return copy
    }

    /// 生成当前 section 的 compositional layout section。
    ///
    /// - Parameter fallback: 当前 section 没有声明 ListKit layout 时使用的 fallback。
    /// - Returns: 可交给 compositional layout provider 的 layout section。
    /// - Important: header/footer/custom kind 会根据 supplementary 声明自动补 boundary；
    /// 显式 item-level layout 则会挂到每一个 item 上。
    @MainActor public func makeCompositionalLayoutSection(
        fallback: NSCollectionLayoutSection? = nil
    ) -> NSCollectionLayoutSection {
        let layouts = resolvedSupplementaryLayouts()
        let itemSupplementaries = layouts.compactMap { $0.makeItemSupplementaryItem() }
        let section = fallback ?? (sectionLayout ?? .list()).makeCompositionalSection(
            itemSupplementaries: itemSupplementaries
        )
        section.boundarySupplementaryItems = layouts.compactMap { $0.makeBoundarySupplementaryItem() }
        section.contentInsets = contentInsetsWithReservedBoundarySpace(
            base: section.contentInsets,
            layouts: layouts
        )
        if let backgroundDecorationItem {
            section.decorationItems.append(backgroundDecorationItem.makeDecorationItem())
        }
        if let visibleItemsInvalidationHandler {
            section.visibleItemsInvalidationHandler = { items, offset, environment in
                MainActor.assumeIsolated {
                    visibleItemsInvalidationHandler(items, offset, environment)
                }
            }
        }
        return section
    }

    @MainActor func resolvedSupplementaryLayouts() -> [ListSupplementaryLayout] {
        var resolved: [ListSupplementaryLayout] = []
        var usedKinds: Set<String> = []

        for supplementary in supplementaries {
            let layout = supplementaryLayouts[supplementary.kind] ?? defaultSupplementaryLayout(for: supplementary.kind)
            resolved.append(layoutWithStickyHeaderIfNeeded(layout))
            usedKinds.insert(supplementary.kind)
        }

        return resolved
    }

    @MainActor private mutating func appendSectionSupplementaries(
        _ items: [ListSectionSupplementary<SectionID>]
    ) {
        for item in items {
            supplementaries.append(item.makeSupplementary(sectionID: id))
            if let layout = item.layout {
                applySupplementaryLayout(layout)
            }
        }
    }

    private mutating func applyLayoutConfiguration(_ configuration: ListSectionLayoutConfiguration<SectionID>?) {
        guard let configuration else { return }
        layoutID = configuration.layoutID
        sectionLayout = configuration.sectionLayout
        customSectionLayout = configuration.customSectionLayout
    }

    private mutating func appendSupplementaryLayouts(_ layouts: [ListSupplementaryLayout]) {
        for layout in layouts {
            applySupplementaryLayout(layout)
        }
    }

    private func settingSupplementaryLayout(_ layout: ListSupplementaryLayout) -> Self {
        var copy = self
        copy.applySupplementaryLayout(layout)
        return copy
    }

    private mutating func applySupplementaryLayout(_ layout: ListSupplementaryLayout) {
        if
            let existing = supplementaryLayouts[layout.kind],
            existing.placement.placementKind != layout.placement.placementKind
        {
            layoutDiagnostics.append(
                ListDiagnosticsIssue(
                    kind: .conflictingSupplementaryLayout,
                    message: "ListKit: supplementary kind \(layout.kind) configured as both \(existing.placement.placementKind) and \(layout.placement.placementKind); last explicit layout wins"
                )
            )
        }
        supplementaryLayouts[layout.kind] = layout
    }

    @MainActor private func defaultSupplementaryLayout(for kind: String) -> ListSupplementaryLayout {
        let alignment: ListSupplementaryAnchor
        if kind == UICollectionView.elementKindSectionFooter {
            alignment = .bottom
        } else {
            alignment = .top
        }

        return ListSupplementaryLayout(
            kind: kind,
            placement: .boundary(
                alignment: alignment,
                extendsBoundary: false,
                pinToVisibleBounds: false,
                offset: .zero
            ),
            width: .fractionalWidth(1),
            height: .estimated(44)
        )
    }

    @MainActor private func layoutWithStickyHeaderIfNeeded(_ layout: ListSupplementaryLayout) -> ListSupplementaryLayout {
        guard isHeaderSticky, layout.kind == UICollectionView.elementKindSectionHeader else {
            return layout
        }
        return layout.pinningBoundaryToVisibleBounds()
    }

    private func contentInsetsWithReservedBoundarySpace(
        base: NSDirectionalEdgeInsets,
        layouts: [ListSupplementaryLayout]
    ) -> NSDirectionalEdgeInsets {
        var insets = base
        for layout in layouts {
            let reserved = layout.boundaryReservedContentInsets
            insets.top += reserved.top
            insets.bottom += reserved.bottom
            insets.leading += reserved.leading
            insets.trailing += reserved.trailing
        }
        return insets
    }
}
