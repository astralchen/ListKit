# ListKit DSL Design

## Architecture

`ListKit` 是 `CellKit` 的并行替代方案，只依赖 UIKit/Foundation，不依赖 Rebirth 业务代码和第三方 UI 库。核心链路是：

```text
声明式描述树 -> 内部类型擦除 -> Diffable snapshot -> 精准刷新 -> 事件分发
```

主要组件：

- `CollectionListAdapter<SectionID>`：绑定 `UICollectionView`，管理 diffable data source、snapshot、刷新和事件分发。
- `ListSection<SectionID>`：描述 section、rows、header/footer/custom supplementary。
- `Row<ID, Model, Cell>`：描述业务身份、model、cell 类型、配置闭包和事件。
- `Supplementary<ID, View>`：描述 header/footer/custom supplementary。
- `ListContext`：向配置和事件闭包提供 `sectionID`、`indexPath`、`collectionView` 和 `context.send(...)`。
- `AnyListRow` / `AnySupplementary` / `AnyListID` / `AnyListIdentity`：内部类型擦除，避免业务 model conform 框架协议。

## Public API

### ForEach 内继承 id

```swift
adapter.apply(animatingDifferences: false) {
    ListSection(.users) {
        ForEach(users, id: \.userID) { user in
            if user.isVIP {
                Row(model: user, cell: VIPUserCell.self) { cell, user, context in
                    cell.configure(user)
                }
                .refreshID(user.profileVersion)
            } else {
                Row(model: user, cell: NormalUserCell.self) { cell, user, context in
                    cell.configure(user)
                }
                .refreshID(user.profileVersion)
            }
        }
    }
}
```

重点逻辑：`ForEach(data, id:)` 会把当前元素 id 下传给内部 `Row(model:cell:)`。这样常见列表不需要在 `ForEach` 和 `Row` 上重复写两次业务 id。

### 单个 Row

```swift
Row("banner", model: banners, cell: BannerCell.self) { cell, banners, _ in
    cell.configure(banners)
}

Row(model: user, cell: UserCell.self) { cell, user, _ in
    cell.configure(user)
}

Row(model: user, id: \.userID, cell: UserCell.self) { cell, user, _ in
    cell.configure(user)
}

Row(model: user, id: { $0.userID.isEmpty ? $0.accountID : $0.userID }, cell: UserCell.self) { cell, user, _ in
    cell.configure(user)
}
```

固定功能块保留语义 id；`Identifiable` model 可自动使用 `model.id`；普通 model 用 keyPath 或 closure 明确身份。

## Identity And Refresh Rules

Row 的展示身份是：

```text
sectionID + rowID + ObjectIdentifier(Cell.self) + variant
```

`refreshID` 不参与 identity。原因是：数据变了通常只需要刷新同一个展示节点；只有 `rowID + Cell.self + variant` 变化时，才代表“这是另一个 UI 节点”，应交给 diffable 做 delete + insert。

刷新策略：

- `.automaticVisible`：默认策略。identity 不变时只重配可见 cell。
- `.whenRefreshIDChanges`：`refreshID` 变化时触发 `reconfigureItems`，iOS 14 使用 `reloadItems` 兜底。
- `.never`：identity 不变时不主动刷新。
- `.alwaysVisible`：每次 apply 后重配可见 cell。

## Event Model

内置 Row 事件：

- `.onSelect`
- `.onDeselect`
- `.onDisplay`
- `.onEndDisplay`
- `.onPrefetch`
- `.onCancelPrefetch`
- `.contextMenu`
- `.leadingSwipeActions`
- `.trailingSwipeActions`

Supplementary 事件：

- `.onTap`
- `.onDisplay`
- `.onEndDisplay`
- section 级 `.onHeaderTap` / `.onFooterTap`

自定义事件：

```swift
enum UserListEvent: ListEvent {
    case avatarTap(userID: String)
}

Row(model: user, id: \.userID, cell: UserCell.self) { cell, user, context in
    cell.onAvatarTap = {
        context.send(UserListEvent.avatarTap(userID: user.userID))
    }
}

adapter.apply { ... }
    .onEvent(UserListEvent.self) { event, context in
        // 页面统一处理业务事件
    }
```

## Error Handling

- `Row(model:cell:)` 如果既不是 `Identifiable` 单个 model，也没有位于 `ForEach(id:)` 继承作用域内，会触发明确的 precondition failure，提示使用 `Row(model:id:cell:)` 或显式 id。
- dequeue 使用强类型泛型 API；如果业务注册/类型错误，会以 UIKit 原有错误形式暴露，便于定位。
- `context.send(...)` 只在 `@MainActor` 分发，避免 UIKit 事件越过主线程。

## Testing

测试覆盖：

- builder 支持 `ForEach`、`if/else` 和 header。
- `ForEach` 内 `Row(model:cell:)` 继承外层 id。
- closure id 支持 fallback identity。
- 单个 `Identifiable` model 自动使用 `model.id`。
- 单个普通 model 支持 keyPath id。
- `Cell.self` 参与 identity，`refreshID` 独立于 identity。
- `.variant(...)` 改变 identity。
- 可见 cell 重配。
- Header tap 和自定义事件分发。
