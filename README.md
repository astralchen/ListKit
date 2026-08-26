# ListKit

用声明式 DSL 驱动 `UICollectionView` 与 `UITableView` 的 UIKit 列表框架。

ListKit 让调用方在数据变化时重新描述列表结构，再由 adapter 负责 diffable snapshot、复用视图注册、内容刷新和事件分发。Model 不需要遵守框架协议，也不需要手动维护 index path。

```swift
adapter.apply {
    ListSection(.users) {
        ForEach(users, id: \.id) { user in
            Row(model: user, cell: UserCell.self) { cell, user, _ in
                cell.configure(with: user)
            }
            .refreshID(user.version)
        }
    }
}
```

## 特性

- 同时支持 `UICollectionView` 和 `UITableView`，共享一致的 identity、刷新、事件与 apply 语义。
- 基于 diffable data source；用稳定 ID 描述变化，避免状态更新依赖位置。
- Swift result builder DSL，支持 `if`、`switch`、`ForEach`、状态 Row 和层级列表。
- 自动注册并类型安全地 dequeue cell、header 和 footer；同名 nib 会被自动发现。
- Collection 内置 list、grid、横向滚动、自定义 compositional layout、supplementary 和 section decoration。
- 支持 selection、prefetch、swipe、context menu、editing、move、focus、display 等 UIKit 交互。
- 支持 typed event、可见节点刷新、稳定身份查询、async apply、滚动事务和 diagnostics。

## 目录

