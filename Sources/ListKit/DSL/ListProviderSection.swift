import UIKit

public typealias ListSelectionHandler = @Sendable @MainActor (_ indexPath: IndexPath) -> Void
public typealias ListSupplementarySelectionHandler = @Sendable @MainActor (_ kind: String, _ indexPath: IndexPath) -> Void

/// 迁移兼容层：新页面优先使用 `Row(model:id:cell:)` 和 `ListSection`。
@available(*, deprecated, message: "Migration-only compatibility. Prefer Row(model:id:cell:) and ListSection.")
public protocol ListCellProvider: Hashable, Sendable {
    associatedtype ItemIdentifier: Hashable & Sendable
    typealias SelectionHandler = ListSelectionHandler

    var identifier: ItemIdentifier { get }
    var selectionHandler: ListSelectionHandler? { get }

    @MainActor func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell
    @MainActor func configureVisibleCell(_ cell: UICollectionViewCell, collectionView: UICollectionView, at indexPath: IndexPath)
}

@available(*, deprecated, message: "Migration-only compatibility. Prefer Row(model:id:cell:) and ListSection.")
public extension ListCellProvider {
    var selectionHandler: ListSelectionHandler? { nil }

    @MainActor func configureVisibleCell(_ cell: UICollectionViewCell, collectionView: UICollectionView, at indexPath: IndexPath) {}

    @MainActor func eraseToAnyListCellProvider() -> AnyListCellProvider {
        AnyListCellProvider(self)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.identifier == rhs.identifier
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }
}

/// 迁移兼容层：用于把旧 item provider 接入 ListKit diff/selection。
@available(*, deprecated, message: "Migration-only compatibility. Prefer Row(model:id:cell:) and ListSection.")
public struct AnyListCellProvider: Hashable, Sendable {
    public let identity: AnyListID

    private let presentationID: ObjectIdentifier
    private let selection: ListSelectionHandler?
    private let makeCell: @MainActor (UICollectionView, IndexPath, ListContext) -> UICollectionViewCell
    private let reconfigure: @MainActor (UICollectionViewCell, UICollectionView, IndexPath) -> Void

    @MainActor public init<Item>(_ item: Item) where Item: ListCellProvider {
        self.identity = AnyListID(item.identifier)
        self.presentationID = ObjectIdentifier(Item.self)
        self.selection = item.selectionHandler
        self.makeCell = { collectionView, indexPath, _ in
            item.collectionView(collectionView, cellForItemAt: indexPath)
        }
        self.reconfigure = { cell, collectionView, indexPath in
            item.configureVisibleCell(cell, collectionView: collectionView, at: indexPath)
        }
    }

    @MainActor func makeRow() -> ProviderRow<AnyListID> {
        ProviderRow(
            identity,
            presentationID: presentationID,
            register: { _ in },
            cellProvider: makeCell,
            configureVisibleCell: { cell, context in
                reconfigure(cell, context.collectionView, context.indexPath)
            }
        )
        .onSelect { context in
            selection?(context.indexPath)
        }
    }

    @MainActor func performSelection(at indexPath: IndexPath) {
        selection?(indexPath)
    }

    public func typedIdentifier<ID>(_ type: ID.Type = ID.self) -> ID? where ID: Hashable & Sendable {
        identity.typed(type)
    }

    @MainActor public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let context = ListContext(
            sectionID: AnyListID(indexPath.section),
            indexPath: indexPath,
            collectionView: collectionView,
            eventDispatcher: { _, _ in }
        )
        return makeCell(collectionView, indexPath, context)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.identity == rhs.identity && lhs.presentationID == rhs.presentationID
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identity)
        hasher.combine(presentationID)
    }
}

/// 迁移兼容层：新页面优先使用 `ListSection.header/footer/supplementary`。
@available(*, deprecated, message: "Migration-only compatibility. Prefer ListSection.header/footer/supplementary.")
public protocol ListSupplementaryProvider: Hashable, Sendable {
    associatedtype SupplementaryIdentifier: Hashable & Sendable
    typealias SelectionHandler = ListSupplementarySelectionHandler

    var identifier: SupplementaryIdentifier { get }
    @MainActor var elementKind: String { get }
    var selectionHandler: ListSupplementarySelectionHandler? { get }

    @MainActor func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView
}

@available(*, deprecated, message: "Migration-only compatibility. Prefer ListSection.header/footer/supplementary.")
public extension ListSupplementaryProvider {
    var selectionHandler: ListSupplementarySelectionHandler? { nil }

