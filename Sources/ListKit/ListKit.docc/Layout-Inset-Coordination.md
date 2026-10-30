# Collection 布局与系统 Insets

让 ListKit 生成的 compositional layout 与 UIKit 的安全区域调整保持同一套几何基准。

## 默认保留 UIKit 行为

``ListCompositionalLayoutConfiguration`` 的 `scrollDirection`、`interSectionSpacing` 默认是 `nil`，
`contentInsetsReference` 默认使用 ``ListContentInsetsReference/systemDefault``。ListKit 创建
`UICollectionViewCompositionalLayoutConfiguration` 时不会写入这些属性，因此系统版本、容器和 UIKit
自己决定实际默认值。调用方提供非 `nil` 值或非 `.systemDefault` case 后才会显式覆盖。

其中 `scrollDirection: nil` 保留 UIKit 默认纵向滚动。Grid 根据外层方向与自身 orthogonalScrolling 配置解析内容方向；不再有 columns:/rows: 方向入口。尺寸与分页规则见 <doc:Declarative-Layouts>。

Collection View 的 `contentInsetAdjustmentBehavior` 仍由页面拥有。ListKit 不会因为创建 layout 而修改它。
普通导航栈或 Tab Bar 页面应同时保留两侧的系统默认：

```swift
collectionView.collectionViewLayout = adapter.makeCompositionalLayout()
```

``ListContentInsetsReference/systemDefault`` 与
``ListContentInsetsReference/automatic`` 语义不同：前者不写 UIKit 属性，后者显式写入
`UIContentInsetsReference.automatic`。

## Section inset 与尺寸基准

全局 `contentInsetsReference`、collection 的 `contentInset` 与 Section 的 `.sectionInsets(...)` 属于不同层级。
Section inset 修饰方法重复调用时覆盖原值，不累加；ListKit 不因添加 boundary、设置 offset 或 extendsBoundary 而额外追加 Section inset。

- Grid 默认 Section inset 为零。
- 原生 UIKit List 未声明 inset 时保留系统生成的值，显式声明则覆盖。
- CustomLayout 未声明 inset 时由 provider 管理；显式声明时，provider 必须用 `context.sectionInsets` 构建几何，并在返回的 Section 上设置同值，否则解析失败。

未显式配置 gridCrossAxisSize 时，Grid 轨道及边界主轴比例计算使用 `environment.container.effectiveContentSize`，再扣除 Section 交叉轴 inset 一次；不再次扣除安全区域。
`ListLayoutDimension.fractionalWidth` / `.fractionalHeight` 则由 UIKit 按所在布局层级的容器解析，不是固定相对屏幕或整个 collection view。
显式 gridCrossAxisSize 指定主体交叉轴内容尺寸，不再从中扣除 section inset；fractionalViewport 使用有效容器主轴长度减去对应 section inset。gridCrossAxisSize 随内容轴解释，使用 itemMainAxisSize 或 group 配置主轴内容。
`DecorationItemLayout.backgroundInsets` 只调整背景 decoration，不改变 Section 或 cell 的 inset。

## 显式接管

只有页面明确需要自定义 inset 时才覆盖，并把 layout 的内容宽度与 scroll view 的调整方式作为一组审查。
例如不避让系统区域的全屏画布可以显式声明：

```swift
collectionView.contentInsetAdjustmentBehavior = .never
collectionView.collectionViewLayout = adapter.makeCompositionalLayout(
    configuration: .init(contentInsetsReference: .none)
)
```

普通页面不应组合 `contentInsetsReference: .none` 与
`contentInsetAdjustmentBehavior = .always`。横屏出现左右安全区域时，scroll view 会把内容原点推入安全区，
但 compositional layout 仍可能按完整容器宽度生成 Section，导致内容从另一侧越界并产生非预期的横向滚动范围。

## UIKit List 与自绘分隔线

``ListUIKitListLayout`` 的 `showsSeparators` 默认是 `nil`，表示保留指定 appearance 创建出来的 UIKit
默认值。传入 `true` 或 `false` 才会写入 `UICollectionLayoutListConfiguration.showsSeparators`。
`headerTopPadding: nil` 同样保留 UIKit 默认值；显式值只写入该 configuration 属性，不会创建 header，也不替代 boundary 的尺寸与偏移。

``UICollectionViewCompositionalSeparatorLayout`` 绘制的是 ListKit decoration，不存在可以继承的系统
separator inset。它在枚举到的 cell（含最后一个）和 supplementary frame 底部添加水平线，不随滚动方向改为竖线。

`separatorInsets` 默认 `.zero`；当前实现只使用 leading/trailing，分别映射到 cell 分隔线的物理 left/right，
不自动按 RTL 交换，top/bottom 不参与计算。supplementary 分隔线始终使用零 inset。
分隔线高度单位为点，初始化时默认取 `1 / UIScreen.main.scale`，不会随之后的窗口或显示器 scale 变化自动重算。
分隔线颜色保存在 layout attributes 中，因此每个 layout 实例互不影响。

## Table Header

`UITableView.tableHeaderView` 的任意子视图不会自动获得 inset-grouped Section/Cell 的水平布局边界。
Header 可以继续占满 Table View 宽度，但内部内容必须使用随 `safeAreaInsets`、布局方向和旋转变化而更新的
directional layout margins。不要把内容用固定边距直接约束到 Header 的物理边缘。
