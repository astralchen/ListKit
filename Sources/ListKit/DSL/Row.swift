import UIKit

// MARK: - Row Model

/// Row 刷新策略。
public enum RowRefreshPolicy: Equatable, Sendable {
    /// 默认策略。identity 不变时只重配可见 cell。
    case automaticVisible
    /// `refreshID` 变化时触发 diffable reconfigure/reload。
    case whenRefreshIDChanges
    /// identity 不变时不主动刷新。
    case never
    /// 每次 apply 后都重配可见 cell。
    case alwaysVisible
}

/// section 选择模式描述。
public enum ListSelectionMode: Equatable, Sendable {
    /// 不启用选择。
    case none
    /// 单选。
    case single
    /// 多选。
    case multiple
}

/// 类型擦除后的 Row 描述。
///
/// - Note: 页面通常不直接创建它；`Row`、`ProviderRow` 和 `ListStateRow` 会在
/// `ListSection` 构建阶段转成 `AnyListRow`，再交给 `CollectionListAdapter`
/// 做 diff、dequeue、可见刷新和事件回调。
public struct AnyListRow {
    public let identity: AnyListIdentity
    public let refreshID: AnyListID?
    public let refreshPolicy: RowRefreshPolicy
    public let isSelected: Bool?

    let register: @MainActor (UICollectionView) -> Void
    let cellProvider: @MainActor (UICollectionView, IndexPath, ListContext) -> UICollectionViewCell
    let configureVisibleCell: @MainActor (UICollectionViewCell, ListContext) -> Void
    let selectHandler: (@MainActor (ListContext) -> Void)?
    let deselectHandler: (@MainActor (ListContext) -> Void)?
    let selectionChangeHandler: (@MainActor (Bool, ListContext) -> Void)?
    let displayHandler: (@MainActor (UICollectionViewCell, ListContext) -> Void)?
    let endDisplayHandler: (@MainActor (UICollectionViewCell, ListContext) -> Void)?
    let prefetchHandler: (@MainActor (ListContext) -> Void)?
    let cancelPrefetchHandler: (@MainActor (ListContext) -> Void)?
    let contextMenuProvider: (@MainActor (ListContext) -> UIContextMenuConfiguration?)?
    let leadingSwipeActionsProvider: (@MainActor (ListContext) -> UISwipeActionsConfiguration?)?
    let trailingSwipeActionsProvider: (@MainActor (ListContext) -> UISwipeActionsConfiguration?)?
}

/// 可以放入 `ListSection` row builder 的元素协议。
///
/// - Important: 页面代码优先使用 `Row(...)`、`ForEach(...)`、`ListStateRow`；
/// 自定义 conform 通常只用于框架内部扩展或迁移桥接。
public protocol ListRowRepresentable {
    @MainActor func eraseToAnyListRows<SectionID>(sectionID: SectionID) -> [AnyListRow]
        where SectionID: Hashable & Sendable

    @MainActor func eraseToAnyListRows<SectionID>(
        sectionID: SectionID,
        inheritedID: AnyListID?
    ) -> [AnyListRow] where SectionID: Hashable & Sendable
}

public extension ListRowRepresentable {
    /// ForEach 会通过这个入口把当前元素的 id 传给内部 Row。
    ///
    /// 普通 Row 默认忽略 inheritedID；只有 `Row(model:cell:)` 这种“继承身份”的 Row 会读取它。
    @MainActor func eraseToAnyListRows<SectionID>(
        sectionID: SectionID,
        inheritedID: AnyListID?
    ) -> [AnyListRow] where SectionID: Hashable & Sendable {
        eraseToAnyListRows(sectionID: sectionID)
    }
}

private enum RowIDSource<ID> {
    case explicit(ID)
    case inherited
}

/// 业务 model 不强制要求 `Sendable`，事件闭包又统一在 MainActor 回调。
/// 这个盒子只用于消除“把非 Sendable model 捕获到 MainActor 闭包”的误报风险。
private struct MainActorValueBox<Value>: @unchecked Sendable {
    let value: Value
}

