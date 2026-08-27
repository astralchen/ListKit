# ListKit Refresh System V2 Requirements

## Summary

发版前直接采用破坏性的新刷新契约。最低系统为 iOS 15，语言模式为 Swift 6；不保留旧 API
别名或兼容 shim。Collection 与 Table 共享刷新决策和 mutation 调度，但 UIKit data source、
delegate、layout 与具体执行仍分别留在 adapter。

## Requirement 1: 正交 Row 刷新

1. Row 必须通过 `ListRowRefreshRule` 分别声明 `trigger`、`scope` 和 `action`。
2. `ListRefreshTrigger.automatic` 在未设置 `refreshID` 时每次 apply 触发；设置后仅在值变化时触发。
3. `nil -> value`、`value -> nil` 和不同非 nil 值都属于变化；`nil -> nil` 和相同非 nil 值不属于变化。
4. `.visible` reconfigure 必须直接配置可见 Cell；visible reload 必须只筛选可见 identity，并通过 diffable snapshot `reloadItems` 提交，避免调用 diffable data source 禁止的列表 mutation API。
5. 同一 presentation identity 的冲突按 reload、invalidate reconfigure、plain reconfigure 的顺序取最强动作。
6. 不同 presentation identity 的动作不得互相升级。

## Requirement 2: Supplementary 真实能力

1. Supplementary 必须使用 `ListSupplementaryRefreshRule`，不得公开 Row scope。
2. `.reconfigureVisible` 只配置已存在的 view，并按 layout policy 汇总一次显式布局需求。
3. `.reloadSection` 使用 snapshot `reloadSections`，并明确连带重载所属 Section 的 Row。
4. Section reload 必须覆盖该 Section 内重复的 Row 与 Supplementary 刷新动作。
5. Collection outline Section reload 后必须恢复当前 expansion state，而不是描述树初始状态。

## Requirement 3: 统一调度与取消

1. `apply`、Row refresh、Section reload 和 `reloadAll` 必须进入同一 FIFO scheduler。
2. `.serial` 严格保持调用顺序；`.coalesceLatest` 只合并相邻且兼容的定向请求。
3. 新 apply 只能 supersede 未完成的旧 coalescing apply，不得 supersede 定向刷新。
4. 每个 async 调用必须拥有可取消 subscriber；completion 和 fire-and-forget subscriber 不因 Task cancellation 被移除。
5. cancel-before-register 和 cancel-before-commit 返回 `.cancelledBeforeCommit`；commit 后取消必须等待真实结果。
6. continuation、completion、supersede 和 cancellation 路径必须恰好完成一次。
7. 外部 completion 调用前 scheduler 必须恢复空闲；completion 返回后才启动下一 entry。

## Requirement 4: 指标与完成时序

1. `ListApplySummary` 必须通过 `ListRefreshMetrics` 暴露五类动作指标。
2. 合并定向请求时，每个 subscriber 只得到自己的 requested、matched 和动作指标。
3. Section reload 连带更新的 Row 不计入 `reloadedRowCount`，覆盖动作不得重复计数。
4. `.cancelledBeforeCommit` 的动作指标必须全部为零。
5. 执行顺序必须为 global snapshot、outline、事件重绑、可见配置、selection/focus、单次显式布局、最终滚动、等待动画、完成 scheduler。

## Requirement 5: 公共 DSL 与 Demo

1. `RowGroup` 和 `TableRowGroup` 必须提供公开 builder 初始化器。
2. Section 的类型擦除存储必须允许外部模块只读检查。
3. LiveRoom Row 回调只发送事件；Controller 校验 payload 与 context identity。
4. Mic/Gift 选择必须幂等，只对真实状态变化增加 version，并且一次事件最多 render 一次。
