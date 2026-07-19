import UIKit

// MARK: - Table DSL

/// UITableView row/header/footer 高度描述。
public enum TableRowHeight: Equatable, Sendable {
    /// 固定高度。
    case fixed(CGFloat)
    /// 自动高度，可附带估算高度。
    case automatic(estimated: CGFloat? = nil)
    /// 自动高度，并使用指定估算高度。
    case estimated(CGFloat)

    @MainActor var resolvedHeight: CGFloat {
        switch self {
        case .fixed(let height):
            return height
        case .automatic, .estimated:
            return UITableView.automaticDimension
        }
    }

    @MainActor var resolvedEstimatedHeight: CGFloat {
        switch self {
        case .fixed(let height):
            return height
        case .automatic(let estimated):
            return estimated ?? UITableView.automaticDimension
        case .estimated(let height):
            return height
        }
    }
}

extension TableRowHeight {
    var isFixed: Bool {
        if case .fixed = self { return true }
        return false
    }
}

/// Table row 在 `TableForEach(id:)` 内使用时的占位 ID 类型。
public struct InheritedTableRowID: Hashable, Sendable {
    private init() {}
}

/// UITableView row/header/footer 配置和事件闭包收到的上下文。
@MainActor
public struct TableListContext {
    /// 当前 row/header/footer 的稳定展示身份。
    public let identity: AnyListIdentity
    public var sectionID: AnyListID { identity.sectionID }
    public var itemID: AnyListID { identity.rowID }
    /// 事件发生时的位置；跨刷新逻辑应优先使用 `identity`。
    public let indexPath: IndexPath
    private let tableViewReference: TableListViewReference

    public var tableView: UITableView {
        guard let tableView = tableViewReference.tableView else {
            preconditionFailure("ListKit: TableListContext tableView was released")
        }
        return tableView
    }

    public var tableViewIfAvailable: UITableView? {
        tableViewReference.tableView
    }

    private let eventDispatcher: @MainActor (any ListEvent, TableListContext) -> Void

    init(
        identity: AnyListIdentity,
        indexPath: IndexPath,
        tableView: UITableView,
        eventDispatcher: @escaping @MainActor (any ListEvent, TableListContext) -> Void
    ) {
        self.identity = identity
        self.indexPath = indexPath
        self.tableViewReference = TableListViewReference(tableView)
        self.eventDispatcher = eventDispatcher
    }

    @available(*, deprecated, message: "Pass a stable AnyListIdentity instead of a positional sectionID.")
    init(
        sectionID: AnyListID,
        indexPath: IndexPath,
        tableView: UITableView,
        eventDispatcher: @escaping @MainActor (any ListEvent, TableListContext) -> Void
    ) {
        self.init(
            identity: AnyListIdentity(
                sectionID: sectionID,
                rowID: AnyListID(indexPath.row),
                presentationID: ObjectIdentifier(LegacyTableListContextPresentation.self)
            ),
            indexPath: indexPath,
            tableView: tableView,
            eventDispatcher: eventDispatcher
        )
    }

    /// 向 table adapter 发送业务事件。
    ///
    /// - Parameter event: 遵守 `ListEvent` 的业务事件。
    @MainActor public func send<Event>(_ event: Event) where Event: ListEvent {
        eventDispatcher(event, self)
    }

    /// 取回强类型 sectionID。
    ///
    /// - Parameter type: 要恢复的 section id 类型。
    /// - Returns: 类型匹配时返回原始 section id，否则返回 `nil`。
    public func section<ID>(as type: ID.Type = ID.self) -> ID? where ID: Hashable & Sendable {
        sectionID.typed(type)
    }

    public func item<ID>(as type: ID.Type = ID.self) -> ID? where ID: Hashable & Sendable {
        itemID.typed(type)
    }

    public func row<ID>(as type: ID.Type = ID.self) -> ID? where ID: Hashable & Sendable {
        item(as: type)
    }
}

@MainActor
private final class TableListViewReference {
    weak var tableView: UITableView?

    init(_ tableView: UITableView) {
        self.tableView = tableView
    }
}

private final class LegacyTableListContextPresentation {}

/// 类型擦除后的 table row 描述。
public struct AnyTableRow {
    public let identity: AnyListIdentity
    public let refreshID: AnyListID?
    public let refreshPolicy: RowRefreshPolicy
    public let isSelected: Bool?
    public let isSelectionDisabled: Bool
    public let isFocusable: Bool?
    public let selectionFollowsFocus: Bool?
    public let isSpringLoadingEnabled: Bool?
    public let height: TableRowHeight?
    public let estimatedHeight: CGFloat?
    public let indentationLevel: Int?
    public let shouldIndentWhileEditing: Bool?
    public let contentTransition: ListContentTransition

    let register: @MainActor (UITableView) -> Void
    let cellProvider: @MainActor (UITableView, IndexPath, TableListContext) -> UITableViewCell
    let configureVisibleCell: @MainActor (UITableViewCell, TableListContext) -> Void
    let selectHandler: (@MainActor (TableListContext) -> Void)?
    let deselectHandler: (@MainActor (TableListContext) -> Void)?
    let selectionChangeHandler: (@MainActor (Bool, TableListContext) -> Void)?
    let highlightChangeHandler: (@MainActor (Bool, TableListContext) -> Void)?
    let primaryActionHandler: (@MainActor (TableListContext) -> Void)?
    let accessoryButtonHandler: (@MainActor (TableListContext) -> Void)?
    let displayHandler: (@MainActor (UITableViewCell, TableListContext) -> Void)?
    let endDisplayHandler: (@MainActor (UITableViewCell, TableListContext) -> Void)?
    let prefetchHandler: (@MainActor (TableListContext) -> Void)?
    let cancelPrefetchHandler: (@MainActor (TableListContext) -> Void)?
    let contextMenuProvider: (@MainActor (TableListContext) -> UIContextMenuConfiguration?)?
    let contextMenuHighlightPreviewProvider: (@MainActor (TableListContext) -> UITargetedPreview?)?
    let contextMenuDismissalPreviewProvider: (@MainActor (TableListContext) -> UITargetedPreview?)?
    let contextMenuCommitHandler: (@MainActor (TableListContext, any UIContextMenuInteractionCommitAnimating) -> Void)?
    let editingStyle: UITableViewCell.EditingStyle?
    let commitEditingHandler: (@MainActor (UITableViewCell.EditingStyle, TableListContext) -> Void)?
    let editingChangeHandler: (@MainActor (Bool, TableListContext) -> Void)?
    let moveHandler: (@MainActor (IndexPath, IndexPath) -> Void)?
    let moveTargetProvider: (@MainActor (IndexPath, IndexPath) -> IndexPath)?
    let leadingSwipeActionsProvider: (@MainActor (TableListContext) -> UISwipeActionsConfiguration?)?
    let trailingSwipeActionsProvider: (@MainActor (TableListContext) -> UISwipeActionsConfiguration?)?
}