/// 声明一个列表中的 cell 节点。
///
/// - Usage:
/// ```swift
/// ForEach(users, id: \.userID) { user in
///     if user.isVIP {
///         Row(model: user, cell: VIPUserCell.self) { cell, user, _ in
///             cell.configure(user)
///         }
///     } else {
///         Row(model: user, cell: NormalUserCell.self) { cell, user, _ in
///             cell.configure(user)
///         }
///     }
/// }
/// ```
/// - Note: `Cell.self` 会参与 identity，同一个业务 id 切换 cell 类型时会触发 delete/insert。
public struct Row<ID, Model, Cell>: ListRowRepresentable where ID: Hashable & Sendable, Cell: UICollectionViewCell {
    private typealias CellEventBinder = @MainActor (Cell, Model, ListContext) -> Void

    private let idSource: RowIDSource<ID>
    private let model: Model
    private let cellType: Cell.Type
    private let configure: @MainActor (Cell, Model, ListContext) -> Void
    private var rowVariant: AnyListID?
    private var rowRefreshID: AnyListID?
    private var rowRefreshPolicy: RowRefreshPolicy = .automaticVisible
    private var rowIsSelected: Bool?
    private var rowSelectHandler: (@MainActor (ListContext) -> Void)?
    private var rowDeselectHandler: (@MainActor (ListContext) -> Void)?
    private var rowSelectionChangeHandler: (@MainActor (Bool, ListContext) -> Void)?
    private var rowDisplayHandler: (@MainActor (Cell, ListContext) -> Void)?
    private var rowEndDisplayHandler: (@MainActor (Cell, ListContext) -> Void)?
    private var rowPrefetchHandler: (@MainActor (ListContext) -> Void)?
    private var rowCancelPrefetchHandler: (@MainActor (ListContext) -> Void)?
    private var rowContextMenuProvider: (@MainActor (ListContext) -> UIContextMenuConfiguration?)?
    private var rowLeadingSwipeActionsProvider: (@MainActor (ListContext) -> UISwipeActionsConfiguration?)?
    private var rowTrailingSwipeActionsProvider: (@MainActor (ListContext) -> UISwipeActionsConfiguration?)?
    private var rowCellEventBinders: [CellEventBinder] = []

    /// 创建带显式 id 的 Row。
    ///
    /// - Parameters:
    ///   - id: 业务 row id。
    ///   - model: 配置 cell 时使用的业务数据。
    ///   - cellType: 要注册和 dequeue 的 cell 类型。
    ///   - configure: 每次创建或重配 cell 时执行的配置闭包。
    public init(
        _ id: ID,
        model: Model,
        cell cellType: Cell.Type,
        configure: @escaping @MainActor (Cell, Model, ListContext) -> Void
    ) {
        self.idSource = .explicit(id)
        self.model = model
        self.cellType = cellType
        self.configure = configure
    }

    /// 使用 key path 从 model 中读取 Row 身份。
    ///
    /// - Parameters:
    ///   - model: 配置 cell 时使用的业务数据。
    ///   - id: 指向业务 row id 的 key path。
    ///   - cellType: 要注册和 dequeue 的 cell 类型。
    ///   - configure: 每次创建或重配 cell 时执行的配置闭包。
    public init(
        model: Model,
        id: KeyPath<Model, ID>,
        cell cellType: Cell.Type,
        configure: @escaping @MainActor (Cell, Model, ListContext) -> Void
    ) {
        self.idSource = .explicit(model[keyPath: id])
        self.model = model
        self.cellType = cellType
        self.configure = configure
    }

    /// 使用闭包从 model 中生成 Row 身份。
    ///
    /// - Parameters:
    ///   - model: 配置 cell 时使用的业务数据。
    ///   - id: 生成业务 row id 的闭包。
    ///   - cellType: 要注册和 dequeue 的 cell 类型。
    ///   - configure: 每次创建或重配 cell 时执行的配置闭包。
    public init(
        model: Model,
        id: (Model) -> ID,
        cell cellType: Cell.Type,
        configure: @escaping @MainActor (Cell, Model, ListContext) -> Void
    ) {
        self.idSource = .explicit(id(model))
        self.model = model
        self.cellType = cellType
        self.configure = configure
    }

