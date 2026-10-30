import UIKit

// MARK: - Section DSL

/// 分区的内容、布局与交互配置。
///
/// 每个分区使用一个可整体替换的布局值；替换布局时保留已有内容注册。
public struct ListSection<SectionID> where SectionID: Hashable & Sendable {
    /// section 的稳定 id。
    public let id: SectionID
    /// 类型擦除后的 row 描述。
    public internal(set) var rows: [AnyListRow]
    /// 层级 section snapshot 的根节点；普通 section 中每个节点都是叶子。
    public internal(set) var outlineRoots: [AnyListOutlineNode]
    /// 是否包含父子层级。
    public var hasOutlineHierarchy: Bool {
        outlineRoots.contains { !$0.children.isEmpty }
    }
    /// 类型擦除后的 supplementary 描述。
    public internal(set) var supplementaries: [AnySupplementary]
    /// 唯一布局来源。未声明时为普通列表；通过 layout builder 替换整个值。
    public private(set) var layoutSource: ListSectionLayoutSource<SectionID>
    /// section 选择模式，默认为根据 Row 选择意图自动解析。
    public var selectionMode: ListSelectionMode
    /// 侧边索引中展示的标题。
    public var indexTitle: String?
    /// 是否允许通过二指平移等系统交互进入多选。
    public var allowsMultipleSelectionInteraction: Bool
    /// 当前分区的装饰视图注册声明，几何由分区布局配置决定。
    public private(set) var decorations: [SectionDecoration]
    var expansionChangeHandler: (@MainActor (AnyListIdentity, Bool) -> Void)?
    var visibleItemsInvalidationHandler:
        (
            @MainActor (
                [any NSCollectionLayoutVisibleItem],
                CGPoint,
                any NSCollectionLayoutEnvironment
            ) -> Void
        )?

    /// 创建 section，并用 builder 同时声明 rows、layout、supplementary 和背景。
    ///
    /// - Parameters:
    ///   - id: section 的稳定 id。
    ///   - rows: 生成当前 section rows 的 builder；`{ }` 生成空内容。
    ///   - layout: 生成当前 section 完整布局；省略、`{ }`、空分支或 nil 均使用默认单轨道估算布局。
    ///   - supplementaries: 生成自定义 supplementary 的 builder；省略或 `{ }` 均不声明补充内容。
    ///   - decorations: decoration 注册声明；省略或 `{ }` 均不注册装饰。未配置布局的 decorationItems 时自动生成默认背景几何。
    @MainActor public init(
        _ id: SectionID,
        @ListRowBuilder rows: () -> [any ListRowRepresentable],
        @ListSectionLayoutBuilder<SectionID> layout: () -> ListSectionLayoutSource<SectionID>? = {
            nil
        },
        @ListSectionSupplementaryBuilder<SectionID> supplementaries: () -> [ListSectionSupplementary<
            SectionID
        >] = { [] },
        @ListLayoutArrayBuilder<SectionDecoration> decorations: () -> [SectionDecoration] = { [] }
    ) {
        self.id = id
        let outlineRoots = rows().flatMap { $0.eraseToAnyListOutlineNodes(sectionID: id) }
        self.outlineRoots = outlineRoots
        self.rows = outlineRoots.flatMap(\.flattenedRows)
        self.supplementaries = []
        self.layoutSource = layout() ?? .builtIn(.defaultLayout)
        self.selectionMode = .automatic
        self.indexTitle = nil
        self.allowsMultipleSelectionInteraction = false
        self.decorations = decorations()
        self.expansionChangeHandler = nil
        self.visibleItemsInvalidationHandler = nil
        appendSectionSupplementaries(supplementaries())
    }

    /// 设置 section 在 collection view 侧边索引中的标题。
    public func indexTitle(_ title: String?) -> Self {
        var copy = self
        copy.indexTitle = title
        return copy
    }

