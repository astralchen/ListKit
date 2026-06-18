# ListKit Item Supplementary Refresh Requirements

## Goal

补齐 item-level supplementary 作为 badge、角标等 UI 时的数据刷新语义，并让 builder API 名称清晰表达 item supplementary layout。

## Requirements

1. `ListSectionSupplementary` 必须提供 `itemSupplementaryLayout(...)`，用于把当前 supplementary 放到每个 item 上。
2. `ListSectionSupplementary` 的旧短名 item layout modifier 不再作为 public API 暴露，因为 ListKit 尚未发布且该命名容易和 row/item 混淆。
3. item-level supplementary 必须继续复用现有 supplementary register、dequeue、configure、tap、display、endDisplay、refreshID 和 refreshPolicy 语义。
4. 当 supplementary 的 refresh policy 为 `.automaticVisible` 或 `.alwaysVisible`，`apply` 完成后必须重配当前可见 supplementary view。
5. 当 supplementary 的 refresh policy 为 `.whenRefreshIDChanges`，只有同 identity supplementary 的 refreshID 变化时才重配当前可见 supplementary view。
6. 当 supplementary 的 refresh policy 为 `.never`，`apply` 不得主动重配当前可见 supplementary view。
7. `CollectionListAdapter` 必须提供按 kind 刷新当前可见 supplementary 的手动 API。
8. `CollectionListAdapter` 必须提供按 kind + rowID 刷新当前可见 item supplementary 的手动 API。
9. `ListApplySummary` 必须能区分 row refresh 统计和 supplementary refresh 统计，避免 supplementary 行为被隐藏在 row 指标里。