    /// 给同一个业务 id 增加展示变体。
    ///
    /// 当同一个 model 可能用同一个 cell 类型展示为不同 UI 节点时使用。`variant`
    /// 会参与 identity，因此变化时 diffable 会执行 delete + insert。
    /// - Parameter variant: 展示变体 id。
    /// - Returns: 应用变体后的 Row。
    public func variant<Variant>(_ variant: Variant) -> Self where Variant: Hashable & Sendable {
        var copy = self
        copy.rowVariant = AnyListID(variant)
        return copy
    }

    /// 描述同一 identity 下的内容版本。
    ///
    /// `refreshID` 不参与 identity，只用于判断是否需要重配当前展示节点。常见写法是
    /// 传入布局版本、状态版本或 model 中真正影响 UI 的字段。
    /// - Parameter refreshID: 当前内容版本 id。
    /// - Returns: 应用内容版本后的 Row。
    public func refreshID<RefreshID>(_ refreshID: RefreshID) -> Self where RefreshID: Hashable & Sendable {
        var copy = self
        copy.rowRefreshID = AnyListID(refreshID)
        return copy
    }

    /// 覆盖当前 Row 的刷新策略。
    ///
    /// - Parameter policy: 当前 Row 的刷新策略。
    /// - Returns: 应用刷新策略后的 Row。
    public func refreshPolicy(_ policy: RowRefreshPolicy) -> Self {
        var copy = self
        copy.rowRefreshPolicy = policy
        return copy
    }

    /// 绑定 UIKit 选中事件。
    ///
    /// - Parameter handler: cell 被选中时在主线程调用的闭包。
    /// - Returns: 绑定事件后的 Row。
    public func onSelect(_ handler: @escaping @MainActor (ListContext) -> Void) -> Self {
        var copy = self
        copy.rowSelectHandler = handler
        return copy
    }

    /// 选择事件的强类型 model 重载，页面不需要再额外捕获 model。
    ///
    /// - Parameter handler: cell 被选中时收到 model 和 context 的闭包。
    /// - Returns: 绑定事件后的 Row。
    public func onSelect(_ handler: @escaping @MainActor (Model, ListContext) -> Void) -> Self {
        let boxedModel = MainActorValueBox(value: model)
        return onSelect { context in
            handler(boxedModel.value, context)
        }
    }

    /// 绑定 UIKit 取消选中事件。
    ///
    /// - Parameter handler: cell 取消选中时在主线程调用的闭包。
    /// - Returns: 绑定事件后的 Row。
    public func onDeselect(_ handler: @escaping @MainActor (ListContext) -> Void) -> Self {
        var copy = self
        copy.rowDeselectHandler = handler
        return copy
    }

    /// 取消选中事件的强类型 model 重载。
    ///
    /// - Parameter handler: cell 取消选中时收到 model 和 context 的闭包。
    /// - Returns: 绑定事件后的 Row。
    public func onDeselect(_ handler: @escaping @MainActor (Model, ListContext) -> Void) -> Self {
        let boxedModel = MainActorValueBox(value: model)
        return onDeselect { context in
            handler(boxedModel.value, context)
        }
    }

    /// 描述当前 Row 是否选中。adapter 会在 cell dequeue 时同步 UIKit 选中态。
    ///
    /// - Parameter isSelected: 当前 Row 是否处于选中状态。
    /// - Returns: 应用选中态后的 Row。
    public func selected(_ isSelected: Bool = true) -> Self {
        var copy = self
        copy.rowIsSelected = isSelected
        return copy
    }

    /// 绑定选中态变化事件。
    ///
    /// - Parameter handler: 选中态变化时收到新状态和 context 的闭包。
    /// - Returns: 绑定事件后的 Row。
    public func onSelectionChange(_ handler: @escaping @MainActor (Bool, ListContext) -> Void) -> Self {
        var copy = self
        copy.rowSelectionChangeHandler = handler
        return copy
    }

