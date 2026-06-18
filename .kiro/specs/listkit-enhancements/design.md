# ListKit Enhancements Design

## Architecture

增强版继续沿用“声明式描述树 -> 类型擦除 -> diffable snapshot -> 精准刷新”的架构。本轮只在核心模型上增加元数据和诊断能力，不引入业务状态管理，也不让业务 model conform ListKit 私有协议。

```mermaid
flowchart LR
    "DSL: ListSection / Row / Supplementary" --> "Validate: ListDiagnostics"
    "Validate: ListDiagnostics" --> "Lookup Tables"
    "Lookup Tables" --> "Diffable Snapshot"
    "Diffable Snapshot" --> "Refresh Strategy"
    "Refresh Strategy" --> "Events / Selection / Delegates"
```

## New Public Types

### `ListDiagnostics`

负责在 `apply` 前检测重复 identity。

```swift
let issues = ListDiagnostics.validate(sections)
```

DEBUG 下默认 `.warning`。当存在诊断问题时，adapter 会输出 warning 并跳过本次 diffable apply，避免 diffable 自己崩溃。

### `ListApplyOptions`

承载 apply 级配置。

```swift
adapter.apply(
    options: ListApplyOptions(
        animatingDifferences: false,
        refreshStrategy: .diffableOnly,
        diagnostics: .init(mode: .warning)
    )
) {
    ListSection(.users) {
        ...
    }
}
```

`apply(animatingDifferences:)` 保留，并内部转到 `ListApplyOptions`。

### `ListApplySummary`

`apply` 返回值增加 `summary`，用于测试和 DEBUG 定位。

```swift
let result = adapter.apply(options: .init(animatingDifferences: false)) {
    ListSection(.users) { ... }
}

print(result.summary.refreshIDChangedCount)
```

## Identity Diagnostics

检测范围：

- section: `AnyListID(section.id)`
- row: `sectionID + rowID + Cell.self + variant`
- supplementary: `sectionID + supplementaryID + View.self + kind`

处理策略：

- `.disabled`: 不做拦截。
- `.warning`: 输出 warning，跳过本次 diffable apply。
- `.assertion`: `assertionFailure`，跳过本次 diffable apply。

这层只保护 identity 输入，不改变 ListKit 的 identity 语义。

## Apply Refresh Strategy

Row 级策略继续有效：

- `.automaticVisible`
- `.whenRefreshIDChanges`
- `.never`
- `.alwaysVisible`

Apply 级策略用于一次性覆盖：

- `.automatic`: 使用 Row 级策略。
- `.visibleOnly`: snapshot 不 reconfigure/reload，只刷新可见 cell。
- `.diffableOnly`: 只做 snapshot reconfigure/reload。
- `.forceReload`: 当前 snapshot items 全部 reconfigure/reload。

## Model-Aware Events

保留原 API：

```swift
Row(model: user, cell: UserCell.self) { cell, user, context in
    cell.configure(user)
}
.onSelect { context in
    ...
}
```

新增带 model 重载：

```swift
Row(model: user, cell: UserCell.self) { cell, user, context in
    cell.configure(user)
}
.onSelect { user, context in
    router.openProfile(user.id)
}
.onPrefetch { user, context in
    avatarLoader.prefetch(user.avatarURL)
}
.onCancelPrefetch { user, context in
    avatarLoader.cancel(user.avatarURL)
}
```

内部使用 MainActor 专用捕获盒子保存 model，避免强制业务 model conform `Sendable`。

## Cell Event Binding

`.onCellEvent` 把 cell 内部事件源绑定到类型安全 `ListEvent`。

```swift
enum UserEvent: ListEvent {
    case avatarTap(userID: Int)
}

Row(model: user, cell: UserCell.self) { cell, user, context in
    cell.configure(user)
}
.onCellEvent({ cell, send in
    cell.onAvatarTap = send
}, send: { user in
    UserEvent.avatarTap(userID: user.id)
})
```

