# ListKit

ListKit 提供 `UICollectionView` 和 `UITableView` 列表适配器。它不要求业务 model conform 框架协议，页面每次数据变化后 rebuild 列表描述树，由框架根据 identity、`refreshID` 和 refresh policy 决定 diff、重配或保持不动。

Swift Doc 注释面向 Xcode Quick Help，保留短摘要、参数说明和少量核心 Usage；完整迁移路径、组合示例和设计取舍仍以本文档与 `.kiro` 规格为准。

## 安装

ListKit 支持 iOS 14+，使用 Swift 6 Package Manager。在 Xcode 的 Package Dependencies 中添加：

```text
https://github.com/astralchen/ListKit.git
```

或在 `Package.swift` 中声明：

```swift
dependencies: [
    .package(url: "https://github.com/astralchen/ListKit.git", from: "1.0.0")
]
```

Kiro 规格文件位于 ListKit package 内：

- `.kiro/specs/listkit-cellkit-migration/`：CellKit 到 ListKit 的迁移边界和验收规则
- `.kiro/specs/listkit-adaptation-optimization/`：adapter ownership、稳定 identity、迁移兼容 API 标记
- `.kiro/specs/listkit-conditional-layout-metadata/`：条件 layout、supplementary builder、section 背景装饰
- `.kiro/specs/listkit-api-hardening/`：实时列表定位/可见刷新 API、迁移桥接层退场
- `.kiro/specs/listkit-table-adapter/`：UITableView adapter 独立 Table DSL 和完整 UIKit table 能力边界
- `.kiro/specs/listkit-adapter-core-refactor/`：Collection/Table adapter apply、diagnostics、summary、refresh 和 event core 去重

## 源码目录

ListKit 按职责分成几层，`UICollectionView` 和 `UITableView` adapter 共享 Core/Reusable 和稳定语义：

- `Core/`：identity、diagnostics、events、apply options、apply planner、summary 和 refresh decision 等跨列表核心能力。
- `DSL/`：`Row`、`ListSection`、`Supplementary`、builder 和 modifier。
- `Reusable/`：UICollectionView/UITableView 可复用的注册和 dequeue 基础工具。
- `Collection/`：`CollectionListAdapter` 和 UICollectionView compositional layout DSL。
- `Table/`：`TableListAdapter` 和独立 Table DSL。

## 基础用法

### UICollectionView

```swift
private lazy var adapter = CollectionListAdapter<Section>(collectionView: collectionView)

adapter.apply(transaction: .disabled) {
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
    .header(TitleHeaderView.self, id: "users-header") { view, _ in
        view.titleLabel.text = "用户"
    }
}
```

### UITableView

Table DSL 与 Collection DSL 保持同一套 identity、`refreshID`、refresh policy、diagnostics 和 event 语义，但使用独立 public 类型：

```swift
private lazy var adapter = TableListAdapter<Section>(tableView: tableView)

adapter.apply(transaction: .disabled) {
    TableSection(.messages) {
        TableForEach(messages, id: \.messageID) { message in
            TableRow(model: message, cell: MessageCell.self) { cell, message, context in
                cell.configure(message)
            }
            .refreshID(message.contentVersion)
            .height(.automatic(estimated: 64))
            .onSelect { message, _ in
                router.open(message)
            }
        }
    } header: {
        TableHeader(TitleHeaderView.self, id: "messages-title") { view, _ in
            view.titleLabel.text = "消息"
        }
        .height(.estimated(44))
    }
}
```

## 身份和刷新规则

Row 的展示身份是：

```swift
sectionID + rowID + ObjectIdentifier(Cell.self) + variant
```

`refreshID` 不参与 identity。这样同一个用户从普通态变成 VIP 时，不需要手动传 `kind`：

```swift
ForEach(users, id: \.userID) { user in
    if user.isVIP {
        Row(model: user, cell: VIPUserCell.self) { cell, user, _ in
            cell.configure(user)
        }
    } else {
        Row(model: user, cell: NormalUserCell.self) { cell, user, _ in
            cell.configure(user)
        }
    }
}
```