/// 可以放入 `TableSection` row builder 的元素协议。
public protocol TableRowRepresentable {
    @MainActor func eraseToAnyTableRows<SectionID>(sectionID: SectionID) -> [AnyTableRow]
        where SectionID: Hashable & Sendable

    @MainActor func eraseToAnyTableRows<SectionID>(
        sectionID: SectionID,
        inheritedID: AnyListID?
    ) -> [AnyTableRow] where SectionID: Hashable & Sendable
}

public extension TableRowRepresentable {
    @MainActor func eraseToAnyTableRows<SectionID>(
        sectionID: SectionID,
        inheritedID: AnyListID?
    ) -> [AnyTableRow] where SectionID: Hashable & Sendable {
        eraseToAnyTableRows(sectionID: sectionID)
    }
}

private enum TableRowIDSource<ID> {
    case explicit(ID)
    case inherited
}

private struct TableMainActorValueBox<Value>: @unchecked Sendable {
    let value: Value
}

/// 声明一个 table view cell 节点。
///
/// `TableRow` 的 identity 由 section id、row id、cell 类型和可选 variant 共同组成；
/// `refreshID` 只表示内容版本，不参与插入删除判断。
///
/// ```swift
/// TableRow(model: message, cell: MessageCell.self) { cell, message, context in
///     cell.configure(message)
///     context.send(MessageEvent.open(message.id))
/// }
/// .refreshID(message.version)
/// .onSelect { message, _ in
///     open(message)
/// }
/// ```
public struct TableRow<ID, Model, Cell>: TableRowRepresentable where ID: Hashable & Sendable, Cell: UITableViewCell {
    private typealias CellEventBinder = @MainActor (Cell, Model, TableListContext) -> Void

    private let idSource: TableRowIDSource<ID>
    private let model: Model
    private let cellType: Cell.Type
    private let configure: @MainActor (Cell, Model, TableListContext) -> Void
    private var rowVariant: AnyListID?
    private var rowRefreshID: AnyListID?
    private var rowRefreshPolicy: RowRefreshPolicy = .automaticVisible
    private var rowContentTransition: ListContentTransition = .identity
    private var rowIsSelected: Bool?
    private var rowIsSelectionDisabled = false
    private var rowIsFocusable: Bool?
    private var rowSelectionFollowsFocus: Bool?
    private var rowIsSpringLoadingEnabled: Bool?
    private var rowHeight: TableRowHeight?
    private var rowEstimatedHeight: CGFloat?
    private var rowIndentationLevel: Int?
    private var rowShouldIndentWhileEditing: Bool?
    private var rowSelectHandler: (@MainActor (TableListContext) -> Void)?
    private var rowDeselectHandler: (@MainActor (TableListContext) -> Void)?
    private var rowSelectionChangeHandler: (@MainActor (Bool, TableListContext) -> Void)?
    private var rowHighlightChangeHandler: (@MainActor (Bool, TableListContext) -> Void)?
    private var rowPrimaryActionHandler: (@MainActor (TableListContext) -> Void)?
    private var rowAccessoryButtonHandler: (@MainActor (TableListContext) -> Void)?
    private var rowDisplayHandler: (@MainActor (Cell, TableListContext) -> Void)?
    private var rowEndDisplayHandler: (@MainActor (Cell, TableListContext) -> Void)?
    private var rowPrefetchHandler: (@MainActor (TableListContext) -> Void)?
    private var rowCancelPrefetchHandler: (@MainActor (TableListContext) -> Void)?
    private var rowContextMenuProvider: (@MainActor (TableListContext) -> UIContextMenuConfiguration?)?
    private var rowContextMenuHighlightPreviewProvider: (@MainActor (TableListContext) -> UITargetedPreview?)?
    private var rowContextMenuDismissalPreviewProvider: (@MainActor (TableListContext) -> UITargetedPreview?)?
    private var rowContextMenuCommitHandler: (@MainActor (TableListContext, any UIContextMenuInteractionCommitAnimating) -> Void)?
    private var rowEditingStyle: UITableViewCell.EditingStyle?
    private var rowCommitEditingHandler: (@MainActor (UITableViewCell.EditingStyle, TableListContext) -> Void)?
    private var rowEditingChangeHandler: (@MainActor (Bool, TableListContext) -> Void)?
    private var rowMoveHandler: (@MainActor (IndexPath, IndexPath) -> Void)?
    private var rowMoveTargetProvider: (@MainActor (IndexPath, IndexPath) -> IndexPath)?
    private var rowLeadingSwipeActionsProvider: (@MainActor (TableListContext) -> UISwipeActionsConfiguration?)?
    private var rowTrailingSwipeActionsProvider: (@MainActor (TableListContext) -> UISwipeActionsConfiguration?)?
    private var rowCellEventBinders: [CellEventBinder] = []

    /// 创建带显式 id 的 row。
    ///
    /// - Parameters:
    ///   - id: row 的稳定业务身份。
    ///   - model: 配置 cell 使用的数据。
    ///   - cellType: cell 类型。
    ///   - configure: cell 配置闭包。
    public init(
        _ id: ID,
        model: Model,
        cell cellType: Cell.Type,
        configure: @escaping @MainActor (Cell, Model, TableListContext) -> Void
    ) {
        self.idSource = .explicit(id)
        self.model = model
        self.cellType = cellType
        self.configure = configure
    }

    /// 使用 key path 从 model 中读取 row 身份。
    ///
    /// - Parameters:
    ///   - model: 配置 cell 使用的数据。
    ///   - id: 从 model 读取稳定身份的 key path。
    ///   - cellType: cell 类型。
    ///   - configure: cell 配置闭包。
    public init(
        model: Model,
        id: KeyPath<Model, ID>,
        cell cellType: Cell.Type,
        configure: @escaping @MainActor (Cell, Model, TableListContext) -> Void
    ) {
        self.idSource = .explicit(model[keyPath: id])
        self.model = model
        self.cellType = cellType
        self.configure = configure
    }

    /// 使用闭包从 model 中生成 row 身份。
    ///
    /// - Parameters:
    ///   - model: 配置 cell 使用的数据。
    ///   - id: 从 model 生成稳定身份的闭包。
    ///   - cellType: cell 类型。
    ///   - configure: cell 配置闭包。
    public init(
        model: Model,
        id: (Model) -> ID,
        cell cellType: Cell.Type,
        configure: @escaping @MainActor (Cell, Model, TableListContext) -> Void
    ) {
        self.idSource = .explicit(id(model))
        self.model = model
        self.cellType = cellType
        self.configure = configure
    }