这个 API 是 configure 内 `context.send(...)` 的少样板版本，两者可以并存。

## Lightweight State Rows

状态 Row 只提供稳定 identity 和强类型配置闭包。

```swift
ListSection(.users) {
    if isLoading {
        ListStateRow.loading(LoadingCell.self) { cell, context in
            cell.startAnimating()
        }
    } else if users.isEmpty {
        ListStateRow.empty(EmptyCell.self) { cell, context in
            cell.titleLabel.text = "暂无用户"
        }
    }
}
```

状态机仍由页面或 view model 管理。

## Section Metadata

Section 新增可选元数据：

```swift
ListSection(.users) {
    ...
}
.layout("two-column-grid")
.selectionMode(.multiple)
.stickyHeader()
.backgroundDecoration("user-background")
```

`layout`、`stickyHeader`、`backgroundDecoration` 首版只存 metadata。页面可以在 compositional layout provider 中读取 adapter/section 的 metadata 来生成真实 layout；后续再评估是否提供更完整的 layout provider 封装。

## Selection

Row 选中态：

```swift
Row(model: gift, cell: GiftCell.self) { cell, gift, _ in
    cell.configure(gift)
}
.selected(selectedGiftID == gift.id)
.onSelectionChange { gift, isSelected, context in
    store.updateSelection(gift.id, isSelected: isSelected)
}
```

Adapter 在 cell dequeue 时同步 UIKit 选中态，并在 select/deselect delegate 中触发 selection change。

## Supplementary Enhancements

`Supplementary` 支持 refresh policy：

```swift
let header = Supplementary(
    UICollectionView.elementKindSectionHeader,
    id: "users-header",
    view: TitleHeaderView.self
) { view, context in
    view.titleLabel.text = "用户"
}
.refreshID(headerVersion)
.refreshPolicy(.whenRefreshIDChanges)

ListSection(.users) { ... }
    .supplementary(header)
```

多个 custom kind 继续通过多次 `.supplementary(kind, ...)` 追加。

## Delegate Forwarding

Adapter 仍接管 `collectionView.delegate`，但页面可以设置转发对象：

```swift
adapter.scrollDelegate = self
adapter.layoutDelegate = self
```

首版转发常用 scroll 和 `UICollectionViewDelegateFlowLayout` 方法。未设置 delegate 时使用 flow layout 自身默认值。

## P2 Table Design

### UITableView Adapter

独立 spec 已新增并完成首版实现：`.kiro/specs/listkit-table-adapter/`。

设计结论：

- 使用 `TableListAdapter`、`TableSection`、`TableRow`、`TableListContext`，不泛化当前 collection-only `Row/ListSection/ListContext`。
- 复用 Core identity、refresh、diagnostics、apply options 和 `ListEvent` 语义。
- 首版按完整 UIKit UITableView 能力设计，覆盖 cell/header/footer、selection、display、prefetch、高度、editing、move、context menu、leading/trailing `UISwipeActionsConfiguration`、可见刷新和 scroll forwarding。
- 不在 ListKit package 引入 `SwipeCellKit`；第三方 swipe 通过 App 层 bridge 或页面自管。

### File Split

当前已经按职责拆分到目录，保持 public API 不变：

- `Core/`：`Identity.swift`、`Diagnostics.swift`、`ApplyOptions.swift`、`Events.swift`
- `DSL/`：`ListBuilders.swift`、`Row.swift`、`Section.swift`、`Supplementary.swift`
- `Reusable/`：`CollectionReusable.swift`
- `Collection/`：`CollectionListAdapter.swift`、`CollectionLayout.swift`
- `Table/`：`TableListAdapter.swift`、`TableDSL.swift`

### Macro / Codegen

宏只作为编译期糖，不进入首版默认路径。可探索：

- `@ListCellEventSource`
- `@ListRowBinding`
- 事件 enum 到 cell closure 的生成。