因为 `Cell.self` 参与 identity，`NormalUserCell` 和 `VIPUserCell` 会被视为不同展示节点，diffable 会执行 delete + insert。

## Row ID 写法

`ForEach` 内部的 Row 默认继承外层 id，不需要重复写一遍：

```swift
ForEach(users, id: \.userID) { user in
    Row(model: user, cell: UserCell.self) { cell, user, _ in
        cell.configure(user)
    }
}
```

单个固定功能 Row 仍建议用语义 id：

```swift
Row("banner", model: banners, cell: BannerCell.self) { cell, banners, _ in
    cell.configure(banners)
}
```

单个业务 model 可以用 `Identifiable` 自动 id，或者用 keyPath/闭包显式声明身份：

```swift
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

当 `rowID` 和 `Cell.self` 不变但数据变化时：

```swift
Row(model: user, id: \.userID, cell: UserCell.self) { cell, user, _ in
    cell.configure(user)
}
.refreshID(user.profileVersion)
.refreshPolicy(.whenRefreshIDChanges)
```

iOS 15+ 使用 `reconfigureItems`，iOS 14 使用 `reloadItems` 兜底。默认 `.automaticVisible` 只重配当前可见 cell；未提供 `refreshID` 时每次 apply 都会重配，提供后只在标识变化时重配。`.alwaysVisible` 用于明确要求每次重配。

apply 级策略中，`.automatic` 按 Row policy 选择 diffable 或可见刷新；`.visibleOnly` 不修改 snapshot refresh 标记，其中 `.whenRefreshIDChanges` 会在标识变化时改为重配可见 cell；`.diffableOnly` 不执行额外可见重配；`.forceReload` 会 reload 所有新旧 snapshot 中都存在的 Row。

`ListApplyRefreshStrategy.forceReload` 只对新旧 snapshot 都存在的 row identity 执行 diffable refresh；新插入的 row 交给 diffable insert 处理，不再被重复 reload/reconfigure。Table header/footer 和 Collection supplementary 的 `refreshID` 变化会进入 `supplementaryRefreshIDChangedCount`，并按 supplementary 可见刷新策略在 apply completion 后轻刷当前可见 view。

## 事件

标准 Row 事件：

```swift
Row(model: channel, id: \.channelID, cell: RoomCell.self) { cell, channel, _ in
    cell.configure(channel)
}
.onSelect { context in
    // 跳转或进入房间
}
.onSelect { channel, context in
    // 需要 model 时直接使用强类型重载
}
.onDisplay { cell, context in
    // 曝光
}
.onPrefetch { channel, context in
    // 预取图片、房间封面等资源
}
```

自定义事件：

```swift
enum UserListEvent: ListEvent {
    case avatarTap(userID: String)
}

adapter.apply {
    ListSection(.users) {
        Row(model: user, id: \.userID, cell: UserCell.self) { cell, user, context in
            cell.onAvatarTap = {
                context.send(UserListEvent.avatarTap(userID: user.userID))
            }
        }
    }
}
.onEvent(UserListEvent.self) { event, context in
    // 页面统一处理业务事件
}
```

cell 内部事件也可以用少样板绑定：

```swift
Row(model: user, id: \.userID, cell: UserCell.self) { cell, user, _ in
    cell.configure(user)
}
.onCellEvent({ cell, send in
    cell.onAvatarTap = send
}, send: { user in
    UserListEvent.avatarTap(userID: user.userID)
})
```

## 实时列表定位与可见刷新

实时页面不需要保存第二套 `sections` 才能查行或刷新可见 cell，优先读取 adapter 当前描述树：

```swift
let count = adapter.itemCount(in: .messages)
let indexPaths = adapter.indexPaths(forRowID: messageID, in: .messages)

