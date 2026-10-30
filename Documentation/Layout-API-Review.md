# 布局 API 重构复查

> 本文保留该轮复查结果。后续对其余布局 API 的作用对象命名做了统一；最新改名与验证见 [Layout-API-Object-Naming.md](Layout-API-Object-Naming.md)。

日期：2026-10-29。在已有未提交改动上复查并修复；未提交、推送或创建 PR。当前 API 以 [Layout-API.md](Layout-API.md) 为准，[首轮验证](Layout-API-Semantics-Validation.md) 保留历史结果。

## 已修复问题

### Section inset 命名缺少作用对象

布局 DSL 的 `contentInsets` 容易与 collection view、item、cell 内容及背景 inset 混淆。统一改为：

- GridLayout 与 UIKitListLayout：`.sectionInsets(...)`。
- CustomLayout：构造参数 `sectionInsets:`，provider 读取 `context.sectionInsets`。
- 内部配置与诊断同步使用 sectionInsets；UIKit 原生 `NSCollectionLayoutSection.contentInsets`、collection 的 contentInset、全局 contentInsetsReference 以及其他控件自己的 contentInsets 保留原名。

指南说明了默认值、后调用覆盖、方向性边缘、显式 crossAxisSize 与 inset 的尺寸关系，以及 boundary/decoration 的区别。源码、示例、测试、README 和 DocC 已同步迁移。

### Provider 边界可经公开 builder 擦除所有权并触发断言

此前 `ListLayoutArrayBuilder<BoundarySupplementaryLayout>.buildExpression(CustomLayoutBoundary(...))` 可以编译，返回没有 geometry 的 BoundarySupplementaryLayout；随后调用 `.pinned()` 等方法会进入 preconditionFailure。仅隐藏 CustomLayoutBoundary 上的几何修饰方法未能封闭这条路径。

现在 BoundarySupplementaryLayout 必须持有 geometry；CustomLayout builder 用 ListBoundaryLayout.generated/provided 保留几何所有权。Grid/UIKit List builder 只接受框架生成的 BoundarySupplementaryLayout。包装类型不暴露几何修饰方法，provider 自有边界必须在 provider 内配置。

原路径的编译成功证据保留于 `/tmp/listkit-provider-boundary-leak-before.log`，复现源码为 `/tmp/listkit-provider-boundary-leak.swift`；对照旧模块为 `/tmp/listkit-api.IMSBjZ`。新契约验证原擦除路径、包装后 pinned、Grid/native 接收 provider 引用均在编译期被拒绝，同时验证 CustomLayout 混合两类边界的合法用法。

### 文档仍将 boundary.center 解释为 none

分离 ItemSupplementaryAnchor 与 BoundaryAlignment 后，旧描述已不符合 API。已明确 item 支持 center，boundary 只提供 none，且 none 不承诺居中。历史审查报告中的旧 API 作为历史证据保留，当前使用指南及可执行示例已清理。

## 布局回归验证

新增 `LayoutAPIReviewTests` 的 4 项测试覆盖：

- 外层横/纵方向 × 正交开/关 × 显式/推导 crossAxisSize：真实 item frame、方向性 inset、轨道跨度以及不重复扣 inset。
- 四种方向组合下 fractionalViewport 仅扣对应主轴两侧 inset。
- 双方向的 boundary aspectRatio：显式网格 crossAxisSize 与 Section inset 同时存在时，边界仍按 Section 可用交叉轴计算。
- 双方向的带 badge 多行/列 group：独立 lineSpacing/groupSpacing、fillGroup 尺寸、尾组不拉伸及全部 badge 属性。

既有 self-sizing、uniform、RTL、环境切换、补充视图刷新及滚动保持测试继续保留。本轮未发现这些验证范围内新的运行时布局几何回归。

## 验证结果

环境：Xcode 27.1（27A9275），iPhone 17 Pro Max / iOS 26.5 Simulator，arm64。最低部署目标 iOS 15。

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| 全部 ListKit 包测试 | 289 项通过，0 失败、0 跳过 | `/tmp/listkit-api-review-second.xcresult` |
| iOS 15 / Swift 6 API 编译契约 | 56 项通过：14 个合法用法、42 个预期编译拒绝 | `/tmp/listkit-api-review-contract-final.log` |
| 示例单元及 Layout Lab UI 测试 | 49 项通过（44 单元 + 5 UI），0 失败、0 跳过 | `/tmp/listkit-api-review-demo-final.xcresult` |
| DocC 编译 | 通过，无 warning/error | `/tmp/listkit-api-review-docs.log` |

UI 真实手势覆盖 5 个正交场景 × 两种外层方向、起始/居中分页停靠、两行三列尾组、自定义边界切轴、容器变窄与空内容。当前 README/指南/复查记录的相对链接有效，Markdown 与 DocC 布局指南内容一致，`git diff --check` 通过。

编译契约日志中的 fail 表示非法用法按预期被拒绝。iOS 15 编译检查不等于 iOS 15 runtime 验收；本轮未运行 iOS 15/iOS 17 runtime 或真机测试。

## 修复过程与工作区保护

- `/tmp/listkit-api-review-first.xcresult` 保留首次构建失败：防御校验测试在 result builder 内构造和修改非法内部配置导致 Swift 编译诊断失败；改为在 builder 外准备配置，未放宽原防御断言。
- `/tmp/listkit-api-review-demo-build.log` 保留示例编译失败：3 处 ListSectionLayout 测试辅助属性仍使用 contentInsets，已迁移到 sectionInsets。
- 本轮操作前文件备份、SHA-256 manifest 和本轮增量差异保存在 `/tmp/listkit-api-review-2la20mrz/`。原有无关工作区修改保留。
