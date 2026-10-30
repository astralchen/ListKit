# Section 整体布局

`layout:` 返回一个完整布局值。普通列表、网格和正交滚动统一使用 `GridLayout(tracks:)`；内容声明继续负责注册、身份、刷新与事件。

## 入口与默认值

| 入口 | 用途 |
| --- | --- |
| `GridLayout(tracks: 1)` | 单行或单列；默认主轴 estimated(44)、间距 0、起始对齐，无正交滚动 |
| `GridLayout(tracks: 3)` | 三条等分轨道，方向随环境解析 |
| `GridLayout(tracks: [ListGridTrack])` | fixed / flexible / adaptive 混合轨道 |
| `UIKitListLayout(...)` | 原生列表配置、分隔线和 Row swipe actions；不支持 item supplementary |
| `CustomLayout(layoutKey:)` | 基于真实 context 生成 UIKit section |
| `EnvironmentLayout(layoutKey:)` | 按环境返回一个完整布局分支 |

`ListLayout`、`HorizontalLayout`、`GridLayout(columns:)`、`GridLayout(rows:)` 及其独立模型已移除。没有 `OrthogonalLayout` 或 `VerticalLayout` 容器。

空 builder、nil、EnvironmentLayout 空分支及 provider 解析失败的默认回退为 `GridLayout(tracks: 1)`。显式单轨道 Grid 与回退布局的默认配置一致：item 主轴 estimated(44)，trackSpacing 与 lineSpacing 均为 0，groupSpacing 为 nil（跟随 lineSpacing）。轨道数量不会自动改变 item 尺寸策略。

默认 `.estimated(44)` 中的 44 是初始主轴估算值，不是固定行高：纵向内容估算高度，横向内容估算宽度，最终尺寸由 cell 的 self-sizing 决定。所有轨道数量及两种 tracks 构造入口使用同一默认值。正方形 item 需要显式 `.itemMainAxisSize(.aspectRatio(1))`。默认估算策略同样遵守下文的 estimated 分组限制；固定分页容量应显式选择确定尺寸或 fillGroup。

## 名称与作用对象

修饰方法优先写出被修改的布局对象。已经由接收类型限定的值（如 BoundarySupplementaryLayout.size、alignment、zIndex）不重复加前缀；存在多个合理作用对象或参考基准时，在名称中区分。

| 旧入口 | 当前入口 | 作用对象与参考基准 |
| --- | --- | --- |
| crossAxisSize | gridCrossAxisSize | 全部轨道共同占用的交叉轴区域，不是单个 item 或整个 collection |
| groupLineSpacing | lineSpacing | 内容方向上相邻行／列的统一间距，默认也用于组间 |
| spacing / gridSpacing | trackSpacing + lineSpacing | 分别设置轨道与内容方向间距；特殊组间距用可选 groupSpacing 覆盖 |
| group / ListGridGrouping | lineGrouping / ListGridLineGrouping | 将基本行／列组合成顶层 group；不直接按 item 数量分组 |
| trackAlignment / ListGridTrackAlignment | trackGroupAlignment / ListGridTrackGroupAlignment | 整组轨道在 gridCrossAxisSize 内的对齐，不是每个 cell 的内部对齐 |
| ListGridTrack.spacing | ListGridTrack.spacingAfter | 每条展开轨道到下一条轨道的交叉轴间距；最后一条后不加间距 |
| BoundarySupplementaryLayout 的 axis: | sizingAxis: | 仅决定尺寸推导轴，不改变边界位置或滚动轴 |
| pinned | pinToVisibleBounds | 将边界固定到可见区域的对应边缘，支持吸顶和横向吸边 |
| offset | absoluteOffset | 边界相对 alignment 的点数偏移 |
| ItemSupplementaryLayout 的 anchor: / anchor | itemAnchor: / itemAnchor | 相对于所属 item 的 containerAnchor |
| fractionalOffset | anchorFractionalOffset | item 补充视图的 containerAnchor 比例偏移，与边界绝对偏移区分 |
| DecorationItemLayout 的 insets: / insets | backgroundInsets: / backgroundInsets | 背景 decoration 自身的收缩量，不改变 item 或 Section 布局 |

上述旧入口已移除，不保留兼容别名。`lineSpacing` 默认 0，同时用于组内和未覆盖的组间距；每组只有一个基本行／列时仍通过组间距生效。`groupSpacing` 默认 nil，显式值（包括 0）覆盖组间距，传 nil 恢复跟随当前 lineSpacing。`orthogonalScrolling` 仅设置当前 Section 的正交滚动行为；外层方向由 ListCompositionalLayoutConfiguration.scrollDirection 配置。`sectionInsets`、`itemMainAxisSize`、`trackSpacing`、`lineSpacing`、`groupSpacing`、`boundarySupplementaries`、`itemSupplementaries` 已能区分作用对象，继续保留。

## 自动方向

| 外层 collection | 正交滚动 | 内容方向 | tracks 的含义 |
| --- | --- | --- | --- |
| vertical | 无 | vertical | 列宽 |
| horizontal | 无 | horizontal | 行高 |
| vertical | 有 | horizontal | 行高 |
| horizontal | 有 | vertical | 列宽 |

同一 collection 中每个 section 独立解析。Grid 不修改外层滚动方向。纵向按行填充，横向按列填充，不重排模型数据。

```swift
// 普通自适应列表：纵向时估算高度，横向时估算宽度。
GridLayout(tracks: 1).itemMainAxisSize(.estimated(60)).trackSpacing(8).lineSpacing(8)

// 纵向页面中的单行横向卡片。
GridLayout(tracks: 1)
    .itemMainAxisSize(.fixed(92)).trackSpacing(10).lineSpacing(10)
    .gridCrossAxisSize(.fixed(112))
    .orthogonalScrolling(.continuous)

// 横向页面中的两列纵向内容。
GridLayout(tracks: 2)
    .itemMainAxisSize(.fixed(72)).trackSpacing(10).lineSpacing(10)
    .gridCrossAxisSize(.fixed(300))
    .orthogonalScrolling(.continuous)
```