let transaction = ListTransaction.automatic.scrollBehavior(
    .scrollToLast(in: Section.messages, position: .bottom)
)
let result = await adapter.applyAndWait(transaction: transaction) {
    ListSection(.messages) {
        ForEach(messages, id: \.messageID) { message in
            Row(model: message, cell: MessageCell.self) { cell, message, _ in
                cell.configure(message)
            }
            .refreshID(message.layoutVersion)
        }
    }
}

print(result.summary.animation.scrollAnimated)
```

动态高度变化用 `reloadVisibleRows`，它通过 diffable snapshot reload 当前可见 identity，适合公屏消息展开、图片加载后重新量高：

```swift
adapter.reloadVisibleRows(forRowID: messageID, in: .messages)
```

不需要重新布局的状态轻刷新用 `reconfigureVisibleRows`，适合麦位发言动画、工具栏倒计时、PK 状态：

```swift
adapter.reconfigureVisibleRows(forRowID: seatID, in: .seats)
```

Header/Footer 可以在 view 内部发送事件，也可以使用 section 级点击：

```swift
ListSection(.history) {
    Row(model: keyword, id: \.self, cell: SearchHistoryCell.self) { cell, keyword, _ in
        cell.titleLabel.text = keyword
    }
}
.header(SearchHeaderView.self, id: "history-header") { view, context in
    view.titleLabel.text = "搜索记录:"
    view.onTapped = {
        context.send(SearchEvent.clearHistory)
    }
}
.onHeaderTap { context in
    context.send(SearchEvent.clearHistory)
}
```

### 手写 Data Source 的 Registration Helper

常规 ListKit DSL 不需要手动注册 cell、header、footer 或 supplementary；`Row`、`Header`、
`Footer` 和 `SectionSupplementary` 会继续使用 ListKit 内部的 register + dequeue 流程。

如果页面仍在使用手写 `UICollectionViewDataSource`，或在 `ProviderRow` /
`ProviderSupplementary` 迁移逃生口中需要 UIKit registration object，可以使用 `.lk`
命名空间下的 helper。它们沿用 ListKit 的同名 nib 优先、否则 class fallback 规则：

```swift
let cellRegistration = collectionView.lk.cellRegistration(UserCell.self) { cell, _, user in
    cell.configure(user)
}

let headerRegistration = collectionView.lk.supplementaryRegistration(
    TitleHeaderView.self,
    ofKind: UICollectionView.elementKindSectionHeader
) { view, _, _ in
    view.titleLabel.text = "用户"
}
```

## 条件 Layout、Header/Footer 和背景装饰

`makeCompositionalLayout()` 只需要设置一次。后续通过 `apply` 条件切换 layout、
header/footer/supplementary 和背景装饰，ListKit 会自动注册 typed decoration 并在布局
metadata 变化后 invalidate 当前 layout：

```swift
collectionView.collectionViewLayout = adapter.makeCompositionalLayout()

