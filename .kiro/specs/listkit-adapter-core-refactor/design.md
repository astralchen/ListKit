# ListKit Adapter Core Refactor Design

## Architecture

新增 `Core/ListApplyCore.swift`，承载纯 Swift 的 apply planning、summary、refresh decision、diagnostics stop policy 和 event router。Adapter 每次 apply 时把自身 section 描述树转换成 `ListSectionSnapshot`，core 返回 `ListApplyPlan`，adapter 只负责注册 view、构建 UIKit diffable snapshot、执行 UIKit apply 和可见 view 重配。

Core types are internal to ListKit:

```swift
struct ListNodeSnapshot {
    let identity: AnyListIdentity
    let refreshID: AnyListID?
    let refreshRule: ListNodeRefreshRule
    let role: ListNodeRole
}

struct ListSectionSnapshot {
    let sectionID: AnyListID
    let rows: [ListNodeSnapshot]
    let supplementaries: [ListNodeSnapshot]
}
```

`ListNodeRole` distinguishes row and supplementary-like nodes. Collection headers/footers/custom supplementary and Table header/footer all map to supplementary nodes. Row insert/delete/keep counts remain row-only to preserve `ListApplySummary` public semantics; supplementary changes use the existing supplementary fields.

## Apply Planner

`ListApplyPlanner.makePlan(old:new:options:diagnosticsIssues:)` returns:

- `shouldApplyDiffable`
- `snapshotReconfigureItems` / `snapshotLayoutInvalidationItems` / `snapshotReloadItems`
- `shouldRunVisibleRefresh`
- `initialSummary`
- `completedSummary(visibleReconfiguredRowCount:visibleReloadedRowCount:visibleReconfiguredSupplementaryCount:)`
- old/new row and supplementary node lookups for adapter completion work

Refresh rules:

- Row 的 trigger、scope 和 action 全部来自 `ListRowRefreshRule`；`.allMatching` 进入 snapshot planner，`.visible` 进入 visible pass。
- Supplementary 使用独立 `ListSupplementaryRefreshRule`；`.reloadSection` 先覆盖所属 Section 内的 Row 和 supplementary 动作。
- 同一 Row presentation identity 的冲突按 reload、invalidate reconfigure、plain reconfigure 取最强动作。
- apply 级刷新覆盖已经删除；普通 apply 只遵循节点声明。

Diagnostics stop rules are centralized. `.warning` and `.assertion` return `shouldApplyDiffable == false`; `.assertion` also calls `assertionFailure`.

## Adapter Boundaries

Collection adapter keeps:

- `UICollectionViewDiffableDataSource`
- iOS 15+ 的 `reconfigureItems`、`reloadItems` 与显式 layout invalidation
- supplementary lookup by kind/section
- layout signature/invalidation
- compositional layout diagnostics

Table adapter keeps:

- `UITableViewDiffableDataSource`
- row/header/footer registration and delegate callbacks
- scoped row reconfigure/reload execution and Table layout remeasurement
- header/footer visible refresh after apply completion

Both adapters replace duplicated event dictionaries with `ListEventRouter<Context>`.

Both adapters also share `ListMutationCoordinator` and the pending mutation request model. The
coordinator permits only one UIKit mutation at a time, preserves `.serial` order, coalesces the
latest pending apply, merges compatible pending Row IDs, and upgrades action conflicts using
`reload > reconfigure+invalidate > reconfigure`.

## Testing

Core tests use `@testable import ListKit` and construct `ListNodeSnapshot` directly. Adapter tests cover integration gaps that pure core cannot see, especially Table header/footer visible refresh and Collection layout invalidation.

`swift test --package-path SharePackage/ListKit` is expected to fail on macOS because ListKit imports UIKit. iOS verification uses `xcodebuild` with a writable `-derivedDataPath`.