## 轨道与对齐

```swift
GridLayout(tracks: [
    ListGridTrack(.fixed(80)),
    ListGridTrack(.flexible(minimum: 100, maximum: 180)),
    ListGridTrack(.adaptive(minimumForCount: 72), spacingAfter: 6)
])
.itemMainAxisSize(.aspectRatio(4.0 / 3.0))
.trackSpacing(12).lineSpacing(12)
.trackGroupAlignment(.center)
.sectionInsets(.init(16))
```

`tracks: Int` 创建最小尺寸为 1 点的等分弹性轨道。`ListGridTrack(.flexible())` 默认 minimum 为 10。数量范围 1...10000。adaptive 可以展开为多条，定义数量不是最终轨道数量，更不是数据 item 数量。

先预留固定尺寸和间距，再按定义顺序分配非固定轨道，最后展开 adaptive。已分配的轨道不再次分配。fixed/flexible 在空间不足时仍保留固定值/最小值；adaptive 的 minimumForCount 用于计算展开数量，窄空间下实际尺寸可能更小。maximum 限制后的剩余空间不会重新分配。算法不复刻 SwiftUI 的多轮提议尺寸测量。

`.trackGroupAlignment(.start)` 是默认值。它控制整组轨道在剩余交叉轴空间中的位置：

| 对齐 | 纵向内容 | 横向内容 |
| --- | --- | --- |
| start | leading，支持 RTL | top |
| center | 水平居中 | 垂直居中 |
| end | trailing，支持 RTL | bottom |

不控制 cell 内部内容，不改变分页方式。轨道已占满或超出交叉轴空间时不再偏移。

## Section 内边距

`.sectionInsets(...)` 设置当前 Section 的方向性内边距，映射到 `NSCollectionLayoutSection.contentInsets`。它不设置 collection view 的 contentInset、cell 内部 padding 或 decoration 的背景收缩量，也不随内容轴交换 top/leading 等边缘。

```swift
GridLayout(tracks: 2)
    .sectionInsets(.init(top: 8, leading: 16, bottom: 12, trailing: 16))
    .gridCrossAxisSize(.fixed(220))
```

未指定 gridCrossAxisSize 时，网格按环境的有效交叉轴长度减去 Section 对应两侧 inset 分配轨道。显式 gridCrossAxisSize 已是轨道区域尺寸，不再从中扣 inset；例如横向内容的主体高 220，Section top/bottom 各 8，则主体与两侧 inset 合计占 236 点，boundary 额外占位另按 UIKit 规则计算。fractionalViewport 从环境的内容主轴长度扣除相应两侧 Section inset。

Grid 默认 inset 为零；UIKitListLayout 省略时保留系统值，显式 `.sectionInsets(.zero)` 会覆盖它。CustomLayout 使用构造参数 `sectionInsets:`，provider 从 `context.sectionInsets` 读取并在构建几何时消费，返回的 UIKit Section.contentInsets 必须一致。重复设置取最后一次，不累加。

Section inset 不等于“给所有 header/footer 加 padding”；边界的位置、extendsBoundary 和 fractional dimension 仍遵循 UIKit。`DecorationItemLayout.backgroundInsets` 只收缩背景，`collectionView.contentInset` 与全局 `contentInsetsReference` 由宿主独立配置。

## 三层尺寸

### itemMainAxisSize：item 的内容主轴尺寸

`ListGridItemMainAxisSize` 专用于 Grid item。交叉轴由轨道决定，内容纵向时 itemMainAxisSize 控制高度，横向时控制宽度。

| 配置 | 含义 |
| --- | --- |
| `.fixed(92)` | 固定主轴点数 |
| `.estimated(60)` | item 与内容 group 使用 estimated，依赖真实 self-sizing |
| `.aspectRatio(1)` | 宽÷高；两个方向含义相同，各轨道分别推导尺寸 |
| `.uniform(estimated: 60)` | iOS 17+；同一基本行或列统一主轴尺寸，不扩展到整个分页 group |
| `.fractionalViewport(0.84)` | 相对于扣除对应 section inset 后的内容 viewport 主轴长度 |
| `.fractionalGroup(0.4)` | 相对于显式 group 主轴长度，不提前扣除内部间距 |
| `.fillGroup` | 显式 lines 与 mainAxisSize 扣除 lineSpacing 后等分 |

边界视图使用独立的 `ListBoundaryMainAxisSize`，只提供 fixed、estimated 和 aspectRatio，不接受 uniform、fillGroup 或分页比例。item 与 boundary 不共享公开尺寸类型；二维 boundary 尺寸中的 `ListLayoutDimension.absolute` 等保持不变。

### gridCrossAxisSize：整个轨道区域的交叉轴尺寸

```swift
.gridCrossAxisSize(.fixed(220))     // 纵向内容为宽 220；横向内容为高 220
.gridCrossAxisSize(.estimated(80))  // 单轨道的交叉轴估算值
.gridCrossAxisSize(nil)             // 恢复使用环境可用尺寸
```

它控制整个网格主体的轨道区域，不包含 Section inset 或 boundary 的额外占位。内容方向改变时尺寸随轴解释；不提供物理 width/height 参数，也不控制主轴 viewport、cell 内部 frame 或裁剪。

fixed 完整预留指定区域，剩余空间按 trackGroupAlignment 分配。轨道及间距超出指定区域时会诊断。未指定时，轨道可用空间取 environment.container.effectiveContentSize 并扣除 Section 交叉轴 inset 一次；显式值已是内容尺寸，不再扣 inset。