- [安装](#安装)
- [UICollectionView 快速开始](#uicollectionview-快速开始)
- [UITableView 快速开始](#uitableview-快速开始)
- [Identity 与刷新](#identity-与刷新)
- [条件内容与视图状态](#条件内容与视图状态)
- [Selection](#selection)
- [Layout 与 Supplementary](#layout-与-supplementary)
- [事件](#事件)
- [实时列表查询与定向刷新](#实时列表查询与定向刷新)
- [层级列表](#层级列表)
- [Apply、动画与滚动](#apply动画与滚动)
- [Diagnostics](#diagnostics)
- [自动注册与手写 Data Source](#自动注册与手写-data-source)
- [Adapter 所有权](#adapter-所有权)
- [示例与测试](#示例与测试)

## 环境要求

- iOS 15+
- Swift 6.0+
- Swift Package Manager

## 安装

在 Xcode 的 **Package Dependencies** 中添加：

```text
https://github.com/astralchen/ListKit.git
```

或在 `Package.swift` 中声明：

```swift
dependencies: [
    .package(url: "https://github.com/astralchen/ListKit.git", from: "1.0.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "ListKit", package: "ListKit")
        ]
    )
]
```

然后在需要使用的文件中导入：

```swift
import ListKit
```

## UICollectionView 快速开始

先创建 collection view 和 adapter。Adapter 会接管 data source、delegate 与 prefetch data source：

```swift
enum Section: Hashable, Sendable {
    case users
}

private let collectionView = UICollectionView(
    frame: .zero,
    collectionViewLayout: UICollectionViewFlowLayout()
)

private lazy var adapter = CollectionListAdapter<Section>(
    collectionView: collectionView
)
```

如果使用 ListKit 的 layout DSL，将 adapter 生成的 compositional layout 显式赋给 collection view：

```swift
collectionView.collectionViewLayout = adapter.makeCompositionalLayout()
```

每次状态变化后重新构建列表描述：

```swift
func render(users: [User]) {
    adapter.apply {
        ListSection(.users) {
            ForEach(users, id: \.id) { user in
                Row(model: user, cell: UserCell.self) { cell, user, _ in
                    cell.configure(with: user)
                }
                .refreshID(user.version)
                .onSelect { user, _ in
                    openProfile(user)
                }
            }
        }
        .header(UsersHeaderView.self, id: "users-header") { header, _ in
            header.titleLabel.text = "Users"
        }
        .layout(.list(spacing: 8))
    }
}
```

`ForEach` 会把自己的 ID 传给内部 `Row`，因此上例不需要在 `Row` 上重复写 `id`。

### 完整 View Controller 骨架

下面展示 adapter 的持有方式、layout 初始化和 render 生命周期：

```swift
import UIKit
import ListKit

@MainActor
final class UsersViewController: UIViewController {
    enum Section: Hashable, Sendable {
        case users
    }

    private let collectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: UICollectionViewFlowLayout()
    )

    private lazy var adapter = CollectionListAdapter<Section>(
        collectionView: collectionView
    )

    private var users: [User] = [] {
        didSet {
            if isViewLoaded {
                render()
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        collectionView.collectionViewLayout = adapter.makeCompositionalLayout()
        render()
        loadUsers()
    }

    private func render() {
        adapter.apply {
            ListSection(.users) {
                ForEach(users, id: \.id) { user in
                    Row(model: user, cell: UserCell.self) { cell, user, _ in
                        cell.configure(with: user)
                    }
                    .refreshID(user.version)
                    .onSelect { [weak self] user, _ in
                        self?.showUser(user)
                    }
                }
            }
            .layout(.list(itemHeight: .estimated(64), spacing: 8))
        }
    }
}
```

关键点是 adapter 必须由调用方强引用；列表数据变化时只更新数据源状态并再次调用 `render()`。

## UITableView 快速开始

Table 使用独立 DSL，与 collection-only API 保持隔离：

```swift
enum Section: Hashable, Sendable {
    case messages
}

private let tableView = UITableView(frame: .zero, style: .insetGrouped)
private lazy var adapter = TableListAdapter<Section>(tableView: tableView)

func render(messages: [Message]) {
    adapter.apply {
        TableSection(.messages) {
            TableForEach(messages, id: \.id) { message in
                TableRow(model: message, cell: MessageCell.self) { cell, message, _ in
                    cell.configure(with: message)
                }
                .refreshID(message.version)
                .height(.automatic(estimated: 64))
                .onSelect { message, _ in
                    openMessage(message)
                }
            }
        }
        .headerTitle("Messages")
    }
}
```

`TableRow` 还提供原生 table 能力，例如高度、editing、move、swipe actions、context menu 和 accessory button 回调。

### 自定义 Table Header / Footer

系统文字标题适合简单布局；需要自定义视图时使用 header/footer builder：

```swift
TableSection(.messages) {
    makeMessageRows()
} header: {
    TableHeader(MessagesHeaderView.self, id: "messages-header") { view, _ in
        view.configure(title: "Messages", unreadCount: unreadCount)
    }
    .refreshID(unreadCount)
    .height(.estimated(48))
} footer: {
    if hasMore {
        TableFooter(LoadingFooterView.self, id: "loading-footer") { view, _ in
            view.startAnimating()
        }
        .height(.fixed(44))
    }
}
```

### Table 编辑、移动与滑动操作

原生 table 行为可以直接声明在 `TableRow` 上：

```swift
TableRow(model: message, id: \.id, cell: MessageCell.self) { cell, message, _ in
    cell.configure(with: message)
}
.height(.automatic(estimated: 72))
.editing(.delete) { message, _, _ in
    store.delete(message.id)
}
.onMove { message, source, destination in
    store.move(message.id, from: source, to: destination)
}
.trailingSwipeActions { _ in
    let delete = UIContextualAction(style: .destructive, title: "删除") { _, _, finish in
        store.delete(message.id)
        finish(true)
    }
    return UISwipeActionsConfiguration(actions: [delete])
}
.contextMenu { _ in
    UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
        UIMenu(children: [
            UIAction(title: "复制") { _ in
                copyMessage(message)
            }
        ])
    }
}
```

启用 reordering 时，调用方仍需切换 table view 的 editing 状态：

```swift
tableView.setEditing(true, animated: true)
```

## Identity 与刷新

一个 Row 的展示身份由以下内容组成：

```text
sectionID + rowID + Cell.self + variant
```

`refreshID` 不参与 identity。它只表示“同一个 Row 的内容版本”，因此内容变化不会被误判成删除再插入：

```swift
Row(model: user, id: \.id, cell: UserCell.self) { cell, user, _ in
    cell.configure(with: user)
}
.refreshID(user.profileVersion)
.refreshPolicy(.whenRefreshIDChanges)
```

同一个 row ID 切换 cell 类型时，`Cell.self` 的变化会自然产生 delete + insert。需要用同一个 cell 类型表达多个展示分支时，可以用 `.variant(...)` 显式区分。

### Row ID 的几种写法

在 `ForEach` 内，Row 默认继承外层 ID，这是最常用的列表写法：

```swift
ForEach(users, id: \.userID) { user in
    Row(model: user, cell: UserCell.self) { cell, user, _ in
        cell.configure(with: user)
    }
}
```

单个固定功能 Row 可以直接使用语义 ID：

```swift
Row("banner", model: banners, cell: BannerCell.self) { cell, banners, _ in
    cell.configure(with: banners)
}
```

如果 model 遵守 `Identifiable`，可以自动使用 `model.id`：

```swift
Row(model: user, cell: UserCell.self) { cell, user, _ in
    cell.configure(with: user)
}
```

也可以通过 key path 或闭包明确指定稳定身份：

```swift
Row(model: user, id: \.userID, cell: UserCell.self) { cell, user, _ in
    cell.configure(with: user)
}

Row(
    model: user,
    id: { $0.userID.isEmpty ? $0.accountID : $0.userID },
    cell: UserCell.self
) { cell, user, _ in
    cell.configure(with: user)
}
```

不要使用数组下标、随机 UUID 或每次 render 都变化的值作为 Row ID，否则 diffable 无法判断移动和内容更新。

### 根据状态切换 Cell 类型

`Cell.self` 是 identity 的一部分，所以同一个用户从普通状态切换为 VIP 时，不需要手动拼接 ID：

```swift
ForEach(users, id: \.userID) { user in
    if user.isVIP {
        Row(model: user, cell: VIPUserCell.self) { cell, user, _ in
            cell.configure(with: user)
        }
    } else {
        Row(model: user, cell: NormalUserCell.self) { cell, user, _ in
            cell.configure(with: user)
        }
    }
}
```

如果两个分支使用同一种 Cell，但仍希望切换时执行 delete + insert，可以增加展示变体：

```swift
Row(model: user, id: \.userID, cell: UserCell.self) { cell, user, _ in
    cell.configure(with: user)
}
.variant(user.isVIP ? "vip" : "normal")
```

### 刷新决策

ListKit 将刷新拆成五层，避免把系统版本、触发时机和 Cell 生命周期混在一起：

| 层级 | 负责内容 | 选择方式 |
| --- | --- | --- |
| 触发 | 何时因一次 `apply` 刷新 kept identity | `refreshPolicy` |
| Action | 保留 Cell 重配，还是进入完整 reload/configuration 路径 | `refreshAction` |
| Layout | 重配后是否由 ListKit 主动重新测量 | `.reconfigure(layout:)` |
| Scope | 主动刷新全部匹配项，还是只刷新当前可见匹配项 | `scope: .allMatching / .visible` |
| 结构 | Cell 类型、`presentationID`、`variant` 或列表结构变化 | 重新 `apply`，由 diffable 执行 delete + insert |

#### Refresh Policy

| Policy | 行为 |
| --- | --- |
| `.automaticVisible` | 默认策略；无 `refreshID` 时每次 apply 重配可见 cell，有 `refreshID` 时仅在版本变化后重配。 |
| `.whenRefreshIDChanges` | `refreshID` 变化时通过 diffable reconfigure/reload 刷新。 |
| `.never` | identity 不变时不主动刷新。 |
| `.alwaysVisible` | 每次 apply 都重配当前可见 cell。 |

Policy 只决定触发时机。Row 默认 action 是 `.reconfigure(layout: .none)`：使用
`reconfigureItems` 保留现有 Cell，不进入 `prepareForReuse`，也不额外请求布局失效。
内容可能改变自适应尺寸时显式选择布局重测；确实需要完整 reload/configuration 路径时选择 reload：

```swift
Row(model: message, cell: MessageCell.self) { cell, message, _ in
    cell.configure(message)
}
.refreshID(message.version)
.refreshPolicy(.whenRefreshIDChanges)
.refreshAction(.reconfigure(layout: .invalidate))

ProviderRow(id: legacyID, presentationID: legacyPresentationID) { collectionView, indexPath, _ in
    legacyProvider.cell(in: collectionView, at: indexPath)
}
.refreshAction(.reload)
```

`reload` 请求 `reloadItems` 和完整 provider/configuration 路径，但 UIKit 不保证最终 Cell
对象地址一定变化。Cell 类型或展示变体变化不是 reload；必须改变 presentation identity 并
重新 `apply`。`ProviderRow` 改变 Cell 类型时也必须同步改变 `presentationID`。

请保证同一 section 内的 Row ID 唯一，debug diagnostics 会报告重复身份。

Apply 级别还可以覆盖整批列表的刷新行为：

| Strategy | 行为 |
| --- | --- |
| `.automatic` | 根据每个 Row 的 policy 自动选择 diffable 或可见刷新。 |
| `.visibleOnly` | 将自动刷新 scope 限制为可见项；仍尊重每个 Row 的 action。 |
| `.refreshIDChangesOnly` | 只处理 kept identity 中 `refreshID` 变化的 Row，并尊重其 action。 |
| `.reloadKeptRows` | 忽略 Row action，reload 所有新旧 snapshot 中都存在的 Row。 |

```swift
let options = ListApplyOptions(
    transaction: .automatic,
    refreshStrategy: .refreshIDChangesOnly
)

adapter.apply(options: options) {
    makeSections()
}
```

### 主动刷新层级

身份、`refreshID` 和 policy 都没有变化，但外部环境发生变化时，可以直接按所需粒度刷新：

| API | 行为 |
| --- | --- |
| `reconfigureRows(forRowID:in:scope:layout:)` | 保留 Cell 并重新配置；仅在 `layout: .invalidate` 时主动重测量。 |
| `reloadRows(forRowID:in:scope:)` | 通过 diffable `reloadItems` 进入完整 reload/configuration 路径。 |
| `reloadSections(_:)` | 通过 diffable `reloadSections` 刷新整个 section，包括 Row 和 header/footer/supplementary。 |
| `reloadAll()` | 基于当前已提交状态强刷全部内容、section 附属视图、索引标题和布局。 |

Row API 接受 row ID，不要求调用方构造 ListKit 内部的复合 identity；批量刷新使用
`forRowIDs:`。省略 section 时，同一 row ID 在所有 section 中的匹配项都会刷新：

```swift
adapter.reconfigureRows(forRowID: userID, in: .users)
adapter.reconfigureRows(
    forRowID: expandingMessageID,
    in: .messages,
    scope: .visible,
    layout: .invalidate
)
adapter.reloadRows(forRowIDs: changedMessageIDs, in: .messages, scope: .allMatching)
adapter.reloadSections([.profile, .settings])
```

同步返回值表示请求已提交或零匹配已完成；需要最终 matched/visible/reloaded 数量和
`.completed`、`.superseded`、`.cancelledBeforeCommit` 状态时，使用 completion 或 async 重载。
空输入和最终零匹配的 completion 也会在下一次 MainActor turn 恰好调用一次。

语言、LTR/RTL、Dynamic Type 或全局主题切换适合 `reloadAll`。先更新真正承载列表的
UIKit 环境，再触发刷新；默认使用 0.2 秒 cross-dissolve，并自动遵循 Reduce Motion：

```swift
collectionView.semanticContentAttribute = isRTL ? .forceRightToLeft : .forceLeftToRight

adapter.reloadAll()

// 需要等待过渡和布局完成：
let result = await adapter.reloadAll()
```

`reloadAll` 有意复用当前 diffable snapshot / outline 状态，不提交一份新的结构；内部调用
`reloadData()` 只会让 diffable data source 重新提供当前内容，不会修改 snapshot。ListKit
会避开正在提交的 snapshot 和 `hasUncommittedUpdates`，避免丢弃拖放或重排中的占位状态。

`reloadAll` 不会重新执行 section builder。如果旧描述树已经把本地化字符串保存成值，
请先更新 model，再使用 `apply` 重建 sections；配置闭包在执行时动态读取语言或主题时，
直接 `reloadAll` 即可。若不需要过渡，可显式关闭：

```swift
adapter.reloadAll(transaction: .disabled, transition: .identity)
```

### 内容过渡

同一个 identity 的可见 Cell 可以在重配时加入轻量淡入淡出：

```swift
Row(model: score, id: \.playerID, cell: ScoreCell.self) { cell, score, _ in
    cell.configure(with: score)
}
.refreshID(score.version)
.contentTransition(.opacity(duration: 0.18))
```

## 条件内容与视图状态

Result builder 支持 `if`、`if let`、`switch` 和数组表达式。视图状态仍由调用方管理，ListKit 只负责描述当前应该显示什么：

```swift
ListSection(.users) {
    if isLoading {
        ListStateRow.loading(LoadingCell.self) { cell, _ in
            cell.startAnimating()
        }
    } else if let error {
        ListStateRow.failure(ErrorCell.self) { cell, _ in
            cell.configure(message: error.localizedDescription)
        }
        .onSelect { _ in
            retry()
        }
    } else if users.isEmpty {
        ListStateRow.empty(EmptyCell.self) { cell, _ in
            cell.titleLabel.text = "暂无用户"
        }
    } else {
        ForEach(users, id: \.id) { user in
            Row(model: user, cell: UserCell.self) { cell, user, _ in
                cell.configure(with: user)
            }
        }
    }
}
```

Section 本身也可以按条件出现：

```swift
adapter.apply {
    if !pinnedUsers.isEmpty {
        ListSection(.pinned) {
            makeUserRows(pinnedUsers)
        }
    }

    ListSection(.allUsers) {
        makeUserRows(users)
    }
}
```

## Selection

Section 决定整体选择模式，Row 描述受控选择状态和回调：

```swift
ListSection(.gifts) {
    ForEach(gifts, id: \.id) { gift in
        Row(model: gift, cell: GiftCell.self) { cell, gift, _ in
            cell.configure(with: gift)
        }
        .selected(selectedGiftID == gift.id)
        .selectionDisabled(!gift.isAvailable)
        .onSelectionChange { gift, isSelected, _ in
            if isSelected {
                selectedGiftID = gift.id
            }
        }
    }
}
```

Section 默认使用 `.automatic`：声明了 `.onSelect(...)`、`.onDeselect(...)`、`.selected(...)`、`.onSelectionChange(...)`、`.selectionFollowsFocus()` 或 outline disclosure 的 Row 自动参与 section 内单选，纯展示 Row 不会进入选中态；外部 UIKit delegate 声明选择回调时也会自动启用。显式 `.selectionMode(.single)` 会让 section 内所有未禁用 Row 可选；多选使用 `.selectionMode(.multiple)`，系统多选手势需再声明 `.multipleSelectionInteraction()`；`.selectionMode(.none)` 会关闭选择及其回调。`.onHighlightChange(...)` 可以单独使用，包括在 `.selectionDisabled()` 的 Row 上；键盘、鼠标和 tvOS 风格交互还可以组合 `.focusable()` 与 `.onPrimaryAction(...)`。

## Layout 与 Supplementary

Collection section 可以直接声明常见布局：

```swift
ListSection(.photos) {
    ForEach(photos, id: \.id) { photo in
        Row(model: photo, cell: PhotoCell.self) { cell, photo, _ in
            cell.configure(with: photo)
        }
    }
}
.layout(.grid(
    columns: 2,
    spacing: 12,
    itemHeight: .estimated(180),
    contentInsets: .init(12)
))
```

内置布局包括：

- `.list(...)`：纵向列表。
- `.grid(...)`：固定列数网格。
- `.horizontal(...)`：横向滚动 section。
- `UIKitListLayout(...)`：原生 `UICollectionLayoutListConfiguration`，适合 swipe 与 outline。
- `.custom(...)`：直接生成 `NSCollectionLayoutSection` 的逃生口。

Header、footer 和自定义 supplementary 都属于 section 描述的一部分：

```swift
ListSection(.users) {
    makeUserRows()
}
.header(UsersHeaderView.self, id: "header") { view, _ in
    view.titleLabel.text = "Users"
}
.footer(LoadingFooterView.self, id: "footer") { view, _ in
    view.isLoading = isLoadingMore
}
.stickyHeader()
```

### 横向滚动 Section

标签、推荐卡片和最近访问记录可以使用横向布局：

```swift
ListSection(.recentSearches) {
    ForEach(keywords, id: \.self) { keyword in
        Row(model: keyword, cell: KeywordCell.self) { cell, keyword, _ in
            cell.titleLabel.text = keyword
        }
    }
}
.layout(.horizontal(
    itemWidth: .estimated(80),
    itemHeight: .absolute(36),
    spacing: 8,
    contentInsets: .init(top: 0, leading: 16, bottom: 0, trailing: 16),
    scrollingBehavior: .continuous
))
```

### 条件 Layout、Header 与背景

需要让布局元数据和视图状态一起变化时，可以使用 `ListSection` 的 builders：

```swift
ListSection(.dashboard) {
    ForEach(items, id: \.id) { item in
        Row(model: item, cell: DashboardCell.self) { cell, item, _ in
            cell.configure(with: item)
        }
    }
} layout: {
    if isGrid {
        GridLayout(columns: 2, spacing: 12)
    } else {
        ListLayout(itemHeight: .estimated(64), spacing: 8)
    }
} header: {
    if showHeader {
        Header(DashboardHeaderView.self, id: "dashboard-header") { view, _ in
            view.titleLabel.text = title
        }
        .layout(height: .estimated(52), pinned: true)
    }
} background: {
    if showBackground {
        BackgroundDecoration(
            CardBackgroundView.self,
            contentInsets: .init(top: 8, leading: 12, bottom: 8, trailing: 12)
        )
    }
}
```

Typed background decoration 会由 adapter 自动注册。使用 raw decoration kind 时，需要调用方先向 compositional layout 注册对应 view。

### Supplementary 的刷新与事件

Header/footer 也可以拥有独立的 `refreshID`、刷新策略和点击事件：

```swift
let header = Supplementary(
    UICollectionView.elementKindSectionHeader,
    id: "users-header",
    view: UsersHeaderView.self
) { view, _ in
    view.configure(title: title, onlineCount: onlineCount)
}
.refreshID(headerVersion)
.refreshPolicy(.whenRefreshIDChanges)
.onTap { _ in
    showAllUsers()
}

ListSection(.users) {
    makeUserRows()
}
.supplementary(header)
```

自定义 kind 默认可以作为 boundary supplementary；下面把角标挂到每个 item 的右上角：

```swift
ListSection(.users) {
    makeUserRows()
} supplementaries: {
    SectionSupplementary("online-badge", OnlineBadgeView.self, id: "online") { view, context in
        let user = users[context.indexPath.item]
        view.isOnline = user.isOnline
    }
    .refreshID(presenceVersion)
    .itemSupplementaryLayout(
        anchor: .topTrailing,
        width: .absolute(16),
        height: .absolute(16),
        fractionalOffset: CGPoint(x: 0.25, y: -0.25),
        zIndex: 2
    )
}
```

### 原生 UIKit List

Collection swipe actions、sidebar appearance 和 outline 应使用原生 list layout：

```swift
ListSection(.inbox) {
    ForEach(messages, id: \.id) { message in
        Row(model: message, cell: MessageListCell.self) { cell, message, _ in
            cell.configure(with: message)
        }
        .trailingSwipeActions { _ in
            let delete = UIContextualAction(style: .destructive, title: "删除") { _, _, finish in
                deleteMessage(id: message.id)
                finish(true)
            }
            return UISwipeActionsConfiguration(actions: [delete])
        }
    }
} layout: {
    UIKitListLayout(appearance: .insetGrouped, showsSeparators: true)
}
```

### 接入已有 Layout Provider

现有接入代码可以继续用 `.layout("legacy-id")` 保存布局标识，并在 fallback 中返回原来的 `NSCollectionLayoutSection`：

```swift
adapter.apply {
    ListSection(.products) {
        makeProductRows()
    }
    .layout("two-column-products")
}

collectionView.collectionViewLayout = adapter.makeCompositionalLayout { section, _, environment in
    switch section.layoutID?.typed(String.self) {
    case "two-column-products":
        return makeProductLayout(environment: environment)
    default:
        return nil
    }
}
```

新接入代码优先使用 `.list(...)`、`.grid(...)`、`.horizontal(...)` 或 `.custom(...)`；fallback 主要用于渐进迁移。

## 事件

简单事件可以直接挂在 Row 上：

```swift
Row(model: user, id: \.id, cell: UserCell.self) { cell, user, _ in
    cell.configure(with: user)
}
.onSelect { user, context in
    analytics.trackSelection(id: context.itemID)
    openProfile(user)
}
.onDisplay { cell, context in
    analytics.trackImpression(id: context.itemID)
}
```

Cell 内部产生的事件可以通过强类型路由统一交给调用方处理：

```swift
enum UserListEvent: ListEvent {
    case avatarTapped(userID: String)
}

adapter.onEvent(UserListEvent.self) { event, _ in
    switch event {
    case .avatarTapped(let userID):
        openProfile(userID)
    }
}

adapter.apply {
    ListSection(.users) {
        ForEach(users, id: \.id) { user in
            Row(model: user, cell: UserCell.self) { cell, user, context in
                cell.configure(with: user)
                cell.onAvatarTap = {
                    context.send(UserListEvent.avatarTapped(userID: user.id))
                }
            }
        }
    }
}
```

如果 cell 只需要把一个无参数动作转成事件，可以用 `onCellEvent` 减少绑定样板：

```swift
Row(model: user, id: \.id, cell: UserCell.self) { cell, user, _ in
    cell.configure(with: user)
}
.onCellEvent({ cell, send in
    cell.onAvatarTap = send
}, send: { user in
    UserListEvent.avatarTapped(userID: user.id)
})
```

展示和预取事件也可以直接拿到强类型 model：

```swift
Row(model: user, id: \.id, cell: UserCell.self) { cell, user, _ in
    cell.configure(with: user)
}
.onDisplay { cell, context in
    analytics.trackImpression(id: context.itemID)
    cell.startAnimation()
}
.onEndDisplay { cell, _ in
    cell.stopAnimation()
}
.onPrefetch { user, _ in
    imagePipeline.prefetch(user.avatarURL)
}
.onCancelPrefetch { user, _ in
    imagePipeline.cancelPrefetch(user.avatarURL)
}
```

`ListContext.identity` / `itemID` 是稳定身份；`indexPath` 只表示事件发生时的位置。跨刷新逻辑应优先保存 identity，而不是 index path。

## 实时列表查询与定向刷新

Adapter 保存的是当前已经提交的描述树，因此调用方不需要额外维护一套 sections 来查询位置：

```swift
let count = adapter.itemCount(in: .messages)
let indexPaths = adapter.indexPaths(forRowID: messageID, in: .messages)

if let indexPath = indexPaths.first,
   let identity = adapter.itemIdentity(at: indexPath) {
    print(identity)
    print(adapter.contains(identity))
}
```

轻量状态变化，例如倒计时、音量动画或在线状态，只重配当前可见 Cell：

```swift
adapter.reconfigureRows(
    forRowID: seatID,
    in: .seats,
    scope: .visible
)
```

内容变化会影响自适应高度或布局时，保留 Cell 重配并显式请求重新测量：

```swift
adapter.reconfigureRows(
    forRowID: messageID,
    in: .messages,
    scope: .visible,
    layout: .invalidate
)
```

需要完整 reload/provider 路径时使用 `reloadRows(..., scope: .visible)`；这不承诺 Cell
对象地址一定改变。非目标 Cell 不会被标记为 reconfigure/reload。

Supplementary 也支持按 kind 或关联 Row ID 做可见重配：

```swift
adapter.reconfigureVisibleSupplementaries(
    ofKind: UICollectionView.elementKindSectionHeader,
    in: .messages
)
```

## 层级列表

Collection 使用 `DisclosureGroup` 或 `OutlineGroup` 构建 diffable section snapshot。父节点 Cell 应继承 `UICollectionViewListCell`，并使用 `.outlineDisclosure()` 显示系统展开图标：

```swift
ListSection(.files) {
    ForEach(folders, id: \.id) { folder in
        DisclosureGroup(
            Row(model: folder, cell: FolderCell.self) { cell, folder, _ in
                cell.configure(with: folder)
            }
            .outlineDisclosure(),
            isExpanded: expandedFolderIDs.contains(folder.id)
        ) {
            ForEach(folder.files, id: \.id) { file in
                Row(model: file, cell: FileCell.self) { cell, file, _ in
                    cell.configure(with: file)
                }
            }
        }
    }
} layout: {
    UIKitListLayout(appearance: .sidebar)
}
.selectionMode(.single)
.onExpansionChange { identity, isExpanded in
    guard let folderID = identity.rowID.typed(Folder.ID.self) else { return }
    store.setExpanded(folderID, isExpanded: isExpanded)
}
```

展开状态由调用方保存。下一次 render 时继续把状态传给 `isExpanded`，即可保持声明式单向数据流。

## Apply、动画与滚动

常规更新使用同步 `apply`。需要等待 diffable、selection、可见刷新和滚动全部完成时，
使用 async `apply`：

```swift
let transaction = ListTransaction.automatic
    .scrollBehavior(.scrollToLast(in: Section.messages, position: .bottom))

let summary = await adapter.apply(transaction: transaction) {
    makeMessageSections()
}

print(summary)
```

`ListTransaction` 可以分别控制 snapshot、outline、layout、content 和 scroll 动画，并默认遵循 Reduce Motion。连续 async apply 可以选择合并到最新状态或按调用顺序串行执行。

需要无动画整体替换或自定义刷新策略时，传入完整 options：

```swift
let options = ListApplyOptions(
    transaction: .disabled,
    refreshStrategy: .automatic,
    applicationMode: .reloadData
)

await adapter.apply(options: options) {
    makeSections()
}
```

### 常用 Transaction

首次加载禁用所有动画：

```swift
adapter.apply(transaction: .disabled) {
    makeSections()
}
```

插入历史消息时保持某条可见消息在 viewport 中的位置：

```swift
let transaction = ListTransaction.automatic
    .scrollBehavior(
        .preserveVisiblePosition(
            of: ListScrollTarget(anchorMessageID, in: Section.messages)
        )
    )

await adapter.apply(transaction: transaction) {
    makeMessageSections()
}
```

连续更新必须严格按顺序完成时使用 serial；默认 `.coalesceLatest` 更适合高频实时状态：

```swift
let transaction = ListTransaction.automatic
    .updatePolicy(.serial)
    .snapshotAnimation(.disabled)
    .contentAnimation(.enabled)
```

### Apply Summary

`apply` 会立即返回 summary，这时 `summary.animation.completionState` 通常是 `.submitted`，
用于观察本次提交计划。需要最终可见刷新、layout、滚动和内容过渡统计时，使用 completion
或 async `apply`。摘要适合日志、性能观察和测试断言，不应替代数据源状态：

```swift
let summary = await adapter.apply {
    makeSections()
}

print("inserted rows:", summary.insertedRowCount)
print("deleted rows:", summary.deletedRowCount)
print("moved rows:", summary.movedRowCount)
print("refreshID changed rows:", summary.refreshIDChangedCount)
print("visible refreshed rows:", summary.visibleRefreshCount)
print("completion:", summary.animation.completionState)
```

如果较新的 `.coalesceLatest` apply 取代了尚未完成的旧 apply，旧结果会以 `.superseded` 结束；任务在提交前取消时会返回 `.cancelledBeforeCommit`。
`refreshIDChangedCount` 表示新旧 snapshot 都存在且 refreshID 变化的 Row 数量；
`snapshotRefreshCount` 表示按当前 refresh strategy 交给 diffable reload/reconfigure 的 Row 数量；
`visibleRefreshCount` 表示最终阶段实际重新配置的可见 Row 数量。
Collection supplementary view 与 Table header/footer 会统一计入 supplementary refresh 统计。

## Diagnostics

默认配置会在 diffable apply 前检查重复 identity 和无效布局，问题存在时打印诊断并跳过本次提交，避免 UIKit 用难以定位的异常崩溃：

```swift
let options = ListApplyOptions(
    diagnostics: .init(mode: .warning, logsApplySummary: true)
)

let summary = adapter.apply(options: options) {
    makeSections()
}

for issue in summary.diagnosticsIssues {
    print(issue.kind, issue.message)
}
```

会被检查的问题包括：

- 重复 section ID、Row identity 或 supplementary identity。
- 同一 section 内重复的 supplementary kind。
- supplementary layout 没有匹配的 view。
- 同一个 kind 同时声明 boundary 与 item-level layout。
- grid 列数小于 1、负 spacing、非正尺寸。
- legacy layout ID 没有被 fallback 解析。

调试期希望立即停在问题现场时使用 `.assertion`；完全关闭检查可以使用 `.disabled`。

## 自动注册与手写 Data Source

标准 `Row`、`TableRow`、header、footer 和 supplementary 都会自动注册 class 或同名 nib，不需要调用方手动调用 `register`。

如果现有代码仍然使用手写 `UICollectionViewDataSource`，可以复用 `.lk` 命名空间中的类型安全 helper：

```swift
let cellRegistration: UICollectionView.CellRegistration<UserCell, User> = collectionView.lk.cellRegistration(
    UserCell.self
) { cell, _, user in
    cell.configure(with: user)
}

let headerRegistration = collectionView.lk.supplementaryRegistration(
    UsersHeaderView.self,
    ofKind: UICollectionView.elementKindSectionHeader
) { view, _, _ in
    view.titleLabel.text = "Users"
}
```

Table 也提供同样的注册和 dequeue helper：

```swift
tableView.lk.register(UserTableCell.self)
tableView.lk.registerHeaderFooter(UsersTableHeaderView.self)

let cell: UserTableCell = tableView.lk.dequeue(UserTableCell.self, for: indexPath)
```

## Adapter 所有权

Adapter 会接管 UIKit 的 data source、delegate 与 prefetch data source。请由调用方强引用 adapter；如果其他对象还需要接收未被 ListKit 覆盖的 delegate 回调，可以设置 forwarding delegate：

```swift
adapter.collectionDelegate = self
adapter.scrollDelegate = self
adapter.layoutDelegate = self

tableAdapter.tableDelegate = self
tableAdapter.tableDataSource = self
```

Collection 的原生 drag/drop 仍可直接使用 `dragDelegate` 与 `dropDelegate`。

## 进阶能力

- `ListStateRow`：描述 loading、empty 和 error 状态。
- `DisclosureGroup` / `OutlineGroup`：生成 collection section snapshot 层级。
- `selected(...)` / `selectionMode(...)`：声明单选、多选和受控选择状态。
- `itemIdentity(at:)`、`indexPath(for:)`、`indexPaths(forRowID:in:)`：稳定身份与位置双向查询。
- `reconfigureRows(..., scope: .visible)`：只更新当前可见匹配节点。
- `ProviderRow` / `ProviderSupplementary`：逐步迁移复杂旧 data source 的逃生口。
- `ListDiagnosticsOptions` / `lastApplySummary`：定位重复 ID、无效 layout 和 apply 行为。

## 示例与测试

`Examples/` 包含 collection 与 table 两套完整示例，演示 layout、selection、事件、刷新、swipe、context menu 和 reordering。

ListKit 是 iOS/UIKit 框架，有效验收项是 iOS Simulator 或 generic iOS Simulator 的
`xcodebuild`。裸跑 `swift test` 会走 macOS SwiftPM 构建路径，macOS target 没有
UIKit，因此 `no such module 'UIKit'` 不作为 ListKit 的有效失败信号。

编译 iOS 测试目标：

```bash
xcodebuild -quiet \
  -project Examples/Examples.xcodeproj \
  -scheme ExamplesUnitTests \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/ListKitDerivedData \
  build-for-testing
```

运行 iOS Simulator 测试：

```bash
xcodebuild -quiet \
  -project Examples/Examples.xcodeproj \
  -scheme ExamplesUnitTests \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=26.5' \
  -derivedDataPath /tmp/ListKitDerivedData \
  test
```

可以通过 `xcrun simctl list devices available` 查看本机可用模拟器，并按实际安装的
设备名和系统版本替换 `-destination`。

读取最近一次测试摘要：

```bash
xcrun xcresulttool get test-results summary \
  --path /tmp/ListKitDerivedData/Logs/Test/<Test-ExamplesUnitTests-*.xcresult>
```

## 源码结构

```text
Sources/ListKit/
├── Core/         Identity、events、diagnostics 与 apply core
├── DSL/          Row、section、supplementary 与 builders
├── Reusable/     自动注册与类型安全 dequeue
├── Collection/   UICollectionView adapter 与 layout DSL
└── Table/        UITableView adapter 与 Table DSL
```

## License

ListKit 基于 MIT License 发布，详见 [LICENSE](LICENSE)。
