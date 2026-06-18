# ListKit Table Adapter Requirements

## Summary

`TableListAdapter` 是 ListKit 的 UITableView 适配层。它不复用当前已经绑定 UICollectionView 的 `Row`、`ListSection` 和 `ListContext` public 类型，而是新增独立 Table DSL，并复用 ListKit Core 的 identity、refresh、diagnostics、apply options 和 event 语义。

首版目标是覆盖 UIKit 原生 UITableView 常用能力：cell/header/footer、diffable apply、选择、展示、预取、高度、context menu、editing、move/reorder、leading/trailing swipe、可见刷新和 scroll forwarding。ListKit package 不引入 `SwipeCellKit`；第三方 swipe 由 App 层 bridge 或页面自管。

## Requirements

### Requirement 1: 独立 Table DSL

**User Story:** 作为仍使用 UITableView 的页面开发者，我希望用接近 CollectionListAdapter 的写法声明 table 内容，同时不影响已迁移的 UICollectionView 页面。

#### Acceptance Criteria

- WHEN 新增 Table adapter THE SYSTEM SHALL 提供独立 `TableListAdapter<SectionID>`。
- WHEN 声明 table section THE SYSTEM SHALL 使用 `TableSection`，不复用 collection-only 的 `ListSection`。
- WHEN 声明 table row THE SYSTEM SHALL 使用 `TableRow`，不复用 collection-only 的 `Row`。
- WHEN row/header/footer 回调需要上下文 THE SYSTEM SHALL 提供 `TableListContext`，不复用持有 `UICollectionView` 的 `ListContext`。
- WHEN 新增 public symbol THE SYSTEM SHALL 保持英文命名，Swift Doc 和 README 说明保持中文。

### Requirement 2: Core 语义复用

**User Story:** 作为维护者，我希望 UITableView adapter 复用已经稳定的 ListKit 核心规则，而不是维护第二套 identity 和刷新语义。

#### Acceptance Criteria

- WHEN 构建 table row identity THE SYSTEM SHALL 复用 `AnyListID` 和 `AnyListIdentity`。
- WHEN 判断内容刷新 THE SYSTEM SHALL 复用 `refreshID`、`RowRefreshPolicy` 和 `ListApplyRefreshStrategy` 语义。
- WHEN 发现重复 section/row/header/footer identity THE SYSTEM SHALL 复用 ListKit diagnostics 风格，在 diffable apply 前给出清晰问题。
- WHEN apply 完成 THE SYSTEM SHALL 输出与 `ListApplySummary` 等价的 insert/delete/keep/snapshotRefresh/visibleRefresh 统计。
- WHEN row/header/footer 发送业务事件 THE SYSTEM SHALL 复用 `ListEvent` 类型约束。

### Requirement 3: Apply API 对齐

**User Story:** 作为已经使用 CollectionListAdapter 的开发者，我希望 TableListAdapter 的 apply 入口和查询 helper 看起来一致。

#### Acceptance Criteria

- WHEN 页面调用 `apply` THE SYSTEM SHALL 支持 builder、section array、completion、refresh strategy、完整 options overload。
- WHEN apply 返回结果 THE SYSTEM SHALL 支持读取 summary 并链式绑定事件。
- WHEN 页面按 section index 查询 THE SYSTEM SHALL 提供 `sectionIdentifier(at:)`。
- WHEN 页面按 section id 查询数量 THE SYSTEM SHALL 提供 `rowCount(in:)` 或等价 `itemCount(in:)`。
- WHEN 页面按 row id 查询位置 THE SYSTEM SHALL 提供 `indexPaths(forRowID:in:)`。
- WHEN 页面需要滚动到底 THE SYSTEM SHALL 提供 `scrollToLastRow(in:at:animated:)`。

### Requirement 4: UITableView 可复用基础层

**User Story:** 作为页面开发者，我希望 UITableView cell/header/footer 也能使用 ListKit 的 class/nib 自动注册和类型安全 dequeue。

#### Acceptance Criteria

- WHEN 使用 table cell THE SYSTEM SHALL 支持 `tableView.lk.register(Cell.self)` 和 `tableView.lk.dequeue(Cell.self, for:)`。
- WHEN 使用 table header/footer THE SYSTEM SHALL 支持 `tableView.lk.registerHeaderFooter(View.self)` 和 `tableView.lk.dequeueHeaderFooter(View.self)`。
- WHEN 同名 nib 存在 THE SYSTEM SHALL 优先注册 nib；否则注册 class。
- WHEN App 层仍使用原生 reuseIdentifier API THE SYSTEM SHALL 不强制迁移。

### Requirement 5: Row 内容和可见刷新

**User Story:** 作为实时列表开发者，我希望 table row 能像 collection row 一样区分 identity 和内容刷新版本。

#### Acceptance Criteria