    @MainActor func eraseToAnyListSupplementaryProvider() -> AnyListSupplementaryProvider {
        AnyListSupplementaryProvider(self)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.identifier == rhs.identifier
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }
}

/// 迁移兼容层：用于把旧 supplementary provider 接入 ListKit。
@available(*, deprecated, message: "Migration-only compatibility. Prefer ListSection.header/footer/supplementary.")
public struct AnyListSupplementaryProvider: Hashable, Sendable {
    public let identity: AnyListID
    public let elementKind: String

    private let presentationID: ObjectIdentifier
    private let selection: ListSupplementarySelectionHandler?
    private let makeView: @MainActor (UICollectionView, String, IndexPath, ListContext) -> UICollectionReusableView

    @MainActor public init<Item>(_ item: Item) where Item: ListSupplementaryProvider {
        self.identity = AnyListID(item.identifier)
        self.elementKind = item.elementKind
        self.presentationID = ObjectIdentifier(Item.self)
        self.selection = item.selectionHandler
        self.makeView = { collectionView, kind, indexPath, _ in
            item.collectionView(collectionView, viewForSupplementaryElementOfKind: kind, at: indexPath)
        }
    }

    @MainActor func makeSupplementary() -> ProviderSupplementary<AnyListID> {
        ProviderSupplementary(
            elementKind,
            id: identity,
            presentationID: presentationID,
            register: { _ in },
            viewProvider: { collectionView, indexPath, context in
                makeView(collectionView, elementKind, indexPath, context)
            }
        )
        .onTap { context in
            selection?(elementKind, context.indexPath)
        }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.identity == rhs.identity && lhs.presentationID == rhs.presentationID && lhs.elementKind == rhs.elementKind
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identity)
        hasher.combine(presentationID)
        hasher.combine(elementKind)
    }
}

/// 迁移兼容层：新页面优先使用 `ListRowBuilder` 和 `Row`。
@resultBuilder
@available(*, deprecated, message: "Migration-only compatibility. Prefer ListRowBuilder with Row.")
public enum ListCellProviderBuilder {
    @MainActor public static func buildExpression(_ expression: any ListCellProvider) -> [AnyListCellProvider] {
        [expression.eraseToAnyListCellProvider()]
    }

    public static func buildExpression(_ expression: [AnyListCellProvider]) -> [AnyListCellProvider] {
        expression
    }

    @MainActor public static func buildExpression(_ expression: [any ListCellProvider]) -> [AnyListCellProvider] {
        expression.map { $0.eraseToAnyListCellProvider() }
    }

    public static func buildExpression(_ expression: ()) -> [AnyListCellProvider] {
        []
    }

    public static func buildBlock(_ components: [AnyListCellProvider]...) -> [AnyListCellProvider] {
        components.flatMap { $0 }
    }

    public static func buildArray(_ components: [[AnyListCellProvider]]) -> [AnyListCellProvider] {
        components.flatMap { $0 }
    }

    public static func buildEither(first component: [AnyListCellProvider]) -> [AnyListCellProvider] {
        component
    }

    public static func buildEither(second component: [AnyListCellProvider]) -> [AnyListCellProvider] {
        component
    }

    public static func buildOptional(_ component: [AnyListCellProvider]?) -> [AnyListCellProvider] {
        component ?? []
    }

    public static func buildLimitedAvailability(_ component: [AnyListCellProvider]) -> [AnyListCellProvider] {
        component
    }
}

/// 迁移兼容层：新页面优先使用 `ListSection`。
@available(*, deprecated, message: "Migration-only compatibility. Prefer ListSection.")
public struct ListProviderSection<SectionID>: @unchecked Sendable where SectionID: Hashable & Sendable {
    public var id: SectionID
    public var supplementaries: [AnyListSupplementaryProvider]
    public var cellItems: [AnyListCellProvider]
    private var nativeSupplementaries: [AnySupplementary]

    public var identifier: SectionID { id }

    @MainActor public init(
        sectionIdentifier: SectionID,
        supplementaryItems: [any ListSupplementaryProvider]? = nil,
        cellItems: [any ListCellProvider]
    ) {
        self.id = sectionIdentifier
        self.supplementaries = supplementaryItems?.map { $0.eraseToAnyListSupplementaryProvider() } ?? []
        self.cellItems = cellItems.map { $0.eraseToAnyListCellProvider() }
        self.nativeSupplementaries = []
    }

