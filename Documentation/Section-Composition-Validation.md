# Section 组合 API 验证

日期：2026-10-29。实现和验证均基于当前未提交工作区。

## 变更

- 保留多闭包构造，新增 Section `.supplementaries { }` 替换入口。
- 用 `.addingSupplementaries { }` 取代 `.addingSectionSupplementaries { }`，移除旧入口，不保留兼容别名。
- 新增 `.addingDecorations { }`；与现有 `.decorations { }` 形成设置／追加对称入口。
- 空集合设置清空，空追加保持；内容变化不改写显式布局，重复 kind 和必需绑定缺失仍由既有校验报告。
- 消息列表示例提取 RowGroup、布局值和接收当前数量的 header 方法；去除冗余默认刷新、zIndex 和无条件绑定的 whenContentExists。
- README、布局指南和 DocC 增加组合规则与迁移说明。

## 验证结果

模拟器：iPhone 17 Pro / iOS 26.5，Debug。

| 检查 | 结果 |
| --- | --- |
| SectionCompositionTests | 最终 5/5 通过 |
| ListKitPublicAPITests / KindAssociationTests / SupplementaryReloadIsolationTests | 6 + 5 + 13 = 24/24 通过 |
| ExamplesTests 的 LiveRoomViewModelTests / ListKitLayoutTests | 31/31 通过，示例及测试目标编译成功 |
| iOS 15 Swift 6 编译契约 | 79/79 符合预期：18 个合法用法通过，61 个非法或移除入口按预期拒绝 |
| Markdown 布局指南与 DocC 内容一致性 | 通过 |
| git diff --check | 通过 |

新增测试通过公开接口构建并经 adapter 解析，覆盖多闭包／链式等价、值提取、刷新版本与身份、真实窗口中的可见 header 重配、替换与追加、空集合、顺序、重复 kind、缺失绑定及恢复、默认装饰几何和完整布局替换。

首轮库针对性运行是 28 通过、1 失败：新增测试在 collection view 完成布局前直接请求 supplementary，触发 UIKit 异常。测试改为真实 UIWindow、等待异步 apply、执行布局，再检查可见视图；重跑全部 5 个新增测试后通过。此修正只涉及测试夹具，库实现未因此修改。

## 本机证据

- 首轮库运行日志（含失败和 24 项既有回归通过结果）：`/Users/sondra/Library/Developer/XcodeBuildMCP/workspaces/ListKit-1de09571a095/logs/test_sim_2026-10-29T09-53-38-512Z_pid87223_435a7d2f.log`
- 新增测试最终结果：`/Users/sondra/Library/Developer/XcodeBuildMCP/workspaces/ListKit-1de09571a095/result-bundles/test_sim_2026-10-29T09-55-27-506Z_pid87223_8072242d.xcresult`
- 示例最终结果：`/Users/sondra/Library/Developer/XcodeBuildMCP/workspaces/ListKit-1de09571a095/result-bundles/test_sim_2026-10-29T09-57-09-744Z_pid87223_480375ca.xcresult`
- 编译契约日志：`/private/tmp/listkit-section-composition-api.log`；`fail:` 表示预期编译拒绝，不是验证失败。

本次未运行完整库测试、完整示例测试、UI 自动化、真机、Release 或 iOS 15 runtime。iOS 15 证据仅为编译契约，不代表旧系统运行验证。未提交、推送或创建 PR。

## 后续：其余示例调用整理（2026-10-29）

此阶段只整理示例调用与阅读入口，没有继续修改库 API：

- LiveRoom：麦位、礼物和房间动态采用链式 Section 与独立布局／内容方法；消息和动态共用 RowGroup；API Guide 与管理列表提取长行声明；短 Section 保留内联。
- Context Menu：Section builder 负责组装，`menuRow(for:)` 集中展示菜单生命周期调用，保持弱引用捕获。
- Layout Lab：从同一配置快照组合 rows、完整布局、补充内容和装饰注册；运行代码与代码面板共用 kind 常量，面板显示链式入口和实际 supplementary 绑定。
- 清理冗余 automatic 刷新、默认装饰 zIndex 和无条件绑定的 whenContentExists；保留 allMatching、everyApply、内容刷新时的布局失效、环境驱动布局与所有稳定身份。
- README 增加示例源码导航。最后对 Grid recipe 的链式调用仅做换行整理，已检查去除空白后 token 完全一致。

验证环境为 iPhone 17 Pro Max / iOS 26.5 Simulator，Debug：

| 检查 | 结果 |
| --- | --- |
| ExamplesUnitTests 完整单元测试 | 51/51 通过，0 失败、0 跳过 |
| API Guide 展开／收起、菜单生命周期与提交、麦位／礼物事件 UI | 3/3 通过 |
| Layout Lab 参数／代码／几何、内容刷新与场景切换 UI | 2/2 通过 |
| 示例及测试目标编译、git diff --check | 通过 |

首次在 iPhone 17 Pro 上的构建成功，但测试调用在 300 秒后超时；期间 simctl 报告该设备会话失效／未启动。换到已启动的 iPhone 17 Pro Max，使用同一份测试产物重跑，51 项单元测试全部通过。保留首次日志，不将该超时记作通过。未运行其余 UI 测试、库全套、真机、Release 或旧系统运行验证。

本机证据根目录：`/Users/sondra/Library/Developer/XcodeBuildMCP/workspaces/ListKit-1de09571a095/`。

- 首次构建／超时日志：`logs/test_sim_2026-10-29T10-08-00-910Z_pid96016_c02aa3ad.log`
- 单元测试：`result-bundles/test_sim_2026-10-29T10-13-39-117Z_pid96016_0c8a8352.xcresult`
- 业务 UI：`result-bundles/test_sim_2026-10-29T10-14-15-774Z_pid96016_5a554f25.xcresult`
- Layout Lab UI：`result-bundles/test_sim_2026-10-29T10-16-47-958Z_pid96016_7196aa58.xcresult`
