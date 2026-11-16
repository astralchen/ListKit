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

将 **Dependency Rule** 设置为 **Branch**，分支填写 `main`。

或在 `Package.swift` 中声明：

```swift
dependencies: [
    .package(url: "https://github.com/astralchen/ListKit.git", branch: "main")
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
    let title = "users-title"
    adapter.apply {
        ListSection(.users) {
            ForEach(users, id: \.id) { user in
                Row(model: user, cell: UserCell.self) { cell, user, _ in
                    cell.configure(with: user)
                }
                .refreshID(user.version)
                .onSelect { user, _ in openProfile(user) }
            }
        } layout: {
            GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(8).lineSpacing(8).boundarySupplementaries {
                BoundarySupplementaryLayout(
                    kind: title,
                    size: .init(width: .fractionalWidth(1), height: .estimated(44)),
                    alignment: .top
                )
            }
        } supplementaries: {
            SectionSupplementary(UsersHeaderView.self, kind: title) { view, _ in
                view.titleLabel.text = "Users"
            }
        }
    }
}
```

`ForEach` 会把自己的 ID 传给内部 `Row`，因此上例不需要在 `Row` 上重复写 `id`。

Collection 附属视图的 `kind:` 与布局中的边界元素或 item 徽章对应。同一 Section、同一业务 kind 和视图类型默认复用内容身份。用 `.refreshID(...)` 更新同一份内容；需要替换同一 kind 的业务对象时才传 `elementID:`。这也适用于可独立组合的 `Supplementary` 和自定义 `ProviderSupplementary`。旧的 `id:` 可迁移为 `elementID:`，固定的占位 ID 可以直接省略。

如果公共属性或函数需要写出省略 ID 后的返回类型，可使用 `Supplementary<DefaultSupplementaryID, BadgeView>` 或 `ProviderSupplementary<DefaultSupplementaryID>`。已有的 `DefaultCollectionSupplementaryID` 类型名仍然可用。

### Section 组合方式

保留上面的多闭包写法，也可以用对称的链式入口组织同一份 Section：

```swift
let titleKind = "title"
let section = ListSection(0) {
    Row(0, model: "Hello", cell: UICollectionViewCell.self) { _, _, _ in }
}
.layout {
    GridLayout(tracks: 1)
        .itemMainAxisSize(.estimated(44))
        .boundarySupplementaries {
            BoundarySupplementaryLayout(
                kind: titleKind,
                size: .init(width: .fractionalWidth(1), height: .absolute(36)),
                alignment: .top
            )
        }
}
.supplementaries {
    SectionSupplementary(
        UICollectionReusableView.self, kind: titleKind
    ) { view, _ in
        view.accessibilityLabel = "Messages"
    }
}
.decorations {
    SectionDecoration(UICollectionReusableView.self, kind: "card")
}
```

- `.layout { }` 替换完整布局；`.supplementaries { }`、`.decorations { }` 替换对应集合。
- `.addingSupplementaries { }`、`.addingDecorations { }` 按顺序追加；重复 kind 仍会诊断，不静默覆盖。
- 空的集合设置清空集合，空的追加保留集合；内容改变不改写显式布局，缺失必需绑定仍会诊断。
- 可将 rows 提取为返回 `RowGroup` 的方法，将布局提取为值，将 header 提取为接收当前数据的方法。消息列表示例展示了这种组合。
- `whenContentExists()` 判断对应内容／注册声明是否存在，不判断 rows 是否为空。无条件绑定时无需添加。

迁移：旧的 `.addingSectionSupplementaries { }` 已移除，请改用 `.addingSupplementaries { }`。详见 [Section 组合规则](Documentation/Layout-API.md#section-的三种组合方式)。

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
            } layout: { GridLayout(tracks: 1).itemMainAxisSize(.estimated(64)).trackSpacing(8).lineSpacing(8) }
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
                .onSelect { message, _ in
                    openMessage(message)
                }
            }
        }
        .headerTitle("Messages")
        .layout { TableLayout().rowHeight(.estimated(64)) }
    }
}
```

`TableRow` 还提供原生 table 能力，例如 editing、move、swipe actions、context menu 和 accessory button 回调。

### 自定义 Table Header / Footer

系统文字标题适合简单布局；需要自定义视图时使用 header/footer builder：

```swift
TableSection(.messages) {
    makeMessageRows()
}
.layout {
    TableLayout()
        .rowHeight(.estimated(64))
        .headerHeight(.estimated(48))
        .footerHeight(.fixed(44))
}
.header {
    TableHeader(MessagesHeaderView.self) { view, _ in
        view.configure(title: "Messages", unreadCount: unreadCount)
    }
    .refreshID(unreadCount)
}
.footer {
    if hasMore {
        TableFooter(LoadingFooterView.self) { view, _ in
            view.startAnimating()
        }
    }
}
```

页眉和页脚默认按分区、角色和视图类型确定身份。省略 `elementID` 时，两者的 `context.itemID` 都是与 Collection 共用的 `DefaultSupplementaryID` 标记。要区分两个展示元素，应比较完整的 `context.identity`；需要从回调取回业务 ID 时，显式传入 `elementID`。上例未读数发生变化时，`.refreshID(unreadCount)` 让同一页眉更新内容。若同一分区使用相同视图类型展示不同账户，且切换账户时需要替换页眉，可以写 `TableHeader(ProfileHeaderView.self, elementID: account.id)`。从旧版迁移时，固定的 `id:` 通常可以省略；有意控制替换的业务 ID 改用 `elementID:`。

和 `ListSection` 一样，可以从 rows 开始，链式调用 `.layout { … }`、`.header { … }`、`.footer { … }`，也可以使用初始化器的 `layout:`、`header:`、`footer:` 闭包。两种写法可以混用；每次调用只替换对应声明。`.header {}` 或 `.footer {}` 会清除对应的自定义视图，此时仍可显示已设置的系统标题。

编译器会检查角色：`.header` 只接受 `TableHeader`，`.footer` 只接受 `TableFooter`。单独封装时，返回类型分别写作 `TableSectionHeader<SectionID>` 和 `TableSectionFooter<SectionID>`。系统标题的增删和文字变更会随 `apply` 更新；已声明自定义视图，或 UIKit 实际从外部代理取得了该角色的视图时，修改备用标题不会触发分区重载。代理返回 `nil` 时，该角色按系统标题更新。

`TableLayout` 作用于当前 Section。`.rowHeight(.estimated(64))` 让每行先按 64 点估算，再根据各自的内容测量实际高度。自定义视图和系统标题都使用分区的页眉、页脚规则；上例在 `hasMore == false` 时不会因为 `.footerHeight(.fixed(44))` 而预留 44 点。

| 高度规则 | 实际高度 | 估算高度 |
| --- | --- | --- |
| `.fixed(28)` | 28 点 | 28 点 |
| `.automatic` | UIKit 按内容测量 | UIKit 自动估算 |
| `.estimated(64)` | UIKit 按内容测量 | 64 点 |

同一分区可以在 `rowHeight` 闭包里按稳定行 ID 选择规则。例如，时间分隔行固定为 28 点，其余消息先按 68 点估算：

```swift
enum ChatRowID: Hashable, Sendable {
    case divider
    case message(Int)
}

