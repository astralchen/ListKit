# ListKit Conditional Layout Metadata Requirements

## Summary

ListKit 页面只初始化一次 `collectionView.collectionViewLayout = adapter.makeCompositionalLayout()`。之后所有 section layout、header/footer/supplementary、background decoration 的条件变化都通过 `adapter.apply { ... }` 表达，并由 ListKit 自动注册 decoration、更新 layout metadata、触发 layout invalidation。

## Requirements

- `CollectionListAdapter.apply(...)` 必须检测 section layout metadata 变化，并在 apply 完成后自动 invalidate 当前 `collectionView.collectionViewLayout`。
- layout metadata 包括 section 顺序、`ListSectionLayout`、custom layout id、legacy layout id、supplementary kind/identity/placement/size/pinning、background decoration kind/insets/zIndex。
- Row 数据或 refreshID 变化但 layout metadata 不变时，不应额外 invalidate layout。
- `ListSection` 必须支持 SwiftUI-like 条件 section layout 声明：条件写在 `layout:` builder 内，例如 `if isGrid { GridLayout(...) } else { ListLayout(...) }`。
- `ListSection` 必须支持 SwiftUI-like 条件 header/footer/supplementary 声明：条件写在 `header:`、`footer:`、`supplementaries:` builder 内，例如 `if showHeader { Header(...) }`。
- `ListSection` 必须支持 SwiftUI-like 条件 supplementary layout 声明：条件写在 `supplementaryLayouts:` builder 内，例如 `if isPinned { BoundarySupplementaryLayout(...) }`。
- `ListSection` 不提供 `headerIf`、`footerIf`、`supplementaryIf` 这类条件参数 API；条件统一放在 builder 的 `if` 分支里。
- `ListSection` 必须支持 SwiftUI-like 条件 background decoration 声明：条件写在 `background:` builder 内，例如 `if showBackground { BackgroundDecoration(...) }`。
- `ListSection` 必须支持 section background decoration DSL，并把 decoration item 写入 compositional section。
- typed background decoration view 必须自动注册到当前 compositional layout；raw kind 入口不自动注册 view。
- 页面不需要因为条件 `.layout(...)`、header/footer 或 background decoration 变化重新设置 `collectionView.collectionViewLayout`。