    /// 选中态变化事件的强类型 model 重载。
    ///
    /// - Parameter handler: 选中态变化时收到 model、新状态和 context 的闭包。
    /// - Returns: 绑定事件后的 Row。
    public func onSelectionChange(_ handler: @escaping @MainActor (Model, Bool, ListContext) -> Void) -> Self {
        let boxedModel = MainActorValueBox(value: model)
        return onSelectionChange { isSelected, context in
            handler(boxedModel.value, isSelected, context)
        }
    }

    /// 绑定 cell 即将展示事件，常用于曝光统计或启动轻量动画。
    ///
    /// - Parameter handler: cell 即将展示时收到 cell 和 context 的闭包。
    /// - Returns: 绑定事件后的 Row。
    public func onDisplay(_ handler: @escaping @MainActor (Cell, ListContext) -> Void) -> Self {
        var copy = self
        copy.rowDisplayHandler = handler
        return copy
    }

    /// 绑定 cell 结束展示事件，常用于停止动画或取消曝光计时。
    ///
    /// - Parameter handler: cell 结束展示时收到 cell 和 context 的闭包。
    /// - Returns: 绑定事件后的 Row。
    public func onEndDisplay(_ handler: @escaping @MainActor (Cell, ListContext) -> Void) -> Self {
        var copy = self
        copy.rowEndDisplayHandler = handler
        return copy
    }

    /// 绑定 collection view 预取事件。
    ///
    /// - Parameter handler: collection view 预取当前 Row 时调用的闭包。
    /// - Returns: 绑定事件后的 Row。
    public func onPrefetch(_ handler: @escaping @MainActor (ListContext) -> Void) -> Self {
        var copy = self
        copy.rowPrefetchHandler = handler
        return copy
    }

    /// 预取事件的强类型 model 重载。
    ///
    /// - Parameter handler: collection view 预取当前 Row 时收到 model 和 context 的闭包。
    /// - Returns: 绑定事件后的 Row。
    public func onPrefetch(_ handler: @escaping @MainActor (Model, ListContext) -> Void) -> Self {
        let boxedModel = MainActorValueBox(value: model)
        return onPrefetch { context in
            handler(boxedModel.value, context)
        }
    }

    /// 绑定 collection view 取消预取事件。
    ///
    /// - Parameter handler: collection view 取消预取当前 Row 时调用的闭包。
    /// - Returns: 绑定事件后的 Row。
    public func onCancelPrefetch(_ handler: @escaping @MainActor (ListContext) -> Void) -> Self {
        var copy = self
        copy.rowCancelPrefetchHandler = handler
        return copy
    }

    /// 取消预取事件的强类型 model 重载。
    ///
    /// - Parameter handler: collection view 取消预取当前 Row 时收到 model 和 context 的闭包。
    /// - Returns: 绑定事件后的 Row。
    public func onCancelPrefetch(_ handler: @escaping @MainActor (Model, ListContext) -> Void) -> Self {
        let boxedModel = MainActorValueBox(value: model)
        return onCancelPrefetch { context in
            handler(boxedModel.value, context)
        }
    }

    /// 给 cell 内部按钮、手势或菜单绑定自定义事件。
    ///
    /// - Parameters:
    ///   - bind: 把发送闭包安装到 cell 的闭包。
    ///   - makeEvent: 使用当前 model 创建业务事件的闭包。
    /// - Returns: 绑定事件后的 Row。
    public func onCellEvent<Event>(
        _ bind: @escaping @MainActor (Cell, @escaping @MainActor () -> Void) -> Void,
        send makeEvent: @escaping @MainActor (Model) -> Event
    ) -> Self where Event: ListEvent {
        var copy = self
        copy.rowCellEventBinders.append { cell, model, context in
            bind(cell, {
                context.send(makeEvent(model))
            })
        }
        return copy
    }

    /// 提供 iOS context menu 配置。
    ///
    /// - Parameter provider: 返回当前 Row 菜单配置的闭包。
    /// - Returns: 绑定菜单后的 Row。
    public func contextMenu(_ provider: @escaping @MainActor (ListContext) -> UIContextMenuConfiguration?) -> Self {
        var copy = self
        copy.rowContextMenuProvider = provider
        return copy
    }