TableSection(0) {
    TableRow(ChatRowID.divider, model: "今天", cell: TimeDividerCell.self) { cell, title, _ in
        cell.configure(title: title)
    }
    for message in messages {
        TableRow(ChatRowID.message(message.id), model: message, cell: MessageCell.self) { cell, message, _ in
            cell.configure(with: message)
        }
    }
}
.layout {
    TableLayout().rowHeight { id in
        id.typed(ChatRowID.self) == .divider ? .fixed(28) : .estimated(68)
    }
}
```

闭包收到的是该行实际使用的 ID。上例显式传入 `ChatRowID.message(message.id)`，所以即使 `Message` 遵守 `Identifiable`，也可以用 `typed(ChatRowID.self)` 匹配消息。直接写 `TableRow(model:cell:)` 时，`Identifiable` 模型优先使用 `model.id`；使用继承 ID 的初始化器时才取外层 `TableForEach` 的 ID。

每次执行 `apply` 或 `reloadAll`，adapter 都为每行求值一次，实际高度与估算高度共用该结果。行高闭包中同步发起的 `apply` 按当前更新策略入队。统一规则和闭包可以互相替换，最后一次 `rowHeight` 调用生效。

实际行高与估算行高分别按「分区的 `rowHeight` → 外部 delegate 对应方法 → UITableView 对应属性」解析。页眉、页脚仅在声明了相应视图或标题时使用分区高度，其他情况沿用 delegate 和表格默认值。再次 `apply` 改变已有内容的高度规则时，adapter 会重新测量布局，即使内容的 `refreshID` 相同。

**从旧版高度 API 迁移**

| 旧声明 | 新声明 |
| --- | --- |
| `TableRowHeight` | 共用的 `TableHeight` |
| `.automatic()` / `.automatic(estimated: 64)` | `.automatic` / `.estimated(64)` |
| 整个分区原本都使用 `.height(.estimated(68))` | 在所属分区声明一次 `.layout { TableLayout().rowHeight(.estimated(68)) }` |
| 原来只有个别行用 `.height(...)` 覆盖分区规则 | 使用上例的 `.rowHeight { id in … }`，匹配例外行，其余行返回原分区规则 |
| `TableHeader.height(...)` / `TableFooter.height(...)` | 分区布局的 `.headerHeight(...)` / `.footerHeight(...)` |
| 单行 `.estimatedHeight(64)` | 在 `rowHeight` 闭包里为对应 ID 返回 `.estimated(64)`，并保留其余行的原规则 |

`rowHeight` 闭包必须为每个 ID 返回一个 `TableHeight`。如果原来只有个别行声明高度，其余行依赖 delegate 或表格默认值，应省略该分区的 `rowHeight`，在 delegate 的 `heightForRowAt` 和 `estimatedHeightForRowAt` 中处理例外行，并让其余行沿用原有计算或返回对应的 `UITableView` 默认值。

### Collection 上下文菜单

演示入口：**Room Toolkit → 右上角 More Actions → Context Menu APIs**。
页面提供原卡片高亮和内容预览两种模式，并显示触发坐标、configuration 标识、
高亮／收起预览、显示／结束及动画完成日志。点击内容预览可验证 commit，
选择 Record Action 可对比菜单操作与预览提交；Clear Log 清空日志但不重置菜单编号。

Collection Row 可以获取触发位置、当前菜单配置以及显示、结束和预览提交回调：

```swift
Row(model: message, id: \.id, cell: MessageCell.self) { cell, message, _ in
    cell.configure(message)
}
.contextMenu { context, point in
    // point 使用 collection view 的坐标系。
    UIContextMenuConfiguration(
        identifier: message.id.uuidString as NSString,
        previewProvider: { MessagePreviewController(message: message) }
    ) { _ in
        UIMenu(children: [
            UIAction(title: "复制") { _ in
                UIPasteboard.general.string = message.text
            }
        ])
    }
}
.contextMenuPreview(
    highlighting: { context, configuration in
        guard let collectionView = context.collectionViewIfAvailable,
              let cell = collectionView.cellForItem(at: context.indexPath),
              cell.window != nil else { return nil }
        return UITargetedPreview(view: cell)
    },
    dismissal: { context, configuration in
        guard let collectionView = context.collectionViewIfAvailable,
              let cell = collectionView.cellForItem(at: context.indexPath),
              cell.window != nil else { return nil }
        return UITargetedPreview(view: cell)
    }
)
.onContextMenuWillDisplay { context, configuration, animator in
    // 可用 animator?.addAnimations / addCompletion 参与显示过渡。
}
.onContextMenuCommit { context, configuration, animator in
    animator.addCompletion {
        openMessage(message)
    }
}
.onContextMenuWillEnd { context, configuration, animator in
    // 释放业务持有的预览资源；需要等待收起完成时，使用 addCompletion。
    // animator 为 nil 时直接完成相应清理。
}
```

示例中的 `MessageCell`、`MessagePreviewController` 和 `openMessage` 由业务提供。旧的单参数
`.contextMenu`、`.contextMenuPreview` 及双参数 `.onContextMenuCommit` 继续可用。
重复设置同一种回调时以后一次为准；调用 `contextMenuPreview` 会同时替换两个预览提供者，
仅设置 `dismissal` 时会清除原有 highlighting。所有闭包均在主线程执行。

**系统版本：** ListKit 最低要求仍为 iOS 15。原生单项配置、高亮和收起预览代理方法从
iOS 13.0 引入、iOS 16.0 弃用；显示与结束通知从 iOS 13.2 引入。adapter 在 iOS 16+
使用新的多项配置及逐项预览入口，Row DSL 跨版本保持一致，无需由调用方分支选择。

**转发顺序：** iOS 15 配置请求依次查询 Row、原生旧代理；iOS 16+ 依次查询
`contextMenuForItems`、首个目标 Row、原生代理。DSL provider 返回 `nil` 时继续查询下一级。
原生代理实现新版回调时，其返回值（包括 `nil`）直接生效；仅在未实现对应新版回调时，
才回退旧版回调。菜单配置返回 `nil` 阻止菜单交互，预览返回 `nil` 交由系统处理。
空白区域没有 Row，仅查询多项 provider 和原生新代理。预览先查询匹配 Row，
未提供预览时按上述规则查询原生代理。
显示、结束和 commit 通知先调用 Row，再调用 `collectionDelegate`。多项菜单的逐项预览
各自分发，生命周期和 commit 仅通知首个目标 Row。

**会话与刷新：** adapter 按 configuration 对象身份关联菜单，不修改业务 identifier。
回调使用创建菜单时捕获的 Row，位置按稳定 identity 更新；行被删除后跳过 Row 预览及 commit，
显示／结束生命周期仍可收到原始 context，此时 `indexPath` 可能已失效，不应直接据此操作 cell。
菜单会话保留到结束动画完成；无 animator 时在结束通知后释放。未展示且 configuration 已释放的
会话会在后续菜单请求时清扫。业务闭包应避免强持有页面或 adapter；重复请求应创建新的 configuration 对象。

### Table 编辑、移动与滑动操作

原生 table 行为可以直接声明在 `TableRow` 上：

```swift
TableRow(model: message, id: \.id, cell: MessageCell.self) { cell, message, _ in
    cell.configure(with: message)
}
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
.refresh(when: .refreshIDChanges)
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

需要把一组 Row 封装成可复用函数或属性时，直接使用公开的 `RowGroup`；Table DSL 使用独立的
`TableRowGroup`，不需要再定义一层组件协议：

```swift
func accountRows(_ account: Account) -> RowGroup {
    RowGroup {
        Row("profile", model: account, cell: ProfileCell.self) { cell, account, _ in
            cell.configure(account)
        }
        Row("settings", model: account, cell: SettingsCell.self) { cell, account, _ in
            cell.configure(account)
        }
    }
}
```

`ListSection.rows`、`outlineRoots`、`supplementaries` 以及 Table 对应存储可从外部模块只读检查；
写入仍由 builder 和 ListKit 内部维护。

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

ListKit 将 Row 刷新拆成彼此正交的 trigger、scope、action 和 layout：

| 层级 | 负责内容 | 选择方式 |
| --- | --- | --- |
| Trigger | 何时因一次 `apply` 刷新 kept identity | `ListRefreshTrigger` |
| Action | 保留 Cell 重配，还是进入完整 reload/configuration 路径 | `ListRowRefreshAction` |
| Layout | 重配后是否由 ListKit 主动重新测量 | `.reconfigure(layout:)` |
| Scope | 通过 snapshot 刷新全部匹配项，还是只直接刷新当前可见项 | `.allMatching / .visible` |
| 结构 | Cell 类型、`presentationID`、`variant` 或列表结构变化 | 重新 `apply`，由 diffable 执行 delete + insert |

#### Refresh Trigger

| Trigger | 行为 |
| --- | --- |
| `.automatic` | 默认；未设置 `refreshID` 时每次 apply 刷新，设置后仅在值变化时刷新。 |
| `.refreshIDChanges` | 仅当新旧 `refreshID` 不相等时刷新。`nil ↔ value` 也属于变化。 |
| `.everyApply` | identity 保持不变时每次 apply 都刷新。 |
| `.never` | identity 不变时不主动刷新。 |

`refreshID` 始终独立于 presentation identity。默认 Row 规则为
`.automatic + .visible + .reconfigure(layout: .none)`。`.visible` reconfigure 直接配置当前 Cell；
visible reload 只筛选当前可见 identity，但由于 diffable data source 禁止直接调用列表 mutation API，
仍通过 snapshot `reloadItems` 提交，动画来自 `contentAnimation`。`.allMatching` 使用 snapshot `reconfigureItems/reloadItems`，
动画来自 `snapshotAnimation`。内容可能改变自适应尺寸时显式选择布局重测：

```swift
Row(model: message, cell: MessageCell.self) { cell, message, _ in
    cell.configure(message)
}
.refreshID(message.version)
.refresh(
    when: .refreshIDChanges,
    scope: .allMatching,
    action: .reconfigure(layout: .invalidate)
)

ProviderRow(legacyID, presentationID: legacyPresentationID, register: { collectionView in
    collectionView.lk.register(LegacyCell.self)
}) { collectionView, indexPath, _ in
    legacyProvider.cell(in: collectionView, at: indexPath)
}
.refresh(when: .everyApply, scope: .allMatching, action: .reload)
```

`reload` 请求 `reloadItems` 和完整 provider/configuration 路径，但 UIKit 不保证最终 Cell
对象地址一定变化。Cell 类型或展示变体变化不是 reload；必须改变 presentation identity 并
重新 `apply`。`ProviderRow` 改变 Cell 类型时也必须同步改变 `presentationID`。

请保证同一 section 内的 Row ID 唯一，debug diagnostics 会报告重复身份。

`apply` 不再提供会覆盖节点声明的全局 refresh strategy。普通 `apply` 遵循每个节点的规则；
`.reloadData` 用新描述树执行全量 reload-data 提交；`reloadAll()` 刷新已经提交的描述树；
`reconfigureRows`、`reloadRows` 和 `reloadSections` 用于主动定向刷新。