    /// 允许系统的多选手势从当前 section 开始。仅在 `.selectionMode(.multiple)` 时生效。
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
    /// 重复调用替换原 handler；若 CustomLayout 的 Section 已设置 handler，此声明会覆盖它。
    ///
    /// - Important: 闭包直接交给 UIKit，ListKit 不执行 self-sizing 兼容性检查。
    ///   包含 estimated item 时应仅用于观察；需要修改 `transform`、`alpha` 等属性时，
    ///   请使用确定尺寸并在目标系统验证，不能将回调注册成功视为支持所有尺寸组合。
    public func onVisibleItemsInvalidation(
        _ handler:
            @escaping @MainActor (
                [any NSCollectionLayoutVisibleItem],
                CGPoint,
                any NSCollectionLayoutEnvironment
            ) -> Void
    ) -> Self {
        var copy = self
        copy.visibleItemsInvalidationHandler = handler
        return copy
    }

    /// 完整替换 supplementary 内容声明；空 builder 清空内容集合。
    /// 不修改布局几何；布局仍要求对应内容时，由正常的布局校验报告缺失绑定。
    @MainActor public func supplementaries(
        @ListSectionSupplementaryBuilder<SectionID> _ content: () -> [ListSectionSupplementary<
            SectionID
        >]
    ) -> Self {
        var copy = self
        copy.supplementaries = content().map { $0.makeSupplementary(sectionID: id) }
        return copy
    }

    /// 按声明顺序追加 supplementary 内容，不修改布局几何；空 builder 保留原集合。
    /// 不去重或覆盖相同 kind，重复声明由正常的 Section 校验报告。
    @MainActor public func addingSupplementaries(
        @ListSectionSupplementaryBuilder<SectionID> _ content: () -> [ListSectionSupplementary<
            SectionID
        >]
    ) -> Self {
        var copy = self
        copy.appendSectionSupplementaries(content())
        return copy
    }

    /// 通过 `ListSectionLayoutBuilder` 配置 section 完整布局。
    /// 替换布局主体及其所有修饰配置，不与原布局合并；内容与注册声明保持不变。
    /// 空 builder 或 nil 会恢复默认单轨道估算布局，不是保留原布局或隐藏 Section。
    ///
    /// - Parameter content: 生成当前 section 完整 layout 的 builder。
    /// - Returns: 应用 layout builder 后的 section。
    public func layout(
        @ListSectionLayoutBuilder<SectionID> _ content: () -> ListSectionLayoutSource<SectionID>?
    ) -> Self {
        var copy = self
        copy.layoutSource = content() ?? .builtIn(.defaultLayout)
        return copy
    }

    /// 设置 section 的选择模式。
    ///
    /// - Parameter mode: 当前 section 使用的选择模式；默认为 `.automatic`。
    /// - Returns: 应用选择模式后的 section。
    public func selectionMode(_ mode: ListSelectionMode) -> Self {
        var copy = self
        copy.selectionMode = mode
        return copy
    }

    /// 完整替换 decoration 注册声明，不追加；空 builder 清空注册集合。
    /// 显式几何仍由 layout.decorationItems 决定。
    /// 布局未指定 decorationItems 时，按替换后的注册声明生成默认背景几何。
    public func decorations(
        @ListLayoutArrayBuilder<SectionDecoration> _ content: () -> [SectionDecoration]
    ) -> Self {
        var copy = self
        copy.decorations = content()
        return copy
    }

    /// 按声明顺序追加 decoration 注册；空 builder 保留原集合。
    /// 不去重或覆盖相同逻辑 kind，重复声明由正常的 Section 校验报告。
    /// 显式几何保持不变；未指定 decorationItems 时，新增注册也会生成默认背景几何。
    public func addingDecorations(
        @ListLayoutArrayBuilder<SectionDecoration> _ content: () -> [SectionDecoration]
    ) -> Self {
        var copy = self
        copy.decorations += content()
        return copy
    }

    @MainActor private mutating func appendSectionSupplementaries(
        _ items: [ListSectionSupplementary<SectionID>]
    ) {
        supplementaries += items.map { $0.makeSupplementary(sectionID: id) }
    }
}
