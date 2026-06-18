# ListKit Item Supplementary Refresh Design

## API Shape

`ListSectionSupplementary` 的旧短名 item layout modifier 改名为 `itemSupplementaryLayout(...)`：

```swift
SectionSupplementary("vip-dot", BadgeView.self, id: "vip-dot") { view, context in
    view.configure()
}
.itemSupplementaryLayout(
    anchor: .topTrailing,
    width: .absolute(18),
    height: .absolute(18),
    fractionalOffset: CGPoint(x: 0.25, y: -0.25),
    zIndex: 10
)
```

Section 级 `.itemSupplementaryLayout(kind:...)` 保持不变。两者命名对齐，调用点能看出配置的是 item-level supplementary layout。

## Adapter Refresh Flow

`AnySupplementary` 增加内部 `configureVisibleView` 闭包。普通 dequeue 仍走 `viewProvider`；可见刷新只对已存在的 supplementary view 调用 configure，不触发新的 dequeue。

`CollectionListAdapter.apply` 在 rebuild 前保存旧 supplementary lookup。snapshot apply completion 后，adapter 遍历 layout 当前可见 supplementary attributes，按 kind + section 找到新旧 supplementary：

- `.automaticVisible` 和 `.alwaysVisible`：只要 identity 在旧 lookup 中存在，就重配可见 view。
- `.whenRefreshIDChanges`：旧 identity 存在且 refreshID 变化时重配可见 view。
- `.never`：跳过。

手动刷新 API 不依赖 refresh policy，直接重配匹配 kind、section 和可选 rowID 的当前可见 supplementary view。

## Summary

`ListApplySummary` 保留 row 统计字段，并新增 supplementary 专用字段：

- `supplementaryRefreshIDChangedCount`
- `visibleSupplementaryRefreshCount`

现有 `refreshIDChangedCount`、`snapshotRefreshCount` 和 `visibleRefreshCount` 继续表示 row 行为，避免破坏已有测试和调用方理解。