estimated 同时设置 item 和 group 的交叉轴估算值，需要 cell 实现 self-sizing。仅支持 `tracks: 1`，且不能配合 `.aspectRatio(...)`。例如：

```swift
GridLayout(tracks: 1)
    .itemMainAxisSize(.fixed(92))
    .gridCrossAxisSize(.estimated(80))
    .orthogonalScrolling(.continuous)
```

重复调用完整替换交叉轴尺寸策略，nil 清除显式约束。所有相对计算基于局部布局环境，不使用 UIScreen。

### lineGrouping：基本行／列组合与主轴长度

基本单元为内容纵向时的一行、横向时的一列；单轨道时就是一个 item。

```swift
.lineGrouping(.count(lines: 3)) // 三个基本单元，group 长度由内容推导
.lineGrouping(.count(lines: 3, mainAxisSize: .fractionalViewport(1)))
.lineGrouping(.fitting(mainAxisSize: .fractionalViewport(1)))
```

`count` 不是 item 总数：两条实际轨道 × count(lines: 3) = 每组最多 6 个 item；adaptive 使用展开后的实际轨道数。省略 lineGrouping 等价于 `.count(lines: 1)`。

显式 group 尺寸支持 `.fixed(...)` 和 `.fractionalViewport(...)`。fitting 依据已解析的单元尺寸和间距计算容量，保留指定 group 长度与尾部空白；不会把 fixed item 拉伸。

estimated/uniform 主轴内容使用内容推导的 group，不支持固定容量 fitting 或显式固定 group 长度。这些组合会被拒绝，因为估算尺寸不能保证最终容纳数量。含 item supplementary（如 badge）的 estimated/uniform 支持 `.count(lines: n)`：每个基本行／列独立测量，uniform 只统一该基本单元内的 item。typed SectionSupplementary 自动处理实际 kind 与 indexPath 映射；自定义 provider 使用下文的映射重载。需要保留 UIKit 原生估算重复行为的旧布局，使用后面的 CustomLayout 迁移方案。

**估算主轴的吸附限制：** iOS 26.5 的真实手势复现中，`groupPaging` 和 `continuousGroupLeadingBoundary` 仍按初始估算 group 长度计算停靠，而 item/group 几何已经按内容变大，造成停靠偏差。这是当前未解决的支持边界，`count(lines:)` 正确分组不代表这些行为能精确停靠。需要动态内容时使用 `.continuous`；要求精确分页时使用确定的主轴尺寸与 group 长度。ListKit 仍原样传递调用方选择的原生滚动行为，不自动替换。`groupPagingCentered` 与其他系统版本的估算吸附本轮未验证。

尾组不足时保留原尺寸和空位，不拉伸剩余 item。容量、尺寸循环、fillGroup 缺少约束、固定 item 溢出和非法数值会诊断。每个 group 最多 10000 个 item。

## 滚动与间距

`.orthogonalScrolling(...)` 开启正交滚动，并让内容轴与外层轴垂直。tracks、itemMainAxisSize 和 gridCrossAxisSize 都随内容轴解释；它不改写这些策略或分组配置。省略或 `.orthogonalScrolling(nil)` 跟随外层方向，nil 可用于关闭复用布局值上的正交滚动。

| 行为 | 含义 |
| --- | --- |
| continuous | 连续滚动 |
| continuousGroupLeadingBoundary | 在顶层 group 的起始边界停靠 |
| paging | UIKit 原生正交视口分页 |
| groupPaging | 按顶层 group 分页 |
| groupPagingCentered | 顶层 group 居中分页 |

它们不是 SwiftUI viewAligned 的别名。一个 group 可以包含多个 item，居中 group 不保证每个 item 居中。

```swift
// 两行、每组 3 列，共 6 个 item；纵向外层。
GridLayout(tracks: 2)
    .itemMainAxisSize(.fillGroup).trackSpacing(10).lineSpacing(10)
    .gridCrossAxisSize(.fixed(220))
    .lineGrouping(.count(lines: 3, mainAxisSize: .fractionalViewport(1)))
    .groupSpacing(16)
    .orthogonalScrolling(.groupPaging)
```

- trackSpacing：轨道间的默认交叉轴间距，默认 0。
- lineSpacing：沿内容方向相邻行／列的统一间距，默认 0；用于组内，也作为组间距的默认值。
- groupSpacing：顶层 group 之间的可选覆盖，类型 CGFloat?，默认 nil；实际组间距为 `groupSpacing ?? lineSpacing`。0 表示明确无组间距，nil 恢复跟随。
- ListGridTrack.spacingAfter：单条轨道的显式间距覆盖；最后一条实际轨道后不追加间距，nil 使用 trackSpacing。
- 显式 groupSpacing 与 lineSpacing 的调用顺序无关：`.groupSpacing(20).lineSpacing(8)` 和 `.lineSpacing(8).groupSpacing(20)` 的组间距都为 20。对同一属性重复设置仍以后一次为准。
- `gridSpacing` 已删除，无兼容别名。统一间距改写为 `.trackSpacing(8).lineSpacing(8)`；不修改 sectionInsets 或 interSectionSpacing。

默认值与示例预设不同：库的 `trackSpacing = 0`、`lineSpacing = 0`、`groupSpacing = nil`；Layout Lab 普通网格显式使用 `trackSpacing = 10`、`lineSpacing = 10`，组间距仍为 nil 跟随。

以下调用接在同一个初始 Grid 后，结果如下；`nil` 恢复的是跟随关系，不是把当前行间距复制一次：

