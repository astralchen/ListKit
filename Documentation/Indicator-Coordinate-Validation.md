# 原生滚动指示器坐标对照

验证日期：2026-11-16。

## 已验证的坐标关系

在 iPhone 17 Pro / iOS 26.5 与 iPhone 18 Pro / iOS 27.2 的原生 Collection 对照中，
每套系统的 40 对配置都得到相同分类：21 对位置重合，19 对呈水平镜像。
RTL 下 Flow 的窗口水平基向量为 `+1`，Compositional 为 `−1`；两者的 `transform` 都是
identity。举例：宽 402 点的全屏视口，Flow 的 `convert` 把本地 X 为 `0, 1` 的点投影到
窗口 X `0, 1`，Compositional 则投影到 `402, 401`。

| RTL，全屏（宽 402 点） | Flow 像素起点 X | Compositional 像素起点 X |
| --- | ---: | ---: |
| 自动调整开启，零边距 | 3 | 3 |
| 自动调整开启，仅 left=4 | 7 | 392 |
| 自动调整开启，仅 left=24 | 27 | 372 |
| 自动调整关闭，零边距 | 3 | 396 |
| 自动调整关闭，仅 left=4 | 7 | 392 |
| 自动调整关闭，仅 left=24 | 27 | 372 |

指示器宽均为 3 点。以 left=4 为例，`402 − 7 − 3 = 392`。left 从 4 增到 24 时，
Flow 向右移动 20 点，Compositional 向左移动 20 点，位移符号与各自公开坐标基向量一致。
这证实这些 RTL 配置存在相对于 Flow 的额外水平镜像效果。在全屏、自动调整开启且边距为零时，
Compositional 的基向量仍为 `−1`，但两者都在 X=3，指示器的最终位置没有镜像。
其余 19 组 RTL 配置都呈水平镜像，包括嵌入式视口的全部 10 组；20 组 LTR 配置全都重合。
两套系统在所有配对中，指示器 Y 起点、宽度、长度分别一致。独立改变 right=12 不会移动
RTL 指示器的正常侧边距离；但在全屏自动调整开启时，即使仅 right 非零，也会让
Compositional 从零边距的左侧路径切换到镜像后的右侧。
公开证据能确定这种视觉行为与坐标关系，不能据此断定 UIKit 在哪个内部对象或步骤做转换。

两套系统各采到 80 个截图像素样本，Flow 与 Compositional 的 RTL 视觉排列和实际向右拖动
检查均未失败，纵向网格位置保持不变。两次 XCTest 都在全部采样完成后，因汇总把 `[CGFloat]`
读成 `[Double]` 而失败。已统一存储类型，最终源码 `build-for-testing` 通过；提取同一段 Swift 比较
逻辑对两套系统的原始 UI 记录重放，40 对配置的边距与几何输入、像素和位移断言全部通过。
类型修改后没有重跑整套 XCTest，不把原始测试结果标记为通过。

- [iOS 26.5 实测数据](Indicator-Coordinate-Evidence/ios-26.5-measurements.json)
- [iOS 27.2 实测数据](Indicator-Coordinate-Evidence/ios-27.2-measurements.json)
- [测试结果、原始日志及历史排除记录](Indicator-Coordinate-Evidence/validation-status.json)

## 验证方法

在不依赖 ListKit 的 `NativeCollectionIndicatorViewController` 中追加
`-NativeIndicatorCoordinateProbe -NativeMixedLayout`。默认使用 Compositional；追加
`-NativeCollectionLayout flow` 使用原生 Flow。两个方向、两种几何、两种自动调整设置、
五种指示器边距，共每种布局 40 个采样点。

- 方向：英语启动后显式设置 LTR、RTL；使用公开 semantic 与 trait API。
- 几何：全屏与安全区下方 24 点、左右各缩进 16 点、高 320 点的嵌入式视口。
- `automaticallyAdjustsScrollIndicatorInsets`：true、false。
- `verticalScrollIndicatorInsets`：零；仅 left=4；仅 left=24；仅 right=12；
  `(top:8, left:4, bottom:8, right:12)`。
- `contentInsetAdjustmentBehavior` 保持 `.automatic`，内容边距保持零。