    /// 提供左侧滑动操作配置。
    ///
    /// - Parameter provider: 返回当前 Row 左滑操作配置的闭包。
    /// - Returns: 绑定滑动操作后的 Row。
    public func leadingSwipeActions(_ provider: @escaping @MainActor (ListContext) -> UISwipeActionsConfiguration?) -> Self {
        var copy = self
        copy.rowLeadingSwipeActionsProvider = provider
        return copy
    }

    /// 提供右侧滑动操作配置。
    ///
    /// - Parameter provider: 返回当前 Row 右滑操作配置的闭包。
    /// - Returns: 绑定滑动操作后的 Row。
    public func trailingSwipeActions(_ provider: @escaping @MainActor (ListContext) -> UISwipeActionsConfiguration?) -> Self {
        var copy = self
        copy.rowTrailingSwipeActionsProvider = provider
        return copy
    }

    @MainActor public func eraseToAnyListRow<SectionID>(
        sectionID: SectionID,
        inheritedID: AnyListID? = nil
    ) -> AnyListRow
        where SectionID: Hashable & Sendable
    {
        let rowID: AnyListID
        switch idSource {
        case .explicit(let id):
            rowID = AnyListID(id)
        case .inherited:
            guard let inheritedID else {
                preconditionFailure("ListKit: Row(model:cell:) 需要放在 ForEach(_:id:) 内使用；单个 Row 请使用 Row(model:id:cell:)、Identifiable model 或 Row(_, model:cell:)。")
            }
            rowID = inheritedID
        }

        let identity = AnyListIdentity(
            sectionID: AnyListID(sectionID),
            rowID: rowID,
            presentationID: ObjectIdentifier(cellType),
            variant: rowVariant
        )
        let displayHandler: (@MainActor (UICollectionViewCell, ListContext) -> Void)?
        if let handler = rowDisplayHandler {
            displayHandler = { cell, context in
                guard let typedCell = cell as? Cell else { return }
                handler(typedCell, context)
            }
        } else {
            displayHandler = nil
        }
        let endDisplayHandler: (@MainActor (UICollectionViewCell, ListContext) -> Void)?
        if let handler = rowEndDisplayHandler {
            endDisplayHandler = { cell, context in
                guard let typedCell = cell as? Cell else { return }
                handler(typedCell, context)
            }
        } else {
            endDisplayHandler = nil
        }

        return AnyListRow(
            identity: identity,
            refreshID: rowRefreshID,
            refreshPolicy: rowRefreshPolicy,
            isSelected: rowIsSelected,
            register: { collectionView in
                collectionView.lk.register(cellType)
            },
            cellProvider: { collectionView, indexPath, context in
                let cell = collectionView.lk.dequeue(cellType, for: indexPath)
                configure(cell, model, context)
                rowCellEventBinders.forEach { $0(cell, model, context) }
                if let rowIsSelected, rowIsSelected {
                    collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
                } else if rowIsSelected == false {
                    collectionView.deselectItem(at: indexPath, animated: false)
                }
                return cell
            },
            configureVisibleCell: { cell, context in
                guard let typedCell = cell as? Cell else { return }
                configure(typedCell, model, context)
                rowCellEventBinders.forEach { $0(typedCell, model, context) }
            },
            selectHandler: rowSelectHandler,
            deselectHandler: rowDeselectHandler,
            selectionChangeHandler: rowSelectionChangeHandler,
            displayHandler: displayHandler,
            endDisplayHandler: endDisplayHandler,
            prefetchHandler: rowPrefetchHandler,
            cancelPrefetchHandler: rowCancelPrefetchHandler,
            contextMenuProvider: rowContextMenuProvider,
            leadingSwipeActionsProvider: rowLeadingSwipeActionsProvider,
            trailingSwipeActionsProvider: rowTrailingSwipeActionsProvider
        )
    }

    @MainActor public func eraseToAnyListRows<SectionID>(sectionID: SectionID) -> [AnyListRow]
        where SectionID: Hashable & Sendable
    {
        [eraseToAnyListRow(sectionID: sectionID)]
    }

