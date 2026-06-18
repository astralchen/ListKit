# ListKit CellKit Migration Design

## Architecture

迁移保持现有 UIKit 页面结构，只替换列表数据源层。每个旧 CellKit 页面持有 `CollectionListAdapter<Section>`，数据变化时 rebuild `ListSection` 描述树。布局优先用 ListKit layout DSL；旧页面已有高度定制的 compositional layout 时使用 `.layout(.custom(id:) { ... })` 或保留显式 layout provider。

## ListKit Additions

- `UICollectionView` kind 常量和 `elementKind(for:)` 从 CellKit 平移到 ListKit 的 reusable 层。
- `UICollectionViewLayout.registerDecorationView(_:forKind:)` 平移到 ListKit，继续支持 nib/class 自动注册。
- `UICollectionViewCompositionalSeparatorLayout` 平移到 ListKit，供设置、榜单、礼物记录等页面继续使用分隔线 decoration。
- 如旧复杂 item 暂时需要按 provider 生成 cell，使用 ListKit provider row 逃生口承载，页面仍通过 `CollectionListAdapter.apply { ListSection { ... } }` 进入 ListKit diff/refresh 流程。

## App Migration

- `CollectionViewController`、`CollectionViewSectionType`、`DataSourceType`、`apply(_ sections:)` 全部替换为 `CollectionListAdapter`。
- 单 cell 类型 section 用 `ForEach(data,id:) + Row(model:cell:)`。
- 混合 cell 类型或旧复杂 item 先改为普通配置器，再由 ListKit Row 包装。
- Supplementary 从旧 item 改为 `.header/.footer/.supplementary`，复杂旧配置器由 configure 闭包调用。
- 手写 data source 页面只依赖注册/dequeue helper 时，改为 `collectionView.lk.register` / `collectionView.lk.dequeue`。

## High Risk Pages

- `PublicMessageViewController`：保留新消息计数、自动滚底、可见消息布局刷新。
- `SeatPositionViewController`：保留布局切换、可见项轻刷新、麦位位置查询。
- `ToolbarViewController`：保留动态 PK 状态、倒计时刷新和弹窗跳转。

## Dependency Cleanup

App build phases、package product dependencies、local package references 移除 CellKit。文档包表更新为 ListKit。`SharePackage/CellKit` 目录不删除。