Compositional 保留 20 项 `.continuous` 横向正交 section，随后为 90 项三列纵向网格。
Flow 没有正交 section API，对照组用 App 创建的横向 Collection 放在首个 96 点高的 cell 中，
随后使用相同三列网格。探针网格的 section leading/trailing 为 40/60 点，确保
left=24 时指示器仍在白色边缘上，避免半透明指示器与彩色 cell 混合干扰灰色像素检测。
两者横向内容均做 RTL 视觉排列、真实向右拖动及纵向位置不变检查。
这不是声称 Flow 的嵌套容器等同于 UIKit 的正交滚动引擎；它用于匹配主轴内容长度和指示器轨道。

同方向的所有几何、自动调整与边距步骤复用主 Collection 和同一布局实例。Flow 在几何变化时
通过公开 invalidation 重新查询 delegate item 尺寸。每步固定主轴 offset=(0,300)，采集公开
frame/bounds、安全区、adjusted/content inset、contentSize、自动调整开关、指示器边距及
UIView 坐标基向量。测试逐项比较两种布局的几何与配置输入；坐标基向量作为输出单独诊断，
不预设 Compositional 的 `convert` 与 Flow 相同。

最终位置从截图的灰色长条像素测量，不查找指示器子视图、不读取私有类型或 KVC。
切换配置后重复调用 `flashScrollIndicators()`；若首张截图太晚，可再闪现两次。
仍缺失像素则测试失败。每个样本先确认当前步骤，截图前后检查应用在前台。
两套系统分别在固定 ID 的不同模拟器上验证。公开的 cell frame、layout attributes 及转换到 window 的结果另行记录。

## 如何判断镜像

截图矩形使用 `[x, y, width, height]`，单位为屏幕点。设视口屏幕左边为 `X`、宽度为 `W`，
Flow 的指示器为 `[xF, yF, wF, hF]`。完全水平镜像的预期为：

```text
xC = 2 * X + W - xF - wF
yC = yF
wC = wF
hC = hF
```

测试比较每一对样本是否具有相同位置或满足这个镜像关系，误差限为 1.5 点；Y 起点和长度
也必须一致。测试通过表示公开输入、混合布局手势与坐标关系的诊断成立，不表示 RTL 指示器
在所有配置下均处于正确侧边。

## 与参考工程的关系

参考 `UIKitLanguageDemo` 中的
`CompositionalDemoViewController.viewDidLayoutSubviews`，该页面在 iOS 26+ 把
`verticalScrollIndicatorInsets.left` 设为 `max(0, viewportWidth - 8)`，在 LTR 设为零。
它明确拥有页面的左侧指示器边距，其他边距保留。

实测 `left` 位移在镜像路径下反号，解释了为何参考页增大 `left` 可以把指示器朝物理左侧推。
全屏、自动调整开启且零边距时本来就在左侧；设置非零 `left` 会统一走镜像轨道。
ListKit 用实测的默认间距和滑块宽度计算补偿。对侧 `right` 大于目标距离时，UIKit 会限制
镜像轨道可到达的位置。例如业务 `left=4, right=12` 时，仅补偿 `left` 会停在离左边 15 点处，
而 Flow 为 7 点。ListKit 临时放宽对侧限制，并在退出补偿时恢复两侧业务边距。
这里的原生坐标矩阵不启用该修正。

## 公开 API 语义

Apple 的 [verticalScrollIndicatorInsets](https://developer.apple.com/documentation/uikit/uiscrollview/verticalscrollindicatorinsets)
与 [automaticallyAdjustsScrollIndicatorInsets](https://developer.apple.com/documentation/uikit/uiscrollview/automaticallyadjustsscrollindicatorinsets)
提供边距及自动调整设置；
[developmentLayoutDirection](https://developer.apple.com/documentation/uikit/uicollectionviewlayout/developmentlayoutdirection)
与 [flipsHorizontallyInOppositeLayoutDirection](https://developer.apple.com/documentation/uikit/uicollectionviewlayout/flipshorizontallyinoppositelayoutdirection)
描述布局开发方向与反向布局翻转规则。这里的像素对照用于判断输出是否具有镜像关系，
不把这些 API 的文档理解为对 UIKit 内部指示器实现的说明。