| 调用序列 | 组内间距 | 实际组间距 |
| --- | --- | --- |
| `.lineSpacing(12)` | 12 | 12 |
| `.groupSpacing(24).lineSpacing(12)` | 12 | 24 |
| `.lineSpacing(12).groupSpacing(24)` | 12 | 24 |
| `.groupSpacing(0).lineSpacing(18)` | 18 | 0 |
| `.lineSpacing(12).groupSpacing(12).lineSpacing(18)` | 18 | 12 |
| `.groupSpacing(24).groupSpacing(nil).lineSpacing(18)` | 18 | 18 |
| `.groupSpacing(24).lineSpacing(18).groupSpacing(nil)` | 18 | 18 |

显式 group 主轴尺寸大于内容占用时，group 内仍可能保留尾部空白；lineSpacing 统一的是布局间距，不会压缩显式 group 尺寸。

fillGroup 必须与显式 `.count(lines:mainAxisSize:)` 配合；从 group 长度扣除 lineSpacing 后等分。fractionalGroup 乘的是完整 group 长度，不扣间距：300 点、3 个 line、间距 10 时，fillGroup 为 93.33 点，而 fractionalGroup(1/3) 为 100 点并因总长度 320 而溢出。

## 从旧布局迁移

| 旧配置 | 新配置 |
| --- | --- |
| `ListLayout(itemHeight: .estimated(44))` | `GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0)` |
| `GridLayout(columns: n)` | `GridLayout(tracks: n)`，核实实际内容方向仍纵向 |
| `GridLayout(rows: n)` | `GridLayout(tracks: n)`，核实实际内容方向仍横向 |
| columns/rows 的 alignment | `.trackGroupAlignment(.start/.center/.end)` |
| 固定尺寸 HorizontalLayout | 单轨道 Grid + gridCrossAxisSize + fitting + orthogonalScrolling |

原普通 List 总是以高度描述尺寸，新 Grid 是内容主轴尺寸；非纵向使用必须审查，不能只替换名称。Grid 默认 trackSpacing 与 lineSpacing 均为 0，groupSpacing 为 nil（跟随 lineSpacing）；需要视觉间隔时显式设置 trackSpacing 和 lineSpacing，特殊组间距再设置 groupSpacing。

保留旧固定尺寸横向布局的整宽 group：

```swift
EnvironmentLayout(layoutKey: "legacy-fixed-strip") { environment in
    GridLayout(tracks: 1)
        .itemMainAxisSize(.fixed(92)).trackSpacing(10).lineSpacing(10)
        .gridCrossAxisSize(.fixed(112))
        .lineGrouping(.fitting(mainAxisSize: .fixed(environment.container.effectiveContentSize.width)))
        .groupSpacing(10)
        .orthogonalScrolling(.continuousGroupLeadingBoundary)
        .sectionInsets(.init(top: 8, leading: 14, bottom: 12, trailing: 14))
}
```

旧 `.fractionalWidth(1)` group 使用环境的完整有效宽度；新 `.fractionalViewport(1)` 则扣除 section 主轴 inset。存在 inset 时二者不等价，会改变容量和停靠点。上例通过 EnvironmentLayout 在尺寸变化时重算完整 group 宽度。

省略 fitting 会改成一个 item 一个 group，停靠点随之改变。旧 itemHeight 实际是 group 高度；新 gridCrossAxisSize 明确表示区域交叉尺寸。

旧 estimated 宽度 + 整宽分页、复杂 fractionalWidth/fractionalHeight 或 `.none` 如果必须逐层保持原 UIKit 参考对象，使用 CustomLayout：

```swift
CustomLayout(layoutKey: "legacy-estimated-strip") { context in
    let item = NSCollectionLayoutItem(
        layoutSize: .init(widthDimension: .estimated(44), heightDimension: .fractionalHeight(1)),
        supplementaryItems: context.itemSupplementaries)
    let group = NSCollectionLayoutGroup.horizontal(
        layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(44)),
        subitems: [item])
    group.interItemSpacing = .fixed(10)
    let section = NSCollectionLayoutSection(group: group)
    section.interGroupSpacing = 10
    section.orthogonalScrollingBehavior = .groupPagingCentered
    section.contentInsets = context.sectionInsets?.directionalEdgeInsets ?? .zero
    return section
}
```

按照原布局替换各层 dimension 与行为；捕获业务参数时纳入 layoutKey。不要把旧 estimated 直接改为固定 gridCrossAxisSize，也不要把所有 fractionalWidth 都替换为 fractionalViewport；它们的父级参考对象可能不同。

如果产品意图是按内容尺寸逐卡片滚动，可以有意迁移为 `.itemMainAxisSize(.estimated(...)).gridCrossAxisSize(.estimated(...)).orthogonalScrolling(.continuous)` 的自然分组；这不是旧整宽 group 的完全等价替换。

## 边界与 item 补充视图

不设置通用 Header/Footer 角色。边界的位置只由 alignment 决定，`.top` 不随滚动轴自动变成 `.leading`，kind 不参与角色推断。leading/trailing 使用方向性语义，不是固定左右；item 的 `ListItemSupplementaryAnchor.center` 使用中心锚点；boundary 使用独立的 `ListBoundaryAlignment`，仅提供 `.none` 表示 UIKit 无边界对齐，不提供 `.center`，也不承诺居中。

`boundarySupplementaries` 接受多个元素；每个元素支持二维尺寸、alignment、`.pinToVisibleBounds()`、`.extendsBoundary(...)`、`.absoluteOffset(...)` 和 `.zIndex(...)`。多个同侧元素遵循 UIKit 边界布局规则，不承诺 VStack 式排列。

