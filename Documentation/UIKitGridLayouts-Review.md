# UIKitGridLayouts 源码审查与集成决策

> 以下保留各阶段的审查与集成决策。当前接口采用 ListGridTrack、itemMainAxisSize、gridCrossAxisSize、lineGrouping、trackSpacing、统一 lineSpacing 与可选 groupSpacing 覆盖；以 [Layout-API.md](Layout-API.md) 为准。历史命名和验证结果不表示当前 API 仍可调用。

审查版本：[89aa339cc5651147c3c6265c0c931dd701bb45a7](https://github.com/astralchen/UIKitGridLayouts/tree/89aa339cc5651147c3c6265c0c931dd701bb45a7)。审查了全部 5 个 Sources 文件、4 个测试文件、Package.swift、LICENSE 和 README 中的示例。该版本没有独立 Example app 源码目录，示例位于 README，截图位于 Documentation/Screenshots；没有把截图当作本次验证结果。

| 真实实现能力 | ListKit 原有能力 | 集成方式 |
| --- | --- | --- |
| fixed/flexible/adaptive 混排，顺序分配后展开 | 仅固定列数网格 | 复用通用轨道 resolver；固定列数转换为等宽 flexible 定义 |
| VGrid 列与 HGrid 行 | 垂直网格、orthogonal 横向 section | GridLayout 的 columns/rows 均须匹配外层方向；纵向页面中的独立横滑仍由 HorizontalLayout 提供 |
| track spacing、主轴 spacing、整组对齐 | 单一 grid spacing | track nil spacing 继承 section grid spacing，alignment 为对应轴的类型 |
| fixed/estimated/aspectRatio/uniform | UIKit dimension、旧网格 group 比例高度 | 主轴尺寸规则统一为 ListGridSize；uniform 保留 iOS 17 可用性 |
| effectiveContentSize 与 section inset | 内建大多使用 fractional 尺寸 | Grid 在解析时扣除交叉轴 inset 一次；保留系统 inset 所有权 |
| 标准 header/footer 及 pinnedViews | 任意 boundary/item supplementary、typed 背景 | 不引入第二套 supplementary 系统，接入 ListKit 声明和注册 |
| 完整 V/H layout 子类及独立 makeSection 工厂 | adapter provider、布局元数据比较 | 不复制完整 public layout 包装，统一在 adapter 解析 |

Package 要求 Swift tools 6.3、Swift 6、iOS 15，只有 UIKit 依赖，与 ListKit 当前平台契合。uniform 的工厂受 iOS 17 限制，实际使用 `uniformAcrossSiblings(estimate:)`；没有降级等价保证。

依赖方案体积很小，能直接跟踪上游维护，平台也兼容；但其公开轨道、尺寸、header/footer、inset 与完整布局入口会形成第二套 ListKit 配置概念，且内部 resolver 不是可复用的 public API。直接调用上游工厂还需要在工厂外补充 item supplementary，增加对 UIKit group 结构的依赖。

选择内部整合必要 resolver、尺寸解析和 group 生成算法。保留值模型、统一 adapter 更新机制、在创建 item 时接入 supplementary；省去完整 layout 子类和重复边界配置。维护成本是 ListKit 需要主动审查上游算法变更，因此记录固定来源版本、保留算法边界测试及测量测试。没有新增 SwiftPM 依赖。

主要适配：spacing 继承关系、默认零 section inset、默认正方形、ListKit diagnostics、等轨道 supplementary 使用重复 item（独立 subitem 重复 kind 在 UIKit 中会异常，异构组合显式诊断）、容器变化失效及统一来源解析。保留 fixed/flexible 窄容器溢出、adaptive 可小于 minimum、maximum 后余量不重分配等规则，不宣称完整模拟 SwiftUI。

采用 MIT。复制/改写的源码和测试带来源与版权头，完整许可证位于 [UIKitGridLayouts-LICENSE.txt](../ThirdPartyNotices/UIKitGridLayouts-LICENSE.txt)。版权为 Copyright (c) 2026 Sondra。

## 0.5.0 功能同步

同步版本：[0.5.0 / 5a5bd7440677b31088a91bca93b227cbbacf8097](https://github.com/astralchen/UIKitGridLayouts/tree/5a5bd7440677b31088a91bca93b227cbbacf8097)。已核对从原审查提交到该标签的全部源码和测试差异，并读取新增 UIKitGridBoundaryItem、完整 builder、Package.swift 与 LICENSE。0.5.0 将标准 header/footer kind 改为显式配置；轨道 resolver、cell 尺寸算法、平台要求和 MIT 许可证不变。

ListKit 通过统一 Supplementary DSL 保留这些能力，不引入另一套 UIKitGridBoundaryItem。当前 API 使用 SectionSupplementary 与 BoundarySupplementaryLayout 共享的实际 `kind: String` 关联内容和几何，Slot API 已移除。二维尺寸或显式 axis 的主轴尺寸规则决定几何；axis 不改变 alignment 或滚动方向，alignment 不由 Header/Footer 角色推断。吸顶、offset、extendsBoundary 与自定义 provider 边界所有权均位于完整布局值内。

装饰采用 decorationItems 集合，SectionDecoration 只负责注册；省略集合时按注册生成默认背景，显式空集合关闭框架生成的背景。轨道算法保持不变；边界主轴尺寸解析仍复用 ListGridSize，其中 uniform 按独立 estimated 测量，不统一多个边界。源算法和许可头保留，实际验证记录区分历史版本与本次整体 DSL。

## 2026-10-29 命名对齐（统一 Grid 之前的历史阶段）

对照来源提交 `89aa339cc5651147c3c6265c0c931dd701bb45a7` 的实际源码，并核对 0.5.0 对应命名。复用概念沿用上游词汇，将库前缀 `UIKit` 替换为 `List`。

| 原 ListKit 名称 | 当前名称 | 上游对应名称 / 原因 |
| --- | --- | --- |
| `GridTrack` | `ListGridItem` | `UIKitGridItem` 表示轨道定义；展开后的内部 `Track` 仍表示实际轨道 |
| `ListGridItemSize` | `ListGridSize` | `UIKitGridSize` 同时用于 cell 和边界辅助视图，不限定为 item |
| `ListGridItemSize.absolute(_:)` | `ListGridSize.fixed(_:)` | 与上游固定主轴尺寸策略的 `fixed(_:)` 一致 |
| `ListGridGeometry` | `ListGridLayoutBuilder` | 对应 `UIKitGridLayoutBuilder`，负责轨道解析和 section 构建 |
| 对齐类型的 `fraction` | `offsetFraction` | 与上游一致，明确表示剩余空间的偏移比例 |

本次是允许的不兼容命名调整：删除公开旧类型名与 `absolute(_:)`，不保留 typealias 或 deprecated 转发。仓库内调用、示例及当前 API 文档使用新命名；UIKit 与 `ListLayoutDimension.absolute` 仍保持原名。

保留 `GridLayout` / `ListSectionGridLayout` 的 ListKit DSL 命名、`ListGridHorizontalAlignment` / `ListGridVerticalAlignment`，以及与上游一致的 `resolve`、`Track`、`extent`、`spacing`、`resolvedExtent`、`dimension` 等名称。`checkedResolve`、`checkedExtent` 与 diagnostics 是 ListKit 的额外验证职责，继续保留。未调整算法、默认值、尺寸上下限、系统可用性或布局行为。


## 2026-10-29 统一 Grid 后的当前差异

当前入口统一为 `GridLayout(tracks:)`，内容方向由外层 collection 与 orthogonalScrolling 配置解析，移除 columns:/rows:、普通 ListLayout 与 HorizontalLayout。UIKitListLayout 保留。

轨道 resolver、fixed/flexible/adaptive 分配和 ListGridSize 测量策略继续保留来源及许可。新 `ListGridItemSize` 是 item 专用包装，额外承载 fractionalViewport、fractionalGroup、fill；边界继续使用 ListGridSize，避免把分页尺寸暴露给边界视图。这不是恢复历史类型的旧契约。

对齐统一为 `ListGridAlignment` 和 `.alignment(...)`，默认 start；方向特定的旧对齐类型已移除。新增 frame、单轨道 estimatedFrame、group 和独立正交修饰。group 生成已扩展，不能将此前“不改变布局行为”的命名阶段结论用于当前重构。当前契约和限制见 [Layout-API.md](Layout-API.md)，当前验证见 [Unified-Grid-Validation.md](Unified-Grid-Validation.md)。