    /// 设置同一业务 row 的展示变体。
    ///
    /// - Parameter variant: 参与 identity 的展示变体。
    public func variant<Variant>(_ variant: Variant) -> Self where Variant: Hashable & Sendable {
        var copy = self
        copy.rowVariant = AnyListID(variant)
        return copy
    }

    /// 设置 row 的内容刷新版本。
    ///
    /// - Parameter refreshID: 内容版本标识，不参与插入删除 identity。
    public func refreshID<RefreshID>(_ refreshID: RefreshID) -> Self where RefreshID: Hashable & Sendable {
        var copy = self
        copy.rowRefreshID = AnyListID(refreshID)
        return copy
    }

    /// 设置 `refreshID` 变化时的刷新策略。
    ///
    /// - Parameter policy: row 的刷新策略。
    public func refreshPolicy(_ policy: RowRefreshPolicy) -> Self {
        var copy = self
        copy.rowRefreshPolicy = policy
        return copy
    }

    /// 设置相同 identity 的可见内容刷新过渡。
    public func contentTransition(_ transition: ListContentTransition) -> Self {
        var copy = self
        copy.rowContentTransition = transition
        return copy
    }

    /// 设置 row 高度。
    ///
    /// - Parameter height: 固定高度、自动高度或估算高度描述。
    public func height(_ height: TableRowHeight) -> Self {
        var copy = self
        copy.rowHeight = height
        return copy
    }

    /// 设置 row 的估算高度。
    ///
    /// - Parameter height: 估算高度。
    public func estimatedHeight(_ height: CGFloat) -> Self {
        var copy = self
        copy.rowEstimatedHeight = height
        return copy
    }

    /// 设置 UIKit table row 的缩进级别。
    public func indentationLevel(_ level: Int) -> Self {
        var copy = self
        copy.rowIndentationLevel = level
        return copy
    }

    /// 控制编辑状态下当前 row 是否缩进。
    public func indentWhileEditing(_ enabled: Bool = true) -> Self {
        var copy = self
        copy.rowShouldIndentWhileEditing = enabled
        return copy
    }

    /// 设置 row 的初始选中状态。
    ///
    /// - Parameter isSelected: 是否选中。
    public func selected(_ isSelected: Bool = true) -> Self {
        var copy = self
        copy.rowIsSelected = isSelected
        return copy
    }

    /// 禁止当前 Row 被选择，同时保留 section 级选择策略。
    public func selectionDisabled(_ disabled: Bool = true) -> Self {
        var copy = self
        copy.rowIsSelectionDisabled = disabled
        return copy
    }

    /// 控制焦点系统是否可以聚焦当前 Row。
    public func focusable(_ isFocusable: Bool = true) -> Self {
        var copy = self
        copy.rowIsFocusable = isFocusable
        return copy
    }

    /// 控制焦点移动时是否同步选择状态。
    public func selectionFollowsFocus(_ enabled: Bool = true) -> Self {
        var copy = self
        copy.rowSelectionFollowsFocus = enabled
        return copy
    }

    /// 控制当前 Row 是否响应 spring loading。
    public func springLoadingEnabled(_ enabled: Bool = true) -> Self {
        var copy = self
        copy.rowIsSpringLoadingEnabled = enabled
        return copy
    }

    /// 监听 row 被选中。
    ///
    /// - Parameter handler: 选中回调。
    public func onSelect(_ handler: @escaping @MainActor (TableListContext) -> Void) -> Self {
        var copy = self
        copy.rowSelectHandler = handler
        return copy
    }

    /// 监听 row 被选中，并传入当前 model。
    ///
    /// - Parameter handler: 选中回调。
    public func onSelect(_ handler: @escaping @MainActor (Model, TableListContext) -> Void) -> Self {
        let boxedModel = TableMainActorValueBox(value: model)
        return onSelect { context in
            handler(boxedModel.value, context)
        }
    }

    /// 监听 row 取消选中。
    ///
    /// - Parameter handler: 取消选中回调。
    public func onDeselect(_ handler: @escaping @MainActor (TableListContext) -> Void) -> Self {
        var copy = self
        copy.rowDeselectHandler = handler
        return copy
    }

    /// 监听 row 取消选中，并传入当前 model。
    ///
    /// - Parameter handler: 取消选中回调。
    public func onDeselect(_ handler: @escaping @MainActor (Model, TableListContext) -> Void) -> Self {
        let boxedModel = TableMainActorValueBox(value: model)
        return onDeselect { context in
            handler(boxedModel.value, context)
        }
    }

    /// 监听 row 选中状态变化。
    ///
    /// - Parameter handler: 选中状态变化回调。
    public func onSelectionChange(_ handler: @escaping @MainActor (Bool, TableListContext) -> Void) -> Self {
        var copy = self
        copy.rowSelectionChangeHandler = handler
        return copy
    }

    /// 监听 row 选中状态变化，并传入当前 model。
    ///
    /// - Parameter handler: 选中状态变化回调。
    public func onSelectionChange(_ handler: @escaping @MainActor (Model, Bool, TableListContext) -> Void) -> Self {
        let boxedModel = TableMainActorValueBox(value: model)
        return onSelectionChange { isSelected, context in
            handler(boxedModel.value, isSelected, context)
        }
    }

    /// 监听高亮状态变化。
    public func onHighlightChange(_ handler: @escaping @MainActor (Bool, TableListContext) -> Void) -> Self {
        var copy = self
        copy.rowHighlightChangeHandler = handler
        return copy
    }

    /// 监听高亮状态变化，并传入当前 model。
    public func onHighlightChange(_ handler: @escaping @MainActor (Model, Bool, TableListContext) -> Void) -> Self {
        let boxedModel = TableMainActorValueBox(value: model)
        return onHighlightChange { highlighted, context in
            handler(boxedModel.value, highlighted, context)
        }
    }

    /// 监听键盘回车、遥控器等触发的主操作。
    public func onPrimaryAction(_ handler: @escaping @MainActor (TableListContext) -> Void) -> Self {
        var copy = self
        copy.rowPrimaryActionHandler = handler
        return copy
    }

    /// 监听主操作，并传入当前 model。
    public func onPrimaryAction(_ handler: @escaping @MainActor (Model, TableListContext) -> Void) -> Self {
        let boxedModel = TableMainActorValueBox(value: model)
        return onPrimaryAction { context in
            handler(boxedModel.value, context)
        }
    }