adapter.apply {
    ListSection(.main) {
        ForEach(items, id: \.id) { item in
            Row(model: item, cell: ItemCell.self) { cell, item, _ in
                cell.configure(item)
            }
        }
    } layout: {
        if isGrid {
            GridLayout(columns: 2, spacing: 12)
        } else {
            ListLayout(spacing: 8)
        }
    } header: {
        if showHeader {
            Header(TitleHeaderView.self, id: "title") { view, _ in
                view.titleLabel.text = title
            }
            .layout(
                height: isCompact ? .absolute(36) : .estimated(64),
                pinned: isPinned
            )
        }
    } footer: {
        if showFooter {
            Footer(FooterView.self, id: "footer") { view, _ in
                view.configure()
            }
        }
    } background: {
        if showBackground {
            BackgroundDecoration(
                GroupBackgroundView.self,
                contentInsets: .init(top: 8, leading: 16, bottom: 8, trailing: 16)
            )
        }
    }
}
```

已有 header/footer 或自定义 supplementary 需要单独配置 layout 时，用 `supplementaryLayouts:` builder。新页面优先把 header/footer 的布局直接写在 `Header(...).layout(...)` 上；`supplementaryLayouts:` 主要用于旧调用逐步迁移或多个 kind 统一配置：

```swift
ListSection(.main) {
    Row(...)
} header: {
    Header(TitleHeaderView.self, id: "title") { view, _ in
        view.titleLabel.text = title
    }
} supplementaries: {
    SectionSupplementary("badge", BadgeView.self, id: "badge") { view, _ in
        view.configure()
    }
} supplementaryLayouts: {
    if isPinned {
        BoundarySupplementaryLayout(
            kind: UICollectionView.elementKindSectionHeader,
            height: .absolute(36),
            pinned: true
        )
    }
    if showBadge {
        ItemSupplementaryLayout(
            kind: "badge",
            anchor: .topTrailing,
            width: .absolute(16),
            height: .absolute(16)
        )
    }
}
```

需要复用已有 decoration kind 时，用 raw kind 入口；这种写法不自动注册 view：

```swift
ListSection(.main) { ... } background: {
    if showBackground {
        BackgroundDecoration(
            kind: UICollectionView.elementKindSectionBackgroundDecoration,
            contentInsets: .init(top: 8, leading: 16, bottom: 8, trailing: 16)
        )
    }
}
```

简单固定背景也可以继续使用 modifier：

```swift
ListSection(.main) { ... }
    .backgroundDecoration(
        GroupBackgroundView.self,
        contentInsets: .init(top: 8, leading: 16, bottom: 8, trailing: 16)
    )
```

## Diagnostics 和 Apply Options

增强入口适合调试刷新问题：

```swift
let result = adapter.apply(
    options: ListApplyOptions(
        transaction: .disabled,
        refreshStrategy: .diffableOnly,
        diagnostics: .init(mode: .warning)
    )
) {
    ListSection(.users) {
        ...
    }
}

print(result.summary.insertedSectionCount)
print(result.summary.deletedSectionCount)
print(result.summary.movedSectionCount)
print(result.summary.refreshIDChangedCount)
```

`insertedSectionCount`、`deletedSectionCount`、`movedSectionCount`、`keptSectionCount` 描述 Section 变化；不带 `Section` 的 `insertedCount`、`deletedCount`、`movedCount`、`keptCount` 只统计 Row。同一 Row 随 Section 整体移动不会重复计为 Row move；Row 跨 Section 则按原 Section delete、新 Section insert 统计。

## 动画事务

一次更新的 snapshot、outline、layout、Row 内容和滚动动画统一由 `ListTransaction` 描述。默认 `.automatic` 遵循系统 Reduce Motion；`.enabled` 表示明确强制动画，`.disabled` 则关闭动画。UIKit diffable 的具体 duration 和 curve 仍由系统决定：

```swift
let transaction = ListTransaction()
    .snapshotAnimation(.automatic)
    .outlineAnimation(.automatic)
    .layoutAnimation(.disabled)
    .contentAnimation(.automatic)
    .scrollAnimation(.automatic)
    .updatePolicy(.coalesceLatest)
    .scrollBehavior(
        .preserveVisiblePosition(
            of: ListScrollTarget(RowID.activityTitle, in: Section.activityTitle)
        )
    )

let result = await adapter.applyAndWait(transaction: transaction) {
    sections
}