### 主动刷新层级

身份、`refreshID` 和规则都没有变化，但外部环境发生变化时，可以直接按所需粒度刷新：

| API | 行为 |
| --- | --- |
| `reconfigureRows(forRowID:in:scope:layout:)` | 保留 Cell 并重新配置；仅在 `layout: .invalidate` 时主动重测量。 |
| `reloadRows(forRowID:in:scope:)` | 两种 scope 都使用 snapshot `reloadItems`；`.visible` 只把当前可见匹配 identity 放入 snapshot，并使用 `contentAnimation`。 |
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

### 布局方向

Collection 和 Table adapter 均提供 `layoutDirection: UITraitEnvironmentLayoutDirection`：

```swift
collectionAdapter.layoutDirection = .rightToLeft
tableAdapter.layoutDirection = .rightToLeft

collectionAdapter.layoutDirection = .leftToRight
tableAdapter.layoutDirection = .unspecified // 取消覆盖，恢复设置前的 UIKit 环境
```

默认 `.unspecified` 不修改现有语义方向或 trait。显式切换会更新列表方向并请求布局，
不需要重新 `apply` 或重建列表视图。iOS 17+ 同步列表的方向 trait，取消覆盖后恢复原有
局部覆盖或继承关系。iOS 15/16 使用语义方向，并将显式方向传入 Collection 布局 DSL 的环境。
旧系统中业务视图若直接依赖 `traitCollection.layoutDirection`，仍需由页面控制器提供 trait 环境。

ListKit 创建的 Compositional Layout 在切换时会重建布局对象以清除 UIKit 的镜像缓存，
保留 section provider、当前 configuration 和 decoration 注册。请从 collection view 读取当前布局，
避免继续修改旧布局引用。外部自定义布局仅触发失效，需要自行遵守 UIKit RTL 规则。
使用 leading/trailing 约束和方向性边距；物理 `left/right` 边距及业务内容中的显式方向不会自动交换。
Table 会更新可见 cell 的布局并重新安装原生 accessory，刷新其缓存的方向；保留业务
`accessoryView`、cell 实例及编辑状态。方向切换不翻译文字、不重新执行内容配置闭包；
语言或内容改变仍使用 `apply` / `reloadAll`。

Examples 中通过 **Grid → 布局方向** 打开系统测试页，或使用启动参数 `-LayoutDirectionDemo`。
页面使用 `UICollectionViewController`，由 UIKit 管理完整滚动区域和安全区；同一个 Collection
包含纵向网格与 `.orthogonalScrolling(.continuous)` 横向 section。先分别滚动两个轴，再切换
系统默认 / LTR / RTL。右上角波形按钮显示原生滚动条，表格按钮打开独立的 UITableView 测试页。
正交 section 的指示器由 UIKit 管理，主 Collection 的 `showsHorizontalScrollIndicator`
不等于正交 section 的指示器开关。

ListKit 沿用 Compositional Layout 的原生镜像行为，不额外覆盖
`flipsHorizontallyInOppositeLayoutDirection` 或把 `developmentLayoutDirection` 改成显示方向。
当 `layoutDirection = .unspecified` 时，UIKit 管理列表的方向和指示器。取消显式覆盖时，
ListKit 恢复之前保存的业务边距；之后的指示器位置由 UIKit 决定。
从 iOS 26 起，显式设置 `layoutDirection = .rightToLeft` 时，ListKit 生成的纵向布局会用公开
坐标转换检测 RTL 镜像，再补偿原生竖向指示器的水平边距，使其回到业务指定的物理左侧位置。
切回 LTR 时还原。内容边距、自动调整、
显示开关、上下指示器边距和正交滚动均沿用原有设置。

在 iOS 18，纵向组合布局显式切换方向后，ListKit 会让 UIKit 重算已开启的自动指示器边距。
iPhone XR / iOS 18.7.12 的全屏混合页面中，布局重建后指示器曾停在右边。原生对照中，
关闭再开启自动边距后，指示器出现在左边。ListKit 复用这个刷新过程，并在同一次调用中恢复开关。
切回 `.unspecified` 时，如果实际方向变了，也会在交回 UIKit 前重算一次自动轨道。
XR 真机的全屏和嵌入式往返共四项，以及用应用语言参数启动阿拉伯语的两项均通过。

需要在运行中读写业务边距时，使用 `adapter.verticalScrollIndicatorInsets`；UIKit 的同名
属性在 RTL 下可能包含补偿值。原有的一次性设置也可在首次布局前完成。尺寸变化时会重算
补偿。如果要直接换成外部布局并立即闪现指示器，先设
`adapter.correctsRTLVerticalScrollIndicatorPosition = false`，可立即恢复原始边距；
普通拖动会在开始前自动完成清理。

使用 `-LayoutDirectionOverview` 打开嵌入式对照页，追加 `-CustomIndicatorInsets`
检查关闭自动调整和手动边距。ListKit 的 UI 回归要求显式 RTL 的截图中指示器在左、显式 LTR 时在右；
下文的原生对照页仍用于复现 UIKit 行为，两类测试分开记录。

在 iOS 26.5 和 27.2 模拟器上，全屏和嵌入式两种容器的自动、手动边距往返均通过。
截图逐像素检查 RTL 的物理左边距：零业务边距为 3 点，`left=4, right=12` 为 7 点，
与相同配置的 Flow Layout 一致。系统阿拉伯语冷启动用例不传应用语言参数，也不切换
方向。它们验证 `.unspecified` 继承 RTL、保留原始边距，并用真实手势分别检查正交 section
与主列表滚动。iOS 27.2 上，UIKit 把全屏自动配置的指示器放在左边，全屏手动和嵌入式自动
配置放在右边。运行 `testListKitSystemArabicLaunch*`
前需准备上述模拟器环境，并为测试运行器设置 `LISTKIT_VERIFY_SYSTEM_RTL=1`。
Examples 在 Bundle 中也声明了希伯来语与简体中文，供 UIKit 解析相应的布局方向。
真实系统语言回归使用 `testListKitSystemHebrewLaunch*` 和测试运行器环境变量
`LISTKIT_VERIFY_SYSTEM_HEBREW=1`，不向 App 传入语言启动参数。
在系统简体中文的 iPhone XR 上，`testSystemChineseColdLaunchAndReturnFromRTL` 从常规入口
启动且不传任何参数，确认冷启动和从显式 RTL 切回 `.unspecified` 后，竖向指示器都在右侧。

在 iPhone 17 Pro / iOS 26.5 的原生对照中，临时切换并恢复自动边距开关后，嵌入式和手动
边距 Collection 的 RTL 指示器仍在右侧。重新设置指示器边距、强制布局和调整布局重建顺序
也无法单独修复这两种配置。

新增不依赖 ListKit 的 `NativeCollectionIndicatorViewController` 对照页：启动参数
`-NativeCollectionIndicator` 使用全屏默认配置；追加 `-EmbeddedNativeIndicator` 或
`-CustomIndicatorInsets` 分别复现两种问题。它仅使用 UIKit 原生 Compositional Layout、
data source、方向 trait/semantic 和相同自动边距刷新，截图仍复现上述差异。
这表明在此运行时问题来自原生布局路径；该对照页未接入 ListKit 的指示器补偿。
回归测试单独检查指示器确实可见，避免把闪现结束误归类为已知方向缺陷。

另已独立验证 `showsVerticalScrollIndicator` 隐藏再显示：先设为 `false`，更新方向和布局，
再立即或延迟 0.1 秒恢复原值。嵌入式与手动边距两种场景的四项截图测试均显示 RTL 指示器
仍在右侧，且滚动条确实可见。此实验不叠加自动边距开关刷新；可追加
`-NativeIndicatorVisibilityRefresh immediate` 或 `-NativeIndicatorVisibilityRefresh delayed`
复现。未将无效的可见性切换加入 ListKit。