    /// 监听 cell accessory button 点击。
    public func onAccessoryButtonTap(_ handler: @escaping @MainActor (TableListContext) -> Void) -> Self {
        var copy = self
        copy.rowAccessoryButtonHandler = handler
        return copy
    }

    /// 监听 accessory button 点击，并传入当前 model。
    public func onAccessoryButtonTap(_ handler: @escaping @MainActor (Model, TableListContext) -> Void) -> Self {
        let boxedModel = TableMainActorValueBox(value: model)
        return onAccessoryButtonTap { context in
            handler(boxedModel.value, context)
        }
    }

    /// 监听 cell 即将展示。
    ///
    /// - Parameter handler: 展示回调。
    public func onDisplay(_ handler: @escaping @MainActor (Cell, TableListContext) -> Void) -> Self {
        var copy = self
        copy.rowDisplayHandler = handler
        return copy
    }

    /// 监听 cell 即将展示，并传入当前 model。
    ///
    /// - Parameter handler: 展示回调。
    public func onDisplay(_ handler: @escaping @MainActor (Model, Cell, TableListContext) -> Void) -> Self {
        let boxedModel = TableMainActorValueBox(value: model)
        return onDisplay { cell, context in
            handler(boxedModel.value, cell, context)
        }
    }

    /// 监听 cell 结束展示。
    ///
    /// - Parameter handler: 结束展示回调。
    public func onEndDisplay(_ handler: @escaping @MainActor (Cell, TableListContext) -> Void) -> Self {
        var copy = self
        copy.rowEndDisplayHandler = handler
        return copy
    }

    /// 监听 cell 结束展示，并传入当前 model。
    ///
    /// - Parameter handler: 结束展示回调。
    public func onEndDisplay(_ handler: @escaping @MainActor (Model, Cell, TableListContext) -> Void) -> Self {
        let boxedModel = TableMainActorValueBox(value: model)
        return onEndDisplay { cell, context in
            handler(boxedModel.value, cell, context)
        }
    }

    /// 监听 row 预取。
    ///
    /// - Parameter handler: 预取回调。
    public func onPrefetch(_ handler: @escaping @MainActor (TableListContext) -> Void) -> Self {
        var copy = self
        copy.rowPrefetchHandler = handler
        return copy
    }

    /// 监听 row 预取，并传入当前 model。
    ///
    /// - Parameter handler: 预取回调。
    public func onPrefetch(_ handler: @escaping @MainActor (Model, TableListContext) -> Void) -> Self {
        let boxedModel = TableMainActorValueBox(value: model)
        return onPrefetch { context in
            handler(boxedModel.value, context)
        }
    }

    /// 监听 row 取消预取。
    ///
    /// - Parameter handler: 取消预取回调。
    public func onCancelPrefetch(_ handler: @escaping @MainActor (TableListContext) -> Void) -> Self {
        var copy = self
        copy.rowCancelPrefetchHandler = handler
        return copy
    }

    /// 监听 row 取消预取，并传入当前 model。
    ///
    /// - Parameter handler: 取消预取回调。
    public func onCancelPrefetch(_ handler: @escaping @MainActor (Model, TableListContext) -> Void) -> Self {
        let boxedModel = TableMainActorValueBox(value: model)
        return onCancelPrefetch { context in
            handler(boxedModel.value, context)
        }
    }

    /// 把 cell 内部动作绑定为 adapter 事件。
    ///
    /// - Parameters:
    ///   - bind: 在 cell 上安装事件触发闭包。
    ///   - makeEvent: 根据当前 model 生成业务事件。
    public func onCellEvent<Event>(
        _ bind: @escaping @MainActor (Cell, @escaping @MainActor () -> Void) -> Void,
        send makeEvent: @escaping @MainActor (Model) -> Event
    ) -> Self where Event: ListEvent {
        var copy = self
        copy.rowCellEventBinders.append { cell, model, context in
            bind(cell) {
                context.send(makeEvent(model))
            }
        }
        return copy
    }

    /// 设置 row 的 context menu。
    ///
    /// - Parameter provider: 菜单配置提供者。
    public func contextMenu(_ provider: @escaping @MainActor (TableListContext) -> UIContextMenuConfiguration?) -> Self {
        var copy = self
        copy.rowContextMenuProvider = provider
        return copy
    }

    /// 自定义 context menu 的高亮和消失预览。
    public func contextMenuPreview(
        highlighting: (@MainActor (TableListContext) -> UITargetedPreview?)? = nil,
        dismissal: (@MainActor (TableListContext) -> UITargetedPreview?)? = nil
    ) -> Self {
        var copy = self
        copy.rowContextMenuHighlightPreviewProvider = highlighting
        copy.rowContextMenuDismissalPreviewProvider = dismissal
        return copy
    }

    /// 监听 context menu preview commit。
    public func onContextMenuCommit(
        _ handler: @escaping @MainActor (TableListContext, any UIContextMenuInteractionCommitAnimating) -> Void
    ) -> Self {
        var copy = self
        copy.rowContextMenuCommitHandler = handler
        return copy
    }

    /// 设置 row 的 UIKit 编辑动作。
    ///
    /// - Parameters:
    ///   - style: 编辑样式。
    ///   - handler: 提交编辑时执行的回调。
    public func editing(
        _ style: UITableViewCell.EditingStyle,
        handler: @escaping @MainActor (Model, UITableViewCell.EditingStyle, TableListContext) -> Void
    ) -> Self {
        let boxedModel = TableMainActorValueBox(value: model)
        var copy = self
        copy.rowEditingStyle = style
        copy.rowCommitEditingHandler = { style, context in
            handler(boxedModel.value, style, context)
        }
        return copy
    }

    /// 监听当前 row 进入或退出编辑状态。
    public func onEditingChange(_ handler: @escaping @MainActor (Bool, TableListContext) -> Void) -> Self {
        var copy = self
        copy.rowEditingChangeHandler = handler
        return copy
    }

    /// 监听编辑状态变化，并传入当前 model。
    public func onEditingChange(
        _ handler: @escaping @MainActor (Model, Bool, TableListContext) -> Void
    ) -> Self {
        let boxedModel = TableMainActorValueBox(value: model)
        return onEditingChange { isEditing, context in
            handler(boxedModel.value, isEditing, context)
        }
    }

    /// 监听 row 移动。
    ///
    /// - Parameter handler: 移动回调，参数为当前 model、源位置和目标位置。
    public func onMove(_ handler: @escaping @MainActor (IndexPath, IndexPath) -> Void) -> Self {
        var copy = self
        copy.rowMoveHandler = handler
        return copy
    }