默认 `extendsBoundary` 为 true、`pinToVisibleBounds` 为 false、absoluteOffset 为零、zIndex 为 0。`.pinToVisibleBounds()` 开启 UIKit 的 `pinToVisibleBounds`；`.absoluteOffset(...)` 是相对 alignment 的绝对偏移，单位为点。ListKit 不会为 absoluteOffset 或 extendsBoundary 额外修改 Section inset。

需要由交叉轴推导尺寸时使用显式主轴：

```swift
BoundarySupplementaryLayout(
    kind: title,
    mainAxisSize: .aspectRatio(4),
    sizingAxis: .vertical,
    alignment: .top
)
```

这里的 `sizingAxis` 只决定尺寸计算，不改变 alignment 或滚动方向：vertical 控制高度并使用 `.fractionalWidth(1)`，horizontal 控制宽度并使用 `.fractionalHeight(1)`。比例计算以 `effectiveContentSize` 扣除 Section 交叉轴 inset 后的尺寸为基准，至少取 1 点。

Item 附件使用独立规则，不能吸顶：

```swift
GridLayout(tracks: 3).itemSupplementaries {
    ItemSupplementaryLayout(
        kind: "badge",
        size: .init(width: .absolute(18), height: .absolute(18)),
        itemAnchor: .topTrailing
    ).anchorFractionalOffset(CGPoint(x: 0.2, y: -0.2)).zIndex(2)
}
```

item supplementary 的 itemAnchor 相对于所属 item，不是 Section 边界。`.anchorFractionalOffset(...)` 传给 UIKit containerAnchor，使用比例而非点数，默认零；zIndex 默认 0。

Grid 启用 item supplementary 时，要求实际解析出的轨道尺寸相等且轨道间距一致；异构组合会被 adapter 拒绝。原生 UIKit List 不提供 itemSupplementaries 修饰方法，此类组合在编译期被拒绝。CustomLayout 需要自行将 `context.itemSupplementaries` 安装到 item 上。

supplementary 内容和几何直接通过同一个非空 `kind: String` 关联。普通布局原样使用这个 kind；estimated/uniform 多 line Grid 为各基本单元生成内部实际 elementKind，以避免 UIKit 的重复 kind 冲突。UIKit 对每个实际 kind 独立编号，因此实际 supplementary indexPath 与所属 item indexPath 可能不同。业务声明、刷新及事件继续使用业务 kind/所属 item 位置。每个 Section 内一个 kind 只能声明一份内容，并且只能附着到一条 boundary 或 item 规则；不同 Section 可以复用 kind。内容 id 表示业务身份，refreshID 表示内容版本。kind 和视图类型也参与展示 identity，改变它们不等同于仅更新内容版本。

自适应多 line 的 badge 示例：

```swift
GridLayout(tracks: 2)
    .itemMainAxisSize(.estimated(60))
    .lineGrouping(.count(lines: 3))
    .trackSpacing(10).lineSpacing(12).groupSpacing(20)
    .itemSupplementaries {
        ItemSupplementaryLayout(kind: "badge",
            size: .init(width: .absolute(16), height: .absolute(16)), itemAnchor: .topTrailing)
    }
```

用 `SectionSupplementary(BadgeView.self, kind: "badge", id: ...)` 声明一次内容即可。configure、onTap、onDisplay 和 onEndDisplay 中的 `context.indexPath` 是所属 item 的位置。`reconfigureVisibleSupplementaries(ofKind:forRowID:in:)` 按业务 row identity 查询，在重排后仍指向该 row。

需要直接查询 UIKit 时，先取得实际地址；不要把业务 item 的 indexPath 与实际 kind 混用，也不要缓存地址跨布局／数据更新：

```swift
if let address = adapter.supplementaryElement(ofKind: "badge", at: itemIndexPath) {
    let view = collectionView.supplementaryView(
        forElementKind: address.elementKind, at: address.indexPath)
}
```

自定义 provider 使用接收实际 elementKind 的重载。provider 的 `indexPath` 用于 UIKit dequeue，`context.indexPath` 用于业务，两者职责不同：

```swift
ProviderSupplementary("badge", id: "badge", view: BadgeView.self) {
    collectionView, elementKind, indexPath, context in
    let view = collectionView.lk.dequeue(BadgeView.self, ofKind: elementKind, for: indexPath)
    view.configure(item: context.indexPath.item)
    return view
}
```

自定义 register 闭包同样可接收 `(collectionView, elementKind)`。旧三参数 viewProvider 在原有不需要映射的布局中保持可用；自适应多 line 布局会在构建前要求迁移该 provider。原始 UIKit delegate 转发和 visibleItemsInvalidationHandler 仍携带 UIKit 的实际标识；ListKit 的业务事件与刷新入口负责转换。

同一 Section、同一 kind 下，业务 id 或视图类型改变属于身份替换：当该 kind 的几何已启用且仍需显示时，框架重新加载受影响的已有 Section，使 supplementary 进入完整配置/复用路径。仅保留内容注册、未启用几何的 kind 不因此重新加载 Section；环境布局以当前真实环境解析的新分支为准。屏幕外但已启用的 kind 仍参与替换判断。直接提供的 FlowLayout 或未通过 `makeCompositionalSection` 解析的外部布局没有可验证的 kind 启用元数据，保留原有的保守重载行为，不用 DSL 缺省值推断其几何。切换 collection layout 时清理旧布局的解析和滚动记录。

Section 重载同时覆盖该 Section 的其他 supplementary 和 Row，与逐项 reconfigure/reload 互斥；身份替换不受 `.never` 内容刷新策略限制。Row 会重新配置，可能更换实例或执行 `prepareForReuse`，不保证 cell 内部临时状态、输入焦点或编辑内容保留。选择按 Row identity 恢复。

