# ListKit API Hardening Requirements

## Goal

让 Rebirth 的列表代码从迁移兼容状态收敛到长期 ListKit DSL 写法，同时补齐实时页面需要的 row 定位和可见刷新能力。

## Requirements

1. App 层不得再引用 `AppListSection`、`AppListCellItem`、`AnyAppListCellItem` 或 `AppListSectionBuilder`。
2. App 层不得再引用 ListKit migration-only API：`ListCellProvider`、`ListProviderSection`、`ListSupplementaryProvider`、`AnyListCellProvider`。
3. `CollectionListAdapter` 必须提供基于当前 snapshot 的 row lookup API，页面不需要维护第二套 `sections` 才能定位 row。
4. `CollectionListAdapter` 必须提供可见 row 轻刷新和布局刷新 API，用于公屏、麦位、工具面板等实时页面。
5. 公屏必须保留自动滚底、可见消息动态高度刷新和链接点击行为。
6. 麦位和工具面板必须保留现有刷新行为，不允许回退到手写 data source。
7. `UICollectionView` generic 注册和复用调用优先使用 `collectionView.lk.*`；FSPagerView 和 UIKit 原生 reuseIdentifier API 不属于本轮清理范围。
8. 迁移完成后删除 App 侧桥接层文件，README 补充实时刷新和桥接层退场示例。
