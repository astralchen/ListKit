# 自动测量瀑布流

`WaterfallLayout` 与 `GridLayout` 一样放在 Section 的 layout builder 中。标准 `Row` 自动提供内部测量能力，业务无需 `measureHeight`、辅助 Cell 或手动维护高度数组。

```swift
ListSection(0) {
    ForEach(items, id: \.id) { item in
        Row(model: item, cell: CardCell.self) { cell, item, context in
            cell.configure(item, loadsImages: !context.isMeasuring)
        }
        .refreshID(item)
        .refresh(when: .refreshIDChanges)
    }
} layout: {
    WaterfallLayout(tracks: 2)
        .trackSpacing(12)
        .lineSpacing(12)
        .sectionInsets(.init(16))
}
```

## 方向与轨道

| 外层方向 | orthogonalScrolling | 内容方向 | 测量方式 |
| --- | --- | --- | --- |
| vertical | nil | 纵向 | 固定列宽，自动测高 |
| horizontal | nil | 横向 | 固定行高，自动测宽 |
| vertical | continuous 等 | 横向 | 固定行高，自动测宽 |
| horizontal | continuous 等 | 纵向 | 固定列宽，自动测高 |

外层方向通过 `adapter.makeCompositionalLayout(configuration: .init(scrollDirection: ...))` 设置。之后修改原生 layout.configuration.scrollDirection 也会重新解析。

`tracks` 接受数量，也接受与 Grid 相同的 `[ListGridTrack]`（fixed、flexible、adaptive）。自适应示例：

```swift
WaterfallLayout(tracks: [ListGridTrack(.adaptive(minimum: 140))])
    .trackSpacing(12)
    .lineSpacing(12)
```

可用 `.crossAxisSize(260)` 固定整个轨道区域的交叉轴尺寸，常用于正交滚动的行高区域；nil 恢复跟随容器。`.alignment(.center)` 控制轨道区域对齐。Insets、boundary supplementaries、背景 decoration 沿用 ListKit 的公共布局流程。RTL 由外层 ListKit layout 镜像，业务不反转数据顺序。

每个 item 放入当前结束位置最短的轨道，同长时选逻辑起始侧。`lineSpacing` 仅加在相邻条目之间，末尾不增加空白。异宽轨道先选轨道，再按其宽度测量。

## Cell 与配置闭包

- Auto Layout 必须能在固定交叉轴尺寸下求出有限、正的主轴尺寸。通常是 contentView 内完整的上下/左右约束链。
- 框架调用 `cell.systemLayoutSizeFitting(_:withHorizontalFittingPriority:verticalFittingPriority:)`，尊重 Cell 对此方法的重写。横向 Cell 必须在固定高度下能求出宽度。
- 标准 Row 使用已有的 Cell 类型/XIB 查找规则创建独立测量实例，不从展示 CollectionView dequeue。
- 配置闭包会在主线程对测量实例执行，`context.isMeasuring == true`。它必须完整配置内容，允许重复调用。
- 测量不派发 `context.send`，不调用框架的展示、预取和交互绑定回调。闭包内部直接发起的网络请求无法由框架自动拦截；有需要时使用 `isMeasuring` 跳过非尺寸相关的操作。
- 已选中状态和字体/方向环境参与测量。测量 Cell 被复用，并在使用前后清理复用状态。

## 更新与性能

首次解析会测量当前 section 的全部条目，并生成 custom group 的确定 frame；不是仅测量屏幕可见项。测量缓存由 adapter 持有，末尾追加复用旧尺寸，重新计算排布。

`refreshID` 也是尺寸内容版本。影响尺寸的内容变化必须改变 refreshID；没有 refreshID 的 Row 每次接受新 apply 后保守重测。实际轨道尺寸、内容方向、索引位置、选择状态和 trait 环境变化会重新测量。删除的数据会清理，内存警告清空测量缓存和 Cell 池。

尺寸失效不受可见刷新 scope 限制：屏幕外 Row 内容版本变化也会重新排布后续条目。没有 apply 的 Cell 内部异步尺寸变化不会自动反馈到这个预测量布局；请把变化写回状态并 apply。

首版支持平铺的 typed Row，不支持 ProviderRow、outline 和 item supplementary；这些情况会诊断。整个 section 是一个 custom group，group paging 会以整个 section 为分页单位，不提供按卡片分组分页。

## 示例

运行 Examples，在列表页导航栏点击 **Waterfall**，或使用启动参数 `-WaterfallDemo`。页面提供纵向、横向、正交横向、自适应/2/3 轨道、追加、重置和点击展开/收起。示例 Cell 只使用约束，没有尺寸拟合方法或业务测量闭包。

自适应模式以当前容器为基准：纵向示例最小列宽 150 点，横向示例最小行高 100 点。改变窗口、旋转或分屏时自动计算新的轨道数，无需重新 apply。