    @MainActor public func eraseToAnyListRows<SectionID>(
        sectionID: SectionID,
        inheritedID: AnyListID?
    ) -> [AnyListRow] where SectionID: Hashable & Sendable {
        [eraseToAnyListRow(sectionID: sectionID, inheritedID: inheritedID)]
    }
}

public extension Row where ID == InheritedRowID {
    /// ForEach 内部 Row 的最简写法，身份继承自外层 `ForEach(id:)`。
    ///
    /// - Parameters:
    ///   - model: 配置 cell 时使用的业务数据。
    ///   - cellType: 要注册和 dequeue 的 cell 类型。
    ///   - configure: 每次创建或重配 cell 时执行的配置闭包。
    /// - Important: 此 initializer 需要放在 `ForEach(_:id:)` 内使用。
    @_disfavoredOverload
    init(
        model: Model,
        cell cellType: Cell.Type,
        configure: @escaping @MainActor (Cell, Model, ListContext) -> Void
    ) {
        self.idSource = .inherited
        self.model = model
        self.cellType = cellType
        self.configure = configure
    }
}

public extension Row where Model: Identifiable, ID == Model.ID, Model.ID: Sendable {
    /// 单个 `Identifiable` model 的最简写法，默认使用 `model.id` 作为 Row 身份。
    ///
    /// - Parameters:
    ///   - model: 提供 `id` 且用于配置 cell 的业务数据。
    ///   - cellType: 要注册和 dequeue 的 cell 类型。
    ///   - configure: 每次创建或重配 cell 时执行的配置闭包。
    init(
        model: Model,
        cell cellType: Cell.Type,
        configure: @escaping @MainActor (Cell, Model, ListContext) -> Void
    ) {
        self.idSource = .explicit(model.id)
        self.model = model
        self.cellType = cellType
        self.configure = configure
    }
}

/// ListKit 内置轻量状态 Row 身份。
///
/// 它只描述 UI，不管理网络请求或页面状态机。页面决定什么时候展示 empty/loading/failure。
public enum ListStateRowKind: Hashable, Sendable {
    case empty
    case loading
    case failure
}

/// 状态 Row 工厂。
///
/// - Usage:
/// ```swift
/// ListSection(.users) {
///     if users.isEmpty {
///         ListStateRow.empty(EmptyCell.self) { cell, _ in
///             cell.titleLabel.text = "暂无用户"
///         }
///     }
/// }
/// ```
public enum ListStateRow {
    /// 创建空状态 Row。
    ///
    /// - Parameters:
    ///   - cellType: 空状态 cell 类型。
    ///   - configure: 配置空状态 cell 的闭包。
    /// - Returns: 使用固定 `.empty` 身份的 Row。
    @MainActor public static func empty<Cell>(
        _ cellType: Cell.Type,
        configure: @escaping @MainActor (Cell, ListContext) -> Void
    ) -> Row<ListStateRowKind, Void, Cell> where Cell: UICollectionViewCell {
        Row(.empty, model: (), cell: cellType) { cell, _, context in
            configure(cell, context)
        }
    }

    /// 创建加载中状态 Row。
    ///
    /// - Parameters:
    ///   - cellType: 加载中状态 cell 类型。
    ///   - configure: 配置加载中状态 cell 的闭包。
    /// - Returns: 使用固定 `.loading` 身份的 Row。
    @MainActor public static func loading<Cell>(
        _ cellType: Cell.Type,
        configure: @escaping @MainActor (Cell, ListContext) -> Void
    ) -> Row<ListStateRowKind, Void, Cell> where Cell: UICollectionViewCell {
        Row(.loading, model: (), cell: cellType) { cell, _, context in
            configure(cell, context)
        }
    }

    /// 创建失败状态 Row。
    ///
    /// - Parameters:
    ///   - cellType: 失败状态 cell 类型。
    ///   - configure: 配置失败状态 cell 的闭包。
    /// - Returns: 使用固定 `.failure` 身份的 Row。
    @MainActor public static func failure<Cell>(
        _ cellType: Cell.Type,
        configure: @escaping @MainActor (Cell, ListContext) -> Void
    ) -> Row<ListStateRowKind, Void, Cell> where Cell: UICollectionViewCell {
        Row(.failure, model: (), cell: cellType) { cell, _, context in
            configure(cell, context)
        }
    }
}