    /// 监听 row 移动，并传入当前 model。
    public func onMove(_ handler: @escaping @MainActor (Model, IndexPath, IndexPath) -> Void) -> Self {
        let boxedModel = TableMainActorValueBox(value: model)
        var copy = self
        copy.rowMoveHandler = { source, destination in
            handler(boxedModel.value, source, destination)
        }
        return copy
    }

    /// 调整交互式移动的建议目标位置。
    public func moveTarget(_ provider: @escaping @MainActor (IndexPath, IndexPath) -> IndexPath) -> Self {
        var copy = self
        copy.rowMoveTargetProvider = provider
        return copy
    }

    /// 设置 row 左侧滑动动作。
    ///
    /// - Parameter provider: UIKit swipe actions 配置提供者。
    public func leadingSwipeActions(_ provider: @escaping @MainActor (TableListContext) -> UISwipeActionsConfiguration?) -> Self {
        var copy = self
        copy.rowLeadingSwipeActionsProvider = provider
        return copy
    }

    /// 设置 row 右侧滑动动作。
    ///
    /// - Parameter provider: UIKit swipe actions 配置提供者。
    public func trailingSwipeActions(_ provider: @escaping @MainActor (TableListContext) -> UISwipeActionsConfiguration?) -> Self {
        var copy = self
        copy.rowTrailingSwipeActionsProvider = provider
        return copy
    }

    @MainActor public func eraseToAnyTableRow<SectionID>(
        sectionID: SectionID,
        inheritedID: AnyListID? = nil
    ) -> AnyTableRow where SectionID: Hashable & Sendable {
        let rowID: AnyListID
        switch idSource {
        case .explicit(let id):
            rowID = AnyListID(id)
        case .inherited:
            guard let inheritedID else {
                preconditionFailure("ListKit: TableRow(model:cell:) 需要放在 TableForEach(_:id:) 内使用；单个 TableRow 请使用 TableRow(model:id:cell:)、Identifiable model 或 TableRow(_, model:cell:)。")
            }
            rowID = inheritedID
        }

        let identity = AnyListIdentity(
            sectionID: AnyListID(sectionID),
            rowID: rowID,
            presentationID: ObjectIdentifier(cellType),
            variant: rowVariant
        )
        let displayHandler = rowDisplayHandler.map { handler -> @MainActor (UITableViewCell, TableListContext) -> Void in
            { cell, context in
                guard let typedCell = cell as? Cell else { return }
                handler(typedCell, context)
            }
        }
        let endDisplayHandler = rowEndDisplayHandler.map { handler -> @MainActor (UITableViewCell, TableListContext) -> Void in
            { cell, context in
                guard let typedCell = cell as? Cell else { return }
                handler(typedCell, context)
            }
        }

        return AnyTableRow(
            identity: identity,
            refreshID: rowRefreshID,
            refreshPolicy: rowRefreshPolicy,
            isSelected: rowIsSelected,
            isSelectionDisabled: rowIsSelectionDisabled,
            isFocusable: rowIsFocusable,
            selectionFollowsFocus: rowSelectionFollowsFocus,
            isSpringLoadingEnabled: rowIsSpringLoadingEnabled,
            height: rowHeight,
            estimatedHeight: rowEstimatedHeight,
            indentationLevel: rowIndentationLevel,
            shouldIndentWhileEditing: rowShouldIndentWhileEditing,
            contentTransition: rowContentTransition,
            register: { tableView in
                tableView.lk.register(cellType)
            },
            cellProvider: { tableView, indexPath, context in
                let cell = tableView.lk.dequeue(cellType, for: indexPath)
                configure(cell, model, context)
                if let rowIndentationLevel { cell.indentationLevel = rowIndentationLevel }
                if let rowShouldIndentWhileEditing { cell.shouldIndentWhileEditing = rowShouldIndentWhileEditing }
                rowCellEventBinders.forEach { $0(cell, model, context) }
                if let rowIsSelected, rowIsSelected {
                    tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
                } else if rowIsSelected == false {
                    tableView.deselectRow(at: indexPath, animated: false)
                }
                return cell
            },
            configureVisibleCell: { cell, context in
                guard let typedCell = cell as? Cell else { return }
                configure(typedCell, model, context)
                if let rowIndentationLevel { typedCell.indentationLevel = rowIndentationLevel }
                if let rowShouldIndentWhileEditing { typedCell.shouldIndentWhileEditing = rowShouldIndentWhileEditing }
                rowCellEventBinders.forEach { $0(typedCell, model, context) }
            },
            selectHandler: rowSelectHandler,
            deselectHandler: rowDeselectHandler,
            selectionChangeHandler: rowSelectionChangeHandler,
            highlightChangeHandler: rowHighlightChangeHandler,
            primaryActionHandler: rowPrimaryActionHandler,
            accessoryButtonHandler: rowAccessoryButtonHandler,
            displayHandler: displayHandler,
            endDisplayHandler: endDisplayHandler,
            prefetchHandler: rowPrefetchHandler,
            cancelPrefetchHandler: rowCancelPrefetchHandler,
            contextMenuProvider: rowContextMenuProvider,
            contextMenuHighlightPreviewProvider: rowContextMenuHighlightPreviewProvider,
            contextMenuDismissalPreviewProvider: rowContextMenuDismissalPreviewProvider,
            contextMenuCommitHandler: rowContextMenuCommitHandler,
            editingStyle: rowEditingStyle,
            commitEditingHandler: rowCommitEditingHandler,
            editingChangeHandler: rowEditingChangeHandler,
            moveHandler: rowMoveHandler,
            moveTargetProvider: rowMoveTargetProvider,
            leadingSwipeActionsProvider: rowLeadingSwipeActionsProvider,
            trailingSwipeActionsProvider: rowTrailingSwipeActionsProvider
        )
    }

    @MainActor public func eraseToAnyTableRows<SectionID>(sectionID: SectionID) -> [AnyTableRow]
        where SectionID: Hashable & Sendable
    {
        [eraseToAnyTableRow(sectionID: sectionID)]
    }

    @MainActor public func eraseToAnyTableRows<SectionID>(
        sectionID: SectionID,
        inheritedID: AnyListID?
    ) -> [AnyTableRow] where SectionID: Hashable & Sendable {
        [eraseToAnyTableRow(sectionID: sectionID, inheritedID: inheritedID)]
    }
}

public extension TableRow where ID == InheritedTableRowID {
    /// 创建继承外层 `TableForEach` 身份的 row。
    ///
    /// - Important: 该初始化器只能在 `TableForEach(_:id:)` 内使用。
    /// - Parameters:
    ///   - model: 配置 cell 使用的数据。
    ///   - cellType: cell 类型。
    ///   - configure: cell 配置闭包。
    @_disfavoredOverload
    init(
        model: Model,
        cell cellType: Cell.Type,
        configure: @escaping @MainActor (Cell, Model, TableListContext) -> Void
    ) {
        self.idSource = .inherited
        self.model = model
        self.cellType = cellType
        self.configure = configure
    }
}