框架创建的 compositional layout 在身份替换时按 Section identity 保留正交滚动偏移，包括 Section 移动和屏幕外 Section 返回可见范围；内容缩短时限制在新布局的有效范围内。恢复先于调用方的显式滚动行为执行。此行为不修改业务 cell 内部嵌套的滚动视图。身份保持不变、仅 refreshID 改变时，继续按刷新规则重配可见 supplementary；默认动作不重新加载 Section，也不额外失效布局。

几何引用缺失内容默认报错；`.whenContentExists()` 显式允许当前 Section 缺少相同 kind 的内容声明，缺少时跳过对应几何。它不按屏幕可见性或逐 item 状态筛选，也不跳过尺寸、kind 唯一性和 provider 所有权校验。声明了内容但当前布局未使用该 kind 时，只保留注册，不生成隐式边界。事件直接使用内容的 `.onTap`、`.onDisplay` 等方法。

## Decoration 集合

布局侧使用 `.decorationItems { DecorationItemLayout(...) }`；注册侧使用 `decorations: { SectionDecoration(...) }` 或 Section 的 `.decorations { ... }`。支持多个装饰元素，每个元素通过逻辑 `kind: String` 关联注册。UIKit 的 background decoration 仍是底层实现，不需要公开第二套 background DSL。

`SectionDecoration.kind` 是 Section 内的逻辑 kind，同一 Section 内不可重复，不同 Section 可以复用。逻辑 kind 不能直接用于 UIKit 注册或 attributes 查询。typed 注册的 `elementKind` 由逻辑 kind 和视图类型确定性生成，作为 UIKit 的实际注册与复用标识。同一逻辑 kind 从 View A 切换到 View B 时，UIKit 会替换元素，不会继续复用 A；其他 Section 可以继续使用 A。

查询 decoration attributes 时使用 `SectionDecoration.elementKind`；自定义 provider 使用 `context.decorationElementKind(for:)`。手动注册入口为 `SectionDecoration(kind:elementKind:)`，原样使用传入的实际标识，由调用方负责注册；逻辑 kind 由调用方显式指定。改变手动 elementKind 也会触发布局更新。

物理冲突仅按实际 `elementKind` 检查。同一 Section 的当前装饰几何不能重复使用一个实际标识，typed/manual 混用也遵循此规则；未启用的逻辑 kind 可以保留注册。不同 Section 可以共享同一有效注册。静态几何冲突在 apply 前诊断；环境选择器中的几何冲突在解析环境后诊断。手动注册的视图类型由调用方管理，框架无法检查外部注册表，不应手动覆盖框架生成的 typed elementKind。

```swift
let typed = SectionDecoration(CardView.self, kind: "card")
// typed.kind 是逻辑名称；typed.elementKind 才是 UIKit 注册标识。
let manual = SectionDecoration(kind: "overlay", elementKind: "app.overlay")
layout.registerDecorationView(OverlayView.self, forKind: manual.elementKind)
```

`.decorationItems(.registeredBackgrounds)`（也是省略时的默认值）为所有声明的装饰生成零 inset、zIndex -1 的默认背景几何；显式 `.decorationItems(.none)` 关闭框架生成的背景，仍保留注册，也不删除 CustomLayout provider 自有的 decoration。

`DecorationItemLayout.backgroundInsets` 只作用于背景 decoration 自身，不改变 Section 或 cell 的 inset；backgroundInsets 须为有限非负数。`.whenContentExists()` 判断当前 Section 是否存在相同逻辑 kind 的注册声明，缺少时跳过背景，不代替视图注册。backgroundInsets 和 zIndex 只保存在布局值中，注册对象不保存几何。没有额外的 items-only 或 visible-only 覆盖模式。

## Section 的三种组合方式

多闭包和链式入口生成相同的 Section 描述，可以按代码组织需要选择。rows、supplementary 内容、decoration 注册和完整布局各自保持明确职责。

```swift
let titleKind = "title"
let cardKind = "card"
let count = 3
let rows = ForEach(0..<count, id: \.self) { value in
    Row(model: value, cell: UICollectionViewCell.self) { _, _, _ in }
}
let layout = GridLayout(tracks: 1)
    .itemMainAxisSize(.estimated(44))
    .trackSpacing(8).lineSpacing(8)
    .boundarySupplementaries {
        BoundarySupplementaryLayout(
            kind: titleKind,
            size: .init(width: .fractionalWidth(1), height: .absolute(36)),
            alignment: .top
        )
    }
let title: ListSectionSupplementary<Int> = SectionSupplementary(
    UICollectionReusableView.self, kind: titleKind, id: "title"
) { view, _ in
    view.accessibilityLabel = "\(count) items"
}
.refreshID(count)
let card = SectionDecoration(UICollectionReusableView.self, kind: cardKind)

// 一次完整声明。
let inline = ListSection(0) {
    rows
} layout: {
    layout
} supplementaries: {
    title
} decorations: {
    card
}

// 分步组合，行为与上面的多闭包声明一致。
let chained = ListSection(0) { rows }
    .layout { layout }
    .supplementaries { title }
    .decorations { card }
```

第三种方式是把这些值进一步提取成属性和方法：布局属性返回 `ListSectionGridLayout`，rows 方法返回 `RowGroup`，header 方法返回 `ListSectionSupplementary<SectionID>`。在每次构建 Section 时把当前数量、标题等动态数据传给内容方法，不缓存捕获旧状态的内容描述。完整实例见 Examples 的 `LiveRoomViewModel.makeMessagesSection()`。

| Section 入口 | 重复调用 | 空 builder |
| --- | --- | --- |
| `.layout { }` | 替换完整布局及其几何修饰 | 恢复默认单轨道估算布局 |
| `.supplementaries { }` | 替换补充内容集合 | 清空补充内容 |
| `.decorations { }` | 替换装饰注册集合 | 清空装饰注册 |
| `.addingSupplementaries { }` | 按顺序追加补充内容 | 保留原集合 |
| `.addingDecorations { }` | 按顺序追加装饰注册 | 保留原集合 |

