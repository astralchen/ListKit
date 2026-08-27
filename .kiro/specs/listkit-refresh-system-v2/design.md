# ListKit Refresh System V2 Design

## Public Contract

- Row：`ListRefreshTrigger + ListRefreshScope + ListRowRefreshAction` 组成 `ListRowRefreshRule`。
- Supplementary：`ListRefreshTrigger + ListSupplementaryRefreshAction` 组成 `ListSupplementaryRefreshRule`。
- `ListApplyOptions` 只包含 transaction、applicationMode 和 diagnostics。
- 环境变化使用 `reloadAll()`；结构和内容描述变化使用 `apply`；局部主动刷新使用 Row/Section API。
- `ListApplySummary` 和 `ListRefreshSummary` 统一引用 `ListRefreshMetrics` 与 `ListAnimationSummary`。

## Shared Planner

Planner 只接受纯 Swift 节点快照。它先解析 supplementary Section reload，再解析未被覆盖的
Row snapshot 动作，最后判断是否需要 visible pass。输出按 presentation identity 去重；
reload Section 按 Section identity 去重。所有输出按描述树顺序保持确定性。

## Mutation Scheduler

Scheduler entry 的逻辑状态为 queued、starting、committed、finished。定向请求保存 subscriber
自己的目标集合和 action，执行前从最新 committed snapshot 解析目标；合并只合并执行批次，
不合并调用方指标。`reloadAll` 是要求 `hasUncommittedUpdates == false` 的普通队首 entry。

async API 使用统一 cancellation bridge。bridge 以锁保护 cancel-before-register 状态和 exactly-once
continuation；scheduler 只允许移除 queued subscriber。adapter 或 scheduler 在 commit 前释放时，
排队 subscriber 以 cancelled 结果结束。

## UIKit Backend Matrix

| 动作 | Collection / Table 执行 | 动画来源 |
| --- | --- | --- |
| visible Row reconfigure | 直接配置当前 Cell | contentAnimation |
| allMatching Row reconfigure | snapshot reconfigureItems | snapshotAnimation |
| visible Row reload | snapshot reloadItems，仅含可见 identity | contentAnimation |
| allMatching Row reload | snapshot reloadItems | snapshotAnimation |
| Supplementary reconfigureVisible | 直接配置当前 view | contentAnimation |
| Supplementary reloadSection | snapshot reloadSections | snapshotAnimation |
| 显式布局重测量 | Collection invalidate / Table batch update | layoutAnimation |
| 最终滚动或锚点补偿 | scroll API | scrollAnimation |

visible helper 只返回动作数和布局需求；它不得自行失效布局。visible reload 虽然只匹配可见
identity，但仍必须通过 diffable snapshot 提交，因为 UIKit 禁止在 diffable data source 上直接调用
Collection/Table 的 mutation API。一个 mutation 最多执行一次显式布局，
滚动目标和 anchor compensation 必须基于最终几何计算。

## Demo Data Flow

`LiveRoomCollectionEvent` 使用 `selectMicSeat(String)`、`selectGift(String)` 和 `sendGift(String)`。
Row 只通过 context 发送事件。Controller 校验 Section 与 item identity 后调用幂等 ViewModel；
只有返回 `true` 时 render。send gift 在同一事件内完成必要选择、发送、单次 render 和滚动。
