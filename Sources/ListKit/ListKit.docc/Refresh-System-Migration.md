# 刷新系统迁移指南

在未发布版本中，ListKit 将刷新条件、范围和 UIKit 动作拆分为正交规则，并删除旧刷新策略和
apply 级强制刷新选项。迁移后，普通 `apply` 只遵循各节点的声明。

## Row 刷新

Collection Row 与 Table Row 使用 ``ListRowRefreshRule``：

```swift
Row(model: user, cell: UserCell.self) { cell, user, _ in
    cell.configure(user)
}
.refreshID(user.version)
.refresh(
    when: .refreshIDChanges,
    scope: .allMatching,
    action: .reconfigure(layout: .invalidate)
)
```

触发条件由 ``ListRefreshTrigger`` 表达：

- `automatic`：没有 `refreshID` 时每次 apply 刷新；有值时仅在值变化时刷新。
- `refreshIDChanges`：仅新旧 `refreshID` 不相等时刷新。
- `everyApply`：presentation identity 保持不变时，每次 apply 都刷新。
- `never`：apply 不主动刷新，但 adapter 的定向刷新 API 仍然有效。

`refreshID` 不参与 presentation identity。`nil` 与非 `nil` 之间的切换，以及两个不同的非
`nil` 值，都属于变化；`nil -> nil` 与相同非 `nil` 值不属于变化。

Row 的动作强度为：`reload` 高于带布局重测量的 `reconfigure`，后者高于普通
`reconfigure`。只有多个请求命中同一个 presentation identity 时才合并为更强动作，不会把
其他 Row 一并升级。

## Supplementary 刷新

SectionSupplementary 使用 ``ListSupplementaryRefreshRule``：

```swift
SectionSupplementary(ProfileHeaderView.self, kind: "profile", id: "profile") { view, _ in
    view.configure(title: title)
}
.refreshID(titleVersion)
.refresh(
    when: .refreshIDChanges,
    action: .reconfigureVisible(layout: .invalidate)
)
```

Supplementary 不公开 ``ListRefreshScope``。UIKit 没有 supplementary identity 级的 snapshot
reload：

- `reconfigureVisible` 直接配置当前存在的 supplementary view。
- `reloadSection` 通过 diffable `reloadSections` 重新进入 provider 生命周期，并连带 reload
  所属 Section 的 Row。

Section reload 覆盖同 Section 内已规划的 Row reload、Row reconfigure 和 Supplementary
reconfigure，避免重复执行和重复计数。

Table 的 header/footer 业务 identity 或视图类型变化，以及自定义 header/footer 的新增、
移除，会重载保留的 Section；这些结构更新不受 `.never` 限制。identity 稳定时，仅
refreshID 变化仍遵循节点规则，不会自动升级为 Section reload。

框架 compositional layout 按 Section identity 保持 Section reload 前的正交滚动偏移。
这同时适用于 supplementary 身份替换、`.reloadSection` 刷新动作与主动 `reloadSections`；
恢复偏移会限制在新内容的有效范围内。屏幕外尚未恢复的偏移会保留到实际恢复，连续
reload 不会用新容器的初始位置覆盖它；恢复完成后的滚动使用新的实际偏移。
`scrollToLastItem` 和 transaction 的显式滚动在找到有效目标后，清除目标 Section 的
pending 恢复，并使正在执行的刷新所捕获的旧偏移快照失效，避免刷新完成后跳回旧位置。
无效目标不会丢弃待恢复位置，其他 Section 的恢复状态也不受影响；后续刷新仍会捕获并
保持显式滚动后的新位置。
Section reload 仍可能替换 Cell 或触发复用，
不承诺保留 Cell 内部的临时状态、输入焦点或编辑内容。

## 主动刷新与全量刷新

以下入口各自承担单一语义：

- 普通 `apply`：提交新描述树，并遵循每个节点声明的刷新规则。
- `apply(applicationMode: .reloadData)`：使用新描述树执行 reload-data 提交。
- `reloadAll()`：重新刷新当前已经提交的描述树，适用于语言、主题、Dynamic Type 和 RTL 等
  环境变化。
- `reconfigureRows`、`reloadRows`、`reloadSections`：忽略节点 trigger，主动刷新明确目标。

定向 Row API 的默认 scope 是 `allMatching`。如只希望直接更新屏幕上的 Cell，请明确传入
`.visible`。Collection/Table 的可见 reload 仍通过 diffable snapshot 提交已过滤的可见
identity，避免直接调用 UIKit visible reload API 与 diffable data source 冲突。

## Summary 与取消

``ListRefreshMetrics`` 分别报告 snapshot Row reconfigure、可见 Row reconfigure、Row reload、
可见 Supplementary reconfigure 和 Section reload。Section reload 连带更新的 Row 不计入 Row
reload 数量，被 Section reload 覆盖的动作也不会重复计数。

``ListApplySummary`` 与 ``ListRefreshSummary`` 的 `animation.completionState` 可能为：

- `submitted`：同步 API 已入队或提交，尚未得到最终结果。
- `completed`：请求已处理，包括诊断拒绝的情况；正常提交等待快照、布局和内容过渡完成，
  不等待已发起的滚动动画结束。
- `superseded`：请求被后续可合并更新取代，可能尚未提交；已提交的部分不会回滚 UIKit。
- `cancelledBeforeCommit`：async subscriber 在 commit gate 前取消，实际动作指标为零。

`.coalesceLatest` 可替换尚未提交的请求。排队中的 apply/reloadAll 被取代时，最终刷新
指标为零，不执行也不报告计划中的动作；声明差异和诊断信息仍保留。它的回调不会覆盖
当前更新请求的 `lastApplySummary`。

已经提交的 apply 即使被后续请求标记为
`superseded`，仍会完成必要的可见内容刷新、布局更新及正交偏移恢复，再推进队列；
避免下一次相同 refreshID 或布局签名的提交遗漏更新。被取代请求不再执行尚未开始的
显式滚动指令。最终 `superseded` 摘要仍报告已执行的刷新、布局和动画指标，并在
completion 调用前更新 `lastApplySummary`；不会用提交时的初始指标覆盖实际工作量。

`.serial` 对 completion 内重入的 apply、定向 Row 刷新和 Section reload 同样遵循调用
顺序；重入请求排在已有请求之后。诊断拒绝队首 apply 后也继续推进队列，
不会使后续有效请求停留在 pending 状态。

async 请求在真正执行时同步检查取消状态，包括在前一请求的 completion 中取消的情况。
合并的 Row/Section 请求按 subscriber 检查，已取消 subscriber 的目标和动作不再参与执行；
其他 subscriber 继续正常完成。提交前取消的 async 结果只报告零实际动作，不包含
排队时尚未执行的刷新计划指标。

async API 在 commit 后收到取消不会回滚 UIKit，而是等待真实完成结果。completion 订阅者和
fire-and-forget 请求不受调用方 Task 取消影响。

## 已删除接口

本次变更不提供兼容别名。迁移时应直接删除旧 policy、action modifier 和 apply refresh
strategy，改用 ``ListRowRefreshRule``、``ListSupplementaryRefreshRule``、`reloadAll()` 或
定向刷新 API。`ListApplyOptions` 只保留 transaction、application mode 与 diagnostics。

