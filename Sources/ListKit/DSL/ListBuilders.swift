import UIKit

private struct InheritedIDRowScope: ListRowRepresentable {
    let row: any ListRowRepresentable
    let inheritedID: AnyListID

    @MainActor func eraseToAnyListRows<SectionID>(sectionID: SectionID) -> [AnyListRow]
    where SectionID: Hashable & Sendable {
        row.eraseToAnyListRows(sectionID: sectionID, inheritedID: inheritedID)
    }

    @MainActor func eraseToAnyListOutlineNodes<SectionID>(sectionID: SectionID)
        -> [AnyListOutlineNode]
    where SectionID: Hashable & Sendable {
        row.eraseToAnyListOutlineNodes(sectionID: sectionID, inheritedID: inheritedID)
    }
}

/// 在 `ListSection` 中遍历数据并把外层 id 传给内部 Row。
///
/// - Usage:
/// ```swift
/// ForEach(users, id: \.userID) { user in
///     Row(model: user, cell: UserCell.self) { cell, user, _ in
///         cell.configure(user)
///     }
/// }
/// ```
/// - Parameters:
///   - data: 要遍历的数据序列。
///   - id: 指向元素稳定 id 的 key path。
///   - content: 为每个元素生成 rows 的 builder。
/// - Returns: 可放入 `ListSection` 的 row 组合。
/// - Note: 内部使用 `Row(model:cell:)` 时会自动继承 `ForEach(id:)` 的身份。
@MainActor public func ForEach<Data, ID>(
    _ data: Data,
    id: KeyPath<Data.Element, ID>,
    @ListRowBuilder content: (Data.Element) -> [any ListRowRepresentable]
) -> RowGroup where Data: Sequence, ID: Hashable & Sendable {
    RowGroup(
        data.flatMap { element in
            let inheritedID = AnyListID(element[keyPath: id])
            return content(element).map { InheritedIDRowScope(row: $0, inheritedID: inheritedID) }
        })
}

/// 使用闭包生成遍历元素 id。
///
/// - Parameters:
///   - data: 要遍历的数据序列。
///   - id: 为元素生成稳定 id 的闭包。
///   - content: 为每个元素生成 rows 的 builder。
/// - Returns: 可放入 `ListSection` 的 row 组合。
@MainActor public func ForEach<Data, ID>(
    _ data: Data,
    id: (Data.Element) -> ID,
    @ListRowBuilder content: (Data.Element) -> [any ListRowRepresentable]
) -> RowGroup where Data: Sequence, ID: Hashable & Sendable {
    RowGroup(
        data.flatMap { element in
            let inheritedID = AnyListID(id(element))
            return content(element).map { InheritedIDRowScope(row: $0, inheritedID: inheritedID) }
        })
}

/// 按声明顺序组合分区条目的结果构建器。
///
/// 支持 `if`、`if/else`、`for`、数组和空分支，让调用方以声明式方式 rebuild rows。
@resultBuilder
public enum ListRowBuilder {
    /// 将表达式转换为构建器的元素集合。
    public static func buildExpression(_ expression: any ListRowRepresentable)
        -> [any ListRowRepresentable]
    {
        [expression]
    }

    /// 按原顺序接收表达式数组。
    public static func buildExpression(_ expression: [any ListRowRepresentable])
        -> [any ListRowRepresentable]
    {
        expression
    }

    /// 将不产生值的表达式转换为空集合。
    public static func buildExpression(_ expression: ()) -> [any ListRowRepresentable] {
        []
    }

    /// 按声明顺序合并构建块中的元素集合。
    public static func buildBlock(_ components: [any ListRowRepresentable]...)
        -> [any ListRowRepresentable]
    {
        components.flatMap { $0 }
    }

    /// 按迭代顺序合并循环各次生成的元素集合。
    public static func buildArray(_ components: [[any ListRowRepresentable]])
        -> [any ListRowRepresentable]
    {
        components.flatMap { $0 }
    }

    /// 返回条件表达式第一个分支的构建结果。
    public static func buildEither(first component: [any ListRowRepresentable])
        -> [any ListRowRepresentable]
    {
        component
    }

    /// 返回条件表达式第二个分支的构建结果。
    public static func buildEither(second component: [any ListRowRepresentable])
        -> [any ListRowRepresentable]
    {
        component
    }

    /// 返回可选分支的元素；分支不存在时返回空集合。
    public static func buildOptional(_ component: [any ListRowRepresentable]?)
        -> [any ListRowRepresentable]
    {
        component ?? []
    }

    /// 传递通过系统可用性检查的分支结果。
    public static func buildLimitedAvailability(_ component: [any ListRowRepresentable])
        -> [any ListRowRepresentable]
    {
        component
    }
}

