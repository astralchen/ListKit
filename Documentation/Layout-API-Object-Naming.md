# 布局 API 作用对象命名审查

> 后续间距 API 已统一：删除 gridSpacing，groupLineSpacing 改为 lineSpacing，groupSpacing 改为可选覆盖（nil 跟随 lineSpacing）。下文为当时的实现与验证记录；当前契约见 [布局指南](Layout-API.md#滚动与间距)。

> 默认值后续调整为 estimated(44) 和三层零间距，详见 [布局默认值验证](Layout-Defaults-Validation.md)。以下各阶段记录保留当时结果。

> 历史阶段说明：本报告记录了曾将 lineSpacing 改名为 groupLineSpacing 的过程；该命名已被后续统一行间距方案替代。下文的名称、默认值和验证表仅代表当时状态。

日期：2026-10-29。在 sectionInsets 修复之后继续审查其余公开布局 API；所有改动保持未提交。当前使用指南及迁移表见 [Layout-API.md](Layout-API.md#名称与作用对象)。此前 [复查记录](Layout-API-Review.md) 和 [首轮语义验证](Layout-API-Semantics-Validation.md) 保留当时的名称与验证结果。

## 审查原则与改动

名称应明确被修改的布局对象，以及容易混淆的参考基准；接收类型已经唯一限定的 size、alignment、zIndex 等无需重复加前缀。此次为破坏兼容的命名统一，不保留旧入口别名。

| 原入口 | 新入口 | 修复的歧义 |
| --- | --- | --- |
| crossAxisSize | gridCrossAxisSize | 所有轨道占用的区域，不是单个 item 或 collection |
| spacing | gridSpacing | 同时设置轨道、组内行/列、组间三层间距 |
| group / ListGridGrouping | lineGrouping / ListGridLineGrouping | 分组单位是基本行/列，不是 item 总数 |
| trackAlignment / ListGridTrackAlignment | trackGroupAlignment / ListGridTrackGroupAlignment | 对齐整组轨道，不对齐 cell 内部内容 |
| ListGridTrack.spacing | spacingAfter（属性与初始化标签） | 每条实际轨道到下一条轨道的间距 |
| BoundarySupplementaryLayout.axis: | sizingAxis: | 仅决定尺寸计算轴 |
| pinned | pinToVisibleBounds | 固定到可见区域对应边缘，包含横向吸边 |
| offset | absoluteOffset | 相对边界 alignment 的点数偏移 |
| ItemSupplementaryLayout.anchor | itemAnchor（属性与初始化标签） | 相对于所属 item 的 containerAnchor |
| fractionalOffset | anchorFractionalOffset | containerAnchor 的比例偏移 |
| DecorationItemLayout.insets | backgroundInsets（属性与初始化标签） | 背景自身的收缩量 |

保留并补充作用域说明的入口：sectionInsets、itemMainAxisSize、trackSpacing、groupLineSpacing、groupSpacing、orthogonalScrolling、boundarySupplementaries、itemSupplementaries、decorationItems。全局 ListCompositionalLayoutConfiguration、原生 UIKit 属性和其他控件自己的配置不进行同名替换。

## 行为与覆盖

布局分配算法、默认值、单位、数值校验、方法覆盖顺序和 provider 几何所有权保持原有规则。源码差异中的计算读取只从旧属性名迁移到对应新属性；UIKit 的原生 contentInsets、containerAnchor、fractionalOffset、pinToVisibleBounds 等保持原名。

源码、README、DocC、当前布局指南、Layout Lab、LiveRoom 示例和现有测试已同步。历史报告中旧名称保留为历史记录；当前文档只在迁移表中保留旧入口。

新增 LayoutObjectNamingTests 使用真实 collection view 布局属性，覆盖外层横/纵方向 × 正交开/关四种组合，联合验证：200 点网格区域内整组轨道居中、spacingAfter 不在最后一条轨道后追加空白、sectionInsets 独立于轨道对齐、groupLineSpacing 与 groupSpacing 独立生效。既有补充视图位置、吸附、背景、估算尺寸、uniform、RTL、分页尾组与刷新测试均迁移到新入口。

编译契约新增 18 项检查，覆盖新名称合法用法，以及每个旧方法、初始化标签、可写属性和类型的编译拒绝。

## 验证

环境：Xcode 27.1（27A9275），iPhone 17 Pro Max / iOS 26.5 Simulator，arm64。最低部署目标 iOS 15。

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| 全部 ListKit 包测试 | 290 项通过，0 失败、0 跳过 | `/tmp/listkit-api-owners-package-final.xcresult` |
| iOS 15 / Swift 6 API 编译契约 | 74 项通过：16 个合法用法、58 个预期编译拒绝 | `/tmp/listkit-api-owners-contract-complete.log` |
| 示例单元及 Layout Lab UI 测试 | 49 项通过（44 单元 + 5 UI），0 失败、0 跳过 | `/tmp/listkit-api-owners-demo.xcresult` |
| DocC 编译 | 通过，无 warning/error | `/tmp/listkit-api-owners-docs.log` |

UI 真实手势覆盖双方向的 5 个正交场景、起始/居中分页停靠、两行三列尾组、自定义边界切轴、容器变窄和空内容。README 与当前指南的相对链接通过检查，DocC 与 Markdown 布局指南内容一致，`git diff --check` 通过。

编译契约日志中的 fail 表示非法用法按预期被拒绝。未运行 iOS 15/iOS 17 runtime 或真机测试；UI 范围限定 Layout Lab。

## 过程记录

首轮库测试 `/tmp/listkit-api-owners-package.xcresult` 在最后的对齐类型改名之前完成。随后统一为 ListGridTrackGroupAlignment，最终验证需使用重新构建的模块。`/tmp/listkit-api-owners-contract-final.log` 保留中间状态：脚本已生成旧类型模块后才加入拒绝旧类型的用例，因此出现一次 UNEXPECTED SUCCESS；最终编译契约从稳定源码重新构建模块并全部通过。

本轮操作前 tracked/untracked 非忽略文件的备份与 SHA-256 清单位于 `/var/folders/_b/4kvsp2_s0ss21dbxf2_s7bnh0000gn/T/listkit-api-owners-3kzpshbr`；最终增量差异和清单保存于同一目录。原有无关修改保持原状，未创建提交或推送。

## 历史阶段：groupLineSpacing 补充迁移（2026-10-29，已被替代）

公开属性与链式修饰方法 lineSpacing 均改为 groupLineSpacing，不保留旧入口。内部 fillGroup、fitting、group 长度和 UIKit interItemSpacing 赋值同步迁移；默认值仍为 8，gridSpacing 仍同时设置 trackSpacing、groupLineSpacing、groupSpacing。单个基本行／列的 group 不产生组内间隔。

README、当前 API 指南、DocC、Layout Lab 和现有测试均同步更新。逐文件对比备份确认 9 个 Swift 文件的差异仅为 lineSpacing → groupLineSpacing，计算公式与行为断言没有变化。历史验证报告中的名称作为历史记录保留。

- 全部库测试：290 项通过，0 失败、0 跳过；`/tmp/listkit-group-line-package.xcresult`。
- iOS 15 / Swift 6 编译契约：77 项通过，17 个合法用法、60 个预期编译拒绝；新增旧方法和旧属性拒绝、新方法和可写属性正例。日志 `/tmp/listkit-group-line-contract.log`。
- DocC 编译通过，无 warning/error；`/tmp/listkit-group-line-docs.log`。当前 Markdown/DocC 指南一致，相对链接有效。
- 示例首次运行：44 个单元测试通过，分页尾组 UI 测试通过；分页停靠用例在第二次启动后点击 Scenes 未找到 Centered 按钮，未到达该场景的布局断言。原失败结果保留于 `/tmp/listkit-group-line-demo.xcresult`，没有删除或放宽断言。

本次操作前备份与增量差异：`/tmp/listkit-group-line-m742tdvk/`。未提交、未推送；运行环境与上述相同，没有增加真机或旧系统运行验证。

分页停靠 UI 用例保持源码和断言不变后单独重跑通过（1 项，0 失败、0 跳过），结果 `/tmp/listkit-group-line-ui-retry.xcresult`。本轮共验证 44 个示例单元测试与 2 个选定 UI 用例；首次运行 45 项通过、1 项失败，失败用例重跑通过，不能将首次运行记录为全绿。未重跑全部 5 个 Layout Lab UI 用例。最终 `git diff --check` 通过。