print(result.summary.animation.completionState)
print(result.summary.animation.anchorCompensation)
```

高频状态更新可用 `.coalesceLatest`，旧的未完成更新会以 `.superseded` 结束；必须逐次提交时使用 `.serial`。相同 identity 的可见 Row 如需局部过渡，可在 Row 上声明：

```swift
Row(model: message, cell: MessageCell.self) { cell, message, _ in
    cell.configure(message)
}
.refreshID(message.version)
.refreshPolicy(.automaticVisible)
.contentTransition(.opacity)
```

需要等待 diffable、outline、layout、内容过渡全部结束时使用 `applyAndWait`；普通同步提交继续使用 `apply`。`ListApplySummary.animation` 会报告实际动画范围、内容过渡数量、滚动补偿、Reduce Motion 和最终完成状态。

DEBUG 默认会输出 apply summary。重复 section/row/supplementary identity 会先由 `ListDiagnostics` 报告，避免 diffable 抛出更难定位的异常。

Layout 相关 diagnostics 也会在 `apply` 或 compositional layout provider 期间暴露：

- 同一个 section 内同 kind supplementary view 多次声明会报告，因为 adapter 按 `kind + section` 查找，后声明的 view 会覆盖前者。
- 配置了 `boundarySupplementaryLayout` / `itemSupplementaryLayout` 但没有同 kind supplementary view 会报告；反过来 view 没有 layout 是合法配置，会使用默认 boundary layout。
- 同 kind 同时配置 boundary 和 item-level layout 会报告，最后一次 layout 配置获胜。
- grid columns 小于 1、尺寸非正数、spacing 为负数等不稳定 layout 参数会报告。
- `.layout("legacyID")` 使用 `makeCompositionalLayout()` 时需要提供 `fallback`；未提供或 `fallback` 返回 `nil` 会报告，并临时使用默认 list section 兜底，避免 layout provider 直接崩溃。

## 状态 Row 和 Selection

空态、加载态、错误态只描述 UI：

```swift
ListSection(.users) {
    if isLoading {
        ListStateRow.loading(LoadingCell.self) { cell, _ in
            cell.startAnimating()
        }
    } else if users.isEmpty {
        ListStateRow.empty(EmptyCell.self) { cell, _ in
            cell.titleLabel.text = "暂无用户"
        }
    }
}
```

选择态适合礼物、标签、用户选择：

```swift
ListSection(.gifts) {
    ForEach(gifts, id: \.id) { gift in
        Row(model: gift, cell: GiftCell.self) { cell, gift, _ in
            cell.configure(gift)
        }
        .selected(selectedGiftID == gift.id)
        .onSelectionChange { gift, isSelected, _ in
            store.updateSelection(gift.id, isSelected: isSelected)
        }
    }
}
.selectionMode(.single)
```

## Layout DSL 和 Supplementary Layout

ListKit 可以根据 section DSL 生成 compositional layout helper。adapter 不会自动接管
`collectionView.collectionViewLayout`，页面显式设置：

```swift
collectionView.collectionViewLayout = adapter.makeCompositionalLayout()
```

常见两列网格：

```swift
ListSection(.users) {
    ForEach(users, id: \.userID) { user in
        Row(model: user, cell: UserCell.self) { cell, user, _ in
            cell.configure(user)
        }
    }
}
.layout(.grid(columns: 2, spacing: 12))
.stickyHeader()
```

横向自适应标签：

```swift
ListSection(.history) {
    ForEach(history, id: \.self) { keyword in
        Row(model: keyword, cell: SearchHistoryCell.self) { cell, keyword, _ in
            cell.titleLabel.text = keyword
        }
    }
}
.layout(.horizontal(
    itemWidth: .estimated(20),
    itemHeight: .absolute(20),
    spacing: 8,
    contentInsets: .init(top: 0, leading: 14, bottom: 0, trailing: 14)
))
```

复杂布局逃生口：

```swift
ListSection(.custom) {
    ...
}
.layout(.custom(id: "custom-layout") { section, index, environment in
    makeCustomCompositionalSection()
})
```

同一个 section 的 layout 来源是互斥的，最后一次 layout API 调用获胜：`.layout("legacyID")`、
`.layout(.grid(...))` 和 `.layout(.custom(...))` 会互相清空旧来源。`layout: { ... }`
builder 也会用返回的 configuration 覆盖当前 section layout 来源。

旧的 `.layout("two-column-grid")` 仍保留，只写入 `layoutID`，适合复杂页面继续在外部做映射。
这类 section 需要使用 `adapter.makeCompositionalLayout(fallback:)`：

```swift
collectionView.collectionViewLayout = adapter.makeCompositionalLayout { section, index, environment in
    switch section.layoutID?.typed(String.self) {
    case "two-column-grid":
        return makeTwoColumnGridSection(environment: environment)
    default:
        return nil
    }
}
```

`adapter.makeCompositionalSection(for:)` 只支持内建 `ListSectionLayout` 和默认 list layout。
如果 section 使用 legacy `layoutID` 或 custom layout，请改用 `makeCompositionalLayout(fallback:)`。

Supplementary 可以单独声明 refresh policy：

```swift
let header = Supplementary(
    UICollectionView.elementKindSectionHeader,
    id: "users-header",
    view: TitleHeaderView.self
) { view, _ in
    view.titleLabel.text = "用户"
}
.refreshID(headerVersion)
.refreshPolicy(.whenRefreshIDChanges)

