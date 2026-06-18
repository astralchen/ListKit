# ListKit Table Adapter Design

## Architecture

`TableListAdapter` 独立于 `CollectionListAdapter` 实现，但共享 ListKit Core 的稳定语义。当前 collection DSL 的 `AnyListRow`、`AnySupplementary` 和 `ListContext` 闭包签名已经绑定 `UICollectionView`，因此 table 侧新增 table-specific 描述类型，避免牵动已迁移 collection 页面。

首版 public API 方向：

```swift
private lazy var adapter = TableListAdapter<Section>(tableView: tableView)

adapter.apply(animatingDifferences: false) {
    TableSection(.messages) {
        TableForEach(messages, id: \.messageID) { message in
            TableRow(model: message, cell: MessageCell.self) { cell, message, context in
                cell.configure(message)
            }
            .refreshID(message.contentVersion)
            .onSelect { message, context in
                router.open(message, from: context.indexPath)
            }
        }
    } header: {
        TableHeader(TitleHeaderView.self, id: "title") { view, _ in
            view.titleLabel.text = "消息"
        }
        .height(.estimated(44))
    }
}
```

命名使用 `TableRow`、`TableSection`、`TableHeader`、`TableFooter`、`TableForEach` 和 `TableListContext`，不复用 `Row`/`ListSection` 名称。这样 Quick Help 和调用点能清楚区分 table 与 collection，同时保留一致的 modifier 风格。

## Core Model

Table adapter 内部维护：

- `sections: [TableSection<SectionID>]`
- `rowsByIdentity: [AnyListIdentity: AnyTableRow]`
- `headersBySection: [AnyListID: AnyTableSectionSupplementary]`
- `footersBySection: [AnyListID: AnyTableSectionSupplementary]`
- `eventHandlers: [ObjectIdentifier: @MainActor (any ListEvent, TableListContext) -> Void]`

`AnyTableRow` 使用 `AnyListIdentity` 描述展示身份：

```swift
sectionID + rowID + ObjectIdentifier(Cell.self) + variant
```

`refreshID` 不参与 identity。它只参与 `RowRefreshPolicy` 判断，语义保持和 collection row 一致。

`TableListContext` 持有：

- `sectionID: AnyListID`
- `indexPath: IndexPath`
- `unowned let tableView: UITableView`
- `send(_:)` 事件分发入口
- `section(as:)` 强类型 section id helper

由于 context 类型不同，`TableApplyResult.onEvent` 的 handler 接收 `TableListContext`，不接收 `ListContext`。

## Apply Flow

`TableListAdapter.apply(...)` 对齐 Collection adapter overload：

- builder apply
- section array apply
- completion apply
- `refresh refreshStrategy`
- `options: ListApplyOptions`

流程：

1. builder 生成 `[TableSection<SectionID>]`。
2. 运行 table diagnostics，检查重复 section、row、header、footer identity。
3. 重建 lookup table，并自动注册 cell/header/footer。
4. 生成 `NSDiffableDataSourceSnapshot<AnyListID, AnyListIdentity>`。
5. 按 `ListApplyRefreshStrategy` 和 row refresh policy 计算 snapshot reload items。
6. 调用 `UITableViewDiffableDataSource.apply(...)`。
7. completion 中按 visible refresh policy 重配仍可见 row，并更新 `lastApplySummary`。

UITableView 没有 collection 的 `reconfigureItems` 路径，首版用 snapshot `reloadItems` 表达需要完整刷新/重新量高的节点；轻量 UI 更新走 `reconfigureVisibleRows(...)`，直接对当前 visible cell 执行 configure。

## UITableView Adapter Surface

Adapter 接管：

- `UITableViewDataSource`
- `UITableViewDelegate`
- `UITableViewDataSourcePrefetching`

主要 helper 对齐 Collection adapter：

- `sectionIdentifier(at:)`
- `rowCount(in:)`
- `itemCount(in:)` 作为命名兼容 helper
- `indexPaths(forRowID:in:)`
- `scrollToLastRow(in:at:animated:)`
- `reconfigureVisibleRows(forRowID:in:)`
- `reloadVisibleRows(forRowID:in:)`
- `onEvent(...)`

