# 统一行间距与可选组间距覆盖

日期：2026-10-29。当前 API 说明见 [布局指南](Layout-API.md#滚动与间距)。

## 当前契约

- 删除 `gridSpacing(_:)`，不保留兼容入口；统一配置改用 `.trackSpacing(v).lineSpacing(v)`。
- `groupLineSpacing` 属性和修饰方法改为 `lineSpacing`，默认 0；组内的尺寸计算、fillGroup、fitting 和 UIKit 间距均使用它。
- `groupSpacing` 属性和修饰方法参数改为 `CGFloat?`，默认 nil。实际组间距为 `groupSpacing ?? lineSpacing`。
- 显式组间距不受 lineSpacing 调用顺序影响；0 表示明确无组间距；nil 清除覆盖，恢复跟随当前 lineSpacing。
- `trackSpacing` 与单轨道 `spacingAfter` 的优先关系不变。显式 group 尺寸仍保留其尾部空白。
- 配置相等／哈希保留 nil 与显式值的区别，即使当前实际间距相同；两者对后续 lineSpacing 变化的响应不同。

## 示例与迁移

README、Markdown/DocC 指南、示例、测试与 iOS 15 编译契约脚本已迁移。历史验证报告保留当时名称与结果，并链接到当前契约。

Layout Lab 默认使用 trackSpacing = 10、lineSpacing = 10、groupSpacing = nil。参数页提供「覆盖组间距」开关：启用时取当前行间距作为初始覆盖值，关闭时恢复 nil；生成代码只在有覆盖时输出 groupSpacing。

旧 groupLineSpacing 仅控制组内；迁移后若需保留旧的零组间距，应显式设置 `.groupSpacing(0)`。旧代码依靠后调用 gridSpacing 清掉特殊组间距时，迁移后应删除该覆盖或调用 `.groupSpacing(nil)`。

## 本次验证

运行环境：iPhone 17 Pro Max / iOS 26.5 Simulator，arm64。

- 库全套：308 项通过，0 失败、0 跳过。覆盖默认零间距、四种外层方向／正交组合、单行／多行 group、组间继承、两种调用顺序、显式零、清除覆盖、同一 adapter 上的布局更新、公开属性赋值、无效值诊断，以及 fillGroup/fitting 与轨道间距的独立性。
- 示例：53 项单元测试通过，0 失败；包含默认跟随、显式零覆盖、清除覆盖与代码展示一致性。
- Layout Lab UI：`testParametersUpdateLiveCodeAndGeometry` 通过。实际验证轨道 12 pt、组内 12 pt、覆盖组间距 14 pt；关闭覆盖后组间距恢复 12 pt，生成代码不再包含 groupSpacing，并继续验证切换方向与容器尺寸。
- iOS 15 / Swift 6 编译契约：82 项符合预期（20 正例、62 预期拒绝），包含旧 gridSpacing / groupLineSpacing 属性及方法被拒绝、可选 groupSpacing 与 nil 被接受。
- Markdown 与 DocC 布局指南内容一致；`git diff --check` 通过。

结果包：

- 库：`~/Library/Developer/XcodeBuildMCP/workspaces/ListKit-1de09571a095/result-bundles/test_sim_2026-10-29T10-44-22-158Z_pid7139_8b32f724.xcresult`
- 示例与 UI：`~/Library/Developer/XcodeBuildMCP/workspaces/ListKit-1de09571a095/result-bundles/test_sim_2026-10-29T10-45-45-344Z_pid7139_8bc2a07e.xcresult`
- 编译契约日志：`/tmp/listkit-line-spacing-contract.log`

终端首次 xcodebuild 尝试因 CoreSimulator 服务访问和 workspace 加载失败而未运行测试，日志保留于 `/tmp/listkit-line-spacing-library.log`；随后通过 XcodeBuildMCP 完成上述模拟器测试。

本次未运行真机、iOS 15 runtime、完整示例 UI 套件或 DocC 构建。iOS 15 编译契约不等于 iOS 15 运行时验证。原有工作区改动保留，未提交或推送。操作前文件备份位于 `/tmp/listkit-line-spacing-q_v_q8ha/`。


## 2026-10-30 复查

源码默认值、两种 GridLayout 工厂、默认布局回退与 UIKit 组间距解析均符合契约，未发现需要修改的运行逻辑。生产源码未因本次复查改变。

发现并补齐的遗漏：

- Layout Lab 代码截图仍显示旧 groupLineSpacing(2) 与「三层间距默认 0」。重新运行参数 UI 测试，导出并替换代码、纵向、横向三张截图，同时新增清除覆盖后的代码截图。图片来自真实测试附件，未修改截图内容。
- 历史命名报告仍有「lineSpacing 已改为 groupLineSpacing」的提示；改为明确标记已被替代的历史阶段，保留原始测试证据。默认值报告的「最终契约」改为「当时契约」，上游审查入口提示更新为当前名称。
- 当前指南补上库默认 0/0/nil 与 Layout Lab 预设 10/10/nil 的区别，并加入调用顺序结果表；同步更新 DocC，修正迁移段落中「后者」的歧义。
- 补强四种方向／正交组合 × 单行／多行 group 的真实几何断言：清除覆盖后再次修改行间距、修改行间距后再清除覆盖、显式零保持、显式值恰好等于原行间距时仍独立、清除后重新覆盖。示例测试补上初始预设与库默认值的区分。

本轮重跑结果（iPhone 17 Pro Max / iOS 26.5 Simulator）：

- 库定向回归 25 项通过：GridDefaultsTests、LayoutAPISemanticsTests、UnifiedGridLayoutTests，0 失败、0 跳过。
- Layout Lab 配置单元测试 9 项、参数与代码 UI 测试 1 项，共 10 项通过，0 失败、0 跳过。
- 当前 iOS 15 / Swift 6 编译契约 84 项符合预期（22 正例、62 预期拒绝），日志 `/tmp/listkit-spacing-review-contract.log`。
- Markdown/DocC 指南一致，所改文档的本地链接有效，git diff --check 通过。Swift 源码、示例与测试未残留旧间距 API；脚本中的旧名称仅用于预期编译失败检查。

结果包：

- 库：`~/Library/Developer/XcodeBuildMCP/workspaces/ListKit-1de09571a095/result-bundles/test_sim_2026-10-30T01-07-34-558Z_pid7139_aee5f4c7.xcresult`
- 示例与 UI：`~/Library/Developer/XcodeBuildMCP/workspaces/ListKit-1de09571a095/result-bundles/test_sim_2026-10-30T01-08-02-540Z_pid7139_1fa68a41.xcresult`
- 截图导出与附件映射：`/tmp/listkit-spacing-review-attachments/manifest.json`

此次为定向复查，未重跑全库、完整示例 UI、真机、iOS 15 runtime 或 DocC 构建；上节全套结果仍是 2026-10-29 的证据。改动前备份：`/tmp/listkit-spacing-review-sunalnzg/`。未提交或推送。


## 2026-10-30 全库与完整 Layout Lab UI 回归

按要求在同一当前工作区重新执行全库测试与完整 LayoutLabUITests。环境为 iPhone 17 Pro Max / iOS 26.5 Simulator，arm64，Debug；关闭并行测试。

| 范围 | 通过 | 失败 | 跳过 |
| --- | ---: | ---: | ---: |
| ListKit 全库测试（未使用 only-testing 过滤） | 309 | 0 | 0 |
| 完整 LayoutLabUITests | 8 | 0 | 0 |

8 项 UI 测试全部执行：边界视图方向切换、自适应内容刷新与代码、网格模式／容器宽度／空内容、group 起始和居中停靠、双方向滚动的徽标定位、两种外层方向的正交场景、间距参数与代码／真实几何、2×3 分页停靠与尾组尺寸。

两套测试均首次运行通过，没有失败后重试或修复。运行前后 80 个源码、测试与构建配置文件的 SHA-256 一致，未改动代码或测试，未降低断言；清单位于 `/tmp/listkit-spacing-full-before.json`。本轮只追加验证记录，git diff --check 通过，未暂存、未提交、未推送。

- 全库结果：`~/Library/Developer/XcodeBuildMCP/workspaces/ListKit-1de09571a095/result-bundles/test_sim_2026-10-30T01-12-29-444Z_pid7139_600412f6.xcresult`
- 全库日志：`~/Library/Developer/XcodeBuildMCP/workspaces/ListKit-1de09571a095/logs/test_sim_2026-10-30T01-12-29-444Z_pid7139_ba942f32.log`
- 完整 Layout Lab UI 结果：`~/Library/Developer/XcodeBuildMCP/workspaces/ListKit-1de09571a095/result-bundles/test_sim_2026-10-30T01-13-19-016Z_pid7139_888c1367.xcresult`
- UI 日志：`~/Library/Developer/XcodeBuildMCP/workspaces/ListKit-1de09571a095/logs/test_sim_2026-10-30T01-13-19-016Z_pid7139_4927a286.log`

上述结果未发现本次间距 API 修改引入的回归，覆盖当前模拟器环境。未执行真机、其他系统版本、Release、Layout Lab 之外的 UI 测试或示例单元测试全套；此前定向复查与编译契约证据保持各自日期和范围。
