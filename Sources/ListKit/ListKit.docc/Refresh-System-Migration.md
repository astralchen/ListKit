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

Header、Footer 和自定义 Supplementary 使用 ``ListSupplementaryRefreshRule``：

```swift
Header(ProfileHeaderView.self, id: "profile") { view, _ in
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
- `completed`：UIKit 更新、布局、滚动与动画已经结束。
- `superseded`：已提交的 coalesceLatest mutation 被更新请求取代；不会回滚 UIKit。
- `cancelledBeforeCommit`：async subscriber 在 commit gate 前取消，实际动作指标为零。

async API 在 commit 后收到取消不会回滚 UIKit，而是等待真实完成结果。completion 订阅者和
fire-and-forget 请求不受调用方 Task 取消影响。

## 已删除接口

本次变更不提供兼容别名。迁移时应直接删除旧 policy、action modifier 和 apply refresh
strategy，改用 ``ListRowRefreshRule``、``ListSupplementaryRefreshRule``、`reloadAll()` 或
定向刷新 API。`ListApplyOptions` 只保留 transaction、application mode 与 diagnostics。