/// 按声明顺序组合集合视图分区的结果构建器。
@resultBuilder
public enum ListSectionBuilder<SectionID> where SectionID: Hashable & Sendable {
    /// 将表达式转换为构建器的元素集合。
    public static func buildExpression(_ expression: ListSection<SectionID>) -> [ListSection<
        SectionID
    >] {
        [expression]
    }

    /// 按原顺序接收表达式数组。
    public static func buildExpression(_ expression: [ListSection<SectionID>]) -> [ListSection<
        SectionID
    >] {
        expression
    }

    /// 将不产生值的表达式转换为空集合。
    public static func buildExpression(_ expression: ()) -> [ListSection<SectionID>] {
        []
    }

    /// 按声明顺序合并构建块中的元素集合。
    public static func buildBlock(_ components: [ListSection<SectionID>]...) -> [ListSection<
        SectionID
    >] {
        components.flatMap { $0 }
    }

    /// 按迭代顺序合并循环各次生成的元素集合。
    public static func buildArray(_ components: [[ListSection<SectionID>]]) -> [ListSection<
        SectionID
    >] {
        components.flatMap { $0 }
    }

    /// 返回条件表达式第一个分支的构建结果。
    public static func buildEither(first component: [ListSection<SectionID>]) -> [ListSection<
        SectionID
    >] {
        component
    }

    /// 返回条件表达式第二个分支的构建结果。
    public static func buildEither(second component: [ListSection<SectionID>]) -> [ListSection<
        SectionID
    >] {
        component
    }

    /// 返回可选分支的元素；分支不存在时返回空集合。
    public static func buildOptional(_ component: [ListSection<SectionID>]?) -> [ListSection<
        SectionID
    >] {
        component ?? []
    }

    /// 传递通过系统可用性检查的分支结果。
    public static func buildLimitedAvailability(_ component: [ListSection<SectionID>])
        -> [ListSection<SectionID>]
    {
        component
    }
}

/// 组合分区附属视图内容的结果构建器。
@resultBuilder
public enum ListSectionSupplementaryBuilder<SectionID> where SectionID: Hashable & Sendable {
    /// 将表达式转换为构建器的元素集合。
    public static func buildExpression(_ expression: ListSectionSupplementary<SectionID>)
        -> [ListSectionSupplementary<SectionID>]
    {
        [expression]
    }

    /// 将表达式转换为构建器的元素集合。可选值为 `nil` 时返回空集合。
    public static func buildExpression(_ expression: ListSectionSupplementary<SectionID>?)
        -> [ListSectionSupplementary<SectionID>]
    {
        expression.map { [$0] } ?? []
    }

    /// 按原顺序接收表达式数组。
    public static func buildExpression(_ expression: [ListSectionSupplementary<SectionID>])
        -> [ListSectionSupplementary<SectionID>]
    {
        expression
    }

    /// 将不产生值的表达式转换为空集合。
    public static func buildExpression(_ expression: ()) -> [ListSectionSupplementary<SectionID>] {
        []
    }

    /// 按声明顺序合并构建块中的元素集合。
    public static func buildBlock(_ components: [ListSectionSupplementary<SectionID>]...)
        -> [ListSectionSupplementary<SectionID>]
    {
        components.flatMap { $0 }
    }

    /// 按迭代顺序合并循环各次生成的元素集合。
    public static func buildArray(_ components: [[ListSectionSupplementary<SectionID>]])
        -> [ListSectionSupplementary<SectionID>]
    {
        components.flatMap { $0 }
    }

    /// 返回条件表达式第一个分支的构建结果。
    public static func buildEither(first component: [ListSectionSupplementary<SectionID>])
        -> [ListSectionSupplementary<SectionID>]
    {
        component
    }

    /// 返回条件表达式第二个分支的构建结果。
    public static func buildEither(second component: [ListSectionSupplementary<SectionID>])
        -> [ListSectionSupplementary<SectionID>]
    {
        component
    }

    /// 返回可选分支的元素；分支不存在时返回空集合。
    public static func buildOptional(_ component: [ListSectionSupplementary<SectionID>]?)
        -> [ListSectionSupplementary<SectionID>]
    {
        component ?? []
    }

    /// 传递通过系统可用性检查的分支结果。
    public static func buildLimitedAvailability(_ component: [ListSectionSupplementary<SectionID>])
        -> [ListSectionSupplementary<SectionID>]
    {
        component
    }
}