/// 多个 Row 的组合容器。
///
/// - Note: 页面通常通过 `ForEach` 或 result builder 自然组合，不需要直接创建 `RowGroup`。
public struct RowGroup: ListRowRepresentable {
    private let rows: [any ListRowRepresentable]

    init(_ rows: [any ListRowRepresentable]) {
        self.rows = rows
    }

    @MainActor public func eraseToAnyListRows<SectionID>(sectionID: SectionID) -> [AnyListRow]
        where SectionID: Hashable & Sendable
    {
        rows.flatMap { $0.eraseToAnyListRows(sectionID: sectionID) }
    }

    @MainActor public func eraseToAnyListRows<SectionID>(
        sectionID: SectionID,
        inheritedID: AnyListID?
    ) -> [AnyListRow] where SectionID: Hashable & Sendable {
        rows.flatMap { $0.eraseToAnyListRows(sectionID: sectionID, inheritedID: inheritedID) }
    }
}

/// Provider-backed Row escape hatch for migration-heavy or mixed-cell sections.
///
/// Normal pages should prefer strongly typed `Row(model:cell:)`. This type exists for cases where
/// an existing page already owns cell dequeue/configuration logic and still needs to participate in
/// ListKit identity, diff, refresh, and event handling.
public struct ProviderRow<ID>: ListRowRepresentable where ID: Hashable & Sendable {
    private let id: ID
    private let presentationID: ObjectIdentifier
    private let registerProvider: @MainActor (UICollectionView) -> Void
    private let cellProvider: @MainActor (UICollectionView, IndexPath, ListContext) -> UICollectionViewCell
    private let visibleCellConfigurator: @MainActor (UICollectionViewCell, ListContext) -> Void
    private var rowVariant: AnyListID?
    private var rowRefreshID: AnyListID?
    private var rowRefreshPolicy: RowRefreshPolicy = .automaticVisible
    private var rowSelectHandler: (@MainActor (ListContext) -> Void)?
    private var rowDisplayHandler: (@MainActor (UICollectionViewCell, ListContext) -> Void)?
    private var rowEndDisplayHandler: (@MainActor (UICollectionViewCell, ListContext) -> Void)?

    /// 用 cell 类型作为展示 identity 的 ProviderRow。
    ///
    /// - Parameters:
    ///   - id: 业务 row id。
    ///   - cellType: 用于 presentation identity 和默认注册的 cell 类型。
    ///   - register: 可选的自定义注册闭包。
    ///   - cellProvider: 创建或 dequeue cell 的闭包。
    ///   - configureVisibleCell: 轻量重配可见 cell 时调用的闭包。
    /// - Important: 这是迁移兼容入口；新页面应优先使用强类型 `Row`。
    public init<Cell>(
        _ id: ID,
        cell cellType: Cell.Type,
        register: (@MainActor (UICollectionView) -> Void)? = nil,
        cellProvider: @escaping @MainActor (UICollectionView, IndexPath, ListContext) -> UICollectionViewCell,
        configureVisibleCell: @escaping @MainActor (UICollectionViewCell, ListContext) -> Void = { _, _ in }
    ) where Cell: UICollectionViewCell {
        self.id = id
        self.presentationID = ObjectIdentifier(cellType)
        self.registerProvider = register ?? { collectionView in
            collectionView.lk.register(cellType)
        }
        self.cellProvider = cellProvider
        self.visibleCellConfigurator = configureVisibleCell
    }