public extension TableRow where Model: Identifiable, ID == Model.ID, Model.ID: Sendable {
    /// 使用 `Identifiable.id` 作为 row 身份创建 row。
    ///
    /// - Parameters:
    ///   - model: 遵守 `Identifiable` 的数据。
    ///   - cellType: cell 类型。
    ///   - configure: cell 配置闭包。
    init(
        model: Model,
        cell cellType: Cell.Type,
        configure: @escaping @MainActor (Cell, Model, TableListContext) -> Void
    ) {
        self.idSource = .explicit(model.id)
        self.model = model
        self.cellType = cellType
        self.configure = configure
    }
}

/// 多个 TableRow 的组合容器。
public struct TableRowGroup: TableRowRepresentable {
    private let rows: [any TableRowRepresentable]

    init(_ rows: [any TableRowRepresentable]) {
        self.rows = rows
    }

    @MainActor public func eraseToAnyTableRows<SectionID>(sectionID: SectionID) -> [AnyTableRow]
        where SectionID: Hashable & Sendable
    {
        rows.flatMap { $0.eraseToAnyTableRows(sectionID: sectionID) }
    }

    @MainActor public func eraseToAnyTableRows<SectionID>(
        sectionID: SectionID,
        inheritedID: AnyListID?
    ) -> [AnyTableRow] where SectionID: Hashable & Sendable {
        rows.flatMap { $0.eraseToAnyTableRows(sectionID: sectionID, inheritedID: inheritedID) }
    }
}

private struct InheritedIDTableRowScope: TableRowRepresentable {
    let row: any TableRowRepresentable
    let inheritedID: AnyListID

    @MainActor func eraseToAnyTableRows<SectionID>(sectionID: SectionID) -> [AnyTableRow]
        where SectionID: Hashable & Sendable
    {
        row.eraseToAnyTableRows(sectionID: sectionID, inheritedID: inheritedID)
    }
}

/// 在 `TableSection` 中遍历数据并把外层 id 传给内部 row。
///
/// - Parameters:
///   - data: 要遍历的数据序列。
///   - id: 从元素读取稳定身份的 key path。
///   - content: 为每个元素构建 row 的闭包。
/// - Returns: 可放入 `TableSection` 的 row 组合。
@MainActor public func TableForEach<Data, ID>(
    _ data: Data,
    id: KeyPath<Data.Element, ID>,
    @TableRowBuilder content: (Data.Element) -> [any TableRowRepresentable]
) -> TableRowGroup where Data: Sequence, ID: Hashable & Sendable {
    TableRowGroup(data.flatMap { element in
        let inheritedID = AnyListID(element[keyPath: id])
        return content(element).map { InheritedIDTableRowScope(row: $0, inheritedID: inheritedID) }
    })
}

/// 使用闭包遍历数据并生成元素身份。
///
/// - Parameters:
///   - data: 要遍历的数据序列。
///   - id: 从元素生成稳定身份的闭包。
///   - content: 为每个元素构建 row 的闭包。
/// - Returns: 可放入 `TableSection` 的 row 组合。
@MainActor public func TableForEach<Data, ID>(
    _ data: Data,
    id: (Data.Element) -> ID,
    @TableRowBuilder content: (Data.Element) -> [any TableRowRepresentable]
) -> TableRowGroup where Data: Sequence, ID: Hashable & Sendable {
    TableRowGroup(data.flatMap { element in
        let inheritedID = AnyListID(id(element))
        return content(element).map { InheritedIDTableRowScope(row: $0, inheritedID: inheritedID) }
    })
}

/// `TableSection` rows 的 result builder。
@resultBuilder
public enum TableRowBuilder {
    public static func buildExpression(_ expression: any TableRowRepresentable) -> [any TableRowRepresentable] {
        [expression]
    }

    public static func buildExpression(_ expression: [any TableRowRepresentable]) -> [any TableRowRepresentable] {
        expression
    }

    public static func buildExpression(_ expression: ()) -> [any TableRowRepresentable] {
        []
    }

    public static func buildBlock(_ components: [any TableRowRepresentable]...) -> [any TableRowRepresentable] {
        components.flatMap { $0 }
    }

    public static func buildArray(_ components: [[any TableRowRepresentable]]) -> [any TableRowRepresentable] {
        components.flatMap { $0 }
    }

    public static func buildEither(first component: [any TableRowRepresentable]) -> [any TableRowRepresentable] {
        component
    }

    public static func buildEither(second component: [any TableRowRepresentable]) -> [any TableRowRepresentable] {
        component
    }

    public static func buildOptional(_ component: [any TableRowRepresentable]?) -> [any TableRowRepresentable] {
        component ?? []
    }

    public static func buildLimitedAvailability(_ component: [any TableRowRepresentable]) -> [any TableRowRepresentable] {
        component
    }
}

enum TableSectionSupplementaryKind: Hashable, Sendable {
    case header
    case footer
}

/// 类型擦除后的 table header/footer 描述。
public struct AnyTableSectionSupplementary {
    public let identity: AnyListIdentity
    public let refreshID: AnyListID?
    public let refreshPolicy: RowRefreshPolicy
    public let height: TableRowHeight?

    let kind: TableSectionSupplementaryKind
    let register: @MainActor (UITableView) -> Void
    let viewProvider: @MainActor (UITableView, TableListContext) -> UITableViewHeaderFooterView
    let configureVisibleView: @MainActor (UITableViewHeaderFooterView, TableListContext) -> Void
    let displayHandler: (@MainActor (UITableViewHeaderFooterView, TableListContext) -> Void)?
    let endDisplayHandler: (@MainActor (UITableViewHeaderFooterView, TableListContext) -> Void)?
}

/// Table section header/footer 的 builder 元素。
public struct TableSectionSupplementary<SectionID> where SectionID: Hashable & Sendable {
    let kind: TableSectionSupplementaryKind
    private let makeSupplementaryProvider: @MainActor (SectionID) -> AnyTableSectionSupplementary

    init(
        kind: TableSectionSupplementaryKind,
        makeSupplementary: @escaping @MainActor (SectionID) -> AnyTableSectionSupplementary
    ) {
        self.kind = kind
        self.makeSupplementaryProvider = makeSupplementary
    }

    @MainActor func makeSupplementary(sectionID: SectionID) -> AnyTableSectionSupplementary {
        makeSupplementaryProvider(sectionID)
    }

