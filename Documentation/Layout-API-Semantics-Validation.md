# 布局 API 语义重构验证

> 后续间距 API 已统一：删除 gridSpacing，groupLineSpacing 改为 lineSpacing，groupSpacing 改为可选覆盖（nil 跟随 lineSpacing）。下文为当时的实现与验证记录；当前契约见 [布局指南](Layout-API.md#滚动与间距)。

> 本文保留首轮重构的验证结果。后续复查将 DSL 的 contentInsets 统一改为 sectionInsets，并修复 provider 边界的类型转换漏洞；最新结果见 [Layout-API-Review.md](Layout-API-Review.md)。

日期：2026-10-29。此次在已有未提交的统一 Grid 布局工作上继续重构；没有提交、推送或创建 PR。当前使用方法及完整迁移表见 [Layout-API.md](Layout-API.md)。此前 [Unified-Grid-Validation.md](Unified-Grid-Validation.md)、[Unified-Grid-Review.md](Unified-Grid-Review.md) 的历史结果与失败证据保留，不以本次结果覆盖。

## 本次契约

- 轨道定义为 `ListGridTrack`；adaptive 使用 `minimumForCount:` 明确展开数量的参考值，不改变原有分配算法。
- item 尺寸统一为 `ListGridItemMainAxisSize` / `itemMainAxisSize`；完整轨道区域的交叉轴尺寸为 `crossAxisSize(.fixed / .estimated)`，随内容方向解释，nil 恢复环境尺寸。
- group 使用 `count(lines:mainAxisSize:)` 或 `fitting(mainAxisSize:)`；一个 line 是纵向内容的一行或横向内容的一列，不等于 item 总数。
- trackSpacing、lineSpacing、groupSpacing 为独立字段；spacing 同时赋值三者，后调用覆盖。单条轨道的 spacing 仍优先于全局 trackSpacing。
- fillGroup 扣除 lineSpacing 后按显式 lines 等分，fractionalGroup 仍乘完整 group 长度。
- trackAlignment 只控制整组轨道在交叉轴上的位置。orthogonalScrolling(nil) 关闭正交滚动。
- boundary 使用独立 ListBoundaryMainAxisSize，不暴露 uniform。Item anchor 和 boundary alignment 分离；boundary 的 none 不承诺居中。
- CustomLayoutBoundary 仅关联 provider 的已有边界，不提供 pinned、offset 等几何修饰。UIKitListLayout 不提供 itemSupplementaries。
- CustomLayout 与 EnvironmentLayout 使用 layoutKey 表达变化检测输入。CustomLayout 的 contentInsets 改为构造参数，provider 必须在计算几何时消费它。
- whenContentExists 检查内容声明／注册；addingSectionSupplementaries 明确追加语义，其他集合修饰方法替换集合。
- decorationItems(.none) 与 .registeredBackgrounds 显式关闭／恢复默认背景生成，保留 provider 自有背景的所有权规则。

## 验证环境与结果

环境：Xcode 27.1（27A9275），iPhone 17 Pro Max，iOS 26.5 Simulator，arm64。库最低部署目标保持 iOS 15。

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| 完整 ListKit 包测试 | 285 项通过，0 失败、0 跳过 | `/tmp/listkit-api-semantics-final.xcresult` |
| 新增 API 语义测试 | 7 项通过，包含在包测试中 | `Tests/ListKitTests/LayoutAPISemanticsTests.swift` |
| iOS 15 Swift 6 编译契约 | 48 项通过：12 个合法用法，36 个预期编译拒绝 | `/tmp/listkit-api-semantics-contract-final.log` |
| 示例及测试目标构建 | 通过 | `/tmp/listkit-api-semantics-demo-build.log` |
| 示例单元及 Layout Lab UI 测试 | 49 项通过（44 单元 + 5 UI），0 失败、0 跳过 | `/tmp/listkit-api-semantics-demo-final.xcresult` |
| DocC 编译 | 通过，无 warning/error | `/tmp/listkit-api-semantics-docs.log` |
| README 与布局指南相对链接 | 通过；DocC 布局指南与 Markdown 指南内容一致 | 本轮脚本检查 |
| git diff --check | 通过 | 本轮检查 |

编译契约日志中的 `fail:` 表示对应非法或旧 API 按预期无法编译，不表示脚本失败。构建日志存在 Xcode 工具链的 AppIntents 元数据提示、测试框架最低系统链接提示等；没有将这些工具提示当作运行失败。

新增行为覆盖四种外层轴／正交组合中的实际 item frame、三种独立间距、line 数量、fillGroup/fitting 的主轴计算、crossAxisSize 的随轴解释与清除、正交滚动清除、背景默认策略恢复、provider 边界引用 builder 和数值诊断。既有 RTL、self-sizing、uniform 行／列范围、补充视图身份刷新与滚动保持回归继续保留。

UI 真实手势覆盖 5 个正交场景 × 两种外层方向、两行三列分页停靠与尾组、起始／居中 group 停靠、自定义边界切轴、容器变窄与空内容。截图附件已导出到 `/tmp/listkit-api-semantics-ui-attachments/`；另人工检查了两行三列停靠和尾组截图，尾部保留空位，剩余 cell 没有拉伸。

## 迁移过程中的失败与修复

- `first` 至 `fifth` xcresult 与同名前缀日志保留于 `/tmp/listkit-api-semantics-*`：旧 group 参数标签、边界 uniform、原生列表不支持的修饰方法以及内部 size/frameHeight/id 断言等迁移遗漏导致构建失败，已逐项修正。首次构建还与 adaptive 参数名迁移重叠，后续完整构建验证最终源码。
- `/tmp/listkit-api-semantics-sixth.xcresult`：285 项运行中 284 项通过。诊断清除用例将旧主轴 frame 拒绝场景替换为零尺寸后，在 apply 静态校验阶段就被拒绝，未进入其要验证的环境解析路径。改为正数 1 点但两轨道溢出的配置后，原有解析失败、诊断存在、修复后诊断清除断言均保留；最终完整 285 项通过。
- 原 boundary uniform 用例迁移为 boundary estimated 的真实测量断言；不接受 uniform 的限制由编译拒绝用例验证。原生 List 不支持 item supplementary 的防御校验保留，通过测试内部注入非法元数据触发，公开入口则由编译拒绝用例覆盖。

## 范围与工作区保护

本轮没有执行 iOS 15/iOS 17 runtime 或真机测试；iOS 15 编译成功不代表这些系统上的运行验收。UI 范围限定 Layout Lab，不扩展为全部业务页面 UI 回归。

操作前全部 tracked 与 untracked 非忽略文件的备份及 SHA-256 manifest：`/tmp/listkit-api-semantics-04uzyzxs/`。本轮差异与最终文件清单也保存在该目录。原有刷新、复用、SceneDelegate 等无关改动保留；`.kiro` 中仅将一处 CustomLayout 调用的 id 标签迁移为 layoutKey。ListGridItem.swift 和 ListGridSize.swift 分别改名为 ListGridTrack.swift 和内部 ListGridMeasurement.swift，保留算法来源与许可说明。