- WHEN `TableRow` identity 变化 THE SYSTEM SHALL 交给 UITableView diffable data source 执行插入/删除。
- WHEN identity 不变且 `refreshID` 变化 THE SYSTEM SHALL 按 refresh policy 执行 reload/reconfigure 等价行为。
- WHEN 只需要轻量更新可见 cell THE SYSTEM SHALL 提供 `reconfigureVisibleRows(forRowID:in:)`。
- WHEN 需要重新量高或完整刷新 THE SYSTEM SHALL 提供 `reloadVisibleRows(forRowID:in:)`。
- WHEN 使用 `.automaticVisible` THE SYSTEM SHALL 在 apply completion 后重配仍可见的旧 row。

### Requirement 6: Header 和 Footer

**User Story:** 作为 UITableView 页面开发者，我希望 header/footer 既能声明 view，也能声明高度和刷新版本。

#### Acceptance Criteria

- WHEN section 需要 header THE SYSTEM SHALL 支持 `TableHeader` builder。
- WHEN section 需要 footer THE SYSTEM SHALL 支持 `TableFooter` builder。
- WHEN header/footer 使用 `UITableViewHeaderFooterView` THE SYSTEM SHALL 支持自动注册和类型安全 dequeue。
- WHEN header/footer 需要高度 THE SYSTEM SHALL 支持 fixed、automatic 和 estimated height 描述。
- WHEN header/footer 内容变化 THE SYSTEM SHALL 支持 `refreshID` 和 refresh policy。

### Requirement 7: Selection、Display 和 Prefetch

**User Story:** 作为页面开发者，我希望 Table DSL 能覆盖常用 UITableViewDelegate/DataSourcePrefetching 回调。

#### Acceptance Criteria

- WHEN row 被选中或取消选中 THE SYSTEM SHALL 调用 row 的 selection handler。
- WHEN row 声明初始选中态 THE SYSTEM SHALL 在 cell 展示时同步到 table view。
- WHEN row 即将展示或结束展示 THE SYSTEM SHALL 调用 display/endDisplay handler。
- WHEN table view 触发预取 THE SYSTEM SHALL 调用 prefetch/cancelPrefetch handler。
- WHEN 页面还需要 scroll 回调 THE SYSTEM SHALL 通过 `scrollDelegate` 转发常用 `UIScrollViewDelegate` 方法。

### Requirement 8: 高度和估算高度

**User Story:** 作为 UIKit 页面维护者，我希望不同 row/header/footer 可以声明高度，兼容自动高度和固定高度列表。

#### Acceptance Criteria

- WHEN row 声明 fixed height THE SYSTEM SHALL 在 `heightForRowAt` 返回固定值。
- WHEN row 声明 automatic height THE SYSTEM SHALL 返回 `UITableView.automaticDimension`。
- WHEN row 声明 estimated height THE SYSTEM SHALL 在 `estimatedHeightForRowAt` 返回估算值。
- WHEN section header/footer 声明高度 THE SYSTEM SHALL 转发到对应 delegate 方法。
- WHEN 未声明高度 THE SYSTEM SHALL 尊重 table view 当前默认配置。

### Requirement 9: Context Menu、Editing 和 Swipe

**User Story:** 作为需要消息列表、排行列表或管理列表的页面开发者，我希望首版 Table adapter 覆盖 UIKit 原生编辑和滑动能力。

#### Acceptance Criteria

- WHEN row 声明 context menu THE SYSTEM SHALL 在 iOS 13+ 返回对应 `UIContextMenuConfiguration`。
- WHEN row 声明可编辑 THE SYSTEM SHALL 支持 `canEditRowAt` 和 `commit editingStyle`。
- WHEN row 声明可移动 THE SYSTEM SHALL 支持 `canMoveRowAt` 和 `moveRowAt`。
- WHEN row 声明 leading/trailing swipe THE SYSTEM SHALL 返回 `UISwipeActionsConfiguration`。
- WHEN 页面使用 `SwipeCellKit` THE SYSTEM SHALL 通过 App 层 bridge 或页面自管接入，ListKit package 不直接依赖第三方库。

### Requirement 10: Delegate Forwarding 和迁移边界

**User Story:** 作为逐步迁移页面的维护者，我希望 TableListAdapter 接管 delegate 后仍保留必要 escape hatch。

#### Acceptance Criteria

- WHEN adapter 初始化 THE SYSTEM SHALL 接管 `tableView.dataSource`、`tableView.delegate` 和 `tableView.prefetchDataSource`。
- WHEN 页面设置 forwarding delegate THE SYSTEM SHALL 转发 adapter 未消费或可组合的 UITableViewDelegate/UIScrollViewDelegate 回调。
- WHEN 第三方库需要成为 table delegate THE SYSTEM SHALL 不由 ListKit 强行接管该库；页面应使用 app-side bridge。
- WHEN 首版实现 THE SYSTEM SHALL 不迁移 Rebirth 业务页面，只提供框架能力和测试。

## Out of Scope

- 不把现有 `Row`、`ListSection`、`Supplementary` 泛化为跨 UICollectionView/UITableView public API。
- 不在 ListKit package 引入 `SwipeCellKit` 或其他第三方依赖。
- 不在首版实现中迁移 Rebirth 业务页面；本 spec 只提供 ListKit 框架能力和测试覆盖。
