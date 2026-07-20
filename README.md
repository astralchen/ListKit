# ListKit

用声明式 DSL 驱动 `UICollectionView` 与 `UITableView` 的 UIKit 列表框架。

ListKit 让页面在数据变化时重新描述列表结构，再由 adapter 负责 diffable snapshot、复用视图注册、内容刷新和事件分发。业务 model 不需要遵守框架协议，也不需要手动维护 index path。

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
- 基于 diffable data source；用稳定业务 ID 描述变化，不让业务逻辑依赖位置。
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
- [条件内容与页面状态](#条件内容与页面状态)
- [Selection](#selection)
- [Layout 与 Supplementary](#layout-与-supplementary)
- [事件](#事件)
- [实时列表查询与可见刷新](#实时列表查询与可见刷新)
- [层级列表](#层级列表)
- [Apply、动画与滚动](#apply动画与滚动)
- [Diagnostics](#diagnostics)
- [自动注册与手写 Data Source](#自动注册与手写-data-source)
- [Adapter 所有权](#adapter-所有权)
- [示例与测试](#示例与测试)

## 环境要求

- iOS 14+
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

关键点是 adapter 必须由页面强引用；列表数据变化时只更新业务状态并再次调用 `render()`。

## UITableView 快速开始

Table 使用独立 DSL，避免把 collection-only API 暴露给 table 页面：

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

系统文字标题适合简单页面；需要自定义视图时使用 header/footer builder：

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

启用 reordering 时，页面仍需切换 table view 的 editing 状态：

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

同一个业务 ID 切换 cell 类型时，`Cell.self` 的变化会自然产生 delete + insert。需要用同一个 cell 类型表达多个展示分支时，可以用 `.variant(...)` 显式区分。

### Row ID 的几种写法

在 `ForEach` 内，Row 默认继承外层 ID，这是列表页面最常用的写法：

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

也可以通过 key path 或闭包明确指定业务身份：

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

### Refresh Policy

| Policy | 行为 |
| --- | --- |
| `.automaticVisible` | 默认策略；无 `refreshID` 时每次 apply 重配可见 cell，有 `refreshID` 时仅在版本变化后重配。 |
| `.whenRefreshIDChanges` | `refreshID` 变化时通过 diffable reconfigure/reload 刷新。 |
| `.never` | identity 不变时不主动刷新。 |
| `.alwaysVisible` | 每次 apply 都重配当前可见 cell。 |

iOS 15+ 使用 `reconfigureItems`；iOS 14 自动回退到 `reloadItems`。请保证同一 section 内的 Row ID 唯一，debug diagnostics 会报告重复身份。

Apply 级别还可以覆盖整批列表的刷新行为：

| Strategy | 行为 |
| --- | --- |
| `.automatic` | 根据每个 Row 的 policy 自动选择 diffable 或可见刷新。 |
| `.visibleOnly` | 不向 snapshot 写入 refresh 标记，只重配符合条件的可见节点。 |
| `.diffableOnly` | 只执行 `refreshID` 驱动的 diffable refresh。 |
| `.forceReload` | reload 所有新旧 snapshot 中都存在的 Row。 |

```swift
let options = ListApplyOptions(
    transaction: .automatic,
    refreshStrategy: .diffableOnly
)

adapter.apply(options: options) {
    makeSections()
}
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

## 条件内容与页面状态

Result builder 支持 `if`、`if let`、`switch` 和数组表达式。页面状态仍由业务层管理，ListKit 只负责描述当前应该显示什么：

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
.selectionMode(.single)
```

多选时使用 `.selectionMode(.multiple)`；只展示点击事件、不保留系统选中态时使用 `.selectionMode(.none)` 和 `.onSelect(...)`。键盘、鼠标和 tvOS 风格交互还可以组合 `.focusable()`、`.selectionFollowsFocus()`、`.onHighlightChange(...)` 与 `.onPrimaryAction(...)`。

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

需要让布局元数据和页面状态一起变化时，可以使用 `ListSection` 的 builders：

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

旧页面可以继续用 `.layout("legacy-id")` 保存布局标识，并在 fallback 中返回原来的 `NSCollectionLayoutSection`：

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

新页面优先使用 `.list(...)`、`.grid(...)`、`.horizontal(...)` 或 `.custom(...)`；fallback 主要用于渐进迁移。

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

Cell 内部产生的业务事件可以通过强类型路由统一交给页面处理：

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

## 实时列表查询与可见刷新

Adapter 保存的是当前已经提交的描述树，因此页面不需要额外维护一套 sections 来查询位置：

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
adapter.reconfigureVisibleRows(
    forRowID: seatID,
    in: .seats
)
```

内容变化会影响自适应高度或布局时，通过 diffable snapshot reload 可见节点：

```swift
adapter.reloadVisibleRows(
    forRowID: messageID,
    in: .messages
)
```

两者区别是：`reconfigureVisibleRows` 直接调用当前 Row 的配置闭包，不重新量高；`reloadVisibleRows` 会让 UIKit 重新创建/布局对应的可见节点。

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

展开状态由业务层保存。下一次 render 时继续把状态传给 `isExpanded`，即可保持声明式单向数据流。

## Apply、动画与滚动

普通页面使用 `apply`。需要等待 diffable、selection、可见刷新和滚动全部完成时，使用 `applyAndWait`：

```swift
let transaction = ListTransaction.automatic
    .scrollBehavior(.scrollToLast(in: Section.messages, position: .bottom))

let result = await adapter.applyAndWait(transaction: transaction) {
    makeMessageSections()
}

print(result.summary)
```

`ListTransaction` 可以分别控制 snapshot、outline、layout、content 和 scroll 动画，并默认遵循 Reduce Motion。连续 async apply 可以选择合并到最新状态或按调用顺序串行执行。

需要无动画整体替换或自定义刷新策略时，传入完整 options：

```swift
let options = ListApplyOptions(
    transaction: .disabled,
    refreshStrategy: .automatic,
    applicationMode: .reloadData
)

await adapter.applyAndWait(options: options) {
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

await adapter.applyAndWait(transaction: transaction) {
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

`apply` 会立即返回 result；`applyAndWait` 返回最终完成状态。摘要适合日志、性能观察和测试断言：

```swift
let result = await adapter.applyAndWait {
    makeSections()
}

let summary = result.summary
print("inserted:", summary.insertedCount)
print("deleted:", summary.deletedCount)
print("moved:", summary.movedCount)
print("refreshed:", summary.refreshIDChangedCount)
print("completion:", summary.animation.completionState)
```

如果较新的 `.coalesceLatest` apply 取代了尚未完成的旧 apply，旧结果会以 `.superseded` 结束；任务在提交前取消时会返回 `.cancelledBeforeCommit`。

## Diagnostics

默认配置会在 diffable apply 前检查重复 identity 和无效布局，问题存在时打印诊断并跳过本次提交，避免 UIKit 用难以定位的异常崩溃：

```swift
let options = ListApplyOptions(
    diagnostics: .init(mode: .warning, logsApplySummary: true)
)

let result = adapter.apply(options: options) {
    makeSections()
}

for issue in result.summary.diagnosticsIssues {
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

标准 `Row`、`TableRow`、header、footer 和 supplementary 都会自动注册 class 或同名 nib，不需要页面手动调用 `register`。

如果旧页面仍然使用手写 `UICollectionViewDataSource`，可以复用 `.lk` 命名空间中的类型安全 helper：

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

Adapter 会接管 UIKit 的 data source、delegate 与 prefetch data source。请将 adapter 作为页面的强引用属性保存；如果其他对象还需要接收未被 ListKit 覆盖的 delegate 回调，可以设置 forwarding delegate：

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
- `reconfigureVisibleRows(...)`：只更新当前可见节点。
- `ProviderRow` / `ListProviderSection`：逐步迁移复杂旧 data source 的逃生口。
- `ListDiagnosticsOptions` / `lastApplySummary`：定位重复 ID、无效 layout 和 apply 行为。

## 示例与测试

`Examples/` 包含 collection 与 table 两套完整页面，演示 layout、selection、事件、刷新、swipe、context menu 和 reordering。

运行 iOS Simulator 测试：

```bash
# 增量构建并运行 ExamplesTests
scripts/test-ios.sh

# 只运行一个 suite
scripts/test-ios.sh ExamplesTests/ListKitLayoutTests

# 复用上一次构建产物
scripts/test-ios.sh --no-build ExamplesTests/ListKitLayoutTests
```

可以通过 `LISTKIT_SIMULATOR_ID=<UUID>` 指定模拟器。

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
