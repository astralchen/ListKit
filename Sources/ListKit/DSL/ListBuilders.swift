import UIKit

private struct InheritedIDRowScope: ListRowRepresentable {
    let row: any ListRowRepresentable
    let inheritedID: AnyListID

    @MainActor func eraseToAnyListRows<SectionID>(sectionID: SectionID) -> [AnyListRow]
        where SectionID: Hashable & Sendable
    {
        row.eraseToAnyListRows(sectionID: sectionID, inheritedID: inheritedID)
    }

    @MainActor func eraseToAnyListOutlineNodes<SectionID>(sectionID: SectionID) -> [AnyListOutlineNode]
        where SectionID: Hashable & Sendable
    {
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
///   - id: 指向元素业务 id 的 key path。
///   - content: 为每个元素生成 rows 的 builder。
/// - Returns: 可放入 `ListSection` 的 row 组合。
/// - Note: 内部使用 `Row(model:cell:)` 时会自动继承 `ForEach(id:)` 的身份。
@MainActor public func ForEach<Data, ID>(
    _ data: Data,
    id: KeyPath<Data.Element, ID>,
    @ListRowBuilder content: (Data.Element) -> [any ListRowRepresentable]
) -> RowGroup where Data: Sequence, ID: Hashable & Sendable {
    RowGroup(data.flatMap { element in
        let inheritedID = AnyListID(element[keyPath: id])
        return content(element).map { InheritedIDRowScope(row: $0, inheritedID: inheritedID) }
    })
}

/// 使用闭包生成遍历元素 id。
///
/// - Parameters:
///   - data: 要遍历的数据序列。
///   - id: 为元素生成业务 id 的闭包。
///   - content: 为每个元素生成 rows 的 builder。
/// - Returns: 可放入 `ListSection` 的 row 组合。
@MainActor public func ForEach<Data, ID>(
    _ data: Data,
    id: (Data.Element) -> ID,
    @ListRowBuilder content: (Data.Element) -> [any ListRowRepresentable]
) -> RowGroup where Data: Sequence, ID: Hashable & Sendable {
    RowGroup(data.flatMap { element in
        let inheritedID = AnyListID(id(element))
        return content(element).map { InheritedIDRowScope(row: $0, inheritedID: inheritedID) }
    })
}

/// `ListSection` rows 的 result builder。
///
/// 支持 `if`、`if/else`、`for`、数组和空分支，让页面用声明式方式 rebuild rows。
@resultBuilder
public enum ListRowBuilder {
    public static func buildExpression(_ expression: any ListRowRepresentable) -> [any ListRowRepresentable] {
        [expression]
    }

    public static func buildExpression(_ expression: [any ListRowRepresentable]) -> [any ListRowRepresentable] {
        expression
    }

    public static func buildExpression(_ expression: ()) -> [any ListRowRepresentable] {
        []
    }

    public static func buildBlock(_ components: [any ListRowRepresentable]...) -> [any ListRowRepresentable] {
        components.flatMap { $0 }
    }

    public static func buildArray(_ components: [[any ListRowRepresentable]]) -> [any ListRowRepresentable] {
        components.flatMap { $0 }
    }

    public static func buildEither(first component: [any ListRowRepresentable]) -> [any ListRowRepresentable] {
        component
    }

    public static func buildEither(second component: [any ListRowRepresentable]) -> [any ListRowRepresentable] {
        component
    }

    public static func buildOptional(_ component: [any ListRowRepresentable]?) -> [any ListRowRepresentable] {
        component ?? []
    }

    public static func buildLimitedAvailability(_ component: [any ListRowRepresentable]) -> [any ListRowRepresentable] {
        component
    }
}

/// `CollectionListAdapter.apply` 的 section result builder。
@resultBuilder
public enum ListSectionBuilder<SectionID> where SectionID: Hashable & Sendable {
    public static func buildExpression(_ expression: ListSection<SectionID>) -> [ListSection<SectionID>] {
        [expression]
    }

    public static func buildExpression(_ expression: [ListSection<SectionID>]) -> [ListSection<SectionID>] {
        expression
    }

    public static func buildExpression(_ expression: ()) -> [ListSection<SectionID>] {
        []
    }

    public static func buildBlock(_ components: [ListSection<SectionID>]...) -> [ListSection<SectionID>] {
        components.flatMap { $0 }
    }

    public static func buildArray(_ components: [[ListSection<SectionID>]]) -> [ListSection<SectionID>] {
        components.flatMap { $0 }
    }

    public static func buildEither(first component: [ListSection<SectionID>]) -> [ListSection<SectionID>] {
        component
    }

    public static func buildEither(second component: [ListSection<SectionID>]) -> [ListSection<SectionID>] {
        component
    }

    public static func buildOptional(_ component: [ListSection<SectionID>]?) -> [ListSection<SectionID>] {
        component ?? []
    }

    public static func buildLimitedAvailability(_ component: [ListSection<SectionID>]) -> [ListSection<SectionID>] {
        component
    }
}

/// Header/Footer/custom supplementary 的 result builder。
@resultBuilder
public enum ListSectionSupplementaryBuilder<SectionID> where SectionID: Hashable & Sendable {
    public static func buildExpression(_ expression: ListSectionSupplementary<SectionID>) -> [ListSectionSupplementary<SectionID>] {
        [expression]
    }

    public static func buildExpression(_ expression: [ListSectionSupplementary<SectionID>]) -> [ListSectionSupplementary<SectionID>] {
        expression
    }

    public static func buildExpression(_ expression: ()) -> [ListSectionSupplementary<SectionID>] {
        []
    }

    public static func buildBlock(_ components: [ListSectionSupplementary<SectionID>]...) -> [ListSectionSupplementary<SectionID>] {
        components.flatMap { $0 }
    }

    public static func buildArray(_ components: [[ListSectionSupplementary<SectionID>]]) -> [ListSectionSupplementary<SectionID>] {
        components.flatMap { $0 }
    }

    public static func buildEither(first component: [ListSectionSupplementary<SectionID>]) -> [ListSectionSupplementary<SectionID>] {
        component
    }

    public static func buildEither(second component: [ListSectionSupplementary<SectionID>]) -> [ListSectionSupplementary<SectionID>] {
        component
    }

    public static func buildOptional(_ component: [ListSectionSupplementary<SectionID>]?) -> [ListSectionSupplementary<SectionID>] {
        component ?? []
    }

    public static func buildLimitedAvailability(_ component: [ListSectionSupplementary<SectionID>]) -> [ListSectionSupplementary<SectionID>] {
        component
    }
}

/// Section 主布局的 result builder。
///
/// 多个分支同时产出布局时，最后一个非空配置生效。
@resultBuilder
public enum ListSectionLayoutBuilder<SectionID> where SectionID: Hashable & Sendable {
    public static func buildExpression(_ expression: ListSectionLayout) -> ListSectionLayoutConfiguration<SectionID>? {
        ListSectionLayoutConfiguration(sectionLayout: expression)
    }

    public static func buildExpression(_ expression: ListCustomSectionLayout<SectionID>) -> ListSectionLayoutConfiguration<SectionID>? {
        ListSectionLayoutConfiguration(customSectionLayout: expression)
    }

    public static func buildExpression(_ expression: ListSectionLayoutConfiguration<SectionID>) -> ListSectionLayoutConfiguration<SectionID>? {
        expression
    }

    public static func buildExpression(_ expression: ListSectionLayoutConfiguration<SectionID>?) -> ListSectionLayoutConfiguration<SectionID>? {
        expression
    }

    public static func buildExpression(_ expression: ()) -> ListSectionLayoutConfiguration<SectionID>? {
        nil
    }

    public static func buildBlock(
        _ components: ListSectionLayoutConfiguration<SectionID>?...
    ) -> ListSectionLayoutConfiguration<SectionID>? {
        components.compactMap { $0 }.last
    }

    public static func buildEither(
        first component: ListSectionLayoutConfiguration<SectionID>?
    ) -> ListSectionLayoutConfiguration<SectionID>? {
        component
    }

    public static func buildEither(
        second component: ListSectionLayoutConfiguration<SectionID>?
    ) -> ListSectionLayoutConfiguration<SectionID>? {
        component
    }

    public static func buildOptional(
        _ component: ListSectionLayoutConfiguration<SectionID>??
    ) -> ListSectionLayoutConfiguration<SectionID>? {
        component ?? nil
    }

    public static func buildLimitedAvailability(
        _ component: ListSectionLayoutConfiguration<SectionID>?
    ) -> ListSectionLayoutConfiguration<SectionID>? {
        component
    }
}

/// Supplementary layout 的 result builder。
@resultBuilder
public enum ListSupplementaryLayoutBuilder {
    public static func buildExpression(_ expression: ListSupplementaryLayout) -> [ListSupplementaryLayout] {
        [expression]
    }

    public static func buildExpression(_ expression: [ListSupplementaryLayout]) -> [ListSupplementaryLayout] {
        expression
    }

    public static func buildExpression(_ expression: ()) -> [ListSupplementaryLayout] {
        []
    }

    public static func buildBlock(_ components: [ListSupplementaryLayout]...) -> [ListSupplementaryLayout] {
        components.flatMap { $0 }
    }

    public static func buildArray(_ components: [[ListSupplementaryLayout]]) -> [ListSupplementaryLayout] {
        components.flatMap { $0 }
    }

    public static func buildEither(first component: [ListSupplementaryLayout]) -> [ListSupplementaryLayout] {
        component
    }

    public static func buildEither(second component: [ListSupplementaryLayout]) -> [ListSupplementaryLayout] {
        component
    }

    public static func buildOptional(_ component: [ListSupplementaryLayout]?) -> [ListSupplementaryLayout] {
        component ?? []
    }

    public static func buildLimitedAvailability(_ component: [ListSupplementaryLayout]) -> [ListSupplementaryLayout] {
        component
    }
}

/// Section 背景装饰的 result builder。
///
/// 多个分支同时产出背景时，最后一个非空配置生效。
@resultBuilder
public enum ListSectionBackgroundBuilder {
    public static func buildExpression(_ expression: ListBackgroundDecoration) -> ListBackgroundDecoration? {
        expression
    }

    public static func buildExpression(_ expression: ListBackgroundDecoration?) -> ListBackgroundDecoration? {
        expression
    }

    public static func buildExpression(_ expression: ()) -> ListBackgroundDecoration? {
        nil
    }

    public static func buildBlock(_ components: ListBackgroundDecoration?...) -> ListBackgroundDecoration? {
        components.compactMap { $0 }.last
    }

    public static func buildArray(_ components: [ListBackgroundDecoration?]) -> ListBackgroundDecoration? {
        components.compactMap { $0 }.last
    }

    public static func buildEither(first component: ListBackgroundDecoration?) -> ListBackgroundDecoration? {
        component
    }

    public static func buildEither(second component: ListBackgroundDecoration?) -> ListBackgroundDecoration? {
        component
    }

    public static func buildOptional(_ component: ListBackgroundDecoration??) -> ListBackgroundDecoration? {
        component ?? nil
    }

    public static func buildLimitedAvailability(_ component: ListBackgroundDecoration?) -> ListBackgroundDecoration? {
        component
    }
}

/// 独立构建 section 数组的 helper。
///
/// - Note: 页面可以先组合 sections，再调用 `adapter.apply(sections)`。
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