    @MainActor public init(
        sectionIdentifier: SectionID,
        supplementaryItems: [any ListSupplementaryProvider]? = nil,
        @ListCellProviderBuilder cellItemsBuilder: () -> [AnyListCellProvider]
    ) {
        self.id = sectionIdentifier
        self.supplementaries = supplementaryItems?.map { $0.eraseToAnyListSupplementaryProvider() } ?? []
        self.cellItems = cellItemsBuilder()
        self.nativeSupplementaries = []
    }

    @MainActor public func header<ID, View>(
        _ viewType: View.Type,
        id: ID,
        configure: @escaping @MainActor (View, ListContext) -> Void
    ) -> Self where ID: Hashable & Sendable, View: UICollectionReusableView {
        supplementary(UICollectionView.elementKindSectionHeader, viewType, id: id, configure: configure)
    }

    @MainActor public func footer<ID, View>(
        _ viewType: View.Type,
        id: ID,
        configure: @escaping @MainActor (View, ListContext) -> Void
    ) -> Self where ID: Hashable & Sendable, View: UICollectionReusableView {
        supplementary(UICollectionView.elementKindSectionFooter, viewType, id: id, configure: configure)
    }

    @MainActor public func supplementary<ID, View>(
        _ kind: String,
        _ viewType: View.Type,
        id: ID,
        configure: @escaping @MainActor (View, ListContext) -> Void
    ) -> Self where ID: Hashable & Sendable, View: UICollectionReusableView {
        var copy = self
        let item = Supplementary(kind, id: id, view: viewType, configure: configure)
        copy.nativeSupplementaries.append(item.eraseToAnySupplementary(sectionID: self.id))
        return copy
    }

    @MainActor public func supplementary<ID, View>(_ supplementary: Supplementary<ID, View>) -> Self
        where ID: Hashable & Sendable, View: UICollectionReusableView
    {
        var copy = self
        copy.nativeSupplementaries.append(supplementary.eraseToAnySupplementary(sectionID: self.id))
        return copy
    }

    @MainActor public func supplementary<ID>(_ supplementary: ProviderSupplementary<ID>) -> Self
        where ID: Hashable & Sendable
    {
        var copy = self
        copy.nativeSupplementaries.append(supplementary.eraseToAnySupplementary(sectionID: self.id))
        return copy
    }

    @MainActor func makeListSection() -> ListSection<SectionID> {
        var section = ListSection(id) {
            ForEach(cellItems, id: \.identity) { item in
                item.makeRow()
            }
        }

        for supplementary in supplementaries {
            section = section.supplementary(supplementary.makeSupplementary())
        }
        section.supplementaries.append(contentsOf: nativeSupplementaries)

        return section
    }

    @MainActor public func performSelectionHandler(at indexPath: IndexPath) {
        guard cellItems.indices.contains(indexPath.item) else { return }
        cellItems[indexPath.item].performSelection(at: indexPath)
    }

    @MainActor public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        cellItems[indexPath.item].collectionView(collectionView, cellForItemAt: indexPath)
    }
}

/// 迁移兼容层：新页面优先使用 `ListSectionBuilder`。
@resultBuilder
@available(*, deprecated, message: "Migration-only compatibility. Prefer ListSectionBuilder.")
public enum ListProviderSectionBuilder {
    public static func buildExpression<SectionID>(_ expression: ListProviderSection<SectionID>) -> [ListProviderSection<SectionID>] {
        [expression]
    }

    public static func buildExpression<SectionID>(_ expression: [ListProviderSection<SectionID>]) -> [ListProviderSection<SectionID>] {
        expression
    }

    public static func buildExpression<SectionID>(_ expression: ()) -> [ListProviderSection<SectionID>] {
        []
    }

    public static func buildBlock<SectionID>(_ components: [ListProviderSection<SectionID>]...) -> [ListProviderSection<SectionID>] {
        components.flatMap { $0 }
    }

    public static func buildArray<SectionID>(_ components: [[ListProviderSection<SectionID>]]) -> [ListProviderSection<SectionID>] {
        components.flatMap { $0 }
    }

    public static func buildEither<SectionID>(first component: [ListProviderSection<SectionID>]) -> [ListProviderSection<SectionID>] {
        component
    }

    public static func buildEither<SectionID>(second component: [ListProviderSection<SectionID>]) -> [ListProviderSection<SectionID>] {
        component
    }

    public static func buildOptional<SectionID>(_ component: [ListProviderSection<SectionID>]?) -> [ListProviderSection<SectionID>] {
        component ?? []
    }

    public static func buildLimitedAvailability<SectionID>(_ component: [ListProviderSection<SectionID>]) -> [ListProviderSection<SectionID>] {
        component
    }
}