    /// 设置 header/footer 高度。
    ///
    /// - Parameter height: 固定高度、自动高度或估算高度描述。
    public func height(_ height: TableRowHeight) -> Self {
        mapSupplementary { supplementary in
            AnyTableSectionSupplementary(
                identity: supplementary.identity,
                refreshID: supplementary.refreshID,
                refreshPolicy: supplementary.refreshPolicy,
                height: height,
                kind: supplementary.kind,
                register: supplementary.register,
                viewProvider: supplementary.viewProvider,
                configureVisibleView: supplementary.configureVisibleView,
                displayHandler: supplementary.displayHandler,
                endDisplayHandler: supplementary.endDisplayHandler
            )
        }
    }

    /// 设置 header/footer 的内容刷新版本。
    ///
    /// - Parameter refreshID: 内容版本标识。
    public func refreshID<RefreshID>(_ refreshID: RefreshID) -> Self where RefreshID: Hashable & Sendable {
        mapSupplementary { supplementary in
            AnyTableSectionSupplementary(
                identity: supplementary.identity,
                refreshID: AnyListID(refreshID),
                refreshPolicy: supplementary.refreshPolicy,
                height: supplementary.height,
                kind: supplementary.kind,
                register: supplementary.register,
                viewProvider: supplementary.viewProvider,
                configureVisibleView: supplementary.configureVisibleView,
                displayHandler: supplementary.displayHandler,
                endDisplayHandler: supplementary.endDisplayHandler
            )
        }
    }

    /// 设置 header/footer 的刷新策略。
    ///
    /// - Parameter policy: 刷新策略。
    public func refreshPolicy(_ policy: RowRefreshPolicy) -> Self {
        mapSupplementary { supplementary in
            AnyTableSectionSupplementary(
                identity: supplementary.identity,
                refreshID: supplementary.refreshID,
                refreshPolicy: policy,
                height: supplementary.height,
                kind: supplementary.kind,
                register: supplementary.register,
                viewProvider: supplementary.viewProvider,
                configureVisibleView: supplementary.configureVisibleView,
                displayHandler: supplementary.displayHandler,
                endDisplayHandler: supplementary.endDisplayHandler
            )
        }
    }

    /// 监听 header/footer 即将展示。
    ///
    /// - Parameter handler: 展示回调。
    public func onDisplay(_ handler: @escaping @MainActor (UITableViewHeaderFooterView, TableListContext) -> Void) -> Self {
        mapSupplementary { supplementary in
            AnyTableSectionSupplementary(
                identity: supplementary.identity,
                refreshID: supplementary.refreshID,
                refreshPolicy: supplementary.refreshPolicy,
                height: supplementary.height,
                kind: supplementary.kind,
                register: supplementary.register,
                viewProvider: supplementary.viewProvider,
                configureVisibleView: supplementary.configureVisibleView,
                displayHandler: handler,
                endDisplayHandler: supplementary.endDisplayHandler
            )
        }
    }

    /// 监听 header/footer 结束展示。
    ///
    /// - Parameter handler: 结束展示回调。
    public func onEndDisplay(_ handler: @escaping @MainActor (UITableViewHeaderFooterView, TableListContext) -> Void) -> Self {
        mapSupplementary { supplementary in
            AnyTableSectionSupplementary(
                identity: supplementary.identity,
                refreshID: supplementary.refreshID,
                refreshPolicy: supplementary.refreshPolicy,
                height: supplementary.height,
                kind: supplementary.kind,
                register: supplementary.register,
                viewProvider: supplementary.viewProvider,
                configureVisibleView: supplementary.configureVisibleView,
                displayHandler: supplementary.displayHandler,
                endDisplayHandler: handler
            )
        }
    }

    private func mapSupplementary(
        _ transform: @escaping @MainActor (AnyTableSectionSupplementary) -> AnyTableSectionSupplementary
    ) -> Self {
        let provider = makeSupplementaryProvider
        return TableSectionSupplementary(kind: kind) { sectionID in
            transform(provider(sectionID))
        }
    }
}

/// 创建 table section header。
///
/// - Parameters:
///   - viewType: header view 类型。
///   - id: header 的稳定身份。
///   - configure: header 配置闭包。
/// - Returns: 可放入 `TableSection` header builder 的元素。
@MainActor public func TableHeader<SectionID, ID, View>(
    _ viewType: View.Type,
    id: ID,
    configure: @escaping @MainActor (View, TableListContext) -> Void
) -> TableSectionSupplementary<SectionID>
    where SectionID: Hashable & Sendable, ID: Hashable & Sendable, View: UITableViewHeaderFooterView
{
    TableSectionSupplementary(kind: .header) { sectionID in
        let identity = AnyListIdentity(
            sectionID: AnyListID(sectionID),
            rowID: AnyListID(id),
            presentationID: ObjectIdentifier(viewType),
            variant: AnyListID(TableSectionSupplementaryKind.header)
        )
        return AnyTableSectionSupplementary(
            identity: identity,
            refreshID: nil,
            refreshPolicy: .automaticVisible,
            height: nil,
            kind: .header,
            register: { tableView in
                tableView.lk.registerHeaderFooter(viewType)
            },
            viewProvider: { tableView, context in
                let view = tableView.lk.dequeueHeaderFooter(viewType)
                configure(view, context)
                return view
            },
            configureVisibleView: { view, context in
                guard let typedView = view as? View else { return }
                configure(typedView, context)
            },
            displayHandler: nil,
            endDisplayHandler: nil
        )
    }
}

/// 创建 table section footer。
///
/// - Parameters:
///   - viewType: footer view 类型。
///   - id: footer 的稳定身份。
///   - configure: footer 配置闭包。
/// - Returns: 可放入 `TableSection` footer builder 的元素。
@MainActor public func TableFooter<SectionID, ID, View>(
    _ viewType: View.Type,
    id: ID,
    configure: @escaping @MainActor (View, TableListContext) -> Void
) -> TableSectionSupplementary<SectionID>
    where SectionID: Hashable & Sendable, ID: Hashable & Sendable, View: UITableViewHeaderFooterView
{
    TableSectionSupplementary(kind: .footer) { sectionID in
        let identity = AnyListIdentity(
            sectionID: AnyListID(sectionID),
            rowID: AnyListID(id),
            presentationID: ObjectIdentifier(viewType),
            variant: AnyListID(TableSectionSupplementaryKind.footer)
        )
        return AnyTableSectionSupplementary(
            identity: identity,
            refreshID: nil,
            refreshPolicy: .automaticVisible,
            height: nil,
            kind: .footer,
            register: { tableView in
                tableView.lk.registerHeaderFooter(viewType)
            },
            viewProvider: { tableView, context in
                let view = tableView.lk.dequeueHeaderFooter(viewType)
                configure(view, context)
                return view
            },
            configureVisibleView: { view, context in
                guard let typedView = view as? View else { return }
                configure(typedView, context)
            },
            displayHandler: nil,
            endDisplayHandler: nil
        )
    }
}