/// 选择单个完整分区布局的结果构建器。
///
/// 零或一个布局；多个并列值在编译期被拒绝。支持 if/else 和可选分支。
/// 空 builder 或 nil 交给 Section / EnvironmentLayout 解析为默认单轨道估算布局，不表示隐藏或保留旧布局。
@resultBuilder
public enum ListSectionLayoutBuilder<SectionID> where SectionID: Hashable & Sendable {
    /// 将布局声明转换为分区布局来源。
    public static func buildExpression(_ value: ListCustomLayout<SectionID>)
        -> ListSectionLayoutSource<SectionID>?
    { .custom(value) }
    /// 将布局声明转换为分区布局来源。可选值为 `nil` 时不提供布局。
    public static func buildExpression(_ value: ListCustomLayout<SectionID>?)
        -> ListSectionLayoutSource<SectionID>?
    { value.map { .custom($0) } }

    /// 将布局声明转换为分区布局来源。可选值为 `nil` 时不提供布局。
    public static func buildExpression(_ expression: ListSectionGridLayout?)
        -> ListSectionLayoutSource<SectionID>?
    {
        expression.map { .builtIn(.gridConfiguration($0)) }
    }

    /// 将布局声明转换为分区布局来源。
    public static func buildExpression(_ expression: ListSectionGridLayout)
        -> ListSectionLayoutSource<SectionID>?
    {
        .builtIn(.gridConfiguration(expression))
    }

    /// 将布局声明转换为分区布局来源。可选值为 `nil` 时不提供布局。
    public static func buildExpression(_ expression: ListUIKitListLayout?) -> ListSectionLayoutSource<
        SectionID
    >? {
        expression.map { .builtIn(.uiKitListConfiguration($0)) }
    }

    /// 将布局声明转换为分区布局来源。
    public static func buildExpression(_ expression: ListUIKitListLayout) -> ListSectionLayoutSource<
        SectionID
    >? {
        .builtIn(.uiKitListConfiguration(expression))
    }

    /// 将布局声明转换为分区布局来源。可选值为 `nil` 时不提供布局。
    public static func buildExpression(_ expression: ListSectionLayout?) -> ListSectionLayoutSource<
        SectionID
    >? {
        expression.map { .builtIn($0) }
    }

    /// 将布局声明转换为分区布局来源。
    public static func buildExpression(_ expression: ListSectionLayout) -> ListSectionLayoutSource<
        SectionID
    >? {
        .builtIn(expression)
    }

    /// 将布局声明转换为分区布局来源。
    public static func buildExpression(_ expression: ListSectionLayoutSource<SectionID>)
        -> ListSectionLayoutSource<SectionID>?
    {
        expression
    }

    /// 将布局声明转换为分区布局来源。可选值为 `nil` 时不提供布局。
    public static func buildExpression(_ expression: ListSectionLayoutSource<SectionID>?)
        -> ListSectionLayoutSource<SectionID>?
    {
        expression
    }

    /// 将不产生值的表达式转换为空布局结果。
    public static func buildExpression(_ expression: ()) -> ListSectionLayoutSource<SectionID>? {
        nil
    }

    /// 为空构建块返回未指定布局的结果。
    public static func buildBlock() -> ListSectionLayoutSource<SectionID>? { nil }
    /// 返回构建块中的唯一布局来源。
    public static func buildBlock(_ component: ListSectionLayoutSource<SectionID>?)
        -> ListSectionLayoutSource<SectionID>?
    { component }

    /// 返回条件表达式第一个分支的构建结果。
    public static func buildEither(
        first component: ListSectionLayoutSource<SectionID>?
    ) -> ListSectionLayoutSource<SectionID>? {
        component
    }

    /// 返回条件表达式第二个分支的构建结果。
    public static func buildEither(
        second component: ListSectionLayoutSource<SectionID>?
    ) -> ListSectionLayoutSource<SectionID>? {
        component
    }

    /// 返回可选分支的布局来源；分支不存在时返回 `nil`。
    public static func buildOptional(
        _ component: ListSectionLayoutSource<SectionID>??
    ) -> ListSectionLayoutSource<SectionID>? {
        component ?? nil
    }

    /// 传递通过系统可用性检查的分支结果。
    public static func buildLimitedAvailability(
        _ component: ListSectionLayoutSource<SectionID>?
    ) -> ListSectionLayoutSource<SectionID>? {
        component
    }
}

/// 独立构建 section 数组的 helper。
///
/// - Note: 调用方可以先组合 sections，再调用 `adapter.apply(sections)`。
public enum ListSectionsBuilder<SectionID> where SectionID: Hashable & Sendable {
    /// 执行 section builder 并返回 section 数组。
    ///
    /// - Parameter content: 生成 section 数组的 builder。
    /// - Returns: 构建完成的 section 数组。
    @MainActor public static func build(
        @ListSectionBuilder<SectionID> _ content: () -> [ListSection<SectionID>]
    ) -> [ListSection<SectionID>] {
        content()
    }
}