方向设置层级也已对照：追加 `-NativeDirectionScope controller`、`window` 或 `scene`，
分别只设置页面、窗口或 `UIWindowScene` 的 `traitOverrides.layoutDirection`，移除 Collection
本地 trait 覆盖并保持其 `semanticContentAttribute = .unspecified`，让方向向下继承。
这组实验不切换自动边距开关，也不隐藏指示器。在同一 iPhone 17 Pro / iOS 26.5 上，
三个层级 × 嵌入式/手动边距共六项均显示内容为 RTL、指示器仍在右侧；切回 LTR 和移除
覆盖后方向恢复。场景层级实验记录中，scene、window、controller、Collection 的方向均为 RTL，
因此不能把问题仅归因于“Collection 是 RTL、父环境还是 LTR”。这组实验针对已有视图动态切换。
Apple 的 [trait 层级说明](https://developer.apple.com/documentation/uikit/traits-and-the-trait-environment)
解释了场景覆盖如何影响后代，但未承诺它能刷新此处的指示器位置。

也已验证创建窗口前设置 Scene 方向：追加 `-NativeSceneRTLBeforeWindow -NativeDirectionScope scene`，
在 `SceneDelegate` 中先设置 `windowScene.traitOverrides.layoutDirection = .rightToLeft`，
再创建 `UIWindow`、根控制器和 Collection。首次显示不点击方向按钮、不重建布局、不切换
指示器可见性或自动边距开关。首次截图确认各层 trait 均为 RTL，内容排列正确，但：

| 创建窗口前 Scene 为 RTL | 首次 RTL 指示器 | 再切换至 LTR |
| --- | --- | --- |
| 嵌入式 Collection | 右侧，异常 | 右侧，正常 |
| 全屏、手动指示器边距 | 右侧，异常 | 右侧，正常 |
| 全屏、默认配置 | 右侧，异常 | 左侧，异常 |

因此提前设置 Scene 方向也不是已验证可用的修复；全屏默认配置还呈现出与动态切换实验不同的
行为，不能把此前全屏通过的结论推广到所有初始化方式。测试分别保留首次 RTL、随后 LTR 的
截图与首次环境数据，并把侧边错误记录为 iOS 26.5 的预期失败；内容方向和指示器可见性仍须通过。
前述 Scene 实验本身没有改变应用语言；RTL 语言启动的对照如下。

**阿拉伯语启动与 Scene 覆盖对照（同一 iPhone 17 Pro / iOS 26.5）：** Examples 的
`CFBundleLocalizations` 声明 `en`、`ar`，使 UIKit 可以选中阿拉伯语；演示文案没有完整翻译。
语言启动用例保持“系统默认”，不点击方向按钮、不设置 Scene/Collection trait 或 semantic，
也不执行方向刷新。分别验证两条路径：

- 应用启动参数：`-NativeLanguageStartup -AppleLanguages '(ar)' -AppleLocale ar_SA`，
  这是 [Apple 的语言测试方式](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPInternational/TestingYourInternationalApp/TestingYourInternationalApp.html)。
  全屏默认、嵌入式、手动指示器边距三项均为正确 RTL 内容、右侧指示器（异常）。
- 模拟器全局语言：临时将当前设备的 `NSGlobalDomain.AppleLanguages` 设为
  `ar, zh-Hans-CN, en-CN`，应用启动不传 `AppleLanguages`。地区保持 `zh_CN`，未重启设备。
  首选语言和 Bundle 实际语言均为 `ar`；两种目标场景仍异常。结束后恢复并核对原语言顺序
  `zh-Hans-CN, en-CN`。此项验证的是新启动应用读取全局语言偏好，不包含重启 SpringBoard 后的整机 UI 验证。

| 启动方式 | UIApplication 方向 | Scene/Collection 方向 | 嵌入式 / 手动边距指示器 |
| --- | --- | --- | --- |
| 英语 + 创建窗口前 Scene RTL 覆盖 | LTR | RTL / RTL | 均在右侧，异常 |
| 阿拉伯语应用启动参数 | RTL | RTL / RTL，无覆盖 | 均在右侧，异常 |
| 全局首选阿拉伯语，无语言启动参数 | RTL | RTL / RTL，无覆盖 | 均在右侧，异常 |
| 全局首选阿拉伯语并重启 SpringBoard，无语言启动参数 | RTL | RTL / RTL，无覆盖 | 均在右侧，异常 |

测试记录应用语言、UIApplication 方向、两层方向覆盖是否存在及语言参数是否存在，
避免把英语回退或 trait 覆盖误判为 RTL 语言启动。`testNativeSystemLanguage*` 默认跳过，
仅在已准备好全局阿拉伯语环境且测试运行器环境变量 `LISTKIT_VERIFY_SYSTEM_RTL=1` 时执行；
测试本身不会修改全局语言。三项 `testNativeArabicLanguage*` 可独立重复运行。
结果进一步说明，仅切换应用/全局语言也未解决这里的原生 Compositional Layout 指示器问题。

**SpringBoard 重启验证：** 在同一已启动设备上写入阿拉伯语首选语言后，通过
`simctl spawn <UDID> launchctl stop com.apple.SpringBoard` 让系统重新启动 SpringBoard；
确认进程 PID 已变化、主屏幕系统应用名称显示阿拉伯语、状态栏与图标排列镜像后，才运行
两项 `testNativeSystemLanguage*`。应用不传语言参数、不覆盖方向，采集到 `bundleLanguage=ar`、
`applicationDirection=1`、各层 RTL，以及 `sceneOverride=false`、`collectionOverride=false`、
`semantic=0`、`argumentLanguageOverride=false`。截图中嵌入式与手动边距指示器仍在右侧，
两项均复现已记录的侧边错误（预期失败），内容方向和指示器可见性检查通过。
因此这两个场景的异常不能仅归因于 SpringBoard 尚未更新语言。测试后恢复原来的
`zh-Hans-CN, en-CN` 顺序，再次重启 SpringBoard，核对中文主屏幕与 LTR 状态栏已经恢复；
地区始终为 `zh_CN`。本轮只补充实验记录，未修改 ListKit 正式实现。

**Flow Layout 与 Compositional Layout 对照：** 在原生页追加
`-NativeCollectionLayout flow` 使用未经子类覆盖的 `UICollectionViewFlowLayout`；默认仍为
`UICollectionViewCompositionalLayout`。两者共享 Collection、数据源和 cell，三列、行高 72、
行/列间距 8、section 水平总边距 60，上下各 12。Flow 使用 delegate 按容器宽度计算 item 宽度。
在同一已启动 iPhone 17 Pro / iOS 26.5 上，90 项内容高度均为 2416；嵌入式 frame 为
`(16, 174, 370, 320)`，手动边距全屏 frame 为 `(0, 0, 402, 874)`，对应的安全区、内容边距、
自动指示器边距开关和 `verticalScrollIndicatorInsets` 均相同。

| RTL 来源与配置 | UICollectionViewFlowLayout | UICollectionViewCompositionalLayout |
| --- | --- | --- |
| 阿拉伯语启动，嵌入式 | 内容 RTL，指示器左侧，正常 | 内容 RTL，指示器右侧，异常 |
| 阿拉伯语启动，手动指示器边距 | 内容 RTL，指示器左侧，正常 | 内容 RTL，指示器右侧，异常 |
| 英语启动后切换 Collection RTL，嵌入式 | 内容 RTL，指示器左侧，正常 | 内容 RTL，指示器右侧，异常 |
| 英语启动后切换 Collection RTL，手动指示器边距 | 内容 RTL，指示器左侧，正常 | 内容 RTL，指示器右侧，异常 |

Flow 的四项测试不使用预期失败，内容方向和指示器位置均实际通过；Compositional 的四项
仍记录为已知侧边错误。运行时采集到两种布局的 `developmentLayoutDirection` 都是 LTR，
`flipsHorizontallyInOppositeLayoutDirection` 都是 false；不能仅通过这两个返回值解释差异。
这把当前问题缩小到这组原生 Compositional Layout 配置及当前系统运行时的行为，尚未证明其内部原因。
此轮没有更改设备语言或重启模拟器，也没有替换 ListKit 的布局实现。

**保留纵横混合布局的公开配置对照：** 原生页的 `-NativeMixedLayout` 使用一个主轴为纵向的
Compositional Layout：第一个 section 为 20 项横向 `.continuous` 正交滚动，第二个 section 为
90 项三列网格。通过真实向右拖动验证 RTL 后续横向项目进入视口，且主轴网格的 Y 位置不变；
随后向上滚动并截图检查主轴原生指示器。全屏默认配置的这组检查实际通过，RTL 指示器在左侧。

`-NativeCompositionalCase` 支持以下配置。同一 iPhone 17 Pro / iOS 26.5 上，英语启动后切换
Collection RTL，分别在嵌入式和手动指示器边距配置运行，共 14 组，结果如下：

| 单变量配置 | 嵌入式 RTL 指示器 | 全屏手动边距 RTL 指示器 |
| --- | --- | --- |
| `default`：默认 `.safeArea` | 右侧，异常 | 右侧，异常 |
| `automatic`：布局边距参考 `.automatic` | 右侧，异常 | 右侧，异常 |
| `none`：布局边距参考 `.none` | 右侧，异常 | 右侧，异常 |
| `margins`：布局边距参考 `.layoutMargins` | 右侧，异常 | 右侧，异常 |
| `readable`：布局边距参考 `.readableContent` | 右侧，异常 | 右侧，异常 |
| `adjust-always`：内容边距调整 `.always` | 右侧，异常 | 右侧，异常 |
| `adjust-never`：内容边距调整 `.never` | 右侧，异常 | 右侧，异常 |

手动指示器边距始终为 `(top: 8, left: 4, bottom: 8, right: 12)`，自动调整仍为 false。
所有网格的 RTL 排列检查通过；13 组横向滚动检查通过。全屏 `.never` 的横向首行被导航栏
遮挡，单独排除其横向手势检查并复测，保留网格排列、指示器可见性和侧边检查。
这组结果说明：正交 section 本身不必然导致异常，调整这些公开边距配置也未解决异常。

**系统 list 工厂对照：** Today 使用 `UICollectionViewCompositionalLayout.list(using:)`。
原生页的 `list-factory` 分别以 `.plain` 和 `-NativeGroupedList` 的 `.grouped` 外观验证；
`list-section` 则保留横向正交 section、三列网格，再加入 90 行系统 list section，使用
[NSCollectionLayoutSection.list(using:layoutEnvironment:)](https://developer.apple.com/documentation/uikit/nscollectionlayoutsection/list(using:layoutenvironment:))。
这三种配置分别在嵌入式和手动指示器边距场景验证，六组仍全部在右侧。混合配置的网格和横向
项目 RTL 排列、真实横向滚动检查通过。因此 Today 使用 list 工厂这一差异，单独不足以解释
之前全屏正常，也不能作为这两个异常场景的修复。list 行采用浅色背景，避免半透明指示器与
彩色背景混合后被灰色像素检查漏检；截图中的可见性检查仍为严格断言。

**直接初始化 Compositional 的对照：** `-NativeInitialCompositionalLayout` 将布局直接传入
`UICollectionView(frame:collectionViewLayout:)`，不先创建 Flow 再赋值。保留纵横混合布局，
分别测试阿拉伯语启动（无方向覆盖）和英语启动后动态切换 RTL，在嵌入式、手动指示器边距下
共四组。采集到 `initialCompositional=true`、`mixed=true`、Collection trait/effective 均为 RTL；
阿拉伯语组为 `bundleLanguage=ar`、`semantic=0`。网格排列和横向滚动检查通过，竖向指示器
四组仍在右侧。因此异常也不能仅归因于先创建 Flow 再切换到 Compositional 的初始化顺序。

以上异常侧边断言在 iOS 26.5 上使用严格的 `XCTExpectFailure` 记录；测试运行成功表示已复现
已记录的问题，不表示方向已修复。可见性、内容排列、横向手势检查不被预期失败包裹。
最终代码另行复跑 `testNativeFlowDirectionEmbedded`、`testNativeFlowDirectionCustomInsets` 和
`testNativeMixedDefault`，三项均实际通过，未使用预期失败，确认 Flow 的两类场景与全屏默认
Compositional 混合布局仍为正常对照。本轮复用同一已启动模拟器，未更改设备全局语言，
未引入私有 API 或指示器位移补偿。

**自动调整触发条件探针（iOS 26.5，英语启动后仅将 Collection 切换为 RTL）：**
`-NativeIndicatorTriggerProbe -NativeMixedLayout` 在同一个 Collection、同一个 Compositional
布局实例上连续修改配置，点击“探针”进入下一步。开始先验证网格和正交 section 的 RTL 排列、
实际横向拖动；之后保持方向不变，不重建布局，不重复切换方向，也不套用原有的开关刷新实验。
诊断子类只观测 `safeAreaInsetsDidChange` 与 `adjustedContentInsetDidChange`，均调用 super；
每步跨一轮主队列采集公开几何、配置、回调和截图。19 步序列重复运行结果一致：

| 同实例上的操作 | 竖向指示器侧边 | 安全区 / adjustedContentInset 回调 |
| --- | --- | --- |
| 全屏、自动调整开启、竖向指示器边距为零 | 左侧 | 无新增回调 |
| 关闭自动调整；再开启 | 右侧 → 左侧 | 均无新增回调 |
| 仅设竖向指示器 top=8；恢复零 | 右侧 → 左侧 | 均无新增回调 |
| 仅设竖向指示器 bottom=8；恢复零 | 右侧 → 左侧 | 均无新增回调 |
| 仅设竖向指示器 left=4/right=12；恢复零 | 右侧 → 左侧 | 均无新增回调 |
| 仅设 horizontalScrollIndicatorInsets 非零；恢复零 | 均左侧 | 均无新增回调 |
| 全屏 contentInsetAdjustmentBehavior 改为 .never；恢复 .automatic | 均左侧 | 各一次 adjustedContentInset 回调 |
| 改为嵌入式 `(16,174,370,320)` | 右侧 | 各一次 |
| 嵌入式增加控制器 additionalSafeAreaInsets，使 Collection 的 safe/adjusted.top=36 | 仍右侧，指示器变短 | 各一次 |
| 恢复原全屏几何 | 左侧 | 各一次 |

这些回调既不是侧边变化的必要条件，也不足以保证侧边正确。`.never` 时全屏
`adjustedContentInset` 已变成零，指示器仍在左侧，说明不能用该属性是否非零判断侧边路径。
也不能把“手动边距”简单解释为自动避让完全失效：仅设 left/right 时，原生指示器的 Y 范围
仍为 `262.33...475.00`，与默认全屏完全一致，只是 X 从 `3...6` 变为 `392...395`；
关闭自动调整后，Y 范围则变为 `189.00...430.33`。这是截图像素的屏幕点坐标，不是 UIKit
私有视图的 frame。之前同配置 Flow 手动边距的 X 为 `7...10`，Compositional 为 `392...395`，
相对于宽度 402 呈水平镜像关系；这支持“坐标转换路径有差异”的推断，尚不能证明内部实现。

**Flow / Compositional 坐标差分验证：** 新增 `-NativeIndicatorCoordinateProbe -NativeMixedLayout`，
在 LTR/RTL、全屏/嵌入式、自动调整开/关及五种相同指示器边距下采集截图像素与公开坐标。
Flow 对照也保留横向内容，并匹配主轴网格和内容长度。iOS 26.5 与 27.2 均确认 19 组 RTL
配置呈水平镜像；全屏自动调整且零边距时仍与 Flow 重合。方法、结果与原始数据见
[原生滚动指示器坐标对照](Documentation/Indicator-Coordinate-Validation.md)。

**系统栏覆盖范围对照：** 同一探针追加 `-NativeIndicatorBoundaryProbe` 测边界，或
`-NativeIndicatorTopProbe` 测宽度。仍保持自动调整开启、竖向指示器边距为零，视图不重建。
设备窗口为 `402×874`，Window 安全区上 62 / 下 34，控制器导航栏下沿为 150。

| Collection 的屏幕几何（x, y, width, height） | Collection safe/adjusted.top / bottom | RTL 侧边 |
| --- | --- | --- |
| `(0,0,402,320)` | 150 / 0 | 左 |
| `(16,0,370,320)` | 150 / 0 | 右 |
| `(0,1,402,320)` | 149 / 0 | 左 |
| `(16,1,370,320)` | 149 / 0 | 右 |
| `(0,61,402,320)` | 89 / 0 | 左 |
| `(16,61,370,320)` | 89 / 0 | 右 |
| `(0,149,402,320)` | 1 / 0 | 左 |
| `(16,149,370,320)` | 1 / 0 | 右 |
| `(0,150,402,320)` | 0 / 0 | 右 |
| `(16,521,370,320)`，底部进入 Window 底部安全区 1 点 | 0 / 1 | 左 |
| `(16,520,370,320)`，底部刚好贴安全区边界 | 0 / 0 | 右 |
| `(16,519,370,320)`，底部离开边界 1 点 | 0 / 0 | 右 |

仅跨过 Window 顶部安全区的 61 / 62 / 63 边界，在窄列表中均为右侧；不能把上下端简单
归为同一 Window 安全区判定。顶部全宽和窄列表拥有完全相同的 safe/adjusted 值，却有不同
侧边；这将影响因素进一步缩小到系统栏的实际覆盖几何，超过了公开 inset 数值本身。
重写 `contentScrollView(for:)` 返回 nil 并恢复系统栏观察时，确认 UIKit 实际调用了该
公开 override，但全屏默认侧边仍始终在左侧；这项观察开关也没有提供独立的侧边控制。
其公开语义参见 [contentScrollView(for:)](https://developer.apple.com/documentation/uikit/uiviewcontroller/contentscrollview(for:))。

因此，当前证据不支持把问题当作“缺少一次安全区通知 / layout 刷新”。自动避让与侧边
坐标处理需要分开判断；临时清零或改全屏再恢复原几何，会重新进入异常状态，不能作为
保留业务配置的修复。以上是对公开输入、公开回调和最终像素的实测归纳，内部 UIKit 路径
尚未得到证实，仍没有加入正式 ListKit 补偿代码。

`testNativeIndicatorAutomaticAdjustmentTriggers`、`testNativeIndicatorSystemBarBoundaries` 与
`testNativeIndicatorTopGeometry` 是诊断测试：严格检查内容排列、
真实横向滚动、指示器可见且只在一侧，并把左右像素数作为附件记录；其通过不表示异常已修复。
这些公开 API 的作用分别见 Apple 的
[自动指示器边距](https://developer.apple.com/documentation/uikit/uiscrollview/automaticallyadjustsscrollindicatorinsets) 和
[adjustedContentInset](https://developer.apple.com/documentation/uikit/uiscrollview/adjustedcontentinset) 文档。
以上触发条件是这组运行时对照的观察，不是 Apple 对 RTL 侧边行为的保证，也不能外推到
前述阿拉伯语首次启动场景。

Apple 文档说明 [contentInsetsReference](https://developer.apple.com/documentation/uikit/uicollectionviewcompositionallayoutconfiguration/contentinsetsreference)
控制内容边距的参考边界，默认值为 `.safeArea`；它没有承诺控制指示器侧边。
[developmentLayoutDirection](https://developer.apple.com/documentation/uikit/uicollectionviewlayout/developmentlayoutdirection)
描述布局设计时的语言方向，也不是独立的指示器方向开关。这里保留诊断对照，未启用 ListKit
的公开边距补偿。

进一步对照表明，不能简单把差异归结为“全屏 / 非全屏”。同一原生页面、同一设备上，
保持 RTL 内容排列时的实测结果如下（自动调整默认开启，未列出的指示器边距为零）：

| 单变量配置 | RTL 竖向指示器 |
| --- | --- |
| 仅把全屏列表左右各缩进 16，仍延伸到屏幕上下边缘 | 左侧，正常 |
| 顶部仍延伸至屏幕顶部，仅将高度改为 320 | 左侧，正常 |
| 顶部移到导航栏下方，底部仍延伸至屏幕底部 | 左侧，正常 |
| 四边都约束到安全区，列表自身的安全区为零 | 右侧，异常 |
| 嵌入式子控制器增加 `additionalSafeAreaInsets.top = 12` | 右侧，异常 |
| 嵌入式列表设置 `contentInset.top = 12` | 右侧，异常 |
| 全屏列表关闭自动调整，指示器边距仍为零 | 右侧，异常 |
| 全屏列表保持自动调整，仅设置上下指示器边距为 8 | 右侧，异常 |
| 全屏列表显式设置指示器边距为零 | 左侧，正常 |

通过的非全屏场景仍覆盖了系统栏或底部手势区域；仅人为增加局部安全区或内容边距并不能
复制这一行为。这是当前运行时的观测差异，不是可以用任意非零 inset 修复的保证。
关闭边缘效果、设置 `.hard` 或添加 `UIScrollEdgeElementContainerInteraction` 也未解决异常。
可在 `-NativeCollectionIndicator` 后追加 `-NativeIndicatorCase` 及 `narrow`、`short`、
`below-bar`、`safe-area`、`child-safe-area`、`content-inset`、`manual-zero`、`auto-custom`、
`top-insets`、`zero-set` 复现；UI 测试会附带方向更新时的公开几何与配置数据。

也验证了布局属性覆盖方案：`.unspecified` 时均返回 `super`；显式 RTL 时，将
`developmentLayoutDirection` 固定为 `.rightToLeft`，无论 `flipsHorizontallyInOppositeLayoutDirection`
为 true 或 false，指示器都到了左侧，但网格排列变为 LTR。使用 LTR 坐标基准并开启翻转则
排列正确、指示器仍在右侧。`developmentLayoutDirection` 是布局实现的坐标基准，不能直接
当作显示方向映射。实验只保留在原生对照页的 `-NativeLayoutPolicy target-true`、`target-false`、
`base-true` 参数中（可与 `-EmbeddedNativeIndicator` 组合），未改变 ListKit 的原生布局行为。

Table 在方向布局后临时切换并恢复 `automaticallyAdjustsScrollIndicatorInsets`，触发原生
指示器位置重算；仅重设相同的边距会导致 RTL 切回 LTR 后指示器仍留在左侧。此刷新保留
业务的自动调整开关、两轴边距和滚动位置。表格页也提供滚动条显示按钮，使用
`-CustomTableIndicatorInsets` 可验证关闭自动调整并设置手动边距的场景。

语言、Dynamic Type 或全局主题切换适合 `reloadAll`。先更新真正承载列表的
UIKit 环境，再触发刷新；默认使用 0.2 秒 cross-dissolve，并自动遵循 Reduce Motion：

```swift
adapter.layoutDirection = isRTL ? .rightToLeft : .leftToRight

adapter.reloadAll()

// 需要等待过渡和布局完成：
let result = await adapter.reloadAll()
```

`reloadAll` 有意复用当前 diffable snapshot / outline 状态，不提交一份新的结构；内部调用
`reloadData()` 只会让 diffable data source 重新提供当前内容，不会修改 snapshot。ListKit
会避开正在提交的 snapshot 和 `hasUncommittedUpdates`，避免丢弃拖放或重排中的占位状态。
Table 和 Collection 中已排队的 `.reloadData` 模式 `apply` 同样会在队首等待 `hasUncommittedUpdates` 变为 `false`。它完成后，队列才会执行随后入队的 `reloadAll`。

`reloadAll` 不会重新执行 section builder。如果旧描述树已经把本地化字符串保存成值，
请先更新 model，再使用 `apply` 重建 sections；配置闭包在执行时动态读取语言或主题时，
直接 `reloadAll` 即可。Table 的 `reloadAll` 会在 UIKit 重载前重新执行当前分区的行高闭包，因此环境变化也能更新已有行的高度。若不需要过渡，可显式关闭：

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

`Row.onPrimaryAction(...)` 和 `TableRow.onPrimaryAction(...)` 要求 iOS 16.0 / tvOS 16.0；`CollectionListAdapter.contextMenuForItems(...)` 要求 iOS 16.0 / tvOS 17.0。部署目标为 iOS 15 时，调用这些 API 需要放在 `if #available(iOS 16.0, *)` 分支中。

Collection 按当前行判断 primary action 能力，未配置动作的行不会因 adapter 提供动作转发而改变普通触摸多选。默认仅 Row 配置了 `.onPrimaryAction(...)` 或 `collectionDelegate` 实现了 `performPrimaryActionForItemAt` 时启用；外部代理若实现 `canPerformPrimaryActionForItemAt`，其显式判断优先。执行动作时仍先调用 Row 闭包，再转发给外部代理。已启用的 primary action 保留 UIKit 的独占选择语义。

## Layout 与 Supplementary

布局返回一个完整值，由主体与 `.sectionInsets`、`.boundarySupplementaries`、`.itemSupplementaries`、`.decorationItems` 组合。补充视图内容统一使用 `SectionSupplementary`，装饰注册使用 `SectionDecoration`；supplementary 通过实际 kind 关联布局，decoration 通过逻辑 kind 关联布局，内容均不携带几何。通用 Header/Footer 与 background 专用入口已移除，TableHeader/TableFooter 保留。

| 布局入口 | 适用场景与默认行为 |
| --- | --- |
| `GridLayout(tracks: 1)` | 单行或单列；默认主轴 `.estimated(44)`、间距 0、`.alignment(.start)` |
| `GridLayout(tracks: n)` | n 条等分轨道，自动适配方向 |
| `GridLayout(tracks: [ListGridTrack])` | fixed / flexible / adaptive 混合轨道 |
| `WaterfallLayout(tracks:)` | 标准 Row 默认自动测量，支持纵向、横向及正交滚动的最短轨道排布 |
| `UIKitListLayout(...)` | UIKit 原生列表、分隔线和 swipe actions |
| `CustomLayout(layoutKey:)` | 根据真实 context 构建自定义 UIKit section |
| `EnvironmentLayout(layoutKey:)` | 按环境返回完整布局 |

Grid 未开启正交滚动时跟随外层方向，开启后沿垂直于外层的方向展开。纵向内容中 tracks 表示列宽，横向内容中表示行高；单轨道替代普通 ListLayout，正交修饰替代 HorizontalLayout。columns:/rows: 入口已移除。

固定 crossAxisSize 完整预留交叉轴区域；估算 crossAxisSize 不支持宽高比。带 badge 的 estimated/uniform 支持多基本行／列 group；业务 kind 只声明一次，框架负责实际 kind/indexPath 映射。自定义 provider 与 UIKit 查询迁移见[自适应徽标实现与验证](Documentation/Measured-Grid-Badges.md)。估算主轴 group 的精确吸附仍有 UIKit 实测偏差，动态内容示例使用连续滚动；精确分页使用确定尺寸。旧 Horizontal 整宽 group 与 fractionalViewport 的 inset 参考不同，精确迁移见[布局文档](Documentation/Layout-API.md#从旧布局迁移)。

```swift
// 纵向页面中的两行横向分页，每组 3 列，共 6 个 item。
GridLayout(tracks: 2)
    .itemMainAxisSize(.fillGroup).trackSpacing(10).lineSpacing(10)
    .crossAxisSize(.fixed(220))
    .lineGrouping(.count(lines: 3, mainAxisSize: .fractionalViewport(1)))
    .groupSpacing(16)
    .orthogonalScrolling(.groupPaging)
```

itemMainAxisSize 控制内容主轴尺寸；轨道控制交叉尺寸；crossAxisSize 设置所有轨道共同占用的交叉轴区域；lineGrouping 配置基本行／列数量与主轴长度。crossAxisSize 不含 section inset，随内容方向解释。`.crossAxisSize(.estimated(...))` 支持单轨道估算交叉尺寸；estimated/uniform 主轴使用内容推导的 group，不能与 fitting 或显式 group 长度混用。

`.alignment(.start/.center/.end)` 对齐整组轨道，默认 start；不控制 cell 内部内容或分页。trackSpacing 控制轨道间距，lineSpacing 控制内容方向的组内与默认组间距，两者默认 0。groupSpacing 为可选覆盖，默认 nil 跟随当前 lineSpacing；显式值（包括 0）只覆盖组间距，调用 `.groupSpacing(nil)` 恢复跟随。

自动测量瀑布流的 Cell 约束、缓存失效、方向配置和边界说明见 [WaterfallLayout](Documentation/Waterfall-Layouts.md)。示例列表页导航栏的 **Waterfall** 可切换纵向、横向、正交滚动和轨道数，并验证追加及展开内容后的自动重排。

布局使用以下替换与默认规则：

- 重复调用布局集合修饰方法会完整替换，不追加。Section 的 `.layout { ... }` 替换主体及其修饰配置，保留内容和注册声明。
- 空 layout builder、nil 或 `EnvironmentLayout` 的空分支均回退到默认 `GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0)`，不会保留旧布局或隐藏 Section。
- 省略 `decorationItems` 时，为已有装饰注册生成零 inset、zIndex -1 的默认背景；显式 `.decorationItems(.none)` 关闭框架生成的背景，保留注册和 provider 自有几何。
- `.whenContentExists()` 判断当前 Section 是否存在对应内容或注册声明，不判断屏幕可见性，也不跳过尺寸与唯一性校验。
- 边界位置由 alignment 决定，leading/trailing 不是固定左右，top/bottom 不随滚动轴互换。原生 List 省略 inset 修饰时保留系统值；CustomLayout 显式声明 inset 时须由 provider 使用并返回同值。

装饰的 `SectionDecoration.kind` 是逻辑名称；`SectionDecoration.elementKind` 才是 UIKit 实际注册标识。自定义 provider 使用 `context.decorationElementKind(for:)`，手动注册入口使用 `SectionDecoration(kind:elementKind:)`。不同 Section 可以复用逻辑名称并采用不同视图类型。

完整 API、默认值、Grid 规则、自定义 UIKit 接口与诊断见 [布局 API](Documentation/Layout-API.md)。[上游审查](Documentation/UIKitGridLayouts-Review.md)记录内部算法整合与 MIT 署名；[历史验证记录](Documentation/Layout-Validation.md)与[统一 Grid 验证](Documentation/Unified-Grid-Validation.md)分别记录各阶段的编译、模型和真实渲染证据。示例首页的 **Grid** 打开 [Layout Lab](Documentation/Layout-Lab.md)：切换方向、轨道、场景和容器尺寸，通过右上角 **参数 / 代码** 调整主轴尺寸、分组、轨道／行间距、组间距覆盖与对齐，并查看当前配置实时生成的布局代码。单元格显示实际宽高；支持增加内容观察 self-sizing，以及 Cards、Tags、Banner、Measured badges、Centered、2×3、Mixed sections 与 Native list 场景。

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
.onAppear { cell, context in
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
.onAppear { cell, context in
    analytics.trackImpression(id: context.itemID)
    cell.startAnimation()
}
.onDisappear { cell, _ in
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

展开和收起操作使用与 `apply` 共用的队列。`onExpansionChange` 中同步提交的更新会等待本次展开状态提交完成，再按更新策略执行。点击行与系统展开按钮都走这条路径。

折叠后，选择、预取以及位置查询按 diffable data source 的当前快照定位。`indexPath(for:)` 对隐藏的后代返回 `nil`，`indexPaths(forRowID:in:)` 跳过这些后代；`contains(_:)` 仍可确认它们存在于描述树中。

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

需要无动画整体替换时，传入完整 options：

```swift
let options = ListApplyOptions(
    transaction: .disabled,
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
print("refreshID changed rows:", summary.rowRefreshIDChangedCount)
print("snapshot reconfigured rows:", summary.refreshMetrics.snapshotReconfiguredRowCount)
print("visible reconfigured rows:", summary.refreshMetrics.visibleReconfiguredRowCount)
print("reloaded rows:", summary.refreshMetrics.reloadedRowCount)
print("visible supplementaries:", summary.refreshMetrics.visibleReconfiguredSupplementaryCount)
print("reloaded sections:", summary.refreshMetrics.reloadedSectionCount)
print("completion:", summary.animation.completionState)
```

如果较新的 `.coalesceLatest` apply 取代了尚未完成的旧 apply，旧结果会以 `.superseded` 结束；任务在提交前取消时会返回 `.cancelledBeforeCommit`。
`rowRefreshIDChangedCount` 与 `supplementaryRefreshIDChangedCount` 只描述版本变化；
`refreshMetrics` 描述真实规划或执行的动作。Section reload 连带更新的 Row 不重复计入
`reloadedRowCount`；`.cancelledBeforeCommit` 的动作指标全部为零。

主动刷新返回 `ListRefreshSummary`。合并请求中的每个调用方只收到自己目标集合的
`requestedTargetCount`、`matchedTargetCount` 和动作指标，不会复制整批合并结果。

## Diagnostics

库内部使用 Apple 统一日志 `Logger`，subsystem 为 `ListKit`。
apply summary 使用 `Apply` category 和 `debug` 级别；结构与布局诊断使用
`Diagnostics` category 和 `warning` 级别。可在 Xcode 控制台或 Console.app 中按
subsystem/category 筛选，查看 summary 时需启用 Debug 级别日志。

普通 apply summary 日志默认不打印。需要查看时，在 Xcode → Edit Scheme → Run →
Arguments → Arguments Passed On Launch 中添加并勾选 `-ListKitLogApplySummary true`
（参数名为 `-ListKitLogApplySummary`，紧随其后的值为 `true`）。
只有在 DEBUG 构建、该参数值为 `true` 且 `logsApplySummary == true` 时才会输出；
未添加参数、缺少值或值不是 `true` 时均不打印。
`logsApplySummary: false` 始终关闭 summary 日志，Release 构建不会输出。
Table 和 Collection 共用此开关，summary 数据仍照常生成和返回。
诊断警告不受该启动参数控制，仍按 diagnostics 配置处理。

默认配置会在 diffable apply 前检查重复 identity 和可静态确定的无效布局，问题存在时打印诊断并跳过本次提交。依赖实际容器、外层方向或 provider 返回值的问题，在 Section 解析阶段另行检查：

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
- 自定义 UIKit boundary 与 Section 声明的 kind 冲突。
- 无效 grid 数量、轨道上下限、非有限/非正尺寸或负 spacing/inset。
- Grid 滚动轴与外层布局不匹配，原生 UIKit List 使用 item supplementary。

调试期希望在诊断处调用 `assertionFailure` 时使用 `.assertion`。`.disabled` 不能理解为允许任意无效布局：即使不记录解析诊断，Section 解析仍会拒绝尺寸约束不满足等无效配置。

`makeCompositionalSection` 的 `scrollDirection` 必须与外层 layout 实际方向一致；Grid 尺寸约束不满足时返回 nil，不自动改为正交滚动。此类解析诊断通过 `lastLayoutDiagnostics` 观测，不能仅从 apply 返回值判断。`makeCompositionalLayout` 的 provider 在解析返回 nil 时使用默认 List 布局回退；自行创建外层 layout 时由调用方处理 nil。详见[解析诊断与回退](Documentation/Layout-API.md#解析诊断与回退)。

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

### Collection 行拖放

`Row.onDrag` 在开始拖动时创建内容。`Row.onDrop` 接收放在该行上、符合声明类型的 provider。两者均支持 iOS 15。拖出行与目标行可以分别声明。

```swift
import UniformTypeIdentifiers

Row("message", model: text, cell: MessageCell.self) { cell, text, _ in
    cell.configure(text)
}
.onDrag { NSItemProvider(object: text as NSString) }

Row("inbox", model: inbox, cell: InboxCell.self) { cell, inbox, _ in
    cell.configure(inbox)
}
.onDrop(of: [.plainText], isTargeted: { inside in
    updateInboxHighlight(inside)
}, canDrop: { _ in inbox.hasCapacity }) { providers in
    guard let provider = providers.first else { return }
    provider.loadObject(ofClass: NSString.self) { value, _ in
        guard let text = value as? String else { return }
        Task { @MainActor in addMessage(text) }
    }
}
```

可选的 `canDrop` 在会话进入、悬停和提交时检查业务条件。它只应检查状态和 provider 的元数据。在 `perform` 闭包里开始读取内容。行接收内容时向 UIKit 提议复制操作，调用方负责更新数据。当前行不能接收的会话可由父视图的 drop interaction 接收。`isTargeted` 为可选闭包，进入匹配的行时收到 `true`，离开或结束时收到 `false`。

同一行可以同时声明 `onDrag` 和 `onMove`。在 Examples 的编辑模式中，拖动行内容会复制文本，拖动系统排序手柄会调整顺序并触发 `onMove`。

需要自定义整个 collection 的拖放策略时，可以设置 `adapter.dragDelegate` 或 `adapter.dropDelegate`。显式代理优先处理对应方向。将其设为 `nil` 或释放代理对象后，该方向恢复使用 Row 声明。

## 进阶能力

- `ListStateRow`：描述 loading、empty 和 error 状态。
- `DisclosureGroup` / `OutlineGroup`：生成 collection section snapshot 层级。
- `selected(...)` / `selectionMode(...)`：声明单选、多选和受控选择状态。
- `itemIdentity(at:)`、`indexPath(for:)`、`indexPaths(forRowID:in:)`：稳定身份与位置双向查询。
- `reconfigureRows(..., scope: .visible)`：只更新当前可见匹配节点。
- `ProviderRow` / `ProviderSupplementary`：逐步迁移复杂旧 data source 的逃生口。
- `ListDiagnosticsOptions` / `lastApplySummary`：定位重复 ID、无效 layout 和 apply 行为。

## 示例与测试

使用 Xcode 打开根目录的 `ListKit.xcworkspace`，即可在同一个工作空间中管理
`ListKit` Swift Package 和 `Examples` 示例工程：

```bash
open ListKit.xcworkspace
```

`Examples` scheme 用于运行示例，`ExamplesUnitTests` 用于运行示例单元测试；
`ListKit` scheme 用于构建库和运行 `Tests/ListKitTests` 中的库测试。
示例继续通过本地 Swift Package 依赖根目录的 ListKit，修改库代码后可直接在示例中验证。

`Examples/` 包含 collection 与 table 两套完整示例，演示 layout、selection、事件、刷新、swipe、context menu 和 reordering。

可按需要参考不同的 API 组合方式：

| 示例源码 | 组合方式 |
| --- | --- |
| [LiveRoomViewModel](Examples/Examples/LiveRoomViewModel.swift) | 简单 Section 内联；麦位、消息、礼物使用链式入口与独立布局／内容方法；房间动态复用消息 RowGroup；管理列表保留 TableHeader 专用入口。 |
| [ContextMenuDemoViewController](Examples/Examples/ContextMenuDemoViewController.swift) | Section builder 负责组装，`menuRow(for:)` 集中展示单行菜单与生命周期 API。 |
| [LayoutLabViewController](Examples/Examples/LayoutLabViewController.swift) | 从同一份配置快照组合 rows、完整布局和补充内容；“参数 / 代码”面板同步展示链式调用及补充视图绑定。 |

ListKit 是 iOS/UIKit 框架，有效验收项是 iOS Simulator 或 generic iOS Simulator 的
`xcodebuild`。裸跑 `swift test` 会走 macOS SwiftPM 构建路径，macOS target 没有
UIKit，因此 `no such module 'UIKit'` 不作为 ListKit 的有效失败信号。

编译 iOS 测试目标：

```bash
xcodebuild -quiet \
  -workspace ListKit.xcworkspace \
  -scheme ExamplesUnitTests \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/ListKitDerivedData \
  build-for-testing
```

运行 iOS Simulator 测试：

```bash
xcodebuild -quiet \
  -workspace ListKit.xcworkspace \
  -scheme ExamplesUnitTests \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=26.5' \
  -derivedDataPath /tmp/ListKitDerivedData \
  test
```

可以通过 `xcrun simctl list devices available` 查看本机可用模拟器，并按实际安装的
设备名和系统版本替换 `-destination`。

运行库测试时，将上面命令中的 `-scheme ExamplesUnitTests` 替换为 `-scheme ListKit`。

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

Grid 算法及部分测试改编自 UIKitGridLayouts；来源版本与适配见 [审查记录](Documentation/UIKitGridLayouts-Review.md)，随附 [MIT 许可证](ThirdPartyNotices/UIKitGridLayouts-LICENSE.txt)。

ListKit 基于 MIT License 发布，详见 [LICENSE](LICENSE)。


### Collection 分组触摸索引

`ListSection.indexTitle(_:)` 提供分组标题。需要常驻的点选／滑动索引和当前字母提示时，
创建 `CollectionSectionIndexView`，赋给 `adapter.sectionIndexView`，并由页面放到列表的语义尾侧。
控件不依赖 QuickLayoutKit；可使用 QuickLayout、Auto Layout 或其他宿主布局。建议宽度至少 44 pt。
宿主先处理索引的横向安全区域；与列表等高布局时，在布局回调中将列表 `adjustedContentInset` 的 top／bottom 传给索引 `contentInsets` 的对应边缘，避免导航栏或工具栏遮挡，也避免横向安全区域重复叠加。

```swift
let index = CollectionSectionIndexView()
index.accessibilityLabel = "联系人索引" // 应用负责本地化
adapter.sectionIndexView = index
// 页面将 collectionView 和 index 并排布局，避免索引覆盖行内容。
adapter.apply(transaction: .disabled) {
    ListSection("A") {
        Row("alice", model: "Alice", cell: UICollectionViewListCell.self) { cell, name, _ in
            var content = UIListContentConfiguration.cell()
            content.text = name
            cell.contentConfiguration = content
        }
    }.indexTitle("A")
}
```

索引只包含有可定位行的分组，按提交顺序排列；隐藏某分组索引使用 `.indexTitle(nil)`。
所有标题清空后控件自动隐藏。点选和滑动定位分组顶部，列表尾部按实际可滚动范围限制；
不选择联系人、不触发 Row 动作。VoiceOver 使用可调整控件逐项定位，值为当前标题。
数据更新后通过行 identity 解析当前位置；snapshot 提交期间忽略定位，避免陈旧 IndexPath。
绑定自定义索引时关闭原生索引数据返回，解除绑定后恢复原生路径。控件由页面持有，adapter 弱持有。

## 布局 API 语义与迁移

布局尺寸按内容轴解释：`ListGridTrack` 定义交叉轴轨道，`itemMainAxisSize` 定义 cell 的主轴尺寸，`crossAxisSize` 定义所有轨道共同占用的交叉轴区域。`lineGrouping(.count(lines:mainAxisSize:))` 的数量单位是基本行／列，不是 item。

```swift
// 外层纵向时：两行、每组三列，最多六个 item。
GridLayout(tracks: 2)
    .crossAxisSize(.fixed(220))
    .trackSpacing(10)
    .lineSpacing(12)
    .groupSpacing(20)
    .itemMainAxisSize(.fillGroup)
    .lineGrouping(.count(lines: 3, mainAxisSize: .fractionalViewport(1)))
    .alignment(.start)
    .orthogonalScrolling(.groupPaging)
```

`gridSpacing` 已删除；统一间距使用 `.trackSpacing(value).lineSpacing(value)`。`lineSpacing` 不覆盖显式 groupSpacing，二者调用顺序无关；`.groupSpacing(nil)` 清除覆盖。`.orthogonalScrolling(nil)` 关闭正交滚动；`.crossAxisSize(nil)` 恢复环境尺寸。背景可以显式使用 `.decorationItems(.none)` 关闭，或 `.decorationItems(.registeredBackgrounds)` 恢复默认生成。 本轮验证见[统一行间距验证](Documentation/Layout-Spacing-Validation.md)。

本次不兼容旧 frame、itemSize、ListGridItem、无单位 group count 等入口；完整改名表、layoutKey 捕获状态规则、CustomLayout 输入与边界所有权规则见 [布局 API 与迁移](Documentation/Layout-API.md)。历史验证报告保留旧名称与当时的结果。

布局 DSL 的 `.sectionInsets(...)` 明确作用于当前 Section，CustomLayout 使用同名构造参数与 `context.sectionInsets`。它映射到 UIKit Section.contentInsets，不替代 collection view 的 contentInset、cell padding 或 DecorationItemLayout.backgroundInsets。详见[Section 内边距语义](Documentation/Layout-API.md#section-内边距)。

其余布局修饰方法同样明确作用对象：`crossAxisSize`、`trackSpacing`、`lineSpacing`、`groupSpacing`、`lineGrouping`、`alignment`；轨道使用 `spacing`，背景使用 `backgroundInsets`，补充视图区分 `absoluteOffset` 与 `anchorFractionalOffset`。完整说明见[名称与作用对象](Documentation/Layout-API.md#名称与作用对象)。

公开 API 参照 SwiftUI 统一命名，迁移时对应替换：

| 原名称 | 当前名称 |
| --- | --- |
| `adaptive(minimumForCount:maximum:)` | `adaptive(minimum:maximum:)` |
| `ListGridTrack.spacingAfter` / `spacingAfter:` | `ListGridTrack.spacing` / `spacing:` |
| `onDisplay` / `onEndDisplay` | `onAppear` / `onDisappear` |
| `onTap` | `onTapGesture` |
| `gridCrossAxisSize` | `crossAxisSize` |
| `trackGroupAlignment` / `ListGridTrackGroupAlignment` | `alignment` / `ListGridAlignment` |
| `ListLayoutScrollDirection` | `ListAxis` |

`onAppear` / `onDisappear` 仍对应 UIKit 的 willDisplay / didEndDisplaying 回调，闭包继续接收视图、上下文及适用的 model；它们可能随复用多次触发，测量 cell 不触发展示回调。`onTapGesture` 仅用于支持点击手势的 supplementary，仍识别单击。Row 的选择、主操作与刷新继续使用 `onSelect`、`onPrimaryAction`、`refresh`。

命名参考：[SwiftUI 生命周期与手势](https://developer.apple.com/documentation/swiftui/view-input-and-events)、[LazyVGrid](https://developer.apple.com/documentation/swiftui/lazyvgrid)、[Axis](https://developer.apple.com/documentation/swiftui/axis)。这些调整只改变公开名称，布局、复用和回调时机保持原有契约；旧名称不保留兼容别名。


Grid 默认 item 主轴尺寸为 `.estimated(44)`：纵向估算高度、横向估算宽度，44 不是固定尺寸，最终由 cell 的 self-sizing 决定。需要正方形时显式设置 `.itemMainAxisSize(.aspectRatio(1))`。