@resultBuilder
public enum TableSectionSupplementaryBuilder<SectionID> where SectionID: Hashable & Sendable {
    public static func buildExpression(_ expression: TableSectionSupplementary<SectionID>) -> [TableSectionSupplementary<SectionID>] {
        [expression]
    }

    public static func buildExpression(_ expression: [TableSectionSupplementary<SectionID>]) -> [TableSectionSupplementary<SectionID>] {
        expression
    }

    public static func buildExpression(_ expression: ()) -> [TableSectionSupplementary<SectionID>] {
        []
    }

    public static func buildBlock(_ components: [TableSectionSupplementary<SectionID>]...) -> [TableSectionSupplementary<SectionID>] {
        components.flatMap { $0 }
    }

    public static func buildArray(_ components: [[TableSectionSupplementary<SectionID>]]) -> [TableSectionSupplementary<SectionID>] {
        components.flatMap { $0 }
    }

    public static func buildEither(first component: [TableSectionSupplementary<SectionID>]) -> [TableSectionSupplementary<SectionID>] {
        component
    }

    public static func buildEither(second component: [TableSectionSupplementary<SectionID>]) -> [TableSectionSupplementary<SectionID>] {
        component
    }

    public static func buildOptional(_ component: [TableSectionSupplementary<SectionID>]?) -> [TableSectionSupplementary<SectionID>] {
        component ?? []
    }

    public static func buildLimitedAvailability(_ component: [TableSectionSupplementary<SectionID>]) -> [TableSectionSupplementary<SectionID>] {
        component
    }
}

/// 一个 UITableView section 的完整描述。
public struct TableSection<SectionID> where SectionID: Hashable & Sendable {
    public let id: SectionID
    public var rows: [AnyTableRow]
    public var header: AnyTableSectionSupplementary?
    public var footer: AnyTableSectionSupplementary?
    public var selectionMode: ListSelectionMode
    public var indexTitle: String?
    public var headerTitle: String?
    public var footerTitle: String?
    public var allowsMultipleSelectionInteraction: Bool

    /// 创建 table section。
    ///
    /// ```swift
    /// TableSection(.messages) {
    ///     TableForEach(messages, id: \.id) { message in
    ///         TableRow(model: message, cell: MessageCell.self) { cell, message, _ in
    ///             cell.configure(message)
    ///         }
    ///     }
    /// } header: {
    ///     TableHeader(MessageHeaderView.self, id: "header") { view, _ in
    ///         view.title = "Messages"
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - id: section 的稳定业务身份。
    ///   - rows: row builder。
    ///   - header: header builder，最多使用第一个 header。
    ///   - footer: footer builder，最多使用第一个 footer。
    @MainActor public init(
        _ id: SectionID,
        @TableRowBuilder rows: () -> [any TableRowRepresentable],
        @TableSectionSupplementaryBuilder<SectionID> header: () -> [TableSectionSupplementary<SectionID>] = { [] },
        @TableSectionSupplementaryBuilder<SectionID> footer: () -> [TableSectionSupplementary<SectionID>] = { [] }
    ) {
        self.id = id
        self.rows = rows().flatMap { $0.eraseToAnyTableRows(sectionID: id) }
        self.header = header().first { $0.kind == .header }?.makeSupplementary(sectionID: id)
        self.footer = footer().first { $0.kind == .footer }?.makeSupplementary(sectionID: id)
        self.selectionMode = .none
        self.indexTitle = nil
        self.headerTitle = nil
        self.footerTitle = nil
        self.allowsMultipleSelectionInteraction = false
    }

    /// 设置 section 的选择模式。
    ///
    /// - Parameter mode: 单选、多选或不启用选择。
    public func selectionMode(_ mode: ListSelectionMode) -> Self {
        var copy = self
        copy.selectionMode = mode
        return copy
    }

    /// 设置 table 侧边索引标题。
    public func indexTitle(_ title: String?) -> Self {
        var copy = self
        copy.indexTitle = title
        return copy
    }

    /// 使用系统文本 header；自定义 header builder 优先。
    public func headerTitle(_ title: String?) -> Self {
        var copy = self
        copy.headerTitle = title
        return copy
    }

    /// 使用系统文本 footer；自定义 footer builder 优先。
    public func footerTitle(_ title: String?) -> Self {
        var copy = self
        copy.footerTitle = title
        return copy
    }

    /// 允许系统的多选手势从当前 section 开始。
    public func multipleSelectionInteraction(_ enabled: Bool = true) -> Self {
        var copy = self
        copy.allowsMultipleSelectionInteraction = enabled
        return copy
    }
}

/// `TableListAdapter.apply` 的 section result builder。
@resultBuilder
public enum TableSectionBuilder<SectionID> where SectionID: Hashable & Sendable {
    public static func buildExpression(_ expression: TableSection<SectionID>) -> [TableSection<SectionID>] {
        [expression]
    }

    public static func buildExpression(_ expression: [TableSection<SectionID>]) -> [TableSection<SectionID>] {
        expression
    }

    public static func buildExpression(_ expression: ()) -> [TableSection<SectionID>] {
        []
    }

    public static func buildBlock(_ components: [TableSection<SectionID>]...) -> [TableSection<SectionID>] {
        components.flatMap { $0 }
    }

    public static func buildArray(_ components: [[TableSection<SectionID>]]) -> [TableSection<SectionID>] {
        components.flatMap { $0 }
    }

    public static func buildEither(first component: [TableSection<SectionID>]) -> [TableSection<SectionID>] {
        component
    }

    public static func buildEither(second component: [TableSection<SectionID>]) -> [TableSection<SectionID>] {
        component
    }

    public static func buildOptional(_ component: [TableSection<SectionID>]?) -> [TableSection<SectionID>] {
        component ?? []
    }

    public static func buildLimitedAvailability(_ component: [TableSection<SectionID>]) -> [TableSection<SectionID>] {
        component
    }
}

/// 独立构建 table section 数组的 helper。
public enum TableSectionsBuilder<SectionID> where SectionID: Hashable & Sendable {
    /// 构建 section 数组。
    ///
    /// - Parameter content: section builder。
    /// - Returns: 构建完成的 section 数组。
    @MainActor public static func build(
        @TableSectionBuilder<SectionID> _ content: () -> [TableSection<SectionID>]
    ) -> [TableSection<SectionID>] {
        content()
    }
}