转发对象：

- `scrollDelegate: UIScrollViewDelegate?`
- `tableDelegate: UITableViewDelegate?`

adapter 消费 row DSL 已声明的 selection、display、height、context menu、editing、swipe 和 prefetch；未声明或 ListKit 不处理的 delegate 方法再转发给 `tableDelegate`。如果某个回调同时存在 row handler 和 tableDelegate，先执行 row handler，再按 UIKit 语义返回可组合结果；不可组合的返回值优先使用 row 声明。

## Table DSL

`TableSection` 负责 rows、header、footer、selection mode 和 section-level metadata。首版不承载 collection layout、supplementary layout 或 background decoration。

```swift
TableSection(.main) {
    TableRow(model: user, id: \.userID, cell: UserCell.self) { cell, user, _ in
        cell.configure(user)
    }
} header: {
    TableHeader(UserHeaderView.self, id: "header") { view, _ in
        view.configure(title)
    }
    .height(.fixed(48))
} footer: {
    TableFooter(LoadingFooterView.self, id: "footer") { view, _ in
        view.isLoading = isLoading
    }
    .height(.automatic(estimated: 52))
}
```

`TableRow` 支持：

- explicit id、key path id、closure id、`Identifiable` model、`TableForEach` identity inheritance
- `variant(_:)`
- `refreshID(_:)`
- `refreshPolicy(_:)`
- `height(_:)` / `estimatedHeight(_:)`
- `selected(_:)`
- `onSelect` / `onDeselect` / `onSelectionChange`
- `onDisplay` / `onEndDisplay`
- `onPrefetch` / `onCancelPrefetch`
- `onCellEvent`
- `contextMenu(_:)`
- `editing(...)`
- `canMove(_:)` / `onMove(...)`
- `leadingSwipeActions(_:)` / `trailingSwipeActions(_:)`

`TableHeader` 和 `TableFooter` 使用 `UITableViewHeaderFooterView`，支持 `refreshID`、`refreshPolicy`、`height`、`onDisplay` 和 `onEndDisplay`。

## Reusable Namespace

新增 `UITableView.lk`：

```swift
tableView.lk.register(UserCell.self)
let cell: UserCell = tableView.lk.dequeue(UserCell.self, for: indexPath)

tableView.lk.registerHeaderFooter(UserHeaderView.self)
let header: UserHeaderView = tableView.lk.dequeueHeaderFooter(UserHeaderView.self)
```

注册规则与 collection 一致：同名 nib 存在时注册 nib，否则注册 class。原生 `register(_:forCellReuseIdentifier:)` 和 `dequeueReusableCell(withIdentifier:for:)` 不废弃，迁移页面可以继续混用。

## Editing and Swipe

ListKit 只内置 UIKit 原生能力：

- `UITableViewCell.EditingStyle`
- `commit editingStyle`
- `canEditRowAt`
- `canMoveRowAt`
- `moveRowAt`
- `UISwipeActionsConfiguration`
- iOS 13+ context menu

`SwipeCellKit` 不进入 ListKit package 依赖。`ConversationListViewController` 这类页面如果需要迁移，应在 Rebirth App 层提供 bridge：将 `TableRow` 的业务事件和页面现有 SwipeCellKit delegate 连接起来，或者让该页面继续自管第三方 swipe delegate。

## Diagnostics and Tests

Table diagnostics 复用 `ListDiagnosticsIssueKind` 中现有重复类型。header/footer 可沿用 `.duplicateSupplementary`，message 中明确 table header/footer 和 section id。

实现阶段需要新增 table-focused XCTest：

- diffable apply 生成 section/row snapshot
- duplicate section/row/header/footer diagnostics
- refreshID + refresh policy reload 统计
- visible reconfigure 和 visible reload
- selection/display/prefetch handler
- fixed/automatic/estimated row/header/footer height
- context menu、editing、move、leading/trailing swipe
- `UITableView.lk` class/nib 注册和类型安全 dequeue

包级 `swift test` 在当前工具链可能仍走 macOS route 导致 UIKit 导入失败；如果发生，记录原始错误，并使用 Rebirth workspace iOS Simulator build 作为编译兜底。