ListSection(.users) { ... }
    .supplementary(header)
```

Header/Footer 会自动生成 boundary supplementary layout。custom kind 默认也是 top boundary；
需要调整位置、尺寸或 zIndex 时使用显式 layout：

```swift
ListSection(.users) {
    ...
}
.supplementary("badge", BadgeView.self, id: "vip-badge") { view, _ in
    view.configure(text: "VIP")
}
.boundarySupplementaryLayout(
    kind: "badge",
    alignment: .topTrailing,
    width: .absolute(64),
    height: .absolute(28),
    zIndex: 5
)
```

角标要挂到每个 item 上时，用 item-level supplementary：

```swift
ListSection(.users) {
    ...
} layout: {
    GridLayout(columns: 2, spacing: 12)
} supplementaries: {
    SectionSupplementary("vip-dot", BadgeView.self, id: "vip-dot") { view, context in
        view.configure(count: badges[context.indexPath.item].count)
    }
    .refreshID(badgeVersion)
    .refreshPolicy(.whenRefreshIDChanges)
    .itemSupplementaryLayout(
        anchor: .topTrailing,
        width: .absolute(18),
        height: .absolute(18),
        fractionalOffset: CGPoint(x: 0.25, y: -0.25)
    )
}
```

## SwiftUI 风格交互、原生 List 与层级

Row 行为通过值语义 modifier 组合；section 决定整体选择模式，单行可以继续细化：

```swift
Row(model: user, id: \.id, cell: UserCell.self) { cell, user, _ in
    cell.configure(user)
}
.selectionDisabled(user.isUnavailable)
.focusable()
.selectionFollowsFocus()
.springLoadingEnabled()
.onHighlightChange { user, highlighted, _ in
    analytics.highlight(user.id, highlighted)
}
.onPrimaryAction { user, _ in
    router.open(user)
}
```

Collection swipe 必须使用 UIKit 原生 list layout。`leadingSwipeActions` / `trailingSwipeActions`
会被安装到 `UICollectionLayoutListConfiguration`，不是伪装成 collection delegate 方法：

```swift
collectionView.collectionViewLayout = adapter.makeCompositionalLayout(
    configuration: .init(interSectionSpacing: 12)
)