集合 builder 支持多个值、数组、Optional、条件和循环；同一次 builder 内按顺序收集，不静默去重。追加相同 supplementary kind 或 decoration 逻辑 kind 仍由正常校验报告冲突。

内容设置和追加不改写显式布局。清空内容后，如果布局仍要求该 kind，则报告缺失绑定；可以同时替换布局，或为确实允许缺少声明的共享布局使用 `.whenContentExists()`。它检查对应内容／注册声明是否存在，与 rows 是否为空无关。无条件声明 header 和 decoration 的普通示例无需加这个修饰。

布局省略 `decorationItems` 时，默认按当前装饰注册生成背景；因此新增注册会获得默认背景，清空注册会移除这些默认背景。显式 decoration 几何仍由完整布局值决定。

普通示例可以省略 Row 的 `.refresh(when: .automatic)` 和 `DecorationItemLayout` 的 `zIndex: -1`，两者均为默认值；保留业务需要的 `refreshID`、布局尺寸和 inset 即可。

## 状态、环境与单值语义

`layout:` 只接受零或一个布局，支持 optional 和 if/else；多个并列布局编译失败。省略或 nil 使用默认普通列表。Supplementary 和 decoration 集合接受多个值、数组、循环与可选分支。

同一布局修饰方法再次调用时替换整个属性/集合，不隐式合并；同一次集合 builder 内则按声明顺序合并元素、数组和分支，不去重。Section 的 `.layout { ... }` 替换完整布局及修饰配置，保留内容和注册声明；新的布局若省略 `decorationItems`，仍会按保留的注册生成默认背景。Section 的 `.supplementaries { ... }` 和 `.decorations { ... }` 分别替换内容与注册集合；`.addingSupplementaries { ... }` 和 `.addingDecorations { ... }` 则显式追加。

```swift
layout: {
    EnvironmentLayout(layoutKey: layoutRevision) { environment in
        if environment.container.effectiveContentSize.width >= 600 {
            GridLayout(tracks: 4).trackSpacing(12).lineSpacing(12).sectionInsets(.init(20))
        } else {
            GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(8).lineSpacing(8).sectionInsets(.init(12))
        }
    }
}
```

环境选择器返回完整布局。公共修饰放在分支内部，选择器本身不接受外层几何覆盖。使用实际 effectiveContentSize，不依赖 UIScreen。闭包无法比较，EnvironmentLayout 和 CustomLayout 的 layoutKey 必须涵盖影响几何的业务捕获状态；环境变化本身不要求修改 layoutKey。

Section 的空 layout builder、nil 和 EnvironmentLayout 的空分支都回退到默认单轨道估算布局，不会保留上次布局，也不会隐藏 Section。需要隐藏 Section 时，应在内容 builder 中按条件省略该 Section。

## 自定义 UIKit Section

`CustomLayout(layoutKey:)` 的 context 包含 section、sectionIndex、environment、显式 sectionInsets、itemSupplementaries 和 `decorationElementKind(for:)`。supplementary provider 直接使用与内容相同的 kind，无需查询 Slot 映射。

每次解析根据 context 构建 Section，不缓存可变的 UIKit Section 对象。CustomLayout 的相等性比较 layoutKey 与修饰配置；EnvironmentLayout 仅比较 layoutKey，二者均不比较闭包本身。

没有显式 inset 时由 provider 管理；使用 `CustomLayout(layoutKey:sectionInsets:)` 传入 inset 时 provider 必须在构建几何时使用 context.sectionInsets，并在返回的 Section 上设置同值。框架会诊断不匹配，不事后改写 group 树。provider 负责把 context.itemSupplementaries 挂到 item。

Grid 和 UIKitListLayout 的 boundarySupplementaries 只接受 BoundarySupplementaryLayout，不能引用 provider 边界。CustomLayout 的 builder 使用 ListBoundaryLayout 保留 generated/provided 所有权，支持两种声明混排、数组和可选值。框架负责边界几何时使用普通 BoundarySupplementaryLayout。若在 `boundarySupplementaries` 集合中关联 provider 自有的边界，使用 `CustomLayoutBoundary(kind:)`，不再指定框架尺寸；有对应内容时，返回的 Section 必须包含恰好一个匹配 kind 的边界。此值可调用 `.whenContentExists()`，不提供 `.pinToVisibleBounds`、`.extendsBoundary`、`.absoluteOffset` 或 `.zIndex`，调用会在编译期失败；这些几何属性应由 provider 配置。

同一 Section 中，provider 返回的 decoration 与框架安装的 decoration 不得使用相同实际 `elementKind`；可用 `.decorationItems(.none)` 关闭框架默认生成的背景。`context.decorationElementKind(for:)` 将逻辑 kind 转成当前注册标识，未声明时返回 nil。provider 自己管理的原始 elementKind 可以恰好等于 typed 内容的逻辑 kind；只要实际 elementKind 不同即可共存。

`onVisibleItemsInvalidation` 重复调用会替换原 handler；若 provider 返回的 Section 已有 handler，Section 上的声明会覆盖它。闭包直接交给 UIKit，ListKit 不执行 self-sizing 兼容性检查。包含 estimated item 时应仅用于观察；修改 transform、alpha 等属性时使用确定尺寸并在目标系统验证。

原有通用 Header/Footer 工厂、专用闭包、角色、点击快捷入口，内容侧 geometry modifier，以及 background 配置入口均已删除。UITableView 的 TableHeader/TableFooter 不属于本次 Collection 布局重构范围。

## 解析诊断与回退