    /// 完全自定义展示 identity 的 ProviderRow。
    ///
    /// - Parameters:
    ///   - id: 业务 row id。
    ///   - presentationID: 自定义展示身份。
    ///   - register: 注册 cell 或相关 reusable view 的闭包。
    ///   - cellProvider: 创建或 dequeue cell 的闭包。
    ///   - configureVisibleCell: 轻量重配可见 cell 时调用的闭包。
    /// - Important: 仅用于无法用具体 cell 类型表达 presentation identity 的迁移场景。
    public init(
        _ id: ID,
        presentationID: ObjectIdentifier,
        register: @escaping @MainActor (UICollectionView) -> Void,
        cellProvider: @escaping @MainActor (UICollectionView, IndexPath, ListContext) -> UICollectionViewCell,
        configureVisibleCell: @escaping @MainActor (UICollectionViewCell, ListContext) -> Void = { _, _ in }
    ) {
        self.id = id
        self.presentationID = presentationID
        self.registerProvider = register
        self.cellProvider = cellProvider
        self.visibleCellConfigurator = configureVisibleCell
    }

    /// 增加展示变体，语义与 `Row.variant(_:)` 一致。
    ///
    /// - Parameter variant: 展示变体 id。
    /// - Returns: 应用变体后的 ProviderRow。
    public func variant<Variant>(_ variant: Variant) -> Self where Variant: Hashable & Sendable {
        var copy = self
        copy.rowVariant = AnyListID(variant)
        return copy
    }

    /// 设置内容刷新版本，语义与 `Row.refreshID(_:)` 一致。
    ///
    /// - Parameter refreshID: 当前内容版本 id。
    /// - Returns: 应用内容版本后的 ProviderRow。
    public func refreshID<RefreshID>(_ refreshID: RefreshID) -> Self where RefreshID: Hashable & Sendable {
        var copy = self
        copy.rowRefreshID = AnyListID(refreshID)
        return copy
    }

    /// 覆盖 ProviderRow 的刷新策略。
    ///
    /// - Parameter policy: 当前 ProviderRow 的刷新策略。
    /// - Returns: 应用刷新策略后的 ProviderRow。
    public func refreshPolicy(_ policy: RowRefreshPolicy) -> Self {
        var copy = self
        copy.rowRefreshPolicy = policy
        return copy
    }

    /// 绑定选中事件。
    ///
    /// - Parameter handler: cell 被选中时在主线程调用的闭包。
    /// - Returns: 绑定事件后的 ProviderRow。
    public func onSelect(_ handler: @escaping @MainActor (ListContext) -> Void) -> Self {
        var copy = self
        copy.rowSelectHandler = handler
        return copy
    }

    /// 绑定展示事件。
    ///
    /// - Parameter handler: cell 即将展示时收到 cell 和 context 的闭包。
    /// - Returns: 绑定事件后的 ProviderRow。
    public func onDisplay(_ handler: @escaping @MainActor (UICollectionViewCell, ListContext) -> Void) -> Self {
        var copy = self
        copy.rowDisplayHandler = handler
        return copy
    }

    /// 绑定结束展示事件。
    ///
    /// - Parameter handler: cell 结束展示时收到 cell 和 context 的闭包。
    /// - Returns: 绑定事件后的 ProviderRow。
    public func onEndDisplay(_ handler: @escaping @MainActor (UICollectionViewCell, ListContext) -> Void) -> Self {
        var copy = self
        copy.rowEndDisplayHandler = handler
        return copy
    }

    @MainActor public func eraseToAnyListRows<SectionID>(sectionID: SectionID) -> [AnyListRow]
        where SectionID: Hashable & Sendable
    {
        let identity = AnyListIdentity(
            sectionID: AnyListID(sectionID),
            rowID: AnyListID(id),
            presentationID: presentationID,
            variant: rowVariant
        )

        return [
            AnyListRow(
                identity: identity,
                refreshID: rowRefreshID,
                refreshPolicy: rowRefreshPolicy,
                isSelected: nil,
                register: registerProvider,
                cellProvider: cellProvider,
                configureVisibleCell: visibleCellConfigurator,
                selectHandler: rowSelectHandler,
                deselectHandler: nil,
                selectionChangeHandler: nil,
                displayHandler: rowDisplayHandler,
                endDisplayHandler: rowEndDisplayHandler,
                prefetchHandler: nil,
                cancelPrefetchHandler: nil,
                contextMenuProvider: nil,
                leadingSwipeActionsProvider: nil,
                trailingSwipeActionsProvider: nil
            )
        ]
    }
}