adapter.apply {
    ListSection(.inbox) {
        Row(model: message, id: \.id, cell: MessageListCell.self) { cell, message, _ in
            cell.configure(message)
        }
        .trailingSwipeActions { context in
            UISwipeActionsConfiguration(actions: [deleteAction(context.itemID)])
        }
    } layout: {
        UIKitListLayout(appearance: .insetGrouped, showsSeparators: true)
    }
}
```

层级列表使用 `DisclosureGroup` 构建 section snapshot。父节点 cell 应使用
`UICollectionViewListCell` 并显式添加 `.outlineDisclosure()`：

```swift
ListSection(.files) {
    DisclosureGroup(
        Row(folder.id, model: folder, cell: FolderCell.self) { cell, folder, _ in
            cell.configure(folder)
        }
        .outlineDisclosure(),
        isExpanded: expandedFolderIDs.contains(folder.id)
    ) {
        ForEach(folder.files, id: \.id) { file in
            Row(model: file, cell: FileCell.self) { cell, file, _ in
                cell.configure(file)
            }
        }
    }
} layout: {
    UIKitListLayout(appearance: .sidebar)
}
.onExpansionChange { identity, isExpanded in
    store.setExpanded(identity.rowID, isExpanded: isExpanded)
}
```

需要等待 diffable、层级 snapshot、selection 和可见刷新全部完成时，使用 `applyAndWait`；
需要无动画整体替换时选择 `.reloadData`：

```swift
let result = await adapter.applyAndWait(
    options: .init(transaction: .disabled, applicationMode: .reloadData)
) {
    makeSections()
}
print(result.summary)
```

`ListContext.identity` / `itemID` 是稳定身份，`indexPath` 只代表事件发生时的位置。adapter
也提供 `itemIdentity(at:)`、`indexPath(for:)`、`rowIdentifier(at:as:)` 和 `contains(_:)` 做双向查询。

## Delegate Forwarding

Adapter 会接管 UIKit delegate/data source。声明式 API 未覆盖的方法会动态转发；已覆盖的方法会先执行
ListKit 行为再调用转发对象：

```swift
adapter.collectionDelegate = self
adapter.scrollDelegate = self
adapter.layoutDelegate = self

tableAdapter.tableDelegate = self
tableAdapter.tableDataSource = self
```

原生 drag/drop 不强制包装进 DSL，可直接设置 `dragDelegate` / `dropDelegate`。

## iOS 模拟器测试

仓库提供只包含 `ExamplesTests` 的共享 Scheme，默认关闭测试并行和代码覆盖，避免运行单元测试时
额外构建 `ExamplesUITests`。测试脚本会优先复用已经启动的 iPhone/iPad；仅在没有可用的已启动设备时
启动一次模拟器，并在测试结束后保留它供下一次运行复用：

```bash
# 增量构建并运行全部 ExamplesTests
scripts/test-ios.sh

# 只运行一个 suite
scripts/test-ios.sh ExamplesTests/ListKitLayoutTests

# 代码没有变化时复用上一次构建产物
scripts/test-ios.sh --no-build ExamplesTests/ListKitLayoutTests
```

需要预构建后反复运行时，先执行 `scripts/test-ios.sh --prepare`，后续使用 `--no-build`。
可通过 `LISTKIT_SIMULATOR_ID=<UUID>` 固定设备；脚本不会主动 shutdown 或 erase 模拟器。

## CellKit 迁移对照

| CellKit | ListKit |
| --- | --- |
| `CollectionViewController` + `sections` + `apply` | `CollectionListAdapter.apply { ... }` |
| `CollectionViewCellItem` model conform | 业务 model 不需要 conform，直接传给 `Row(..., model:)` |
| `selectionHandler` | `.onSelect { context in ... }` |
| `CollectionViewSupplementary` | `.header(...)` / `.footer(...)` / `.supplementary(...)` |
| cell 内按钮闭包直连页面 | `context.send(MyEvent)` + `.onEvent(MyEvent.self)` |
| 手动注册 cell/header | ListKit 自动按 class/nib 注册 |

迁移期少量复杂旧 cell 可以用 `ProviderRow` 作为逃生口，但不要再包装成 App 级 provider/section DSL。长期代码应直接写 `ListSection`、`Row(model:id:cell:)`、`.refreshID`、`.onSelect` 和 `.header/.footer/.supplementary`。

## 当前边界

- `CollectionListAdapter` 继续承载 compositional layout、supplementary layout 和 background decoration。
- `TableListAdapter` 提供独立 Table DSL、diffable apply、cell/header/footer、selection、display、prefetch、高度、editing、move、context menu、UIKit swipe、可见刷新和 delegate forwarding。
- `SwipeCellKit` 不进入 ListKit package；使用第三方 swipe 的页面通过 App 层 bridge 或页面自管接入。
- FSPagerView 等业务型组件仍留在 App 层，ListKit 只负责列表描述、diff、刷新和事件分发。