可静态确定的内容与布局问题在 apply 前检查；依赖实际容器、外层方向或 provider 返回值的问题在 Section 解析阶段检查，两者不是同一次校验。

调用 `adapter.makeCompositionalSection` 时，`scrollDirection` 必须填写外层 layout 的实际方向，默认 `.vertical`；该参数只用于解析与校验，不会修改外层 layout。实际内容方向由此外层方向与 section 的正交配置共同决定；无效尺寸组合会按 diagnostics 配置处理并返回 nil。`.disabled` 不记录解析诊断，但仍拒绝无效布局；`.assertion` 会调用 `assertionFailure`。

`adapter.makeCompositionalLayout` 在其 provider 收到 nil 结果时使用默认 List 布局回退。因此，“解析失败”不等于“隐藏 Section”或“保留旧布局”。自行创建外层 layout 时，调用方负责处理 `makeCompositionalSection` 的 nil 返回值。

## 从 Slot API 迁移

`SupplementarySlot` 和 `DecorationSlot` 已移除，不提供兼容别名。布局构造器统一使用 `kind:`；内容侧不再传入 `slot:`。包装现有 `Supplementary` 或 `ProviderSupplementary` 时，直接调用 `SectionSupplementary(value)`，沿用 value 的 kind。

迁移时直接使用业务名称，不保留旧默认名称中的 `ListKit.Supplementary.` 或 `ListKit.Decoration.` 前缀。例如旧 title 槽位改为 `kind: "title"`，旧 card 槽位改为 `kind: "card"`。已经显式指定的业务 kind 继续原样使用。

这是一项有意的行为变更：

- supplementary 实际 kind 和展示 identity 随之改变。首次从旧描述切换到新描述时按内容身份变化处理；稳定使用新 kind 后，refreshID 继续控制内容刷新。
- typed decoration 的逻辑 kind 改变，使生成的实际 elementKind 改变；UIKit 应替换旧元素。生成公式仍包含逻辑 kind 与视图类型，防止跨类型复用。
- 手动 decoration 的逻辑 kind 同样使用业务名称，实际 elementKind 继续由调用方显式提供；外部注册和布局查询必须与该实际值一致。

所有相关布局、注册、可见 supplementary 刷新和 attributes 查询都应同步使用新名称；不要把本次迁移当作保持 identity 的纯语法替换。布局复用通过接收 kind 参数的工厂实现；CustomLayout 捕获的 kind 改变时，必须同步更新其 layoutKey。Decoration 的自定义 provider 仍可按固定逻辑 kind 查询本次内容的实际 elementKind，以支持视图类型或手动注册标识切换。

## 布局语义重构迁移（2026-10-29）

本次为破坏兼容的 API 迁移，不提供旧入口别名。历史验证报告中的旧名称描述当时的源码，不作为当前 API 参考。

| 旧入口 | 当前入口与行为 |
| --- | --- |
| contentInsets / CustomLayout(contentInsets:) / context.contentInsets | sectionInsets / CustomLayout(sectionInsets:) / context.sectionInsets；UIKit 原生 contentInsets 属性保持原名 |
| ListGridItem | ListGridTrack，描述轨道而非数据 item |
| ListGridItemSize / itemSize | ListGridItemMainAxisSize / itemMainAxisSize |
| ListGridGroupSize | ListGridGroupMainAxisSize |
| frame / estimatedFrame | gridCrossAxisSize(.fixed / .estimated)，随内容轴解释；nil 恢复环境尺寸 |
| alignment / ListGridAlignment | trackGroupAlignment / ListGridTrackGroupAlignment |
| group(.count(n, size: ...)) | lineGrouping(.count(lines: n, mainAxisSize: ...)) |
| group(.fit(size: ...)) | lineGrouping(.fitting(mainAxisSize: ...)) |
| fill | fillGroup，要求显式分组数量与长度 |
| adaptive(minimum:) | adaptive(minimumForCount:)，用于计算轨道展开数量；不足时可小于此值 |
| ListGridSize 用于边界 | ListBoundaryMainAxisSize；uniform 不再可用 |
| EnvironmentLayout(id:) / CustomLayout(id:) | layoutKey:，包含影响布局的外部捕获状态 |
| CustomLayout(...).sectionInsets(...) | CustomLayout(layoutKey:sectionInsets:)，provider 构建时消费输入 |
| BoundarySupplementaryLayout.providedByCustomLayout | 独立 CustomLayoutBoundary 类型，不暴露几何修饰方法 |
| whenPresent | whenContentExists，检查内容声明／注册而非屏幕可见性 |
| ListSupplementaryAnchor | item 使用 ListItemSupplementaryAnchor；boundary 使用 ListBoundaryAlignment（none 不代表居中） |
| sectionSupplementaries / addingSectionSupplementaries | addingSupplementaries，显式表示追加；旧入口已移除 |

所有不带 adding 的集合修饰方法替换此前集合；同一次 builder 内按顺序组合。addingSupplementaries 和 addingDecorations 追加内容／注册，重复 kind 仍会诊断。空 layout builder 的含义维持“默认单轨道估算布局”，不会隐藏 Section；需要隐藏时在内容 builder 中省略 Section。

旧 `gridSpacing(v)` 改为 `.trackSpacing(v).lineSpacing(v)`；`groupLineSpacing(v)` 改为 `.lineSpacing(v)`，但现在它默认也影响组间距。若需保留旧的零组间距，显式追加 `.groupSpacing(0)`。旧代码先设置 groupSpacing、再用 gridSpacing 覆盖全部间距时，迁移后应删除该覆盖或调用 `.groupSpacing(nil)`。显式 groupSpacing 不再被 lineSpacing 覆盖；轨道自身显式 spacingAfter 仍优先于全局 trackSpacing。
