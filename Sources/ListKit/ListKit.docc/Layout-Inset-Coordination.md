# Collection 布局与系统 Insets

让 ListKit 生成的 compositional layout 与 UIKit 的安全区域调整保持同一套几何基准。

## 默认保留 UIKit 行为

``ListCompositionalLayoutConfiguration`` 的 `scrollDirection`、`interSectionSpacing` 默认是 `nil`，
`contentInsetsReference` 默认使用 ``ListContentInsetsReference/systemDefault``。ListKit 创建
`UICollectionViewCompositionalLayoutConfiguration` 时不会写入这些属性，因此系统版本、容器和 UIKit
自己决定实际默认值。调用方提供非 `nil` 值或非 `.systemDefault` case 后才会显式覆盖。

Collection View 的 `contentInsetAdjustmentBehavior` 仍由页面拥有。ListKit 不会因为创建 layout 而修改它。
普通导航栈或 Tab Bar 页面应同时保留两侧的系统默认：

```swift
collectionView.collectionViewLayout = adapter.makeCompositionalLayout()
```

``ListContentInsetsReference/systemDefault`` 与
``ListContentInsetsReference/automatic`` 语义不同：前者不写 UIKit 属性，后者显式写入
`UIContentInsetsReference.automatic`。

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

``UICollectionViewCompositionalSeparatorLayout`` 绘制的是 ListKit decoration，不存在可以继承的系统
separator inset。`separatorInsets` 明确相对已经由 compositional layout 解析完成的 item frame 计算，默认
`.zero`。分隔线颜色保存在 layout attributes 中，因此每个 layout 实例互不影响。

## Table Header

`UITableView.tableHeaderView` 的任意子视图不会自动获得 inset-grouped Section/Cell 的水平布局边界。
Header 可以继续占满 Table View 宽度，但内部内容必须使用随 `safeAreaInsets`、布局方向和旋转变化而更新的
directional layout margins。不要把内容用固定边距直接约束到 Header 的物理边缘。
