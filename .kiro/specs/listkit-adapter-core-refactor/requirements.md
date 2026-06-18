# ListKit Adapter Core Refactor Requirements

## Summary

`CollectionListAdapter` 和 `TableListAdapter` 当前分别维护 apply、diagnostics、summary、refresh decision 和 event routing 规则。两者 UIKit 边界不同，但核心规则应只有一份，避免共享基础设施在修 bug 时出现分叉。

本规格只抽取纯 Swift core。Collection 继续负责 `UICollectionView`、supplementary、compositional layout 和 layout invalidation；Table 继续负责 `UITableView`、row/header/footer delegate。ListKit 尚未对外发布，可以调整内部结构和必要 public API，但本次不主动迁移 Rebirth 业务页面。

## Requirements

### Requirement 1: Shared Apply Planner

**User Story:** 作为 ListKit 维护者，我希望两个 adapter 使用同一套 apply planner，避免 refresh 和 summary 规则分叉。

#### Acceptance Criteria

- WHEN adapter applies sections THE SYSTEM SHALL map adapter-specific sections into shared `ListSectionSnapshot` values.
- WHEN an apply plan is created THE SYSTEM SHALL compute insert/delete/keep summary from row identities in one shared implementation.
- WHEN `refreshID` changes on kept rows THE SYSTEM SHALL count `refreshIDChangedCount` in one shared implementation.
- WHEN `ListApplyRefreshStrategy.forceReload` is used THE SYSTEM SHALL refresh only row identities present in both old and new snapshots.
- WHEN `ListApplyRefreshStrategy.visibleOnly` is used THE SYSTEM SHALL not request diffable snapshot row refresh.

### Requirement 2: Shared Diagnostics Stop Policy

**User Story:** 作为页面开发者，我希望 duplicate identity 被 ListKit 在 diffable 前拦截，且 warning/assertion 行为在 Collection 和 Table 一致。

#### Acceptance Criteria

- WHEN diagnostics mode is `.disabled` THE SYSTEM SHALL allow diffable apply even if diagnostics issues exist.
- WHEN diagnostics mode is `.warning` THE SYSTEM SHALL stop before diffable apply and keep previous adapter state unchanged.
- WHEN diagnostics mode is `.assertion` THE SYSTEM SHALL trigger assertion and stop before diffable apply.
- WHEN diagnostics stop occurs THE SYSTEM SHALL return a summary containing diagnostics issues and zero snapshot/visible refresh counts.

### Requirement 3: Shared Supplementary Summary

**User Story:** 作为使用 table header/footer 或 collection supplementary 的开发者，我希望 supplementary 的刷新统计和策略语义一致。

#### Acceptance Criteria

- WHEN supplementary identity is kept and `refreshID` changes THE SYSTEM SHALL count `supplementaryRefreshIDChangedCount`.
- WHEN Collection supplementary uses `.whenRefreshIDChanges` THE SYSTEM SHALL refresh visible supplementary only when `refreshID` changed.
- WHEN Table header/footer uses `.whenRefreshIDChanges` THE SYSTEM SHALL include header/footer in supplementary summary and visible refresh policy.
- WHEN supplementary uses `.never` THE SYSTEM SHALL not run default visible refresh.

### Requirement 4: Shared Event Routing

**User Story:** 作为维护者，我希望 Collection 和 Table 事件绑定只维护一份 typed routing 逻辑。

#### Acceptance Criteria

- WHEN adapter binds a typed `ListEvent` THE SYSTEM SHALL store it through shared `ListEventRouter`.
- WHEN context sends an event THE SYSTEM SHALL dispatch only to the handler registered for that concrete event type.
- WHEN no handler is registered THE SYSTEM SHALL safely ignore the event.
- WHEN Collection and Table use different context types THE SYSTEM SHALL keep context generic and adapter-specific.

## Out of Scope

- 不合并 Collection DSL 和 Table DSL。
- 不把 compositional layout、UITableView delegate、diffable data source apply 迁入 core。
- 不主动迁移 Rebirth 业务页面调用点。
